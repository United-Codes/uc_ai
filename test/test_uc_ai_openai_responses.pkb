create or replace package body test_uc_ai_openai_responses as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  


  procedure setup_tests
  as
  begin
    uc_ai.g_provider_override := null;
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    
    -- Enable Responses API for OpenAI
    uc_ai_openai.g_use_responses_api := true;
    
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
    uc_ai_responses_api.g_reasoning_summary := 'concise';

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is 123 * 456?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%56088%');

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
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%29%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Encrypted reasoning test');

    -- Cleanup
    uc_ai.g_enable_reasoning := false;
    uc_ai_responses_api.g_store_responses := true;
    uc_ai_responses_api.g_include_encrypted_reasoning := false;
  end test_encrypted_reasoning;


  procedure test_message_conversion
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
  begin
    -- Test that LM-style messages work via uc_ai.GENERATE_TEXT
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Hello!',
      p_system_prompt => 'You are a helpful assistant.',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Message conversion test');

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);
  end test_message_conversion;


  procedure test_embeddings
  as
    l_result json_array_t;
    l_array_clob clob;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    l_result := uc_ai.generate_embeddings(
      p_input => json_array_t('["Hello world", "OpenAI embeddings"]'),
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_text_embedding_3_small
    );

    l_array_clob := l_result.to_clob;
    ut.expect(l_array_clob).to_be_not_null();
    sys.dbms_output.put_line('Embeddings array: ' || substr(l_array_clob, 1, 500) || '...');
    ut.expect(l_result.get_size).to_equal(2);
    ut.expect(treat(l_result.get(0) as json_array_t).get_size).to_be_greater_than(0);
    ut.expect(treat(l_result.get(1) as json_array_t).get_size).to_be_greater_than(0);
  end test_embeddings;

end test_uc_ai_openai_responses;
/
