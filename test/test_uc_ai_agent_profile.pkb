create or replace package body test_uc_ai_agent_profile as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_profile_agent_code constant varchar2(50 char) := 'TEST_PROFILE_AGENT';

  procedure setup
  as
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create required prompt profile
    uc_ai_test_agent_utils.create_math_profile;
  end setup;

  procedure teardown
  as
  begin
    uc_ai_test_agent_utils.cleanup_test_data;
  end teardown;

  procedure execute_profile_agent
  as
    l_agent_id   number;
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
    l_status     varchar2(50 char);
  begin
    -- Create a profile agent wrapping the math profile
    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => gc_profile_agent_code,
      p_description         => 'Test profile agent for math',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_MATH',
      p_status              => uc_ai_agents_api.c_status_active
    );

    ut.expect(l_agent_id).to_be_not_null();

    -- Execute the agent
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_profile_agent_code,
      p_input_parameters => json_object_t('{"question": "2 + 3"}'),
      p_session_id       => l_session_id
    );

    -- Validate result structure
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Profile Agent');

    -- Check the answer contains "5"
    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_like('%5%');

    -- Verify status is completed
    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    -- Verify execution was recorded
    uc_ai_test_agent_utils.validate_execution_recorded(l_session_id, 'Profile Agent');
  end execute_profile_agent;

  procedure execute_with_parameters
  as
    l_agent_id   number;
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
    l_params     json_object_t;
  begin
    -- Create profile agent if not exists
    begin
      select id into l_agent_id
        from uc_ai_agents
       where code = gc_profile_agent_code || '_PARAMS'
         and status = 'active';
    exception
      when no_data_found then
        l_agent_id := uc_ai_agents_api.create_agent(
          p_code                => gc_profile_agent_code || '_PARAMS',
          p_description         => 'Test profile agent with params',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Execute with different math question
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_params := json_object_t();
    l_params.put('question', '10 * 5');

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_profile_agent_code || '_PARAMS',
      p_input_parameters => l_params,
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Profile with params');

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_like('%50%');
  end execute_with_parameters;

  procedure execute_follow_up_message
  as
    l_agent_id     number;
    l_session_id   varchar2(100 char);
    l_result       json_object_t;
    l_follow_up    json_object_t;
    l_final_msg    clob;
    l_follow_msg   clob;
  begin
    -- Create profile agent
    begin
      select id into l_agent_id
        from uc_ai_agents
       where code = gc_profile_agent_code || '_FOLLOWUP'
         and status = 'active';
    exception
      when no_data_found then
        l_agent_id := uc_ai_agents_api.create_agent(
          p_code                => gc_profile_agent_code || '_FOLLOWUP',
          p_description         => 'Test profile agent for follow-up',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- First call
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_profile_agent_code || '_FOLLOWUP',
      p_input_parameters => json_object_t('{"question": "What is 15 + 27?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Follow-up initial call');
    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Initial result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_like('%42%');

    -- Follow-up call referencing the previous answer
    l_follow_up := uc_ai_agents_api.execute_agent(
      p_agent_code        => gc_profile_agent_code || '_FOLLOWUP',
      p_follow_up_message => 'Now multiply that result by 2',
      p_session_id        => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_follow_up, 'Follow-up call');
    l_follow_msg := l_follow_up.get_clob('final_message');
    sys.dbms_output.put_line('Follow-up result: ' || l_follow_msg);
    ut.expect(l_follow_msg).to_be_like('%84%');

    -- Verify follow-up result contains full conversation history
    declare
      l_messages   json_array_t;
      l_msg        json_object_t;
      l_has_system boolean := false;
      l_user_count number := 0;
      l_asst_count number := 0;
    begin
      ut.expect(l_follow_up.has('messages'), 'Follow-up should have messages array').to_be_true();
      l_messages := l_follow_up.get_array('messages');

      -- Should have: system + user1 + (tool calls from 1st) + assistant1 + user2 + (tool calls from 2nd) + assistant2
      -- At minimum: system + user + assistant + user + assistant = 5, likely more with tool calls
      sys.dbms_output.put_line('Follow-up message count: ' || l_messages.get_size);
      ut.expect(l_messages.get_size, 'Follow-up should have full conversation history').to_be_greater_than(4);

      <<message_loop>>
      for i in 0 .. l_messages.get_size - 1 loop
        l_msg := treat(l_messages.get(i) as json_object_t);
        case l_msg.get_string('role')
          when 'system' then l_has_system := true;
          when 'user' then l_user_count := l_user_count + 1;
          when 'assistant' then l_asst_count := l_asst_count + 1;
          else null;
        end case;
      end loop message_loop;

      ut.expect(l_has_system, 'Should preserve system message').to_be_true();
      ut.expect(l_user_count, 'Should have 2 user messages (initial + follow-up)').to_equal(2);
      ut.expect(l_asst_count, 'Should have 2 assistant messages').to_be_greater_or_equal(2);
    end;

    -- Verify execution table has both executions with token usage
    declare
      l_count         number;
      l_total_input   number;
      l_total_output  number;
      l_min_input     number;
    begin
      select count(*),
             sum(total_input_tokens),
             sum(total_output_tokens),
             min(total_input_tokens)
        into l_count, l_total_input, l_total_output, l_min_input
        from uc_ai_agent_executions
       where session_id = l_session_id;

      ut.expect(l_count, 'Should have 2 executions in session').to_equal(2);
      ut.expect(l_total_input, 'Total input tokens should be > 0').to_be_greater_than(0);
      ut.expect(l_total_output, 'Total output tokens should be > 0').to_be_greater_than(0);
      ut.expect(l_min_input, 'Each execution should have input tokens').to_be_greater_than(0);

      sys.dbms_output.put_line('Total input tokens: ' || l_total_input || ', output tokens: ' || l_total_output);
    end;
  end execute_follow_up_message;

  procedure follow_up_no_session_error
  as
    l_agent_id number;
    l_result   json_object_t;
  begin
    -- Create profile agent
    begin
      select id into l_agent_id
        from uc_ai_agents
       where code = gc_profile_agent_code || '_FOLLOWUP'
         and status = 'active';
    exception
      when no_data_found then
        l_agent_id := uc_ai_agents_api.create_agent(
          p_code                => gc_profile_agent_code || '_FOLLOWUP',
          p_description         => 'Test profile agent for follow-up',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Should raise error: follow_up_message without session_id
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code        => gc_profile_agent_code || '_FOLLOWUP',
      p_follow_up_message => 'This should fail'
    );
  end follow_up_no_session_error;

  procedure follow_up_no_prior_exec_error
  as
    l_agent_id number;
    l_result   json_object_t;
  begin
    -- Create profile agent
    begin
      select id into l_agent_id
        from uc_ai_agents
       where code = gc_profile_agent_code || '_FOLLOWUP'
         and status = 'active';
    exception
      when no_data_found then
        l_agent_id := uc_ai_agents_api.create_agent(
          p_code                => gc_profile_agent_code || '_FOLLOWUP',
          p_description         => 'Test profile agent for follow-up',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Should raise error: no prior execution in this session
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code        => gc_profile_agent_code || '_FOLLOWUP',
      p_follow_up_message => 'This should fail',
      p_session_id        => 'nonexistent-session-' || sys_guid()
    );
  end follow_up_no_prior_exec_error;

end test_uc_ai_agent_profile;
/
