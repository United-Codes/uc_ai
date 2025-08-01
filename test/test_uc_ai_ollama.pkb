create or replace package body test_uc_ai_ollama as

  c_model_qwen_1b constant uc_ai.model_type := 'qwen3:1.7b';
  c_model_qwen_4b constant uc_ai.model_type := 'qwen3:4b';
  c_model_gemma3_4b constant uc_ai.model_type := 'gemma3:4b';

  procedure basic_recipe (
    p_model in uc_ai.model_type,
    p_base_url in varchar2 default 'host.containers.internal:11434/api',
    p_reasoning_enabled in boolean default true
  )
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    uc_ai.g_base_url := p_base_url;
    uc_ai.g_enable_reasoning := p_reasoning_enabled;
    uc_ai.g_enable_tools := false;
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please just list 3 possible dishe names without instructions.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => p_model
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

  procedure tool_user_info(
    p_model in uc_ai.model_type,
    p_base_url in varchar2 default 'host.containers.internal:11434/api',
    p_reasoning_enabled in boolean default true
  )
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

    uc_ai.g_base_url := p_base_url;
    uc_ai.g_enable_reasoning := p_reasoning_enabled;
    uc_ai.g_enable_tools := true;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => p_model
    );
    logger.log('UC AI result', 'Tool User Info Test ', l_result.to_string);

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

  procedure tool_clock_in_user(
    p_model in uc_ai.model_type,
    p_base_url in varchar2 default 'host.containers.internal:11434/api',
    p_reasoning_enabled in boolean default true
  )
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

    uc_ai.g_base_url := p_base_url;
    uc_ai.g_enable_reasoning := p_reasoning_enabled;
    uc_ai.g_enable_tools := true;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user and project information. You can also clock in a user. Make sure to validate the user and project before clocking in.
        
        The current user is Michael Scott.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => p_model
    );
    logger.log('UC AI result', 'Tool Clock In User Test ', l_result.to_string);

    l_final_message := l_result.get_clob('final_message');

    -- most likely the model will just give up; in this case l_final_message will be null
    if l_final_message is null then
      sys.dbms_output.put_line('No final message returned, assuming model gave up.');
    end if;

    --ut.expect(l_final_message).to_be_not_null();

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
  end tool_clock_in_user;

  procedure convert_messages
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_test_utils.get_tool_user_messages();

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_result, 'Convert messages test');

    ut.expect(l_result.get_size).to_be_greater_than(0);
  end convert_messages;

  -- Test procedures for specific models
  procedure basic_recipe_qwen_1b
  as
  begin
    basic_recipe(p_model => c_model_qwen_1b);
  end basic_recipe_qwen_1b;

  procedure basic_recipe_gemma_4b
  as
  begin
    basic_recipe(p_model => c_model_gemma3_4b, p_reasoning_enabled => false);
  end basic_recipe_gemma_4b;

  procedure tool_user_info_qwen_4b
  as
  begin
    tool_user_info(p_model => c_model_qwen_4b);
  end tool_user_info_qwen_4b;

  procedure tool_clock_in_user_qwen_4b
  as
  begin
    tool_clock_in_user(p_model => c_model_qwen_4b);
  end tool_clock_in_user_qwen_4b;


  procedure image_file_input_gemma_4b
  as
    l_messages json_array_t := json_array_t();
    l_content json_array_t := json_array_t();
    l_result json_object_t;
    l_res_clob clob;
    l_final_message clob;
  begin
    l_messages.append(uc_ai_message_api.create_system_message(
      'You are an image analysis assistant.'));

    l_content.append(uc_ai_message_api.create_file_content(
      p_media_type => 'image/webp',
      p_data_blob => uc_ai_test_utils.get_apple_webp,
      p_filename => 'data.webp'
    ));

    l_content.append(uc_ai_message_api.create_text_content(
      'What is the fruit depicted in the attached image?'
    ));

    l_messages.append(uc_ai_message_api.create_user_message(l_content));
    

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Image file input before');

    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false; -- disable tools for this test
    uc_ai.g_enable_reasoning := false; -- disable reasoning for this test

    l_result := uc_ai.generate_text(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model_gemma3_4b
    );

    l_res_clob := l_result.to_clob;
    logger.log_info(p_text => 'Image file input result:', p_extra => l_res_clob);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%apple%');

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Image file input response');

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
  end image_file_input_gemma_4b;

end test_uc_ai_ollama;
/
