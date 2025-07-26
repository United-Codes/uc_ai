create or replace package body test_uc_ai_ollama as

  c_model_qwen constant uc_ai.model_type := 'qwen3:1.7b';

  procedure basic_recipe
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please just list 3 possible dishe names without instructions.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model_qwen
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3); -- System, user, assistant message

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end basic_recipe;

  procedure tool_user_info
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_tool_calls_count pls_integer;
  begin
    delete from UC_AI_TOOL_PARAMETERS where 1 = 1;
    delete from UC_AI_TOOLS where 1 = 1;
    uc_ai_test_utils.add_get_users_tool();

    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model_qwen
    );
    logger.log('Response', 'Tool User Info Test ', l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_be_greater_than(2); -- Should have tool calls

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    ut.expect(l_tool_calls_count).to_be_greater_than(0);

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    sys.dbms_output.put_line('Last message: ' || l_final_message);
  
   -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool User Info Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end tool_user_info;

  procedure tool_clock_in_user
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_tool_calls_count pls_integer;

    l_user_id number;
  begin
    delete from UC_AI_TOOL_PARAMETERS where 1 = 1;
    delete from UC_AI_TOOLS where 1 = 1;
    uc_ai_test_utils.add_get_users_tool();
    uc_ai_test_utils.add_get_projects_tool();
    uc_ai_test_utils.add_clock_tools();

    -- delete all time entries for Michael Scott (to avoid error "already clocked in")
    select user_id into l_user_id from TT_USERS where email = 'michael.scott@dundermifflin.com';
    delete from TT_TIME_ENTRIES where user_id = l_user_id;

    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock in Michael Scott to the project that includes Dunder and Mifflin in the name.',
      p_system_prompt => 'You are an assistant to a time tracking system. You can get information on users, projects and clock users in and out.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model_qwen
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_be_greater_than(2); -- Should have tool calls

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    ut.expect(l_tool_calls_count).to_be_greater_than(0);

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

   -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool Clock In User Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end tool_clock_in_user;

  procedure convert_messages
  as
    l_result json_array_t;
    l_test_messages json_array_t := uc_ai_test_utils.get_tool_user_messages();
  begin
    l_result := uc_ai_test_utils.get_tool_user_messages();

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_result, 'Convert messages test');

    ut.expect(l_result.get_size).to_be_greater_than(0);
  end convert_messages;

end test_uc_ai_ollama;
/
