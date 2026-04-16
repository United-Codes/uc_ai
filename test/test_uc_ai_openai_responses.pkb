create or replace package body test_uc_ai_openai_responses as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  


  procedure setup_tests
  as
  begin
    uc_ai.g_provider_override := null;
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    
    -- Configure Responses API settings
    uc_ai_responses_api.g_store_responses := true;
    uc_ai_responses_api.g_include_encrypted_reasoning := false;
  end setup_tests;


  procedure test_simple_string_input
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    l_result := uc_ai.GENERATE_TEXT(
      p_system_prompt => 'You are a helpful assistant.',
      p_user_prompt => 'Say "Hello, Responses API!" and nothing else.',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%hello%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    ut.expect(l_messages.get_size).to_be_greater_than(0);

    sys.dbms_output.put_line('Last message: ' || l_final_message);

    uc_ai_test_message_utils.validate_message_array(l_messages, 'Simple string input test');

    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3); -- system message + user message + assistant response
  end test_simple_string_input;


  procedure test_multi_turn_conversation
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_content json_array_t := json_array_t();
    l_message_count pls_integer;
  begin
    -- Test simple conversation pattern
    l_result := uc_ai.GENERATE_TEXT(
      p_system_prompt => 'You are a helpful assistant.',
      p_user_prompt => 'Remember this number: 42. Say "I will remember 42".',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%42%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Multi-turn conversation test');

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    l_content.append(uc_ai_message_api.create_text_content(
      'What number did I ask you to remember?'
    ));

    l_messages.append(
      uc_ai_message_api.create_user_message(l_content)
    );

   l_result := uc_ai.GENERATE_TEXT(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_like('%42%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(5); -- system message + (user message + assistant response) * 2

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Basic recipe Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');
  end test_multi_turn_conversation;


  procedure test_function_calling
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_tool_calls_count pls_integer;
  begin
    delete from UC_AI_TOOLS where 1 = 1;
    uc_ai_test_utils.add_get_users_tool;

    uc_ai.g_enable_tools := true;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user information.',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%jim.halpert@dundermifflin.com%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Function calling test');

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_equal(1);

    uc_ai.g_enable_tools := false;
  end test_function_calling;


  procedure test_tool_clock_in_user
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

    -- delete all time entries for Michael Scott (to avoid error "already clocked in")
    select user_id into l_user_id from TT_USERS where email = 'michael.scott@dundermifflin.com';
    delete from TT_TIME_ENTRIES where user_id = l_user_id;

    uc_ai.g_enable_tools := true; -- enable tools usage

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.
        The current user is Michael Scott.

        If you clock somebody in, answer with: "You are now clocked in to the project "{{project_name}}" with the note "{{notes| - }}".', 
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%now clocked in%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- multiple tool calls
    ut.expect(l_message_count).to_be_greater_than(5);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool Clock in user Test');

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_be_greater_than(1);

    uc_ai.g_enable_tools := false;
  end test_tool_clock_in_user;


  procedure test_structured_output
  as
    l_schema json_object_t;
    l_result json_object_t;
    l_final_message clob;
    l_structured_output json_object_t;
    l_messages json_array_t;
  begin
    -- Use confidence schema from test utils
    l_schema := uc_ai_test_utils.get_confidence_json_schema();

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France? Please respond with confidence.',
      p_system_prompt => 'You are a helpful assistant that provides accurate information.',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_response_json_schema => l_schema
    );

    ut.expect(l_result).to_be_not_null();

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);
    ut.expect(l_final_message).to_be_not_null();

    l_structured_output := json_object_t(l_final_message);
    
    ut.expect(l_structured_output.has('response')).to_equal(true);
    ut.expect(l_structured_output.has('confidence')).to_equal(true);
    ut.expect(lower(l_structured_output.get_string('response'))).to_be_like('%paris%');
    ut.expect(l_structured_output.get_number('confidence')).to_be_between(0, 1);

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Structured output test');

    sys.dbms_output.put_line('Structured Response: ' || l_structured_output.get_string('response'));
    sys.dbms_output.put_line('Confidence: ' || l_structured_output.get_number('confidence'));
  end test_structured_output;


  procedure test_pdf_file_input
  as
    l_messages json_array_t := json_array_t();
    l_content json_array_t := json_array_t();
    l_result json_object_t;
    l_res_clob clob;
    l_final_message clob;
  begin
    l_messages.append(uc_ai_message_api.create_system_message(
      'You are an assistant answering trivia questions about TV Shows. Please answer in super short sentences.'));

    l_content.append(uc_ai_message_api.create_file_content(
      p_media_type => 'application/pdf',
      p_data_blob => uc_ai_test_utils.get_emp_pdf,
      p_filename => 'data.pdf'
    ));

    l_content.append(uc_ai_message_api.create_text_content(
      'Which is the TV show of the characters that are inside the attached PDF?'
    ));

    l_messages.append(uc_ai_message_api.create_user_message(l_content));

    uc_ai_test_message_utils.validate_message_array(l_messages, 'PDF file input before');

    l_result := uc_ai.GENERATE_TEXT(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    l_res_clob := l_result.to_clob;
    sys.dbms_output.put_line('PDF file input result: ' || substr(l_res_clob, 1, 500));

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%office%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'PDF file input response');
  end test_pdf_file_input;


  procedure test_image_file_input
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

    uc_ai_test_message_utils.validate_message_array(l_messages, 'Image file input before');

    uc_ai.g_enable_tools := false;

    l_result := uc_ai.GENERATE_TEXT(
      p_messages => l_messages,
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4_1
    );

    l_res_clob := l_result.to_clob;
    sys.dbms_output.put_line('Image file input result: ' || substr(l_res_clob, 1, 500));

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%apple%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Image file input response');

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
  end test_image_file_input;


  procedure test_instructions
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
  begin
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Hello!',
      p_system_prompt => 'You are a pirate. Always respond like a pirate.',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%ahoy%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Instructions test');

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);
  end test_instructions;


  procedure test_reasoning_config
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := true;
    uc_ai_responses_api.g_reasoning_effort := 'medium';
    uc_ai_responses_api.g_reasoning_summary := null;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is 123 * 456?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_5
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(replace(lower(l_final_message), ',')).to_be_like('%56088%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Reasoning config test');

    uc_ai.g_enable_reasoning := false;
  end test_reasoning_config;


  procedure test_encrypted_reasoning
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := true;
    uc_ai_responses_api.g_store_responses := false;
    uc_ai_responses_api.g_include_encrypted_reasoning := true;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Think about prime numbers and tell me the 10th prime number.',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_5
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%29%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(
      p_messages => l_messages, p_test_name => 'Encrypted reasoning test', p_should_have_reasoning => true
    );

    -- Cleanup
    uc_ai.g_enable_reasoning := false;
    uc_ai_responses_api.g_store_responses := true;
    uc_ai_responses_api.g_include_encrypted_reasoning := false;
  end test_encrypted_reasoning;

end test_uc_ai_openai_responses;
/
