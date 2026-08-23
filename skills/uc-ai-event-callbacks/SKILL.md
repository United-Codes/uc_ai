---
name: uc-ai-event-callbacks
description: Use when observing UC AI generate_text calls live from Oracle PL/SQL — streaming-style UIs, audit logging of tool calls, or observability. Covers uc_ai.set_event_callback / clear_event_callback, the callback signature (p_request_id, p_event_type, p_event_data clob), event constants uc_ai.c_event_assistant_text / assistant_reasoning / tool_call / tool_result / response_complete, uc_ai.g_request_id correlation, and g_callback_fatal error semantics.
---

# UC AI Event Callbacks — Observing generate_text Live

UC AI can push events to a PL/SQL procedure of yours while `uc_ai.generate_text` runs: assistant text blocks, reasoning blocks, tool calls and their results, and final completion. Use this for streaming-style UIs (render activity as it happens), audit logging of every tool call, and observability across long agent runs.

Registration is session-scoped and global to the session: register once, and every subsequent `generate_text` call in that session delivers events to your procedure until you clear it.

## Callback contract

Your callback must be a schema-visible procedure with this exact signature:

```sql
procedure my_ai_event_handler(
  p_request_id in varchar2
, p_event_type in varchar2
, p_event_data in clob    -- JSON serialized payload
);
```

`p_event_data` is a CLOB instead of `json_object_t` because PL/SQL object types cannot be bound via `execute immediate`. Parse it with `json_object_t.parse(p_event_data)` when you need structured access; the CLOB is safe to store or forward beyond the callback scope.

## Register and clear

```sql
uc_ai.set_event_callback('MY_PKG.ON_AI_EVENT');  -- or 'MY_SCHEMA.MY_PKG.ON_AI_EVENT'

uc_ai.clear_event_callback;
```

The name is validated via `dbms_assert.qualified_sql_name` — a malformed name raises ORA-44003/ORA-44004 at registration time, before any event fires. Registration lives in `uc_ai.g_event_callback` and is session-scoped, but it intentionally **survives `uc_ai.reset_globals`** (long-lived registration), so you don't have to re-register after each reset.

## Event types

Compare `p_event_type` against the `uc_ai.c_event_*` constants, never string literals:

| Constant | Value | When it fires | Payload (roughly) |
|---|---|---|---|
| `uc_ai.c_event_assistant_text` | `assistant_text` | Assistant returns a text content block | `text` |
| `uc_ai.c_event_assistant_reasoning` | `assistant_reasoning` | A reasoning/thinking block is returned | reasoning text |
| `uc_ai.c_event_tool_call` | `tool_call` | Before a tool is executed | `toolName`, arguments |
| `uc_ai.c_event_tool_result` | `tool_result` | After a tool executes | `result` |
| `uc_ai.c_event_response_complete` | `response_complete` | At the very end of `generate_text` | the final result object |

Events only fire during a `generate_text` call — building input messages yourself outside a call emits nothing.

## Complete example

A minimal handler that logs to `dbms_output`:

```sql
create or replace package my_pkg is
  procedure on_ai_event(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  );
end my_pkg;
/

create or replace package body my_pkg is
  procedure on_ai_event(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  )
  as
    l_data json_object_t;
  begin
    l_data := json_object_t.parse(p_event_data);
    dbms_output.put_line('[' || p_request_id || '] ' || p_event_type);
    case p_event_type
      when uc_ai.c_event_assistant_text then
        dbms_output.put_line('  text: ' || l_data.get_string('text'));
      when uc_ai.c_event_tool_call then
        dbms_output.put_line('  tool: ' || l_data.get_string('toolName'));
      when uc_ai.c_event_tool_result then
        dbms_output.put_line('  result: ' || l_data.get_clob('result'));
      else
        null;
    end case;
  end on_ai_event;
end my_pkg;
/
```

Register it and run a call:

```sql
begin
  uc_ai.set_event_callback('MY_PKG.ON_AI_EVENT');

  declare
    l_result json_object_t;
  begin
    -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the email address of Jim?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => uc_ai_openai.c_model_gpt_5_6_luna
    );
  end;

  uc_ai.clear_event_callback;
end;
/
```

Typical output (tool-calling path):

```
[A1B2C3...] tool_call
  tool: TT_GET_USERS
[A1B2C3...] tool_result
  result: [{"user_id":4,"first_name":"Jim",...}]
[A1B2C3...] assistant_text
  text: jim.halpert@dundermifflin.com
[A1B2C3...] response_complete
```

Model constants change with releases — check the installed provider spec. For `generate_text` basics and API key setup, see the `uc-ai-quickstart` skill or https://www.united-codes.com/products/uc-ai/docs/api/generate_text/.

## Error semantics

By default, exceptions raised inside your callback are **swallowed** so a buggy handler can never break an AI call — failures are logged via `uc_ai_logger` (with backtrace). To make callback errors abort the `generate_text` call — useful during development so you actually notice handler bugs:

```sql
uc_ai.g_callback_fatal := true;
```

Like all `g_*` globals this is session-scoped — and unlike `g_event_callback`, it **is** reset to `false` by `uc_ai.reset_globals`.

## Correlating events

`p_request_id` is a per-call correlation id (a hex GUID), unique per `generate_text` call: two sequential calls in the same session get two different ids. Use it to group events belonging to one AI call, e.g. inside multi-step or multi-agent workflows. The framework sets `uc_ai.g_request_id` at the start of each call and clears it at the end — you can read it mid-call from any code running inside the request (tools, for instance).

## Pitfalls

- **Asymmetric reset behavior:** `g_event_callback` survives `uc_ai.reset_globals` (intentional long-lived registration) but `g_callback_fatal` does not — after a reset, callback errors are silently swallowed again. Re-set `g_callback_fatal := true;` after every reset during development.
- **Silent-by-default failures:** if events seem to be "missing", your handler may be raising and being swallowed. Turn on `g_callback_fatal` or check the `uc_ai_logger` output.
- **Session scope:** registration only applies to the current session. In connection-pool environments (APEX, ORDS) each request may get a different session — register at the start of processing, don't assume it persists across requests.
- **Signature must match exactly** (`p_request_id varchar2, p_event_type varchar2, p_event_data clob`); it is invoked dynamically, so a mismatch fails at event time, not at registration.
- **No events outside `generate_text`:** message-building or other UC AI calls outside a running request emit nothing.

## Full documentation

- Event callbacks guide: https://www.united-codes.com/products/uc-ai/docs/guides/event-callbacks/
- generate_text API: https://www.united-codes.com/products/uc-ai/docs/api/generate_text/
