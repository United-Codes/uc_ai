# Architectural Patterns & Conventions

## Provider Abstraction (Strategy Pattern via CASE Routing)

The main `uc_ai.generate_text()` function routes to provider-specific packages via a CASE statement on the provider constant string.

- Routing logic: `src/packages/uc_ai.pkb:18-82`
- Provider constants: `src/packages/uc_ai.pks:16-27`

Each provider package implements the same interface: `generate_text()` and optionally `generate_embeddings()`, but there is no formal interface type -- the dispatch is manual.

**Provider override pattern**: xAI and OpenRouter reuse the OpenAI implementation by setting `g_base_url` and `g_provider_override` globals before calling `uc_ai_openai.generate_text()`. See `src/packages/uc_ai.pkb:61-69`.

## Package Spec/Body Separation

Every package has paired `.pks` (specification) and `.pkb` (body) files. Specs declare the public API (types, constants, procedures, functions). Bodies contain implementation details and private helpers.

- All packages live in `src/packages/`
- Installation order matters: specs before bodies, core before dependents
- The install script enforces this: `install_uc_ai.sql:19-58`

## Naming Conventions

These prefixes are used consistently across all packages:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `c_` | Constants | `c_provider_openai`, `c_model_gpt_4o`, `c_api_url` |
| `g_` | Package-level globals | `g_base_url`, `g_enable_tools`, `g_normalized_messages` |
| `l_` | Local variables | `l_result`, `l_messages`, `l_scope` |
| `p_` | Input parameters | `p_user_prompt`, `p_provider` |
| `po_` | OUT parameters | `po_system_prompt`, `po_step_output` |
| `pio_` | IN OUT parameters | `pio_workflow_state`, `pio_codes` |
| `t_` | Type names | `t_validation_result`, `t_agent_code_list` |
| `e_` | Exceptions | `e_max_calls_exceeded`, `e_error_response` |

Package names: `uc_ai_<domain>` (e.g., `uc_ai_tools_api`, `uc_ai_anthropic`).

## Custom Subtypes for Domain Safety

Domain-specific subtypes constrain string types to prevent misuse:

- `src/packages/uc_ai.pks:14-15`: `provider_type is varchar2(64 char)`, `model_type is varchar2(128 char)`
- `src/packages/uc_ai_logger.pks:20`: `scope is varchar2(100 char)`

These subtypes are used throughout as parameter and variable types instead of raw varchar2.

## Global Variable Configuration Pattern

Provider-specific settings are exposed as package-level global variables rather than procedure parameters. Each provider package declares its own globals:

- `src/packages/uc_ai.pks:38-58`: `g_base_url`, `g_enable_reasoning`, `g_enable_tools`, `g_tool_tags`, `g_apex_web_credential`
- `src/packages/uc_ai_anthropic.pks:28-35`: `g_max_tokens`, `g_reasoning_budget_tokens`
- `src/packages/uc_ai_google.pks:37-40`: `g_reasoning_budget`
- `src/packages/uc_ai_openai.pks:48-51`: `g_reasoning_effort`

A `reset_globals()` procedure in `uc_ai.pks:103` resets all globals to defaults.

Globals are annotated with `@dblinter ignore(g-7230)` to suppress the linter warning about package-level state.

## JSON as Universal Data Format

Oracle's native `json_object_t` and `json_array_t` types are used for:
- API request/response construction (all provider `.pkb` files)
- Message content building (`src/packages/uc_ai_message_api.pkb:12-26`)
- Workflow state management (`src/packages/uc_ai_agent_exec_api.pkb:81-104`)
- Tool parameter schemas (`src/packages/uc_ai_tools_api.pkb`)
- Agent configuration (workflow definitions, orchestration configs)

**Message conversion pattern**: Each provider transforms the normalized internal message format to its provider-specific format:
- `uc_ai_anthropic.pkb`: `convert_lm_messages_to_anthropic()` (line 76)
- `uc_ai_google.pkb`: `convert_lm_messages_to_google()` (line 102)
- `uc_ai_openai.pkb`: `convert_lm_messages_to_openai()` (line 75)
- `uc_ai_responses_api.pkb`: `convert_lm_messages_to_items()` (line 36)

## Error Handling

### Custom Exception Codes
Framework-level exceptions defined in `src/packages/uc_ai.pks:60-69`:
- `-20301`: Max tool calls exceeded
- `-20302`: Error response from provider
- `-20303`: Unhandled format
- `-20304`: Format processing error
- `-20305`: Model not found

Agent-specific errors use `-20001` (general) and `-20011` to `-20023` range.

### Logging Before Re-raise
All exception handlers log via `uc_ai_logger` before re-raising. Standard pattern found in every `.pkb` file:

```
exception
  when others then
    uc_ai_logger.log_error(
      'Description',
      l_scope,
      sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
    );
    raise;
```

### Scope Tracking
Every package body declares `c_scope_prefix` as a constant for logger scope identification. Individual procedures build scope as `c_scope_prefix || 'procedure_name'`.

## Provider Global State for Conversation Tracking

Each provider package maintains global state for multi-turn conversations:

- `g_normalized_messages json_array_t` -- accumulated conversation history
- `g_final_message clob` -- last AI response text
- `g_input_tokens number` / `g_output_tokens number` -- token counters
- `g_tool_calls number` -- tool call counter (prevents infinite loops)

See: `uc_ai_anthropic.pkb:8-12`, `uc_ai_google.pkb:7-12`, `uc_ai_openai.pkb:8-14`

## Agent Type System

Five agent types with dedicated execution functions in `src/packages/uc_ai_agent_exec_api.pkb`:

| Type | Constant | Behavior |
|------|----------|----------|
| `profile` | `c_type_profile` | Single prompt profile execution |
| `workflow` | `c_type_workflow` | Multi-step workflows (sequential, conditional, parallel, loop) |
| `orchestrator` | `c_type_orchestrator` | Central agent delegates to child agents registered as temporary tools |
| `handoff` | `c_type_handoff` | Agent-to-agent control passing |
| `conversation` | `c_type_conversation` | Multi-agent dialogue (round-robin or AI-driven) |

Type constants: `src/packages/uc_ai_agents_api.pks:13-22`

## Workflow Step Execution Pattern

Workflow steps are defined as JSON objects with:
- `agent_code`: which agent to run
- `input_mapping`: data flow using JSONPath-like syntax (`$.input.*`, `$.steps.<name>.*`)
- `output_key`: where to store results in workflow state
- `condition`: optional conditional execution

The `run_step()` procedure in `src/packages/uc_ai_agent_workflow_api.pks:27-35` handles step execution with pre/post step support. Input mapping supports both simple (`"key": "$.path"`) and extended (`"key": {"path": "$.path", "default": "value"}`) syntax. See `docs/input-mapping-guide.md`.

## Orchestrator Tool Registration Pattern

Orchestrator agents register child agents as temporary tools in `uc_ai_tools` table during execution, then clean them up after. This lets the AI model "call" other agents through the existing function-calling mechanism.

- Registration: `src/packages/uc_ai_agent_exec_api.pks:137-141`
- Cleanup: `src/packages/uc_ai_agent_exec_api.pks:143-145`

## Execution State Persistence

Agent executions are tracked in `uc_ai_agent_executions` table with:
- `status`: pending -> running -> completed/failed/timeout
- `input_parameters`, `current_state`, `output_result` as CLOB (JSON)
- `parent_execution_id`: links nested agent calls
- `session_id`: groups related executions (generated via `SYS_GUID()`)

Creation: `src/packages/uc_ai_agents_api.pkb:114-142`
Status constants: `src/packages/uc_ai_agents_api.pks:39-44`

## Versioning Pattern

Both prompt profiles and agents support versioning:
- Multiple versions can exist per `code`
- Only one version per code can have `status = 'active'` (enforced by unique index)
- `create_new_version()` clones from a source version
- Status lifecycle: `draft` -> `active` -> `archived`

Prompt profiles: `src/packages/uc_ai_prompt_profiles_api.pks:33-80`
Agents: `src/packages/uc_ai_agents_api.pks:197-201`

## Test Conventions

- Test packages: `test_uc_ai_<feature>.pks/.pkb` in `test/`
- Setup/teardown procedures configure provider globals and seed test data
- Assertions use `ut.expect()` from utPLSQL
- Test data management: explicit DELETE + re-insert in setup (no rollback-based isolation)
- Shared helpers: `uc_ai_test_utils` provides tool creation, message builders, and test fixtures
- Message validation utilities: `uc_ai_test_message_utils.validate_message_array()`, `valididate_return_object()`

## APEX Web Credential Integration

Authentication with AI providers uses Oracle APEX web credentials. Each provider package has a `g_apex_web_credential` global. The credential format varies by provider:
- Anthropic: HTTP Header `x-api-key`
- OpenAI/xAI/OpenRouter: HTTP Header `Authorization` (Bearer token)
- Google: URL query parameter `key=...`
- OCI: OCI native authentication
