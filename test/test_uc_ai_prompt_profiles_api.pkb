create or replace package body test_uc_ai_prompt_profiles_api as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  
  gc_test_code constant varchar2(50 char) := 'TEST_PROFILE';

  procedure setup
  as
  begin
    -- Clean up any existing test data
    delete from uc_ai_prompt_profiles where code like 'TEST_%';
  end setup;

  procedure teardown
  as
  begin
    -- Clean up test data
    delete from uc_ai_prompt_profiles where code like 'TEST_%';
  end teardown;


  procedure create_basic_profile
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code,
      p_description => 'Test profile for basic creation',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Answer this question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 1,
      p_status => 'draft'
    );

    -- Verify ID was returned
    ut.expect(l_id).to_be_not_null();
    ut.expect(l_id).to_be_greater_than(0);

    -- Retrieve and verify the profile
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);
    
    ut.expect(l_profile.code).to_equal(gc_test_code);
    ut.expect(l_profile.version).to_equal(1);
    ut.expect(l_profile.status).to_equal('draft');
    ut.expect(l_profile.provider).to_equal(uc_ai.c_provider_openai);
    ut.expect(l_profile.model).to_equal(uc_ai_openai.c_model_gpt_4o_mini);
    ut.expect(l_profile.created_by).to_be_not_null(); -- Set by trigger

    sys.dbms_output.put_line('Created profile with ID: ' || l_id);
  end create_basic_profile;


  procedure create_profile_with_config
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
    l_config clob := '{
      "g_enable_reasoning": true,
      "openai": {
        "g_reasoning_effort": "medium"
      }
    }';
    l_response_schema clob := '{
      "type": "object",
      "properties": {
        "answer": {"type": "string"},
        "confidence": {"type": "number"}
      },
      "required": ["answer", "confidence"]
    }';
  begin

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_CONFIG',
      p_description => 'Test profile with configuration',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Answer: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_model_config_json => l_config,
      p_response_schema => l_response_schema
    );

    -- Verify profile was created with config
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);
    
    ut.expect(l_profile.model_config_json).to_be_not_null();
    ut.expect(l_profile.response_schema).to_be_not_null();
    
    sys.dbms_output.put_line('Created profile with config, ID: ' || l_id);
  end create_profile_with_config;


  procedure update_profile_by_id
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
    l_new_description varchar2(4000 char) := 'Updated description via ID';
  begin
    -- Create a profile first
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_UPDATE',
      p_description => 'Original description',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    -- Update the profile
    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_id => l_id,
      p_description => l_new_description,
      p_system_prompt_template => 'You are a very helpful assistant.',
      p_user_prompt_template => 'Please answer: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o
    );

    -- Verify the update
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);
    
    ut.expect(l_profile.description).to_equal(l_new_description);
    ut.expect(l_profile.model).to_equal(uc_ai_openai.c_model_gpt_4o);

    sys.dbms_output.put_line('Updated profile ID: ' || l_id);
  end update_profile_by_id;


  procedure update_profile_by_code
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
    l_new_description varchar2(4000 char) := 'Updated description via code';
  begin
    -- Create a profile first
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_UPDATE2',
      p_description => 'Original description',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 1
    );

    -- Update the profile by code and version
    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_code => gc_test_code || '_UPDATE2',
      p_version => 1,
      p_description => l_new_description,
      p_system_prompt_template => 'You are a very helpful assistant.',
      p_user_prompt_template => 'Please answer: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o
    );

    -- Verify the update
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code => gc_test_code || '_UPDATE2',
      p_version => 1
    );
    
    ut.expect(l_profile.description).to_equal(l_new_description);
    ut.expect(l_profile.model).to_equal(uc_ai_openai.c_model_gpt_4o);

    sys.dbms_output.put_line('Updated profile by code/version');
  end update_profile_by_code;


  procedure delete_profile_by_id
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    -- Create a profile first
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_DELETE',
      p_description => 'Profile to delete',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    -- Delete the profile
    uc_ai_prompt_profiles_api.delete_prompt_profile(p_id => l_id);

    -- Verify deletion - should raise error
    begin
      l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);
      ut.fail('Expected no_data_found exception');
    exception
      when others then
        ut.expect(sqlcode).to_equal(-20001); -- Custom error from API
    end;

    sys.dbms_output.put_line('Deleted profile ID: ' || l_id);
  end delete_profile_by_id;


  procedure delete_profile_by_code
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    -- Create a profile first
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_DELETE2',
      p_description => 'Profile to delete',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 1
    );

    -- Delete the profile by code and version
    uc_ai_prompt_profiles_api.delete_prompt_profile(
      p_code => gc_test_code || '_DELETE2',
      p_version => 1
    );

    -- Verify deletion - should raise error
    begin
      l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
        p_code => gc_test_code || '_DELETE2',
        p_version => 1
      );
      ut.fail('Expected no_data_found exception');
    exception
      when others then
        ut.expect(sqlcode).to_equal(-20001);
    end;

    sys.dbms_output.put_line('Deleted profile by code/version');
  end delete_profile_by_code;


  procedure change_profile_status
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    -- Create a profile
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_STATUS',
      p_description => 'Status test profile',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_status => 'draft'
    );

    -- Change to active
    uc_ai_prompt_profiles_api.change_status(
      p_id => l_id,
      p_status => 'active'
    );

    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);
    ut.expect(l_profile.status).to_equal('active');

    -- Change to archived
    uc_ai_prompt_profiles_api.change_status(
      p_id => l_id,
      p_status => 'archived'
    );

    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);
    ut.expect(l_profile.status).to_equal('archived');

    sys.dbms_output.put_line('Changed status successfully');
  end change_profile_status;


  procedure create_new_profile_version
  as
    l_id_v1 number;
    l_id_v2 number;
    l_profile_v1 uc_ai_prompt_profiles%rowtype;
    l_profile_v2 uc_ai_prompt_profiles%rowtype;
  begin
    -- Create version 1
    l_id_v1 := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_VERSION',
      p_description => 'Version 1',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 1,
      p_status => 'active'
    );

    -- Create version 2 from version 1
    l_id_v2 := uc_ai_prompt_profiles_api.create_new_version(
      p_code => gc_test_code || '_VERSION',
      p_source_version => 1,
      p_new_version => 2
    );

    -- Verify both versions exist
    l_profile_v1 := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code => gc_test_code || '_VERSION',
      p_version => 1
    );
    
    l_profile_v2 := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code => gc_test_code || '_VERSION',
      p_version => 2
    );

    ut.expect(l_profile_v1.version).to_equal(1);
    ut.expect(l_profile_v2.version).to_equal(2);
    ut.expect(l_profile_v2.status).to_equal('draft'); -- New version starts as draft
    ut.expect(l_profile_v2.description).to_equal(l_profile_v1.description);
  end create_new_profile_version;


  procedure get_profile_by_id
  as
    l_id number;
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    -- Create a profile
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_GET',
      p_description => 'Get test profile',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini
    );

    -- Get profile by ID
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_id => l_id);

    ut.expect(l_profile.id).to_equal(l_id);
    ut.expect(l_profile.code).to_equal(gc_test_code || '_GET');
  end get_profile_by_id;


  procedure get_profile_latest_active
  as
    -- @dblinter ignore(g-2120): l_id_v3 intentionally unused - created to test version selection
    l_id_v1 number;
    l_id_v2 number;
    l_id_v3 number;
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    -- Create multiple versions
    l_id_v1 := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_LATEST',
      p_description => 'Version 1',
      p_system_prompt_template => 'You are a helpful assistant v1.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 1,
      p_status => 'active'
    );

    l_id_v2 := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_LATEST',
      p_description => 'Version 2',
      p_system_prompt_template => 'You are a helpful assistant v2.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 2,
      p_status => 'active'
    );

    l_id_v3 := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_LATEST',
      p_description => 'Version 3',
      p_system_prompt_template => 'You are a helpful assistant v3.',
      p_user_prompt_template => 'Question: #question#',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_version => 3,
      p_status => 'draft' -- Not active
    );

    -- Get latest active (should return version 2)
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code => gc_test_code || '_LATEST',
      p_version => null
    );

    ut.expect(l_profile.version).to_equal(2);
    ut.expect(l_profile.status).to_equal('active');

    -- Verify v3 was created but is draft
    ut.expect(l_id_v3).to_be_greater_than(0);
  end get_profile_latest_active;


  procedure execute_simple_profile
  as
    l_id number;
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
  begin
    uc_ai.g_enable_tools := false; -- Disable tools for this test
    uc_ai.g_enable_reasoning := false;

    -- Create a simple profile
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_EXEC',
      p_description => 'Simple execution test',
      p_system_prompt_template => 'You are a helpful assistant that answers in short sentences.',
      p_user_prompt_template => 'What is 2 + 2?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_status => 'active'
    );

    -- Execute the profile
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code => gc_test_code || '_EXEC'
    );

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);

    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%4%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    ut.expect(l_messages.get_size).to_equal(3); -- system, user, assistant

    uc_ai_test_message_utils.validate_message_array(l_messages, 'Simple profile execution');
  end execute_simple_profile;


  procedure execute_profile_with_placeholders
  as
    l_id number;
    l_result json_object_t;
    l_final_message clob;
    l_parameters json_object_t;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create profile with placeholders
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_PLACEHOLDERS',
      p_description => 'Profile with placeholders',
      p_system_prompt_template => 'You are a #role# assistant.',
      p_user_prompt_template => 'What is the capital of #country#?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_status => 'active'
    );

    -- Create parameters
    l_parameters := json_object_t();
    l_parameters.put('role', 'geography');
    l_parameters.put('country', 'France');

    -- Execute with parameters
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code => gc_test_code || '_PLACEHOLDERS',
      p_parameters => l_parameters
    );

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);

    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%paris%');

    uc_ai_test_message_utils.validate_message_array(
      treat(l_result.get('messages') as json_array_t),
      'Profile execution with placeholders'
    );
  end execute_profile_with_placeholders;


  procedure execute_profile_with_config
  as
    l_id number;
    l_result json_object_t;
    l_final_message clob;
    l_config clob;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create config with specific settings
    l_config := '{
      "g_enable_reasoning": true,
      "g_reasoning_level": "low"
    }';

    uc_ai.g_enable_reasoning := false; -- Ensure global is off to test profile config
    uc_ai.g_reasoning_level := null;

    -- Create profile with config
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_CONFIG_EXEC',
      p_description => 'Profile with model config',
      p_system_prompt_template => 'You are a concise assistant.',
      p_user_prompt_template => 'In one word, what color is the sky?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_o4_mini,
      p_model_config_json => l_config,
      p_status => 'active'
    );

    -- Execute the profile (config should be applied)
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code => gc_test_code || '_CONFIG_EXEC'
    );

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);

    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%blue%');

    ut.expect(uc_ai.g_enable_reasoning).to_equal(true);
    ut.expect(uc_ai.g_reasoning_level).to_equal(uc_ai.c_reasoning_level_low);
  end execute_profile_with_config;


  procedure execute_profile_structured_output
  as
    l_id number;
    l_result json_object_t;
    l_final_message clob;
    l_structured_output json_object_t;
    l_response_schema clob;
    l_answer varchar2(4000 char);
    l_confidence number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create response schema
    l_response_schema := '{
      "type": "object",
      "properties": {
        "answer": {"type": "string"},
        "confidence": {"type": "number", "minimum": 0, "maximum": 1}
      },
      "required": ["answer", "confidence"],
      "additionalProperties": false
    }';

    -- Create profile with structured output
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_STRUCTURED',
      p_description => 'Profile with structured output',
      p_system_prompt_template => 'You are a helpful assistant. Respond with confidence level.',
      p_user_prompt_template => 'What is the capital of Germany?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_response_schema => l_response_schema,
      p_status => 'active'
    );

    -- Execute the profile
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code => gc_test_code || '_STRUCTURED'
    );

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);

    ut.expect(l_final_message).to_be_not_null();

    -- Parse structured output
    l_structured_output := json_object_t(l_final_message);
    l_answer := l_structured_output.get_string('answer');
    l_confidence := l_structured_output.get_number('confidence');

    ut.expect(lower(l_answer)).to_be_like('%berlin%');
    ut.expect(l_confidence).to_be_between(0, 1);

    sys.dbms_output.put_line('Answer: ' || l_answer);
    sys.dbms_output.put_line('Confidence: ' || l_confidence);
  end execute_profile_structured_output;


  procedure execute_profile_with_override
  as
    l_id number;
    l_result json_object_t;
    l_final_message clob;
    l_model varchar2(255 char);
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create profile with one model
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_OVERRIDE',
      p_description => 'Profile for override test',
      p_system_prompt_template => 'You are a helpful assistant.',
      p_user_prompt_template => 'What is 5 + 5?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_status => 'active'
    );

    -- Execute with model override
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code => gc_test_code || '_OVERRIDE',
      p_model_override => uc_ai_openai.c_model_gpt_4o
    );

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);

    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%10%');

    uc_ai_test_message_utils.validate_message_array(
      treat(l_result.get('messages') as json_array_t),
      'Profile execution with override'
    );

    l_model := l_result.get_string('model');
    ut.expect(l_model).to_be_like(uc_ai_openai.c_model_gpt_4o || '%');
  end execute_profile_with_override;


  procedure execute_profile_with_tools
  as
    l_id number;
    l_result json_object_t;
    l_final_message clob;
    l_tool_calls_count pls_integer;
    l_messages json_array_t;
    l_config clob;
  begin
    -- Setup tools
    delete from uc_ai_tool_parameters where 1 = 1;
    delete from uc_ai_tools where 1 = 1;
    uc_ai_test_utils.add_get_users_tool;

    l_config := '{
      "g_enable_tools": true,
      "g_enable_reasoning": false
    }';

    -- Create profile that requires tool usage
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code => gc_test_code || '_TOOLS',
      p_description => 'Profile with tool usage',
      p_system_prompt_template => 'You are an assistant with access to user information. Answer concisely.',
      p_user_prompt_template => 'What is the email of #user_name#?',
      p_provider => uc_ai.c_provider_openai,
      p_model => uc_ai_openai.c_model_gpt_4o_mini,
      p_status => 'active',
      p_model_config_json => l_config
    );

    -- Create parameters
    declare
      l_parameters json_object_t := json_object_t();
    begin
      l_parameters.put('user_name', 'Jim');

      -- Execute profile
      l_result := uc_ai_prompt_profiles_api.execute_profile(
        p_code => gc_test_code || '_TOOLS',
        p_parameters => l_parameters,
        p_max_tool_calls => 5
      );
    end;

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Response: ' || l_final_message);

    ut.expect(l_final_message).to_be_not_null();
    ut.expect(lower(l_final_message)).to_be_like('%jim.halpert@dundermifflin.com%');

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    ut.expect(l_tool_calls_count).to_be_greater_than(0);

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_message_utils.validate_message_array(l_messages, 'Profile execution with tools');

    sys.dbms_output.put_line('Tool calls made: ' || l_tool_calls_count);
  end execute_profile_with_tools;

end test_uc_ai_prompt_profiles_api;
/
