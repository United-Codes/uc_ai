create or replace package body test_uc_ai_wire_3 as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-7230): the event sink records what it was given in package state, which the test reads back

  c_credential constant varchar2(30 char) := 'WIRE_TEST_CREDENTIAL';

  -- The prompts the samples were recorded with.
  c_recipe_prompt constant varchar2(200 char) := 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?';
  c_users_prompt  constant varchar2(200 char) := 'What is the email address of Jim?';
  c_users_system  constant varchar2(200 char) := 'You are an assistant to a time tracking system. Your tools give you access to user information.';
  c_oci_llama     constant varchar2(64 char)  := 'meta.llama-3.3-70b-instruct';
  c_jim_answer    constant varchar2(100 char) := 'Jim''s email address is jim.halpert@dundermifflin.com.';
  -- base64 of the five bytes 'hello', the whole content of the fake files
  c_fake_base64   constant varchar2(10 char)  := 'aGVsbG8=';

  -- the event sink
  type t_event is record (
    request_id varchar2(32 char)
  , event_type varchar2(64 char)
  , payload    clob
  );
  type t_events is table of t_event index by pls_integer;
  -- @dblinter ignore(g-9105): package-global collection; the g_ prefix is intended (not a local var)
  g_events t_events;


  -- ---- helpers (the shared ones live in test_uc_ai_wire and test_uc_ai_wire_2) ------

  function config(p_json in varchar2 default '{}') return json_object_t
  as
  begin
    return test_uc_ai_wire.config(p_json);
  end config;


  procedure enqueue(p_body in clob)
  as
  begin
    test_uc_ai_wire_2.enqueue(p_body);
  end enqueue;


  procedure enqueue_sample(p_sample in varchar2)
  as
  begin
    test_uc_ai_wire.enqueue_sample(p_sample);
  end enqueue_sample;


  procedure expect_request(
    p_index  in pls_integer
  , p_sample in varchar2
  )
  as
  begin
    test_uc_ai_wire.expect_request(p_index, p_sample);
  end expect_request;


  procedure expect_url(
    p_index in pls_integer
  , p_url   in varchar2
  )
  as
  begin
    test_uc_ai_wire.expect_url(p_index, p_url);
  end expect_url;


  procedure expect_all_consumed(p_requests in pls_integer)
  as
  begin
    test_uc_ai_wire.expect_all_consumed(p_requests);
  end expect_all_consumed;


  procedure expect_usage(
    p_result            in json_object_t
  , p_prompt_tokens     in number
  , p_completion_tokens in number
  , p_total_tokens      in number   default null
  , p_reasoning_tokens  in number   default null
  )
  as
  begin
    test_uc_ai_wire.expect_usage(p_result, p_prompt_tokens, p_completion_tokens, p_total_tokens, p_reasoning_tokens);
  end expect_usage;


  function messages_of(p_result in json_object_t) return json_array_t
  as
  begin
    return test_uc_ai_wire.messages_of(p_result);
  end messages_of;


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


  function content_of(p_message in json_object_t) return json_array_t
  as
  begin
    return test_uc_ai_wire_2.content_of(p_message);
  end content_of;


  function last_message_of(p_result in json_object_t) return json_object_t
  as
  begin
    return test_uc_ai_wire_2.last_message_of(p_result);
  end last_message_of;


  procedure register_users_tool
  as
  begin
    test_uc_ai_wire.register_users_tool;
  end register_users_tool;


  -- ---- event sink --------------------------------------------------------------

  procedure on_event(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  )
  as
    l_event t_event;
  begin
    l_event.request_id := p_request_id;
    l_event.event_type := p_event_type;
    l_event.payload    := p_event_data;
    g_events(g_events.count + 1) := l_event;
  end on_event;


  function count_events(p_event_type in varchar2) return pls_integer
  as
    l_count pls_integer := 0;
  begin
    <<events_loop>>
    for i in 1 .. g_events.count loop
      if g_events(i).event_type = p_event_type then
        l_count := l_count + 1;
      end if;
    end loop events_loop;

    return l_count;
  end count_events;


  function first_event(p_event_type in varchar2) return t_event
  as
  begin
    <<events_loop>>
    for i in 1 .. g_events.count loop
      if g_events(i).event_type = p_event_type then
        return g_events(i);
      end if;
    end loop events_loop;

    return null;
  end first_event;


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
    -- the callback survives reset_globals on purpose; do not leak it to other suites
    uc_ai.clear_event_callback;
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_test_http_mock.reset;
    g_events.delete;
  end reset_state;


  -- ---- passthrough -------------------------------------------------------------

  procedure extra_body_protects_reserved_keys
  as
    l_result  json_object_t;
    l_request json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.chat_completion('ok'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"g_extra_body":{"top_p":0.9,"service_tier":"flex",'
                       || '"messages":[{"role":"user","content":"pwned"}],"model":"evil-model","tools":[{"type":"function"}]},'
                       || '"openai":{"g_use_responses_api":false}}')
    );

    l_request := request_json(1);
    -- unwrapped parameters pass through
    ut.expect(l_request.get_number('top_p')).to_equal(0.9);
    ut.expect(l_request.get_string('service_tier')).to_equal('flex');
    -- the keys that define the conversation stay the framework's
    ut.expect(l_request.get_string('model')).to_equal('gpt-4o-mini');
    ut.expect(l_request.get_array('messages').get_size).to_equal(1);
    ut.expect(item(content_of(item(l_request.get_array('messages'), 0)), 0).get_clob('text')).to_equal(to_clob(c_users_prompt));
    ut.expect(l_request.has('tools'), 'no tools smuggled in').to_be_false();

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('ok'));
    expect_all_consumed(1);
  end extra_body_protects_reserved_keys;


  procedure anthropic_provider_tools
  as
    l_result json_object_t;
    l_tools  json_array_t;
  begin
    register_users_tool;
    -- server-side blocks come back next to the text; they are not local tool calls
    enqueue(test_uc_ai_wire_2.anthropic_message(json_array_t(
      '[{"type":"server_tool_use","id":"srvtoolu_wire_1","name":"web_search","input":{"query":"uc ai"}},'
      || '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_wire_1","content":[]},'
      || '{"type":"text","text":"UC AI is a PL/SQL SDK."}]'), 'end_turn', 100, 30));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is UC AI?'
    , p_provider    => uc_ai.c_provider_anthropic
    , p_model       => 'claude-haiku-4-5'
    , p_config      => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],'
                       || '"g_provider_tools":[{"type":"web_search_20250305","name":"web_search","max_uses":3}]}')
    );

    l_tools := request_json(1).get_array('tools');
    ut.expect(l_tools.get_size, 'local tool plus provider tool').to_equal(2);
    ut.expect(item(l_tools, 0).get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(item(l_tools, 1), 'provider tool verbatim').to_equal(json_object_t('{"type":"web_search_20250305","name":"web_search","max_uses":3}'));

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('UC AI is a PL/SQL SDK.'));
    ut.expect(l_result.get_number('tool_calls_count'), 'server-side blocks are not local calls').to_equal(0);
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(content_of(last_message_of(l_result)).get_size, 'only the text is normalized').to_equal(1);
    expect_all_consumed(1);
  end anthropic_provider_tools;


  procedure responses_provider_tools
  as
    l_result  json_object_t;
    l_request json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.responses_body(test_uc_ai_wire_2.responses_text('It is sunny.')));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Weather in Paris?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"g_provider_tools":[{"type":"web_search_preview"}]}')
    );

    expect_url(1, 'https://api.openai.com/v1/responses');
    l_request := request_json(1);
    -- provider tools are sent even though local tools are off
    ut.expect(l_request.get_array('tools')).to_equal(json_array_t('[{"type":"web_search_preview"}]'));
    ut.expect(l_request.get_boolean('store'), 'config default').to_be_false();
    ut.expect(l_request.has('include')).to_be_false();

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('It is sunny.'));
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(0);
    expect_all_consumed(1);
  end responses_provider_tools;


  procedure base_url_override
  as
    l_result  json_object_t;
    l_vectors json_array_t;
    c_base    constant varchar2(50 char) := 'https://proxy.example.com/llm/';
  begin
    enqueue_sample('anthropic/1-simple-response');
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_anthropic
    , p_model       => 'claude-3-5-haiku-latest'
    , p_config      => config('{"g_base_url":"' || c_base || '"}')
    );
    expect_url(1, 'https://proxy.example.com/llm/messages');

    enqueue(test_uc_ai_wire_2.chat_completion('ok'));
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"g_base_url":"' || c_base || '","openai":{"g_use_responses_api":false}}')
    );
    expect_url(2, 'https://proxy.example.com/llm/chat/completions');

    enqueue_sample('openai/responses/1-simple-response');
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"g_base_url":"' || c_base || '"}')
    );
    expect_url(3, 'https://proxy.example.com/llm/responses');

    enqueue_sample('google/1-simple-response');
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_google
    , p_model       => 'gemini-2.5-flash'
    , p_config      => config('{"g_base_url":"' || c_base || '"}')
    );
    expect_url(4, 'https://proxy.example.com/llm/gemini-2.5-flash:generateContent');

    enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t('{"role":"assistant","content":"ok"}')));
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => 'qwen3:4b'
    , p_config      => config('{"g_base_url":"' || c_base || '","ollama":{"g_use_responses_api":false}}')
    );
    expect_url(5, 'https://proxy.example.com/llm/chat');

    enqueue(test_uc_ai_wire_2.oci_generic_text('ok'));
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_oci_llama
    , p_config      => test_uc_ai_wire_2.oci_config('{"g_base_url":"' || c_base || '"}')
    );
    expect_url(6, 'https://proxy.example.com/llm/20231130/actions/chat');

    enqueue_sample('openai/chat/6-embedding-response');
    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["a"]')
    , p_provider => uc_ai.c_provider_openai
    , p_model    => 'text-embedding-3-small'
    , p_config   => config('{"g_base_url":"' || c_base || '"}')
    );
    expect_url(7, 'https://proxy.example.com/llm/embeddings');

    ut.expect(l_vectors.get_size).to_equal(1);
    expect_all_consumed(7);
  end base_url_override;


  -- ---- file inputs -------------------------------------------------------------

  procedure openai_file_inputs
  as
    l_result  json_object_t;
    l_content json_array_t;
    l_part    json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.chat_completion('Two files.'));
    l_result := uc_ai.generate_text(
      p_messages => test_uc_ai_wire_2.files_message
    , p_provider => uc_ai.c_provider_openai
    , p_model    => 'gpt-4o-mini'
    , p_config   => config('{"openai":{"g_use_responses_api":false}}')
    );

    l_content := content_of(item(request_json(1).get_array('messages'), 0));
    ut.expect(l_content.get_size, 'text, image, pdf').to_equal(3);
    ut.expect(item(l_content, 0).get_clob('text')).to_equal(to_clob('Describe the files.'));

    l_part := item(l_content, 1);
    ut.expect(l_part.get_string('type')).to_equal('image_url');
    ut.expect(l_part.get_object('image_url').get_string('url')).to_equal('data:image/png;base64,' || c_fake_base64);

    l_part := item(l_content, 2);
    ut.expect(l_part.get_string('type')).to_equal('file');
    ut.expect(l_part.get_object('file').get_string('filename')).to_equal('doc.pdf');
    ut.expect(l_part.get_object('file').get_string('file_data')).to_equal('data:application/pdf;base64,' || c_fake_base64);

    enqueue(test_uc_ai_wire_2.responses_body(test_uc_ai_wire_2.responses_text('Two files.')));
    l_result := uc_ai.generate_text(
      p_messages => test_uc_ai_wire_2.files_message
    , p_provider => uc_ai.c_provider_openai
    , p_model    => 'gpt-4o-mini'
    , p_config   => config
    );

    l_content := content_of(item(request_json(2).get_array('input'), 0));
    ut.expect(l_content.get_size).to_equal(3);
    ut.expect(item(l_content, 0).get_string('type')).to_equal('input_text');

    l_part := item(l_content, 1);
    ut.expect(l_part.get_string('type')).to_equal('input_image');
    ut.expect(l_part.get_string('image_url')).to_equal('data:image/png;base64,' || c_fake_base64);
    ut.expect(l_part.get_string('detail')).to_equal('auto');

    l_part := item(l_content, 2);
    ut.expect(l_part.get_string('type')).to_equal('input_file');
    ut.expect(l_part.get_string('filename')).to_equal('doc.pdf');
    ut.expect(l_part.get_string('file_data')).to_equal('data:application/pdf;base64,' || c_fake_base64);

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Two files.'));
    expect_all_consumed(2);
  end openai_file_inputs;


  procedure anthropic_google_file_inputs
  as
    l_result  json_object_t;
    l_content json_array_t;
    l_parts   json_array_t;
  begin
    enqueue_sample('anthropic/1-simple-response');
    l_result := uc_ai.generate_text(
      p_messages => test_uc_ai_wire_2.files_message
    , p_provider => uc_ai.c_provider_anthropic
    , p_model    => 'claude-3-5-haiku-latest'
    , p_config   => config
    );

    l_content := content_of(item(request_json(1).get_array('messages'), 0));
    ut.expect(l_content.get_size, 'text, image, document').to_equal(3);
    ut.expect(item(l_content, 1)).to_equal(json_object_t(
      '{"type":"image","source":{"type":"base64","media_type":"image/png","data":"' || c_fake_base64 || '"}}'));
    ut.expect(item(l_content, 2)).to_equal(json_object_t(
      '{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"' || c_fake_base64 || '"}}'));

    enqueue_sample('google/1-simple-response');
    l_result := uc_ai.generate_text(
      p_messages => test_uc_ai_wire_2.files_message
    , p_provider => uc_ai.c_provider_google
    , p_model    => 'gemini-2.5-flash'
    , p_config   => config
    );

    l_parts := item(request_json(2).get_array('contents'), 0).get_array('parts');
    ut.expect(l_parts.get_size).to_equal(3);
    ut.expect(item(l_parts, 1)).to_equal(json_object_t('{"inline_data":{"mime_type":"image/png","data":"' || c_fake_base64 || '"}}'));
    ut.expect(item(l_parts, 2)).to_equal(json_object_t('{"inline_data":{"mime_type":"application/pdf","data":"' || c_fake_base64 || '"}}'));

    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    expect_all_consumed(2);
  end anthropic_google_file_inputs;


  /*
   * The PNG half of files_message: one image file, one text part.
   */
  function png_only_message return json_array_t
  as
    l_messages json_array_t := json_array_t();
    l_files    uc_ai_message_api.t_files := uc_ai_message_api.t_files();
  begin
    l_files.extend(1);
    l_files(1).media_type := 'image/png';
    l_files(1).data_blob  := sys.utl_raw.cast_to_raw('hello');
    l_files(1).filename   := 'pic.png';

    l_messages.append(uc_ai_message_api.create_user_message(
      p_text  => 'Describe the files.'
    , p_files => l_files
    ));

    return l_messages;
  end png_only_message;


  procedure oci_ollama_file_inputs
  as
    l_result  json_object_t;
    l_content json_array_t;
    l_message json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.oci_generic_text('Two files.'));
    l_result := uc_ai.generate_text(
      p_messages => test_uc_ai_wire_2.files_message
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_oci_llama
    , p_config   => test_uc_ai_wire_2.oci_config
    );

    l_content := content_of(item(request_json(1).get_object('chatRequest').get_array('messages'), 0));
    ut.expect(l_content.get_size, 'TEXT, IMAGE, DOCUMENT').to_equal(3);
    ut.expect(item(l_content, 1)).to_equal(json_object_t(
      '{"type":"IMAGE","imageUrl":{"url":"data:image/png;base64,' || c_fake_base64 || '","detail":"AUTO"}}'));
    ut.expect(item(l_content, 2)).to_equal(json_object_t(
      '{"type":"DOCUMENT","documentUrl":{"url":"data:application/pdf;base64,' || c_fake_base64 || '","detail":"AUTO"}}'));

    -- Ollama takes bare base64 in a parallel images array, but /api/chat has no
    -- envelope for a document, so only an image may go in it. A PNG passes; the
    -- PDF of files_message is refused rather than sent as if it were an image.
    enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t('{"role":"assistant","content":"One picture."}')));
    l_result := uc_ai.generate_text(
      p_messages => png_only_message
    , p_provider => uc_ai.c_provider_ollama
    , p_model    => 'qwen3.5:2b'
    , p_config   => config('{"ollama":{"g_use_responses_api":false}}')
    );

    l_message := item(request_json(2).get_array('messages'), 0);
    ut.expect(l_message.get_clob('content')).to_equal(to_clob('Describe the files.'));
    ut.expect(l_message.get_array('images')).to_equal(json_array_t('["' || c_fake_base64 || '"]'));
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('One picture.'));

    expect_all_consumed(2);
  end oci_ollama_file_inputs;


  procedure ollama_rejects_a_document
  as
    l_result json_object_t;
    l_raised boolean := false;
  begin
    -- No request must be built at all: a media type Ollama cannot carry is an
    -- error, not something to smuggle into the images array.
    begin
      l_result := uc_ai.generate_text(
        p_messages => test_uc_ai_wire_2.files_message
      , p_provider => uc_ai.c_provider_ollama
      , p_model    => 'qwen3.5:2b'
      , p_config   => config('{"ollama":{"g_use_responses_api":false}}')
      );
    exception
      when uc_ai.e_unhandled_format then
        l_raised := true;
    end;

    ut.expect(l_raised, 'a PDF raises -20303 on the native route').to_be_true();
    expect_all_consumed(0);
  end ollama_rejects_a_document;


  -- ---- finish reasons ----------------------------------------------------------

  procedure anthropic_max_tokens_is_length
  as
    l_result json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.anthropic_message(json_array_t('[{"type":"text","text":"The capital of France is"}]'), 'max_tokens', 20, 8));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France?'
    , p_provider    => uc_ai.c_provider_anthropic
    , p_model       => 'claude-haiku-4-5'
    , p_config      => config('{"anthropic":{"g_max_tokens":8}}')
    );

    ut.expect(request_json(1).get_number('max_tokens')).to_equal(8);
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_length);
    ut.expect(l_result.get_clob('final_message'), 'the partial text is kept').to_equal(to_clob('The capital of France is'));
    expect_all_consumed(1);
  end anthropic_max_tokens_is_length;


  procedure google_finish_reasons
  as
    l_result json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.google_candidate(json_array_t('[{"text":"The capital of France is"}]'), 'MAX_TOKENS', 20, 8));
    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France?'
    , p_provider    => uc_ai.c_provider_google
    , p_model       => 'gemini-2.5-flash'
    , p_config      => config
    );
    ut.expect(l_result.get_string('finish_reason'), 'MAX_TOKENS').to_equal(uc_ai.c_finish_reason_length);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('The capital of France is'));

    enqueue(test_uc_ai_wire_2.google_candidate(json_array_t('[{"text":"I cannot help with that."}]'), 'SAFETY', 20, 6));
    l_result := uc_ai.generate_text(
      p_user_prompt => 'Something unsafe.'
    , p_provider    => uc_ai.c_provider_google
    , p_model       => 'gemini-2.5-flash'
    , p_config      => config
    );
    ut.expect(l_result.get_string('finish_reason'), 'SAFETY').to_equal(uc_ai.c_finish_reason_content_filter);

    expect_all_consumed(2);
  end google_finish_reasons;


  procedure openai_chat_finish_reasons
  as
    l_result json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.chat_completion('The capital of France is', p_finish_reason => 'length'));
    l_result := uc_ai.generate_text(
      p_user_prompt => 'What is the capital of France?'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"openai":{"g_use_responses_api":false}}')
    );
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_length);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('The capital of France is'));
    ut.expect(messages_of(l_result).get_size, 'user and the partial answer').to_equal(2);

    enqueue(test_uc_ai_wire_2.chat_completion(null, p_finish_reason => 'content_filter'));
    l_result := uc_ai.generate_text(
      p_user_prompt => 'Something unsafe.'
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"openai":{"g_use_responses_api":false}}')
    );
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_content_filter);
    ut.expect(l_result.get_clob('final_message'), 'nothing to show').to_be_null();
    ut.expect(messages_of(l_result).get_size, 'no assistant turn').to_equal(1);

    expect_all_consumed(2);
  end openai_chat_finish_reasons;


  procedure response_without_usage
  as
    l_result json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.chat_completion('ok', p_with_usage => false));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"openai":{"g_use_responses_api":false}}')
    );

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('ok'));
    expect_usage(l_result, 0, 0, 0, 0);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'no usage');
    expect_all_consumed(1);
  end response_without_usage;


  -- ---- reasoning replay --------------------------------------------------------

  procedure anthropic_replays_signed_thinking
  as
    l_result   json_object_t;
    l_messages json_array_t := json_array_t();
    l_content  json_array_t := json_array_t();
    l_replayed json_array_t;
  begin
    enqueue_sample('anthropic/1-simple-response');

    -- the normalized turn keeps the order the model answered in: text, then the
    -- two reasoning items; only the signed one can go back
    l_content.append(uc_ai_message_api.create_text_content('Paris.'));
    l_content.append(uc_ai_message_api.create_reasoning_content('The user asks for a capital.', json_object_t('{"type":"thinking","signature":"SIGNED_BY_ANTHROPIC"}')));
    l_content.append(uc_ai_message_api.create_reasoning_content('An unsigned afterthought.'));

    l_messages.append(uc_ai_message_api.create_simple_user_message('Capital of France?'));
    l_messages.append(uc_ai_message_api.create_assistant_message(l_content));
    l_messages.append(uc_ai_message_api.create_simple_user_message('And of Italy?'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_anthropic
    , p_model    => 'claude-sonnet-4-0'
    , p_config   => config('{"g_enable_reasoning":true,"g_reasoning_level":"low"}')
    );

    l_replayed := content_of(item(request_json(1).get_array('messages'), 1));
    ut.expect(l_replayed.get_size, 'thinking and text, the unsigned block dropped').to_equal(2);
    ut.expect(item(l_replayed, 0)).to_equal(json_object_t(
      '{"type":"thinking","thinking":"The user asks for a capital.","signature":"SIGNED_BY_ANTHROPIC"}'));
    ut.expect(item(l_replayed, 1)).to_equal(json_object_t('{"type":"text","text":"Paris."}'));
    ut.expect(request_json(1).get_object('thinking').get_number('budget_tokens')).to_equal(2048);

    ut.expect(messages_of(l_result).get_size).to_equal(4);
    expect_all_consumed(1);
  end anthropic_replays_signed_thinking;


  procedure responses_encrypted_reasoning
  as
    l_result   json_object_t;
    l_request  json_object_t;
    l_messages json_array_t := json_array_t();
    l_content  json_array_t := json_array_t();
    l_item     json_object_t;
  begin
    enqueue(test_uc_ai_wire_2.responses_body(
      json_array_t('[{"id":"rs_wire_2","type":"reasoning","encrypted_content":"ENCRYPTED_TURN_2","summary":[]},'
        || '{"id":"msg_wire_2","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","annotations":[],"text":"Rome."}]}]')
    , 'resp_wire_2', 30, 10, 5));

    -- encrypted reasoning is only reachable through the Responses API globals
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai.g_enable_reasoning := true;
    uc_ai.g_reasoning_level := uc_ai.c_reasoning_level_low;
    uc_ai_responses_api.g_include_encrypted_reasoning := true;

    l_content.append(uc_ai_message_api.create_reasoning_content('Thinking about capitals.', json_object_t('{"id":"rs_wire_1","encrypted_content":"ENCRYPTED_TURN_1"}')));
    l_content.append(uc_ai_message_api.create_text_content('Paris.'));

    l_messages.append(uc_ai_message_api.create_simple_user_message('Capital of France?'));
    l_messages.append(uc_ai_message_api.create_assistant_message(l_content));
    l_messages.append(uc_ai_message_api.create_simple_user_message('And of Italy?'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_openai
    , p_model    => 'gpt-5-mini'
    );

    l_request := request_json(1);
    ut.expect(l_request.get_array('include')).to_equal(json_array_t('["reasoning.encrypted_content"]'));
    ut.expect(l_request.get_boolean('store')).to_be_false();
    ut.expect(l_request.get_object('reasoning').get_string('effort')).to_equal('low');

    -- the reasoning item goes back with its blob, before the assistant message
    ut.expect(l_request.get_array('input').get_size, 'user, reasoning, assistant, user').to_equal(4);
    ut.expect(item(l_request.get_array('input'), 1)).to_equal(json_object_t(
      '{"type":"reasoning","id":"rs_wire_1","summary":[{"type":"summary_text","text":"Thinking about capitals."}],"encrypted_content":"ENCRYPTED_TURN_1"}'));
    ut.expect(item(l_request.get_array('input'), 2).get_string('role')).to_equal('assistant');

    -- and the new blob is kept for the next turn
    l_item := item(content_of(last_message_of(l_result)), 0);
    ut.expect(l_item.get_string('type')).to_equal('reasoning');
    ut.expect(l_item.get_object('providerOptions').get_string('id')).to_equal('rs_wire_2');
    ut.expect(l_item.get_object('providerOptions').get_string('encrypted_content')).to_equal('ENCRYPTED_TURN_2');
    ut.expect(l_item.has('text'), 'no summary text was sent').to_be_false();
    ut.expect(last_message_of(l_result).get_string('response_id')).to_equal('resp_wire_2');

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Rome.'));
    expect_usage(l_result, 30, 10, 40, 5);
    expect_all_consumed(1);
  end responses_encrypted_reasoning;


  -- ---- embeddings --------------------------------------------------------------

  procedure openrouter_embeddings
  as
    l_vectors json_array_t;
  begin
    enqueue_sample('openrouter/6-embedding-response');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => uc_ai_test_samples.get_json('openrouter/6-embedding-request').get_array('input')
    , p_provider => uc_ai.c_provider_openrouter
    , p_model    => 'thenlper/gte-base'
    , p_config   => config
    );

    expect_url(1, 'https://openrouter.ai/api/v1/embeddings');
    expect_request(1, 'openrouter/6-embedding-request');
    ut.expect(uc_ai_test_http_mock.request(1).credential).to_equal(c_credential);

    ut.expect(l_vectors.get_size, 'one vector per input').to_equal(3);
    ut.expect(treat(l_vectors.get(0) as json_array_t).get_size, 'dimensions').to_equal(4);
    ut.expect(treat(l_vectors.get(0) as json_array_t).get_number(0)).to_equal(0.024633146822452545);
    ut.expect(treat(l_vectors.get(2) as json_array_t).get_number(0)).to_equal(-0.0018287446582689881);
    expect_all_consumed(1);
  end openrouter_embeddings;


  procedure google_embeddings_config
  as
    l_vectors  json_array_t;
    l_requests json_array_t;
  begin
    enqueue('{"embeddings":[{"values":[0.1,0.2,0.3]},{"values":[0.4,0.5,0.6]}]}');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["first","second"]')
    , p_provider => uc_ai.c_provider_google
    , p_model    => 'gemini-embedding-001'
    , p_config   => config('{"google":{"g_embedding_task_type":"RETRIEVAL_DOCUMENT","g_embedding_output_dimensions":768}}')
    );

    -- one batch request per input, each carrying the model and the config
    l_requests := request_json(1).get_array('requests');
    ut.expect(l_requests.get_size).to_equal(2);
    ut.expect(item(l_requests, 0)).to_equal(json_object_t(
      '{"model":"models/gemini-embedding-001","content":{"parts":[{"text":"first"}]},"task_type":"RETRIEVAL_DOCUMENT","output_dimensionality":768}'));
    ut.expect(item(item(l_requests, 1).get_object('content').get_array('parts'), 0).get_string('text')).to_equal('second');

    ut.expect(l_vectors.get_size).to_equal(2);
    ut.expect(treat(l_vectors.get(1) as json_array_t).get_number(0)).to_equal(0.4);
    expect_all_consumed(1);
  end google_embeddings_config;


  procedure ollama_embeddings
  as
    l_vectors json_array_t;
  begin
    enqueue('{"model":"nomic-embed-text","embeddings":[[0.1,0.2],[0.3,0.4]],"prompt_eval_count":4}');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["first","second"]')
    , p_provider => uc_ai.c_provider_ollama
    , p_model    => 'nomic-embed-text'
    , p_config   => config
    );

    expect_url(1, 'http://localhost:11434/api/embed');
    ut.expect(request_json(1)).to_equal(json_object_t('{"model":"nomic-embed-text","input":["first","second"]}'));

    ut.expect(l_vectors.get_size).to_equal(2);
    ut.expect(treat(l_vectors.get(1) as json_array_t).get_number(1)).to_equal(0.4);
    expect_all_consumed(1);
  end ollama_embeddings;


  -- ---- events ------------------------------------------------------------------

  procedure event_callback_during_tool_round_trip
  as
    l_result json_object_t;
    l_event  t_event;
  begin
    register_users_tool;
    enqueue(test_uc_ai_wire_2.chat_tool_call('call_wire_1', 'TT_GET_USERS'));
    enqueue(test_uc_ai_wire_2.chat_completion(c_jim_answer, 100, 12));

    uc_ai.set_event_callback('TEST_UC_AI_WIRE_3.ON_EVENT');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_users_prompt
    , p_system_prompt => c_users_system
    , p_provider      => uc_ai.c_provider_openai
    , p_model         => 'gpt-4o-mini'
    , p_config        => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],"openai":{"g_use_responses_api":false}}')
    );

    uc_ai.clear_event_callback;

    ut.expect(count_events(uc_ai.c_event_tool_call), 'tool_call events').to_equal(1);
    ut.expect(count_events(uc_ai.c_event_tool_result), 'tool_result events').to_equal(1);
    ut.expect(count_events(uc_ai.c_event_assistant_text), 'assistant_text events').to_equal(1);
    ut.expect(count_events(uc_ai.c_event_response_complete), 'response_complete events').to_equal(1);

    -- every event of the call shares its correlation id
    l_event := first_event(uc_ai.c_event_tool_call);
    ut.expect(l_event.request_id, 'request id').to_be_not_null();
    ut.expect(first_event(uc_ai.c_event_response_complete).request_id).to_equal(l_event.request_id);
    ut.expect(json_object_t.parse(l_event.payload).get_string('toolName')).to_equal('TT_GET_USERS');
    ut.expect(json_object_t.parse(first_event(uc_ai.c_event_tool_result).payload).get_clob('result')).to_equal(test_uc_ai_wire.recorded_users);
    ut.expect(json_object_t.parse(first_event(uc_ai.c_event_response_complete).payload).get_clob('final_message')).to_equal(to_clob(c_jim_answer));

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    expect_all_consumed(2);
  end event_callback_during_tool_round_trip;

end test_uc_ai_wire_3;
/
