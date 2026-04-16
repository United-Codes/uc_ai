create or replace package uc_ai_test_agent_utils as

  /**
  * Utility procedures for agent tests
  */

  procedure create_math_profile;

  procedure create_profiles;

  -- Cleans up all test data
  procedure cleanup_test_data;

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

end uc_ai_test_agent_utils;
/
