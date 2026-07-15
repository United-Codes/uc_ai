create or replace package uc_ai_agent_exec_api 
  authid definer
as
  /*
   * UC AI Agent Execution API
   * 
   * Internal package for agent execution logic.
   * Contains functions to execute different agent patterns:
   * - Profile agents
   * - Workflow agents (sequential, loop, parallel)
   * - Orchestrator agents
   * - Handoff agents
   * - Conversation agents
   *
   * Copyright 2024 United Codes GmbH
   * SPDX-License-Identifier: MIT
   */


  -- ============================================================================
  -- Workflow Types
  -- ============================================================================

  c_workflow_sequential  constant varchar2(20 char) := 'sequential';
  c_workflow_conditional constant varchar2(20 char) := 'conditional';
  c_workflow_parallel    constant varchar2(20 char) := 'parallel';
  c_workflow_loop        constant varchar2(20 char) := 'loop';


  -- ============================================================================
  -- Workflow Step Types
  -- ============================================================================

  -- A step either delegates to an agent (default) or runs an inline PL/SQL snippet
  c_step_agent constant varchar2(20 char) := 'agent';
  c_step_plsql constant varchar2(20 char) := 'plsql';


  -- ============================================================================
  -- Default execution limits
  -- ============================================================================
  -- Fallbacks used when a workflow / orchestration config (and, for loops, the
  -- agent's max_iterations) does not specify its own limit.

  c_default_max_iterations constant pls_integer := 10;  -- loop workflows
  c_default_max_handoffs   constant pls_integer := 3;   -- handoff agents
  c_default_max_turns      constant pls_integer := 10;  -- conversation agents


  -- ============================================================================
  -- Conversation Modes
  -- ============================================================================

  c_conversation_round_robin constant varchar2(20 char) := 'round_robin';
  c_conversation_ai_driven   constant varchar2(20 char) := 'ai_driven';


  -- ============================================================================
  -- Session Constants
  -- ============================================================================

  -- Username of the synthetic APEX session created by create_apex_session_if_needed
  c_synthetic_apex_user constant varchar2(30 char) := 'UC_AI_AGENT_EXEC';


  -- ============================================================================
  -- Pattern Execution Functions
  -- ============================================================================

  /*
   * Executes a profile-type agent (wrapper around prompt profile)
   *
   * @param p_agent             Agent rowtype record
   * @param p_input_params      Input parameters for the agent
   * @param p_exec_id           Execution ID for tracking
   * @param p_response_schema   Optional JSON schema for response validation
   * @param p_follow_up_message Optional follow-up message for conversation continuation
   * @param p_session_id        Session ID (required for conversation continuation)
   * @param p_files             Optional files (documents/images) to attach to the user message
   * @param p_extra_tool_tag    Optional engine-supplied tool tag merged into the profile's
   *                            own model config (used by handoff agents to expose transfer tools)
   * @return JSON result from prompt profile execution
   */
  function execute_profile_agent(
    p_agent             in uc_ai_agents%rowtype,
    p_input_params      in json_object_t,
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_response_schema   in json_object_t default null,
    p_follow_up_message in clob default null,
    p_session_id        in varchar2 default null,
    p_files             in uc_ai_message_api.t_files default null,
    p_extra_tool_tag    in varchar2 default null
  ) return json_object_t;


  /*
   * Executes a workflow-type agent
   *
   * @param p_agent        Agent rowtype record
   * @param p_input_params Input parameters for the workflow
   * @param p_session_id   Session ID for grouping executions
   * @param p_exec_id      Execution ID for tracking
   * @return JSON result from workflow execution
   */
  function execute_workflow_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t;


  /*
   * Executes an orchestrator-type agent
   *
   * @param p_agent             Agent rowtype record
   * @param p_input_params      Input parameters for orchestration
   * @param p_session_id        Session ID for grouping executions
   * @param p_exec_id           Execution ID for tracking
   * @param p_follow_up_message Optional follow-up message for conversation continuation
   * @param p_files             Optional files (documents/images) to attach to the user message
   * @return JSON result from orchestration
   */
  function execute_orchestrator_agent(
    p_agent             in uc_ai_agents%rowtype,
    p_input_params      in json_object_t,
    p_session_id        in varchar2,
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_follow_up_message in clob default null,
    p_files             in uc_ai_message_api.t_files default null
  ) return json_object_t;


  /*
   * Executes a handoff-type agent
   *
   * @param p_agent        Agent rowtype record
   * @param p_input_params Input parameters for handoff chain
   * @param p_session_id   Session ID for grouping executions
   * @param p_exec_id      Execution ID for tracking
   * @return JSON result from handoff chain
   */
  function execute_handoff_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t;


  /*
   * Executes a conversation-type agent
   *
   * @param p_agent        Agent rowtype record
   * @param p_input_params Input parameters for conversation
   * @param p_session_id   Session ID for grouping executions
   * @param p_exec_id      Execution ID for tracking
   * @return JSON result from conversation
   */
  function execute_conversation_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t;


  -- ============================================================================
  -- Tool Registration (for Orchestrator pattern)
  -- ============================================================================

  /*
   * Registers a child agent as a temporary tool for orchestration
   *
   * @param p_agent_code       Code of the agent to register
   * @param p_exec_id          Execution ID for cleanup tracking
   * @param p_tool_tag         Tag to assign to the tool for identification
   * @return Tool ID of the created tool
   */
  function register_agent_as_tool(
    p_agent_code       in varchar2,
    p_exec_id          in uc_ai_agent_executions.id%type,
    p_tool_tag         in varchar2,
    p_session_id       in varchar2
  ) return uc_ai_tools.id%type;


  -- ============================================================================
  -- Transfer Requests (for Handoff pattern)
  -- ============================================================================
  -- Handoff agents expose dynamically registered transfer_to_<agent> tools to
  -- the currently active agent. The tool callback records the requested
  -- transfer here (keyed by the handoff wrapper's execution id so concurrent /
  -- nested handoff runs cannot cross-contaminate); after the agent's turn
  -- returns, execute_handoff_agent pops the request and switches agents.

  /*
   * Records a transfer request from a transfer_to_<agent> tool callback.
   * If a request already exists for the execution, the last one wins.
   *
   * @param p_handoff_exec_id Execution ID of the handoff wrapper
   * @param p_target_agent    Code of the agent to transfer to
   * @param p_context         Context summary the target agent receives
   */
  procedure record_transfer_request(
    p_handoff_exec_id in uc_ai_agent_executions.id%type,
    p_target_agent    in uc_ai_agents.code%type,
    p_context         in clob
  );

  /*
   * Returns the pending transfer request for a handoff execution and clears
   * the slot. Returns null if no transfer was requested.
   *
   * @param p_handoff_exec_id Execution ID of the handoff wrapper
   * @return JSON object {target_agent, context} or null
   */
  function pop_transfer_request(
    p_handoff_exec_id in uc_ai_agent_executions.id%type
  ) return json_object_t;

  /*
   * Clears any pending transfer request for a handoff execution.
   *
   * @param p_handoff_exec_id Execution ID of the handoff wrapper
   */
  procedure clear_transfer_request(
    p_handoff_exec_id in uc_ai_agent_executions.id%type
  );


  procedure create_apex_session_if_needed;

end uc_ai_agent_exec_api;
/
