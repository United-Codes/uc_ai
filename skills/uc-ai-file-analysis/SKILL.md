---
name: uc-ai-file-analysis
description: Use when sending files (PDFs, images, documents) to an AI model from Oracle PL/SQL with UC AI — multimodal analysis via uc_ai.generate_text with a manually built message array, using uc_ai_message_api.create_file_content (BLOB or base64 CLOB), create_text_content, create_user_message, and create_system_message. Also covers passing files to profile/orchestrator agents via execute_agent's p_files parameter. Covers PDF question-answering and image description with providers like Google Gemini or Anthropic Claude. Also covers OCR — extracting the text, pages, boxes and confidence of a PDF or image without a chat model — with uc_ai.ocr / uc_ai.ocr_text (Mistral, OCI Document Understanding, Ollama vision models).
---

# UC AI File Analysis — Sending PDFs and Images to AI Models

UC AI supports multimodal input: PDFs, images (JPEG, PNG, WebP, …), and other documents depending on the provider. Files are base64-encoded and sent inside a manually built message array — so instead of `p_user_prompt`, you use the `p_messages` overload of `uc_ai.generate_text`.

The flow is always the same: build a content array (file part + text part), wrap it in a user message, optionally prepend a system message, and pass the whole array to `generate_text`.

## Message-builder API

All builders live in `uc_ai_message_api` and return `json_object_t`:

```sql
function create_system_message(
  p_content in clob
) return json_object_t;

function create_text_content(
  p_text in clob,
  p_provider_options in json_object_t default null
) return json_object_t;

-- file content from a BLOB (UC AI base64-encodes it for you)
function create_file_content(
  p_media_type in varchar2,
  p_data_blob in blob,
  p_filename in varchar2 default null,
  p_provider_options in json_object_t default null
) return json_object_t;

-- alternative overload if you already have base64 text
function create_file_content(
  p_media_type in varchar2,
  p_data_base64 in clob,
  p_filename in varchar2 default null,
  p_provider_options in json_object_t default null
) return json_object_t;

-- wraps a content array (file + text parts) into a user message
function create_user_message(
  p_content in json_array_t
) return json_object_t;

-- text-only shortcut (no files) — handy for follow-up questions
function create_simple_user_message(
  p_text in clob
) return json_object_t;

-- text + files in one call (builds the content array for you)
function create_user_message(
  p_text  in clob,
  p_files in t_files
) return json_object_t;
```

## Example 1: Analyze a PDF

Ask a question about a PDF stored as a BLOB in a table (here: a PDF with a character table from a TV show):

```sql
declare
  l_messages      json_array_t := json_array_t();
  l_content       json_array_t := json_array_t();
  l_result        json_object_t;
  l_final_message clob;
begin
  -- API key: uc_ai_get_key function or uc_ai_google.g_apex_web_credential := 'GOOGLE';

  -- system message sets the context
  l_messages.append(uc_ai_message_api.create_system_message(
    'You are an assistant answering trivia questions about TV Shows. Please answer in super short sentences.'));

  -- the user message has two parts: the file and the text question

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf',
    p_data_blob  => (select blob_content from your_table where id = 1),
    p_filename   => 'characters.pdf'
  ));

  l_content.append(uc_ai_message_api.create_text_content(
    'What is the TV show called of the characters that are inside the attached PDF?'
  ));

  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_google
  , p_model    => uc_ai_google.c_model_gemini_3_7_flash
  );

  l_final_message := l_result.get_clob('final_message');
  dbms_output.put_line('Answer: ' || l_final_message);
  -- > "The Office" or similar
end;
/
```

## Example 2: Analyze an image

Same pattern, different mime type and provider:

```sql
declare
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
begin
  -- API key: uc_ai_get_key function or uc_ai_anthropic.g_apex_web_credential := 'ANTHROPIC';

  l_messages.append(uc_ai_message_api.create_system_message(
    'You are an image analysis assistant.'));

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'image/webp',
    p_data_blob  => (select image_blob from product_images where id = 42),
    p_filename   => 'product.webp'
  ));
  l_content.append(uc_ai_message_api.create_text_content(
    'What is the fruit depicted in the attached image?'
  ));
  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_anthropic
  , p_model    => uc_ai_anthropic.c_model_claude_4_5_haiku
  );

  dbms_output.put_line('Answer: ' || l_result.get_clob('final_message'));
end;
/
```

Always use the package model constants, never string literals — model constants change with releases, so check the installed provider spec for the current list. If you set any `g_*` globals for the call (credentials, tools, …), remember they are session-scoped; call `uc_ai.reset_globals;` first so earlier session state does not leak in. For the basics of `generate_text` and API key setup, see the `uc-ai-quickstart` skill or https://www.united-codes.com/products/uc-ai/docs/api/generate_text/.

## Extract text with OCR (no chat model)

When the goal is the text or structure of a document (ingestion, search, storage) and not an answer about it, use `uc_ai.ocr` or `uc_ai.ocr_text`. OCR does not go through `generate_text`, and the OCR models (for example `mistral-ocr-latest`) do not work there.

```sql
declare
  l_result json_object_t;
  l_text   clob;
begin
  -- API key: uc_ai_get_key function or uc_ai_mistral.g_apex_web_credential := 'MISTRAL';

  l_result := uc_ai.ocr(
    p_document   => (select blob_content from your_table where id = 1),
    p_media_type => 'application/pdf',
    p_provider   => uc_ai.c_provider_mistral   -- or c_provider_oci, c_provider_ollama
  );

  l_text := l_result.get_clob('markdown');                        -- all pages, joined with a blank line
  dbms_output.put_line(l_result.get_object('usage').stringify);   -- e.g. {"pages":1,"bytes":34116}

  -- only the text:
  l_text := uc_ai.ocr_text(
    p_document   => (select blob_content from your_table where id = 1),
    p_media_type => 'application/pdf',
    p_provider   => uc_ai.c_provider_mistral
  );
end;
/
```

The result object holds `markdown`, `pages` (each with `index` starting at 0, `markdown` and, where the provider gives them, `blocks` with normalized `box` values, `dimensions` and `confidence`), `usage` (only keys the provider reports: `pages`, `bytes`, `input_tokens`, `output_tokens`), `model`, `warnings` and `raw` (the provider response). Test optional keys with `has`.

| Provider | Accepts | Notes |
|----------|---------|-------|
| `c_provider_mistral` | PDF, PNG, JPEG, WebP, AVIF, and a URL overload (`p_url`) | Default model `uc_ai_mistral.c_model_mistral_ocr`. Options such as `pages`, `table_format`, `confidence_scores_granularity` pass through. |
| `c_provider_oci` | PDF, PNG, JPEG, TIFF | Needs `uc_ai_oci.g_compartment_id` and the web credential. UC AI builds the Markdown from lines and tables. Synchronous calls: 8 MB and 5 pages at most. Option `tables => true` adds table extraction. |
| `c_provider_ollama` | PNG, JPEG, WebP (no PDF) | `p_model` is required and must be a vision model. Use an image with an opaque background. No boxes and no confidence, so review the result. |

Use the neutral options in `p_options` (a `json_object_t`): `pages` (0-based indexes) and `tables` (boolean). UC AI passes other keys on to the provider; use the key `extra_body` to add fields to the request body. `uc_ai.g_base_url` overrides the endpoint.

An unsupported media type raises `ORA-20508` before any request. A provider error raises `ORA-20302`. A provider without OCR support raises `ORA-20306`. `warnings` holds non-fatal problems, for example OCI reporting that a page has no text.

## Sending files to an agent

Profile and orchestrator agents accept files directly via `p_files` on `uc_ai_agents_api.execute_agent` — no manual message array needed. Build a `uc_ai_message_api.t_files` collection and the files are attached to the agent's user message (works on the initial call and on `p_follow_up_message`):

```sql
declare
  l_result json_object_t;
  l_files  uc_ai_message_api.t_files := uc_ai_message_api.t_files();
begin
  l_files.extend;
  l_files(1).media_type := 'application/pdf';
  l_files(1).data_blob  := (select blob_content from your_table where id = 1);
  l_files(1).filename   := 'characters.pdf';

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'trivia_agent',
    p_input_parameters => json_object_t('{"question": "What TV show are these characters from?"}'),
    p_files            => l_files
  );

  dbms_output.put_line(l_result.get_clob('final_message'));
end;
/
```

Passing `p_files` to a workflow or handoff agent raises an error — only profile and orchestrator agents build a user message.

## Pitfalls

- **`p_media_type` must be the correct mime type** (`application/pdf`, `image/png`, `image/jpeg`, `image/webp`, …). A wrong mime type causes provider-side rejections or misinterpretation.
- **The model must be multimodal.** Text-only models reject or ignore file content. Vision/file support varies per model — check the provider pages: https://www.united-codes.com/products/uc-ai/docs/guides/providers/
- **Mistral takes PDFs in chat as `document_url` parts.** UC AI builds this for you: use the normal `application/pdf` file content with `p_provider => uc_ai.c_provider_mistral`.
- **Provider file-type support differs.** Some providers accept PDFs and other documents, others only images — what works depends on the AI provider's capabilities. Test with your target provider.
- **Large files consume many input tokens.** A multi-page PDF or high-resolution image can dominate your token usage (and cost). Check `l_result.get_object('usage')` and downscale/trim files where possible.
- **Use the BLOB overload of `create_file_content` when you have binary data** — UC AI handles the base64 encoding. Only use the `p_data_base64` CLOB overload if the data is already base64-encoded.

## Full documentation

- File analysis guide: https://www.united-codes.com/products/uc-ai/docs/guides/file_analysis/
- OCR API: https://www.united-codes.com/products/uc-ai/docs/api/ocr/
- generate_text API: https://www.united-codes.com/products/uc-ai/docs/api/generate_text/
- Providers: https://www.united-codes.com/products/uc-ai/docs/guides/providers/
