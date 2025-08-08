create or replace package body test_uc_ai_oci as


  procedure basic_recipe_generic
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    uc_ai_oci.g_compartment_id := get_oci_compratment_id;
    uc_ai_oci.g_region := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'OCI_KEY';

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please answer in short sentences.',
      p_provider => uc_ai.c_provider_oci,
      p_model => uc_ai_oci.c_model_llama_3_3_70b_instruct
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3); -- system message + user message + assistant response

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end basic_recipe_generic;


  procedure continue_conversation_generic
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_content json_array_t := json_array_t();
  begin
    uc_ai_oci.g_compartment_id := get_oci_compratment_id;
    uc_ai_oci.g_region := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'OCI_KEY';

    l_result := uc_ai.GENERATE_TEXT(
      p_system_prompt => 'Let''s count up',
      p_user_prompt => '1',
      p_provider => uc_ai.c_provider_oci,
      p_model => uc_ai_oci.c_model_llama_3_3_70b_instruct
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_like('%2%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3); -- system message + user message + assistant response

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

    l_content.append(uc_ai_message_api.create_text_content(
      '3'
    ));

    l_messages.append(
      uc_ai_message_api.create_user_message(l_content)
    );

    l_result := uc_ai.GENERATE_TEXT(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_oci,
      p_model => uc_ai_oci.c_model_llama_3_3_70b_instruct
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_like('%4%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(5); -- system message + (user message + assistant response) * 2

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end continue_conversation_generic;


  procedure tool_user_info_generic
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

    uc_ai.g_enable_tools := true;
    uc_ai_oci.g_compartment_id := get_oci_compratment_id;
    uc_ai_oci.g_region := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'OCI_KEY';

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.',
      p_provider => uc_ai.c_provider_oci,
      p_model => uc_ai_oci.c_model_llama_3_3_70b_instruct
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
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool User Info Test');


    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end tool_user_info_generic;


  procedure tool_clock_in_user_generic
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

    uc_ai.g_enable_tools := true;
    uc_ai_oci.g_compartment_id := get_oci_compratment_id;
    uc_ai_oci.g_region := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'OCI_KEY';

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.
        The current user is Michael Scott. Make sure to double check if inputs like user or project are correct.

        If you clock somebody in, answer with: "You are now clocked in to the project "{{project_name}}" with the note "{{notes| - }}".',
      p_provider => uc_ai.c_provider_oci,
      p_model => uc_ai_oci.c_model_llama_3_3_70b_instruct
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_be_greater_than(2); -- Should have tool calls

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_be_greater_than(0);

   -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool Clock in user Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

  end tool_clock_in_user_generic;


end test_uc_ai_oci;
/
