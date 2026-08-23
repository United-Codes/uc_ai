---
name: uc-ai-structured-output
description: Use when an AI/LLM response must be machine-parseable JSON from Oracle PL/SQL with UC AI — pass p_response_json_schema to uc_ai.generate_text to enforce a JSON Schema (classification with enums, data extraction, confidence scoring), author draft-07 schemas, parse the schema-conforming final_message, or shrink prompt context with uc_ai_toon.to_toon (TOON format).
---

# UC AI Structured Output — Schema-Enforced JSON Responses

Instead of free-form text, structured output guarantees the AI response conforms to a JSON schema you define. Pass the schema as `p_response_json_schema` to any `uc_ai.generate_text` overload; UC AI converts it to each provider's native structured-output format. The response arrives as schema-conforming JSON text in `final_message` — parse it with `json_object_t(...)`.

## One-call usage

```sql
declare
  l_result json_object_t;
  l_schema json_object_t;
  l_output json_object_t;
begin
  l_schema := json_object_t(q'#{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "title": "Simple AI Response",
    "description": "A basic response format for AI tools that return text with a confidence score",
    "properties": {
      "response": {
        "type": "string",
        "description": "The generated response text"
      },
      "confidence": {
        "type": "number",
        "description": "Confidence score between 0 and 1",
        "minimum": 0,
        "maximum": 1
      }
    },
    "required": ["response", "confidence"]
  }#');

  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_result := uc_ai.generate_text(
    p_user_prompt          => 'What is the capital of France? Please respond with a confidence score.'
  , p_system_prompt        => 'You are a helpful assistant that provides accurate information.'
  , p_provider             => uc_ai.c_provider_openai
  , p_model                => uc_ai_openai.c_model_gpt_5_6_luna
  , p_response_json_schema => l_schema
  );

  -- final_message contains the schema-conforming JSON as text — parse it
  l_output := json_object_t(l_result.get_clob('final_message'));

  dbms_output.put_line('Response: '   || l_output.get_string('response'));
  dbms_output.put_line('Confidence: ' || l_output.get_number('confidence'));
  -- Response: The capital of France is Paris.
  -- Confidence: 1
end;
/
```

The same `p_response_json_schema in json_object_t default null` parameter exists on all four `generate_text` overloads (prompt-based, message-array, and both `p_config` variants). Model constants change with releases — check the installed provider package spec.

## Schema authoring rules

UC AI accepts a JSON Schema **draft-07 subset** and translates it per provider.

- **Describe every property.** The model reads `description` — it is your per-field prompt.
- **Constrain hard**: `enum` for categories, `minimum`/`maximum` for numbers, `items` for arrays.
- **Mark `required`** — otherwise the model may omit fields.
- Use a top-level `"type": "object"` with `properties`.

Build and validate schemas interactively: https://www.united-codes.com/products/uc-ai/docs/other/json-schema/#interactive-builder

## Recipes

**Classification** (force one of N labels):

```json
{
  "type": "object",
  "properties": {
    "category": {
      "type": "string",
      "description": "Ticket category",
      "enum": ["bug", "feature", "question", "documentation"]
    }
  },
  "required": ["category"]
}
```

**Extraction** (array of objects):

```json
{
  "type": "object",
  "properties": {
    "people": {
      "type": "array",
      "description": "All persons mentioned in the text",
      "items": {
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "Full name"},
          "role": {"type": "string", "description": "Job role, if stated"}
        },
        "required": ["name", "role"]
      }
    }
  },
  "required": ["people"]
}
```

**Scoring** (bounded number):

```json
{
  "type": "object",
  "properties": {
    "relevance": {
      "type": "number",
      "description": "Relevance score between 0 and 1",
      "minimum": 0,
      "maximum": 1
    }
  },
  "required": ["relevance"]
}
```

## Provider support

Structured output is supported for OpenAI, Anthropic, Google, Ollama, xAI, OpenRouter, and Mistral (the last three route through the OpenAI-compatible implementation). **OCI GenAI does not support it** — passing a schema with `uc_ai.c_provider_oci` raises ORA-20307. Details per provider: https://www.united-codes.com/products/uc-ai/docs/guides/providers/

## Sending tabular data cheaply: TOON

Structured output covers data the LLM must *return*. For data you *send* — e.g. query results as prompt context — use TOON (Token-Oriented Object Notation) via `uc_ai_toon.to_toon` to cut token usage with a CSV-like, lossless JSON encoding:

```sql
l_toon := uc_ai_toon.to_toon(l_json_array);
-- [2]{id,active}:
--   1,true
--   2,false
```

Full format rules, signatures, and an end-to-end example: see `toon.md` in this skill.

## Pitfalls

- **Parse `final_message`.** With a schema, `final_message` is JSON *text*, not prose — wrap it in `json_object_t(l_result.get_clob('final_message'))` before reading fields.
- **OCI raises ORA-20307** when `p_response_json_schema` is passed — pick a supported provider.
- **Invalid responses are rejected and regenerated** by the provider-side schema enforcement, so responses match the schema exactly — but only fields you `require` are guaranteed present.
- **Descriptions are not optional in practice.** A schema without descriptions produces technically valid but semantically wrong output.
- **OpenAI runs in strict mode** (UC AI sets `strict = true`); keep schemas to the draft-07 subset above — exotic keywords may be dropped or rejected in provider translation.
- **Storing schemas with prompts?** Prompt profiles hold a `p_response_schema` alongside the template — see the `uc-ai-prompt-profiles` skill or https://www.united-codes.com/products/uc-ai/docs/guides/prompt-profiles/

## Full documentation

- Structured output guide: https://www.united-codes.com/products/uc-ai/docs/guides/structured_output/
- JSON schema builder: https://www.united-codes.com/products/uc-ai/docs/other/json-schema/
- TOON guide: https://www.united-codes.com/products/uc-ai/docs/guides/toon/
- generate_text API: https://www.united-codes.com/products/uc-ai/docs/api/generate_text/
