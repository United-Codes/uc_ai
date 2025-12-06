create or replace package body test_uc_ai_xai as
  -- @dblinter ignore(g-5010): allow logger in test packages
  
  procedure basic_recipe
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What an I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please answer in short sentences.',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3);

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe test');

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
    delete from UC_AI_TOOLS where 1 = 1;
    uc_ai_test_utils.add_get_users_tool;

    uc_ai.g_enable_tools := true; -- enable tools usage

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%jim.halpert@dundermifflin.com%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- system proppt, user, tool call, tool_response, assistant
    ut.expect(l_message_count).to_equal(5);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool User Info Test');

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_equal(1);

    --ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

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
    uc_ai_test_utils.add_get_users_tool;
    uc_ai_test_utils.add_get_projects_tool;
    uc_ai_test_utils.add_clock_tools;

    -- delete all time entries for Michael Scott (to avouid error "aleady clocked in")
    select user_id into l_user_id from TT_USERS where email = 'michael.scott@dundermifflin.com';
    delete from TT_TIME_ENTRIES where user_id = l_user_id;

    uc_ai.g_enable_tools := true; -- enable tools usage

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.
        The current user is Michael Scott.

        If you clock somebody in, answer with: "You are now clocked in to the project "{{project_name}}" with the note "{{notes| - }}".',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_reasoning,
      p_max_tool_calls => 5
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%now clocked in%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- multiple cool calls
    ut.expect(l_message_count).to_be_greater_than(5);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool Clock in user Test');

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_be_greater_than(1);

    --ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

  end tool_clock_in_user;


  procedure tool_clock_in_user_eror_handling
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_tool_calls_count pls_integer;
  begin
    delete from UC_AI_TOOLS where 1 = 1;
    uc_ai_test_utils.add_get_users_tool;
    uc_ai_test_utils.add_get_projects_tool;
    uc_ai_test_utils.add_clock_tools;


    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.
        The current user is Michael Scott.

        If you clock somebody in, answer with: "You are now clocked in to the project "{{project_name}}" with the note "{{notes| - }}".',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%now clocked in%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- multiple cool calls
    ut.expect(l_message_count).to_be_greater_than(5);

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_be_greater_than(1);

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

  end tool_clock_in_user_eror_handling;


  procedure convert_messages
  as
    l_messages json_array_t;
    l_result json_object_t;
    l_final_message clob;
    l_message_count pls_integer;
  begin
    l_messages := uc_ai_test_utils.get_tool_user_messages;

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Convert Messages Test before');

    l_result := uc_ai.generate_text(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning,
      p_max_tool_calls => 3
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%jim.halpert@dundermifflin.com%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- system proppt, user, tool call, tool_response, + new: assistant
    ut.expect(l_message_count).to_equal(5);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Convert Messages Test response');
  end convert_messages;

  procedure pdf_file_input
  as
    l_messages json_array_t := json_array_t();
    l_content json_array_t := json_array_t();
    l_result json_object_t;
    l_res_clob clob;
    l_final_message clob;
  begin
    l_messages.append(uc_ai_message_api.create_system_message(
      'You are an assistant answering trivia questions about TV Shows. Please answeer in super short sentences.'));

    l_content.append(uc_ai_message_api.create_file_content(
      p_media_type => 'application/pdf',
      p_data_blob => uc_ai_test_utils.get_emp_pdf,
      p_filename => 'data.pdf'
    ));

    l_content.append(uc_ai_message_api.create_text_content(
      'Which is the TV show of the characters that are inside the attached PDF?'
    ));

    l_messages.append(uc_ai_message_api.create_user_message(l_content));
    

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'PDF file input before');

    uc_ai.g_enable_tools := false; 

    l_result := uc_ai.generate_text(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning,
      p_max_tool_calls => 3
    );

    l_res_clob := l_result.to_clob;
    logger.log_info(p_text => 'PDF file input result:', p_extra => l_res_clob);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%office%');

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'PDF file input response');
  end pdf_file_input;

  procedure image_file_input
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

    uc_ai.g_enable_tools := false; -- disable tools for this test

    l_result := uc_ai.generate_text(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning,
      p_max_tool_calls => 3
    );

    l_res_clob := l_result.to_clob;
    logger.log_info(p_text => 'Image file input result:', p_extra => l_res_clob);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%apple%');

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Image file input response');

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
  end image_file_input;


  procedure reasoning
  as
    l_messages json_array_t := json_array_t();
    l_result json_object_t;
    l_message_count pls_integer;
    l_final_message clob;
  begin
    uc_ai.g_enable_reasoning := true; -- enable reasoning for this test
    uc_ai_xai.g_reasoning_effort := 'low'; -- set reasoning effort

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Answer in one sentence. If there is a great filter, are we before or after it and why.',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%filter%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Reasoning Response');
    l_message_count := l_messages.get_size;
    -- One user message and one assistant message are expected
    -- OpenAI adds no reasoning messages
    ut.expect(l_message_count).to_equal(2);

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

  end reasoning;


  procedure reasoning_main
  as
    l_messages json_array_t := json_array_t();
    l_result json_object_t;
    l_message_count pls_integer;
    l_final_message clob;
  begin
    uc_ai.g_enable_tools := false; -- disable tools for this test
    uc_ai_xai.g_reasoning_effort := null;
    uc_ai.g_enable_reasoning := true; -- enable reasoning for this test
    uc_ai.g_reasoning_level := 'low';

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Answer in one sentence. If there is a great filter, are we before or after it and why.',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%filter%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Reasoning Response');
    l_message_count := l_messages.get_size;
    -- One user message and one assistant message are expected
    -- xAI adds no reasoning messages
    ut.expect(l_message_count).to_equal(2);

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');

  end reasoning_main;

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
    l_schema := uc_ai_test_utils.get_confidence_json_schema();

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France? Please respond with confidence.',
      p_system_prompt => 'You are a helpful assistant that provides accurate information.',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning,
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

  procedure basic_web_credential
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    uc_ai_xai.g_apex_web_credential := 'OPENAI'; -- name of the APEX web credential
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What an I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please answer in short sentences.',
      p_provider => uc_ai.c_provider_xai,
      p_model => uc_ai_xai.c_model_grok_4_fast_non_reasoning
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3);

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end basic_web_credential;

end test_uc_ai_xai;
/
