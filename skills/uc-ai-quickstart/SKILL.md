---
name: uc-ai-quickstart
description: Use when calling an AI/LLM (OpenAI, Anthropic Claude, Google Gemini, Ollama, OCI, xAI, Mistral, OpenRouter) from Oracle PL/SQL with the UC AI library — first uc_ai.generate_text call, choosing provider/model constants, setting up API keys (uc_ai_get_key or APEX web credentials), parsing the result object, continuing conversations, or generating embeddings.
---

# UC AI Quickstart — Calling AI Models from PL/SQL

UC AI is an Oracle PL/SQL framework with a unified API across AI providers. The core call is `uc_ai.generate_text()`, which returns a `json_object_t` with the response, the full message history, and usage statistics.

## Prerequisites

- UC AI installed in the schema (packages `UC_AI`, `UC_AI_OPENAI`, … exist). If not: https://www.united-codes.com/products/uc-ai/docs/guides/installation/
- Oracle Database 12.2+, APEX installed (UC AI uses APEX APIs internally).

## API key setup

Two options — do one of these before any call:

1. **Key function**: the install created `uc_ai_get_key(p_provider in uc_ai.provider_type) return varchar2`. Replace its body so it returns your key per provider.
2. **APEX Web Credential**: create a web credential in the APEX workspace, then set the provider's global to its static ID before calling:

```sql
uc_ai_openai.g_apex_web_credential := 'OPENAI';
-- every provider package has its own g_apex_web_credential;
-- uc_ai.g_apex_web_credential is the cross-provider fallback
```

Setup guides per provider: https://www.united-codes.com/products/uc-ai/docs/guides/installation/#set-up-api-keys

## First call

```sql
declare
  l_result json_object_t;
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_result := uc_ai.generate_text(
    p_user_prompt   => 'What is Oracle APEX?'
  , p_system_prompt => 'You are a helpful assistant. Answer briefly.'
  , p_provider      => uc_ai.c_provider_openai
  , p_model         => uc_ai_openai.c_model_gpt_5_6_luna
  );

  dbms_output.put_line('Response: ' || l_result.get_clob('final_message'));
  dbms_output.put_line('Tokens: ' || l_result.get_object('usage').get_number('total_tokens'));
end;
/
```

## Providers and models

**Always use the package constants, never string literals.** Provider constants live in `uc_ai` (spec), model constants in each `uc_ai_<provider>` spec. Model constants change with releases — check the installed provider package spec for the current list.

| Provider | Constant | Example model constants |
|----------|----------|------------------------|
| OpenAI | `uc_ai.c_provider_openai` | `uc_ai_openai.c_model_gpt_5_6_sol`, `c_model_gpt_5_6_terra`, `c_model_gpt_5_6_luna` |
| Anthropic | `uc_ai.c_provider_anthropic` | `uc_ai_anthropic.c_model_claude_5_opus`, `c_model_claude_4_5_haiku` |
| Google | `uc_ai.c_provider_google` | `uc_ai_google.c_model_gemini_3_1_pro`, `c_model_gemini_3_7_flash` |
| Ollama (local) | `uc_ai.c_provider_ollama` | see `uc_ai_ollama` spec; also set `uc_ai.g_base_url` |
| OCI GenAI | `uc_ai.c_provider_oci` | `uc_ai_oci.c_model_llama_4_maverick`, `c_model_cohere_command_a_reasoning` |
| xAI | `uc_ai.c_provider_xai` | `uc_ai_xai.c_model_grok_4_6`, `c_model_grok_4_3` |
| OpenRouter | `uc_ai.c_provider_openrouter` | see `uc_ai_openrouter` spec |
| Mistral | `uc_ai.c_provider_mistral` | `uc_ai_mistral.c_model_mistral_small`, `c_model_codestral` |

## The four generate_text overloads

```sql
-- 1) prompt-based (start a new conversation)
function generate_text (
  p_user_prompt           in clob
, p_system_prompt         in clob default null
, p_provider              in provider_type
, p_model                 in model_type
, p_max_tool_calls        in pls_integer default null   -- default 10
, p_response_json_schema  in json_object_t default null -- structured output
) return json_object_t;

-- 2) message-array (continue a conversation / full control)
function generate_text (
  p_messages              in json_array_t
, p_provider              in provider_type
, p_model                 in model_type
, p_max_tool_calls        in pls_integer default null
, p_response_json_schema  in json_object_t default null
) return json_object_t;

-- 3) + 4) config-driven variants: same shapes with an extra
--    p_config in json_object_t right after p_model
```

**Rule of thumb:** for scripts and interactive use, set the package globals (`uc_ai.g_enable_tools := true;` etc.) and use overloads 1/2. For reusable or library code, use the `p_config` overloads — they neither read nor mutate globals, are re-entrancy safe, and omitted keys fall back to framework defaults (not current global values):

```sql
l_result := uc_ai.generate_text(
  p_user_prompt => 'Summarize open tickets.'
, p_provider    => uc_ai.c_provider_openai
, p_model       => uc_ai_openai.c_model_gpt_5_6_luna
, p_config      => json_object_t('{
    "g_enable_tools": true,
    "g_tool_tags": ["tickets"],
    "g_apex_web_credential": "OPENAI",
    "openai": {"g_reasoning_effort": "low"}
  }')
);
```

Unknown config keys raise ORA-20503; an unknown provider key raises ORA-20306.

## Reading the result

```sql
l_text   := l_result.get_clob('final_message');            -- the answer
l_reason := l_result.get_string('finish_reason');          -- stop | length | tool_calls | content_filter | max_tool_calls_exceeded
l_usage  := l_result.get_object('usage');                  -- prompt_tokens, completion_tokens, reasoning_tokens, total_tokens
l_msgs   := l_result.get_array('messages');                -- full conversation history
```

Full return-object reference: see `reference.md` in this skill.

## Continuing a conversation

Take `messages` from the previous result, append the follow-up, call the message-array overload. The provider/model may even change mid-conversation:

```sql
l_messages := l_result.get_array('messages');
l_messages.append(
  uc_ai_message_api.create_simple_user_message('And in German, please?')
);

l_result := uc_ai.generate_text(
  p_messages => l_messages
, p_provider => uc_ai.c_provider_google
, p_model    => uc_ai_google.c_model_gemini_3_7_flash
);
```

## Embeddings

```sql
declare
  l_input      json_array_t := json_array_t('["Oracle APEX", "low-code development"]');
  l_embeddings json_array_t;
begin
  l_embeddings := uc_ai.generate_embeddings(
    p_input    => l_input
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_text_embedding_3_small
  );
  -- returns one embedding array (json_array_t of numbers) per input string
  dbms_output.put_line('Vectors: ' || l_embeddings.get_size);
end;
/
```

A config-driven overload `generate_embeddings(p_input, p_provider, p_model, p_config)` exists as well.

## Pitfalls

- **Globals are session-scoped.** Call `uc_ai.reset_globals;` before configuring a call so settings from earlier activity in the session don't leak in. Exception: the event callback registration (`g_event_callback`) intentionally survives resets.
- **Check `finish_reason`.** `length` means the response was truncated; `max_tool_calls_exceeded` means the tool budget ran out.
- **Errors raise exceptions** ORA-20301..20305 (`uc_ai.e_max_calls_exceeded`, `e_error_response`, `e_unhandled_format`, `e_format_processing_error`, `e_model_not_found_error`). Provider API errors surface as `e_error_response` with details in the log.
- **Feature support varies by provider** (tools, structured output, reasoning, file input). Check the provider page: https://www.united-codes.com/products/uc-ai/docs/guides/providers/

## Full documentation

- generate_text API: https://www.united-codes.com/products/uc-ai/docs/api/generate_text/
- Providers: https://www.united-codes.com/products/uc-ai/docs/guides/providers/
- Installation: https://www.united-codes.com/products/uc-ai/docs/guides/installation/
