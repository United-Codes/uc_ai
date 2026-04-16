create or replace package body test_uc_ai_ollama as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  c_model constant uc_ai.model_type := 'gemma4:26b';
  c_base_url constant varchar2(255 char) := 'https://ai.united-codes.com/api';
  c_web_credential constant varchar2(255 char) := 'OLLAMA';

  procedure setup_ollama
  as
  begin
    uc_ai.g_base_url := c_base_url;
    uc_ai.g_apex_web_credential := c_web_credential;
    uc_ai.g_enable_reasoning := false;
  end setup_ollama;

  procedure basic_recipe
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    setup_ollama;
    uc_ai.g_enable_tools := false;
    uc_ai_ollama.g_use_responses_api := false;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please just list 3 possible dish names without instructions.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model
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

    setup_ollama;
    uc_ai.g_enable_tools := true;
    uc_ai_ollama.g_use_responses_api := false;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model
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

    setup_ollama;
    uc_ai.g_enable_tools := true;
    uc_ai_ollama.g_use_responses_api := false;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user and project information. You can also clock in a user. Make sure to validate the user and project before clocking in.

        The current user is Michael Scott.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_be_greater_than(2); -- Should have tool calls

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    ut.expect(l_tool_calls_count).to_be_greater_than(0);

    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool Clock In User Test');
  end tool_clock_in_user;

  procedure basic_recipe_responses_api
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    setup_ollama;
    uc_ai.g_enable_tools := false;


    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please just list 3 possible dish names without instructions.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3); -- System, user, assistant message

    -- Validate message array structure against spec
    uc_ai_test_message_utils.valididate_return_object(p_response => l_result, p_test_name => 'Basic recipe Responses API Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');


  end basic_recipe_responses_api;

  procedure tool_user_info_responses_api
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

    setup_ollama;
    uc_ai.g_enable_tools := true;


    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model
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
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool User Info Responses API Test');

    ut.expect(lower(l_messages.to_clob)).not_to_be_like('%error%');


  end tool_user_info_responses_api;

  procedure tool_clock_in_responses_api
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

    setup_ollama;
    uc_ai.g_enable_tools := true;


    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user and project information. You can also clock in a user. Make sure to validate the user and project before clocking in.

        The current user is Michael Scott.',
      p_provider => uc_ai.c_provider_ollama,
      p_model => c_model
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_be_greater_than(2); -- Should have tool calls

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    ut.expect(l_tool_calls_count).to_be_greater_than(0);

    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Tool Clock In User Responses API Test');


  end tool_clock_in_responses_api;

  procedure convert_messages
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_test_utils.get_tool_user_messages();

    -- Validate message array structure against spec
    uc_ai_test_message_utils.validate_message_array(l_result, 'Convert messages test');

    ut.expect(l_result.get_size).to_be_greater_than(0);
  end convert_messages;

  procedure embeddings
  as
    l_result json_array_t;
    l_array_clob clob;
  begin
    setup_ollama;
    uc_ai.g_enable_tools := false;

    l_result := uc_ai.generate_embeddings(
      p_input => json_array_t('["APEX Office Print lets you create and manage print jobs directly from your APEX applications."]'),
      p_provider => uc_ai.c_provider_ollama,
      p_model => 'qwen3-embedding:8b'
    );

    l_array_clob := l_result.to_clob;
    ut.expect(l_array_clob).to_be_not_null();
    sys.dbms_output.put_line('Embeddings array: ' || substr(l_array_clob, 1, 500) || '...');
    ut.expect(l_result.get_size).to_equal(1);
    ut.expect(treat(l_result.get(0) as json_array_t).get_size).to_be_greater_than(0);
  end embeddings;

  procedure embeddings_multi
  as
    l_result json_array_t;
    l_array_clob clob;
  begin
    setup_ollama;
    uc_ai.g_enable_tools := false;

    l_result := uc_ai.generate_embeddings(
      p_input => json_array_t('["APEX Office Print lets you create and manage print jobs.", "Oracle Database is the world leading relational database.", "PL/SQL is a procedural extension to SQL."]'),
      p_provider => uc_ai.c_provider_ollama,
      p_model => 'qwen3-embedding:8b'
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
