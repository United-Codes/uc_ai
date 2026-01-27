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
    ut.expect(l_result.get_number('tool_calls_count')).to_be_greater_than(3);

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

end test_uc_ai_agent_orchestrator;
/
