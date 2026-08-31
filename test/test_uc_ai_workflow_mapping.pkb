create or replace package body test_uc_ai_workflow_mapping as
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-5040): the tests assert THAT an error is raised; sqlcode/sqlerrm are the assertion

  function big_clob (
    p_length in pls_integer
  ) return clob
  as
    l_clob  clob;
    l_chunk varchar2(4000 char) := rpad('x', 4000, 'x');
    l_len   pls_integer := 0;
  begin
    sys.dbms_lob.createtemporary(l_clob, true);
    <<fill_clob>>
    while l_len < p_length loop
      sys.dbms_lob.append(l_clob, substr(l_chunk, 1, least(4000, p_length - l_len)));
      l_len := l_len + least(4000, p_length - l_len);
    end loop fill_clob;
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


  /*
   * Builds [{"role":"user","content":"msg 1"}, ...]; when p_with_system is
   * true the first message has role system instead.
   */
  function make_history (
    p_count       in pls_integer
  , p_with_system in boolean default false
  ) return json_array_t
  as
    l_history json_array_t := json_array_t();
    l_msg     json_object_t;
  begin
    <<build_history>>
    for i in 1 .. p_count loop
      l_msg := json_object_t();
      if i = 1 and p_with_system then
        l_msg.put('role', 'system');
      else
        l_msg.put('role', 'user');
      end if;
      l_msg.put('content', 'msg ' || i);
      l_history.append(l_msg);
    end loop build_history;
    return l_history;
  end make_history;


  function history_content (
    p_history in json_array_t
  , p_index   in pls_integer
  ) return varchar2
  as
  begin
    return treat(p_history.get(p_index) as json_object_t).get_string('content');
  end history_content;


  procedure add_result_missing_output_key
  as
    l_state json_object_t := json_object_t();
  begin
    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => json_object_t()
    , p_step_output      => json_object_t('{"final_message":"x"}')
    , pio_workflow_state => l_state
    );
  end add_result_missing_output_key;


  procedure add_result_creates_steps_object
  as
    l_state json_object_t := json_object_t('{"input":{"topic":"x"}}');
    l_steps json_object_t;
  begin
    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => json_object_t('{"output_key":"one"}')
    , p_step_output      => json_object_t('{"final_message":"first"}')
    , pio_workflow_state => l_state
    );

    ut.expect(l_state.get_object('steps').get_string('one')).to_equal('first');

    -- a second step must not clobber previous step results
    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => json_object_t('{"output_key":"two"}')
    , p_step_output      => json_object_t('{"final_message":"second"}')
    , pio_workflow_state => l_state
    );

    l_steps := l_state.get_object('steps');
    ut.expect(l_steps.get_string('one')).to_equal('first');
    ut.expect(l_steps.get_string('two')).to_equal('second');
    -- untouched state keys survive
    ut.expect(l_state.get_object('input').get_string('topic')).to_equal('x');
  end add_result_creates_steps_object;


  procedure add_result_clob_final_message
  as
    l_state  json_object_t := json_object_t();
    l_output json_object_t := json_object_t();
  begin
    l_output.put('final_message', big_clob(100000));

    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => json_object_t('{"output_key":"big"}')
    , p_step_output      => l_output
    , pio_workflow_state => l_state
    );

    ut.expect(sys.dbms_lob.getlength(l_state.get_object('steps').get_clob('big'))).to_equal(100000);
  end add_result_clob_final_message;


  procedure add_result_non_string_final_message
  as
    l_state json_object_t := json_object_t();
    l_saved json_object_t;
  begin
    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => json_object_t('{"output_key":"obj"}')
    , p_step_output      => json_object_t('{"final_message":{"a":1}}')
    , pio_workflow_state => l_state
    );

    l_saved := treat(l_state.get_object('steps').get('obj') as json_object_t);
    ut.expect(l_saved.get_number('a')).to_equal(1);
  end add_result_non_string_final_message;


  procedure final_message_object_expression
  as
    l_state  json_object_t := json_object_t('{"steps":{"a":"X"}}');
    l_result clob;
  begin
    l_result := uc_ai_agent_workflow_api.evaluate_final_message(
      p_final_message  => json_object_t('{"expression":"Result: {$.steps.a}"}')
    , p_workflow_state => l_state
    );

    ut.expect(l_result).to_equal(to_clob('Result: X'));
  end final_message_object_expression;


  procedure final_message_string_element_quotes
  as
    l_def    json_object_t := json_object_t('{"final_message":"Hi {$.steps.a}"}');
    l_state  json_object_t := json_object_t('{"steps":{"a":"X"}}');
    l_result clob;
  begin
    -- a plain string final_message (as read from a workflow definition via
    -- get()) must resolve to its string value, not its JSON serialization
    l_result := uc_ai_agent_workflow_api.evaluate_final_message(
      p_final_message  => l_def.get('final_message')
    , p_workflow_state => l_state
    );

    ut.expect(l_result).to_equal(to_clob('Hi X'));
  end final_message_string_element_quotes;


  procedure final_message_clob_32k_plain
  as
    l_steps  json_object_t := json_object_t();
    l_state  json_object_t := json_object_t();
    l_result clob;
  begin
    l_steps.put('big', big_clob(40000));
    l_state.put('steps', l_steps);

    l_result := uc_ai_agent_workflow_api.evaluate_final_message(
      p_final_message  => json_object_t('{"expression":"{$.steps.big}"}')
    , p_workflow_state => l_state
    );

    ut.expect(sys.dbms_lob.getlength(l_result)).to_equal(40000);
  end final_message_clob_32k_plain;


  procedure final_message_plsql_expression
  as
    l_state  json_object_t := json_object_t('{"steps":{"word":"hello"}}');
    l_result clob;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    l_result := uc_ai_agent_workflow_api.evaluate_final_message(
      p_final_message  => json_object_t('{"expression":"upper(''{$.steps.word}'')","is_plsql_expression":true}')
    , p_workflow_state => l_state
    );

    ut.expect(l_result).to_equal(to_clob('HELLO'));
  end final_message_plsql_expression;


  procedure final_message_plsql_oversized
  as
    l_steps  json_object_t := json_object_t();
    l_state  json_object_t := json_object_t();
    l_result clob;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    l_steps.put('big', big_clob(40000));
    l_state.put('steps', l_steps);

    begin
      l_result := uc_ai_agent_workflow_api.evaluate_final_message(
        p_final_message  => json_object_t('{"expression":"''{$.steps.big}''","is_plsql_expression":true}')
      , p_workflow_state => l_state
      );
      ut.fail('Expected final_message evaluation to raise for an oversized value');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_final_message_eval);
    end;
  end final_message_plsql_oversized;


  procedure final_message_plsql_invalid
  as
    l_state  json_object_t := json_object_t('{"steps":{}}');
    l_result clob;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    l_result := uc_ai_agent_workflow_api.evaluate_final_message(
      p_final_message  => json_object_t('{"expression":"this is not plsql(","is_plsql_expression":true}')
    , p_workflow_state => l_state
    );
  end final_message_plsql_invalid;


  procedure jsonpath_resolve_error
  as
    l_state  json_object_t := json_object_t('{"steps":{"list":["a"]}}');
    l_result json_object_t;
  begin
    -- the array index overflows pls_integer inside resolve_path_value
    l_result := uc_ai_agent_workflow_api.map_inputs(
      p_input_mapping  => json_object_t('{"v":"{$.steps.list[99999999999]}"}')
    , p_workflow_state => l_state
    );
  end jsonpath_resolve_error;


  procedure history_null_config_passthrough
  as
    l_history json_array_t := make_history(5);
    l_result  json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => l_history
    , p_history_management => null
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(5);
    ut.expect(history_content(l_result, 0)).to_equal('msg 1');
    ut.expect(history_content(l_result, 4)).to_equal('msg 5');
  end history_null_config_passthrough;


  procedure history_full_passthrough
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(5)
    , p_history_management => json_object_t('{"strategy":"full"}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(5);
  end history_full_passthrough;


  procedure history_window_under_limit
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(5)
    , p_history_management => json_object_t('{"strategy":"sliding_window","max_messages":10}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(5);
  end history_window_under_limit;


  procedure history_window_trims
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(10)
    , p_history_management => json_object_t('{"strategy":"sliding_window","max_messages":4}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(4);
    ut.expect(history_content(l_result, 0)).to_equal('msg 7');
    ut.expect(history_content(l_result, 3)).to_equal('msg 10');
  end history_window_trims;


  procedure history_window_keeps_system
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(10, p_with_system => true)
    , p_history_management => json_object_t('{"strategy":"sliding_window","max_messages":4}')
    , p_session_id         => 'test-session'
    );

    -- system message plus the last 4 messages
    ut.expect(l_result.get_size).to_equal(5);
    ut.expect(treat(l_result.get(0) as json_object_t).get_string('role')).to_equal('system');
    ut.expect(history_content(l_result, 1)).to_equal('msg 7');
    ut.expect(history_content(l_result, 4)).to_equal('msg 10');
  end history_window_keeps_system;


  procedure history_window_default_20
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(25)
    , p_history_management => json_object_t('{"strategy":"sliding_window"}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(20);
    ut.expect(history_content(l_result, 0)).to_equal('msg 6');
    ut.expect(history_content(l_result, 19)).to_equal('msg 25');
  end history_window_default_20;


  procedure history_summarize_fallback_window
  as
    l_result json_array_t;
  begin
    -- no summarizer_agent_code: falls back to a window of the last
    -- summarize_after messages without calling any agent
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(5)
    , p_history_management => json_object_t('{"strategy":"summarize","summarize_after":3}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(3);
    ut.expect(history_content(l_result, 0)).to_equal('msg 3');
    ut.expect(history_content(l_result, 2)).to_equal('msg 5');
  end history_summarize_fallback_window;


  procedure history_summarize_under_threshold
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(5)
    , p_history_management => json_object_t('{"strategy":"summarize","summarize_after":10}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(5);
  end history_summarize_under_threshold;


  procedure history_unknown_strategy_passthrough
  as
    l_result json_array_t;
  begin
    l_result := uc_ai_agent_workflow_api.manage_history(
      p_history            => make_history(5)
    , p_history_management => json_object_t('{"strategy":"bogus"}')
    , p_session_id         => 'test-session'
    );

    ut.expect(l_result.get_size).to_equal(5);
  end history_unknown_strategy_passthrough;


  -- --------------------------------------------------------------------------
  -- PL/SQL-expression injection resistance
  -- --------------------------------------------------------------------------

  procedure condition_injection_blocked
  as
    l_state json_object_t;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    -- an untrusted state value crafted to break out of its string literal and
    -- force the condition true must instead be treated as a plain string
    l_state := json_object_t('{"steps":{"s":"x'' or ''a''=''a"}}');

    ut.expect(
      uc_ai_agent_workflow_api.evaluate_condition('''{$.steps.s}'' = ''safe''', l_state)
    ).to_be_false();
  end condition_injection_blocked;


  procedure condition_quoted_value_matches
  as
    l_state json_object_t;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    -- a legitimate value containing an apostrophe must compare correctly once
    -- both sides are escaped consistently
    l_state := json_object_t('{"steps":{"name":"O''Brien"}}');

    ut.expect(
      uc_ai_agent_workflow_api.evaluate_condition('''{$.steps.name}'' = ''O''''Brien''', l_state)
    ).to_be_true();
  end condition_quoted_value_matches;


  procedure map_inputs_plain_keeps_raw_quotes
  as
    l_state  json_object_t;
    l_result json_object_t;
  begin
    -- plain (non-PL/SQL) mappings feed JSON output, not code, so quotes must be
    -- preserved verbatim and never doubled
    l_state  := json_object_t('{"steps":{"name":"O''Brien"}}');
    l_result := uc_ai_agent_workflow_api.map_inputs(
      json_object_t('{"name":"{$.steps.name}"}'), l_state);

    ut.expect(l_result.get_string('name')).to_equal(q'[O'Brien]');
  end map_inputs_plain_keeps_raw_quotes;


  procedure map_inputs_plsql_escapes_quotes
  as
    l_state  json_object_t;
    l_result json_object_t;
  begin
    uc_ai_agent_exec_api.create_apex_session_if_needed;

    -- PL/SQL-expression mappings must escape the resolved value so an embedded
    -- quote cannot break the expression, and still evaluate correctly
    l_state  := json_object_t('{"steps":{"name":"o''brien"}}');
    l_result := uc_ai_agent_workflow_api.map_inputs(
      json_object_t('{"name":{"expression":"upper(''{$.steps.name}'')","is_plsql_expression":true}}'),
      l_state);

    ut.expect(l_result.get_string('name')).to_equal(q'[O'BRIEN]');
  end map_inputs_plsql_escapes_quotes;

end test_uc_ai_workflow_mapping;
/
