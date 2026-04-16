create or replace package body test_uc_ai_agent_orchestrator as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_orchestrator_code constant varchar2(50 char) := 'TEST_ORCHESTRATOR';
  gc_math_agent_code   constant varchar2(50 char) := 'TEST_ORCH_MATH';
  gc_geo_agent_code    constant varchar2(50 char) := 'TEST_ORCH_GEO';

  procedure setup
  as
    l_id number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create required prompt profiles
    --uc_ai_test_agent_utils.create_math_profile;
    uc_ai_test_agent_utils.create_profiles;

    -- Create math profile agent
    begin
      select id into l_id from uc_ai_agents where code = gc_math_agent_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_math_agent_code,
          p_description         => 'Math agent for orchestrator',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Create geography profile agent
    begin
      select id into l_id from uc_ai_agents where code = gc_geo_agent_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_geo_agent_code,
          p_description         => 'Geography agent for orchestrator',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_GEO',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;
  end setup;

  procedure teardown
  as
  begin
    uc_ai_test_agent_utils.cleanup_test_data;
  end teardown;

  procedure execute_orchestrator_routing
  as
    l_orchestrator_id number;
    l_session_id      varchar2(100 char);
    l_result          json_object_t;
    l_final_msg       clob;
    l_status          varchar2(50 char);
    l_orch_config     clob;
    l_agent_id        number;

    l_input_schema json_object_t;
  begin
    -- Create travel delegate agents
    l_input_schema := json_object_t('{
      "$schema": "http://json-schema.org/draft-07/schema#",
      "type": "object",
      "properties": {
        "prompt": {
          "type": "string",
          "description": "Relevant context for the agent to perform its task"
        }
      },
      "required": ["prompt"]
    }');

    delete from uc_ai_agents where code in ('calendar_agent', 'flight_booking_agent', 'hotel_booking_agent', 'finance_agent');
    

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'calendar_agent',
      p_description         => 'Provides calendar and scheduling information',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'calendar_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'flight_booking_agent',
      p_description         => 'Provides flight booking options',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'flight_booking_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'hotel_booking_agent',
      p_description         => 'Provides hotel accommodation options',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'hotel_booking_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'finance_agent',
      p_description         => 'Reviews and approves travel budgets',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'finance_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    -- Create orchestrator config
    l_orch_config := '{
      "pattern_type": "orchestrator",
      "orchestrator_profile_code": "travel_agent_orchestrator",
      "delegate_agents": ["calendar_agent", "flight_booking_agent", "hotel_booking_agent", "finance_agent"],
      "max_delegations": 8
    }';

    -- Create the orchestrator agent
    l_orchestrator_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_orchestrator_code,
      p_description          => 'Test orchestrator agent',
      p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
      p_orchestration_config => l_orch_config,
      p_status               => uc_ai_agents_api.c_status_active
    );

    ut.expect(l_orchestrator_id).to_be_not_null();

    -- Execute with a travel planning question
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_orchestrator_code,
      p_input_parameters => json_object_t('{"prompt": "I need to travel from New York to San Francisco for a tech conference on Tuesday morning. I have a board meeting Monday until 11 AM. I prefer direct flights and hotels close to the venue. What are my best options? (Today is Monday: 12.01.2026)"}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Orchestrator travel result JSON: ' || l_result.to_clob);
    ut.expect(l_result.get_number('tool_calls_count')).to_be_greater_than(2);

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Orchestrator Travel Planning');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Orchestrator travel result: ' || l_final_msg);
    
    -- Should contain travel recommendations
    ut.expect(lower(l_final_msg)).to_be_like('%flight%');
    ut.expect(lower(l_final_msg)).to_be_like('%hotel%');
  end execute_orchestrator_routing;

  procedure execute_orchestrator_follow_up
  as
    l_orchestrator_id number;
    l_session_id      varchar2(100 char);
    l_result          json_object_t;
    l_follow_up       json_object_t;
    l_final_msg       clob;
    l_follow_msg      clob;
    l_orch_config     clob;
    l_agent_id        number;
    l_input_schema    json_object_t;
  begin
    -- Create travel delegate agents
    l_input_schema := json_object_t('{
      "$schema": "http://json-schema.org/draft-07/schema#",
      "type": "object",
      "properties": {
        "prompt": {
          "type": "string",
          "description": "Relevant context for the agent to perform its task"
        }
      },
      "required": ["prompt"]
    }');

    delete from uc_ai_agents where code in ('calendar_agent', 'flight_booking_agent', 'hotel_booking_agent', 'finance_agent');

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'calendar_agent',
      p_description         => 'Provides calendar and scheduling information',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'calendar_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'flight_booking_agent',
      p_description         => 'Provides flight booking options',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'flight_booking_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'hotel_booking_agent',
      p_description         => 'Provides hotel accommodation options',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'hotel_booking_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'finance_agent',
      p_description         => 'Reviews and approves travel budgets',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'finance_agent_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => l_input_schema.to_clob
    );

    -- Create orchestrator
    l_orch_config := '{
      "pattern_type": "orchestrator",
      "orchestrator_profile_code": "travel_agent_orchestrator",
      "delegate_agents": ["calendar_agent", "flight_booking_agent", "hotel_booking_agent", "finance_agent"],
      "max_delegations": 8
    }';

    begin
      select id into l_orchestrator_id
        from uc_ai_agents
       where code = gc_orchestrator_code || '_FOLLOWUP'
         and status = 'active';
    exception
      when no_data_found then
        l_orchestrator_id := uc_ai_agents_api.create_agent(
          p_code                 => gc_orchestrator_code || '_FOLLOWUP',
          p_description          => 'Test orchestrator for follow-up',
          p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
          p_orchestration_config => l_orch_config,
          p_status               => uc_ai_agents_api.c_status_active
        );
    end;

    -- First call
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_orchestrator_code || '_FOLLOWUP',
      p_input_parameters => json_object_t('{"prompt": "I need to travel from New York to San Francisco for a tech conference on Tuesday morning. I have a board meeting Monday until 11 AM. (Today is Monday: 12.01.2026)"}'),
      p_session_id       => l_session_id
    );

    -- Validate initial result (avoid passing full JSON to ut.expect to prevent utPLSQL buffer overflow)
    ut.expect(l_result.has('final_message'), 'Initial: should have final_message').to_be_true();
    ut.expect(l_result.has('execution_id'), 'Initial: should have execution_id').to_be_true();
    ut.expect(l_result.get_string('status'), 'Initial: status should be completed').to_equal(uc_ai_agents_api.c_exec_completed);
    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Orchestrator initial result: ' || substr(l_final_msg, 1, 500));

    -- Follow-up: ask to change preferences
    l_follow_up := uc_ai_agents_api.execute_agent(
      p_agent_code        => gc_orchestrator_code || '_FOLLOWUP',
      p_follow_up_message => 'Actually I prefer business class flights. Can you find me a business class option instead?',
      p_session_id        => l_session_id
    );

    -- Validate follow-up result
    ut.expect(l_follow_up.has('final_message'), 'Follow-up: should have final_message').to_be_true();
    ut.expect(l_follow_up.has('execution_id'), 'Follow-up: should have execution_id').to_be_true();
    ut.expect(l_follow_up.get_string('status'), 'Follow-up: status should be completed').to_equal(uc_ai_agents_api.c_exec_completed);
    l_follow_msg := l_follow_up.get_clob('final_message');
    sys.dbms_output.put_line('Orchestrator follow-up result: ' || substr(l_follow_msg, 1, 500));

    -- The follow-up should have a non-empty response (LLM content is non-deterministic)
    ut.expect(length(l_follow_msg), 'Follow-up response should not be empty').to_be_greater_than(10);

    -- Verify follow-up result contains full conversation history
    declare
      l_messages   json_array_t;
      l_msg        json_object_t;
      l_has_system boolean := false;
      l_user_count number := 0;
    begin
      ut.expect(l_follow_up.has('messages'), 'Follow-up should have messages array').to_be_true();
      l_messages := l_follow_up.get_array('messages');

      -- Should contain: system + user1 + tool calls from initial + assistant1 + user2 + possible tool calls + assistant2
      sys.dbms_output.put_line('Follow-up message count: ' || l_messages.get_size);
      ut.expect(l_messages.get_size, 'Follow-up should have full conversation history').to_be_greater_than(4);

      for i in 0 .. l_messages.get_size - 1 loop
        l_msg := treat(l_messages.get(i) as json_object_t);
        case l_msg.get_string('role')
          when 'system' then l_has_system := true;
          when 'user' then l_user_count := l_user_count + 1;
          else null;
        end case;
      end loop;

      ut.expect(l_has_system, 'Should preserve system message').to_be_true();
      ut.expect(l_user_count, 'Should have 2 user messages (initial + follow-up)').to_equal(2);
    end;

    -- Verify execution table: multiple executions with token usage
    declare
      l_parent_count    number;
      l_total_count     number;
      l_parent_input    number;
      l_parent_output   number;
      l_followup_input  number;
      l_followup_output number;
    begin
      -- Total executions in session (parent orchestrator calls + delegate child calls)
      select count(*)
        into l_total_count
        from uc_ai_agent_executions
       where session_id = l_session_id;

      ut.expect(l_total_count, 'Should have multiple executions in session').to_be_greater_than(2);

      -- Check the two parent orchestrator executions have token usage
      select count(*)
        into l_parent_count
        from uc_ai_agent_executions
       where session_id = l_session_id
         and parent_execution_id is null;

      ut.expect(l_parent_count, 'Should have 2 top-level orchestrator executions').to_equal(2);

      -- Get token usage for each parent execution (ordered by time)
      declare
        cursor c_parents is
          select total_input_tokens, total_output_tokens
            from uc_ai_agent_executions
           where session_id = l_session_id
             and parent_execution_id is null
           order by started_at;
        l_rec c_parents%rowtype;
      begin
        open c_parents;
        fetch c_parents into l_rec;
        l_parent_input := l_rec.total_input_tokens;
        l_parent_output := l_rec.total_output_tokens;
        fetch c_parents into l_rec;
        l_followup_input := l_rec.total_input_tokens;
        l_followup_output := l_rec.total_output_tokens;
        close c_parents;
      end;

      ut.expect(l_parent_input, 'Initial: input tokens > 0').to_be_greater_than(0);
      ut.expect(l_parent_output, 'Initial: output tokens > 0').to_be_greater_than(0);
      ut.expect(l_followup_input, 'Follow-up: input tokens > 0').to_be_greater_than(0);
      ut.expect(l_followup_output, 'Follow-up: output tokens > 0').to_be_greater_than(0);

      sys.dbms_output.put_line('Initial tokens: in=' || l_parent_input || ' out=' || l_parent_output);
      sys.dbms_output.put_line('Follow-up tokens: in=' || l_followup_input || ' out=' || l_followup_output);
      sys.dbms_output.put_line('Total executions in session: ' || l_total_count);
    end;
  end execute_orchestrator_follow_up;

end test_uc_ai_agent_orchestrator;
/
