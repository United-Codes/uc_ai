create or replace package body test_uc_ai_workflow_mapping as

  function big_clob (
    p_length in pls_integer
  ) return clob
  as
    l_clob  clob;
    l_chunk varchar2(4000 char) := rpad('x', 4000, 'x');
    l_len   pls_integer := 0;
  begin
    sys.dbms_lob.createtemporary(l_clob, true);
    while l_len < p_length loop
      sys.dbms_lob.append(l_clob, substr(l_chunk, 1, least(4000, p_length - l_len)));
      l_len := l_len + least(4000, p_length - l_len);
    end loop;
    return l_clob;
  end big_clob;


  procedure map_inputs_resolves_nested_paths
  as
    l_state  json_object_t;
    l_map    json_object_t;
    l_result json_object_t;
  begin
    l_state := json_object_t('{"input":{"topic":"Star Wars"},"steps":{"haiku":"A haiku text","rating":{"quality":9}}}');
    l_map   := json_object_t('{"topic":"{$.input.topic}","haiku":"{$.steps.haiku}","quality":"{$.steps.rating.quality}"}');

    l_result := uc_ai_agent_workflow_api.map_inputs(l_map, l_state);

    ut.expect(l_result.get_string('topic')).to_equal('Star Wars');
    ut.expect(l_result.get_string('haiku')).to_equal('A haiku text');
    ut.expect(l_result.get_string('quality')).to_equal('9');
  end map_inputs_resolves_nested_paths;


  procedure map_inputs_clob_value_survives
  as
    l_big    clob;
    l_steps  json_object_t := json_object_t();
    l_state  json_object_t := json_object_t();
    l_map    json_object_t;
    l_result json_object_t;
  begin
    l_big := big_clob(100000);

    l_steps.put('big', l_big);
    l_state.put('input', json_object_t());
    l_state.put('steps', l_steps);

    l_map := json_object_t('{"payload":"{$.steps.big}"}');

    l_result := uc_ai_agent_workflow_api.map_inputs(l_map, l_state);

    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('payload'))).to_equal(100000);
  end map_inputs_clob_value_survives;


  procedure map_inputs_template_multiple_tokens
  as
    l_state  json_object_t;
    l_map    json_object_t;
    l_result json_object_t;
  begin
    l_state := json_object_t('{"input":{"topic":"space"},"steps":{"haiku":"stars fall softly"}}');
    l_map   := json_object_t('{"prompt":"Rate this haiku: {$.steps.haiku} (topic: {$.input.topic})"}');

    l_result := uc_ai_agent_workflow_api.map_inputs(l_map, l_state);

    ut.expect(l_result.get_string('prompt')).to_equal('Rate this haiku: stars fall softly (topic: space)');
  end map_inputs_template_multiple_tokens;


  procedure map_inputs_number_and_boolean_conversion
  as
    l_state  json_object_t;
    l_map    json_object_t;
    l_result json_object_t;
  begin
    l_state := json_object_t('{"steps":{"rating":{"quality":8.5,"passed":true,"failed":false}}}');
    l_map   := json_object_t('{"q":"{$.steps.rating.quality}","p":"{$.steps.rating.passed}","f":"{$.steps.rating.failed}"}');

    l_result := uc_ai_agent_workflow_api.map_inputs(l_map, l_state);

    ut.expect(l_result.get_string('q')).to_equal('8.5');
    ut.expect(l_result.get_string('p')).to_equal('true');
    ut.expect(l_result.get_string('f')).to_equal('false');
  end map_inputs_number_and_boolean_conversion;


  procedure unresolved_path_substitutes_empty
  as
    l_state  json_object_t;
    l_map    json_object_t;
    l_result json_object_t;
  begin
    l_state := json_object_t('{"input":{},"steps":{}}');
    l_map   := json_object_t('{"feedback":"{$.steps.missing.rating_feedback}","mixed":"before {$.steps.nope} after"}');

    l_result := uc_ai_agent_workflow_api.map_inputs(l_map, l_state);

    -- unresolved single token resolves to null, embedded token to surrounding text only
    ut.expect(l_result.get_string('feedback')).to_be_null();
    ut.expect(l_result.get_string('mixed')).to_equal('before  after');
  end unresolved_path_substitutes_empty;


  procedure evaluate_condition_numeric_compare
  as
    l_state json_object_t;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    l_state := json_object_t('{"steps":{"rating":{"quality":9}}}');

    ut.expect(uc_ai_agent_workflow_api.evaluate_condition('{$.steps.rating.quality} >= 8', l_state)).to_be_true();
    ut.expect(uc_ai_agent_workflow_api.evaluate_condition('{$.steps.rating.quality} >= 10', l_state)).to_be_false();
  end evaluate_condition_numeric_compare;


  procedure condition_with_oversized_value_raises
  as
    l_steps  json_object_t := json_object_t();
    l_state  json_object_t := json_object_t();
    l_result boolean;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    l_steps.put('big', big_clob(40000));
    l_state.put('steps', l_steps);

    begin
      l_result := uc_ai_agent_workflow_api.evaluate_condition('''{$.steps.big}'' is not null', l_state);
      ut.fail('Expected condition evaluation to raise for an oversized value');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_condition_eval);
    end;
  end condition_with_oversized_value_raises;


  procedure array_index_resolution
  as
    l_state  json_object_t;
    l_map    json_object_t;
    l_result json_object_t;
  begin
    l_state := json_object_t('{"steps":{"list":["alpha","beta","gamma"]}}');
    l_map   := json_object_t('{"first":"{$.steps.list[1]}","third":"{$.steps.list[3]}","oob":"{$.steps.list[4]}"}');

    l_result := uc_ai_agent_workflow_api.map_inputs(l_map, l_state);

    ut.expect(l_result.get_string('first')).to_equal('alpha');
    ut.expect(l_result.get_string('third')).to_equal('gamma');
    ut.expect(l_result.get_string('oob')).to_be_null();
  end array_index_resolution;


  procedure loop_iteration_snapshots_differ
  as
    l_state json_object_t := json_object_t('{"input":{}}');
    l_step  json_object_t := json_object_t('{"output_key":"result"}');
    l_snaps json_array_t := json_array_t();
    l_snap  json_object_t;
  begin
    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => l_step,
      p_step_output      => json_object_t('{"final_message":"first"}'),
      pio_workflow_state => l_state
    );
    l_snap := treat(l_state.get_object('steps').clone as json_object_t);
    l_snaps.append(l_snap);

    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => l_step,
      p_step_output      => json_object_t('{"final_message":"second"}'),
      pio_workflow_state => l_state
    );
    l_snap := treat(l_state.get_object('steps').clone as json_object_t);
    l_snaps.append(l_snap);

    -- each snapshot must keep the value from its own iteration
    ut.expect(treat(l_snaps.get(0) as json_object_t).get_string('result')).to_equal('first');
    ut.expect(treat(l_snaps.get(1) as json_object_t).get_string('result')).to_equal('second');
  end loop_iteration_snapshots_differ;

end test_uc_ai_workflow_mapping;
/
