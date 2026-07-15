create or replace package uc_ai_agents_api 
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

  -- Status constants
  c_status_draft    constant uc_ai_agents.status%type := 'draft';
  c_status_active   constant uc_ai_agents.status%type := 'active';
  c_status_archived constant uc_ai_agents.status%type := 'archived';

  -- Agent type constants
  c_type_profile      constant uc_ai_agents.agent_type%type := 'profile';
  c_type_workflow     constant uc_ai_agents.agent_type%type := 'workflow';
  c_type_orchestrator constant uc_ai_agents.agent_type%type := 'orchestrator';
  c_type_handoff      constant uc_ai_agents.agent_type%type := 'handoff';
  c_type_conversation constant uc_ai_agents.agent_type%type := 'conversation';

  -- Workflow type constants
  c_workflow_sequential  constant varchar2(50 char) := 'sequential';
  c_workflow_conditional constant varchar2(50 char) := 'conditional';
  c_workflow_parallel    constant varchar2(50 char) := 'parallel';
  c_workflow_loop        constant varchar2(50 char) := 'loop';

  -- Conversation mode constants
  c_conversation_round_robin constant varchar2(50 char) := 'round_robin';
  c_conversation_ai_driven   constant varchar2(50 char) := 'ai_driven';

  -- History management strategy constants
  c_history_full           constant varchar2(50 char) := 'full';
  c_history_sliding_window constant varchar2(50 char) := 'sliding_window';
  c_history_summarize      constant varchar2(50 char) := 'summarize';

  -- Execution status constants
  c_exec_pending   constant varchar2(50 char) := 'pending';
  c_exec_running   constant varchar2(50 char) := 'running';
  c_exec_completed constant varchar2(50 char) := 'completed';
  c_exec_failed    constant varchar2(50 char) := 'failed';
  c_exec_timeout   constant varchar2(50 char) := 'timeout';

  -- ============================================================================
  -- Types
  -- ============================================================================

  type t_validation_result is record (
    is_valid     boolean,
    error_reason varchar2(4000 char)
  );

  -- ============================================================================
  -- Session Management
  -- ============================================================================

  /*
   * Generates a new session ID for grouping related agent executions
   * 
   * @return  A unique session ID (based on SYS_GUID)
   */
  function generate_session_id return varchar2;

  -- ============================================================================
  -- Agent Management
  -- ============================================================================

  /*
   * Creates a new agent
   * 
   * @param p_code                   Unique code for the agent
   * @param p_description            Description of the agent
   * @param p_agent_type             Type: 'profile', 'workflow', 'orchestrator', 'handoff', 'conversation'
   * @param p_prompt_profile_code    For profile agents: code of the referenced prompt profile
   * @param p_prompt_profile_version For profile agents: version (null = latest active)
   * @param p_workflow_definition    JSON workflow definition for workflow agents
   * @param p_orchestration_config   JSON config for orchestrator/handoff/conversation agents
   * @param p_input_schema           Optional JSON schema for input validation
   * @param p_output_schema          Optional JSON schema for output validation
   * @param p_timeout_seconds        Optional execution timeout
   * @param p_max_iterations         Optional max iterations for loops
   * @param p_max_history_messages   Optional max conversation history messages
   * @param p_version                Version number (default 1)
   * @param p_status                 Status: 'draft', 'active', or 'archived' (default 'draft')
   * 
   * @return id                      The ID of the created agent
   */
  function create_agent(
    p_code                   in uc_ai_agents.code%type,
    p_description            in uc_ai_agents.description%type,
    p_agent_type             in uc_ai_agents.agent_type%type,
    p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
    p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
    p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
    p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
    p_input_schema           in uc_ai_agents.input_schema%type default null,
    p_output_schema          in uc_ai_agents.output_schema%type default null,
    p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
    p_max_iterations         in uc_ai_agents.max_iterations%type default null,
    p_max_history_messages   in uc_ai_agents.max_history_messages%type default null,
    p_version                in uc_ai_agents.version%type default 1,
    p_status                 in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type;


  /*
   * Updates an existing agent by ID
   * 
   * @param p_id                     ID of the agent to update
   * @param p_description            Description of the agent
   * @param p_prompt_profile_code    For profile agents: code of the referenced prompt profile
   * @param p_prompt_profile_version For profile agents: version (null = latest active)
   * @param p_workflow_definition    JSON workflow definition for workflow agents
   * @param p_orchestration_config   JSON config for orchestrator/handoff/conversation agents
   * @param p_input_schema           Optional JSON schema for input validation
   * @param p_output_schema          Optional JSON schema for output validation
   * @param p_timeout_seconds        Optional execution timeout
   * @param p_max_iterations         Optional max iterations for loops
   * @param p_max_history_messages   Optional max conversation history messages
   */
  procedure update_agent(
    p_id                     in uc_ai_agents.id%type,
    p_description            in uc_ai_agents.description%type default null,
    p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
    p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
    p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
    p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
    p_input_schema           in uc_ai_agents.input_schema%type default null,
    p_output_schema          in uc_ai_agents.output_schema%type default null,
    p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
    p_max_iterations         in uc_ai_agents.max_iterations%type default null,
    p_max_history_messages   in uc_ai_agents.max_history_messages%type default null
  );


  /*
   * Deletes an agent by ID
   * Raises an error if the agent is referenced by other agents
   * 
   * @param p_id  ID of the agent to delete
   */
  procedure delete_agent(
    p_id in uc_ai_agents.id%type
  );


  /*
   * Deletes an agent by code and version
   * Raises an error if the agent is referenced by other agents
   * 
   * @param p_code     Code of the agent
   * @param p_version  Version number
   */
  procedure delete_agent(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type
  );


  /*
   * Changes the status of an agent by ID
   * 
   * @param p_id      ID of the agent
   * @param p_status  New status: 'draft', 'active', or 'archived'
   */
  procedure change_status(
    p_id     in uc_ai_agents.id%type,
    p_status in uc_ai_agents.status%type
  );


  /*
   * Changes the status of an agent by code and version
   * 
   * @param p_code     Code of the agent
   * @param p_version  Version number
   * @param p_status   New status: 'draft', 'active', or 'archived'
   */
  procedure change_status(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type,
    p_status  in uc_ai_agents.status%type
  );


  /*
   * Creates a new version of an existing agent
   * 
   * @param p_code           Code of the existing agent
   * @param p_source_version Source version to copy from
   * @param p_new_version    New version number (if null, increments by 1)
   * 
   * @return id              The ID of the new agent version
   */
  function create_new_version(
    p_code           in uc_ai_agents.code%type,
    p_source_version in uc_ai_agents.version%type,
    p_new_version    in uc_ai_agents.version%type default null
  ) return uc_ai_agents.id%type;


  /*
   * Gets an agent by ID
   * 
   * @param p_id  ID of the agent
   * 
   * @return      The agent record
   */
  function get_agent(
    p_id in uc_ai_agents.id%type
  ) return uc_ai_agents%rowtype;


  /*
   * Gets an agent by code and version
   * 
   * @param p_code     Code of the agent
   * @param p_version  Version number (if null, returns the latest active version)
   * 
   * @return           The agent record
   */
  function get_agent(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type default null
  ) return uc_ai_agents%rowtype;


  -- ============================================================================
  -- Validation Functions
  -- ============================================================================

  /*
   * Validates that all agent_code references in workflow/orchestration configs exist
   * 
   * @param p_workflow_definition   JSON workflow definition
   * @param p_orchestration_config  JSON orchestration config
   * 
   * @return  t_validation_result with is_valid flag and error_reason if invalid
   */
  function validate_agent_references(
    p_workflow_definition  in clob default null,
    p_orchestration_config in clob default null
  ) return t_validation_result;


  /*
   * Checks if an agent is referenced by other agents
   * Raises an exception if the agent is referenced
   * 
   * @param p_agent_code  Code of the agent to check
   */
  procedure check_agent_not_referenced(
    p_agent_code in uc_ai_agents.code%type
  );


  /*
   * Validates a workflow definition JSON
   * 
   * @param p_workflow_definition  The JSON workflow definition to validate
   * 
   * @return  Validation result with is_valid flag and error_reason (if invalid)
   */
  function validate_workflow_definition(
    p_workflow_definition in clob
  ) return t_validation_result;


  /*
   * Validates an orchestration config JSON
   * 
   * @param p_orchestration_config  The JSON orchestration config to validate
   * 
   * @return  Validation result with is_valid flag and error_reason (if invalid)
   */
  function validate_orchestration_config(
    p_orchestration_config in clob
  ) return t_validation_result;


  -- ============================================================================
  -- Workflow-Specific Functions
  -- ============================================================================

  /*
   * Creates a sequential workflow agent
   * 
   * @param p_code         Unique code for the workflow
   * @param p_description  Description of the workflow
   * @param p_agent_steps  JSON array of agent codes in execution order
   * @param p_status       Status: 'draft', 'active', or 'archived' (default 'draft')
   * 
   * @return id            The ID of the created workflow agent
   */
  function create_sequential_workflow(
    p_code        in uc_ai_agents.code%type,
    p_description in uc_ai_agents.description%type,
    p_agent_steps in json_array_t,
    p_status      in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type;


  /*
   * Creates a parallel workflow agent
   * 
   * @param p_code                 Unique code for the workflow
   * @param p_description          Description of the workflow
   * @param p_agent_steps          JSON array of agent codes to execute in parallel
   * @param p_aggregation_strategy Aggregation strategy: 'merge', 'array', 'first' (default 'merge')
   * @param p_status               Status: 'draft', 'active', or 'archived' (default 'draft')
   * 
   * @return id                    The ID of the created workflow agent
   */
  function create_parallel_workflow(
    p_code                 in uc_ai_agents.code%type,
    p_description          in uc_ai_agents.description%type,
    p_agent_steps          in json_array_t,
    p_aggregation_strategy in varchar2 default 'merge',
    p_status               in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type;


  -- ============================================================================
  -- Execution Hooks (generic extension point)
  -- ============================================================================

  /*
   * Registers a package that receives execution lifecycle callbacks around the
   * top-level of execute_agent. This is a general-purpose extension point
   * (budgeting, auditing, rate-limiting, ...); this package stays agnostic of
   * what the hook does.
   *
   * The hook package must implement:
   *
   *   procedure before_execution(
   *     p_agent_id    in number,     -- uc_ai_agents.id
   *     p_agent_code  in varchar2,   -- uc_ai_agents.code
   *     p_created_by  in varchar2,   -- coalesce(APEX user, DB user) of the caller
   *     p_apex_app_id in number,     -- APEX application id (null outside APEX)
   *     p_session_id  in varchar2    -- execution session id
   *   );
   *   -- Called before any execution row is created or tokens are spent.
   *   -- May RAISE to veto the execution (e.g. a budget hard-cap); the exception
   *   -- propagates out of execute_agent and no run happens.
   *
   *   procedure after_execution(
   *     p_exec_id       in number,   -- top-level uc_ai_agent_executions.id
   *     p_status        in varchar2, -- 'completed' or 'failed'
   *     p_input_tokens  in number,
   *     p_output_tokens in number
   *   );
   *   -- Called after the top-level execution finishes (success or failure).
   *   -- Best-effort: exceptions raised here are logged and swallowed so a
   *   -- completed run is never turned into a failure by the hook.
   *
   * The hook package MAY additionally implement (optional — a package without it
   * is detected and simply not called, so existing hooks keep working):
   *
   *   procedure before_tool_call(
   *     p_agent_id    in number,     -- uc_ai_agents.id (null if called standalone)
   *     p_agent_code  in varchar2,   -- uc_ai_agents.code (null if called standalone)
   *     p_tool_code   in varchar2,   -- uc_ai_tools.code about to be executed
   *     p_created_by  in varchar2,   -- coalesce(APEX user, DB user) of the caller
   *     p_session_id  in varchar2,   -- execution session id (null if standalone)
   *     p_apex_app_id in number      -- APEX application id (null outside APEX)
   *   );
   *   -- Called before EACH tool call inside a generate_text tool-calling loop
   *   -- (fired at the provider call sites, before provider-local error handling).
   *   -- May RAISE to veto the tool call mid-run; the exception propagates out of
   *   -- generate_text and stops the run. Fires for agent runs and standalone
   *   -- generate_text tool calls alike (context fields null in the latter).
   *
   *   procedure augment_system_prompt(
   *     pio_system_prompt in out nocopy clob  -- rendered profile system prompt (may be null)
   *   );
   *   -- Called after a prompt profile's system prompt template has been
   *   -- rendered (placeholders substituted), before the model call. May append
   *   -- to or rewrite the prompt (e.g. inject standing instructions); it may
   *   -- also set a prompt where the profile had none. Fires for every
   *   -- uc_ai_prompt_profiles_api.execute_profile call, which covers agent
   *   -- first turns (profile/orchestrator/workflow-nested agents); follow-up
   *   -- turns reuse the persisted system message from the conversation
   *   -- history, so an augmentation made on the first turn travels with the
   *   -- session. Standalone generate_text calls with a raw p_system_prompt are
   *   -- NOT augmented. Read uc_ai.get_exec_context inside the hook to know
   *   -- which agent is running (fields null outside an agent run). Dispatch is
   *   -- best-effort: errors are logged and swallowed and the prompt is used
   *   -- unchanged — this hook cannot veto a run.
   *
   * Resolution: if no override is set, the hook is auto-resolved by convention
   * to a VALID package named UC_AI_HOOK in the current schema (so simply
   * installing an extension that provides UC_AI_HOOK activates it, with no
   * per-session registration). Pass an explicit name to override the
   * convention; pass NULL to clear the override and fall back to the convention.
   *
   * @param p_package_name Hook package name (schema-qualified allowed). Null clears the override.
   */
  procedure set_execution_hook(p_package_name in varchar2 default null);

  /*
   * Fires the optional per-tool-call hook (before_tool_call) on the resolved hook
   * package, if that package implements it. Called by uc_ai_tools_api at each
   * provider tool-call site, immediately before a tool runs. Exceptions PROPAGATE
   * by design: a hook raising here (e.g. a rate-limit hard-cap) vetoes the tool
   * call and stops the run. No-ops when no hook is resolved or the hook package
   * does not implement before_tool_call.
   *
   * @param p_tool_code   uc_ai_tools.code about to be executed
   * @param p_agent_id    calling agent id (null if standalone generate_text)
   * @param p_agent_code  calling agent code (null if standalone generate_text)
   * @param p_created_by  caller (coalesced to the DB session user if unknown)
   * @param p_session_id  execution session id (null if standalone)
   * @param p_apex_app_id APEX application id (null outside APEX)
   */
  procedure fire_before_tool_hook(
    p_tool_code   in varchar2
  , p_agent_id    in number   default null
  , p_agent_code  in varchar2 default null
  , p_created_by  in varchar2 default null
  , p_session_id  in varchar2 default null
  , p_apex_app_id in number   default null
  );

  /*
   * Fires the optional system-prompt augmentation hook (augment_system_prompt)
   * on the resolved hook package, if that package implements it. Called by
   * uc_ai_prompt_profiles_api.execute_profile after the profile's system
   * prompt template has been rendered. Best-effort by design: hook errors are
   * logged and swallowed and the prompt is left unchanged, so a broken
   * augmenter can never fail a run. No-ops when no hook is resolved or the
   * hook package does not implement augment_system_prompt.
   *
   * @param pio_system_prompt  the rendered system prompt; the hook may modify it
   */
  procedure fire_augment_prompt_hook(
    pio_system_prompt in out nocopy clob
  );


  -- ============================================================================
  -- Agent Execution
  -- ============================================================================

  /*
   * Executes an agent by code
   *
   * @param p_agent_code        Code of the agent to execute
   * @param p_agent_version     Version number (null = latest active)
   * @param p_input_parameters  JSON input parameters
   * @param p_follow_up_message Follow-up message to continue an existing conversation (profile/orchestrator/handoff
   *                            agents; handoff agents resume with the agent that answered the previous turn)
   * @param p_session_id        Optional session ID for grouping executions (required when using p_follow_up_message)
   * @param p_parent_exec_id    Optional parent execution ID for nested calls
   * @param p_response_schema   Optional JSON schema for response validation (profile agents only)
   * @param p_files             Optional files (documents/images) to attach to the user message
   *                            (profile/orchestrator agents only). Build with uc_ai_message_api.t_files.
   * @param p_extra_tool_tag    Engine-internal: extra tool tag merged into the profile's model
   *                            config (profile agents only; used for handoff transfer tools)
   *
   * @return                    JSON result object
   */
  function execute_agent(
    p_agent_code        in uc_ai_agents.code%type,
    p_agent_version     in uc_ai_agents.version%type default null,
    p_input_parameters  in json_object_t default null,
    p_follow_up_message in clob default null,
    p_session_id        in varchar2 default null,
    p_parent_exec_id    in uc_ai_agent_executions.id%type default null,
    p_response_schema   in json_object_t default null,
    p_files             in uc_ai_message_api.t_files default null,
    p_extra_tool_tag    in varchar2 default null
  ) return json_object_t;


  /*
   * Executes an agent by ID
   *
   * @param p_agent_id          ID of the agent to execute
   * @param p_input_parameters  JSON input parameters
   * @param p_follow_up_message Follow-up message to continue an existing conversation (profile/orchestrator/handoff
   *                            agents; handoff agents resume with the agent that answered the previous turn)
   * @param p_session_id        Optional session ID for grouping executions (required when using p_follow_up_message)
   * @param p_parent_exec_id    Optional parent execution ID for nested calls
   * @param p_response_schema   Optional JSON schema for response validation (profile agents only)
   * @param p_files             Optional files (documents/images) to attach to the user message
   *                            (profile/orchestrator agents only). Build with uc_ai_message_api.t_files.
   * @param p_extra_tool_tag    Engine-internal: extra tool tag merged into the profile's model
   *                            config (profile agents only; used for handoff transfer tools)
   *
   * @return                    JSON result object
   */
  function execute_agent(
    p_agent_id          in uc_ai_agents.id%type,
    p_input_parameters  in json_object_t default null,
    p_follow_up_message in clob default null,
    p_session_id        in varchar2 default null,
    p_parent_exec_id    in uc_ai_agent_executions.id%type default null,
    p_response_schema   in json_object_t default null,
    p_files             in uc_ai_message_api.t_files default null,
    p_extra_tool_tag    in varchar2 default null
  ) return json_object_t;


  /*
   * Persists a mid-run state checkpoint for a running execution into
   * uc_ai_agent_executions.current_state.
   *
   * Commits in an autonomous transaction so running workflows can be monitored
   * from other sessions and failed/crashed runs keep their last known state.
   * Cleared automatically when the execution completes successfully.
   * Best-effort: never raises.
   *
   * @param p_exec_id       ID of the running execution
   * @param p_current_state Current workflow state (stored as a copy)
   * @param p_last_step     Optional marker of the last completed step
   */
  procedure checkpoint_execution(
    p_exec_id       in uc_ai_agent_executions.id%type,
    p_current_state in json_object_t,
    p_last_step     in varchar2 default null
  );


  -- ============================================================================
  -- Execution History
  -- ============================================================================

  /*
   * Gets the execution history with optional filters
   * 
   * @param p_session_id  Filter by session ID
   * @param p_agent_code  Filter by agent code
   * @param p_status      Filter by execution status
   * @param p_start_date  Filter by start date (from)
   * @param p_end_date    Filter by end date (to)
   * 
   * @return              Cursor with execution records
   */
  function get_execution_history(
    p_session_id in varchar2 default null,
    p_agent_code in uc_ai_agents.code%type default null,
    p_status     in varchar2 default null,
    p_start_date in timestamp default null,
    p_end_date   in timestamp default null
  ) return sys_refcursor;


  /*
   * Gets detailed information about a specific execution
   * 
   * @param p_execution_id  ID of the execution
   * 
   * @return                JSON object with execution details
   */
  function get_execution_details(
    p_execution_id in uc_ai_agent_executions.id%type
  ) return json_object_t;


  /*
   * Lists conversation sessions (one row per session_id) with maintained
   * aggregates (turn/message counts, summed token usage, last status/activity).
   * The conversation-level counterpart to get_execution_history.
   *
   * @param p_agent_code  Filter by the session's root agent code
   * @param p_status      Filter by the session's latest status
   * @param p_created_by  Filter by the opening user
   * @param p_start_date  Filter by session start date (from)
   * @param p_end_date    Filter by session start date (to)
   *
   * @return              Cursor with one row per session
   */
  function list_sessions(
    p_agent_code in uc_ai_agents.code%type default null,
    p_status     in varchar2 default null,
    p_created_by in varchar2 default null,
    p_start_date in timestamp default null,
    p_end_date   in timestamp default null
  ) return sys_refcursor;


  /*
   * Returns the full, untrimmed message log of a session in conversation order
   * (one row per message content item).
   *
   * @param p_session_id  The session to read
   *
   * @return              Cursor with the ordered message rows
   */
  function get_session_messages(
    p_session_id in varchar2
  ) return sys_refcursor;

end uc_ai_agents_api;
/
