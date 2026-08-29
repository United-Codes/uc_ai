create or replace package body test_uc_ai_oci_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its code; a backtrace adds nothing
  -- @dblinter ignore(g-7230): the tool handler records what it was given in package state, which the tests read back

  c_credential constant varchar2(30 char) := 'WIRE_TEST_CREDENTIAL';
  c_tool_tag   constant varchar2(30 char) := 'wire_oci_test';

  -- The placeholder the OCI samples were recorded with; the request carries it verbatim.
  c_compartment constant varchar2(100 char) := 'ocid1.tenancy.oc1..aaaaaaaaXXXX...';
  c_llama       constant varchar2(64 char)  := 'meta.llama-3.3-70b-instruct';
  c_cohere      constant varchar2(64 char)  := 'cohere.command-a-03-2025';

  c_recipe_prompt       constant varchar2(200 char) := 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?';
  c_recipe_system_short constant varchar2(200 char) := 'You are an assistant helping users to get recipes. Please answer in short sentences.';
  c_tool_prompt         constant varchar2(200 char) := 'Echo a and b, then list the users.';
  c_preamble            constant varchar2(200 char) := 'I will use one or more of the available tools to find the answer';

  -- The message the COHERE converter sends when the history has no user turn left.
  c_cohere_continue constant varchar2(200 char) := 'Continue processing the conversation above.';

  -- what the echo handler was last called with
  g_last_echo_args json_object_t;

  e_missing_config exception;
  pragma exception_init(e_missing_config, -20502);
  e_invalid_config exception;
  pragma exception_init(e_invalid_config, -20503);


  -- ---- helpers (the shared ones live in test_uc_ai_wire) -------------------------

  function config(p_json in varchar2 default '{}') return json_object_t
  as
    l_config json_object_t := test_uc_ai_wire.config(p_json);
  begin
    l_config.put('oci', json_object_t('{"g_compartment_id":"' || c_compartment || '","g_max_tokens":600}'));
    return l_config;
  end config;


  procedure enqueue(p_body in clob)
  as
  begin
    uc_ai_test_http_mock.enqueue(p_body);
  end enqueue;


  function request_json(p_index in pls_integer) return json_object_t
  as
  begin
    return uc_ai_test_http_mock.request_json(p_index);
  end request_json;


  function chat_request(p_index in pls_integer) return json_object_t
  as
  begin
    return request_json(p_index).get_object('chatRequest');
  end chat_request;


  function item(
    p_array in json_array_t
  , p_index in pls_integer
  ) return json_object_t
  as
  begin
    return treat(p_array.get(p_index) as json_object_t);
  end item;


  function content_of(p_message in json_object_t) return json_array_t
  as
  begin
    return treat(p_message.get('content') as json_array_t);
  end content_of;


  procedure expect_all_consumed(p_requests in pls_integer)
  as
  begin
    test_uc_ai_wire.expect_all_consumed(p_requests);
  end expect_all_consumed;


  function messages_of(p_result in json_object_t) return json_array_t
  as
  begin
    return test_uc_ai_wire.messages_of(p_result);
  end messages_of;


  -- ---- hand-written provider responses -------------------------------------------

  /*
   * A GENERIC chat result around one choice. p_message is the AssistantMessage
   * the choice carries, so a test can give it content, toolCalls, both or a JSON
   * null content.
   */
  function generic_response(
    p_message           in json_object_t
  , p_finish_reason     in varchar2    default 'stop'
  , p_prompt_tokens     in pls_integer default 10
  , p_completion_tokens in pls_integer default 5
  ) return clob
  as
    l_body    json_object_t := json_object_t();
    l_chat    json_object_t := json_object_t();
    l_choice  json_object_t := json_object_t();
    l_choices json_array_t  := json_array_t();
    l_usage   json_object_t := json_object_t();
  begin
    l_choice.put('index', 0);
    l_choice.put('message', p_message);
    l_choice.put('finishReason', p_finish_reason);
    l_choices.append(l_choice);

    l_usage.put('completionTokens', p_completion_tokens);
    l_usage.put('promptTokens', p_prompt_tokens);
    l_usage.put('totalTokens', p_prompt_tokens + p_completion_tokens);

    l_chat.put('apiFormat', 'GENERIC');
    l_chat.put('choices', l_choices);
    l_chat.put('usage', l_usage);

    l_body.put('modelId', c_llama);
    l_body.put('modelVersion', '1.0.0');
    l_body.put('chatResponse', l_chat);

    return l_body.to_clob;
  end generic_response;


  function generic_text(p_text in varchar2) return clob
  as
    l_message json_object_t := json_object_t();
    l_content json_array_t  := json_array_t();
    l_text    json_object_t := json_object_t();
  begin
    l_text.put('type', 'TEXT');
    l_text.put('text', p_text);
    l_content.append(l_text);
    l_message.put('role', 'ASSISTANT');
    l_message.put('content', l_content);

    return generic_response(l_message);
  end generic_text;


  /*
   * One FunctionCall, the shape OCI returns in AssistantMessage.toolCalls:
   * arguments is the JSON text the model produced, not an object.
   */
  function generic_tool_call(
    p_id        in varchar2
  , p_name      in varchar2
  , p_arguments in varchar2 default '{}'
  ) return json_object_t
  as
    l_call json_object_t := json_object_t();
  begin
    l_call.put('type', 'FUNCTION');
    l_call.put('id', p_id);
    l_call.put('name', p_name);
    l_call.put('arguments', p_arguments);
    return l_call;
  end generic_tool_call;


  function generic_tool_calls(p_tool_calls in json_array_t) return clob
  as
    l_message json_object_t := json_object_t();
  begin
    l_message.put('role', 'ASSISTANT');
    l_message.put('toolCalls', p_tool_calls);

    return generic_response(l_message, 'tool_calls', 100, 10);
  end generic_tool_calls;


  /*
   * A COHERE chat result. p_tool_calls null gives a plain completion.
   */
  function cohere_response(
    p_text            in varchar2
  , p_tool_calls      in json_array_t default null
  , p_chat_history    in json_array_t default null
  , p_finish_reason   in varchar2     default 'COMPLETE'
  , p_error_message   in varchar2     default null
  , p_prompt_tokens   in pls_integer  default 10
  , p_output_tokens   in pls_integer  default 5
  ) return clob
  as
    l_body  json_object_t := json_object_t();
    l_chat  json_object_t := json_object_t();
    l_usage json_object_t := json_object_t();
  begin
    l_usage.put('completionTokens', p_output_tokens);
    l_usage.put('promptTokens', p_prompt_tokens);
    l_usage.put('totalTokens', p_prompt_tokens + p_output_tokens);

    l_chat.put('apiFormat', 'COHERE');
    l_chat.put('text', p_text);
    l_chat.put('chatHistory', coalesce(p_chat_history, json_array_t()));
    l_chat.put('finishReason', p_finish_reason);

    if p_tool_calls is not null then
      l_chat.put('toolCalls', p_tool_calls);
    end if;

    if p_error_message is not null then
      l_chat.put('errorMessage', p_error_message);
    end if;

    l_chat.put('usage', l_usage);

    l_body.put('modelId', c_cohere);
    l_body.put('modelVersion', '1.0');
    l_body.put('chatResponse', l_chat);

    return l_body.to_clob;
  end cohere_response;


  function cohere_tool_call(
    p_name       in varchar2
  , p_parameters in varchar2 default '{}'
  ) return json_object_t
  as
    l_call json_object_t := json_object_t();
  begin
    l_call.put('name', p_name);
    l_call.put('parameters', json_object_t(p_parameters));
    return l_call;
  end cohere_tool_call;


  /*
   * The two-call COHERE tool turn every cohere tool test starts from: a preamble
   * plus one call to each registered tool, with the chatHistory OCI returns
   * alongside it (the live loop replays that history verbatim).
   */
  function cohere_tool_turn return clob
  as
    l_calls   json_array_t  := json_array_t();
    l_history json_array_t  := json_array_t();
    l_user    json_object_t := json_object_t();
    l_chatbot json_object_t := json_object_t();
  begin
    l_calls.append(cohere_tool_call('WIRE_E_ECHO', '{"name":"a"}'));
    l_calls.append(cohere_tool_call('WIRE_E_GET_USERS'));

    l_user.put('role', 'USER');
    l_user.put('message', c_tool_prompt);
    l_history.append(l_user);

    l_chatbot.put('role', 'CHATBOT');
    l_chatbot.put('message', c_preamble);
    l_chatbot.put('toolCalls', l_calls);
    l_history.append(l_chatbot);

    return cohere_response(
      p_text          => c_preamble
    , p_tool_calls    => l_calls
    , p_chat_history  => l_history
    , p_prompt_tokens => 167
    , p_output_tokens => 28
    );
  end cohere_tool_turn;


  -- ---- tool handlers and registration --------------------------------------------

  function echo_name(p_args in clob) return clob
  as
    l_args json_object_t := json_object_t.parse(p_args);
  begin
    g_last_echo_args := l_args;
    return 'echo:' || l_args.get_string('name');
  end echo_name;


  function list_users return clob
  as
  begin
    return '[{"user_id":1,"name":"Jim"}]';
  end list_users;


  /*
   * One tool with a flat string parameter and one with none. Both rows are
   * rolled back with the test.
   */
  procedure register_tools
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code in ('WIRE_E_ECHO', 'WIRE_E_GET_USERS');

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => 'WIRE_E_ECHO'
    , p_description   => 'Echo a name'
    , p_function_call => 'return test_uc_ai_oci_wire.echo_name(:args);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{"name":{"type":"string","description":"Name to echo"}},"required":["name"]}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );
    ut.expect(l_tool_id, 'WIRE_E_ECHO registered').to_be_not_null();

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => 'WIRE_E_GET_USERS'
    , p_description   => 'Get information on all the users in the system'
    , p_function_call => 'return test_uc_ai_oci_wire.list_users;'
    , p_json_schema   => json_object_t('{"type":"object","properties":{}}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );
    ut.expect(l_tool_id, 'WIRE_E_GET_USERS registered').to_be_not_null();
  end register_tools;


  function tool_config return json_object_t
  as
  begin
    return config('{"g_enable_tools":true,"g_tool_tags":["' || c_tool_tag || '"]}');
  end tool_config;


  -- ---- message history builders ---------------------------------------------------

  function count_up_history(p_system_prompt in varchar2) return json_array_t
  as
    l_messages json_array_t := json_array_t();
  begin
    l_messages.append(uc_ai_message_api.create_system_message(p_system_prompt));
    l_messages.append(uc_ai_message_api.create_simple_user_message('1'));
    l_messages.append(uc_ai_message_api.create_simple_assistant_message('2'));
    l_messages.append(uc_ai_message_api.create_simple_user_message('3'));
    return l_messages;
  end count_up_history;


  /*
   * system, user, an assistant turn with two calls, and the turn that answers
   * both: the history an agent continuation hands back.
   */
  function tool_history return json_array_t
  as
    l_messages json_array_t := json_array_t();
    l_calls    json_array_t := json_array_t();
    l_results  json_array_t := json_array_t();
  begin
    l_messages.append(uc_ai_message_api.create_system_message('You are a helper.'));
    l_messages.append(uc_ai_message_api.create_simple_user_message(c_tool_prompt));

    l_calls.append(uc_ai_message_api.create_tool_call_content(
      p_tool_call_id => 'call_a'
    , p_tool_name    => 'WIRE_E_ECHO'
    , p_args         => '{"name":"a"}'
    ));
    l_calls.append(uc_ai_message_api.create_tool_call_content(
      p_tool_call_id => 'call_b'
    , p_tool_name    => 'WIRE_E_GET_USERS'
    , p_args         => '{}'
    ));
    l_messages.append(uc_ai_message_api.create_assistant_message(l_calls));

    l_results.append(uc_ai_message_api.create_tool_result_content(
      p_tool_call_id => 'call_a'
    , p_tool_name    => 'WIRE_E_ECHO'
    , p_result       => 'echo:a'
    ));
    l_results.append(uc_ai_message_api.create_tool_result_content(
      p_tool_call_id => 'call_b'
    , p_tool_name    => 'WIRE_E_GET_USERS'
    , p_result       => list_users
    ));
    l_messages.append(uc_ai_message_api.create_tool_message(l_results));

    return l_messages;
  end tool_history;


  -- ---- fixtures --------------------------------------------------------------------

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
    g_last_echo_args := null;
  end reset_state;


  -- ---- generic ---------------------------------------------------------------------

  procedure generic_empty_tool_calls
  as
    l_result json_object_t;
  begin
    -- The recorded completion carries "toolCalls": []. An empty array is not a
    -- tool turn: reading it as one used to append an ASSISTANT tool message and
    -- make a second request that could never terminate.
    test_uc_ai_wire.enqueue_sample('generic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_prompt
    , p_system_prompt => c_recipe_system_short
    , p_provider      => uc_ai.c_provider_oci
    , p_model         => c_llama
    , p_config        => config
    );

    test_uc_ai_wire.expect_request(1, 'generic/1-simple-request');
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential static id').to_equal(c_credential);

    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(0);
    ut.expect(l_result.get_clob('final_message')).to_be_like('You can make a salad with tomatoes, olives, and cheese.%');
    ut.expect(messages_of(l_result).get_size, 'system, user, assistant').to_equal(3);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci generic empty tool calls');
    expect_all_consumed(1);
  end generic_empty_tool_calls;


  procedure generic_continue_conversation
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample('generic/2-continue-conv-response');

    l_result := uc_ai.generate_text(
      p_messages => count_up_history('Let''s count up')
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_llama
    , p_config   => config
    );

    test_uc_ai_wire.expect_request(1, 'generic/2-continue-conv-request');

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('4'));
    ut.expect(messages_of(l_result).get_size, 'history plus the answer').to_equal(5);
    expect_all_consumed(1);
  end generic_continue_conversation;


  procedure generic_parallel_tool_calls
  as
    l_result   json_object_t;
    l_messages json_array_t;
    l_calls    json_array_t := json_array_t();
    l_tool_a   json_object_t;
    l_tool_b   json_object_t;
  begin
    register_tools;

    l_calls.append(generic_tool_call('call_a', 'WIRE_E_ECHO', '{"name":"a"}'));
    l_calls.append(generic_tool_call('call_b', 'WIRE_E_GET_USERS'));
    enqueue(generic_tool_calls(l_calls));
    enqueue(generic_text('Done.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_llama
    , p_config      => tool_config
    );

    -- user, the assistant turn with both calls, one TOOL message per call
    l_messages := chat_request(2).get_array('messages');
    ut.expect(l_messages.get_size, 'user, assistant, TOOL, TOOL').to_equal(4);
    ut.expect(item(l_messages, 1).get_array('toolCalls').get_size, 'both calls in one assistant turn').to_equal(2);

    l_tool_a := item(l_messages, 2);
    l_tool_b := item(l_messages, 3);

    -- ToolMessage answers a single toolCallId, so each carries exactly one part
    ut.expect(l_tool_a.get_string('role')).to_equal('TOOL');
    ut.expect(l_tool_a.get_string('toolCallId')).to_equal('call_a');
    ut.expect(content_of(l_tool_a).get_size, 'only its own result').to_equal(1);
    ut.expect(item(content_of(l_tool_a), 0).get_clob('text')).to_equal(to_clob('echo:a'));

    ut.expect(l_tool_b.get_string('role')).to_equal('TOOL');
    ut.expect(l_tool_b.get_string('toolCallId')).to_equal('call_b');
    ut.expect(content_of(l_tool_b).get_size, 'only its own result').to_equal(1);
    ut.expect(item(content_of(l_tool_b), 0).get_clob('text')).to_equal(list_users);

    ut.expect(g_last_echo_args.get_string('name'), 'the handler saw its own arguments').to_equal('a');
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(2);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Done.'));
    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci generic parallel tool calls');
    expect_all_consumed(2);
  end generic_parallel_tool_calls;


  procedure generic_null_content_tool_turn
  as
    l_result  json_object_t;
    l_message json_object_t;
    l_calls   json_array_t := json_array_t();
  begin
    register_tools;

    -- AssistantMessage documents content as null (not "") on a tool turn.
    -- has('content') is true for a JSON null and get_array then raises ORA-30625.
    l_calls.append(generic_tool_call('call_a', 'WIRE_E_ECHO', '{"name":"a"}'));
    l_message := json_object_t('{"role":"ASSISTANT","content":null}');
    l_message.put('toolCalls', l_calls);

    enqueue(generic_response(l_message, 'tool_calls', 100, 10));
    enqueue(generic_text('Done.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_llama
    , p_config      => tool_config
    );

    ut.expect(l_result.get_number('tool_calls_count'), 'the tool still ran').to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Done.'));
    expect_all_consumed(2);
  end generic_null_content_tool_turn;


  procedure generic_replays_tool_history
  as
    l_result   json_object_t;
    l_messages json_array_t;
    l_assistant json_object_t;
    l_calls    json_array_t;
  begin
    register_tools;
    enqueue(generic_text('Both done.'));

    l_result := uc_ai.generate_text(
      p_messages => tool_history
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_llama
    , p_config   => tool_config
    );

    l_messages := chat_request(1).get_array('messages');
    ut.expect(l_messages.get_size, 'system, user, assistant, TOOL, TOOL').to_equal(5);

    -- the calls come back as FunctionCalls, not as the text "Tool call: NAME"
    l_assistant := item(l_messages, 2);
    ut.expect(l_assistant.get_string('role')).to_equal('ASSISTANT');
    ut.expect(l_assistant.has('content'), 'no content next to a pure tool turn').to_be_false();

    l_calls := l_assistant.get_array('toolCalls');
    ut.expect(l_calls.get_size).to_equal(2);
    ut.expect(item(l_calls, 0).get_string('type')).to_equal('FUNCTION');
    ut.expect(item(l_calls, 0).get_string('id')).to_equal('call_a');
    ut.expect(item(l_calls, 0).get_string('name')).to_equal('WIRE_E_ECHO');
    ut.expect(item(l_calls, 0).get_clob('arguments')).to_equal(to_clob('{"name":"a"}'));

    -- and the results come back as TOOL messages, not as a USER turn
    ut.expect(item(l_messages, 3).get_string('role')).to_equal('TOOL');
    ut.expect(item(l_messages, 3).get_string('toolCallId')).to_equal('call_a');
    ut.expect(item(content_of(item(l_messages, 3)), 0).get_clob('text')).to_equal(to_clob('echo:a'));
    ut.expect(item(l_messages, 4).get_string('role')).to_equal('TOOL');
    ut.expect(item(l_messages, 4).get_string('toolCallId')).to_equal('call_b');

    ut.expect(chat_request(1).to_clob, 'nothing was turned into prose').not_to_be_like('%Tool call:%');
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Both done.'));
    expect_all_consumed(1);
  end generic_replays_tool_history;


  procedure generic_round_trip_replay
  as
    l_result   json_object_t;
    l_replayed json_object_t;
    l_live     json_array_t;
    l_replay   json_array_t;
    l_calls    json_array_t := json_array_t();
  begin
    register_tools;

    l_calls.append(generic_tool_call('call_a', 'WIRE_E_ECHO', '{"name":"a"}'));
    enqueue(generic_tool_calls(l_calls));
    enqueue(generic_text('Done.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_llama
    , p_config      => tool_config
    );

    -- Feed the returned history back in, which is what an agent continuation
    -- does. The converter has to rebuild the request the live loop built.
    enqueue(generic_text('Still done.'));

    l_replayed := uc_ai.generate_text(
      p_messages => messages_of(l_result)
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_llama
    , p_config   => tool_config
    );

    l_live   := chat_request(2).get_array('messages');
    l_replay := chat_request(3).get_array('messages');

    ut.expect(l_live.get_size, 'user, assistant, TOOL').to_equal(3);
    ut.expect(l_replay.get_size, 'the same three plus the answer').to_equal(4);

    ut.expect(item(l_replay, 0), 'user turn').to_equal(item(l_live, 0));
    ut.expect(item(l_replay, 1), 'assistant tool call').to_equal(item(l_live, 1));
    ut.expect(item(l_replay, 2), 'tool result').to_equal(item(l_live, 2));
    ut.expect(item(l_replay, 3).get_string('role'), 'the answer of the first run').to_equal('ASSISTANT');

    ut.expect(l_replayed.get_clob('final_message')).to_equal(to_clob('Still done.'));
    expect_all_consumed(3);
  end generic_round_trip_replay;


  -- ---- cohere ----------------------------------------------------------------------

  procedure cohere_tool_results_own_output
  as
    l_result       json_object_t;
    l_tool_results json_array_t;
  begin
    register_tools;
    enqueue(cohere_tool_turn);
    enqueue(cohere_response('Both done.', p_prompt_tokens => 1217, p_output_tokens => 27));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => tool_config
    );

    -- Cohere's ToolResult is {call, outputs[]}: the outputs of ONE call
    l_tool_results := chat_request(2).get_array('toolResults');
    ut.expect(l_tool_results.get_size, 'one entry per tool call').to_equal(2);
    ut.expect(item(l_tool_results, 0).get_array('outputs').get_size, 'outputs of WIRE_E_ECHO').to_equal(1);
    ut.expect(item(l_tool_results, 1).get_array('outputs').get_size, 'outputs of WIRE_E_GET_USERS').to_equal(1);
    ut.expect(item(item(l_tool_results, 0).get_array('outputs'), 0).get_clob('result')).to_equal(to_clob('echo:a'));
    ut.expect(item(item(l_tool_results, 1).get_array('outputs'), 0).get_clob('result')).to_equal(list_users);

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(2);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Both done.'));
    expect_all_consumed(2);
  end cohere_tool_results_own_output;


  procedure cohere_keeps_preamble_text
  as
    l_result    json_object_t;
    l_assistant json_object_t;
    l_content   json_array_t;
  begin
    register_tools;
    enqueue(cohere_tool_turn);
    enqueue(cohere_response('Both done.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => tool_config
    );

    -- chatResponse.text is the model's preamble; it belongs to the assistant
    -- turn that made the calls and must survive into the returned history.
    l_assistant := item(messages_of(l_result), 1);
    ut.expect(l_assistant.get_string('role')).to_equal('assistant');

    l_content := content_of(l_assistant);
    ut.expect(l_content.get_size, 'the preamble plus both calls').to_equal(3);
    ut.expect(item(l_content, 0).get_string('type')).to_equal('text');
    ut.expect(item(l_content, 0).get_clob('text')).to_equal(to_clob(c_preamble));
    ut.expect(item(l_content, 1).get_string('type')).to_equal('tool_call');

    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci cohere preamble kept');
    expect_all_consumed(2);
  end cohere_keeps_preamble_text;


  procedure cohere_round_trip_replay
  as
    l_result   json_object_t;
    l_replayed json_object_t;
    l_history  json_array_t;
    l_chatbot  json_object_t;
    l_calls    json_array_t;
    l_results  json_array_t;
  begin
    register_tools;
    enqueue(cohere_tool_turn);
    enqueue(cohere_response('Both done.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => tool_config
    );

    enqueue(cohere_response('Still done.'));

    l_replayed := uc_ai.generate_text(
      p_messages => messages_of(l_result)
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_cohere
    , p_config   => tool_config
    );

    l_history := chat_request(3).get_array('chatHistory');
    ut.expect(l_history.get_size, 'user, chatbot with the calls, tool, chatbot').to_equal(4);
    ut.expect(item(l_history, 0).get_string('role')).to_equal('USER');

    -- one CHATBOT turn for the whole assistant message, carrying both calls
    l_chatbot := item(l_history, 1);
    ut.expect(l_chatbot.get_string('role')).to_equal('CHATBOT');
    ut.expect(l_chatbot.get_clob('message')).to_equal(to_clob(c_preamble));

    l_calls := l_chatbot.get_array('toolCalls');
    ut.expect(l_calls.get_size).to_equal(2);
    ut.expect(item(l_calls, 0).get_string('name')).to_equal('WIRE_E_ECHO');
    ut.expect(item(l_calls, 0).get('parameters').is_object, 'parameters is an object, not a JSON string').to_be_true();
    ut.expect(item(l_calls, 0).get_object('parameters').get_string('name')).to_equal('a');

    -- the results replay as CohereToolResults with their own call and outputs
    l_results := item(l_history, 2).get_array('toolResults');
    ut.expect(item(l_history, 2).get_string('role')).to_equal('TOOL');
    ut.expect(l_results.get_size).to_equal(2);
    ut.expect(item(l_results, 0).get_object('call').get_string('name')).to_equal('WIRE_E_ECHO');
    ut.expect(item(l_results, 0).get_object('call').get_object('parameters').get_string('name'), 'the arguments of the call it answers').to_equal('a');
    ut.expect(item(l_results, 0).get('outputs').is_array, 'outputs is an array').to_be_true();
    ut.expect(item(l_results, 0).get_array('outputs').get_size).to_equal(1);
    ut.expect(item(item(l_results, 0).get_array('outputs'), 0).get_clob('result')).to_equal(to_clob('echo:a'));

    -- the plain answer turn must not pick up an empty toolCalls array
    ut.expect(item(l_history, 3).get_string('role')).to_equal('CHATBOT');
    ut.expect(item(l_history, 3).get_clob('message')).to_equal(to_clob('Both done.'));
    ut.expect(item(l_history, 3).has('toolCalls'), 'a plain turn carries no toolCalls').to_be_false();

    ut.expect(l_replayed.get_clob('final_message')).to_equal(to_clob('Still done.'));
    expect_all_consumed(3);
  end cohere_round_trip_replay;


  procedure cohere_history_without_user_turn
  as
    l_result   json_object_t;
    l_messages json_array_t := json_array_t();
  begin
    -- CohereChatRequest.message is required. A history that ends with the
    -- assistant used to send it as null, which OCI rejects.
    l_messages.append(uc_ai_message_api.create_system_message('You are a helper.'));
    l_messages.append(uc_ai_message_api.create_simple_user_message('1'));
    l_messages.append(uc_ai_message_api.create_simple_assistant_message('2'));

    enqueue(cohere_response('3'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_cohere
    , p_config   => config
    );

    ut.expect(chat_request(1).get_clob('message')).to_equal(to_clob(c_cohere_continue));
    ut.expect(chat_request(1).get_array('chatHistory').get_size, 'the user and the assistant turn').to_equal(2);
    ut.expect(item(chat_request(1).get_array('chatHistory'), 1).get_string('role')).to_equal('CHATBOT');
    ut.expect(chat_request(1).get_clob('preambleOverride')).to_equal(to_clob('You are a helper.'));
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('3'));
    expect_all_consumed(1);
  end cohere_history_without_user_turn;


  procedure cohere_empty_history_raises
  as
    l_messages json_array_t;
    l_system   clob;
    l_user     clob;
    l_code     pls_integer;
  begin
    -- Reading the last element of an empty array used to raise ORA-30625.
    begin
      uc_ai_oci.convert_lm_messages_to_cohere_oci(json_array_t(), l_messages, l_system, l_user);
      ut.fail('expected -20502');
    exception
      when e_missing_config then
        l_code := sqlcode;
    end;

    ut.expect(l_code, 'empty history').to_equal(uc_ai_error.c_err_missing_config);
    expect_all_consumed(0);
  end cohere_empty_history_raises;


  procedure cohere_finish_reason_states
  as
    l_result json_object_t;
  begin
    -- CohereChatResponse.FinishReason has no CONTENT_FILTER; everything that is
    -- not COMPLETE or MAX_TOKENS used to be reported as a clean stop.
    enqueue(cohere_response('I cannot help with that.', p_finish_reason => 'ERROR_TOXIC'));
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => config
    );
    ut.expect(l_result.get_string('finish_reason'), 'ERROR_TOXIC').to_equal(uc_ai.c_finish_reason_content_filter);

    enqueue(cohere_response('Sorry.', p_finish_reason => 'ERROR_LIMIT', p_error_message => 'context length exceeded'));
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => config
    );
    ut.expect(l_result.get_string('finish_reason'), 'ERROR_LIMIT').to_equal('error');
    ut.expect(l_result.get_string('error_message'), 'the provider reason is surfaced').to_equal('context length exceeded');

    enqueue(cohere_response('You can make a salad', p_finish_reason => 'MAX_TOKENS'));
    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => config
    );
    ut.expect(l_result.get_string('finish_reason'), 'MAX_TOKENS').to_equal(uc_ai.c_finish_reason_length);

    expect_all_consumed(3);
  end cohere_finish_reason_states;


  procedure cohere_flat_parameter_definitions
  as
    l_result json_object_t;
    l_tools  json_array_t;
    l_echo   json_object_t;
  begin
    register_tools;
    enqueue(cohere_response('Nothing to do.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_tool_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere
    , p_config      => tool_config
    );

    l_tools := chat_request(1).get_array('tools');

    <<tools_loop>>
    for i in 0 .. l_tools.get_size - 1 loop
      if item(l_tools, i).get_string('name') = 'WIRE_E_ECHO' then
        l_echo := item(l_tools, i);
      end if;
    end loop tools_loop;

    -- CohereTool.parameterDefinitions is a map of name -> {type, description,
    -- isRequired}. A flat one-parameter schema must arrive with its parameter.
    ut.expect(l_echo, 'WIRE_E_ECHO offered').to_be_not_null();
    ut.expect(l_echo.get_object('parameterDefinitions').get_size, 'one parameter').to_equal(1);
    ut.expect(l_echo.get_object('parameterDefinitions').get_object('name').get_string('type')).to_equal('string');
    ut.expect(l_echo.get_object('parameterDefinitions').get_object('name').get_boolean('isRequired')).to_be_true();

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Nothing to do.'));
    expect_all_consumed(1);
  end cohere_flat_parameter_definitions;


  -- ---- serving mode ------------------------------------------------------------------

  procedure dedicated_serving_type_raises
  as
    l_result json_object_t;
    l_code   pls_integer;
    l_config json_object_t := test_uc_ai_wire.config;
  begin
    l_config.put('oci', json_object_t('{"g_compartment_id":"' || c_compartment || '","g_serving_type":"DEDICATED"}'));

    -- DedicatedServingMode is {servingType, endpointId} and has no modelId. UC AI
    -- has no endpoint setting, so the body it would build is invalid.
    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_recipe_prompt
      , p_provider    => uc_ai.c_provider_oci
      , p_model       => c_llama
      , p_config      => l_config
      );
      ut.fail('expected -20503');
    exception
      when e_invalid_config then
        l_code := sqlcode;
    end;

    ut.expect(l_code, 'DEDICATED serving type').to_equal(uc_ai_error.c_err_invalid_config);
    expect_all_consumed(0);
  end dedicated_serving_type_raises;

end test_uc_ai_oci_wire;
/
