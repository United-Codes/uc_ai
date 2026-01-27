create or replace package uc_ai_agent_exec_api as
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
  -- Conversation Modes
  -- ============================================================================

  c_conversation_round_robin constant varchar2(20 char) := 'round_robin';
  c_conversation_ai_driven   constant varchar2(20 char) := 'ai_driven';


  -- ============================================================================
  -- Pattern Execution Functions
  -- ============================================================================

  /*
   * Executes a profile-type agent (wrapper around prompt profile)
   *
   * @param p_agent        Agent rowtype record
   * @param p_input_params Input parameters for the agent
   * @param p_exec_id         Execution ID for tracking
   * @param p_response_schema Optional JSON schema for response validation
   * @return JSON result from prompt profile execution
   */
  function execute_profile_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_exec_id        in uc_ai_agent_executions.id%type,
    p_response_schema in json_object_t default null
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
   * @param p_agent        Agent rowtype record
   * @param p_input_params Input parameters for orchestration
   * @param p_session_id   Session ID for grouping executions
   * @param p_exec_id      Execution ID for tracking
   * @return JSON result from orchestration
   */
  function execute_orchestrator_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
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
    p_tool_tag         in varchar2
  ) return uc_ai_tools.id%type;


  /*
   * Cleans up temporary tools created for an execution
   *
   * @param p_exec_id Execution ID to clean up tools for
   */
  procedure cleanup_agent_tools(
    p_exec_id in uc_ai_agent_executions.id%type
  );


  procedure create_apex_session_if_needed;

end uc_ai_agent_exec_api;
/
