create or replace package test_uc_ai_tools_api as

  -- %suite(Tools API tests)

  -- %beforeeach
  procedure setup_test_data;

  -- %afterall
  procedure cleanup_test_data;

  --%test(Create tool from JSON schema with various parameter types)
  procedure test_create_tool_from_schema;

  --%test(Create tool with nested object parameters)
  procedure test_create_tool_with_nested_objects;

  --%test(Create tool with array parameters)
  procedure test_create_tool_with_arrays;

  --%test(Create tool with enum parameters)
  procedure test_create_tool_with_enums;

  --%test(Tool retrieval after creation)
  procedure test_tool_retrieval;

  --%test(Create tool with tags)
  procedure test_create_tool_with_tags;



end test_uc_ai_tools_api;
/
