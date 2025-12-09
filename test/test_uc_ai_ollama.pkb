create or replace package body test_uc_ai_ollama as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  c_model_qwen_1b constant uc_ai.model_type := 'qwen3:1.7b';
  c_model_qwen_4b constant uc_ai.model_type := 'qwen3:4b';
  c_model_gemma3_4b constant uc_ai.model_type := 'gemma3:4b';
  c_model_gpt_oss constant uc_ai.model_type := 'gpt-oss:20b';

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

  procedure basic_recipe_gpt_oss
  as
  begin
    basic_recipe(p_model => c_model_gpt_oss, p_reasoning_enabled => false);
  end basic_recipe_gpt_oss;


  procedure tool_user_info_qwen_4b
  as
  begin
    tool_user_info(p_model => c_model_qwen_4b);
  end tool_user_info_qwen_4b;

  procedure tool_user_info_gpt_oss
  as
  begin
    tool_user_info(p_model => c_model_gpt_oss);
  end tool_user_info_gpt_oss;

  procedure tool_clock_in_user_qwen_4b
  as
  begin
    tool_clock_in_user(p_model => c_model_qwen_4b);
  end tool_clock_in_user_qwen_4b;

  procedure tool_clock_in_user_gpt_oss
  as
  begin
    tool_clock_in_user(p_model => c_model_gpt_oss);
  end tool_clock_in_user_gpt_oss;

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


  procedure reasoning
  as
    l_messages json_array_t := json_array_t();
    l_result json_object_t;
    l_message_count pls_integer;
    l_final_message clob;
    l_second_message json_object_t;
    l_second_message_content json_array_t;
    l_content json_object_t;
    l_reasoning_message_found boolean := false;
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false; -- disable tools for this test
    uc_ai.g_enable_reasoning := true; -- enable reasoning for this test

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Answer in one sentence. If there is a great filter, are we before or after it and why.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model_qwen_4b
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%filter%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Reasoning response');
    l_message_count := l_messages.get_size;
    -- One user message and one assistant message are expected
    ut.expect(l_message_count).to_equal(2);

    l_second_message := treat(l_messages.get(1) as json_object_t);
    ut.expect(l_second_message.get_string('role')).to_equal('assistant');

    l_second_message_content := l_second_message.get_array('content');
    ut.expect(l_second_message_content.get_size).to_equal(2);

    <<assistant_content_loop>>
    for i in 0 .. l_second_message_content.get_size - 1 
    loop
      l_content := treat(l_second_message_content.get(i) as json_object_t);
      case l_content.get_string('type')
         when 'reasoning' then
            sys.dbms_output.put_line('Reasoning content: ' || l_content.get_clob('text'));
           l_reasoning_message_found := true;
         when 'text' then
            null;
         else
            sys.dbms_output.put_line('Unknown content type: ' || l_content.get_string('type'));
           ut.expect(false, 'Unknown content type in reasoning response: ' || l_content.get_string('type')).to_equal(true);
      end case;
    end loop assistant_content_loop;

    ut.expect(l_reasoning_message_found, 'No reasoning message found in response').to_equal(true);

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

  end reasoning;


  procedure structured_output
  as
    l_result json_object_t;
    l_schema json_object_t;
    l_final_message clob;
    l_structured_output json_object_t;
    l_messages json_array_t;
    l_message_count pls_integer;

    l_response clob;
    l_confidence number;
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false; -- disable tools for this test
    uc_ai.g_enable_reasoning := true; -- enable reasoning for this test

    l_schema := uc_ai_test_utils.get_confidence_json_schema();

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France? Please respond with confidence.',
      p_system_prompt => 'You are a helpful assistant that provides accurate information.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model_qwen_4b,
      p_response_json_schema => l_schema
    );

    -- Test that we received a result
    ut.expect(l_result).to_be_not_null();

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);
    
    -- Test that we received a final message
    ut.expect(l_final_message).to_be_not_null();

    -- Test that the response is valid JSON
    l_structured_output := json_object_t(l_final_message);

    l_response := l_structured_output.get_string('response');
    l_confidence := l_structured_output.get_number('confidence');

    -- Test the response content
    ut.expect(lower(l_response)).to_be_like('%paris%');

    -- Test confidence is a number between 0 and 1
    ut.expect(l_confidence).to_be_between(0, 1);

    -- Test message structure
    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3); -- system, user, assistant

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Structured Output Test');

    if l_structured_output is not null then
      sys.dbms_output.put_line('Structured Response: ' || l_structured_output.get_string('response'));
      sys.dbms_output.put_line('Confidence: ' || l_structured_output.get_number('confidence'));
    else
      sys.dbms_output.put_line('No structured output received');
    end if;
  end structured_output;

  procedure embeddings
  as
    l_result json_array_t;
    l_array_clob clob;
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false; -- disable tools for this test
    uc_ai.g_enable_reasoning := false; -- disable reasoning for this test

    l_result := uc_ai.generate_embeddings(
      p_input => json_array_t('["APEX Office Print lets you create and manage print jobs directly from your APEX applications."]'),
      p_provider => uc_ai.c_provider_ollama,
      p_model => 'granite-embedding:30m'
    );
    

    l_array_clob := l_result.to_clob;
    ut.expect(l_array_clob).to_be_not_null();
    sys.dbms_output.put_line('Embeddings array: ' || l_array_clob);
    ut.expect(l_result.get_size).to_equal(1);
    ut.expect(treat(l_result.get(0) as json_array_t).get_size).to_be_greater_than(0);
  end embeddings;

  procedure embeddings_multi
  as
    l_result json_array_t;
    l_array_clob clob;
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    l_result := uc_ai.generate_embeddings(
      p_input => json_array_t('["APEX Office Print lets you create and manage print jobs.", "Oracle Database is the world leading relational database.", "PL/SQL is a procedural extension to SQL."]'),
      p_provider => uc_ai.c_provider_ollama,
      p_model => 'granite-embedding:30m'
    );

    l_array_clob := l_result.to_clob;
    ut.expect(l_array_clob).to_be_not_null();
    sys.dbms_output.put_line('Multi embeddings count: ' || l_result.get_size);
    ut.expect(l_result.get_size).to_equal(3);
    -- Check each embedding has values
    ut.expect(treat(l_result.get(0) as json_array_t).get_size).to_be_greater_than(0);
    ut.expect(treat(l_result.get(1) as json_array_t).get_size).to_be_greater_than(0);
    ut.expect(treat(l_result.get(2) as json_array_t).get_size).to_be_greater_than(0);
  end embeddings_multi;

end test_uc_ai_ollama;
/
