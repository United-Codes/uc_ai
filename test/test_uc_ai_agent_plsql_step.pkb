create or replace package body test_uc_ai_agent_plsql_step as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages

  gc_seq_code   constant varchar2(50 char) := 'TEST_PLSQL_SEQ';
  gc_types_code constant varchar2(50 char) := 'TEST_PLSQL_TYPES';
  gc_side_code  constant varchar2(50 char) := 'TEST_PLSQL_SIDE';
  gc_cond_code  constant varchar2(50 char) := 'TEST_PLSQL_COND';
  gc_gate_code  constant varchar2(50 char) := 'TEST_PLSQL_GATE';
  gc_stop_code  constant varchar2(50 char) := 'TEST_PLSQL_STOP';
  gc_loop_code  constant varchar2(50 char) := 'TEST_PLSQL_LOOP';
  gc_err_code   constant varchar2(50 char) := 'TEST_PLSQL_ERR';

  procedure setup
  as
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    -- executions commit autonomously and survive rollback, so purge by pattern
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_PLSQL%');
    commit;
  end setup;

  procedure teardown
  as
  begin
    null;
  end teardown;

  -- Helper: create an active workflow agent and commit it (required before execution)
  procedure create_workflow(
    p_code in varchar2,
    p_def  in clob
  )
  as
    l_id number;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade(p_code);
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'PL/SQL step test workflow ' || p_code,
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => p_def,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_workflow;


  procedure transforms_between_steps
  as
    l_def    clob;
    l_result json_object_t;
    l_steps  json_object_t;
  begin
    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return to_char(json_object_t(:parameters).get_object('input').get_number('x') * 2);",
          "output_key": "doubled"
        },
        {
          "step_type": "plsql",
          "plsql_function_call": "declare j json_object_t := json_object_t(:parameters); o json_object_t := json_object_t(); begin o.put('sum', j.get_object('input').get_number('x') + j.get_object('steps').get_number('doubled')); return o.to_clob; end;",
          "output_key": "combined"
        }
      ]
    }#';

    create_workflow(gc_seq_code, l_def);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_seq_code,
      p_input_parameters => json_object_t('{"x": 5}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );

    sys.dbms_output.put_line('transforms_between_steps: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_number('_workflow_iterations')).to_equal(2);

    l_steps := l_result.get_object('steps');
    -- first step stored as a real number
    ut.expect(l_steps.get_number('doubled')).to_equal(10);
    -- second step read both $.input and $.steps and returned an object
    ut.expect(l_steps.get_object('combined').get_number('sum')).to_equal(15);

    ut.expect(l_result.get_clob('final_message')).to_be_not_null();
  end transforms_between_steps;


  procedure output_types
  as
    l_def    clob;
    l_result json_object_t;
    l_steps  json_object_t;
    l_elem   json_element_t;
  begin
    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return '42';", "output_key": "s_num" },
        { "step_type": "plsql", "plsql_function_call": "declare o json_object_t := json_object_t(); begin o.put('ok', true); return o.to_clob; end;", "output_key": "s_obj" },
        { "step_type": "plsql", "plsql_function_call": "return 'hello';", "output_key": "s_str" }
      ]
    }#';

    create_workflow(gc_types_code, l_def);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_types_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );

    sys.dbms_output.put_line('output_types: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_steps := l_result.get_object('steps');

    -- '42' is stored as a real JSON number, not text
    l_elem := l_steps.get('s_num');
    ut.expect(l_elem.is_number).to_be_true();
    ut.expect(l_steps.get_number('s_num')).to_equal(42);

    -- an object stays an object with navigable fields
    l_elem := l_steps.get('s_obj');
    ut.expect(l_elem.is_object).to_be_true();
    ut.expect(l_steps.get_object('s_obj').get_boolean('ok')).to_be_true();

    -- non-JSON text stays a plain string
    l_elem := l_steps.get('s_str');
    ut.expect(l_elem.is_string).to_be_true();
    ut.expect(l_steps.get_string('s_str')).to_equal('hello');
  end output_types;


  procedure optional_output_key
  as
    l_def    clob;
    l_result json_object_t;
    l_steps  json_object_t;
    l_keys   json_key_list;
  begin
    g_side_effect := 0;

    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "begin test_uc_ai_agent_plsql_step.g_side_effect := 99; return 'done'; end;" }
      ]
    }#';

    create_workflow(gc_side_code, l_def);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_side_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );

    sys.dbms_output.put_line('optional_output_key: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    -- the step ran (side effect visible)
    ut.expect(g_side_effect).to_equal(99);
    -- but nothing was stored, since there was no output_key
    l_steps := l_result.get_object('steps');
    l_keys := l_steps.get_keys;
    ut.expect(l_keys.count).to_equal(0);
    ut.expect(l_result.get_number('_workflow_iterations')).to_equal(1);
  end optional_output_key;


  procedure condition_skips_step
  as
    l_def    clob;
    l_result json_object_t;
  begin
    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "condition": "'{$.input.run}' = 'Y'",
          "plsql_function_call": "return 'ran';",
          "output_key": "out"
        }
      ]
    }#';

    create_workflow(gc_cond_code, l_def);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_cond_code,
      p_input_parameters => json_object_t('{"run": "N"}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );

    sys.dbms_output.put_line('condition_skips_step: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_number('_workflow_iterations')).to_equal(0);
    ut.expect(l_result.get_object('steps').has('out')).to_be_false();
  end condition_skips_step;


  procedure gates_downstream_step
  as
    l_def    clob;
    l_result json_object_t;
  begin
    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return json_object_t(:parameters).get_object('input').get_string('flag');",
          "output_key": "gate"
        },
        {
          "step_type": "plsql",
          "condition": "'{$.steps.gate}' = 'Y'",
          "plsql_function_call": "return 'ran';",
          "output_key": "after"
        }
      ]
    }#';

    create_workflow(gc_gate_code, l_def);

    -- gate = Y -> downstream step runs
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_gate_code,
      p_input_parameters => json_object_t('{"flag": "Y"}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );
    sys.dbms_output.put_line('gates_downstream_step (Y): ' || l_result.to_clob);
    ut.expect(l_result.get_object('steps').get_string('after')).to_equal('ran');

    -- gate = N -> downstream step is skipped
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_gate_code,
      p_input_parameters => json_object_t('{"flag": "N"}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );
    sys.dbms_output.put_line('gates_downstream_step (N): ' || l_result.to_clob);
    ut.expect(l_result.get_object('steps').get_string('gate')).to_equal('N');
    ut.expect(l_result.get_object('steps').has('after')).to_be_false();
  end gates_downstream_step;


  procedure stop_halts_workflow
  as
    l_def    clob;
    l_result json_object_t;
    l_steps  json_object_t;
  begin
    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return 'a';", "output_key": "a" },
        { "step_type": "plsql", "plsql_function_call": "declare o json_object_t := json_object_t(); begin o.put('__control__', 'stop'); return o.to_clob; end;", "output_key": "b" },
        { "step_type": "plsql", "plsql_function_call": "return 'c';", "output_key": "c" }
      ]
    }#';

    create_workflow(gc_stop_code, l_def);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_stop_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );

    sys.dbms_output.put_line('stop_halts_workflow: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    l_steps := l_result.get_object('steps');
    ut.expect(l_steps.get_string('a')).to_equal('a');
    ut.expect(l_steps.get_object('b').get_string('__control__')).to_equal('stop');
    ut.expect(l_steps.has('c'), 'Step after the stop directive must not run').to_be_false();
    ut.expect(l_result.get_number('_workflow_iterations')).to_equal(2);
  end stop_halts_workflow;


  procedure stop_breaks_loop
  as
    l_def    clob;
    l_result json_object_t;
  begin
    g_loop_counter := 0;

    l_def := q'#{
      "workflow_type": "loop",
      "steps": [
        {
          "step_type": "plsql",
          "output_key": "x",
          "plsql_function_call": "declare o json_object_t := json_object_t(); begin test_uc_ai_agent_plsql_step.g_loop_counter := test_uc_ai_agent_plsql_step.g_loop_counter + 1; if test_uc_ai_agent_plsql_step.g_loop_counter >= 2 then o.put('__control__', 'stop'); return o.to_clob; else return to_char(test_uc_ai_agent_plsql_step.g_loop_counter); end if; end;"
        }
      ],
      "loop_config": { "max_iterations": 5 },
      "final_message": "done"
    }#';

    create_workflow(gc_loop_code, l_def);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_loop_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );

    sys.dbms_output.put_line('stop_breaks_loop: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    -- The loop stopped as soon as the counter hit 2, well before max_iterations (5)
    ut.expect(g_loop_counter, 'Loop must stop at the stop directive, not run all 5 iterations').to_equal(2);
    ut.expect(l_result.get_number('_loop_iterations')).to_equal(2);
  end stop_breaks_loop;


  procedure validation_rejects_missing_fc
  as
    l_def clob;
    l_id  number;
  begin
    l_def := q'#{ "workflow_type": "sequential", "steps": [ { "step_type": "plsql", "output_key": "x" } ] }#';
    begin
      l_id := uc_ai_agents_api.create_agent(
        p_code                => 'TEST_PLSQL_VALID',
        p_description         => 'invalid - missing plsql_function_call',
        p_agent_type          => uc_ai_agents_api.c_type_workflow,
        p_workflow_definition => l_def,
        p_status              => uc_ai_agents_api.c_status_active
      );
      ut.fail('create_agent should have rejected a plsql step without plsql_function_call');
    exception
      when others then
        ut.expect(sqlcode).to_equal(-20503);
    end;
  end validation_rejects_missing_fc;


  procedure validation_rejects_unknown_type
  as
    l_def clob;
    l_id  number;
  begin
    l_def := q'#{ "workflow_type": "sequential", "steps": [ { "step_type": "banana", "agent_code": "X" } ] }#';
    begin
      l_id := uc_ai_agents_api.create_agent(
        p_code                => 'TEST_PLSQL_VALID',
        p_description         => 'invalid - unknown step_type',
        p_agent_type          => uc_ai_agents_api.c_type_workflow,
        p_workflow_definition => l_def,
        p_status              => uc_ai_agents_api.c_status_active
      );
      ut.fail('create_agent should have rejected an unknown step_type');
    exception
      when others then
        ut.expect(sqlcode).to_equal(-20503);
    end;
  end validation_rejects_unknown_type;


  procedure validation_accepts_plsql_only
  as
    l_def clob;
    l_id  number;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_PLSQL_VALID');
    -- no agent_code and no output_key is valid for a plsql step
    l_def := q'#{ "workflow_type": "sequential", "steps": [ { "step_type": "plsql", "plsql_function_call": "return 'ok';" } ] }#';
    l_id := uc_ai_agents_api.create_agent(
      p_code                => 'TEST_PLSQL_VALID',
      p_description         => 'valid plsql-only workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_def,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end validation_accepts_plsql_only;


  procedure error_surfaces
  as
    l_def    clob;
    l_result json_object_t;
  begin
    l_def := q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return to_char(1/0);", "output_key": "x" }
      ]
    }#';

    create_workflow(gc_err_code, l_def);

    begin
      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code       => gc_err_code,
        p_input_parameters => json_object_t('{}'),
        p_session_id       => uc_ai_agents_api.generate_session_id
      );
      ut.fail('A failing PL/SQL step should raise');
    exception
      when others then
        ut.expect(sqlcode, 'PL/SQL step failure should surface as c_err_plsql_step_eval').to_equal(-20456);
    end;
  end error_surfaces;

end test_uc_ai_agent_plsql_step;
/
