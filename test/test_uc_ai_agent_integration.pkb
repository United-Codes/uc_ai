create or replace package body test_uc_ai_agent_integration as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  -- Profile agents
  gc_math_profile_code   constant varchar2(50 char) := 'TEST_INT_MATH';
  gc_geo_profile_code    constant varchar2(50 char) := 'TEST_INT_GEO';
  gc_sum_profile_code    constant varchar2(50 char) := 'TEST_INT_SUM';

  -- History-summarizer (auto-compaction test)
  gc_hsum_profile_code   constant varchar2(50 char) := 'TEST_INT_HSUM';
  gc_hsum_agent_code     constant varchar2(50 char) := 'TEST_INT_HSUM_AG';

  -- Workflow agents
  gc_inner_wf_code       constant varchar2(50 char) := 'TEST_INT_INNER_WF';
  gc_outer_wf_code       constant varchar2(50 char) := 'TEST_INT_OUTER_WF';
  gc_math_wf_code        constant varchar2(50 char) := 'TEST_INT_MATH_WF';
  gc_geo_wf_code         constant varchar2(50 char) := 'TEST_INT_GEO_WF';
  
  -- Orchestrator
  gc_nested_orch_code    constant varchar2(50 char) := 'TEST_INT_ORCH';

  procedure setup
  as
    l_id           number;
    l_workflow_def clob;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create required prompt profiles (geography + summarizer come from create_profiles)
    uc_ai_test_agent_utils.create_math_profile;
    uc_ai_test_agent_utils.create_profiles;

    -- Create profile agents
    begin
      select id into l_id from uc_ai_agents where code = gc_math_profile_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_math_profile_code,
          p_description         => 'Math profile for integration test',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_MATH',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    begin
      select id into l_id from uc_ai_agents where code = gc_geo_profile_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_geo_profile_code,
          p_description         => 'Geography profile for integration test',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_GEO',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    begin
      select id into l_id from uc_ai_agents where code = gc_sum_profile_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_sum_profile_code,
          p_description         => 'Summarizer for integration test',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => 'TEST_AGENT_SUM',
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Create history-summarizer profile + agent for the auto-compaction test.
    -- manage_history() passes {conversation_history} (+ summarize_count) as
    -- params, so the template must reference {conversation_history} - reusing
    -- TEST_AGENT_SUM ({text}) would fail placeholder validation.
    delete from uc_ai_prompt_profiles where code = gc_hsum_profile_code;
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => gc_hsum_profile_code,
      p_description            => 'History summarizer for auto-compaction test',
      p_system_prompt_template => 'Summarize in one short sentence.',
      p_user_prompt_template   => 'Summarize this conversation: {conversation_history}',
      p_provider               => uc_ai.c_provider_openai,
      p_model                  => uc_ai_openai.c_model_gpt_4o_mini,
      p_status                 => 'active'
    );

    begin
      select id into l_id from uc_ai_agents where code = gc_hsum_agent_code and status = 'active';
    exception
      when no_data_found then
        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_hsum_agent_code,
          p_description         => 'History summarizer agent for auto-compaction test',
          p_agent_type          => uc_ai_agents_api.c_type_profile,
          p_prompt_profile_code => gc_hsum_profile_code,
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Create inner workflow (math + summarize)
    begin
      select id into l_id from uc_ai_agents where code = gc_inner_wf_code and status = 'active';
    exception
      when no_data_found then
        l_workflow_def := '{
          "workflow_type": "sequential",
          "steps": [
            {
              "agent_code": "' || gc_math_profile_code || '",
              "input_mapping": {"question": "$.input.question"},
              "output_key": "math_result"
            },
            {
              "agent_code": "' || gc_sum_profile_code || '",
              "input_mapping": {"text": "$.steps.math_result.final_message"},
              "output_key": "summary"
            }
          ]
        }';

        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_inner_wf_code,
          p_description         => 'Inner workflow for nesting test',
          p_agent_type          => uc_ai_agents_api.c_type_workflow,
          p_workflow_definition => l_workflow_def,
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Create math workflow (single step wrapper)
    begin
      select id into l_id from uc_ai_agents where code = gc_math_wf_code and status = 'active';
    exception
      when no_data_found then
        l_workflow_def := '{
          "workflow_type": "sequential",
          "steps": [
            {
              "agent_code": "' || gc_math_profile_code || '",
              "input_mapping": {"question": "$.input.question"},
              "output_key": "result"
            }
          ]
        }';

        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_math_wf_code,
          p_description         => 'Math workflow',
          p_agent_type          => uc_ai_agents_api.c_type_workflow,
          p_workflow_definition => l_workflow_def,
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;

    -- Create geography workflow (single step wrapper)
    begin
      select id into l_id from uc_ai_agents where code = gc_geo_wf_code and status = 'active';
    exception
      when no_data_found then
        l_workflow_def := '{
          "workflow_type": "sequential",
          "steps": [
            {
              "agent_code": "' || gc_geo_profile_code || '",
              "input_mapping": {"question": "$.input.question"},
              "output_key": "result"
            }
          ]
        }';

        l_id := uc_ai_agents_api.create_agent(
          p_code                => gc_geo_wf_code,
          p_description         => 'Geography workflow',
          p_agent_type          => uc_ai_agents_api.c_type_workflow,
          p_workflow_definition => l_workflow_def,
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

  procedure execute_nested_orchestrator_workflow
  as
    l_orch_id    number;
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
    l_status     varchar2(50 char);
    l_exec_count number;
    l_orch_cfg   clob;
  begin
    -- Create orchestrator that routes to workflows (not just profiles)
    l_orch_cfg := '{
      "router_prompt": "Route math questions to math workflow, geography questions to geography workflow.",
      "agents": [
        {
          "code": "' || gc_math_wf_code || '",
          "description": "Handles math calculations via workflow",
          "input_mapping": {"question": "$.input.question"}
        },
        {
          "code": "' || gc_geo_wf_code || '",
          "description": "Answers geography questions via workflow",
          "input_mapping": {"question": "$.input.question"}
        }
      ]
    }';

    -- Create orchestrator
    begin
      select id into l_orch_id
        from uc_ai_agents
       where code = gc_nested_orch_code
         and status = 'active';
    exception
      when no_data_found then
        l_orch_id := uc_ai_agents_api.create_agent(
          p_code                 => gc_nested_orch_code,
          p_description          => 'Orchestrator calling workflows',
          p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
          p_orchestration_config => l_orch_cfg,
          p_status               => uc_ai_agents_api.c_status_active
        );
    end;
    commit;

    ut.expect(l_orch_id).to_be_not_null();

    -- Execute with a math question
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_nested_orch_code,
      p_input_parameters => json_object_t('{"question": "What is 15 + 25?"}'),
      p_session_id       => l_session_id
    );

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Nested Orchestrator->Workflow');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Nested orch->wf result: ' || l_final_msg);
    
    -- Should contain 40 (15 + 25)
    ut.expect(l_final_msg).to_be_like('%40%');

    -- Verify multiple executions recorded (orch + workflow + profile)
    select count(*) into l_exec_count
      from uc_ai_agent_executions
     where session_id = l_session_id;
    
    sys.dbms_output.put_line('Execution count: ' || l_exec_count);
    ut.expect(l_exec_count, 'Should have 3+ executions for nested call').to_be_greater_or_equal(3);

    -- Attribution: across the orch -> workflow -> profile nesting, every
    -- agent-produced message names an agent that ran in the session.
    declare
      l_bad_attr number;
    begin
      select count(*) into l_bad_attr
        from uc_ai_agent_messages m
       where m.session_id = l_session_id
         and ( (m.role in ('assistant', 'tool_call', 'tool_result', 'reasoning')
                and m.agent_code is null)
            or (m.agent_code is not null and not exists (
                  select 1
                    from uc_ai_agent_executions e
                    join uc_ai_agents a on a.id = e.agent_id
                   where e.session_id = l_session_id
                     and a.code = m.agent_code)) );
      ut.expect(l_bad_attr, 'Nested orch->wf messages attributed to a session agent').to_equal(0);
    end;
  end execute_nested_orchestrator_workflow;

  procedure execute_workflow_calling_workflow
  as
    l_outer_wf_id number;
    l_session_id  varchar2(100 char);
    l_result      json_object_t;
    l_final_msg   clob;
    l_status      varchar2(50 char);
    l_exec_count  number;
    l_workflow_def clob;
  begin
    -- Create outer workflow that calls inner workflow
    l_workflow_def := '{
      "workflow_type": "sequential",
      "steps": [
        {
          "agent_code": "' || gc_inner_wf_code || '",
          "input_mapping": {"question": "$.input.question"},
          "output_key": "inner_result"
        }
      ]
    }';

    begin
      select id into l_outer_wf_id
        from uc_ai_agents
       where code = gc_outer_wf_code
         and status = 'active';
    exception
      when no_data_found then
        l_outer_wf_id := uc_ai_agents_api.create_agent(
          p_code                => gc_outer_wf_code,
          p_description         => 'Outer workflow calling inner workflow',
          p_agent_type          => uc_ai_agents_api.c_type_workflow,
          p_workflow_definition => l_workflow_def,
          p_status              => uc_ai_agents_api.c_status_active
        );
    end;
    commit;

    ut.expect(l_outer_wf_id).to_be_not_null();

    -- Execute outer workflow
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_outer_wf_code,
      p_input_parameters => json_object_t('{"question": "What is 100 / 4?"}'),
      p_session_id       => l_session_id
    );

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Workflow->Workflow');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Workflow->workflow result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_not_null();

    -- Verify execution hierarchy recorded
    select count(*) into l_exec_count
      from uc_ai_agent_executions
     where session_id = l_session_id;
    
    sys.dbms_output.put_line('Execution count: ' || l_exec_count);
    -- Outer WF + Inner WF + Math Profile + Summarizer Profile = 4
    ut.expect(l_exec_count, 'Should have 4 executions for WF->WF->profiles').to_be_greater_or_equal(4);

    -- Verify parent-child relationships exist
    declare
      l_has_parent number;
    begin
      select count(*) into l_has_parent
        from uc_ai_agent_executions
       where session_id = l_session_id
         and parent_execution_id is not null;
      
      ut.expect(l_has_parent, 'Should have parent-child exec relationships').to_be_greater_than(0);
    end;

    -- Attribution: across the workflow -> workflow -> profile nesting, every
    -- agent-produced message names an agent that ran in the session.
    declare
      l_bad_attr number;
    begin
      select count(*) into l_bad_attr
        from uc_ai_agent_messages m
       where m.session_id = l_session_id
         and ( (m.role in ('assistant', 'tool_call', 'tool_result', 'reasoning')
                and m.agent_code is null)
            or (m.agent_code is not null and not exists (
                  select 1
                    from uc_ai_agent_executions e
                    join uc_ai_agents a on a.id = e.agent_id
                   where e.session_id = l_session_id
                     and a.code = m.agent_code)) );
      ut.expect(l_bad_attr, 'WF->WF messages attributed to a session agent').to_equal(0);
    end;
  end execute_workflow_calling_workflow;

  procedure history_summarize_calls_agent
  as
    l_history json_array_t := json_array_t();
    l_msg     json_object_t;
    l_result  json_array_t;
    l_first   json_object_t;
    l_summary varchar2(32767 char);
    c_prefix  constant varchar2(50 char) := 'Previous conversation summary: ';
  begin
    -- 5 tiny messages; summarize_after=3 -> older 2 get summarized, last 3 kept
    <<build_history>>
    for i in 1 .. 5 loop
      l_msg := json_object_t();
      l_msg.put('role', 'user');
      l_msg.put('content', 'msg ' || i);
      l_history.append(l_msg);
    end loop build_history;

    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => l_history,
      p_history_management => json_object_t(
        '{"strategy":"summarize","summarize_after":3,"summarizer_agent_code":"' || gc_hsum_agent_code || '"}'
      ),
      p_session_id         => 'test-hsum-session'
    );

    -- 1 summary system message + 3 recent messages
    ut.expect(l_result.get_size).to_equal(4);

    -- Element 0: the injected summary as a system message
    l_first := treat(l_result.get(0) as json_object_t);
    ut.expect(l_first.get_string('role')).to_equal('system');

    l_summary := l_first.get_string('content');
    sys.dbms_output.put_line('Summary message: ' || l_summary);
    ut.expect(l_summary).to_be_like(c_prefix || '%');
    -- Prefix + a non-empty summary => the summarizer agent actually ran
    ut.expect(length(l_summary), 'Summarizer returned a non-empty final_message')
      .to_be_greater_than(length(c_prefix));

    -- Recent messages preserved in order (oldest two dropped)
    ut.expect(treat(l_result.get(1) as json_object_t).get_string('content')).to_equal('msg 3');
    ut.expect(treat(l_result.get(3) as json_object_t).get_string('content')).to_equal('msg 5');
  end history_summarize_calls_agent;

end test_uc_ai_agent_integration;
/
