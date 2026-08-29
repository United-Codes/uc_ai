create or replace package body test_uc_ai_responses_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-7230): allow package state in test helper
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its code; a backtrace adds nothing

  -- Named on every call so no provider ever asks uc_ai_get_key for a key. The
  -- mock records the name; nothing resolves it.
  c_credential constant varchar2(30 char) := 'WIRE_TEST_CREDENTIAL';

  c_model constant varchar2(30 char) := 'gpt-4o-mini';

  -- WIRE_D_ prefix: the suite must not contend with another suite on a uc_ai_tools row
  c_users_tool  constant uc_ai_tools.code%type := 'WIRE_D_USERS';
  c_params_tool constant uc_ai_tools.code%type := 'WIRE_D_PARAMS';
  c_tool_tag    constant varchar2(30 char) := 'wire_d_test';

  c_sink_proc constant varchar2(64 char) := 'TEST_UC_AI_RESPONSES_WIRE.SINK_ON_EV';

  -- the last argument object a registered tool was called with
  g_last_args json_object_t;

  -- event type -> number of times the sink saw it
  type t_event_counts is table of pls_integer index by varchar2(64 char);
  -- @dblinter ignore(g-9105): package-global collection of a test helper, g_ prefix is intended
  g_event_counts t_event_counts;


  -- ---- tool handlers and the event sink ----------------------------------------

  function echo_args(p_args in clob) return clob
  as
  begin
    g_last_args := json_object_t.parse(p_args);
    return 'ok';
  end echo_args;


  function users_result return clob
  as
  begin
    return to_clob('[{"name":"Jim","email":"jim.halpert@dundermifflin.com"}]');
  end users_result;


  -- @dblinter ignore(g-7150): the event sink signature is fixed by uc_ai.fire_event; only the type is counted
  procedure sink_on_ev(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  )
  as
  begin
    if g_event_counts.exists(p_event_type) then
      g_event_counts(p_event_type) := g_event_counts(p_event_type) + 1;
    else
      g_event_counts(p_event_type) := 1;
    end if;
  end sink_on_ev;


  function event_count(p_event_type in varchar2) return pls_integer
  as
  begin
    if g_event_counts.exists(p_event_type) then
      return g_event_counts(p_event_type);
    end if;

    return 0;
  end event_count;


  -- ---- helpers -----------------------------------------------------------------

  /*
   * A generate_text config that names the web credential plus whatever the test
   * adds. Config-driven calls read no globals, so a test states its whole setup in
   * one place.
   */
  function config(p_json in varchar2 default '{}') return json_object_t
  as
    l_config json_object_t := json_object_t.parse(p_json);
  begin
    l_config.put('g_apex_web_credential', c_credential);
    return l_config;
  end config;


  /*
   * A Responses API envelope in the shape the recorded samples have: 'status' and
   * 'incomplete_details' report the outcome, there is no 'stop_reason' key.
   * p_with_output false leaves the 'output' array out entirely, which is the one
   * shape the framework cannot answer from.
   */
  function responses_body(
    p_output            in json_array_t
  , p_id                in varchar2    default 'resp_wire_d'
  , p_status            in varchar2    default 'completed'
  , p_incomplete_reason in varchar2    default null
  , p_with_output       in boolean     default true
  ) return clob
  as
    l_body    json_object_t := json_object_t();
    l_usage   json_object_t := json_object_t();
    l_details json_object_t := json_object_t();
  begin
    l_usage.put('input_tokens', 10);
    l_usage.put('output_tokens', 5);
    l_usage.put('total_tokens', 15);

    l_body.put('id', p_id);
    l_body.put('object', 'response');
    l_body.put('status', p_status);
    l_body.put('model', 'gpt-4o-mini-2024-07-18');

    if p_incomplete_reason is null then
      l_body.put_null('incomplete_details');
    else
      l_details.put('reason', p_incomplete_reason);
      l_body.put('incomplete_details', l_details);
    end if;

    if p_with_output then
      l_body.put('output', p_output);
    end if;

    l_body.put('usage', l_usage);

    return l_body.to_clob;
  end responses_body;


  function text_output(
    p_text in clob
  , p_id   in varchar2 default 'msg_wire_d'
  ) return json_array_t
  as
    l_output  json_array_t := json_array_t();
    l_message json_object_t := json_object_t();
    l_content json_array_t := json_array_t();
    l_text    json_object_t := json_object_t();
  begin
    l_text.put('type', 'output_text');
    l_text.put('annotations', json_array_t());
    l_text.put('text', p_text);
    l_content.append(l_text);

    l_message.put('id', p_id);
    l_message.put('type', 'message');
    l_message.put('status', 'completed');
    l_message.put('role', 'assistant');
    l_message.put('content', l_content);
    l_output.append(l_message);

    return l_output;
  end text_output;


  function function_call_item(
    p_call_id   in varchar2
  , p_name      in varchar2
  , p_arguments in varchar2 default '{}'
  ) return json_object_t
  as
    l_item json_object_t := json_object_t();
  begin
    l_item.put('id', 'fc_' || p_call_id);
    l_item.put('type', 'function_call');
    l_item.put('status', 'completed');
    l_item.put('call_id', p_call_id);
    l_item.put('name', p_name);
    l_item.put('arguments', p_arguments);

    return l_item;
  end function_call_item;


  function function_call_output_item(
    p_call_id in varchar2
  , p_output  in clob
  ) return json_object_t
  as
    l_item json_object_t := json_object_t();
  begin
    l_item.put('id', 'fco_' || p_call_id);
    l_item.put('type', 'function_call_output');
    l_item.put('call_id', p_call_id);
    l_item.put('output', p_output);

    return l_item;
  end function_call_output_item;


  function one_item(p_item in json_object_t) return json_array_t
  as
    l_output json_array_t := json_array_t();
  begin
    l_output.append(p_item);

    return l_output;
  end one_item;


  /*
   * A CLOB of p_length characters, built above the 32767-byte varchar2 limit so a
   * get_string on the way through raises ORA-06502.
   */
  function long_text(p_length in pls_integer) return clob
  as
    c_chunk constant varchar2(40 char) := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcd';
    -- starts with one chunk, because to_clob('') is NULL and the loop would never run
    l_text  clob := to_clob(c_chunk);
  begin
    <<fill_loop>>
    while sys.dbms_lob.getlength(l_text) < p_length
    loop
      l_text := l_text || c_chunk;
    end loop fill_loop;

    return l_text;
  end long_text;


  /*
   * Asserts an input item was found without handing the item itself to ut.expect:
   * serializing a json_object_t that carries a 40 KB value raises JZN-00018 inside
   * the utPLSQL reporter.
   */
  procedure expect_present(
    p_item    in json_object_t
  , p_message in varchar2
  )
  as
  begin
    ut.expect(case when p_item is null then 'missing' else 'present' end, p_message).to_equal('present');
  end expect_present;


  procedure expect_all_consumed(p_requests in pls_integer)
  as
  begin
    ut.expect(uc_ai_test_http_mock.request_count, 'requests made').to_equal(p_requests);
    ut.expect(uc_ai_test_http_mock.pending_count, 'responses nobody asked for').to_equal(0);
  end expect_all_consumed;


  /*
   * The p_occurrence-th input item of the given type in the given request, or null.
   */
  function input_item(
    p_request    in pls_integer
  , p_type       in varchar2
  , p_occurrence in pls_integer default 1
  ) return json_object_t
  as
    l_input json_array_t := uc_ai_test_http_mock.request_json(p_request).get_array('input');
    l_item  json_object_t;
    l_seen  pls_integer := 0;
  begin
    <<input_loop>>
    for i in 0 .. l_input.get_size - 1
    loop
      l_item := treat(l_input.get(i) as json_object_t);

      if l_item.get_string('type') = p_type then
        l_seen := l_seen + 1;
        if l_seen = p_occurrence then
          return l_item;
        end if;
      end if;
    end loop input_loop;

    return null;
  end input_item;


  function count_input_items(
    p_request in pls_integer
  , p_type    in varchar2
  ) return pls_integer
  as
    l_input json_array_t := uc_ai_test_http_mock.request_json(p_request).get_array('input');
    l_count pls_integer := 0;
  begin
    <<input_loop>>
    for i in 0 .. l_input.get_size - 1
    loop
      if treat(l_input.get(i) as json_object_t).get_string('type') = p_type then
        l_count := l_count + 1;
      end if;
    end loop input_loop;

    return l_count;
  end count_input_items;


  /*
   * Every content item of every assistant message of the result, flattened, so a
   * test can assert on the normalized shape without walking the history itself.
   */
  function assistant_content_types(p_result in json_object_t) return varchar2
  as
    l_messages json_array_t := treat(p_result.get('messages') as json_array_t);
    l_message  json_object_t;
    l_content  json_array_t;
    l_types    varchar2(4000 char);
  begin
    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1
    loop
      l_message := treat(l_messages.get(i) as json_object_t);

      continue when l_message.get_string('role') != 'assistant' or not l_message.get('content').is_array;

      l_content := treat(l_message.get('content') as json_array_t);

      <<content_loop>>
      for j in 0 .. l_content.get_size - 1
      loop
        l_types := l_types || treat(l_content.get(j) as json_object_t).get_string('type') || ' ';
      end loop content_loop;
    end loop message_loop;

    return l_types;
  end assistant_content_types;


  procedure register_users_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_users_tool;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_users_tool
    , p_description   => 'Get information on all the users in the system'
    , p_function_call => 'return test_uc_ai_responses_wire.users_result;'
    , p_json_schema   => json_object_t('{"type":"object","properties":{}}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'users tool registered').to_be_not_null();
  end register_users_tool;


  /*
   * A flat tool that declares a scalar property literally named "parameters". The
   * request builder must not read that property as an argument wrapper.
   */
  procedure register_params_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_params_tool;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_params_tool
    , p_description   => 'Run a report with a parameters string'
    , p_function_call => 'return test_uc_ai_responses_wire.echo_args(:args);'
    , p_json_schema   => json_object_t('{"type":"object","properties":'
                          || '{"parameters":{"type":"string","description":"Report parameters"}'
                          || ',"unit":{"type":"string","description":"Unit"}}'
                          || ',"required":["parameters","unit"]}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'params tool registered').to_be_not_null();
  end register_params_tool;


  -- ---- fixtures ----------------------------------------------------------------

  procedure register_mock
  as
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
  end register_mock;


  procedure unregister_mock
  as
  begin
    uc_ai_http.set_transport(null);
    uc_ai.clear_event_callback;
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    -- reset_globals deliberately keeps the event callback, so clear it by hand:
    -- a sink left behind by one test would count the events of the next.
    uc_ai.clear_event_callback;
    uc_ai_test_http_mock.reset;
    g_last_args := null;
    g_event_counts.delete;
  end reset_state;


  -- ---- finish_reason -------------------------------------------------------------

  procedure finish_reason_stop_on_completed
  as
    l_result json_object_t;
  begin
    -- The recorded response: status completed, incomplete_details JSON null, and
    -- no stop_reason key anywhere.
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('openai/responses/1-simple-response'));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Say hello.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_model
    , p_config      => config
    );

    ut.expect(uc_ai_test_samples.get_json('openai/responses/1-simple-response').has('stop_reason')
            , 'the recorded response has no stop_reason key').to_be_false();
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    expect_all_consumed(1);
  end finish_reason_stop_on_completed;


  procedure finish_reason_length_on_truncation
  as
    l_result json_object_t;
  begin
    -- A truncated response still carries the partial answer; only
    -- incomplete_details.reason says it was cut off.
    uc_ai_test_http_mock.enqueue(responses_body(
      p_output            => text_output('The capital of France is')
    , p_status            => 'incomplete'
    , p_incomplete_reason => 'max_output_tokens'
    ));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Write a long essay.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_model
    , p_config      => config
    );

    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_length);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('The capital of France is'));
    expect_all_consumed(1);
  end finish_reason_length_on_truncation;


  procedure finish_reason_content_filter
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(responses_body(
      p_output            => text_output('I cannot help with')
    , p_status            => 'incomplete'
    , p_incomplete_reason => 'content_filter'
    ));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Something the policy blocks.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_model
    , p_config      => config
    );

    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_content_filter);
    expect_all_consumed(1);
  end finish_reason_content_filter;


  procedure finish_reason_unmapped_incomplete
  as
    l_result json_object_t;
  begin
    -- A reason the API may add later. There is no constant for it, so the result
    -- falls back to a documented value rather than passing the raw string on.
    uc_ai_test_http_mock.enqueue(responses_body(
      p_output            => text_output('Partial.')
    , p_status            => 'incomplete'
    , p_incomplete_reason => 'some_future_reason'
    ));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Anything.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_model
    , p_config      => config
    );

    -- The raw provider string must not leak into the result: callers branch on the
    -- documented set, and there is no constant for an unknown reason.
    ut.expect(l_result.get_string('finish_reason'), 'raw reason must not leak')
      .not_to_equal('some_future_reason');
    ut.expect(l_result.get_string('finish_reason'), 'documented fallback')
      .to_equal(uc_ai.c_finish_reason_stop);
    expect_all_consumed(1);
  end finish_reason_unmapped_incomplete;


  procedure finish_reason_max_tool_calls
  as
    l_result json_object_t;
  begin
    register_users_tool;

    -- Two turns that both ask for the tool, with a budget of one: the second turn
    -- ends the run with a tool call still outstanding.
    uc_ai_test_http_mock.enqueue(responses_body(one_item(function_call_item('call_d_1', c_users_tool)), 'resp_d_1'));
    uc_ai_test_http_mock.enqueue(responses_body(one_item(function_call_item('call_d_2', c_users_tool)), 'resp_d_2'));

    l_result := uc_ai.generate_text(
      p_user_prompt    => 'Who is Jim?'
    , p_provider       => uc_ai.c_provider_openai
    , p_model          => c_model
    , p_config         => config('{"g_enable_tools":true,"g_tool_tags":["wire_d_test"]}')
    , p_max_tool_calls => 1
    );

    ut.expect(l_result.get_string('finish_reason')).to_equal('max_tool_calls_exceeded');
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    expect_all_consumed(2);
  end finish_reason_max_tool_calls;


  procedure missing_output_raises
  as
    l_result  json_object_t;
    l_sqlcode number;
  begin
    -- A 200 with no output array. Answering with a null final_message hid the
    -- reason behind a result that looked successful.
    uc_ai_test_http_mock.enqueue(responses_body(
      p_output            => json_array_t()
    , p_status            => 'incomplete'
    , p_incomplete_reason => 'max_output_tokens'
    , p_with_output       => false
    ));

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => 'Anything.'
      , p_provider    => uc_ai.c_provider_openai
      , p_model       => c_model
      , p_config      => config
      );
    exception
      -- @dblinter ignore(g-5040): the test asserts on the code of whatever was raised
      when others then
        l_sqlcode := sqlcode;
    end;

    ut.expect(l_sqlcode, 'raised -20302').to_equal(uc_ai_error.c_err_provider_response);
    expect_all_consumed(1);
  end missing_output_raises;


  -- ---- normalized history --------------------------------------------------------

  procedure tool_call_replays_after_budget
  as
    l_result    json_object_t;
    l_replayed  json_object_t;
    l_messages  json_array_t;
  begin
    register_users_tool;
    uc_ai.set_event_callback(c_sink_proc);

    uc_ai_test_http_mock.enqueue(responses_body(one_item(function_call_item('call_d_1', c_users_tool)), 'resp_d_1'));
    uc_ai_test_http_mock.enqueue(responses_body(one_item(function_call_item('call_d_2', c_users_tool)), 'resp_d_2'));

    l_result := uc_ai.generate_text(
      p_user_prompt    => 'Who is Jim?'
    , p_provider       => uc_ai.c_provider_openai
    , p_model          => c_model
    , p_config         => config('{"g_enable_tools":true,"g_tool_tags":["wire_d_test"]}')
    , p_max_tool_calls => 1
    );

    -- The outstanding call is normalized with the shared builder, so it is a
    -- 'tool_call' content item and the tool_call event fired for it. It used to be
    -- a hand-built Anthropic-shaped 'tool_use' block, which fired nothing.
    ut.expect(assistant_content_types(l_result), 'normalized assistant content')
      .to_equal('tool_call tool_call ');
    ut.expect(event_count(uc_ai.c_event_tool_call), 'tool_call events').to_equal(2);

    -- Feeding the returned history back must reproduce both calls on the wire.
    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_http_mock.reset;
    uc_ai_test_http_mock.enqueue(responses_body(text_output('Jim is jim.halpert@dundermifflin.com.'), 'resp_d_3'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_openai
    , p_model    => c_model
    , p_config   => config
    );

    ut.expect(count_input_items(1, 'function_call'), 'both tool calls replayed').to_equal(2);
    ut.expect(count_input_items(1, 'function_call_output'), 'the executed call is answered').to_equal(1);

    l_replayed := input_item(1, 'function_call', 2);
    expect_present(l_replayed, 'the outstanding call reached the wire');
    ut.expect(l_replayed.get_string('call_id')).to_equal('call_d_2');
    ut.expect(l_replayed.get_string('name')).to_equal(c_users_tool);
    ut.expect(l_replayed.get_clob('arguments')).to_equal(to_clob('{}'));

    expect_all_consumed(1);
  end tool_call_replays_after_budget;


  procedure tool_result_replays_as_output_item
  as
    l_result   json_object_t;
    l_output   json_array_t := json_array_t();
    l_messages json_array_t;
    l_item     json_object_t;
  begin
    register_users_tool;

    -- A turn that carries both the call and its answer, as a provider-executed
    -- tool does. A budget of zero stops the loop before UC AI runs anything, so
    -- only the normalization of the returned items is under test.
    l_output.append(function_call_item('call_d_1', c_users_tool));
    l_output.append(function_call_output_item('call_d_1', users_result));
    uc_ai_test_http_mock.enqueue(responses_body(l_output, 'resp_d_1'));

    l_result := uc_ai.generate_text(
      p_user_prompt    => 'Who is Jim?'
    , p_provider       => uc_ai.c_provider_openai
    , p_model          => c_model
    , p_config         => config('{"g_enable_tools":true,"g_tool_tags":["wire_d_test"]}')
    , p_max_tool_calls => 0
    );

    ut.expect(l_result.get_number('tool_calls_count'), 'nothing was executed').to_equal(0);

    l_messages := treat(l_result.get('messages') as json_array_t);
    uc_ai_test_http_mock.reset;
    uc_ai_test_http_mock.enqueue(responses_body(text_output('Jim it is.'), 'resp_d_2'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_openai
    , p_model    => c_model
    , p_config   => config
    );

    l_item := input_item(1, 'function_call');
    expect_present(l_item, 'the call replayed');
    ut.expect(l_item.get_string('call_id')).to_equal('call_d_1');

    l_item := input_item(1, 'function_call_output');
    expect_present(l_item, 'the result replayed');
    ut.expect(l_item.get_string('call_id')).to_equal('call_d_1');
    ut.expect(l_item.get_clob('output')).to_equal(users_result);

    expect_all_consumed(1);
  end tool_result_replays_as_output_item;


  -- ---- 32 KB ceilings --------------------------------------------------------------

  procedure large_tool_result_replays_whole
  as
    l_result     json_object_t;
    l_big        clob := long_text(40000);
    l_messages   json_array_t := json_array_t();
    l_call       json_array_t := json_array_t();
    l_tool       json_array_t := json_array_t();
    l_item       json_object_t;
  begin
    -- A history whose tool result is above the varchar2 limit. get_string on the
    -- replay path raised ORA-06502 here, and every result UC AI itself produces
    -- takes that branch.
    l_call.append(uc_ai_message_api.create_tool_call_content('call_d_1', c_users_tool, '{}'));
    l_tool.append(uc_ai_message_api.create_tool_result_content('call_d_1', c_users_tool, l_big));

    l_messages.append(uc_ai_message_api.create_simple_user_message('List everything.'));
    l_messages.append(uc_ai_message_api.create_assistant_message(l_call));
    l_messages.append(uc_ai_message_api.create_tool_message(l_tool));

    uc_ai_test_http_mock.enqueue(responses_body(text_output('Done.'), 'resp_d_1'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_openai
    , p_model    => c_model
    , p_config   => config
    );

    l_item := input_item(1, 'function_call_output');
    expect_present(l_item, 'the result replayed');
    ut.expect(sys.dbms_lob.getlength(l_item.get_clob('output')), 'the whole result reached the wire').to_equal(40000);
    -- compared with dbms_lob, not ut.expect: a failing 40 KB comparison would be
    -- reported by serializing both sides, which raises inside the reporter
    ut.expect(sys.dbms_lob.compare(l_item.get_clob('output'), l_big), 'the result is unchanged').to_equal(0);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Done.'));
    expect_all_consumed(1);
  end large_tool_result_replays_whole;


  procedure large_answer_is_not_truncated
  as
    l_result   json_object_t;
    l_big      clob := long_text(40000);
    l_messages json_array_t;
    l_content  json_array_t;
  begin
    -- Model text has no size bound on the wire, so both the normalization and the
    -- final_message extraction must read it as a CLOB.
    uc_ai_test_http_mock.enqueue(responses_body(text_output(l_big), 'resp_d_1'));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Write a lot.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_model
    , p_config      => config
    );

    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('final_message')), 'final_message length').to_equal(40000);
    ut.expect(sys.dbms_lob.compare(l_result.get_clob('final_message'), l_big), 'the answer is unchanged').to_equal(0);

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_content := treat(treat(l_messages.get(l_messages.get_size - 1) as json_object_t).get('content') as json_array_t);
    ut.expect(sys.dbms_lob.getlength(treat(l_content.get(0) as json_object_t).get_clob('text')), 'normalized text length')
      .to_equal(40000);

    expect_all_consumed(1);
  end large_answer_is_not_truncated;


  -- ---- request building --------------------------------------------------------------

  procedure scalar_parameters_is_not_unwrapped
  as
    l_result json_object_t;
  begin
    register_params_tool;

    -- "parameters" here is one of the tool's own properties, not the argument
    -- wrapper some models add. Unwrapping it left the handler with no arguments.
    uc_ai_test_http_mock.enqueue(responses_body(
      one_item(function_call_item('call_d_1', c_params_tool, '{"parameters":"monthly","unit":"EUR"}'))
    , 'resp_d_1'));
    uc_ai_test_http_mock.enqueue(responses_body(text_output('Report ready.'), 'resp_d_2'));

    l_result := uc_ai.generate_text(
      p_user_prompt    => 'Run the monthly report in EUR.'
    , p_provider       => uc_ai.c_provider_openai
    , p_model          => c_model
    , p_config         => config('{"g_enable_tools":true,"g_tool_tags":["wire_d_test"]}')
    , p_max_tool_calls => 3
    );

    ut.expect(g_last_args, 'the handler was called with arguments').to_be_not_null();
    ut.expect(g_last_args.get_string('parameters'), 'the property survived').to_equal('monthly');
    ut.expect(g_last_args.get_string('unit'), 'the sibling property survived').to_equal('EUR');
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    expect_all_consumed(2);
  end scalar_parameters_is_not_unwrapped;


  procedure encrypted_reasoning_included_when_not_stored
  as
    l_result  json_object_t;
    l_request json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(responses_body(text_output('Paris.'), 'resp_d_1'));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Capital of France?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-5-mini'
    , p_config      => config('{"g_enable_reasoning":true,"g_reasoning_level":"low"}')
    );

    l_request := uc_ai_test_http_mock.request_json(1);

    -- store defaults to false, and nothing is persisted server-side then, so the
    -- encrypted blob is the only way the reasoning item can be replayed.
    ut.expect(l_request.get_boolean('store')).to_be_false();
    ut.expect(l_request.get_array('include')).to_equal(json_array_t('["reasoning.encrypted_content"]'));
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Paris.'));
    expect_all_consumed(1);
  end encrypted_reasoning_included_when_not_stored;


  procedure encrypted_reasoning_omitted_when_stored
  as
    l_result  json_object_t;
    l_request json_object_t;
  begin
    -- store is only reachable through the package global; the config surface has
    -- no key for it.
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai.g_enable_reasoning := true;
    uc_ai_responses_api.g_store_responses := true;

    uc_ai_test_http_mock.enqueue(responses_body(text_output('Rome.'), 'resp_d_1'));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Capital of Italy?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-5-mini'
    );

    l_request := uc_ai_test_http_mock.request_json(1);

    -- With store=true the provider can reconstitute a reasoning item from its id,
    -- so the blob is not asked for.
    ut.expect(l_request.get_boolean('store')).to_be_true();
    ut.expect(l_request.has('include'), 'no include key').to_be_false();
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Rome.'));
    expect_all_consumed(1);
  end encrypted_reasoning_omitted_when_stored;

end test_uc_ai_responses_wire;
/
