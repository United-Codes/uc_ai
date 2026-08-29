create or replace package body test_uc_ai_ollama_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its code; a backtrace adds nothing

  -- The web credential every call is named with comes from test_uc_ai_wire.config,
  -- so no provider ever asks uc_ai_get_key for a key.
  c_model      constant uc_ai.model_type := 'qwen3:4b';
  c_chat_url   constant varchar2(100 char) := 'http://localhost:11434/api/chat';

  -- Own tool and own tag, so the tools of the other wire suites never reach a
  -- request built here.
  c_tool_code  constant uc_ai_tools.code%type := 'WIRE_F_GET_USERS';
  c_tool_tag   constant varchar2(30 char) := 'wire_f_test';

  c_users_prompt constant varchar2(200 char) := 'What is the email address of Jim?';
  c_jim_answer   constant varchar2(100 char) := 'Jim''s email address is jim.halpert@dundermifflin.com.';
  c_tool_result  constant varchar2(100 char) := '[{"name":"Jim","email":"jim.halpert@dundermifflin.com"}]';

  -- base64 of the five bytes 'hello', the whole content of every fake file below
  c_fake_base64 constant varchar2(10 char) := 'aGVsbG8=';

  e_unhandled_format exception;
  pragma exception_init(e_unhandled_format, -20303);
  e_format_processing exception;
  pragma exception_init(e_format_processing, -20304);


  -- ---- helpers (the shared ones live in test_uc_ai_wire and test_uc_ai_wire_2) ------

  /*
   * The native route plus the web credential. The default of
   * uc_ai_ollama.g_use_responses_api is true, which would delegate the whole call
   * to uc_ai_responses_api and test nothing this suite is about.
   */
  function native_config(p_json in varchar2 default '{}') return json_object_t
  as
    l_config json_object_t := test_uc_ai_wire.config(p_json);
    l_ollama json_object_t;
  begin
    if l_config.has('ollama') then
      l_ollama := l_config.get_object('ollama');
    else
      l_ollama := json_object_t();
    end if;

    l_ollama.put('g_use_responses_api', false);
    l_config.put('ollama', l_ollama);

    return l_config;
  end native_config;


  function request_json(p_index in pls_integer) return json_object_t
  as
  begin
    return test_uc_ai_wire_2.request_json(p_index);
  end request_json;


  function item(
    p_array in json_array_t
  , p_index in pls_integer
  ) return json_object_t
  as
  begin
    return test_uc_ai_wire_2.item(p_array, p_index);
  end item;


  procedure expect_all_consumed(p_requests in pls_integer)
  as
  begin
    test_uc_ai_wire.expect_all_consumed(p_requests);
  end expect_all_consumed;


  /*
   * The messages array of the p_index-th recorded request.
   */
  function sent_messages(p_index in pls_integer) return json_array_t
  as
  begin
    return request_json(p_index).get_array('messages');
  end sent_messages;


  /*
   * A user message built from optional text plus one file, the shape
   * uc_ai_message_api hands to every provider. p_text null gives the file-only
   * message the normalized format allows.
   */
  function file_message(
    p_media_type in varchar2
  , p_text       in clob default null
  ) return json_array_t
  as
    l_messages json_array_t := json_array_t();
    l_files    uc_ai_message_api.t_files := uc_ai_message_api.t_files();
  begin
    l_files.extend(1);
    l_files(1).media_type := p_media_type;
    l_files(1).data_blob  := sys.utl_raw.cast_to_raw('hello');
    l_files(1).filename   := 'file.bin';

    l_messages.append(uc_ai_message_api.create_user_message(p_text => p_text, p_files => l_files));

    return l_messages;
  end file_message;


  /*
   * A native tool-call turn. p_arguments null omits the arguments key entirely,
   * which is what a server that has nothing to pass sends.
   */
  function tool_call_turn(
    p_content   in varchar2 default null
  , p_arguments in varchar2 default '{}'
  ) return clob
  as
    l_message   json_object_t := json_object_t();
    l_call      json_object_t := json_object_t();
    l_function  json_object_t := json_object_t();
    l_calls     json_array_t  := json_array_t();
  begin
    l_function.put('name', c_tool_code);
    if p_arguments is not null then
      l_function.put('arguments', json_object_t(p_arguments));
    end if;

    l_call.put('function', l_function);
    l_calls.append(l_call);

    l_message.put('role', 'assistant');
    l_message.put('content', coalesce(p_content, empty_clob()));
    l_message.put('tool_calls', l_calls);

    return test_uc_ai_wire_2.ollama_chat(l_message, 30, 12);
  end tool_call_turn;


  /*
   * A tool with no parameters that answers with a fixed result. Tagged so only it
   * reaches the request. The row is rolled back with the test.
   */
  procedure register_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_tool_code;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_tool_code
    , p_description   => 'Get information on all the users in the system'
    , p_function_call => 'return test_uc_ai_ollama_wire.tool_answer;'
    , p_json_schema   => json_object_t('{"type":"object","properties":{}}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'tool registered').to_be_not_null();
  end register_tool;


  function tool_answer return clob
  as
  begin
    return to_clob(c_tool_result);
  end tool_answer;


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
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_test_http_mock.reset;
  end reset_state;


  -- ---- user message conversion -------------------------------------------------

  /*
   * A user message that carries a file and no text is legal in the normalized
   * format. It used to be dropped whole, because the append was gated on
   * length(NULL) > 0, and the image never reached the model.
   */
  procedure file_only_user_message
  as
    l_result  json_object_t;
    l_message json_object_t;
  begin
    test_uc_ai_wire_2.enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t('{"role":"assistant","content":"A greeting."}')));

    l_result := uc_ai.generate_text(
      p_messages => file_message('image/png')
    , p_provider => uc_ai.c_provider_ollama
    , p_model    => c_model
    , p_config   => native_config
    );

    ut.expect(sent_messages(1).get_size, 'the user message reaches the request').to_equal(1);

    l_message := item(sent_messages(1), 0);
    ut.expect(l_message.get_string('role')).to_equal('user');
    -- to_clob('') is NULL in Oracle, so the JSON scalar itself is compared
    ut.expect(l_message.get('content').to_string(), 'an empty string, not a JSON null').to_equal('""');
    ut.expect(l_message.get_array('images')).to_equal(json_array_t('["' || c_fake_base64 || '"]'));

    test_uc_ai_wire.expect_url(1, c_chat_url);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('A greeting.'));
    expect_all_consumed(1);
  end file_only_user_message;


  /*
   * /api/chat has no envelope for a document. A PDF appended to `images` would be
   * read as an image, so the conversion has to refuse it before the request.
   */
  procedure pdf_user_file_raises
  as
    l_result json_object_t;
    l_code   pls_integer;
  begin
    begin
      l_result := uc_ai.generate_text(
        p_messages => file_message('application/pdf', 'Describe the file.')
      , p_provider => uc_ai.c_provider_ollama
      , p_model    => c_model
      , p_config   => native_config
      );
      ut.fail('expected -20303, got a result: ' || l_result.to_clob);
    exception
      when e_unhandled_format then
        l_code := sqlcode;
    end;

    ut.expect(l_code, 'a PDF is refused').to_equal(uc_ai_error.c_err_unhandled_format);
    -- nothing was queued and nothing was sent: the conversion raised first
    expect_all_consumed(0);
  end pdf_user_file_raises;


  /*
   * Regression guard for the two fixes above: the ordinary case still works.
   */
  procedure text_and_image_user_message
  as
    l_result  json_object_t;
    l_message json_object_t;
  begin
    test_uc_ai_wire_2.enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t('{"role":"assistant","content":"A greeting."}')));

    l_result := uc_ai.generate_text(
      p_messages => file_message('image/png', 'Describe the file.')
    , p_provider => uc_ai.c_provider_ollama
    , p_model    => c_model
    , p_config   => native_config
    );

    l_message := item(sent_messages(1), 0);
    ut.expect(l_message.get_clob('content')).to_equal(to_clob('Describe the file.'));
    ut.expect(l_message.get_array('images')).to_equal(json_array_t('["' || c_fake_base64 || '"]'));

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('A greeting.'));
    expect_all_consumed(1);
  end text_and_image_user_message;


  -- ---- tool calling ------------------------------------------------------------

  /*
   * The shape a real Ollama tool-call turn has: role assistant, an empty content
   * string, no thinking, and the calls. The empty-content guard used to raise
   * -20304 on it, so local tool calling never ran on this route.
   */
  procedure empty_content_tool_call
  as
    l_result   json_object_t;
    l_messages json_array_t;
  begin
    register_tool;
    test_uc_ai_wire_2.enqueue(tool_call_turn);
    test_uc_ai_wire_2.enqueue(test_uc_ai_wire_2.ollama_chat(
      json_object_t('{"role":"assistant","content":"' || c_jim_answer || '"}'), 200, 15));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => c_model
    , p_config      => native_config('{"g_enable_tools":true,"g_tool_tags":["' || c_tool_tag || '"]}')
    );

    -- the tool was offered
    ut.expect(item(request_json(1).get_array('tools'), 0).get_object('function').get_string('name'))
      .to_equal(c_tool_code);

    -- Ollama has no call ids: the result names the tool instead
    l_messages := sent_messages(2);
    ut.expect(l_messages.get_size, 'user, assistant, tool').to_equal(3);
    ut.expect(item(l_messages, 1).get_string('role')).to_equal('assistant');
    ut.expect(item(l_messages, 1).get('content').to_string(), 'replayed as "" not a JSON null').to_equal('""');
    ut.expect(item(l_messages, 1).get_array('tool_calls').get_size).to_equal(1);
    ut.expect(item(l_messages, 2).get_string('role')).to_equal('tool');
    ut.expect(item(l_messages, 2).get_string('tool_name')).to_equal(c_tool_code);
    ut.expect(item(l_messages, 2).get_clob('content')).to_equal(to_clob(c_tool_result));

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob(c_jim_answer));
    uc_ai_test_message_utils.valididate_return_object(l_result, 'ollama native tool round trip');
    expect_all_consumed(2);
  end empty_content_tool_call;


  /*
   * A call with no arguments key at all. get_object returns NULL for a missing or
   * JSON null value, which used to reach execute_agent_tool as a NULL object.
   */
  procedure tool_call_without_arguments
  as
    l_result json_object_t;
  begin
    register_tool;
    test_uc_ai_wire_2.enqueue(tool_call_turn(p_arguments => null));
    test_uc_ai_wire_2.enqueue(test_uc_ai_wire_2.ollama_chat(
      json_object_t('{"role":"assistant","content":"' || c_jim_answer || '"}'), 200, 15));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => c_model
    , p_config      => native_config('{"g_enable_tools":true,"g_tool_tags":["' || c_tool_tag || '"]}')
    );

    ut.expect(item(sent_messages(2), 2).get_clob('content')).to_equal(to_clob(c_tool_result));
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    expect_all_consumed(2);
  end tool_call_without_arguments;


  -- ---- response parsing --------------------------------------------------------

  /*
   * Regression guard: a turn with text and no tool calls is unaffected by the
   * relaxed empty-content guard.
   */
  procedure plain_text_turn
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire_2.enqueue(test_uc_ai_wire_2.ollama_chat(
      json_object_t('{"role":"assistant","content":"' || c_jim_answer || '"}'), 200, 15));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => c_model
    , p_config      => native_config
    );

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob(c_jim_answer));
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(0);
    test_uc_ai_wire.expect_usage(l_result, 200, 15, 215);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'ollama native plain text');
    expect_all_consumed(1);
  end plain_text_turn;


  /*
   * has() is true for a JSON null too. OpenAI-compatible servers behind the same
   * route send "tool_calls": null on an ordinary turn; get_array then returns
   * NULL and get_size on it raised ORA-30625.
   */
  procedure json_null_tool_calls
  as
    l_result  json_object_t;
    l_message json_object_t := json_object_t();
  begin
    l_message.put('role', 'assistant');
    l_message.put('content', c_jim_answer);
    l_message.put_null('tool_calls');

    test_uc_ai_wire_2.enqueue(test_uc_ai_wire_2.ollama_chat(l_message, 200, 15));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => c_model
    , p_config      => native_config
    );

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob(c_jim_answer));
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    expect_all_consumed(1);
  end json_null_tool_calls;


  /*
   * A body with no message object at all. The caller gets a UC AI error naming
   * the provider instead of ORA-30625 from a method call on a NULL object.
   */
  procedure response_without_message
  as
    l_result json_object_t;
    l_code   pls_integer;
  begin
    test_uc_ai_wire_2.enqueue('{"model":"' || c_model || '","done_reason":"stop","done":true,"prompt_eval_count":5,"eval_count":0}');

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_users_prompt
      , p_provider    => uc_ai.c_provider_ollama
      , p_model       => c_model
      , p_config      => native_config
      );
      ut.fail('expected -20304, got a result: ' || l_result.to_clob);
    exception
      when e_format_processing then
        l_code := sqlcode;
    end;

    ut.expect(l_code, 'a body without a message raises a UC AI error').to_equal(uc_ai_error.c_err_format_processing);
    expect_all_consumed(1);
  end response_without_message;

end test_uc_ai_ollama_wire;
/
