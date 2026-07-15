create or replace package uc_ai_test_agent_utils as

  /**
  * Utility procedures for agent tests
  */

  procedure create_math_profile;

  procedure create_profiles;

  -- Creates the customer-support profiles for handoff tests: a triage agent
  -- plus product (with get_product_details tool), shipping, and customer
  -- details specialists.
  procedure create_support_profiles;

  -- Cleans up all test data
  procedure cleanup_test_data;

  -- Deletes agents matching a code pattern together with their execution
  -- rows (including child executions of other agents spawned by them).
  -- Needed because execution telemetry commits autonomously and survives
  -- test rollbacks.
  procedure delete_agents_cascade(
    p_code_pattern in varchar2
  );

  -- Validates agent result has required fields
  procedure validate_agent_result(
    p_result    in json_object_t,
    p_test_name in varchar2
  );

  -- Validates execution was recorded
  procedure validate_execution_recorded(
    p_session_id in varchar2,
    p_test_name  in varchar2
  );

  -- Validates execution captured the caller's environment context
  procedure validate_execution_context(
    p_session_id in varchar2,
    p_test_name  in varchar2
  );

end uc_ai_test_agent_utils;
/
