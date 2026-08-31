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

    commit; -- agents must be committed before execution (autonomous telemetry)
  end setup;

  procedure teardown
  as
  begin
    uc_ai_test_agent_utils.cleanup_test_data;
    commit;
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

    uc_ai_test_agent_utils.delete_agents_cascade('calendar_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('flight_booking_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('hotel_booking_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('finance_agent');

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
    uc_ai_test_agent_utils.delete_agents_cascade(gc_orchestrator_code);
    l_orchestrator_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_orchestrator_code,
      p_description          => 'Test orchestrator agent',
      p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
      p_orchestration_config => l_orch_config,
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

    ut.expect(l_orchestrator_id).to_be_not_null();

    -- Execute with a travel planning question
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_orchestrator_code,
      p_input_parameters => json_object_t('{"prompt": "I need to travel from New York (departing JFK) to San Francisco for a tech conference at the Moscone Center on Tuesday morning. I have a board meeting Monday until 11 AM. I prefer direct flights and a hotel within walking distance of the Moscone Center. Please put together a complete plan with both a flight and a hotel using your specialist agents. Make reasonable assumptions and do not ask me any clarifying questions. (Today is Monday: 12.01.2026)"}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Orchestrator travel result JSON: ' || l_result.to_clob);
    -- The prompt explicitly requests both a flight and a hotel, so the
    -- orchestrator should delegate to at least two specialist agents. We assert
    -- >= 2 rather than a higher fan-out count: exactly which extra agents
    -- (calendar/finance) a reasoning model consults is model-dependent and was
    -- a source of flakiness (models increasingly return early to clarify).
    ut.expect(l_result.get_number('tool_calls_count')).to_be_greater_than(1);

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Orchestrator Travel Planning');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Orchestrator travel result: ' || l_final_msg);
    
    -- Should contain travel recommendations
    ut.expect(lower(l_final_msg)).to_be_like('%flight%');
    ut.expect(lower(l_final_msg)).to_be_like('%hotel%');

    -- ------------------------------------------------------------------
    -- Session rollup: one header, tokens summed across orchestrator + its
    -- delegate sub-agents via session_id, with no parent/child double count.
    -- ------------------------------------------------------------------
    declare
      l_sess_count    number;
      l_turn_count    number;
      l_status_hdr    varchar2(50 char);
      l_top_index     number;
      l_child_count   number;
      l_bad_child_idx number;
      l_bad_child_sid number;
      l_orch_own_in   number;
      l_child_own_in  number;
      l_sess_in       number;
      l_sess_out      number;
      l_exec_in       number;
      l_exec_out      number;
    begin
      select count(*) into l_sess_count
        from uc_ai_agent_sessions where session_id = l_session_id;
      ut.expect(l_sess_count, 'One session header for the orchestrator run').to_equal(1);

      select turn_count, status into l_turn_count, l_status_hdr
        from uc_ai_agent_sessions where session_id = l_session_id;
      ut.expect(l_turn_count, 'Only the top-level orchestrator run counts as a turn').to_equal(1);
      ut.expect(l_status_hdr, 'Session status completed').to_equal(uc_ai_agents_api.c_exec_completed);

      -- Top-level orchestrator execution is turn 1
      select turn_index into l_top_index
        from uc_ai_agent_executions
       where session_id = l_session_id and parent_execution_id is null;
      ut.expect(l_top_index, 'Top-level execution is turn 1').to_equal(1);

      -- Delegate sub-agents run under the same session, as nested (turn_index null)
      select count(*),
             count(case when turn_index is not null then 1 end),
             count(case when session_id <> l_session_id then 1 end)
        into l_child_count, l_bad_child_idx, l_bad_child_sid
        from uc_ai_agent_executions
       where parent_execution_id is not null
         and session_id = l_session_id;
      ut.expect(l_child_count, 'Orchestrator spawned delegate sub-agent executions').to_be_greater_than(0);
      ut.expect(l_bad_child_idx, 'Nested executions carry no turn_index').to_equal(0);
      ut.expect(l_bad_child_sid, 'Nested executions share the session_id').to_equal(0);

      -- Both the orchestrator and its delegates recorded their OWN tokens
      select total_input_tokens into l_orch_own_in
        from uc_ai_agent_executions
       where session_id = l_session_id and parent_execution_id is null;
      ut.expect(l_orch_own_in, 'Orchestrator recorded its own input tokens').to_be_greater_than(0);

      select nvl(sum(total_input_tokens), 0) into l_child_own_in
        from uc_ai_agent_executions
       where session_id = l_session_id and parent_execution_id is not null;
      ut.expect(l_child_own_in, 'Delegate sub-agents recorded their own input tokens').to_be_greater_than(0);

      -- Session total = SUM of every execution's own tokens (orchestrator + children)
      select total_input_tokens, total_output_tokens into l_sess_in, l_sess_out
        from uc_ai_agent_sessions where session_id = l_session_id;
      select nvl(sum(total_input_tokens), 0), nvl(sum(total_output_tokens), 0)
        into l_exec_in, l_exec_out
        from uc_ai_agent_executions where session_id = l_session_id;

      ut.expect(l_sess_in, 'Session input = SUM of orchestrator + delegate own tokens').to_equal(l_exec_in);
      ut.expect(l_sess_out, 'Session output = SUM of orchestrator + delegate own tokens').to_equal(l_exec_out);
      ut.expect(l_sess_in, 'Session input = orchestrator own + delegates own').to_equal(l_orch_own_in + l_child_own_in);
    end;

    -- ------------------------------------------------------------------
    -- Message log: delegate calls are persisted as tool_call/tool_result rows
    -- with their tool metadata (the mapping apex-chat now depends on).
    -- ------------------------------------------------------------------
    declare
      l_tool_calls    number;
      l_tool_results  number;
      l_calls_no_name number;
      l_res_no_name   number;
      l_msg_rows      number;
      l_hdr_count     number;
    begin
      select count(case when role = 'tool_call' then 1 end),
             count(case when role = 'tool_result' then 1 end),
             count(case when role = 'tool_call' and tool_name is null then 1 end),
             count(case when role = 'tool_result' and tool_name is null then 1 end),
             count(*)
        into l_tool_calls, l_tool_results, l_calls_no_name, l_res_no_name, l_msg_rows
        from uc_ai_agent_messages where session_id = l_session_id;

      ut.expect(l_tool_calls, 'Delegate tool_call rows persisted').to_be_greater_than(0);
      ut.expect(l_tool_results, 'Delegate tool_result rows persisted').to_be_greater_than(0);
      ut.expect(l_calls_no_name, 'Every tool_call row has a tool_name').to_equal(0);
      ut.expect(l_res_no_name, 'Every tool_result row has a tool_name').to_equal(0);

      select message_count into l_hdr_count
        from uc_ai_agent_sessions where session_id = l_session_id;
      ut.expect(l_hdr_count, 'Header message_count matches persisted rows').to_equal(l_msg_rows);
    end;
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

    uc_ai_test_agent_utils.delete_agents_cascade('calendar_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('flight_booking_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('hotel_booking_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('finance_agent');

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
    commit;

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

      <<history_roles>>
      for i in 0 .. l_messages.get_size - 1 loop
        l_msg := treat(l_messages.get(i) as json_object_t);
        case l_msg.get_string('role')
          when 'system' then l_has_system := true;
          when 'user' then l_user_count := l_user_count + 1;
          else null;
        end case;
      end loop history_roles;

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
        cursor l_parents_cur is
          select total_input_tokens, total_output_tokens
            from uc_ai_agent_executions
           where session_id = l_session_id
             and parent_execution_id is null
           order by started_at;
        l_rec l_parents_cur%rowtype;
      begin
        open l_parents_cur;
        fetch l_parents_cur into l_rec;
        l_parent_input := l_rec.total_input_tokens;
        l_parent_output := l_rec.total_output_tokens;
        fetch l_parents_cur into l_rec;
        l_followup_input := l_rec.total_input_tokens;
        l_followup_output := l_rec.total_output_tokens;
        close l_parents_cur;
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
