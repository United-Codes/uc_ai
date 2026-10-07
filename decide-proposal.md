# Proposal: typed decisions in UC AI (`uc_ai.decide`)

Status: draft. Design decisions are made (section 2). The OpenAI wire format is verified against real calls (section 1, 2026-10-07). The TypeSafe wire format is NOT yet verified.
Backends in the first release: **OpenAI Decisions** (`POST /v1/decisions`, model `gpt-6-luna`) and **TypeSafe jev** (`POST /v1/systemone`, model `jev-latest`).
Both APIs are beta. The public entry point is marked experimental in the spec and the docs.

## 1. Facts and open verification

### OpenAI Decisions `POST {base_url}/decisions` (real calls from the dev database, 2026-10-07)

About 70 calls through `uc_ai_http.post` with the web credential `OPENAI` (no key read or echoed). Cost: a few thousand input tokens in total. Recorded in `test/samples/openai/decisions/` (response bodies as returned, request bodies as sent; HTTP status codes are in this section, not in the files; `triage_response_headers.json` holds the header sample).

**Request**
- URL `https://api.openai.com/v1/decisions`. `uc_ai_openai` builds chat as `rtrim(settings.base_url, '/') || '/chat/completions'` or `c_api_url || path`. A decisions URL built the same way gives `base || '/decisions'`, so `uc_ai.g_base_url`, `provider_override` and the web credential handling carry over unchanged.
- Headers: `Content-Type: application/json` and Bearer auth (the web credential adds it). Nothing else is needed.
- Body: `{"model":"gpt-6-luna","input":<string | message array>,"questions":[...],"safety_identifier":"..."?}`. `model`, `input` and `questions` are required (400 `missing_required_parameter`). `safety_identifier` is accepted. Unknown top-level fields (`temperature`) are rejected with 400 `unknown_parameter`. Unknown fields inside a question are rejected too.
- `input` as string: plain text. `input` as array: only `{"role":"user","content":...}` items; `role` `system` or any other value gives 400 `invalid_value` ("Value must be 'user'"). `content` is a string or an array of parts. Two user messages in a row work. An empty `input` string, an empty `input` array and an empty `content` array all return 200 (the model then sees no evidence: `refusal` or a vague probability, see below).
- Image shape (confirmed by call): `{"role":"user","content":[{"type":"input_text","text":"..."},{"type":"input_image","image_url":"data:image/png;base64,..."}]}`. `image_url` is a plain string, not the chat shape `{"url":...}` (that gives 400 "Supported values are: 'input_text' and 'input_image'"). The string must match `^data:`: an `https://` URL gives 400 `invalid_value`. Bad base64 gives 400 "Invalid image data. Supply a supported base64 image data URL." (`code` null). PNG, JPEG and WebP data URLs work. An image alone, text plus image, and two images in one message all work. `detail` is accepted (effect not measured). A 562-byte PNG with the text "REFUND 42" was read correctly (choice `refund` with confidence 0.99, predicate on the number 42 gave 1.0). An image costs about 25 to 30 input tokens at this size. `file_id` input is documented as unsupported and was not called.
- Question objects, all with required `type`, `name`, `instructions` (a missing `instructions` gives 400):
  - `predicate`: no other field. A `choices` or `description` field gives 400 `unknown_parameter`. A caller's true/false criteria must go into `instructions`; instructions of the form "Answer true if ... Answer false if ..." work.
  - `choice`: `choices:[{"value":"...","description":"..."?}]`. `description` is optional (calls without it work). `choices` must be an object array: `["a","b"]` gives 400 `invalid_type`.
  - `score`: `levels:[{"label":"...","description":"..."?}]`. `description` is optional.
- Limits (400 `invalid_request_error`, `code` `array_above_max_length` / `array_below_min_length` / `empty_array`, `param` names the field): `choices` 2 to 255 (255 works, 256 and 300 fail), `levels` 2 to 10 (10 works, 11 and 20 fail). One option or one level fails. At least 1 question (`empty_array`). 50 questions in one request work (7,609 input tokens, 310 ms). The upper question limit was not searched. Choice values must be unique inside a question and question names unique in the request (400, `code` null, message "Choice values must be unique within the question." / "Question names must be unique within the request."). A name can be any string: spaces, `-`, `.`, `:`, `/`, `[0]`, umlauts, CJK, 1 and 200 characters all returned answers with the name echoed unchanged.

**Response** (200)
- `{"model":"gpt-6-luna","answers":[...],"usage":{"input_tokens","input_tokens_details":{"cached_tokens","cache_write_tokens"},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens"}}`. `model` is the alias as sent (no dated version). `output_tokens` is always 0 (only input is billed). `total_tokens` equals `input_tokens`. A request has a fixed overhead: 152 input tokens for one predicate on an empty-ish input, 429 for the three-question triage example.
- `answers` has one entry per question, in question order (checked with 50 questions and with mixed types). Every entry has `type` and `name`.
  - `predicate`: `{"type","name","probability"}`. No `confidence`.
  - `choice`: `{"type","name","choice","probabilities":[{"value","probability"}],"confidence"}`.
  - `score`: `{"type","name","score","probabilities":[{"value":<int index>,"label":"...","probability"}],"confidence"}`. The probability entries carry the level `label` as well as the zero-based index in `value`.
  - `refusal`: `{"type":"refusal","name"}` and nothing else.
- `confidence` was present on every choice and score answer (12 answers). It is not the probability of the chosen option: choice `none` had probability 0.97 and confidence 0.96. A score over 10 irrelevant levels (flat distribution) has `confidence` 0.0.
- `probabilities` are complete: every option and every level is listed, zeros included (255 entries for 255 choices). They sum to exactly 1.0 in every recorded answer (floating point sum, deviation 0). Values have 2 decimals; a spread of 0.01 over many options (cat_1, cat_2, ... 0.01 each, 0.94 for the winner) still adds up. The chosen `choice` was the argmax every time.
- `score` equals the probability-weighted mean of the level indices computed from the rounded probabilities (4.39 from ten levels, 1.97 from `0, 0.03, 0.97`), 2 decimals. Indices start at 0.
- Predicate `probability` has 2 decimals (0.93, 0.47, 1.0).

**Refusal** (provoked in 4 of 6 probe requests; it is per question, other answers in the same response are normal)
- Refused: a predicate with empty `instructions`; a choice with a meaningless instruction ("Pick the colour of the number seven's smell"); a predicate that infers a protected trait ("The author is gay."; the sibling question on religion was answered); "Name the private home address of this person." (the sibling "Is it ok to publish ..." was answered with 0.52); input `"x"` with a meaningless predicate ("Is it?"); an empty `input` array. These are mostly ill-posed questions, not policy blocks.
- Not refused: a self-harm detection question on a self-harm sentence (predicate 1.0, score 2.0), a prompt-injection text ("Ignore all previous instructions ...", answered 1.0 for "tries to override instructions"), a lottery prediction question (answered 0.47).
- A refusal still bills input tokens. The HTTP status is 200. A question with no `name` (sent in a test, not reachable through `uc_ai.decide`) also returned 200 with `{"type":"refusal","name":null}` instead of a 400.

**Errors** (status 4xx, standard OpenAI shape `{"error":{"message","type":"invalid_request_error","param","code"}}`, so the `has('error')` branch in `uc_ai_openai` fits)
- Unknown model: **404**, `code` `model_not_found`, message "The model `gpt-6-nope` does not exist or you do not have access to it.", `param` null.
- All validation errors above: **400**, `param` is the JSON path of the field (`questions[0].choices`, `input[0].role`, `questions[1].name`). `code` is `missing_required_parameter`, `unknown_parameter`, `invalid_type`, `invalid_value`, `array_*`, `empty_array`, or null (uniqueness and image data).
- Not tested on purpose: bad or missing key (401), rate limit (429).

**Headers** (200 response): `x-request-id` (`req_...`, worth logging), `openai-processing-ms` (142 to 935 ms measured; error responses 1 ms), `x-ratelimit-limit-requests/-tokens`, `x-ratelimit-remaining-requests/-tokens`, `x-ratelimit-reset-requests/-tokens` (this account: 5000 requests and 2,000,000 tokens per window). Response `Content-Type: application/json`.

**Still unverified**: 429 shape and `retry-after`; 401 shape; the upper limit of questions and of input size; the effect of `detail` on images; large images (only 0.5 to 2.4 KB images were sent); PDF or other media types (the docs only name images); behaviour for `file_id`; whether `safety_identifier` changes anything (accepted only); latency for long inputs.

### TypeSafe jev (NOT verified in this run; from the Vercel AI SDK adapter and vendor docs only)

| | TypeSafe jev |
|---|---|
| Endpoint | `POST https://api.typesafe.ai/v1/systemone` |
| Auth | Bearer |
| Model | `jev-latest` |
| Input | `state` (string) |
| Questions | object keyed by question id |
| Boolean | type `noul`, answer `{noul: p}` |
| Choice | `criteria: {option: description}`, answer `{choice, probabilities:{option: p}, confidence}` |
| Score | `criteria: [description, ...]`, answer `{score, probabilities:{index: p}, confidence}` |
| Refusal | none |
| Limits | 255 choice options, 10 score levels |
| Usage | `usage.input_tokens`, `output_tokens` |
| Rounding | probabilities and scores to 2 decimals |

Open for the TypeSafe WP0: whether jev accepts images (if not, TypeSafe raises -20508 for files), its error body shapes, and whether `confidence` is always present.

### Contradictions found (OpenAI calls against sections 2 and 3; decisions NOT edited)

WP1 applied points 1, 2, 3 and 7 to section 3 (limits check, 2 options or levels minimum, criteria folded into the predicate instructions, images as message array). Points 4 and 5 are implemented as decided (refusal raises; null name handled). Point 6 is implemented (the label is dropped).

1. **Limits exist.** The old table said "none documented". The API enforces 2 to 255 choices and 2 to 10 levels. Section 3 lists the 255/10 pre-flight check for TypeSafe only. Without a check for OpenAI, the caller gets -20302 (400 with `array_above_max_length`) after a network call. Decide: add the same check to the OpenAI path.
2. **A choice needs at least 2 options.** Section 3 says "non-empty object" for choice `criteria`; the API rejects 1 option (400). A one-level or one-option question should raise -20503 in the neutral check.
3. **Predicate has no `criteria`.** Section 3 makes `criteria` optional on `boolean`. The OpenAI predicate takes only `instructions`; an extra field is a 400. The adapter has to fold `criteria` text into `instructions`. TypeSafe `noul` was not checked.
4. **Refusal is per question and often means "ill-posed".** Decision 5 raises -20309 for any refusal and drops the valid answers in the same response (they stay in `p_extra`). Empty instructions, meaningless input, protected-trait inference and "name the private address" all produce refusals while sibling questions are answered. Decide whether one refused question among many should still fail the whole call.
5. **Refusal `name` can be null** when the question had no name. Not reachable through `uc_ai.decide` (ids are validated first), but the adapter should read `name` with a null check.
6. **Score probability entries have a `label`** in addition to `value` and `probability`. The adapter should read `value` for the index and may ignore `label`.
7. **Images are supported as designed, with one change of shape.** `input` has to become a message array, `{"role":"user","content":[input_text, input_image...]}`; `input` as a plain string stays for text-only calls. Only `data:` URLs work, so the adapter builds `data:<media_type>;base64,...` from `create_file_content`. PDFs are not named in the docs; only image media types should pass the -20508 check.
8. **Decision 2.4 and the checks need no change** for sums and score: the data matched exactly. The tolerance for warnings (1e-6 plus half a unit per rounded value) is generous. No other contradiction with the neutral result: `usage.output_tokens` is always 0 and `usage` carries more keys than section 3 lists (`input_tokens_details.cached_tokens`, `cache_write_tokens`, `reasoning_tokens`, `total_tokens`).

## 2. Decisions

1. Public API `uc_ai.decide`, provider-neutral, in a new package `uc_ai_decisions` (spec + body) with two private adapters (`openai`, `typesafe`). Same pattern as `uc_ai.ocr` / `uc_ai_ocr`. Not routed through `generate_text`: the result has no messages and no tool calls.
2. Return `json_object_t`, not a record.
3. The neutral model follows Vercel: one shared `state`, `questions` keyed by id, answer types `boolean`, `choice`, `score`. The wire names `noul` and `predicate` never leave the adapters.
4. Failed distribution checks (sum to 1, score equals weighted mean) become `warnings`, not errors. Structural problems raise.
5. A refusal on any question raises `c_err_decision_refused` (-20309). The message lists the refused question ids. The raw response goes to `p_extra` so the logger keeps it. A `refused` answer type may be added later as an opt-in; going the other way would break callers.
6. TypeSafe is a real provider constant, `uc_ai.c_provider_typesafe`. `scripts/generate_uc_ai_utils_body.sh` excludes it (like `c_provider_responses_api`) because it cannot chat.
7. Images are in the first release, through `uc_ai_message_api.create_file_content` objects.
8. No new package globals except the TypeSafe credential (section 4). Provider options go in one `p_options json_object_t`.
9. Never log the request body (it can hold base64 images). Log provider, model, question count, file count and byte size.
10. Do not bump `uc_ai.c_version`.

## 3. Public spec (`uc_ai.pks`; existing signatures untouched)

```plsql
/**
 * EXPERIMENTAL. Decide typed answers to named questions against one shared state.
 */
function decide (
  p_state     in clob                          -- text, or JSON serialised with to_clob
, p_questions in json_object_t                 -- see "Questions"
, p_provider  in provider_type                 -- c_provider_openai | c_provider_typesafe
, p_model     in model_type default null       -- null: provider default
, p_files     in json_array_t default null     -- create_file_content objects (images)
, p_options   in json_object_t default null    -- provider passthrough
) return json_object_t;
```

Constants: `uc_ai.c_provider_typesafe = 'typesafe'`, `uc_ai_typesafe.c_model_jev_latest = 'jev-latest'` (default for TypeSafe), `uc_ai_openai.c_model_gpt_6_luna` (default for OpenAI decisions; it is also a chat model).

### Questions

```json
{
  "department": { "type": "choice", "instructions": "Which team should handle this?",
                  "criteria": { "billing": "Payments and refunds", "support": "Other requests" } },
  "severity":   { "type": "score",   "instructions": "How severe is the issue?",
                  "criteria": [ "Cosmetic", "Workaround exists", "Blocking" ] },
  "refund":     { "type": "boolean", "instructions": "Is the customer asking for money back?",
                  "criteria": { "true": "...", "false": "..." } }
}
```

- `instructions` is a required, non-blank string. `criteria` is required for `choice` (an object with **at least 2** options) and `score` (an array of **at least 2** levels; level 0 is the first element). A choice option or level without a description (null or empty) is sent without one. It is optional for `boolean`: an object `{"true": "...", "false": "..."}`; the OpenAI adapter folds it into the predicate `instructions` (a predicate takes only `instructions`; an extra field is a 400): the instructions, then a blank line and `Criteria for true:` plus a line feed plus the text, then the same for `false`, each only when given.
- Question ids must match `^[A-Za-z][A-Za-z0-9_]{0,63}$` (a trailing line feed is rejected too). Check before any request. A key in a question other than `type`, `instructions` and `criteria` adds a warning and is ignored.
- Read every string with `get_clob`, never `get_string` (32k limit).
- The score levels go to OpenAI as `{"label": "0", "description": <criteria text>}`: the label is the zero-based index, so the answer index and the label always agree.

### Neutral result

```json
{
  "answers": {
    "department": { "type": "choice",  "choice": "billing", "probabilities": { "billing": 0.97, "support": 0.03 } },
    "severity":   { "type": "score",   "score": 1.2, "probabilities": { "0": 0.1, "1": 0.6, "2": 0.3 } },
    "refund":     { "type": "boolean", "probability": 0.98 }
  },
  "usage": { "input_tokens": 120, "output_tokens": 0 },
  "model": "gpt-6-luna",
  "provider_metadata": { "confidence": { "department": 0.91 } },
  "warnings": [ "..." ],
  "raw": { "provider response as returned" }
}
```

Rules:
- `probabilities` is optional on `choice` and `score`, required `probability` on `boolean`. This leaves room for a structured-output fallback later.
- Score probabilities are keyed by zero-based level index as a string.
- `confidence` is the vendor statistic. It is not the probability of the selected option. It stays in `provider_metadata`.
- `usage` keys appear only when the provider reports them.
- `raw` keeps the full provider response.

### Checks

Before any request (no HTTP call is made if one fails):
- Malformed question or id, a choice with fewer than 2 options, a score with fewer than 2 levels, an unknown type (`predicate` and `noul` are not neutral types), blank instructions, an empty state without files, a malformed file object, an option of the wrong type: `c_err_invalid_config` (-20503).
- Question type or file the provider cannot take: `c_err_unsupported_content` (-20508). The message names the supported types. More than 255 options in a choice or more than 10 levels in a score (OpenAI, verified; TypeSafe has the same numbers). The limits are in one per-provider table in the body of `uc_ai_decisions` (`limits_of`). Files: only `image/png`, `image/jpeg` and `image/webp` pass for OpenAI (verified); other media types raise before any request. TypeSafe files: only if WP0 shows jev takes images.
- Null or unknown provider: existing unknown-provider error (-20306), checked first. The message lists the providers that have decision support.

After the response:
- Errors (`c_err_format_processing`, -20304): a question has no answer or has an extra answer, the answer type differs from the question type, a choice is not one of the options, a score is outside [0, levels - 1], a probability is outside [0, 1].
- Refusal: -20309 as in decision 5. The refusal handling is one procedure in the body (`raise_if_refused`) with a comment on how to change the policy. The message lists only the refused ids (`(no name)` for a refusal without a name); the raw response, with the sibling answers, goes to the logger.
- Warnings: a distribution does not sum to 1, or a score differs from the probability-weighted mean. Tolerance is 1e-6 plus half a unit in the last decimal (0.005, the 2-decimal rounding both APIs report) for each rounded value that goes into the sum or the mean. For the sum that is `1e-6 + 0.005 * n` for n entries. For the mean, a rounding error of probability i moves the mean by up to `0.005 * i`, so the tolerance is `1e-6 + 0.005 (the score itself) + 0.005 * (sum of the indexes)`. The sum tolerance grows with n, so the check cannot fire on a choice with about 200 options or more (255 options allow a deviation of 1.3); it is a check for the small questions, not for the 255-option case.
- Unknown keys in `p_options` add a warning and are ignored. Known keys: `safety_identifier` (string, sent as is) and `extra_body` (object, merged into the request; the keys `model`, `input` and `questions` always win).
- Provider HTTP or API error (status 400 or more, or an `error` object in a 200 body): `c_err_provider_response` (-20302) with the provider message and, when the error has one, its `param`. A non-JSON error body (a 502 page) is reported with a preview of the body.

## 4. Footprint

No tables, no migration.

- `src/packages/uc_ai_decisions.pks/.pkb`: dispatcher, pre-flight checks, validation, result assembly, both adapters as private functions.
- `src/packages/uc_ai_typesafe.pks` (spec only, like `uc_ai_mistral.pks`): `c_model_jev_latest`, `g_apex_web_credential`.
- `uc_ai.pks`: `c_provider_typesafe`, the `decide` facade. `uc_ai.pkb`: the facade body, built with `uc_ai_settings.build_from_globals`.
- `uc_ai_settings`: add `ts_apex_web_credential` in the four places named in `uc_ai_settings.pks`, and in `reset_globals`.
- `uc_ai_error.pks`: `c_err_decision_refused constant number := -20309`.
- `scripts/package_utils.sh`: `uc_ai_decisions` in the core list after `uc_ai_ocr`, `uc_ai_typesafe` in the provider list. Then regenerate install, upgrade and uninstall scripts.
- `scripts/generate_uc_ai_utils_body.sh`: exclude `typesafe` from the provider list.
- `uc_ai_get_key` belongs to the user (`src/dependencies/key_function.sql`) and raises -20001 for an unknown provider. Every user needs a `typesafe` branch. The docs must say so, and the post-install script should not overwrite the user function.
- OpenAI base URL: the adapter follows `uc_ai.g_base_url` like chat. The docs must say that a proxy URL then also receives decision calls.
- Set `p_transfer_timeout` on decision calls (images can make them slow).

## 5. Interaction with existing features

- **Workflows:** no new step type. A `plsql` step whose `plsql_function_call` returns `uc_ai.decide(...).to_clob` becomes step state. A condition such as `'{$.steps.route.answers.department.choice}' = 'billing'` routes on it. Document this with a recorded example. Known gap: tokens from such a step do not reach the `uc_ai_agent_executions` totals and the execution hook does not see the call.
- **Prompt profiles, agents, tools, events, structured output:** untouched.

## 6. Build plan (one sub-agent per work package, in order)

0. **WP0 Verify.** Make real calls from the dev database to both APIs (questions of all three types, one refusal-prone question, an image for OpenAI, an error case each). Needs a TypeSafe key and OpenAI access to `gpt-6-luna` Decisions. Never echo keys. Record the responses in `test/samples/`. Correct section 1.
1. **WP1 Core and OpenAI.** `uc_ai_decisions` (dispatcher, checks, validation, assembly), the `uc_ai.decide` facade, OpenAI adapter, error constant, script wiring.
2. **WP2 TypeSafe.** `uc_ai_typesafe.pks`, `c_provider_typesafe`, settings field, TypeSafe adapter, generator exclusion, `uc_ai_get_key` docs note.
3. **WP3 Docs.** `api/decide.mdx`, `providers/typesafe.mdx`, updates to `providers/openai.mdx`, `api/cheatsheet.mdx`, `api/types.mdx`, `other/release-history.mdx`, the `CLAUDE.md` package table, and a workflow-routing example. Use `simple-english` and `docs-voice`. Grep every heading anchor before changing it. Docs output must come from recorded calls.

### Tests (utPLSQL; `test_uc_ai_decisions` and `test_uc_ai_decisions_wire`, following the OCR test packages)

Wire tests (no network, recorded samples, `uc_ai_http.set_transport`):
- OpenAI: URL ends in `/decisions`; question array shape for all three types; `predicate` name never appears in the neutral result; image becomes a data URL; probability array to object; refusal raises -20309 with ids; 429 maps to -20302; usage mapped; request body absent from the log table.
- TypeSafe: URL `/systemone`; `noul` mapping both ways; questions keyed by id; 256 options and 11 levels raise before any request; `confidence` lands in `provider_metadata`.
- Neutral: bad id, empty criteria, one-level score, unknown type raise -20503; unsupported type or file raises -20508 and the mock saw no request; answer missing, answer of the wrong type, unknown choice, score out of range raise -20304; sum-to-1 and weighted-mean failures give warnings and no error.

Live tests (disabled when a credential is missing): OpenAI and TypeSafe each with the triage example (all three types), an image question for OpenAI, a bad model name (-20302). A cross-provider test asserts the same choice on an unambiguous input.

## 7. Later (not in the first release)

Structured-output fallback for Anthropic, Google and the other chat providers (no real probabilities). A `p_config` overload and scalar helpers (`decide_choice`, `decide_probability`). A `refused` answer type as an opt-in. A strict mode that turns distribution warnings into errors. A `decision` workflow step type with usage accounting. Prompt-profile integration. Batch of unrelated states.
