create or replace package uc_ai_agent_workflow_api as
  /*
   * UC AI Agent Workflow API
   * 
   * Internal helper package for agent workflow operations.
   * Contains utility functions for input/output mapping,
   * condition evaluation, and conversation history management.
   *
   * Copyright 2024 United Codes GmbH
   * SPDX-License-Identifier: MIT
   */


  -- ============================================================================
  -- History Management Strategies
  -- ============================================================================

  c_history_full           constant varchar2(20 char) := 'full';
  c_history_sliding_window constant varchar2(20 char) := 'sliding_window';
  c_history_summarize      constant varchar2(20 char) := 'summarize';


  -- ============================================================================
  -- Workflow Helper Functions
  -- ============================================================================

  function evaluate_final_message(
    p_final_message in json_element_t,
    p_workflow_state in json_object_t
  ) return varchar2;

  /*
   * Evaluates a condition expression against workflow state
   *
   * @param p_condition      JSON object with condition configuration
   * @param p_workflow_state Current workflow state for evaluation
   * @return Boolean result of condition evaluation
   */
  function evaluate_condition(
    p_condition      in varchar2,
    p_workflow_state in json_object_t
  ) return boolean;


  /*
   * Maps input parameters based on input_mapping configuration
   *
   * Use cases:
   * - Loop workflows where feedback from previous iteration may not exist in first iteration
   * - Conditional workflows where certain inputs may not always be available
   * - Workflows with progressive enhancement of data
   *
   * @param p_input_mapping  JSON object defining input mappings
   * @param p_workflow_state Current workflow state
   * @param p_original_input Original input parameters
   * @return Mapped input parameters
   */
  function map_inputs(
    p_input_mapping  in json_object_t,
    p_workflow_state in json_object_t
  ) return json_object_t;


  /*
   * Merges step output into workflow state based on output_mapping
   *
   * @param p_step             JSON object defining the current step
   * @param p_step_output      Output from the current step
   * @param pio_workflow_state Workflow state to merge into (in/out)
   */
  procedure add_result_to_workflow_state(
    p_step             in json_object_t,
    p_step_output      in json_object_t,
    pio_workflow_state in out nocopy json_object_t
  );


  /*
   * Manages conversation history based on strategy
   *
   * @param p_history            Current conversation history
   * @param p_history_management JSON object with history management config
   * @param p_session_id         Session ID for context
   * @return Managed history array
   */
  function manage_history(
    p_history            in json_array_t,
    p_history_management in json_object_t,
    p_session_id         in varchar2
  ) return json_array_t;

end uc_ai_agent_workflow_api;
/
