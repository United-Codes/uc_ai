create or replace package uc_ai_memory
  authid definer
as
  /**
  * UC AI — Agent memory (virtual filesystem)
  *
  * Persistent, provider-independent agent memory implementing the Anthropic
  * memory-tool contract (view / create / str_replace / insert / delete /
  * rename on a virtual filesystem rooted at /memories) on top of Oracle
  * tables. The MEMORY function tool dispatches into execute_command, which
  * resolves WHICH store (virtual filesystem) the caller sees from the ambient
  * execution context (uc_ai.get_exec_context) + the per-agent config in
  * uc_ai_memory_config.
  *
  * execute_command NEVER raises: per the Anthropic contract, errors are
  * returned to the model as instructive result strings. Only the admin /
  * config procedures raise.
  */

  -- Scope constants (uc_ai_memory_config.scope / uc_ai_memory_stores.scope)
  c_scope_agent   constant varchar2(50 char) := 'agent';
  c_scope_user    constant varchar2(50 char) := 'user';
  c_scope_session constant varchar2(50 char) := 'session';
  c_scope_shared  constant varchar2(50 char) := 'shared';
  c_scope_global  constant varchar2(50 char) := 'global';
  -- One store per value of a run-context key (uc_ai.t_exec_context.run_context),
  -- e.g. one memory per document in a "talk to this document" agent.
  c_scope_context constant varchar2(50 char) := 'context';

  -- Virtual filesystem root; every path lives under it
  c_root constant varchar2(20 char) := '/memories';

  -- The registered function tool (see src/post-scripts/register_memory_tool.sql)
  c_tool_code constant varchar2(255 char) := 'MEMORY';
  c_tool_tag  constant varchar2(255 char) := 'memory';

  -- Error codes (admin/config API only; execute_command never raises)
  c_err_invalid_scope   constant pls_integer := -20421;
  c_err_agent_not_found constant pls_integer := -20422;
  c_err_store_not_found constant pls_integer := -20423;
  c_err_config_invalid  constant pls_integer := -20424;
  c_err_file_not_found  constant pls_integer := -20425;

  -- Default caps applied when no config row governs the resolved store
  -- (e.g. standalone usage through set_store)
  c_default_max_file_chars constant number := 100000;
  c_default_max_files      constant number := 1000;


  -- ==========================================================================
  -- Tool entry point
  -- ==========================================================================

  /*
   * Sole entry point of the MEMORY function tool
   * (function_call = 'return uc_ai_memory.execute_command(:ARGUMENTS);').
   *
   * Dispatches on p_arguments.command (view | create | str_replace | insert |
   * delete | rename), resolves the caller's store from the execution context
   * (or the set_store session override) and executes the command against the
   * virtual filesystem. Returns the Anthropic-contract result string; ALL
   * errors — validation, missing paths, caps, unexpected exceptions — are
   * returned as instructive strings, never raised.
   */
  function execute_command(p_arguments in json_object_t) return clob;


  -- ==========================================================================
  -- Low-code enablement
  -- ==========================================================================

  /*
   * Enables memory for an agent: merges its uc_ai_memory_config row and (by
   * default) wires the 'memory' tool tag + g_enable_tools into the agent's
   * prompt profile model_config_json so the tool reaches the model.
   *
   * Profiles are versioned data: the tag is written to the profile version the
   * agent currently resolves to. Creating a NEW profile version later does not
   * carry the tag over — re-run enable_for_agent (it is idempotent). When
   * other agents reference the same profile a warning is logged (they will see
   * the memory tool but resolve their OWN stores, so no data leaks). For
   * non-profile agent types the profile wiring is skipped with a warning — add
   * the tag to the relevant profiles manually.
   *
   * @param p_agent_code      Agent to enable memory for (must exist)
   * @param p_scope           'agent' (default) | 'user' | 'session' | 'shared' | 'global' | 'context'
   * @param p_store_code      Named store, required for scope 'shared'. Optional for scope
   *                          'context': the namespace several agents can share, so they see
   *                          one memory per context value. Defaults to the agent code, which
   *                          keeps each agent's per-value stores to itself.
   * @param p_context_key     Run-context key that identifies the store, required for scope
   *                          'context' (e.g. 'document_id')
   * @param p_update_profile  Also add the memory tool tag to the agent's prompt profile (default true)
   * @param p_max_file_chars  Cap per file (default 100000)
   * @param p_max_store_chars Optional cap for the whole store (null = unlimited)
   * @param p_max_files       Cap for files per store (default 1000)
   */
  procedure enable_for_agent(
    p_agent_code      in uc_ai_agents.code%type,
    p_scope           in varchar2 default c_scope_agent,
    p_store_code      in varchar2 default null,
    p_context_key     in varchar2 default null,
    p_update_profile  in boolean  default true,
    p_max_file_chars  in number   default null,
    p_max_store_chars in number   default null,
    p_max_files       in number   default null
  );

  /*
   * Disables memory for an agent (sets the config row to enabled = 'N').
   *
   * @param p_agent_code      Agent to disable memory for
   * @param p_remove_tool_tag Remove the memory tag from the agent's profile —
   *                          skipped if another memory-enabled agent shares the
   *                          profile (default true)
   * @param p_drop_store      Also delete the agent's own stores and files
   *                          (agent + user scoped stores of this agent;
   *                          shared/global/session stores are never dropped)
   */
  procedure disable_for_agent(
    p_agent_code      in uc_ai_agents.code%type,
    p_remove_tool_tag in boolean default true,
    p_drop_store      in boolean default false
  );


  -- ==========================================================================
  -- Standalone (non-agent) usage
  -- ==========================================================================

  /*
   * Session-level store override for using the memory tool OUTSIDE an agent
   * run (plain uc_ai.generate_text with the memory tool tag): subsequent
   * execute_command calls in this session resolve to the shared store
   * p_store_code (auto-provisioned). Takes precedence over agent context.
   */
  procedure set_store(p_store_code in varchar2);

  /*
   * Clears the set_store session override.
   */
  procedure clear_store;


  -- ==========================================================================
  -- Prompt protocol
  -- ==========================================================================

  /*
   * The MEMORY PROTOCOL instruction block ("always view /memories first,
   * record progress as you go, assume interruption"). Appended to memory-
   * enabled agents' system prompts by augment_system_prompt; exposed publicly
   * so it can also be pasted into a prompt profile template manually.
   */
  function get_memory_protocol return clob;


  /*
   * Appends the MEMORY PROTOCOL block to a rendered system prompt when the
   * running agent has memory enabled. A no-op outside an agent run and for an
   * agent without an enabled uc_ai_memory_config row.
   *
   * Called by uc_ai_prompt_profiles_api.execute_profile for every profile
   * execution, which covers the first turn of profile, orchestrator and
   * workflow-nested agents. That call is best-effort: an error is logged and
   * the prompt is used unchanged, so the protocol can never fail a run. A follow-up turn reuses the system message
   * persisted in the conversation history, so the block travels with the
   * session. A standalone uc_ai.generate_text call with a raw p_system_prompt
   * is not augmented -- add get_memory_protocol to that prompt yourself.
   *
   * @param pio_system_prompt the rendered system prompt (may be null)
   */
  procedure augment_system_prompt(
    pio_system_prompt in out nocopy clob
  );


  -- ==========================================================================
  -- Admin helpers
  -- ==========================================================================

  /*
   * Resolves a store id from explicit scope parameters (for admin access to a
   * particular virtual filesystem). Raises c_err_store_not_found when the
   * store does not exist and c_err_invalid_scope for a bad scope.
   *
   * @param p_scope         'agent' | 'user' | 'session' | 'shared' | 'global' | 'context'
   * @param p_agent_code    Required for 'agent' and 'user'; the namespace default for 'context'
   * @param p_username      Required for 'user' (the run's created_by)
   * @param p_session_id    Required for 'session'
   * @param p_store_code    Required for 'shared'; optional namespace for 'context'
   * @param p_context_key   Required for 'context' (e.g. 'document_id')
   * @param p_context_value Required for 'context' (e.g. '7')
   */
  function resolve_store_id(
    p_scope         in varchar2,
    p_agent_code    in varchar2 default null,
    p_username      in varchar2 default null,
    p_session_id    in varchar2 default null,
    p_store_code    in varchar2 default null,
    p_context_key   in varchar2 default null,
    p_context_value in varchar2 default null
  ) return number;

  /*
   * Files of a store: path, char_count, created_at, updated_at,
   * last_accessed_at — ordered by path.
   */
  function list_files(p_store_id in number) return sys_refcursor;

  /*
   * Returns a file's content. Raises c_err_file_not_found when missing.
   */
  function get_file(
    p_store_id in number,
    p_path     in varchar2
  ) return clob;

  /*
   * Creates or overwrites a file (admin path, e.g. seeding memory). The path
   * is normalized and validated like tool paths; raises c_err_config_invalid
   * on an invalid path.
   */
  procedure put_file(
    p_store_id in number,
    p_path     in varchar2,
    p_content  in clob
  );

  /*
   * Deletes a single file. Raises c_err_file_not_found when missing.
   */
  procedure delete_file(
    p_store_id in number,
    p_path     in varchar2
  );

  /*
   * Deletes ALL files of a store (the store row remains).
   */
  procedure clear_store_files(p_store_id in number);

  /*
   * Housekeeping: deletes files not touched for p_days days, using
   * greatest(last_accessed_at, updated_at). All stores when p_store_id is
   * null. Does not commit.
   */
  procedure expire_files(
    p_days     in number,
    p_store_id in number default null
  );

end uc_ai_memory;
/
