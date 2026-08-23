---
name: uc-ai-tools
description: Use when giving an AI/LLM access to database data or actions (tools / function calling) from Oracle PL/SQL with UC AI — registering tools with uc_ai_tools_api.create_tool_from_schema or merge_tool_from_schema, describing parameters with a JSON schema, enabling tools via uc_ai.g_enable_tools, restricting them with uc_ai.g_tool_tags, limiting p_max_tool_calls, testing with execute_tool, writing robust CLOB-in/CLOB-out tool functions, enabling code mode (programmatic tool calling) with uc_ai.g_enable_programmatic_tools, or adding provider server-side tools with uc_ai.g_provider_tools.
---

# UC AI Tools — Let the AI Call Your PL/SQL

Tools (function calling) let the model interact with your data. You register a PL/SQL function with a description and a JSON schema of its parameters; during `uc_ai.generate_text` the model decides when to call it, UC AI executes the function and feeds the result back to the model. See `examples.sql` in this skill for a complete multi-tool timetracking example.

## The tool contract

A tool is a PL/SQL function with these attributes:

- Takes **at most one parameter**: a `clob` containing a JSON object with all arguments (the model "speaks JSON", so multiple logical arguments travel in one object).
- Returns a `clob` — the text the model gets to read.
- The registered `p_function_call` snippet is a function body like `return my_pkg.get_weather(:parameters);`. It may contain **exactly one bind variable** (conventionally `:parameters`), which receives the arguments JSON as a CLOB. More than one bind is rejected for security.
- Parameterless tools: pass `p_json_schema => null` and use no bind at all, e.g. `return my_pkg.get_all_users_json();`.

## Registering a tool

The real signature (from `uc_ai_tools_api`):

```sql
function create_tool_from_schema(
  p_tool_code             in uc_ai_tools.code%type,
  p_description           in uc_ai_tools.description%type,
  p_function_call         in uc_ai_tools.function_call%type,
  p_json_schema           in json_object_t,
  p_active                in uc_ai_tools.active%type default 1,
  p_version               in uc_ai_tools.version%type default '1.0',
  p_authorization_schema  in uc_ai_tools.authorization_schema%type default null,
  p_created_by            in uc_ai_tools.created_by%type default coalesce(sys_context('APEX$SESSION','app_user'), sys_context('userenv', 'session_user')),
  p_tags                  in apex_t_varchar2 default apex_t_varchar2()
) return uc_ai_tools.id%type;
```

Complete example — the function, its schema, and the registration:

```sql
-- 1) the tool function: one CLOB in (JSON object), CLOB out
create or replace function get_weather (
  p_parameters in clob
) return clob
as
  l_json json_object_t := json_object_t(p_parameters);
  l_city varchar2(255 char) := l_json.get_string('city');
  l_unit varchar2(20 char)  := coalesce(l_json.get_string('unit'), 'celsius');
begin
  if l_city is null then
    return 'Error: city is required';
  end if;
  -- look up / call weather API here ...
  return 'Weather in ' || l_city || ': 21 degrees ' || l_unit || ', sunny';
end get_weather;
/

-- 2) register it with a JSON schema describing the parameters
declare
  l_schema  json_object_t;
  l_tool_id uc_ai_tools.id%type;
begin
  l_schema := json_object_t('{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "title": "get weather parameters",
    "properties": {
      "city": {
        "type": "string",
        "description": "Name of the city to get weather information for"
      },
      "unit": {
        "type": "string",
        "description": "Temperature unit. Defaults to celsius",
        "enum": ["celsius", "fahrenheit", "kelvin"]
      }
    },
    "required": ["city"]
  }');

  l_tool_id := uc_ai_tools_api.create_tool_from_schema(
    p_tool_code     => 'GET_WEATHER'
  , p_description   => 'Get the current weather for a given city'
  , p_function_call => 'return get_weather(:parameters);'
  , p_json_schema   => l_schema
  , p_tags          => apex_t_varchar2('weather')
  );
  commit;
end;
/
```

`create_tool_from_schema` is **create-only** — it raises an error if a tool with the same `p_tool_code` already exists.

### Idempotent deployments: merge_tool_from_schema

`uc_ai_tools_api.merge_tool_from_schema` takes the exact same parameters and upserts: it creates the tool if missing, otherwise updates it — the tool's parameters and tags are fully replaced from the new schema/tags. Use it in deployment/install scripts:

```sql
l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
  p_tool_code     => 'GET_WEATHER'
, p_description   => 'Get the current weather for a given city'
, p_function_call => 'return get_weather(:parameters);'
, p_json_schema   => l_schema
, p_tags          => apex_t_varchar2('weather')
);
```

To test a tool without an AI call, execute it directly:

```sql
function execute_tool(
  p_tool_code in uc_ai_tools.code%type
, p_arguments in json_object_t
) return clob;
```

## Enabling tools in a call

Tools are off by default. Enable them per session via globals (globals are session-scoped — call `uc_ai.reset_globals;` before configuring):

```sql
declare
  l_result json_object_t;
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  uc_ai.reset_globals;
  uc_ai.g_enable_tools := true;
  -- optionally expose only tools carrying certain tags
  uc_ai.g_tool_tags := apex_t_varchar2('weather');

  l_result := uc_ai.generate_text(
    p_user_prompt    => 'How is the weather in Paris?'
  , p_provider       => uc_ai.c_provider_openai
  , p_model          => uc_ai_openai.c_model_gpt_5_6_luna
  , p_max_tool_calls => 6  -- default 10
  );

  dbms_output.put_line(l_result.get_clob('final_message'));
end;
/
```

Model constants change with releases — check the installed `uc_ai_openai` spec (or the respective `uc_ai_<provider>` spec) for the current list.

`p_max_tool_calls` caps how many tool executions one `generate_text` call may perform (default 10). If the budget runs out, `finish_reason` is `max_tool_calls_exceeded`.

For reusable/library code prefer the `p_config` overload of `generate_text` — it neither reads nor mutates globals:

```sql
l_result := uc_ai.generate_text(
  p_user_prompt => 'How is the weather in Paris?'
, p_provider    => uc_ai.c_provider_openai
, p_model       => uc_ai_openai.c_model_gpt_5_6_luna
, p_config      => json_object_t('{
    "g_enable_tools": true,
    "g_tool_tags": ["weather"]
  }')
);
```

## Code mode (programmatic tool calling)

Instead of one LLM round-trip per tool call, the model can write **one** JavaScript program that calls many tools in-database and returns only the final result. Big token savings on loops and large intermediate data.

```sql
uc_ai.reset_globals;
uc_ai.g_enable_tools := true;
uc_ai.g_enable_programmatic_tools := true;   -- opt in
```

Config style: `{"g_enable_programmatic_tools": true}`. Prompt profiles and agents accept the same key.

Requirements and behavior:

- Needs **Oracle 23ai** (MLE JavaScript with `PURE` execution contexts). The rest of UC AI runs on 12.2+.
- A DBA installs the sandbox once per UC AI schema: `@scripts/install_ptc_sandbox.sql` (or `install_ptc_sandbox_complete.sql` from a release download). Without it, enabling code mode raises an error naming the script.
- The model's JavaScript has **no SQL access at all** — it cannot read data, and it cannot `COMMIT` or `ROLLBACK`. It reaches tools only through one gateway that enforces a per-run allow-list and a call budget.
- Your **tools** still run with full UC AI privileges and in the caller's transaction. The sandbox constrains the generated code, not your tools. Give a code-mode run read-oriented tools only — use `p_tool_tags` to keep write and destructive tools out.
- Works with every provider. Both options stay available: the model can still call a tool directly.

Per-tool availability is set at registration with `p_code_mode_access`:

| Value | Meaning |
|-------|---------|
| `direct` | Normal tool only. Not callable from a program. |
| `code` | Callable only from a code-mode program. |
| `both` | Both |

Defaults differ per procedure: `create_tool_from_schema` defaults to `'both'`;
`merge_tool_from_schema` defaults to **null**, which keeps whatever an existing tool
already has and uses `both` for a new one — so re-running a merge script never
widens a tool you deliberately narrowed.

## Provider (server-side) tools

Some providers run their own tools server-side (web search, for example). Append their raw, provider-native definitions — UC AI sends them verbatim and does not execute them:

```sql
uc_ai.g_provider_tools := json_array_t('[{"type":"web_search_preview"}]');   -- OpenAI Responses
uc_ai.g_provider_tools := json_array_t('[{"type":"web_search_20250305","name":"web_search"}]');  -- Anthropic
```

Config style: `{"g_provider_tools": [{"type": "web_search_preview"}]}`. These are sent even when `g_enable_tools` is false, and they combine with your local tools.

## Writing robust tool functions

The model reads whatever your function returns — use that channel:

- Parse with `json_object_t(p_parameters)` and `get_string`/`get_number`.
- **Validate required fields** and constraints yourself; the schema guides the model but does not guarantee valid input.
- **Return error text instead of raising.** `return 'Error: project "' || l_name || '" not found';` lets the model self-correct — it can fix a typo, call a lookup tool, or ask the user. A raised exception aborts the whole `generate_text` call.
- **Return explicit success confirmations** ("User X clocked in successfully on project Y") so the model knows the action happened and can report it.

```sql
create or replace function clock_in_json (
  p_parameters in clob
) return clob
as
  l_json json_object_t := json_object_t(p_parameters);
  l_user_email varchar2(255 char) := l_json.get_string('user_email');
begin
  if l_user_email is null then
    return 'Error: user_email is required';
  end if;
  -- do the work ...
  return 'User ' || l_user_email || ' clocked in successfully';
exception
  when others then
    return 'Error: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace;
end clock_in_json;
/
```

## Read-only tools: returning query results

Serialize rows into one CLOB with SQL/JSON:

```sql
create or replace function get_all_users_json
return clob
as
  l_json clob;
begin
  select json_arrayagg(
           json_object(
             'user_id'    value user_id,
             'first_name' value first_name,
             'last_name'  value last_name,
             'email'      value email
           )
           order by last_name
           returning clob
         )
    into l_json
    from tt_users;

  return coalesce(l_json, '[]');
end get_all_users_json;
/
```

For larger result sets, TOON encoding cuts token usage substantially compared to JSON — see the `uc-ai-structured-output` skill or https://www.united-codes.com/products/uc-ai/docs/guides/toon/.

## Best practices

- **Describe tools thoroughly**, including example parameter values in `p_description` (e.g. `Example parameters: {"user_email": "user@example.com", "project_name": "TV Marketing"}`). Good descriptions drastically improve tool selection.
- **Restrict via tags** (`uc_ai.g_tool_tags` / config `"g_tool_tags"`). Many registered tools means bloated context and worse tool choices — expose only what the current use case needs.
- **Enable reasoning** for multi-step tool workflows; it helps the model plan which tools to call in what order — see the `uc-ai-reasoning` skill or https://www.united-codes.com/products/uc-ai/docs/guides/reasoning/.
- **Provider quality varies a lot** for tool calling. Test your workflow per provider/model; Anthropic models are notably strong here.

## Pitfalls

- **Tools are opt-in per call.** Registering a tool is not enough — without `uc_ai.g_enable_tools := true;` (or `"g_enable_tools": true` in `p_config`) the model never sees it.
- **Globals are session-scoped.** Call `uc_ai.reset_globals;` before configuring, or a `g_tool_tags` filter from earlier code silently hides tools. For library code use the `p_config` overloads.
- **Only one bind variable** is allowed in `p_function_call`. Pack all arguments into the single JSON object; the bind name is arbitrary (convention: `:parameters`).
- **Don't raise from tool functions** — return the error text so the model can recover. Raising aborts the entire `generate_text` call.
- **Commit after registering.** `create_tool_from_schema`/`merge_tool_from_schema` do not commit.
- **`create_tool_from_schema` fails on re-run** (duplicate code). Use `merge_tool_from_schema` in scripts that run more than once.

## Full documentation

- Tools guide: https://www.united-codes.com/products/uc-ai/docs/guides/tools/
- Programmatic tool calling (code mode): https://www.united-codes.com/products/uc-ai/docs/guides/programmatic-tool-calling/
- Interactive JSON schema builder: https://www.united-codes.com/products/uc-ai/docs/other/json-schema/
- Reasoning (better tool planning): https://www.united-codes.com/products/uc-ai/docs/guides/reasoning/
