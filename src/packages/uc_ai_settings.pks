create or replace package uc_ai_settings
  authid definer
as
  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  /*
   * Per-call configuration and run state, threaded as parameters through the
   * provider generate_text implementations instead of read from mutable package
   * globals. Building the settings record once (build_from_globals) at the top
   * of uc_ai.generate_text and passing it down makes a nested agent execution
   * unable to corrupt its caller's in-flight tool-calling loop: each call owns
   * its own record on the call stack.
   *
   * The uc_ai.* / provider g_* globals remain the public WRITE surface (users and
   * uc_ai_prompt_profiles_api.apply_model_config set them); this record is derived
   * from them.
   *
   * Explicit scalar types are used (no cross-package %type in record fields).
   */

  -- Read-only per-call configuration snapshot.
  -- `initialized` distinguishes a supplied record from an uninitialised default
  -- (records cannot be null); build_from_globals sets it to true.
  --
  -- Adding a setting means touching four places: the g_* global (uc_ai.pks or the
  -- provider .pks), the field below (keep the type in sync with the global's),
  -- build_from_globals and build_from_config in uc_ai_settings.pkb, and the
  -- consumer that reads it from the record.
  type t_settings is record (
    initialized                    boolean
    -- execution context (from uc_ai.get_exec_context; null outside an agent run).
    -- Threaded down so the per-tool-call hook can attribute a tool call to its
    -- agent and caller. Not part of the JSON config surface (build_from_config
    -- leaves these null).
  , ctx_agent_id                   number
  , ctx_agent_code                 varchar2(255 char)
  , ctx_created_by                 varchar2(255 char)
  , ctx_session_id                 varchar2(255 char)
  , ctx_apex_app_id                number
    -- common (from uc_ai.g_*)
  , base_url                       varchar2(4000 char)
  , provider_override              varchar2(4000 char)
  , apex_web_credential            varchar2(255 char)
  , enable_tools                   boolean
  , enable_reasoning               boolean
  , reasoning_level                varchar2(10 char)
  , tool_tags                      apex_t_varchar2
  , max_tool_calls                 pls_integer
  , extra_headers                  uc_ai.t_extra_headers
  , extra_body                     json_object_t
  , provider_tools                 json_array_t
    -- openai
  , oa_use_responses_api           boolean
  , oa_reasoning_effort            varchar2(32 char)
  , oa_apex_web_credential         varchar2(255 char)
    -- anthropic
  , an_max_tokens                  pls_integer
  , an_reasoning_budget_tokens     pls_integer
  , an_apex_web_credential         varchar2(255 char)
    -- google
  , go_reasoning_budget            pls_integer
  , go_apex_web_credential         varchar2(255 char)
  , go_embedding_task_type         varchar2(255 char)
  , go_embedding_output_dimensions pls_integer
    -- ollama
  , ol_apex_web_credential         varchar2(255 char)
  , ol_use_responses_api           boolean
    -- oci
  , oc_compartment_id              varchar2(255 char)
  , oc_serving_type                varchar2(64 char)
  , oc_region                      varchar2(64 char)
  , oc_apex_web_credential         varchar2(255 char)
  , oc_use_responses_api           boolean
  , oc_max_tokens                  pls_integer
    -- xai
  , xa_reasoning_effort            varchar2(32 char)
  , xa_apex_web_credential         varchar2(255 char)
    -- openrouter
  , or_reasoning_effort            varchar2(32 char)
  , or_apex_web_credential         varchar2(255 char)
    -- mistral
  , ms_apex_web_credential         varchar2(255 char)
    -- responses api (populated by openai/ollama/oci before delegating)
  , ra_base_url                    varchar2(4000 char)
  , ra_apex_web_credential         varchar2(255 char)
  , ra_reasoning_effort            varchar2(32 char)
  , ra_reasoning_summary           varchar2(32 char)
  , ra_text_verbosity              varchar2(32 char)
  , ra_store_responses             boolean
  , ra_include_encrypted_reasoning boolean
  , ra_skip_auth                   boolean
  );

  -- Mutable per-call accumulators (the message array is threaded separately as
  -- an `in out json_array_t`, since records cannot reliably hold json_array_t).
  type t_run_state is record (
    tool_calls           pls_integer
  , final_message        clob
  , input_tokens         number
  , output_tokens        number
  , reasoning_tokens     number
  , total_tokens         number
  );

  /*
   * Snapshot the current global configuration into a settings record.
   * Read once per top-level uc_ai.generate_text call.
   */
  function build_from_globals return t_settings;

  /*
   * Build a settings record directly from a JSON config object WITHOUT reading
   * or mutating any global variable. Accepts the same JSON structure as
   * uc_ai_prompt_profiles_api.apply_model_config (root keys such as g_base_url,
   * g_enable_tools, g_tool_tags, ... plus a provider-named nested object, e.g.
   * {"openai": {"g_use_responses_api": false}}). Unknown keys raise
   * uc_ai_error.c_err_invalid_config; an unknown provider raises
   * c_err_unknown_provider.
   *
   * This lets external callers drive uc_ai.generate_text with a self-contained
   * config (see the uc_ai.generate_text overloads that take p_config) instead of
   * having to set the package globals first.
   *
   * Fields not present in p_config keep their framework default (the same values
   * uc_ai.reset_globals restores). The `response_schema` key is ignored here
   * (pass the schema via p_response_json_schema instead).
   */
  function build_from_config(
    p_config   in json_object_t
  , p_provider in varchar2
  ) return t_settings;

  /*
   * Append the user-supplied extra HTTP headers (uc_ai.g_extra_headers /
   * "g_extra_headers" config key) to apex_web_service.g_request_headers.
   * Call AFTER the provider set its base headers (Content-Type, auth, ...)
   * and immediately before apex_web_service.make_rest_request, so a prior
   * apex_web_service.set_request_headers (p_reset defaults to true) cannot
   * wipe them.
   */
  procedure apply_extra_headers(
    p_settings in t_settings
  );

  /*
   * Shallow-merge p_settings.extra_body (uc_ai.g_extra_body / "g_extra_body"
   * config key) onto an already-built request body object. Top-level keys
   * override whatever the framework set; nested objects replace wholesale.
   * Call AFTER the provider set its own framework keys and BEFORE messages /
   * model / system are added, so those reserved keys cannot be clobbered.
   * No-op when extra_body is null.
   */
  procedure apply_extra_body(
    pio_input_obj in out nocopy json_object_t
  , p_settings    in t_settings
  );

  /*
   * Fresh, zero-initialised run state for a single generate_text call.
   */
  function new_run_state return t_run_state;

end uc_ai_settings;
/
