create or replace package uc_ai_test_utils as

  procedure add_get_users_tool;

  procedure add_get_projects_tool;

  procedure add_clock_tools;

  function get_tool_user_messages return json_array_t;

  function get_emp_pdf return blob;

  function get_apple_webp return blob;

  function get_confidence_json_schema return json_object_t;

end uc_ai_test_utils;
/
