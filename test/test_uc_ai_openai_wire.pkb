create or replace package body test_uc_ai_openai_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error test catches the expected exception to assert on its message; a backtrace adds nothing

  -- Tool codes carry the WIRE_C_ prefix so this suite can never contend with
  -- another suite on a uc_ai_tools row. Both rows roll back with the test.
  c_echo_tool_code constant uc_ai_tools.code%type := 'WIRE_C_ECHO_ARGS';
  c_big_tool_code  constant uc_ai_tools.code%type := 'WIRE_C_BIG_ARGS';
  c_tool_tag       constant varchar2(30 char) := 'wire_c_test';

  -- Named on every call so no provider ever asks uc_ai_get_key for a key. The
  -- mock records the name; nothing resolves it.
  c_credential constant varchar2(30 char) := 'WIRE_TEST_CREDENTIAL';

  -- The prompt test/samples/xai/5-reasoning-request.json was recorded with. A
  -- request only matches its sample when the prompt is the same text.
  c_filter_prompt constant varchar2(200 char) := 'Answer in one sentence. If there is a great filter, are we before or after it and why.';
  c_tool_prompt   constant varchar2(200 char) := 'What is the weather in Berlin?';

  c_xai_model  constant varchar2(50 char) := 'grok-4-fast-non-reasoning';
  c_chat_model constant varchar2(50 char) := 'gpt-4o-mini';

  -- Size of the oversized argument payload. Comfortably past the 32767-byte
  -- varchar2 ceiling that get_string imposes.
  c_big_payload_size constant pls_integer := 40000;


  -- ---- helpers ---------------------------------------------------------------

  /*
   * Escape a CLOB for use as a JSON string value. Only the two characters that
   * can appear in the payloads this suite builds are handled; nothing here comes
   * from outside the package.
   */
  function json_escape(p_text in clob) return clob
  as
  begin
    return replace(replace(p_text, '\', '\\'), '"', '\"');
  end json_escape;


  /*
   * A Chat Completions tool-call response, assembled as text rather than through
   * json_object_t so the arguments string can be larger than a varchar2 literal.
   */
  function tool_call_response(
    p_model     in varchar2
  , p_call_id   in varchar2
  , p_tool_code in varchar2
  , p_arguments in clob
  , p_content   in varchar2 default null
  ) return clob
  as
    l_body clob;
  begin
    l_body := '{"id":"chatcmpl-wire-c-1","object":"chat.completion","model":"' || p_model || '"'
           || ',"choices":[{"index":0,"message":{"role":"assistant","content":'
           || case when p_content is null then 'null' else '"' || p_content || '"' end
           || ',"tool_calls":[{"id":"' || p_call_id || '","type":"function","function":{"name":"'
           || p_tool_code || '","arguments":"';

    l_body := l_body || json_escape(p_arguments);

    l_body := l_body || '"}}]},"finish_reason":"tool_calls"}]'
           || ',"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}';

    return l_body;
  end tool_call_response;


  /*
   * A plain Chat Completions answer, the second half of every tool round trip.
   */
  function text_response(
    p_model in varchar2
  , p_text  in varchar2
  ) return clob
  as
  begin
    return '{"id":"chatcmpl-wire-c-2","object":"chat.completion","model":"' || p_model || '"'
        || ',"choices":[{"index":0,"message":{"role":"assistant","content":"' || p_text || '"},"finish_reason":"stop"}]'
        || ',"usage":{"prompt_tokens":100,"completion_tokens":12,"total_tokens":112}}';
  end text_response;


  /*
   * The content of the first role=tool message of a captured request. That is the
   * tool result as it went back to the provider, which for the echo tool below is
   * exactly the argument object the tool was called with.
   */
  function tool_result_on_the_wire(p_index in pls_integer) return clob
  as
    l_messages json_array_t := uc_ai_test_http_mock.request_json(p_index).get_array('messages');
    l_message  json_object_t;
  begin
    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_message := treat(l_messages.get(i) as json_object_t);
      if l_message.get_string('role') = 'tool' then
        return l_message.get_clob('content');
      end if;
    end loop message_loop;

    return null;
  end tool_result_on_the_wire;


  /*
   * A tool with two FLAT string parameters, the shape the built-in MEMORY tool
   * uses. The handler echoes the whole argument object back as its result, so a
   * test can read on the wire exactly what the tool was called with.
   */
  procedure register_echo_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_echo_tool_code;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_echo_tool_code
    , p_description   => 'Get the weather for a city'
    , p_function_call => 'return :parameters;'
    , p_json_schema   => json_object_t('{"type":"object","properties":'
        || '{"city":{"type":"string","description":"City name"}'
        || ',"unit":{"type":"string","description":"celsius or fahrenheit"}}'
        || ',"required":["city","unit"]}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'echo tool registered').to_be_not_null();
  end register_echo_tool;


  /*
   * A tool with one flat string parameter, used for the oversized argument test.
   * Its handler takes no bind on purpose: uc_ai_tools_api binds the arguments
   * through apex_plugin_util.t_bind, whose value is a varchar2(32767), so a
   * handler that reads its arguments hits a second, separate 32 KB ceiling that
   * does not live in uc_ai_openai. This test pins the read at the provider
   * boundary, which is the site it is about.
   */
  procedure register_big_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_big_tool_code;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_big_tool_code
    , p_description   => 'Store a large text payload'
    , p_function_call => 'return ''stored'';'
    , p_json_schema   => json_object_t('{"type":"object","properties":'
        || '{"payload":{"type":"string","description":"The text to store"}}'
        || ',"required":["payload"]}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'big-payload tool registered').to_be_not_null();
  end register_big_tool;


  -- ---- fixtures --------------------------------------------------------------

  procedure register_mock
  as
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
  end register_mock;


  procedure unregister_mock
  as
  begin
    uc_ai_http.set_transport(null);
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_test_http_mock.reset;
  end reset_state;


  -- ---- B4 --------------------------------------------------------------------

  /*
   * xAI has no reasoning_level parameter and drops it like any unknown body key.
   * Measured live on grok-4.3: reasoning_effort "none" bills 0 reasoning tokens
   * and a bogus value is rejected with HTTP 400 "Invalid reasoning effort", while
   * reasoning_level "none" still bills several hundred reasoning tokens and a
   * bogus value is accepted with HTTP 200, exactly like an invented key.
   */
  procedure xai_sends_reasoning_effort
  as
    l_result  json_object_t;
    l_request json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('xai/5-reasoniong-response'));

    -- xAI shares the OpenAI implementation, and its Chat Completions route is
    -- selected by the OpenAI package's global. The xai config block cannot reach
    -- that global and the openai block is not read for another provider, so every
    -- xAI test here states its setup through the globals instead of p_config.
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;
    uc_ai.g_enable_reasoning := true;

    l_result := uc_ai.generate_text(
      p_user_prompt => c_filter_prompt
    , p_provider    => uc_ai.c_provider_xai
    , p_model       => 'grok-4-fast-reasoning'
    );

    l_request := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_request.get_string('reasoning_effort'), 'reasoning_effort').to_equal('low');
    ut.expect(l_request.has('reasoning_level'), 'reasoning_level still sent').to_be_false();

    test_uc_ai_wire.expect_url(1, 'https://api.x.ai/v1/chat/completions');
    test_uc_ai_wire.expect_request(1, 'xai/5-reasoning-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('Assuming the Great Filter exists%');
    test_uc_ai_wire.expect_usage(l_result, 177, 55, 501, 269);
    test_uc_ai_wire.expect_all_consumed(1);
  end xai_sends_reasoning_effort;


  -- ---- B5 --------------------------------------------------------------------

  /*
   * The unwrap of the "parameters" wrapper used to run unconditionally for xAI.
   * On flat arguments treat(NULL as json_object_t) produced a NULL object and the
   * tool ran with no arguments at all - silently, because uc_ai_tools_api
   * substitutes an empty object for a NULL one.
   */
  procedure xai_flat_tool_arguments
  as
    l_result json_object_t;
    l_args   json_object_t;
  begin
    register_echo_tool;

    uc_ai_test_http_mock.enqueue(tool_call_response(
      p_model     => c_xai_model
    , p_call_id   => 'call_wire_c_1'
    , p_tool_code => c_echo_tool_code
    , p_arguments => '{"city":"Berlin","unit":"celsius"}'
    ));
    uc_ai_test_http_mock.enqueue(text_response(c_xai_model, 'It is 21 degrees in Berlin.'));

    -- globals, not p_config: see xai_sends_reasoning_effort
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags := apex_t_varchar2(c_tool_tag);

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_xai
    , p_model       => c_xai_model
    );

    -- the echo tool returns the argument object it was called with
    l_args := json_object_t.parse(tool_result_on_the_wire(2));

    ut.expect(l_args.get_string('city'), 'city the tool received').to_equal('Berlin');
    ut.expect(l_args.get_string('unit'), 'unit the tool received').to_equal('celsius');

    ut.expect(l_result.get_number('tool_calls_count'), 'tool calls').to_equal(1);
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(2);
  end xai_flat_tool_arguments;


  /*
   * The other half of the same guard: when xAI does wrap the arguments, the
   * wrapper still has to come off.
   */
  procedure xai_wrapped_tool_arguments
  as
    l_result json_object_t;
    l_args   json_object_t;
  begin
    register_echo_tool;

    uc_ai_test_http_mock.enqueue(tool_call_response(
      p_model     => c_xai_model
    , p_call_id   => 'call_wire_c_2'
    , p_tool_code => c_echo_tool_code
    , p_arguments => '{"parameters":{"city":"Paris","unit":"fahrenheit"}}'
    ));
    uc_ai_test_http_mock.enqueue(text_response(c_xai_model, 'It is 70 degrees in Paris.'));

    -- globals, not p_config: see xai_sends_reasoning_effort
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags := apex_t_varchar2(c_tool_tag);

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_xai
    , p_model       => c_xai_model
    );

    l_args := json_object_t.parse(tool_result_on_the_wire(2));

    ut.expect(l_args.get_string('city'), 'city the tool received').to_equal('Paris');
    ut.expect(l_args.get_string('unit'), 'unit the tool received').to_equal('fahrenheit');
    ut.expect(l_args.has('parameters'), 'wrapper still around the arguments').to_be_false();

    ut.expect(l_result.get_number('tool_calls_count'), 'tool calls').to_equal(1);
    test_uc_ai_wire.expect_all_consumed(2);
  end xai_wrapped_tool_arguments;


  -- ---- B13 -------------------------------------------------------------------

  /*
   * get_string returns a varchar2 and raises ORA-06502 above 32767 bytes, so a
   * model that emitted a large argument payload killed the whole run.
   */
  procedure chat_large_tool_arguments
  as
    l_result   json_object_t;
    l_payload  clob;
    l_args     json_object_t;
    l_assistant json_object_t;
    l_call     json_object_t;
  begin
    register_big_tool;

    <<payload_chunks>>
    for i in 1 .. c_big_payload_size / 1000 loop
      l_payload := l_payload || rpad('A', 1000, 'A');
    end loop payload_chunks;

    ut.expect(length(l_payload), 'payload built').to_equal(c_big_payload_size);

    uc_ai_test_http_mock.enqueue(tool_call_response(
      p_model     => c_chat_model
    , p_call_id   => 'call_wire_c_3'
    , p_tool_code => c_big_tool_code
    , p_arguments => '{"payload":"' || l_payload || '"}'
    ));
    uc_ai_test_http_mock.enqueue(text_response(c_chat_model, 'Stored.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Store this text for me.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_chat_model
    , p_config      => test_uc_ai_wire.config('{"g_enable_tools":true,"g_tool_tags":["' || c_tool_tag || '"]'
                       || ',"openai":{"g_use_responses_api":false}}')
    );

    -- The run reached the second request at all, which get_string could not do.
    -- The normalized history carries the arguments the provider sent, whole:
    -- that value is exactly what the read at the provider boundary produced.
    l_assistant := treat(test_uc_ai_wire.messages_of(l_result).get(1) as json_object_t);
    l_call := treat(treat(l_assistant.get('content') as json_array_t).get(0) as json_object_t);
    ut.expect(l_call.get_string('type'), 'first content part').to_equal('tool_call');

    l_args := json_object_t.parse(l_call.get_clob('args'));
    ut.expect(length(l_args.get_clob('payload')), 'payload length in result.messages').to_equal(c_big_payload_size);
    ut.expect(l_args.get_clob('payload'), 'payload content in result.messages').to_equal(l_payload);

    ut.expect(l_result.get_number('tool_calls_count'), 'tool calls').to_equal(1);
    test_uc_ai_wire.expect_all_consumed(2);
  end chat_large_tool_arguments;


  -- ---- B20 -------------------------------------------------------------------

  /*
   * The normalized assistant turn used to be built from the tool calls alone, so
   * any text the model sent alongside them was gone from result.messages - the
   * history uc_ai_agent_exec_api reloads on the next run.
   */
  procedure chat_text_next_to_tool_calls
  as
    c_preamble constant varchar2(100 char) := 'Let me look up the weather for you.';
    l_result    json_object_t;
    l_messages  json_array_t;
    l_assistant json_object_t;
    l_content   json_array_t;
    l_part      json_object_t;
  begin
    register_echo_tool;

    uc_ai_test_http_mock.enqueue(tool_call_response(
      p_model     => c_chat_model
    , p_call_id   => 'call_wire_c_4'
    , p_tool_code => c_echo_tool_code
    , p_arguments => '{"city":"Berlin","unit":"celsius"}'
    , p_content   => c_preamble
    ));
    uc_ai_test_http_mock.enqueue(text_response(c_chat_model, 'It is 21 degrees in Berlin.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_chat_model
    , p_config      => test_uc_ai_wire.config('{"g_enable_tools":true,"g_tool_tags":["' || c_tool_tag || '"]'
                       || ',"openai":{"g_use_responses_api":false}}')
    );

    -- user, assistant (text + tool call), tool, assistant (answer)
    l_messages := test_uc_ai_wire.messages_of(l_result);
    ut.expect(l_messages.get_size, 'user, assistant, tool, assistant').to_equal(4);

    l_assistant := treat(l_messages.get(1) as json_object_t);
    ut.expect(l_assistant.get_string('role'), 'role of message 2').to_equal('assistant');

    l_content := treat(l_assistant.get('content') as json_array_t);
    ut.expect(l_content.get_size, 'text part plus tool call part').to_equal(2);

    l_part := treat(l_content.get(0) as json_object_t);
    ut.expect(l_part.get_string('type'), 'first content part').to_equal('text');
    ut.expect(l_part.get_clob('text'), 'the preamble the model sent').to_equal(to_clob(c_preamble));

    l_part := treat(l_content.get(1) as json_object_t);
    ut.expect(l_part.get_string('type'), 'second content part').to_equal('tool_call');
    ut.expect(l_part.get_string('toolCallId'), 'tool call id').to_equal('call_wire_c_4');

    test_uc_ai_wire.expect_all_consumed(2);
  end chat_text_next_to_tool_calls;


  -- ---- response robustness ---------------------------------------------------

  /*
   * has() is also true for a JSON null, so "usage": null used to reach get_object
   * and raise ORA-30625. Same for completion_tokens_details inside a usage object.
   */
  procedure null_usage_is_tolerated
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue('{"id":"chatcmpl-null-1","object":"chat.completion","model":"' || c_chat_model || '"'
      || ',"choices":[{"index":0,"message":{"role":"assistant","content":"Paris."},"finish_reason":"stop"}]'
      || ',"usage":null}');

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_chat_model
    , p_config      => test_uc_ai_wire.config('{"openai":{"g_use_responses_api":false}}')
    );

    ut.expect(l_result.get_clob('final_message'), 'answer with a null usage').to_equal(to_clob('Paris.'));
    test_uc_ai_wire.expect_usage(l_result, 0, 0, 0, 0);

    -- and a null completion_tokens_details inside a usage object
    uc_ai_test_http_mock.enqueue('{"id":"chatcmpl-null-2","object":"chat.completion","model":"' || c_chat_model || '"'
      || ',"choices":[{"index":0,"message":{"role":"assistant","content":"Berlin."},"finish_reason":"stop"}]'
      || ',"usage":{"prompt_tokens":7,"completion_tokens":2,"total_tokens":9,"completion_tokens_details":null}}');

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of Germany?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => c_chat_model
    , p_config      => test_uc_ai_wire.config('{"openai":{"g_use_responses_api":false}}')
    );

    ut.expect(l_result.get_clob('final_message'), 'answer with a null details object').to_equal(to_clob('Berlin.'));
    test_uc_ai_wire.expect_usage(l_result, 7, 2, 9, 0);

    test_uc_ai_wire.expect_all_consumed(2);
  end null_usage_is_tolerated;


  /*
   * A 200 body without a choices array left l_choices NULL and the loop header
   * raised ORA-30625. It is a provider-response error and has to read like one.
   */
  procedure missing_choices_raises
  as
    l_result json_object_t;
    l_error  varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('{"id":"chatcmpl-no-choices","object":"chat.completion","model":"' || c_chat_model || '"'
      || ',"usage":{"prompt_tokens":7,"completion_tokens":0,"total_tokens":7}}');

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => 'What is the capital of France?'
      , p_provider    => uc_ai.c_provider_openai
      , p_model       => c_chat_model
      , p_config      => test_uc_ai_wire.config('{"openai":{"g_use_responses_api":false}}')
      );
      ut.fail('expected -20302, got ' || l_result.to_clob);
    exception
      when uc_ai.e_error_response then
        l_error := sqlerrm;
    end;

    ut.expect(l_error, 'error message').to_be_like('%choices%');
    test_uc_ai_wire.expect_all_consumed(1);
  end missing_choices_raises;

end test_uc_ai_openai_wire;
/
