# Update Provider Models

Updates model constants across all AI provider packages and regenerates the `uc_ai_utils` package body.

## Trigger

When asked to update, add, or sync AI provider models/constants.

## Architecture

Models are defined in exactly **one place**: as `c_model_*` constants in each provider's package spec (`.pks` file). The `uc_ai_utils.pkb` body is auto-generated from these constants — never edit it manually.

### Key files

| File | Purpose |
|------|---------|
| `src/packages/uc_ai.pks` | Provider constants (`c_provider_*`) |
| `src/packages/uc_ai_openai.pks` | OpenAI model constants |
| `src/packages/uc_ai_anthropic.pks` | Anthropic model constants |
| `src/packages/uc_ai_google.pks` | Google Gemini model constants |
| `src/packages/uc_ai_oci.pks` | OCI GenAI model constants |
| `src/packages/uc_ai_xai.pks` | xAI Grok model constants |
| `src/packages/uc_ai_mistral.pks` | Mistral model constants (`-latest` aliases) |
| `src/packages/uc_ai_ollama.pks` | Ollama (no hardcoded models — dynamic) |
| `src/packages/uc_ai_openrouter.pks` | OpenRouter (no hardcoded models — dynamic) |
| `src/packages/uc_ai_utils.pks` | Package spec with pipelined function signatures and record types |
| `src/packages/uc_ai_utils.pkb` | **Auto-generated** — do NOT edit manually |
| `scripts/generate_uc_ai_utils_body.sh` | Bash script that generates `uc_ai_utils.pkb` |

### Documentation URLs for each provider

- OpenAI: https://developers.openai.com/api/docs/models and https://developers.openai.com/api/docs/pricing
- Anthropic: https://platform.claude.com/docs/en/about-claude/models/overview and https://platform.claude.com/docs/en/about-claude/model-deprecations
- Google: https://ai.google.dev/gemini-api/docs/models
- xAI: https://docs.x.ai/docs/models
- Mistral: https://docs.mistral.ai/models
- OCI: https://docs.oracle.com/en-us/iaas/Content/generative-ai/pretrained-models.htm

Provider doc URLs move often. If a fetch returns a redirect, follow it and update
the URL in this list and in the `.pks` header comment.

### Cross-check source: models.dev

https://models.dev aggregates the model ids of all providers, and it keeps the
`-latest` aliases that some provider pages no longer print. Use it when:

- A provider page gives a display name but no API id (OCI does this).
- A provider page prints only versioned ids and you need to know if an alias is still valid (Mistral does this).
- Two pages of the same provider disagree on an id.

Per-provider pages have the form `https://models.dev/labs/<provider>/`, for
example `https://models.dev/labs/mistral/`. Treat it as a second opinion, not as
the primary source. The provider page wins when both are clear.

Do not invent an id. If the provider page and models.dev do not agree, leave the
constant out and report the conflict.

## Steps

### 1. Look up current models from provider docs

Fetch each provider's documentation page to get the current list of model IDs. Compare against existing `c_model_*` constants in the corresponding `.pks` file.

### 2. Add missing constants to provider specs

Add new `c_model_*` constants to the appropriate provider `.pks` file. Follow existing naming conventions:

```sql
-- Pattern: c_model_<name> constant uc_ai.model_type := '<api-model-id>';
c_model_gpt_5_4 constant uc_ai.model_type := 'gpt-5.4';
```

- Constants for embedding models must contain `embed` in the name (the generator uses this to set `model_type`).
- Order: newest models first within each provider file.
- Keep deprecated/legacy models — users may still reference them.
- Never write a `c_model_*` name inside a comment in a `.pks` file. The generator
  greps the raw file, so a name in a comment becomes a duplicate row in
  `uc_ai_utils.pkb`.
- Group the retired models at the end of the list, under a comment that says the
  provider retired them and that the constants stay for backward compatibility.
- If a preview model reaches GA and the preview id is shut down, change the value
  of the existing constant to the GA id. Example: `gemini-3.1-flash-lite-preview`
  becomes `gemini-3.1-flash-lite`.

### 3. If adding a new provider

1. Add `c_provider_<name>` constant to `src/packages/uc_ai.pks`
2. Add a display name case to `provider_display_name()` in `scripts/generate_uc_ai_utils_body.sh`
3. The generator will auto-discover the new provider and its models

### 4. Regenerate the utils body

```bash
bash scripts/generate_uc_ai_utils_body.sh
```

This reads all `c_provider_*` from `uc_ai.pks` and all `c_model_*` from each provider spec, then generates `src/packages/uc_ai_utils.pkb` with pipelined `pipe row` calls.

### 5. Compile and test

```bash
echo "@@src/packages/uc_ai_<provider>.pks
@@src/packages/uc_ai_utils.pkb
show errors package uc_ai_<provider>;
show errors package body uc_ai_utils;" | sql -name local-23ai-uc_ai
```

Then verify:

```sql
select provider, model_type, count(*) as cnt
  from table(uc_ai_utils.get_models)
 group by provider, model_type
 order by provider, model_type;
```

### 6. Regenerate install script

```bash
bash scripts/generate_install_script.sh
```

### 7. Update the documentation

The docs must name and use only current models. An old id can already be retired,
and a copied example then fails for the reader.

1. `docs/src/content/docs/providers/<provider>.mdx` — the `Models` section lists
   the constants. List the current models. Then add a `Retired Models` section
   that names the retired families and says that the constants stay for backward
   compatibility.
2. Replace retired constants in every example, in the guides and in the API pages.
   `grep -rn "c_model_" docs/src/content/docs` shows all of them.
3. `docs/src/content/docs/index.mdx` — the `Supported AI Providers` list names
   models in prose.
4. `docs/src/content/docs/other/glossary.mdx` and
   `docs/src/content/docs/api/generate_text.mdx` name model ids in prose and in
   sample JSON.
5. Leave `docs/src/content/docs/other/release-history.mdx` alone. It is a record
   of past releases. Only correct a link whose anchor you renamed.
6. Never change heading text that another page links to. `grep -rnoE "#[a-z0-9-]+\)" docs`
   shows the anchors in use. `starlightLinksValidator` fails the build on a broken
   anchor.
7. Invoke the `simple-english` skill before you write documentation prose.
8. Verify with `cd docs && bun run build`. The build validates all internal links.

Cross-check that every constant in the docs exists:

```bash
grep -ohE "c_model_[a-z0-9_]+" src/packages/*.pks | sort -u > /tmp/have.txt
grep -rohE "c_model_[a-z0-9_]+" docs/src/content/docs skills | sort -u > /tmp/want.txt
comm -13 /tmp/have.txt /tmp/want.txt   # must be empty
```

### 8. Check the consumer skills

The top-level `skills/` directory (Claude Code skills for library consumers) uses model constants in examples and tables. If a constant used there was deprecated or a notable new default model exists, update the affected skills — `grep -rn "c_model_" skills/` shows what they reference. The provider table in `skills/uc-ai-quickstart/SKILL.md` lists example constants per provider.

## Important notes

- `uc_ai_utils.pkb` is compiled as an API package body (after all provider specs), so it can reference any provider's constants.
- Ollama and OpenRouter have no hardcoded models — they support dynamic model selection. The generator skips providers with 0 `c_model_*` constants.
- The `model_type` field is auto-detected: constants containing `embed` in the name → `embedding`, everything else → `chat`.
