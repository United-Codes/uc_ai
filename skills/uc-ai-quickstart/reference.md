# UC AI generate_text — Result Object & Config Reference

## Return object structure

`uc_ai.generate_text()` returns a `json_object_t`:

```json
{
  "final_message": "The AI's final response text",
  "messages": [],
  "finish_reason": "stop",
  "usage": {
    "prompt_tokens": 45,
    "completion_tokens": 23,
    "reasoning_tokens": 15,
    "total_tokens": 68
  },
  "tool_calls_count": 2,
  "model": "gpt-4o-mini",
  "provider": "openai"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `final_message` | CLOB | Final assistant message — read with `get_clob('final_message')` |
| `messages` | JSON_ARRAY_T | Complete conversation history (system, user, assistant, tool messages) |
| `finish_reason` | VARCHAR2 | `stop`, `tool_calls`, `length`, `content_filter`, `max_tool_calls_exceeded` |
| `usage` | JSON_OBJECT_T | `prompt_tokens`, `completion_tokens`, `reasoning_tokens`, `total_tokens` |
| `tool_calls_count` | NUMBER | Number of tool executions during the call |
| `model` / `provider` | VARCHAR2 | What actually served the request |

## Message structure

Each entry in `messages`:

- `role`: `"system"` \| `"user"` \| `"assistant"` \| `"tool"`
- `content`: message text (may be `null` for assistant messages that only carry tool calls; may be an array of typed content parts, e.g. `{"type": "text"}`, `{"type": "reasoning"}`, `{"type": "file"}`)
- `tool_calls`: (assistant messages) array of `{id, type, function: {name, arguments}}`
- `tool_call_id`: (tool messages) the call being answered

## Finish reason handling

```sql
case l_result.get_string('finish_reason')
  when 'stop' then
    null; -- completed normally
  when 'length' then
    dbms_output.put_line('Truncated: raise the max tokens (e.g. uc_ai_anthropic.g_max_tokens)');
  when 'max_tool_calls_exceeded' then
    dbms_output.put_line('Tool budget exhausted: raise p_max_tool_calls');
  when 'content_filter' then
    dbms_output.put_line('Blocked by provider content policy');
  else
    dbms_output.put_line('Unexpected: ' || l_result.get_string('finish_reason'));
end case;
```

## p_config keys

The `p_config` overloads (and prompt-profile `model_config_json`) accept root-level keys mirroring the `uc_ai` globals, plus one nested object per provider:

```json
{
  "g_base_url": "http://localhost:11434",
  "g_enable_reasoning": true,
  "g_reasoning_level": "medium",
  "g_enable_tools": true,
  "g_tool_tags": ["billing"],
  "g_max_tool_calls": 5,
  "g_apex_web_credential": "MY_CRED",
  "g_extra_headers": {"X-Tenant-Id": "acme"},
  "g_extra_body": {"top_p": 0.9},
  "g_provider_tools": [{"type": "web_search_preview"}],

  "openai":    {"g_use_responses_api": false, "g_reasoning_effort": "low"},
  "anthropic": {"g_max_tokens": 16384, "g_reasoning_budget_tokens": 2048},
  "google":    {"g_reasoning_budget": -1},
  "xai":       {"g_reasoning_effort": "high"}
}
```

- Unknown keys → ORA-20503. Unknown provider object → ORA-20306.
- Omitted keys fall back to framework defaults (what `uc_ai.reset_globals` restores), **not** to the session's current global values.
- Structured output is always passed via the `p_response_json_schema` parameter, not inside `p_config`. With a schema, `final_message` contains the schema-conforming JSON text — parse it with `json_object_t(l_result.get_clob('final_message'))`.

## Custom HTTP headers

Globals style:

```sql
uc_ai.g_extra_headers('X-Tenant-Id') := 'acme';
uc_ai.g_extra_headers('X-Trace-Id')  := 'abc123';
-- sent with every provider REST request until reset_globals
```

Config style: `{"g_extra_headers": {"X-Tenant-Id": "acme"}}`.

Headers are appended after the framework's own headers (Content-Type, auth, provider version headers) — avoid names the framework already sets.

## Custom request-body properties

For provider parameters the SDK does not wrap (`top_p`, `stop_sequences`, `service_tier`, `metadata`, Anthropic `cache_control`):

```sql
uc_ai.g_extra_body := json_object_t('{"top_p": 0.9, "service_tier": "flex"}');
```

Config style: `{"g_extra_body": {"top_p": 0.9}}`.

Shallow-merged into every provider request body. Top-level keys override framework values; nested objects replace wholesale. The conversation-defining keys are protected and cannot be clobbered: `model`, `messages`, `input`, `instructions`, `system`, `tools`.

## Provider (server-side) tools

Raw, provider-native tool definitions appended verbatim to the request's `tools` array. The provider executes them, not your database, so they are sent with no framework wrapping — and they are sent even when local tools are disabled.

```sql
uc_ai.g_provider_tools := json_array_t('[{"type":"web_search_preview"}]');   -- OpenAI Responses
uc_ai.g_provider_tools := json_array_t('[{"type":"web_search_20250305","name":"web_search"}]');  -- Anthropic
```

Config style: `{"g_provider_tools": [{"type": "web_search_preview"}]}`.

These are provider-specific — check the provider's own API reference for the exact shape. They combine with local tools; the model can use both in one call.
