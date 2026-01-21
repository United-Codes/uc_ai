create or replace package uc_ai_test_message_utils as

  procedure validate_message_array(
    p_messages in json_array_t,
    p_test_name in varchar2 default 'Message Array Validation',
    p_should_have_reasoning in boolean default false
  );


  procedure valididate_return_object (
    p_response in json_object_t,
    p_test_name in varchar2 default 'Response Object Validation',
    p_should_have_reasoning in boolean default false
  );

end uc_ai_test_message_utils;
/
