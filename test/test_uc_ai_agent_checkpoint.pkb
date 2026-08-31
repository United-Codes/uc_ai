create or replace package body test_uc_ai_agent_checkpoint as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages

  gc_math_agent_code   constant varchar2(50 char) := 'TEST_CHKPT_MATH';
  gc_wf_ok_code        constant varchar2(50 char) := 'TEST_CHKPT_WF_OK';
  gc_wf_fail_code      constant varchar2(50 char) := 'TEST_CHKPT_WF_FAIL';
  gc_direct_agent_code constant varchar2(50 char) := 'TEST_CHKPT_DIRECT';

  procedure setup
  as
    l_id number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    uc_ai_test_agent_utils.create_math_profile;

    uc_ai_test_agent_utils.delete_agents_cascade(gc_math_agent_code);
    -- @dblinter ignore(g-2135): create_agent is a function; the new id is not needed by the test
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_math_agent_code,
      p_description         => 'Math step agent for checkpoint tests',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_MATH',
      p_status              => uc_ai_agents_api.c_status_active
    );

    commit; -- agents must be committed before execution (autonomous telemetry)
  end setup;

  procedure teardown
  as
  begin
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_CHKPT%');
    commit;
  end teardown;

  procedure checkpoint_execution_direct
  as
    l_agent_id number;
    l_exec_id  number;
    l_state    clob;
    l_json     json_object_t;
  begin
    -- unknown execution id: best-effort, must not raise
    uc_ai_agents_api.checkpoint_execution(
      p_exec_id       => -999999,
      p_current_state => json_object_t('{"a":1}'),
      p_last_step     => 'nope'
    );

    -- real execution row gets the checkpoint payload
    uc_ai_test_agent_utils.delete_agents_cascade(gc_direct_agent_code);
    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => gc_direct_agent_code,
      p_description         => 'Direct checkpoint test agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_MATH',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    insert into uc_ai_agent_executions (id, agent_id, session_id, status, started_at)
    values (uc_ai_agent_executions_seq.nextval, l_agent_id, 'CHKPT_DIRECT_TEST', 'running', systimestamp)
    returning id into l_exec_id;
    commit;

    uc_ai_agents_api.checkpoint_execution(
      p_exec_id       => l_exec_id,
      p_current_state => json_object_t('{"foo":"bar"}'),
      p_last_step     => 'step_x'
    );

    select current_state into l_state from uc_ai_agent_executions where id = l_exec_id;
    ut.expect(l_state).to_be_not_null();

    l_json := json_object_t.parse(l_state);
    ut.expect(l_json.get_string('foo')).to_equal('bar');
    ut.expect(l_json.get_string('_last_completed_step')).to_equal('step_x');
    ut.expect(l_json.has('_checkpoint_at')).to_be_true();
  end checkpoint_execution_direct;

  procedure checkpoint_cleared_on_success
  as
    l_wf_id       number;
    l_session_id  varchar2(100 char);
    l_result      json_object_t;
    l_exec        uc_ai_agent_executions%rowtype;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade(gc_wf_ok_code);
    l_wf_id := uc_ai_agents_api.create_agent(
      p_code                => gc_wf_ok_code,
      p_description         => 'Checkpoint success workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => '{
        "workflow_type": "sequential",
        "steps": [
          {
            "agent_code": "' || gc_math_agent_code || '",
            "input_mapping": {"question": "{$.input.question}"},
            "output_key": "step1_result"
          }
        ]
      }',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_wf_ok_code,
      p_input_parameters => json_object_t('{"question": "2 + 3"}'),
      p_session_id       => l_session_id
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    select * into l_exec
      from uc_ai_agent_executions
     where session_id = l_session_id
       and agent_id = l_wf_id;

    ut.expect(l_exec.status).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_exec.output_result).to_be_not_null();
    -- checkpoint is cleared on successful completion
    ut.expect(l_exec.current_state).to_be_null();
  end checkpoint_cleared_on_success;

  procedure checkpoint_survives_failure
  as
    l_wf_id      number;
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_exec       uc_ai_agent_executions%rowtype;
    l_state      json_object_t;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade(gc_wf_fail_code);
    -- step 2 has a PL/SQL input-mapping expression that raises at runtime
    l_wf_id := uc_ai_agents_api.create_agent(
      p_code                => gc_wf_fail_code,
      p_description         => 'Checkpoint failure workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => '{
        "workflow_type": "sequential",
        "steps": [
          {
            "agent_code": "' || gc_math_agent_code || '",
            "input_mapping": {"question": "{$.input.question}"},
            "output_key": "step1_result"
          },
          {
            "agent_code": "' || gc_math_agent_code || '",
            "input_mapping": {"question": {"expression": "to_char(1/0)", "is_plsql_expression": true}},
            "output_key": "step2_result"
          }
        ]
      }',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    l_session_id := uc_ai_agents_api.generate_session_id;
    begin
      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code       => gc_wf_fail_code,
        p_input_parameters => json_object_t('{"question": "2 + 3"}'),
        p_session_id       => l_session_id
      );
      ut.fail('Expected workflow execution to fail at step 2');
    exception
      when others then
        null; -- expected
    end;

    -- the failed row and its last checkpoint are committed and durable
    select * into l_exec
      from uc_ai_agent_executions
     where session_id = l_session_id
       and agent_id = l_wf_id;

    ut.expect(l_exec.status).to_equal(uc_ai_agents_api.c_exec_failed);
    ut.expect(l_exec.current_state).to_be_not_null();

    l_state := json_object_t.parse(l_exec.current_state);
    ut.expect(l_state.get_string('_last_completed_step')).to_equal(gc_math_agent_code);
    ut.expect(l_state.get_object('steps').has('step1_result')).to_be_true();
  end checkpoint_survives_failure;

end test_uc_ai_agent_checkpoint;
/
