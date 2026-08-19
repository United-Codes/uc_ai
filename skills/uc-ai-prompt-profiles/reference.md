# model_config_json — Full Key Reference

The JSON stored in a profile's `model_config_json` (or passed as `p_config_override` to `execute_profile`) is applied at execution time: UC AI first calls `uc_ai.reset_globals`, then sets the corresponding globals from the config. The same structure is accepted by the `p_config` overloads of `uc_ai.generate_text`.

Rules:

- **Unknown root or provider keys raise ORA-20503** (invalid config); an **unknown provider raises ORA-20306**.
- **Omitted keys fall back to framework defaults** (what `uc_ai.reset_globals` restores), **not** to the session's current global values.
- Only the nested object matching the **executing provider** is applied. Other providers' objects may be present at root level (handy with `p_provider_override`), but their contents are neither applied nor validated.
- Root keys with a wrong JSON type (e.g. string where boolean expected) are silently skipped.
- `response_schema` is a reserved root key consumed internally by agent execution — set structured-output schemas via the profile's `p_response_schema` column instead.

## Root-level keys

Mirror the `uc_ai` package globals:

| Key | Type | Default after reset | Purpose |
|-----|------|---------------------|---------|
| `g_base_url` | string | null | Override the API endpoint (required for Ollama, e.g. `http://localhost:11434`) |
| `g_enable_reasoning` | boolean | false | Enable reasoning/thinking mode |
| `g_reasoning_level` | string | null | `low`, `medium`, or `high` (see `uc_ai.c_reasoning_level_*` constants) |
| `g_enable_tools` | boolean | false | Enable tool/function calling |
| `g_tool_tags` | array of strings or single string | empty | Filter which registered tools are offered |
| `g_max_tool_calls` | number | null (framework default 10) | Tool-call budget per conversation |
| `g_apex_web_credential` | string | null | Cross-provider APEX web credential static ID |
| `g_extra_headers` | object of name/value strings | empty | Extra HTTP headers sent with every provider request |

## Provider-specific keys

Nested under the provider name (values of `uc_ai.c_provider_*`). Exactly these keys are accepted per provider — anything else raises ORA-20503.

### `openai`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_reasoning_effort` | string | `low` | `minimal`, `low`, `medium`, `high`, `xhigh` |
| `g_apex_web_credential` | string | null | Provider-specific credential |
| `g_use_responses_api` | boolean | true | Use the OpenAI Responses API instead of Chat Completions |

### `anthropic`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_max_tokens` | number | 8192 | Maximum response tokens |
| `g_reasoning_budget_tokens` | number | null | Thinking token budget (minimum 1024) |
| `g_apex_web_credential` | string | null | Provider-specific credential |

### `google`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_reasoning_budget` | number | null | Thinking budget (`-1` dynamic, `0` off) |
| `g_apex_web_credential` | string | null | Provider-specific credential |
| `g_embedding_task_type` | string | `SEMANTIC_SIMILARITY` | Embedding task type |
| `g_embedding_output_dimensions` | number | 1536 | Embedding vector size |

### `ollama`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_apex_web_credential` | string | null | Provider-specific credential |
| `g_use_responses_api` | boolean | true | Use the Responses-API-compatible endpoint |

### `xai`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_reasoning_effort` | string | `low` | `low`, `high` |
| `g_apex_web_credential` | string | null | Provider-specific credential |

### `openrouter`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_reasoning_effort` | string | `low` | `minimal`, `low`, `medium`, `high` |
| `g_apex_web_credential` | string | null | Provider-specific credential |

### `mistral`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_apex_web_credential` | string | null | Provider-specific credential |

### `oci`

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `g_apex_web_credential` | string | null | Provider-specific credential |
| `g_compartment_id` | string | null | OCID of the compartment to use |
| `g_serving_type` | string | `ON_DEMAND` | `ON_DEMAND` or `DEDICATED` |
| `g_region` | string | `us-ashburn-1` | OCI region for the API endpoint |
| `g_use_responses_api` | boolean | true | Use the Responses-API-compatible endpoint |

## Complete example

A profile config enabling tools and reasoning, with per-provider settings for its default provider (Anthropic) and an alternative used via `p_provider_override`:

```json
{
  "g_enable_reasoning": true,
  "g_reasoning_level": "medium",
  "g_enable_tools": true,
  "g_tool_tags": ["tickets", "user_lookup"],
  "g_max_tool_calls": 5,
  "g_apex_web_credential": "MY_CRED",
  "g_extra_headers": {"X-Tenant-Id": "acme"},

  "anthropic": {
    "g_max_tokens": 16384,
    "g_reasoning_budget_tokens": 2048
  },
  "openai": {
    "g_reasoning_effort": "low",
    "g_use_responses_api": true
  }
}
```

Used in `create_prompt_profile`:

```sql
l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
  p_code                   => 'COMPLEX_ANALYSIS'
, p_description            => 'Analyzes complex scenarios with reasoning and tools'
, p_system_prompt_template => 'You are an analytical assistant.'
, p_user_prompt_template   => 'Analyze: {scenario}'
, p_provider               => uc_ai.c_provider_anthropic
, p_model                  => uc_ai_anthropic.c_model_claude_4_5_haiku
, p_model_config_json      => l_config_clob
);
```

## Full documentation

- Prompt profiles guide (configuration section): https://www.united-codes.com/products/uc-ai/docs/guides/prompt-profiles/
- Provider setup guides: https://www.united-codes.com/products/uc-ai/docs/guides/providers/
