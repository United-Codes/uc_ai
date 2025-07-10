create or replace package uc_ai_test_message_utils as

  procedure validate_message_array(
    p_messages in json_array_t,
    p_test_name in varchar2 default 'Message Array Validation'
  );

  procedure validate_content_array(
    p_content in json_array_t,
    p_message_index in pls_integer,
    p_test_name in varchar2,
    p_role in varchar2
  );

  procedure validate_text_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  );

  procedure validate_file_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  );

  procedure validate_reasoning_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  );

  procedure validate_tool_call_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  );

  procedure validate_tool_result_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  );

end uc_ai_test_message_utils;
/
