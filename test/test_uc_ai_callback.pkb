create or replace package body test_uc_ai_callback as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-7230): allow package state in test helper

  c_sink_proc    constant varchar2(64 char) := 'TEST_UC_AI_CALLBACK.SINK_ON_EV';
  c_raising_proc constant varchar2(64 char) := 'TEST_UC_AI_CALLBACK.SINK_RAISING';

  -- in-memory event sink populated by sink_on_ev
  type t_event_rec is record (
    req_id  varchar2(32 char),
    ev      varchar2(64 char),
    payload clob
  );
  type t_event_tab is table of t_event_rec index by pls_integer;
  g_events t_event_tab;
  g_idx    pls_integer := 0;

  procedure sink_on_ev(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  )
  as
  begin
    g_idx := g_idx + 1;
    g_events(g_idx).req_id  := p_request_id;
    g_events(g_idx).ev      := p_event_type;
    g_events(g_idx).payload := p_event_data;
  end sink_on_ev;

  procedure sink_raising(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  )
  as
  begin
    raise_application_error(-20999, 'boom from sink_raising');
  end sink_raising;

  -- helpers
  procedure clear_sink
  as
  begin
    g_events.delete;
    g_idx := 0;
  end clear_sink;

  function count_by(p_event_type in varchar2) return pls_integer
  as
    l_n pls_integer := 0;
  begin
    for i in 1 .. g_idx loop
      if g_events(i).ev = p_event_type then
        l_n := l_n + 1;
      end if;
    end loop;
    return l_n;
  end count_by;

  function distinct_req_ids return pls_integer
  as
    l_seen sys.odcivarchar2list := sys.odcivarchar2list();
    l_known boolean;
  begin
    for i in 1 .. g_idx loop
      l_known := false;
      for j in 1 .. l_seen.count loop
        if l_seen(j) = g_events(i).req_id then
          l_known := true;
          exit;
        end if;
      end loop;
      if not l_known then
        l_seen.extend;
        l_seen(l_seen.count) := g_events(i).req_id;
      end if;
    end loop;
    return l_seen.count;
  end distinct_req_ids;

  -- lifecycle
  procedure setup_tests
  as
  begin
    null;
  end setup_tests;

  procedure reset_state
  as
  begin
    clear_sink;
    uc_ai.g_callback_fatal := false;
    uc_ai.g_request_id := null;
    uc_ai.set_event_callback(c_sink_proc);
  end reset_state;

  procedure teardown
  as
  begin
    uc_ai.clear_event_callback;
    uc_ai.g_request_id := null;
    uc_ai.g_callback_fatal := false;
  end teardown;

  -- tests (no API)
  procedure input_side_silence
  as
    l_ignore json_object_t;
  begin
    -- g_request_id is null; building content must not emit events
    l_ignore := uc_ai_message_api.create_text_content('input-side text');
    l_ignore := uc_ai_message_api.create_tool_call_content('id1', 'some_tool', '{}');
    ut.expect(g_idx).to_equal(0);
  end input_side_silence;

  procedure reset_preserves_callback
  as
    l_before varchar2(128 char);
    l_after  varchar2(128 char);
  begin
    l_before := uc_ai.g_event_callback;
    ut.expect(l_before).to_equal(c_sink_proc);

    uc_ai.reset_globals;

    l_after := uc_ai.g_event_callback;
    ut.expect(l_after).to_equal(l_before);
  end reset_preserves_callback;

  procedure clear_stops_firing
  as
    l_ignore json_object_t;
    l_count_after_first pls_integer;
  begin
    uc_ai.g_request_id := rawtohex(sys_guid());
    l_ignore := uc_ai_message_api.create_text_content('before clear');
    uc_ai.g_request_id := null;
    l_count_after_first := g_idx;
    ut.expect(l_count_after_first).to_be_greater_than(0);

    uc_ai.clear_event_callback;

    uc_ai.g_request_id := rawtohex(sys_guid());
    l_ignore := uc_ai_message_api.create_text_content('after clear');
    uc_ai.g_request_id := null;

    ut.expect(g_idx).to_equal(l_count_after_first);
  end clear_stops_firing;

  procedure error_swallowed_default
  as
    l_ignore json_object_t;
  begin
    uc_ai.set_event_callback(c_raising_proc);
    uc_ai.g_callback_fatal := false;
    uc_ai.g_request_id := rawtohex(sys_guid());

    -- must not raise
    l_ignore := uc_ai_message_api.create_text_content('swallow me');

    uc_ai.g_request_id := null;
    -- if we reach here, the error was swallowed as expected
    ut.expect(1).to_equal(1);
  end error_swallowed_default;

  procedure fatal_flag_propagates
  as
    l_ignore  json_object_t;
    l_raised  boolean := false;
    l_sqlcode pls_integer;
  begin
    uc_ai.set_event_callback(c_raising_proc);
    uc_ai.g_callback_fatal := true;
    uc_ai.g_request_id := rawtohex(sys_guid());

    begin
      l_ignore := uc_ai_message_api.create_text_content('should raise');
    exception
      when others then
        l_raised := true;
        l_sqlcode := sqlcode;
    end;

    uc_ai.g_request_id := null;
    ut.expect(l_raised).to_be_true();
    ut.expect(l_sqlcode).to_equal(-20999);
  end fatal_flag_propagates;

  procedure invalid_name_rejected
  as
    l_raised  boolean := false;
    l_sqlcode pls_integer;
  begin
    begin
      uc_ai.set_event_callback('not a valid name!!!');
    exception
      when others then
        l_raised := true;
        l_sqlcode := sqlcode;
    end;

    ut.expect(l_raised).to_be_true();
    -- dbms_assert raises ORA-44003 (bad name) or ORA-44004 (invalid qualified name)
    ut.expect(l_sqlcode in (-44003, -44004)).to_be_true();
  end invalid_name_rejected;

  -- tests (OpenAI API)
  procedure fires_text_and_complete
  as
    l_result json_object_t;
  begin
    l_result := uc_ai.generate_text(
      p_user_prompt => 'Say hello in one very short sentence.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Event count: ' || g_idx);

    ut.expect(count_by(uc_ai.c_event_assistant_text)).to_be_greater_or_equal(1);
    ut.expect(count_by(uc_ai.c_event_response_complete)).to_equal(1);
    ut.expect(distinct_req_ids).to_equal(1);

    -- response_complete payload must carry finish_reason and provider fields
    declare
      l_last_payload clob;
    begin
      for i in 1 .. g_idx loop
        if g_events(i).ev = uc_ai.c_event_response_complete then
          l_last_payload := g_events(i).payload;
        end if;
      end loop;
      ut.expect(lower(l_last_payload)).to_be_like('%"provider":"openai"%');
      ut.expect(lower(l_last_payload)).to_be_like('%finish_reason%');
    end;
  end fires_text_and_complete;

  procedure fires_tool_events
  as
    l_result json_object_t;
    l_text_idx pls_integer := null;
    l_call_idx pls_integer := null;
    l_result_idx pls_integer := null;
    l_complete_idx pls_integer := null;
  begin
    delete from uc_ai_tools where 1 = 1;
    uc_ai_test_utils.add_get_users_tool;
    uc_ai.g_enable_tools := true;

    l_result := uc_ai.generate_text(
      p_user_prompt   => 'What is the email address of Jim?'
    , p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user info. Answer concise and short.'
    , p_provider      => uc_ai.c_provider_openai
    , p_model         => uc_ai_openai.c_model_gpt_4o_mini
    );

    sys.dbms_output.put_line('Event count: ' || g_idx);
    for i in 1 .. g_idx loop
      sys.dbms_output.put_line(i || ': ' || g_events(i).ev);
    end loop;

    ut.expect(count_by(uc_ai.c_event_tool_call)).to_be_greater_or_equal(1);
    ut.expect(count_by(uc_ai.c_event_tool_result)).to_be_greater_or_equal(1);
    ut.expect(count_by(uc_ai.c_event_assistant_text)).to_be_greater_or_equal(1);
    ut.expect(count_by(uc_ai.c_event_response_complete)).to_equal(1);
    ut.expect(distinct_req_ids).to_equal(1);

    -- order: tool_call appears before its matching tool_result, and before the final response_complete
    for i in 1 .. g_idx loop
      if l_call_idx is null and g_events(i).ev = uc_ai.c_event_tool_call then
        l_call_idx := i;
      end if;
      if l_call_idx is not null and l_result_idx is null and g_events(i).ev = uc_ai.c_event_tool_result then
        l_result_idx := i;
      end if;
      if g_events(i).ev = uc_ai.c_event_response_complete then
        l_complete_idx := i;
      end if;
      if g_events(i).ev = uc_ai.c_event_assistant_text then
        l_text_idx := i;
      end if;
    end loop;

    ut.expect(l_call_idx).to_be_not_null();
    ut.expect(l_result_idx).to_be_not_null();
    ut.expect(l_complete_idx).to_be_not_null();
    ut.expect(l_result_idx > l_call_idx).to_be_true();
    ut.expect(l_complete_idx >= nvl(l_text_idx, l_result_idx)).to_be_true();
  end fires_tool_events;

  procedure request_id_is_per_call
  as
    l_r1 json_object_t;
    l_r2 json_object_t;
  begin
    l_r1 := uc_ai.generate_text(
      p_user_prompt => 'Reply with the single word: one'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => uc_ai_openai.c_model_gpt_4o_mini
    );
    l_r2 := uc_ai.generate_text(
      p_user_prompt => 'Reply with the single word: two'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => uc_ai_openai.c_model_gpt_4o_mini
    );

    ut.expect(distinct_req_ids).to_be_greater_or_equal(2);
    ut.expect(count_by(uc_ai.c_event_response_complete)).to_equal(2);
  end request_id_is_per_call;

end test_uc_ai_callback;
/
