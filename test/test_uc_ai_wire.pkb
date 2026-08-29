create or replace package body test_uc_ai_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its message; a backtrace adds nothing

  -- Named on every call so no provider ever asks uc_ai_get_key for a key. The
  -- mock records the name; nothing resolves it.
  c_credential constant varchar2(30 char) := 'WIRE_TEST_CREDENTIAL';

  -- The prompts the samples were recorded with. A request only matches its sample
  -- when the prompt is the same text.
  c_capital_prompt      constant varchar2(200 char) := 'What is the capital of France? Please respond with confidence.';
  c_capital_system      constant varchar2(200 char) := 'You are a helpful assistant that provides accurate information.';
  c_recipe_prompt       constant varchar2(200 char) := 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?';
  c_recipe_typo_prompt  constant varchar2(200 char) := 'I have tomatoes, salad, potatoes, olives, and cheese. What an I cook with that?';
  c_recipe_system_short constant varchar2(200 char) := 'You are an assistant helping users to get recipes. Please answer in short sentences.';
  c_recipe_system_list  constant varchar2(200 char) := 'You are an assistant helping users to get recipes. Please just list 3 possible dishe names without instructions.';
  c_filter_prompt       constant varchar2(200 char) := 'Answer in one sentence. If there is a great filter, are we before or after it and why.';
  c_users_prompt        constant varchar2(200 char) := 'What is the email address of Jim?';
  c_users_system        constant varchar2(200 char) := 'You are an assistant to a time tracking system. Your tools give you access to user information.';

  c_users_tool_code     constant uc_ai_tools.code%type := 'TT_GET_USERS';
  c_users_tool_tag      constant varchar2(30 char) := 'wire_test';


  -- ---- helpers ---------------------------------------------------------------

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


  procedure enqueue_sample(p_sample in varchar2)
  as
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(p_sample));
  end enqueue_sample;


  /*
   * The request body UC AI sent equals the recorded request. utPLSQL reports the
   * differing JSON paths when it does not.
   */
  procedure expect_request(
    p_index  in pls_integer
  , p_sample in varchar2
  )
  as
  begin
    ut.expect(uc_ai_test_http_mock.request_json(p_index), 'request ' || p_index || ' vs ' || p_sample)
      .to_equal(uc_ai_test_samples.get_json(p_sample));
  end expect_request;


  procedure expect_url(
    p_index in pls_integer
  , p_url   in varchar2
  )
  as
  begin
    ut.expect(uc_ai_test_http_mock.request(p_index).url, 'URL of request ' || p_index).to_equal(p_url);
  end expect_url;


  /*
   * Every queued response was asked for: the framework made exactly the requests
   * the test expected, no more.
   */
  procedure expect_all_consumed(p_requests in pls_integer)
  as
  begin
    ut.expect(uc_ai_test_http_mock.request_count, 'requests made').to_equal(p_requests);
    ut.expect(uc_ai_test_http_mock.pending_count, 'responses nobody asked for').to_equal(0);
  end expect_all_consumed;


  procedure expect_usage(
    p_result            in json_object_t
  , p_prompt_tokens     in number
  , p_completion_tokens in number
  , p_total_tokens      in number   default null
  , p_reasoning_tokens  in number   default null
  )
  as
    l_usage json_object_t := p_result.get_object('usage');
  begin
    ut.expect(l_usage.get_number('prompt_tokens'), 'usage.prompt_tokens').to_equal(p_prompt_tokens);
    ut.expect(l_usage.get_number('completion_tokens'), 'usage.completion_tokens').to_equal(p_completion_tokens);

    if p_total_tokens is not null then
      ut.expect(l_usage.get_number('total_tokens'), 'usage.total_tokens').to_equal(p_total_tokens);
    end if;

    if p_reasoning_tokens is not null then
      ut.expect(l_usage.get_number('reasoning_tokens'), 'usage.reasoning_tokens').to_equal(p_reasoning_tokens);
    end if;
  end expect_usage;


  function messages_of(p_result in json_object_t) return json_array_t
  as
  begin
    return treat(p_result.get('messages') as json_array_t);
  end messages_of;


  /*
   * Structured output arrives as text in final_message; the caller parses it.
   */
  function structured_output_of(p_result in json_object_t) return json_object_t
  as
  begin
    return json_object_t.parse(p_result.get_clob('final_message'));
  end structured_output_of;


  /*
   * The first reasoning content item of any assistant message, or null.
   */
  function first_reasoning_item(p_result in json_object_t) return json_object_t
  as
    l_messages json_array_t := messages_of(p_result);
    l_message  json_object_t;
    l_content  json_array_t;
    l_item     json_object_t;
  begin
    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_message := treat(l_messages.get(i) as json_object_t);

      continue when l_message.get_string('role') != 'assistant' or not l_message.get('content').is_array;

      l_content := treat(l_message.get('content') as json_array_t);

      <<content_loop>>
      for j in 0 .. l_content.get_size - 1 loop
        l_item := treat(l_content.get(j) as json_object_t);
        if l_item.get_string('type') = 'reasoning' then
          return l_item;
        end if;
      end loop content_loop;
    end loop message_loop;

    return null;
  end first_reasoning_item;


  /*
   * The confidence answer every structured-output sample was recorded with.
   */
  procedure expect_capital_answer(p_result in json_object_t)
  as
    l_output json_object_t := structured_output_of(p_result);
  begin
    ut.expect(l_output.get_string('response'), 'response').to_equal('The capital of France is Paris.');
    ut.expect(l_output.get_number('confidence'), 'confidence').to_be_between(0.99, 1);
    ut.expect(p_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(messages_of(p_result).get_size, 'system, user, assistant').to_equal(3);
    uc_ai_test_message_utils.valididate_return_object(p_result, 'structured output result');
  end expect_capital_answer;


  /*
   * A tool with no parameters, named like the recorded one, that answers with the
   * recorded result. Tagged so only it reaches the request. The row is rolled back
   * with the test.
   */
  procedure register_users_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_users_tool_code;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_users_tool_code
    , p_description   => 'Get information on all the users in the system'
    , p_function_call => 'return test_uc_ai_wire.recorded_users;'
    , p_json_schema   => json_object_t('{"type":"object","properties":{}}')
    , p_tags          => apex_t_varchar2(c_users_tool_tag)
    );

    ut.expect(l_tool_id, 'tool registered').to_be_not_null();
  end register_users_tool;


  function recorded_users return clob
  as
    l_input json_array_t := uc_ai_test_samples.get_json('openai/responses/3-2-tool-call-request').get_array('input');
  begin
    -- input[2] is the function_call_output item of the recorded second request
    return treat(l_input.get(2) as json_object_t).get_clob('output');
  end recorded_users;


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


  -- ---- structured output -------------------------------------------------------

  procedure openai_chat_structured_output
  as
    l_result json_object_t;
  begin
    enqueue_sample('openai/chat/4-structured-output-response');

    l_result := uc_ai.generate_text(
      p_user_prompt          => c_capital_prompt
    , p_system_prompt        => c_capital_system
    , p_provider             => uc_ai.c_provider_openai
    , p_model                => 'gpt-4o-mini'
    , p_config               => config('{"openai":{"g_use_responses_api":false}}')
    , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
    );

    expect_url(1, 'https://api.openai.com/v1/chat/completions');
    expect_request(1, 'openai/chat/4-structured-output-request');

    expect_capital_answer(l_result);
    ut.expect(l_result.get_string('model')).to_equal('gpt-4o-mini-2024-07-18');
    expect_usage(l_result, 72, 16, 88, 0);
    expect_all_consumed(1);
  end openai_chat_structured_output;


  procedure openai_responses_structured_output
  as
    l_result json_object_t;
  begin
    enqueue_sample('openai/responses/4-structured-output-response');

    -- The sample was recorded with store: true, which is only reachable through
    -- the package global; the config surface has no key for it.
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_responses_api.g_store_responses := true;

    l_result := uc_ai.generate_text(
      p_user_prompt          => c_capital_prompt
    , p_system_prompt        => c_capital_system
    , p_provider             => uc_ai.c_provider_openai
    , p_model                => 'gpt-4o-mini'
    , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
    );

    expect_url(1, 'https://api.openai.com/v1/responses');
    expect_request(1, 'openai/responses/4-structured-output-request');

    expect_capital_answer(l_result);
    ut.expect(l_result.get_string('model')).to_equal('gpt-4o-mini-2024-07-18');
    expect_usage(l_result, 66, 17, 83, 0);
    expect_all_consumed(1);
  end openai_responses_structured_output;


  procedure anthropic_structured_output
  as
    l_result json_object_t;
  begin
    enqueue_sample('anthropic/4-structured-output-response');

    l_result := uc_ai.generate_text(
      p_user_prompt          => c_capital_prompt
    , p_system_prompt        => c_capital_system
    , p_provider             => uc_ai.c_provider_anthropic
    , p_model                => 'claude-haiku-4-5'
    , p_config               => config
    , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
    );

    expect_url(1, 'https://api.anthropic.com/v1/messages');
    expect_request(1, 'anthropic/4-structured-output-request');

    expect_capital_answer(l_result);
    ut.expect(l_result.get_string('model')).to_equal('claude-haiku-4-5-20251001');
    expect_usage(l_result, 267, 22, 289);
    expect_all_consumed(1);
  end anthropic_structured_output;


  procedure google_structured_output
  as
    l_result json_object_t;
  begin
    enqueue_sample('google/4-structured-output-response');

    l_result := uc_ai.generate_text(
      p_user_prompt          => c_capital_prompt
    , p_system_prompt        => c_capital_system
    , p_provider             => uc_ai.c_provider_google
    , p_model                => 'gemini-2.5-flash'
    , p_config               => config
    , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
    );

    -- with a web credential no ?key= is appended
    expect_url(1, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent');
    expect_request(1, 'google/4-structured-output-request');

    expect_capital_answer(l_result);
    ut.expect(l_result.get_string('model')).to_equal('gemini-2.5-flash');
    expect_usage(l_result, 24, 19, 110, 67);
    expect_all_consumed(1);
  end google_structured_output;


  procedure xai_structured_output
  as
    l_result json_object_t;
  begin
    enqueue_sample('xai/4-structured-output-response');

    -- xAI shares the OpenAI implementation; its Chat Completions route is selected
    -- by the OpenAI package's global, which the xai config block cannot reach.
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;
    uc_ai.g_enable_reasoning := true;

    l_result := uc_ai.generate_text(
      p_user_prompt          => c_capital_prompt
    , p_system_prompt        => c_capital_system
    , p_provider             => uc_ai.c_provider_xai
    , p_model                => 'grok-4-fast-reasoning'
    , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
    );

    expect_url(1, 'https://api.x.ai/v1/chat/completions');
    expect_request(1, 'xai/4-structured-output-request');

    expect_capital_answer(l_result);
    ut.expect(l_result.get_string('model')).to_equal('grok-4-fast-reasoning');
    expect_usage(l_result, 259, 14, 375, 102);
    expect_all_consumed(1);
  end xai_structured_output;


  procedure ollama_structured_output
  as
    l_result json_object_t;
  begin
    enqueue_sample('ollama/4-structured-output-response');

    l_result := uc_ai.generate_text(
      p_user_prompt          => c_capital_prompt
    , p_system_prompt        => c_capital_system
    , p_provider             => uc_ai.c_provider_ollama
    , p_model                => 'qwen3:4b'
    , p_config               => config('{"g_enable_reasoning":true,"ollama":{"g_use_responses_api":false}}')
    , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
    );

    expect_url(1, 'http://localhost:11434/api/chat');
    expect_request(1, 'ollama/4-structured-output-request');

    expect_capital_answer(l_result);
    ut.expect(l_result.get_string('model')).to_equal('qwen3:4b');
    -- the native route reports prompt_eval_count / eval_count, not a usage object
    expect_usage(l_result, 37, 28, 65);
    expect_all_consumed(1);
  end ollama_structured_output;


  -- ---- plain text --------------------------------------------------------------

  procedure anthropic_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('anthropic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_prompt
    , p_system_prompt => c_recipe_system_list
    , p_provider      => uc_ai.c_provider_anthropic
    , p_model         => 'claude-3-5-haiku-latest'
    , p_config        => config
    );

    expect_request(1, 'anthropic/1-simple-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('%Greek Salad with Potato Croutons%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal('claude-3-5-haiku-20241022');
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(0);
    ut.expect(messages_of(l_result).get_size).to_equal(3);
    expect_usage(l_result, 54, 56, 110);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'anthropic simple text');
    expect_all_consumed(1);
  end anthropic_simple_text;


  procedure google_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('google/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_prompt
    , p_system_prompt => c_recipe_system_short
    , p_provider      => uc_ai.c_provider_google
    , p_model         => 'gemini-2.5-flash'
    , p_config        => config
    );

    expect_url(1, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent');
    expect_request(1, 'google/1-simple-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('Make a roasted potato salad.%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal('gemini-2.5-flash');
    ut.expect(messages_of(l_result).get_size).to_equal(3);
    expect_usage(l_result, 38, 27, 553, 488);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'google simple text');
    expect_all_consumed(1);
  end google_simple_text;


  procedure openai_responses_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('openai/responses/1-simple-response');

    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_responses_api.g_store_responses := true;

    l_result := uc_ai.generate_text(
      p_user_prompt   => 'Say "Hello, Responses API!" and nothing else.'
    , p_system_prompt => 'You are a helpful assistant.'
    , p_provider      => uc_ai.c_provider_openai
    , p_model         => 'gpt-4o-mini'
    );

    expect_url(1, 'https://api.openai.com/v1/responses');
    expect_request(1, 'openai/responses/1-simple-request');

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Hello, Responses API!'));
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal('gpt-4o-mini-2024-07-18');
    ut.expect(messages_of(l_result).get_size).to_equal(3);
    expect_usage(l_result, 28, 6, 34, 0);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'responses simple text');
    expect_all_consumed(1);
  end openai_responses_simple_text;


  procedure xai_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('xai/1-simple-response');

    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_typo_prompt
    , p_system_prompt => c_recipe_system_short
    , p_provider      => uc_ai.c_provider_xai
    , p_model         => 'grok-4-fast-non-reasoning'
    );

    expect_url(1, 'https://api.x.ai/v1/chat/completions');
    expect_request(1, 'xai/1-simple-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('You can make a simple Greek-inspired salad%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal('grok-4-fast-non-reasoning');
    expect_usage(l_result, 204, 42, 246, 0);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'xai simple text');
    expect_all_consumed(1);
  end xai_simple_text;


  procedure openrouter_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('openrouter/1-simple-response');

    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_typo_prompt
    , p_system_prompt => c_recipe_system_short
    , p_provider      => uc_ai.c_provider_openrouter
    , p_model         => 'amazon/nova-2-lite-v1:free'
    );

    expect_url(1, 'https://openrouter.ai/api/v1/chat/completions');
    expect_request(1, 'openrouter/1-simple-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('### Simple Recipes Using Your Ingredients:%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal('amazon/nova-2-lite-v1:free');
    expect_usage(l_result, 132, 501, 633, 0);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'openrouter simple text');
    expect_all_consumed(1);
  end openrouter_simple_text;


  -- ---- tool calling ------------------------------------------------------------

  procedure openai_responses_tool_round_trip
  as
    l_result json_object_t;
  begin
    register_users_tool;
    enqueue_sample('openai/responses/3-1-tool-call-response');
    enqueue_sample('openai/responses/3-2-tool-call-response');

    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_responses_api.g_store_responses := true;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags := apex_t_varchar2(c_users_tool_tag);

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_users_prompt
    , p_system_prompt => c_users_system
    , p_provider      => uc_ai.c_provider_openai
    , p_model         => 'gpt-4o-mini'
    );

    -- request 1 offers the tool; request 2 replays the call and carries its result
    expect_request(1, 'openai/responses/3-1-tool-call-request');
    expect_request(2, 'openai/responses/3-2-tool-call-request');

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_be_like('%jim.halpert@dundermifflin.com%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    -- system, user, assistant tool call, tool result, assistant answer
    ut.expect(messages_of(l_result).get_size).to_equal(5);
    -- token usage is summed over both requests
    expect_usage(l_result, 67 + 372, 13 + 22, 80 + 394, 0);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'responses tool round trip');
    expect_all_consumed(2);
  end openai_responses_tool_round_trip;


  procedure openai_chat_tool_round_trip
  as
    l_result       json_object_t;
    l_request      json_object_t;
    l_messages     json_array_t;
    l_assistant    json_object_t;
    l_tool_message json_object_t;
  begin
    register_users_tool;

    -- No recorded Chat Completions exchange uses only this tool, so the two
    -- responses are minimal hand-written ones in the documented shape.
    uc_ai_test_http_mock.enqueue('{"id":"chatcmpl-wire-1","object":"chat.completion","model":"gpt-4o-mini-2024-07-18",'
      || '"choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_wire_1","type":"function",'
      || '"function":{"name":"TT_GET_USERS","arguments":"{}"}}]},"finish_reason":"tool_calls"}],'
      || '"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}');
    uc_ai_test_http_mock.enqueue('{"id":"chatcmpl-wire-2","object":"chat.completion","model":"gpt-4o-mini-2024-07-18",'
      || '"choices":[{"index":0,"message":{"role":"assistant","content":"Jim''s email address is jim.halpert@dundermifflin.com."},"finish_reason":"stop"}],'
      || '"usage":{"prompt_tokens":100,"completion_tokens":12,"total_tokens":112}}');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_users_prompt
    , p_system_prompt => c_users_system
    , p_provider      => uc_ai.c_provider_openai
    , p_model         => 'gpt-4o-mini'
    , p_config        => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],"openai":{"g_use_responses_api":false}}')
    );

    -- request 1 offers exactly the one tagged tool
    l_request := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_request.get_array('tools').get_size, 'tools offered').to_equal(1);
    ut.expect(treat(l_request.get_array('tools').get(0) as json_object_t).get_object('function').get_string('name')).to_equal(c_users_tool_code);

    -- request 2 replays the assistant's tool call and answers it under the same id
    l_messages := uc_ai_test_http_mock.request_json(2).get_array('messages');
    ut.expect(l_messages.get_size, 'system, user, assistant tool call, tool result').to_equal(4);

    l_assistant := treat(l_messages.get(2) as json_object_t);
    ut.expect(l_assistant.get_string('role')).to_equal('assistant');
    ut.expect(treat(l_assistant.get_array('tool_calls').get(0) as json_object_t).get_string('id')).to_equal('call_wire_1');

    l_tool_message := treat(l_messages.get(3) as json_object_t);
    ut.expect(l_tool_message.get_string('role')).to_equal('tool');
    ut.expect(l_tool_message.get_string('tool_call_id')).to_equal('call_wire_1');
    ut.expect(l_tool_message.get_clob('content')).to_equal(recorded_users);

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_be_like('%jim.halpert@dundermifflin.com%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    expect_usage(l_result, 110, 17, 127);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'chat tool round trip');
    expect_all_consumed(2);
  end openai_chat_tool_round_trip;


  procedure tool_loop_stops_at_max_tool_calls
  as
    l_result json_object_t;
    l_raised boolean := false;
  begin
    register_users_tool;

    -- one response, because the framework must not make a second request
    uc_ai_test_http_mock.enqueue('{"id":"chatcmpl-wire-1","object":"chat.completion","model":"gpt-4o-mini-2024-07-18",'
      || '"choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_wire_1","type":"function",'
      || '"function":{"name":"TT_GET_USERS","arguments":"{}"}}]},"finish_reason":"tool_calls"}],'
      || '"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}');

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt    => c_users_prompt
      , p_system_prompt  => c_users_system
      , p_provider       => uc_ai.c_provider_openai
      , p_model          => 'gpt-4o-mini'
      , p_config         => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],"openai":{"g_use_responses_api":false}}')
      , p_max_tool_calls => 1
      );
    exception
      when uc_ai.e_max_calls_exceeded then
        l_raised := true;
    end;

    ut.expect(l_raised, 'raised -20301').to_be_true();
    expect_all_consumed(1);
  end tool_loop_stops_at_max_tool_calls;


  -- ---- error handling ----------------------------------------------------------

  procedure http_400_error_body_raises
  as
    l_result json_object_t;
    l_error  varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(
      p_body        => '{"error":{"message":"Invalid schema for response_format ''Response_with_confidence_score'': ''required'' is required to be supplied and to be an array including every key in properties.","type":"invalid_request_error","param":"response_format","code":null}}'
    , p_status_code => 400
    );

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt          => c_capital_prompt
      , p_provider             => uc_ai.c_provider_openai
      , p_model                => 'gpt-4o-mini'
      , p_config               => config('{"openai":{"g_use_responses_api":false}}')
      , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
      );
      ut.fail('expected -20302');
    exception
      when uc_ai.e_error_response then
        l_error := sqlerrm;
    end;

    ut.expect(l_error).to_be_like('%Invalid schema for response_format%');
    expect_all_consumed(1);
  end http_400_error_body_raises;


  procedure http_502_html_body_raises
  as
    l_result json_object_t;
    l_error  varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(
      p_body        => '<html><body><h1>502 Bad Gateway</h1></body></html>'
    , p_status_code => 502
    );

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_capital_prompt
      , p_provider    => uc_ai.c_provider_openai
      , p_model       => 'gpt-4o-mini'
      , p_config      => config('{"openai":{"g_use_responses_api":false}}')
      );
      ut.fail('expected -20302');
    exception
      when uc_ai.e_error_response then
        l_error := sqlerrm;
    end;

    ut.expect(l_error).to_be_like('%502%');
    ut.expect(l_error).to_be_like('%Bad Gateway%');
    expect_all_consumed(1);
  end http_502_html_body_raises;


  procedure http_404_without_error_key_raises
  as
    l_result json_object_t;
    l_error  varchar2(4000 char);
  begin
    -- OCI style: valid JSON, HTTP 404, and no "error" key to trip over
    uc_ai_test_http_mock.enqueue(
      p_body        => '{"code":"404","message":"Entity with key gpt-4o-mini not found"}'
    , p_status_code => 404
    );

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_capital_prompt
      , p_provider    => uc_ai.c_provider_openai
      , p_model       => 'gpt-4o-mini'
      , p_config      => config('{"openai":{"g_use_responses_api":false}}')
      );
      ut.fail('expected -20302');
    exception
      when uc_ai.e_error_response then
        l_error := sqlerrm;
    end;

    ut.expect(l_error).to_be_like('%HTTP 404%');
    ut.expect(l_error).to_be_like('%Entity with key gpt-4o-mini not found%');
    expect_all_consumed(1);
  end http_404_without_error_key_raises;


  procedure anthropic_error_body_raises
  as
    l_result json_object_t;
    l_error  varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(
      p_body        => '{"type":"error","error":{"type":"invalid_request_error","message":"output_config.format.schema: For ''number'' type, property ''minimum'' is not supported"}}'
    , p_status_code => 400
    );

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt          => c_capital_prompt
      , p_provider             => uc_ai.c_provider_anthropic
      , p_model                => 'claude-haiku-4-5'
      , p_config               => config
      , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
      );
      ut.fail('expected -20302');
    exception
      when uc_ai.e_error_response then
        l_error := sqlerrm;
    end;

    ut.expect(l_error).to_be_like('%property ''minimum'' is not supported%');
    expect_all_consumed(1);
  end anthropic_error_body_raises;


  -- ---- embeddings --------------------------------------------------------------

  procedure openai_embeddings
  as
    l_vectors json_array_t;
    l_vector  json_array_t;
  begin
    enqueue_sample('openai/chat/6-embedding-response');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["APEX Office Print lets you create and manage print jobs directly from your APEX applications."]')
    , p_provider => uc_ai.c_provider_openai
    , p_model    => 'text-embedding-3-small'
    , p_config   => config
    );

    expect_url(1, 'https://api.openai.com/v1/embeddings');
    expect_request(1, 'openai/chat/6-embedding-request');

    ut.expect(l_vectors.get_size, 'one vector per input').to_equal(1);
    l_vector := treat(l_vectors.get(0) as json_array_t);
    ut.expect(l_vector.get_size, 'dimensions').to_equal(17);
    ut.expect(l_vector.get_number(0)).to_equal(0.007621578);
    expect_all_consumed(1);
  end openai_embeddings;


  procedure google_embeddings
  as
    l_vectors json_array_t;
    l_vector  json_array_t;
  begin
    enqueue_sample('google/6-embedding-response');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["APEX Office Print lets you create and manage print jobs directly from your APEX applications."]')
    , p_provider => uc_ai.c_provider_google
    , p_model    => 'gemini-embedding-001'
    , p_config   => config
    );

    expect_url(1, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:batchEmbedContents');
    expect_request(1, 'google/6-embedding-request');

    ut.expect(l_vectors.get_size, 'one vector per input').to_equal(1);
    l_vector := treat(l_vectors.get(0) as json_array_t);
    ut.expect(l_vector.get_size, 'dimensions').to_equal(12);
    ut.expect(l_vector.get_number(0)).to_equal(0.0017690804);
    expect_all_consumed(1);
  end google_embeddings;


  -- ---- reasoning ---------------------------------------------------------------

  procedure anthropic_reasoning_round_trip
  as
    l_result    json_object_t;
    l_reasoning json_object_t;
  begin
    enqueue_sample('anthropic/5-reasoniong-response');

    l_result := uc_ai.generate_text(
      p_user_prompt => c_filter_prompt
    , p_provider    => uc_ai.c_provider_anthropic
    , p_model       => 'claude-sonnet-4-0'
    , p_config      => config('{"g_enable_reasoning":true,"g_reasoning_level":"low"}')
    );

    expect_request(1, 'anthropic/5-reasoning-request');

    -- the answer, not the thinking, is the final message
    ut.expect(l_result.get_clob('final_message')).to_be_like('We are most likely before the Great Filter%');
    ut.expect(l_result.get_clob('final_message')).not_to_be_like('%The Great Filter is a concept%');

    -- the thinking block survives as a signed reasoning item, ready to be replayed
    l_reasoning := first_reasoning_item(l_result);
    ut.expect(l_reasoning, 'reasoning item present').to_be_not_null();
    ut.expect(l_reasoning.get_clob('text')).to_be_like('The Great Filter is a concept%');
    ut.expect(l_reasoning.get_object('providerOptions').get_string('signature')).to_be_like('EvUKCkYIChgCKkBdH3K4%');

    expect_usage(l_result, 57, 303, 360);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'anthropic reasoning', p_should_have_reasoning => true);
    expect_all_consumed(1);
  end anthropic_reasoning_round_trip;


  procedure google_reasoning_round_trip
  as
    l_result    json_object_t;
    l_reasoning json_object_t;
  begin
    enqueue_sample('google/5-reasoniong-response');

    l_result := uc_ai.generate_text(
      p_user_prompt => c_filter_prompt
    , p_provider    => uc_ai.c_provider_google
    , p_model       => 'gemini-2.5-flash'
    , p_config      => config('{"g_enable_reasoning":true,"g_reasoning_level":"low"}')
    );

    expect_request(1, 'google/5-reasoning-request');

    -- the thought part must not become the final message
    ut.expect(l_result.get_clob('final_message')).to_be_like('We are most likely *before* the Great Filter%');
    ut.expect(l_result.get_clob('final_message')).not_to_be_like('%Finalized Great Filter Response%');

    l_reasoning := first_reasoning_item(l_result);
    ut.expect(l_reasoning, 'reasoning item present').to_be_not_null();
    ut.expect(l_reasoning.get_clob('text')).to_be_like('**Finalized Great Filter Response**%');

    expect_usage(l_result, 22, 33, 1043, 988);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'google reasoning', p_should_have_reasoning => true);
    expect_all_consumed(1);
  end google_reasoning_round_trip;


  procedure openai_chat_reasoning_tokens
  as
    l_result json_object_t;
  begin
    enqueue_sample('openai/chat/5-reasoniong-response');

    l_result := uc_ai.generate_text(
      p_user_prompt => c_filter_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'o4-mini'
    , p_config      => config('{"g_enable_reasoning":true,"openai":{"g_use_responses_api":false}}')
    );

    expect_request(1, 'openai/chat/5-reasoning-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('We’re almost certainly before the Great Filter%');
    ut.expect(l_result.get_string('model')).to_equal('o4-mini-2025-04-16');
    expect_usage(l_result, 27, 180, 207, 128);
    expect_all_consumed(1);
  end openai_chat_reasoning_tokens;


  -- ---- transport ---------------------------------------------------------------

  procedure headers_and_credential_on_the_wire
  as
    l_result  json_object_t;
    l_request uc_ai_test_http_mock.t_request;
  begin
    enqueue_sample('anthropic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_prompt
    , p_system_prompt => c_recipe_system_list
    , p_provider      => uc_ai.c_provider_anthropic
    , p_model         => 'claude-3-5-haiku-latest'
    , p_config        => config('{"g_extra_headers":{"X-Tenant-Id":"acme"}}')
    );

    l_request := uc_ai_test_http_mock.request(1);

    -- the credential is handed to the transport, so no key header is built
    ut.expect(l_request.credential, 'credential static id').to_equal(c_credential);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'x-api-key'), 'x-api-key').to_be_null();
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization'), 'Authorization').to_be_null();

    -- the framework's own headers and the caller's extra header travel together
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type')).to_equal('application/json');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'anthropic-version'), 'anthropic-version').to_be_not_null();
    ut.expect(uc_ai_test_http_mock.request_header(1, 'X-Tenant-Id')).to_equal('acme');

    -- and the extra header changed nothing in the body
    expect_request(1, 'anthropic/1-simple-request');
    expect_all_consumed(1);
  end headers_and_credential_on_the_wire;

end test_uc_ai_wire;
/
