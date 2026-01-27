create or replace package body test_uc_ai_agent_conversation as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_conversation_code constant varchar2(50 char) := 'TEST_CONVERSATION';
  gc_agent_a_code      constant varchar2(50 char) := 'TEST_CONV_A';
  gc_agent_b_code      constant varchar2(50 char) := 'TEST_CONV_B';

  procedure setup
  as
    l_id number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create prompt profiles for conversation agents
    uc_ai_test_agent_utils.create_profiles;

    -- Create agent A (math)
    begin
      select id into l_id from uc_ai_agents where code = gc_agent_a_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_agent_a_code,
          p_description         => 'Conversation agent A - math',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Create agent B (geography)
    begin
      select id into l_id from uc_ai_agents where code = gc_agent_b_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_agent_b_code,
          p_description         => 'Conversation agent B - geography',
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

  procedure birthday_agents
  as
    l_agent_id    number;
  begin
    delete from uc_ai_agents where code in (
      'party_brainstormer_agent',
      'party_critic_agent',
      'party_synthesizer_agent',
      'party_moderator_agent'
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'party_brainstormer_agent',
      p_description         => 'Brainstorms party ideas',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'party_brainstormer_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => null
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'party_critic_agent',
      p_description         => 'Critiques party ideas',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'party_critic_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => null
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'party_synthesizer_agent',
      p_description         => 'Synthesizes party ideas into a plan',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'party_synthesizer_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => null
    );

    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'party_moderator_agent',
      p_description         => 'Moderates party planning conversation',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'party_moderator_profile',
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => null
    );
  end birthday_agents;

  procedure execute_round_robin_conversation
  as
    l_conv_id     number;
    l_session_id  varchar2(100 char);
    l_result      json_object_t;
    l_final_msg   clob;
    l_status      varchar2(50 char);
    l_conv_config clob;
    
  begin
    birthday_agents;

    -- Create conversation config (round robin, 2 turns max)
    l_conv_config := '{
      "pattern_type": "conversation",
      "conversation_mode": "round_robin",
      "agents": [
        {
          "agent_code": "party_brainstormer_agent",
          "input_mapping": {"prompt": "{$.chat_history}", "role": "{$.agent_description}" }
        },
        {
          "agent_code": "party_critic_agent",
          "input_mapping": {"prompt": "{$.chat_history}", "role": "{$.agent_description}" }
        },
        {
          "agent_code": "party_synthesizer_agent",
          "input_mapping": {"prompt": "{$.chat_history}", "role": "{$.agent_description}" }
        }
      ],
      "max_turns": 3,
      "termination_condition": {
        "type": "keyword_in_response",
        "keyword": "Final Answer"
      }
    }';

    -- Create the conversation agent
    l_conv_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_conversation_code,
      p_description          => 'Test conversation agent',
      p_agent_type           => uc_ai_agents_api.c_type_conversation,
      p_orchestration_config => l_conv_config,
      p_max_iterations       => 2,
      p_status               => uc_ai_agents_api.c_status_active
    );

    ut.expect(l_conv_id).to_be_not_null();

    -- Execute the conversation
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_conversation_code,
      p_input_parameters => json_object_t('{"prompt": "I need to throw a party for my 12 year old boy. He loves pirates and football. Can you help me plan an exciting and educational party that he and his friends (14 attendees max) will enjoy? Max budget is $200."}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Full conversation result: ' || l_result.to_clob());

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Round Robin Conversation');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Conversation result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_not_null();
  end execute_round_robin_conversation;

  procedure execute_ai_driven_conversation
  as
    l_conv_id     number;
    l_session_id  varchar2(100 char);
    l_result      json_object_t;
    l_final_msg   clob;
    l_exec_count  number;
    l_conv_config clob;
  begin
    birthday_agents;

    l_conv_config := '{
      "pattern_type": "conversation",
      "conversation_mode": "ai_driven",
      "moderator_agent": {
        "agent_code": "party_moderator_agent",
        "input_mapping": {"prompt": "Chat history: {$.chat_history} | available agents: {$.available_agents}" },
        "summary_mapping": {"prompt": "The conversation was ended. Now please outline the final plan for the user. Max 2 sentences. | Chat history: {$.chat_history}" }
      },
      "max_turns": 6,
      "agents": [
        {
          "agent_code": "party_brainstormer_agent",
          "input_mapping": {"prompt": "{$.chat_history}", "role": "{$.agent_description} | Why you where picked to speak next: {$.moderator_rationale}" }
        },
        {
          "agent_code": "party_critic_agent",
          "input_mapping": {"prompt": "{$.chat_history}", "role": "{$.agent_description} | Why you where picked to speak next: {$.moderator_rationale}" }
        },
        {
          "agent_code": "party_synthesizer_agent",
          "input_mapping": {"prompt": "{$.chat_history}", "role": "{$.agent_description} | Why you where picked to speak next: {$.moderator_rationale}" }
        }
      ]
    }';

    delete from UC_AI_AGENTS where code = 'test_ai_driven_conversation';

    l_conv_id := uc_ai_agents_api.create_agent(
      p_code                 => 'test_ai_driven_conversation',
      p_description          => 'Short conversation agent',
      p_agent_type           => uc_ai_agents_api.c_type_conversation,
      p_orchestration_config => l_conv_config,
      p_max_iterations       => 1,
      p_status               => uc_ai_agents_api.c_status_active
    );

    -- Execute the conversation
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => 'test_ai_driven_conversation',
      p_input_parameters => json_object_t('{"prompt": "I need to throw a party for my 12 year old boy. He loves pirates and football. Can you help me plan an exciting and educational party that he and his friends (14 attendees max) will enjoy? Max budget is $200."}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Full AI driven conversation result: ' || l_result.to_clob());

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'AI Driven Conversation');

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('AI driven conversation result: ' || l_final_msg);

    -- Verify limited executions
    select count(*) into l_exec_count
      from uc_ai_agent_executions
     where session_id = l_session_id;
    
    -- Should be just 2 (conversation wrapper + one agent)
    ut.expect(l_exec_count, 'Limited turns should limit executions').to_be_greater_than(3);
  end execute_ai_driven_conversation;

end test_uc_ai_agent_conversation;
/
