create or replace package uc_ai_agents_api as

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
   * @return  TRUE if all references are valid
   */
  function validate_agent_references(
    p_workflow_definition  in clob default null,
    p_orchestration_config in clob default null
  ) return boolean;


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
   * @return  TRUE if valid, raises exception otherwise
   */
  function validate_workflow_definition(
    p_workflow_definition in clob
  ) return boolean;


  /*
   * Validates an orchestration config JSON
   * 
   * @param p_orchestration_config  The JSON orchestration config to validate
   * 
   * @return  TRUE if valid, raises exception otherwise
   */
  function validate_orchestration_config(
    p_orchestration_config in clob
  ) return boolean;


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
  -- Agent Execution
  -- ============================================================================

  /*
   * Executes an agent by code
   * 
   * @param p_agent_code       Code of the agent to execute
   * @param p_agent_version    Version number (null = latest active)
   * @param p_input_parameters JSON input parameters
   * @param p_session_id       Optional session ID for grouping executions
   * @param p_parent_exec_id   Optional parent execution ID for nested calls
   * 
   * @return                   JSON result object
   */
  function execute_agent(
    p_agent_code       in uc_ai_agents.code%type,
    p_agent_version    in uc_ai_agents.version%type default null,
    p_input_parameters in json_object_t default null,
    p_session_id       in varchar2 default null,
    p_parent_exec_id   in uc_ai_agent_executions.id%type default null
  ) return json_object_t;


  /*
   * Executes an agent by ID
   * 
   * @param p_agent_id         ID of the agent to execute
   * @param p_input_parameters JSON input parameters
   * @param p_session_id       Optional session ID for grouping executions
   * @param p_parent_exec_id   Optional parent execution ID for nested calls
   * 
   * @return                   JSON result object
   */
  function execute_agent(
    p_agent_id         in uc_ai_agents.id%type,
    p_input_parameters in json_object_t default null,
    p_session_id       in varchar2 default null,
    p_parent_exec_id   in uc_ai_agent_executions.id%type default null
  ) return json_object_t;


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

end uc_ai_agents_api;
/
