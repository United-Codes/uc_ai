create or replace package uc_ai 
  authid definer
as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  c_version     constant varchar2(16 char) := '26.3';
  c_version_num constant number := 20260300;

  subtype provider_type is varchar2(64 char);
  c_provider_openai     constant provider_type := 'openai';
  c_provider_anthropic  constant provider_type := 'anthropic';
  c_provider_google     constant provider_type := 'google';
  c_provider_ollama     constant provider_type := 'ollama';
  c_provider_oci        constant provider_type := 'oci';
  c_provider_xai        constant provider_type := 'xai';
  c_provider_openrouter constant provider_type := 'openrouter';
  c_provider_mistral    constant provider_type := 'mistral';

  -- not a real provider, but usable for any provider that supports Responses API
  c_provider_responses_api constant provider_type := 'responses_api';

  subtype model_type is varchar2(128 char);

  subtype finish_reason_type is varchar2(64 char);

  c_finish_reason_tool_calls     constant finish_reason_type := 'tool_calls';
  c_finish_reason_stop           constant finish_reason_type := 'stop';
  c_finish_reason_length         constant finish_reason_type := 'length';
  c_finish_reason_content_filter constant finish_reason_type := 'content_filter';

  -- general global settings
  g_base_url varchar2(4000 char);

  -- extra HTTP request headers sent with every provider REST request,
  -- appended after the framework's base headers (Content-Type, auth, ...)
  -- e.g. uc_ai.g_extra_headers('X-Tenant-Id') := 'acme';
  type t_extra_headers is table of varchar2(4000 char) index by varchar2(255 char);
  -- @dblinter ignore(g-9105): public package-global collection, g_ prefix is intended (not a local var)
  g_extra_headers t_extra_headers;

  -- extra top-level JSON properties shallow-merged into every provider request
  -- body, for parameters the SDK does not wrap (e.g. top_p, stop_sequences,
  -- service_tier, metadata, Anthropic cache_control). Applied after the
  -- framework's own keys but BEFORE messages/model are added, so those reserved
  -- keys cannot be clobbered. Top-level keys override; nested objects replace
  -- wholesale. e.g. uc_ai.g_extra_body := json_object_t('{"top_p":0.9}');
  -- @dblinter ignore(g-9105): public package-global, g_ prefix is intended (not a local var)
  g_extra_body json_object_t;

  -- raw, provider-native tool definitions appended verbatim to the request's
  -- `tools` array. These are executed server-side by the provider, NOT locally,
  -- so they are sent as-is with no framework wrapping. e.g.
  --   Anthropic:         {"type":"web_search_20250305","name":"web_search"}
  --   OpenAI Responses:  {"type":"web_search_preview"}
  -- @dblinter ignore(g-9105): public package-global, g_ prefix is intended (not a local var)
  g_provider_tools json_array_t;

  -- reasoning level constants
  c_reasoning_level_low    constant varchar2(10 char) := 'low';
  c_reasoning_level_medium constant varchar2(10 char) := 'medium';
  c_reasoning_level_high   constant varchar2(10 char) := 'high';

  -- reasoning global settings
  g_enable_reasoning boolean := false;
  g_reasoning_level varchar2(10 char); -- use c_reasoning_level_* constants

  -- tools relevant global settings
  g_enable_tools boolean := false;
  g_tool_tags apex_t_varchar2;
  g_max_tool_calls pls_integer;
  -- Programmatic tool calling ("code mode"): when true (and tools are enabled),
  -- generate_text also offers the uc_ai__run_code meta-tool, letting the model
  -- author a JS program that orchestrates the other tools in-database via Oracle
  -- MLE, returning only its final result. Opt-in per call and requires the MLE
  -- sandbox from scripts/install_ptc_sandbox.sql (23ai+): when the model calls the
  -- meta-tool without it, the run fails with a clear "sandbox not installed" error.
  g_enable_programmatic_tools boolean := false;

  -- global settings for APEX Web Credentials
  g_apex_web_credential varchar2(255 char);

  -- event callback constants
  subtype event_type is varchar2(32 char);
  c_event_assistant_text      constant event_type := 'assistant_text';
  c_event_assistant_reasoning constant event_type := 'assistant_reasoning';
  c_event_tool_call           constant event_type := 'tool_call';
  c_event_tool_result         constant event_type := 'tool_result';
  c_event_response_complete   constant event_type := 'response_complete';

  -- event callback globals (session-scoped; persist across reset_globals)
  g_event_callback varchar2(128 char);
  g_callback_fatal boolean := false;

  -- correlation id for an active generate_text call (set/cleared by the framework)
  g_request_id varchar2(32 char);

  -- internal use only
  g_provider_override varchar2(4000 char);

  -- Execution context (internal use only; set by the agent layer around a run).
  -- generate_text runs (and their tool-calling loops) originate deep below the
  -- agent layer, where the calling agent/user is otherwise unknown. The agent
  -- layer publishes this context here so build_from_globals can snapshot it into
  -- the per-call settings record and the per-tool-call hook can attribute a tool
  -- call to its agent and caller. Fields are null for standalone generate_text.
  type t_exec_context is record (
    agent_id    number
  , agent_code  varchar2(255 char)
  , created_by  varchar2(255 char)
  , session_id  varchar2(255 char)
  , apex_app_id number
  );

  e_max_calls_exceeded exception;
  pragma exception_init(e_max_calls_exceeded, -20301);
  e_error_response exception;
  pragma exception_init(e_error_response, -20302);
  e_unhandled_format exception;
  pragma exception_init(e_unhandled_format, -20303);
  e_format_processing_error exception;
  pragma exception_init(e_format_processing_error, -20304);
  e_model_not_found_error exception;
  pragma exception_init(e_model_not_found_error, -20305);

  /*
   * Main interface for AI text generation
   * Routes to OpenAI implementation - could be extended for provider selection
   * 
   * See https://www.united-codes.com/products/uc-ai/docs/api/generate_text/ for API documentation
   */
  function generate_text (
    p_user_prompt           in clob
  , p_system_prompt         in clob default null
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t;

  function generate_text (
    p_messages              in json_array_t
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t;

  /*
   * Config-driven variants of generate_text.
   *
   * These take a JSON config object (the same structure accepted by
   * uc_ai_prompt_profiles_api.apply_model_config, e.g.
   *   {"g_enable_tools": true, "g_tool_tags": ["math"],
   *    "g_extra_headers": {"X-Tenant-Id": "acme"},
   *    "openai": {"g_use_responses_api": false}} )
   * and derive this call's configuration from it directly, WITHOUT reading or
   * mutating the package globals. This lets other libraries call generate_text
   * with a self-contained config instead of setting globals first, and is safe to
   * call concurrently / re-entrantly (each call owns its settings on the stack).
   *
   * Keys absent from p_config fall back to the framework defaults (the values
   * uc_ai.reset_globals restores), not to the current global values.
   */
  function generate_text (
    p_user_prompt           in clob
  , p_system_prompt         in clob default null
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_config                in json_object_t
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t;

  function generate_text (
    p_messages              in json_array_t
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_config                in json_object_t
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t;

  function generate_embeddings (
    p_input in json_array_t
  , p_provider in provider_type
  , p_model in model_type
  ) return json_array_t;

  /*
   * Config-driven variant of generate_embeddings.
   *
   * Takes the same JSON config object as the config-driven generate_text
   * overloads (the structure accepted by uc_ai_prompt_profiles_api.apply_model_config)
   * and derives this call's configuration from it directly, WITHOUT reading or
   * mutating the package globals. Lets other libraries request embeddings with a
   * self-contained config; safe to call concurrently / re-entrantly.
   *
   * Keys absent from p_config fall back to the framework defaults (the values
   * uc_ai.reset_globals restores), not to the current global values.
   */
  function generate_embeddings (
    p_input in json_array_t
  , p_provider in provider_type
  , p_model in model_type
  , p_config in json_object_t
  ) return json_array_t;

  /*
   * Resets all global variables in uc_ai and provider packages to their default values.
   * Note: g_event_callback is intentionally preserved across resets (long-lived registration).
   */
  procedure reset_globals;

  /*
   * Register a PL/SQL procedure to receive AI activity events during generate_text calls.
   *
   * The procedure must have the signature:
   *   procedure <name>(
   *     p_request_id in varchar2,
   *     p_event_type in varchar2,
   *     p_event_data in clob          -- JSON serialized; parse with json_object_t.parse if needed
   *   );
   *
   * CLOB is used instead of json_object_t because PL/SQL object types cannot be bound via
   * EXECUTE IMMEDIATE. The CLOB is safe to store/forward beyond the callback scope.
   *
   * @param p_proc_name Qualified procedure name (e.g. 'MY_PKG.ON_AI_EVENT'). Null to clear.
   */
  procedure set_event_callback(p_proc_name in varchar2);

  /*
   * Clear the registered event callback.
   */
  procedure clear_event_callback;

  /*
   * Internal: returns the current execution context (see t_exec_context). Used
   * by uc_ai_settings.build_from_globals to snapshot the context into the
   * per-call settings record. Fields are null when set outside an agent run.
   */
  function get_exec_context return t_exec_context;

  /*
   * Internal: publishes the execution context for the currently running agent.
   * Called by the agent layer (uc_ai_agents_api.execute_agent) around a run,
   * using save/restore so nested executions do not clobber their caller's
   * context. Not intended for user code.
   */
  procedure set_exec_context(p_context in t_exec_context);

  /*
   * Internal: clears the execution context (all fields null). Equivalent to
   * set_exec_context with an uninitialised record.
   */
  procedure clear_exec_context;

  /*
   * Internal: invokes the registered event callback. Called by uc_ai_message_api content
   * builders and by generate_text on completion. Not intended for user code.
   */
  procedure fire_event(
    p_event_type in varchar2
  , p_event_data in json_object_t
  );

end uc_ai;
/
