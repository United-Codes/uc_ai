create or replace package body test_uc_ai_agent_conversation as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_conversation_code constant varchar2(50 char) := 'TEST_CONVERSATION';
  gc_agent_a_code      constant varchar2(50 char) := 'TEST_CONV_A';
  gc_agent_b_code      constant varchar2(50 char) := 'TEST_CONV_B';

  /*
   * Deterministic telemetry checks for a finished conversation run. A
   * conversation agent is a wrapper that delegates every LLM call to its
   * participant/moderator sub-agents (all run with parent_execution_id set to
   * the wrapper), so:
   *   - exactly one session header + one top-level turn (the wrapper)
   *   - the wrapper itself spends no tokens (no direct generate_text call)
   *   - participants run as nested children, sharing the session, no turn_index
   *   - the session token totals equal the SUM of every execution's own tokens
   * The wrapper now emits a full transcript, so the message log holds the
   * opening input as a 'user' row (no agent_code) plus one 'assistant' row per
   * participant turn, each attributed to its producing agent via agent_code.
   */
  procedure validate_conversation_telemetry(
    p_session_id in varchar2,
    p_test_name  in varchar2
  )
  as
    l_count         number;
    l_turn_count    number;
    l_status_hdr    varchar2(50 char);
    l_top_index     number;
    l_top_status    varchar2(50 char);
    l_top_output    clob;
    l_wrapper_in    number;
    l_wrapper_out   number;
    l_child_count   number;
    l_bad_child_idx number;
    l_bad_child_sid number;
    l_child_in      number;
    l_sess_in       number;
    l_sess_out      number;
    l_exec_in       number;
    l_exec_out      number;
    l_msg_rows      number;
    l_hdr_msg       number;
    l_assistant     number;
    l_user_rows     number;
    l_tool_rows     number;
    l_bad_attr      number;
    l_unmatched     number;
    l_min_seq       number;
    l_max_seq       number;
    l_uniq_seq      number;
  begin
    -- One session header, completed, exactly one conversation turn.
    select count(*) into l_count
      from uc_ai_agent_sessions where session_id = p_session_id;
    ut.expect(l_count, p_test_name || ': one session header').to_equal(1);

    select turn_count, status into l_turn_count, l_status_hdr
      from uc_ai_agent_sessions where session_id = p_session_id;
    ut.expect(l_turn_count, p_test_name || ': single conversation turn').to_equal(1);
    ut.expect(l_status_hdr, p_test_name || ': session completed').to_equal(uc_ai_agents_api.c_exec_completed);

    -- Top-level wrapper: turn 1, completed, stored an output_result, and made
    -- no LLM calls of its own (all spend lives on the children).
    select turn_index, status, output_result, total_input_tokens, total_output_tokens
      into l_top_index, l_top_status, l_top_output, l_wrapper_in, l_wrapper_out
      from uc_ai_agent_executions
     where session_id = p_session_id and parent_execution_id is null;
    ut.expect(l_top_index, p_test_name || ': wrapper is turn 1').to_equal(1);
    ut.expect(l_top_status, p_test_name || ': wrapper completed').to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_top_output is not null, p_test_name || ': wrapper stored an output_result').to_be_true();
    ut.expect(l_wrapper_in, p_test_name || ': wrapper spent no input tokens itself').to_equal(0);
    ut.expect(l_wrapper_out, p_test_name || ': wrapper spent no output tokens itself').to_equal(0);

    -- Participant/moderator sub-agents: nested children, same session, no
    -- turn_index, and they actually consumed tokens.
    select count(*),
           count(case when turn_index is not null then 1 end),
           count(case when session_id <> p_session_id then 1 end),
           nvl(sum(total_input_tokens), 0)
      into l_child_count, l_bad_child_idx, l_bad_child_sid, l_child_in
      from uc_ai_agent_executions
     where parent_execution_id is not null and session_id = p_session_id;
    ut.expect(l_child_count, p_test_name || ': conversation spawned participant sub-agents').to_be_greater_than(0);
    ut.expect(l_bad_child_idx, p_test_name || ': nested executions carry no turn_index').to_equal(0);
    ut.expect(l_bad_child_sid, p_test_name || ': nested executions share the session_id').to_equal(0);
    ut.expect(l_child_in, p_test_name || ': participants recorded their own input tokens').to_be_greater_than(0);

    -- Every child's parent is the top-level wrapper of this session.
    select count(*) into l_count
      from uc_ai_agent_executions c
     where c.session_id = p_session_id
       and c.parent_execution_id is not null
       and not exists (
             select 1 from uc_ai_agent_executions p
              where p.id = c.parent_execution_id
                and p.session_id = c.session_id
                and p.parent_execution_id is null);
    ut.expect(l_count, p_test_name || ': every child points at the top-level wrapper').to_equal(0);

    -- Every execution finished cleanly with consistent timestamps.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and (status <> uc_ai_agents_api.c_exec_completed or completed_at is null
            or started_at is null or completed_at < started_at);
    ut.expect(l_count, p_test_name || ': all executions completed with valid timestamps').to_equal(0);

    -- Session token totals reconcile with the SUM over executions (no double
    -- count: each row holds only the tokens of its own LLM calls).
    select total_input_tokens, total_output_tokens into l_sess_in, l_sess_out
      from uc_ai_agent_sessions where session_id = p_session_id;
    select nvl(sum(total_input_tokens), 0), nvl(sum(total_output_tokens), 0)
      into l_exec_in, l_exec_out
      from uc_ai_agent_executions where session_id = p_session_id;
    ut.expect(l_sess_in, p_test_name || ': session input = SUM of execution own tokens').to_equal(l_exec_in);
    ut.expect(l_sess_out, p_test_name || ': session output = SUM of execution own tokens').to_equal(l_exec_out);
    ut.expect(l_sess_in, p_test_name || ': conversation spent input tokens').to_be_greater_than(0);

    -- Message log: header count matches actual rows, seq is contiguous, and the
    -- full debate is recorded - the opening input as a 'user' row plus one
    -- 'assistant' row per participant turn (never collapsed to a single row).
    select count(*),
           count(case when role = 'assistant' then 1 end),
           count(case when role = 'user' then 1 end),
           count(case when role in ('tool_call', 'tool_result') then 1 end),
           min(seq), max(seq), count(distinct seq)
      into l_msg_rows, l_assistant, l_user_rows, l_tool_rows,
           l_min_seq, l_max_seq, l_uniq_seq
      from uc_ai_agent_messages where session_id = p_session_id;
    select message_count into l_hdr_msg
      from uc_ai_agent_sessions where session_id = p_session_id;
    ut.expect(l_hdr_msg, p_test_name || ': header message_count matches persisted rows').to_equal(l_msg_rows);
    ut.expect(l_user_rows, p_test_name || ': opening input persisted as a user row').to_be_greater_than(0);
    ut.expect(l_assistant, p_test_name || ': each participant turn persisted as an assistant row').to_be_greater_than(0);
    ut.expect(l_msg_rows, p_test_name || ': transcript is not collapsed to one row').to_be_greater_than(1);
    -- Conversation is discussion, not tool use: no tool rows expected.
    ut.expect(l_tool_rows, p_test_name || ': no tool rows in a conversation transcript').to_equal(0);
    ut.expect(l_uniq_seq, p_test_name || ': seq values are unique').to_equal(l_msg_rows);
    ut.expect(l_min_seq, p_test_name || ': seq starts at 1').to_equal(1);
    ut.expect(l_max_seq, p_test_name || ': seq ends at message count').to_equal(l_msg_rows);

    -- Attribution: assistant rows name their producing agent; the user row does
    -- not; and every agent_code belongs to an agent that ran in the session.
    select count(case when role = 'assistant' and agent_code is null then 1 end)
         + count(case when role = 'user' and agent_code is not null then 1 end)
      into l_bad_attr
      from uc_ai_agent_messages where session_id = p_session_id;
    ut.expect(l_bad_attr, p_test_name || ': assistant rows attributed, user row not').to_equal(0);

    select count(*) into l_unmatched
      from uc_ai_agent_messages m
     where m.session_id = p_session_id
       and m.agent_code is not null
       and not exists (
             select 1
               from uc_ai_agent_executions e
               join uc_ai_agents a on a.id = e.agent_id
              where e.session_id = p_session_id
                and a.code = m.agent_code);
    ut.expect(l_unmatched, p_test_name || ': every agent_code matches an execution agent in the session').to_equal(0);
  end validate_conversation_telemetry;

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

    commit; -- agents must be committed before execution (autonomous telemetry)
  end setup;

  procedure teardown
  as
  begin
    null;
    --uc_ai_test_agent_utils.cleanup_test_data;
  end teardown;

  procedure birthday_agents
  as
    l_agent_id    number;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade('party_brainstormer_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('party_critic_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('party_synthesizer_agent');
    uc_ai_test_agent_utils.delete_agents_cascade('party_moderator_agent');

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

    commit;
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
    uc_ai_test_agent_utils.delete_agents_cascade(gc_conversation_code);
    l_conv_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_conversation_code,
      p_description          => 'Test conversation agent',
      p_agent_type           => uc_ai_agents_api.c_type_conversation,
      p_orchestration_config => l_conv_config,
      p_max_iterations       => 2,
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

    ut.expect(l_conv_id, 'Conversation agent should have been created').to_be_not_null();

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
    ut.expect(l_status, 'Execution status should be completed').to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Conversation result: ' || l_final_msg);
    ut.expect(l_final_msg, 'Final message should not be null').to_be_not_null();

    validate_conversation_telemetry(l_session_id, 'Round robin conversation');
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

    uc_ai_test_agent_utils.delete_agents_cascade('test_ai_driven_conversation');

    l_conv_id := uc_ai_agents_api.create_agent(
      p_code                 => 'test_ai_driven_conversation',
      p_description          => 'Short conversation agent',
      p_agent_type           => uc_ai_agents_api.c_type_conversation,
      p_orchestration_config => l_conv_config,
      p_max_iterations       => 1,
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

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

    -- The moderator + the agents it picks each run as their own execution
    -- (wrapper + moderator turns + at least one participant).
    select count(*) into l_exec_count
      from uc_ai_agent_executions
     where session_id = l_session_id;
    ut.expect(l_exec_count, 'Moderator-driven run spawns several executions').to_be_greater_than(3);

    validate_conversation_telemetry(l_session_id, 'AI driven conversation');
  end execute_ai_driven_conversation;

end test_uc_ai_agent_conversation;
/
