create or replace package body test_uc_ai_wire_2 as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its code; a backtrace adds nothing
  -- @dblinter ignore(g-7230): the tool handlers record what they were given in package state, which the tests read back

  c_credential constant varchar2(30 char) := 'WIRE_TEST_CREDENTIAL';
  c_tool_tag   constant varchar2(30 char) := 'wire_test';

  -- The prompts the samples were recorded with.
  c_recipe_prompt       constant varchar2(200 char) := 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?';
  c_recipe_system_short constant varchar2(200 char) := 'You are an assistant helping users to get recipes. Please answer in short sentences.';
  c_users_prompt        constant varchar2(200 char) := 'What is the email address of Jim?';
  c_users_system        constant varchar2(200 char) := 'You are an assistant to a time tracking system. Your tools give you access to user information.';
  c_count_system        constant varchar2(200 char) := 'Let''s count up. One at a time. Just reply with the next number.';

  -- The placeholder the OCI samples were recorded with; the request carries it verbatim.
  c_oci_compartment constant varchar2(100 char) := 'ocid1.tenancy.oc1..aaaaaaaaXXXX...';
  c_oci_chat_url    constant varchar2(200 char) := 'https://inference.generativeai.us-ashburn-1.oci.oraclecloud.com/20231130/actions/chat';
  c_oci_embed_url   constant varchar2(200 char) := 'https://inference.generativeai.us-ashburn-1.oci.oraclecloud.com/20231130/actions/embedText';
  c_oci_llama       constant varchar2(64 char)  := 'meta.llama-3.3-70b-instruct';
  c_oci_cohere      constant varchar2(64 char)  := 'cohere.command-a-03-2025';

  c_jim_answer constant varchar2(100 char) := 'Jim''s email address is jim.halpert@dundermifflin.com.';

  -- what the tool handlers were last called with
  g_last_clock_in_args json_object_t;
  g_last_echo_args     json_object_t;

  -- Error codes the tests expect and uc_ai.pks declares no exception for.
  e_missing_config exception;
  pragma exception_init(e_missing_config, -20502);
  e_structured_unsupported exception;
  pragma exception_init(e_structured_unsupported, -20307);
  e_tool_not_found exception;
  pragma exception_init(e_tool_not_found, -20504);


  -- ---- helpers (shared ones live in test_uc_ai_wire; the builders below are shared with test_uc_ai_wire_3)

  function config(p_json in varchar2 default '{}') return json_object_t
  as
  begin
    return test_uc_ai_wire.config(p_json);
  end config;


  /*
   * A config for the OCI samples: their compartment placeholder and maxTokens.
   */
  function oci_config(p_json in varchar2 default '{}') return json_object_t
  as
    l_config json_object_t := config(p_json);
  begin
    l_config.put('oci', json_object_t('{"g_compartment_id":"' || c_oci_compartment || '","g_max_tokens":600}'));
    return l_config;
  end oci_config;


  procedure enqueue(p_body in clob)
  as
  begin
    uc_ai_test_http_mock.enqueue(p_body);
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
    return uc_ai_test_http_mock.request_json(p_index);
  end request_json;


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


  function last_message_of(p_result in json_object_t) return json_object_t
  as
    l_messages json_array_t := messages_of(p_result);
  begin
    return item(l_messages, l_messages.get_size - 1);
  end last_message_of;


  /*
   * A tools array keyed by tool name, so two arrays compare regardless of the
   * order the tools were read from the table in. Handles the bare form
   * ({name, ...}) and the OpenAI envelope ({type, function: {name, ...}}).
   */
  function tools_by_name(p_tools in json_array_t) return json_object_t
  as
    l_by_name json_object_t := json_object_t();
    l_tool    json_object_t;
  begin
    <<tools_loop>>
    for i in 0 .. p_tools.get_size - 1 loop
      l_tool := item(p_tools, i);
      if l_tool.has('function') then
        l_by_name.put(l_tool.get_object('function').get_string('name'), l_tool);
      else
        l_by_name.put(l_tool.get_string('name'), l_tool);
      end if;
    end loop tools_loop;

    return l_by_name;
  end tools_by_name;


  /*
   * The request equals the recorded one, with the tools array compared as a set:
   * the recorded order is the order the tool rows happened to be read in, which
   * a fresh insert does not reproduce. p_parent names the object that holds the
   * tools array (OCI keeps it under chatRequest); p_also_aside removes one more
   * key from the comparison, which the caller then asserts on its own.
   */
  procedure expect_request_tools_aside(
    p_index      in pls_integer
  , p_sample     in varchar2
  , p_parent     in varchar2 default null
  , p_also_aside in varchar2 default null
  )
  as
    l_actual          json_object_t := request_json(p_index);
    l_expected        json_object_t := uc_ai_test_samples.get_json(p_sample);
    l_actual_parent   json_object_t;
    l_expected_parent json_object_t;
    l_actual_tools    json_array_t;
    l_expected_tools  json_array_t;
  begin
    if p_parent is null then
      l_actual_parent   := l_actual;
      l_expected_parent := l_expected;
    else
      l_actual_parent   := l_actual.get_object(p_parent);
      l_expected_parent := l_expected.get_object(p_parent);
    end if;

    l_actual_tools   := l_actual_parent.get_array('tools');
    l_expected_tools := l_expected_parent.get_array('tools');
    l_actual_parent.remove('tools');
    l_expected_parent.remove('tools');

    if p_also_aside is not null then
      l_actual_parent.remove(p_also_aside);
      l_expected_parent.remove(p_also_aside);
    end if;

    ut.expect(l_actual, 'request ' || p_index || ' vs ' || p_sample || ' (tools aside)').to_equal(l_expected);
    ut.expect(tools_by_name(l_actual_tools), 'tools of request ' || p_index || ' vs ' || p_sample).to_equal(tools_by_name(l_expected_tools));
  end expect_request_tools_aside;


  procedure expect_error_code(
    p_sqlcode  in pls_integer
  , p_expected in pls_integer
  , p_message  in varchar2
  )
  as
  begin
    ut.expect(p_sqlcode, p_message).to_equal(p_expected);
  end expect_error_code;


  -- ---- hand-written provider responses -----------------------------------------

  /*
   * A Chat Completions body. p_content null gives "content": null, as the API
   * does on a tool-call or content-filter turn.
   */
  function chat_completion(
    p_content       in varchar2
  , p_prompt_tokens in pls_integer default 10
  , p_output_tokens in pls_integer default 5
  , p_finish_reason in varchar2    default 'stop'
  , p_model         in varchar2    default 'gpt-4o-mini-2024-07-18'
  , p_tool_calls    in json_array_t default null
  , p_with_usage    in boolean     default true
  ) return clob
  as
    l_body    json_object_t := json_object_t();
    l_choice  json_object_t := json_object_t();
    l_message json_object_t := json_object_t();
    l_choices json_array_t  := json_array_t();
    l_usage   json_object_t := json_object_t();
  begin
    l_message.put('role', 'assistant');
    l_message.put('content', p_content);
    if p_tool_calls is not null then
      l_message.put('tool_calls', p_tool_calls);
    end if;

    l_choice.put('index', 0);
    l_choice.put('message', l_message);
    l_choice.put('finish_reason', p_finish_reason);
    l_choices.append(l_choice);

    l_body.put('id', 'chatcmpl-wire');
    l_body.put('object', 'chat.completion');
    l_body.put('model', p_model);
    l_body.put('choices', l_choices);

    if p_with_usage then
      l_usage.put('prompt_tokens', p_prompt_tokens);
      l_usage.put('completion_tokens', p_output_tokens);
      l_usage.put('total_tokens', p_prompt_tokens + p_output_tokens);
      l_body.put('usage', l_usage);
    end if;

    return l_body.to_clob;
  end chat_completion;


  function chat_tool_call(
    p_call_id   in varchar2
  , p_tool_name in varchar2
  , p_arguments in varchar2 default '{}'
  , p_model     in varchar2 default 'gpt-4o-mini-2024-07-18'
  ) return clob
  as
    l_calls    json_array_t  := json_array_t();
    l_call     json_object_t := json_object_t();
    l_function json_object_t := json_object_t();
  begin
    l_function.put('name', p_tool_name);
    l_function.put('arguments', p_arguments);
    l_call.put('id', p_call_id);
    l_call.put('type', 'function');
    l_call.put('function', l_function);
    l_calls.append(l_call);

    return chat_completion(
      p_content       => null
    , p_finish_reason => 'tool_calls'
    , p_model         => p_model
    , p_tool_calls    => l_calls
    );
  end chat_tool_call;


  function anthropic_message(
    p_content       in json_array_t
  , p_stop_reason   in varchar2 default 'end_turn'
  , p_input_tokens  in pls_integer default 10
  , p_output_tokens in pls_integer default 5
  ) return clob
  as
    l_body  json_object_t := json_object_t();
    l_usage json_object_t := json_object_t();
  begin
    l_usage.put('input_tokens', p_input_tokens);
    l_usage.put('output_tokens', p_output_tokens);

    l_body.put('id', 'msg_wire');
    l_body.put('type', 'message');
    l_body.put('role', 'assistant');
    l_body.put('model', 'claude-haiku-4-5-20251001');
    l_body.put('content', p_content);
    l_body.put('stop_reason', p_stop_reason);
    l_body.put('usage', l_usage);

    return l_body.to_clob;
  end anthropic_message;


  function google_candidate(
    p_parts            in json_array_t
  , p_finish_reason    in varchar2 default 'STOP'
  , p_prompt_tokens    in pls_integer default 10
  , p_candidate_tokens in pls_integer default 5
  ) return clob
  as
    l_body       json_object_t := json_object_t();
    l_candidate  json_object_t := json_object_t();
    l_content    json_object_t := json_object_t();
    l_candidates json_array_t  := json_array_t();
    l_usage      json_object_t := json_object_t();
  begin
    l_content.put('parts', p_parts);
    l_content.put('role', 'model');
    l_candidate.put('content', l_content);
    l_candidate.put('finishReason', p_finish_reason);
    l_candidate.put('index', 0);
    l_candidates.append(l_candidate);

    l_usage.put('promptTokenCount', p_prompt_tokens);
    l_usage.put('candidatesTokenCount', p_candidate_tokens);
    l_usage.put('totalTokenCount', p_prompt_tokens + p_candidate_tokens);

    l_body.put('candidates', l_candidates);
    l_body.put('usageMetadata', l_usage);
    l_body.put('modelVersion', 'gemini-2.5-flash');

    return l_body.to_clob;
  end google_candidate;


  function ollama_chat(
    p_message     in json_object_t
  , p_prompt_eval in pls_integer default 10
  , p_eval        in pls_integer default 5
  ) return clob
  as
    l_body json_object_t := json_object_t();
  begin
    l_body.put('model', 'qwen3:4b');
    l_body.put('created_at', '2026-01-01T00:00:00Z');
    l_body.put('message', p_message);
    l_body.put('done_reason', 'stop');
    l_body.put('done', true);
    l_body.put('prompt_eval_count', p_prompt_eval);
    l_body.put('eval_count', p_eval);

    return l_body.to_clob;
  end ollama_chat;


  function oci_generic_response(
    p_message           in json_object_t
  , p_finish_reason     in varchar2
  , p_prompt_tokens     in pls_integer
  , p_completion_tokens in pls_integer
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

    l_body.put('modelId', c_oci_llama);
    l_body.put('modelVersion', '1.0.0');
    l_body.put('chatResponse', l_chat);

    return l_body.to_clob;
  end oci_generic_response;


  /*
   * A GENERIC completion carrying text. No toolCalls key: see the two disabled
   * OCI tests for what an empty toolCalls array does to the run.
   */
  function oci_generic_text(
    p_text              in varchar2
  , p_prompt_tokens     in pls_integer default 10
  , p_completion_tokens in pls_integer default 5
  , p_finish_reason     in varchar2    default 'stop'
  ) return clob
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

    return oci_generic_response(l_message, p_finish_reason, p_prompt_tokens, p_completion_tokens);
  end oci_generic_text;


  function oci_generic_tool_calls(p_tool_calls in json_array_t) return clob
  as
    l_message json_object_t := json_object_t();
  begin
    l_message.put('role', 'ASSISTANT');
    l_message.put('toolCalls', p_tool_calls);

    return oci_generic_response(l_message, 'tool_calls', 100, 10);
  end oci_generic_tool_calls;


  function responses_body(
    p_output        in json_array_t
  , p_id            in varchar2    default 'resp_wire'
  , p_input_tokens  in pls_integer default 10
  , p_output_tokens in pls_integer default 5
  , p_reasoning     in pls_integer default 0
  ) return clob
  as
    l_body    json_object_t := json_object_t();
    l_usage   json_object_t := json_object_t();
    l_details json_object_t := json_object_t();
  begin
    l_details.put('reasoning_tokens', p_reasoning);
    l_usage.put('input_tokens', p_input_tokens);
    l_usage.put('output_tokens', p_output_tokens);
    l_usage.put('output_tokens_details', l_details);
    l_usage.put('total_tokens', p_input_tokens + p_output_tokens);

    l_body.put('id', p_id);
    l_body.put('object', 'response');
    l_body.put('status', 'completed');
    l_body.put('model', 'gpt-4o-mini-2024-07-18');
    l_body.put('output', p_output);
    l_body.put('usage', l_usage);

    return l_body.to_clob;
  end responses_body;


  function responses_text(p_text in varchar2) return json_array_t
  as
  begin
    return json_array_t('[{"id":"msg_wire","type":"message","status":"completed","role":"assistant",'
      || '"content":[{"type":"output_text","annotations":[],"text":' || json_object_t('{"t":"' || replace(p_text, '"', '\"') || '"}').get('t').to_string || '}]}]');
  end responses_text;


  -- ---- tool handlers and registration ------------------------------------------

  /*
   * The recorded time-tracking exchange. Its three tools, prompts and tool results
   * are read from the recording instead of being typed a second time.
   */
  function tt_fixture_messages return json_array_t
  as
  begin
    return uc_ai_test_samples.get_json('generic/3-2-tool-call-request').get_object('chatRequest').get_array('messages');
  end tt_fixture_messages;


  function tt_fixture_text(p_message_index in pls_integer) return clob
  as
  begin
    return item(content_of(item(tt_fixture_messages, p_message_index)), 0).get_clob('text');
  end tt_fixture_text;


  function tt_system_prompt return clob
  as
  begin
    return tt_fixture_text(0);
  end tt_system_prompt;


  function tt_user_prompt return clob
  as
  begin
    return tt_fixture_text(1);
  end tt_user_prompt;


  function tt_tool_calls(p_message_index in pls_integer) return json_array_t
  as
  begin
    return item(tt_fixture_messages, p_message_index).get_array('toolCalls');
  end tt_tool_calls;


  function recorded_projects return clob
  as
  begin
    -- messages[11] is the TT_GET_PROJETS result of the recorded exchange
    return tt_fixture_text(11);
  end recorded_projects;


  /*
   * TT_CLOCK_IN as the recording saw it: two failures, then success. The
   * arguments arrive as one JSON object (plus the run context under _ctx).
   */
  function recorded_clock_in(p_args in clob) return clob
  as
    l_args json_object_t := json_object_t.parse(p_args);
  begin
    g_last_clock_in_args := l_args;

    if l_args.get_string('user_email') = 'michael.scott@example.com' then
      return tt_fixture_text(3);
    elsif l_args.get_string('project_name') = 'Marketing' then
      return tt_fixture_text(9);
    end if;

    return 'You are now clocked in to the project "' || l_args.get_string('project_name')
      || '" with the note "' || l_args.get_string('notes') || '".';
  end recorded_clock_in;


  function echo_args(p_args in clob) return clob
  as
  begin
    g_last_echo_args := json_object_t.parse(p_args);
    return 'ok';
  end echo_args;


  function raising_tool return clob
  as
  begin
    raise_application_error(-20777, 'boom');
    return null;
  end raising_tool;


  procedure register_users_tool
  as
  begin
    test_uc_ai_wire.register_users_tool;
  end register_users_tool;


  /*
   * The three tools of the recorded time-tracking exchange, with the recorded
   * descriptions and schemas, answering with the recorded results. Rolled back
   * with the test.
   */
  procedure register_tt_tools
  as
    l_tools         json_array_t := uc_ai_test_samples.get_json('generic/3-1-tool-call-request').get_object('chatRequest').get_array('tools');
    l_tool          json_object_t;
    l_code          uc_ai_tools.code%type;
    l_function_call uc_ai_tools.function_call%type;
    l_tool_id       uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code in ('TT_CLOCK_IN', 'TT_GET_PROJETS', 'TT_GET_USERS');

    <<tools_loop>>
    for i in 0 .. l_tools.get_size - 1 loop
      l_tool := item(l_tools, i);
      l_code := l_tool.get_string('name');

      l_function_call := case l_code
                           when 'TT_CLOCK_IN'    then 'return test_uc_ai_wire_2.recorded_clock_in(:args);'
                           when 'TT_GET_PROJETS' then 'return test_uc_ai_wire_2.recorded_projects;'
                           when 'TT_GET_USERS'   then 'return test_uc_ai_wire.recorded_users;'
                         end;

      l_tool_id := uc_ai_tools_api.create_tool_from_schema(
        p_tool_code     => l_code
      , p_description   => l_tool.get_string('description')
      , p_function_call => l_function_call
      , p_json_schema   => l_tool.get_object('parameters')
      , p_tags          => apex_t_varchar2(c_tool_tag)
      );

      ut.expect(l_tool_id, l_code || ' registered').to_be_not_null();
    end loop tools_loop;
  end register_tt_tools;


  procedure register_echo_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = 'TT_ECHO';

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => 'TT_ECHO'
    , p_description   => 'Echo a name'
    , p_function_call => 'return test_uc_ai_wire_2.echo_args(:args);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{"name":{"type":"string","description":"Name to echo"}},"required":["name"]}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'tool registered').to_be_not_null();
  end register_echo_tool;


  procedure register_raising_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = 'TT_RAISING';

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => 'TT_RAISING'
    , p_description   => 'Always fails'
    , p_function_call => 'return test_uc_ai_wire_2.raising_tool;'
    , p_json_schema   => json_object_t('{"type":"object","properties":{}}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'tool registered').to_be_not_null();
  end register_raising_tool;


  -- ---- message history builders ------------------------------------------------

  function tool_call_turn(
    p_tool_call_id     in varchar2
  , p_tool_name        in varchar2
  , p_provider_options in json_object_t default null
  ) return json_object_t
  as
    l_content json_array_t := json_array_t();
  begin
    l_content.append(uc_ai_message_api.create_tool_call_content(
      p_tool_call_id     => p_tool_call_id
    , p_tool_name        => p_tool_name
    , p_args             => '{}'
    , p_provider_options => p_provider_options
    ));
    return uc_ai_message_api.create_assistant_message(l_content);
  end tool_call_turn;


  function tool_result_turn(
    p_tool_call_id in varchar2
  , p_tool_name    in varchar2
  , p_result       in clob
  ) return json_object_t
  as
    l_content json_array_t := json_array_t();
  begin
    l_content.append(uc_ai_message_api.create_tool_result_content(
      p_tool_call_id => p_tool_call_id
    , p_tool_name    => p_tool_name
    , p_result       => p_result
    ));
    return uc_ai_message_api.create_tool_message(l_content);
  end tool_result_turn;


  /*
   * The recorded time-tracking history up to and including the tool result, then
   * a fresh user question: system, user, assistant tool call, tool result, user.
   */
  function users_tool_history(p_provider_options in json_object_t default null) return json_array_t
  as
    l_messages json_array_t := json_array_t();
  begin
    l_messages.append(uc_ai_message_api.create_system_message(c_users_system));
    l_messages.append(uc_ai_message_api.create_simple_user_message(c_users_prompt));
    l_messages.append(tool_call_turn('toolu_hist_1', 'TT_GET_USERS', p_provider_options));
    l_messages.append(tool_result_turn('toolu_hist_1', 'TT_GET_USERS', test_uc_ai_wire.recorded_users));
    l_messages.append(uc_ai_message_api.create_simple_assistant_message(c_jim_answer));
    l_messages.append(uc_ai_message_api.create_simple_user_message('And Pam''s?'));
    return l_messages;
  end users_tool_history;


  /*
   * The count-up history the continue-conversation samples were recorded with.
   */
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
   * One user message with a text part, a fake PNG and a fake PDF.
   */
  function files_message return json_array_t
  as
    l_messages json_array_t := json_array_t();
    l_files    uc_ai_message_api.t_files := uc_ai_message_api.t_files();
    l_blob     blob := sys.utl_raw.cast_to_raw('hello');
  begin
    l_files.extend(2);
    l_files(1).media_type := 'image/png';
    l_files(1).data_blob  := l_blob;
    l_files(1).filename   := 'pic.png';
    l_files(2).media_type := 'application/pdf';
    l_files(2).data_blob  := l_blob;
    l_files(2).filename   := 'doc.pdf';

    l_messages.append(uc_ai_message_api.create_user_message(p_text => 'Describe the files.', p_files => l_files));
    return l_messages;
  end files_message;


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
    g_last_clock_in_args := null;
    g_last_echo_args     := null;
  end reset_state;


  -- ---- oci ---------------------------------------------------------------------

  procedure oci_generic_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('generic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_prompt
    , p_system_prompt => c_recipe_system_short
    , p_provider      => uc_ai.c_provider_oci
    , p_model         => c_oci_llama
    , p_config        => oci_config
    );

    -- default region, chat action; the compartment travels in the body
    expect_url(1, c_oci_chat_url);
    expect_request(1, 'generic/1-simple-request');
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential static id').to_equal(c_credential);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type')).to_equal('application/json; charset=utf-8');

    ut.expect(l_result.get_clob('final_message')).to_be_like('You can make a salad with tomatoes, olives, and cheese.%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal(c_oci_llama);
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(0);
    ut.expect(messages_of(l_result).get_size).to_equal(3);
    expect_usage(l_result, 72, 41, 113);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci generic simple text');
    expect_all_consumed(1);
  end oci_generic_simple_text;


  procedure oci_generic_continue_conversation
  as
    l_result json_object_t;
  begin
    enqueue_sample('generic/2-continue-conv-response');

    l_result := uc_ai.generate_text(
      p_messages => count_up_history('Let''s count up')
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_oci_llama
    , p_config   => oci_config
    );

    expect_request(1, 'generic/2-continue-conv-request');

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('4'));
    ut.expect(messages_of(l_result).get_size, 'history plus the answer').to_equal(5);
    expect_usage(l_result, 52, 2, 54);
    expect_all_consumed(1);
  end oci_generic_continue_conversation;


  procedure oci_generic_tool_round_trip
  as
    l_result   json_object_t;
    l_messages json_array_t;
    l_tool     json_object_t;
  begin
    register_tt_tools;

    -- The recording holds the first and the sixth request of a six-tool-call run.
    -- The four responses in between are rebuilt from the tool calls the sixth
    -- request replays, so that request comes out byte for byte.
    enqueue_sample('generic/3-1-tool-call-response');         -- 1: TT_CLOCK_IN, unknown user
    enqueue(oci_generic_tool_calls(tt_tool_calls(4)));        -- 2: TT_CLOCK_IN, unknown user again
    enqueue(oci_generic_tool_calls(tt_tool_calls(6)));        -- 3: TT_GET_USERS
    enqueue(oci_generic_tool_calls(tt_tool_calls(8)));        -- 4: TT_CLOCK_IN, unknown project
    enqueue(oci_generic_tool_calls(tt_tool_calls(10)));       -- 5: TT_GET_PROJETS
    enqueue_sample('generic/3-2-tool-call-response');         -- 6: TT_CLOCK_IN, correct
    enqueue(oci_generic_text('You are now clocked in to the project "Marketing Campaign 2025" with the note "meeting".', 1900, 30));

    l_result := uc_ai.generate_text(
      p_user_prompt   => tt_user_prompt
    , p_system_prompt => tt_system_prompt
    , p_provider      => uc_ai.c_provider_oci
    , p_model         => c_oci_llama
    , p_config        => oci_config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    expect_request_tools_aside(1, 'generic/3-1-tool-call-request', 'chatRequest');
    expect_request_tools_aside(6, 'generic/3-2-tool-call-request', 'chatRequest');

    -- request 7 carries the successful clock-in under the recorded call id
    l_messages := request_json(7).get_object('chatRequest').get_array('messages');
    ut.expect(l_messages.get_size, 'system, user, six call/result pairs').to_equal(14);
    l_tool := item(l_messages, 13);
    ut.expect(l_tool.get_string('role')).to_equal('TOOL');
    ut.expect(l_tool.get_string('toolCallId')).to_equal('chatcmpl-tool-e210fb4e15fd4e4abc948e26ae3de5ea');
    ut.expect(item(content_of(l_tool), 0).get_clob('text')).to_be_like('You are now clocked in to the project "Marketing Campaign 2025"%');

    -- the handler saw the arguments of the last call, parsed from the JSON string
    ut.expect(g_last_clock_in_args.get_string('user_email')).to_equal('michael.scott@dundermifflin.com');
    ut.expect(g_last_clock_in_args.get_string('project_name')).to_equal('Marketing Campaign 2025');

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(6);
    ut.expect(l_result.get_clob('final_message')).to_be_like('You are now clocked in%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(messages_of(l_result).get_size, 'system, user, 6 x (assistant, tool), assistant').to_equal(15);
    expect_usage(l_result, 659 + 4 * 100 + 1781 + 1900, 44 + 4 * 10 + 47 + 30);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci generic tool round trip');
    expect_all_consumed(7);
  end oci_generic_tool_round_trip;


  procedure oci_generic_finish_reason_length
  as
    l_result json_object_t;
  begin
    enqueue(oci_generic_text('You can make a salad with', 10, 600, 'length'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_oci_llama
    , p_config      => oci_config
    );

    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_length);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('You can make a salad with'));
    expect_all_consumed(1);
  end oci_generic_finish_reason_length;


  procedure oci_cohere_simple_text
  as
    l_result json_object_t;
  begin
    enqueue_sample('oci_cohere/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_recipe_prompt
    , p_system_prompt => c_recipe_system_short
    , p_provider      => uc_ai.c_provider_oci
    , p_model         => c_oci_cohere
    , p_config        => oci_config
    );

    -- the model prefix selects the COHERE apiFormat on the same endpoint
    expect_url(1, c_oci_chat_url);
    expect_request(1, 'oci_cohere/1-simple-request');

    ut.expect(l_result.get_clob('final_message')).to_be_like('You can make a **Greek salad**%');
    ut.expect(l_result.get_string('finish_reason'), 'COMPLETE maps to stop').to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal(c_oci_cohere);
    ut.expect(messages_of(l_result).get_size).to_equal(3);
    expect_usage(l_result, 36, 74, 110);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci cohere simple text');
    expect_all_consumed(1);
  end oci_cohere_simple_text;


  procedure oci_cohere_continue_conversation
  as
    l_result json_object_t;
  begin
    enqueue_sample('oci_cohere/2-continue-conv-response');

    l_result := uc_ai.generate_text(
      p_messages => count_up_history(c_count_system)
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_oci_cohere
    , p_config   => oci_config
    );

    -- the last user turn becomes message, the rest chatHistory, the system prompt preambleOverride
    expect_request(1, 'oci_cohere/2-continue-conv-request');

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('4'));
    ut.expect(messages_of(l_result).get_size).to_equal(5);
    expect_usage(l_result, 22, 1, 23);
    expect_all_consumed(1);
  end oci_cohere_continue_conversation;


  procedure oci_cohere_tool_round_trip
  as
    l_result       json_object_t;
    l_tool_results json_array_t;
  begin
    register_tt_tools;
    enqueue_sample('oci_cohere/3-1-tool-call-response');
    enqueue_sample('oci_cohere/3-2-tool-call-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => tt_user_prompt
    , p_system_prompt => tt_system_prompt
    , p_provider      => uc_ai.c_provider_oci
    , p_model         => c_oci_cohere
    , p_config        => oci_config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    expect_request_tools_aside(1, 'oci_cohere/3-1-tool-call-request', 'chatRequest');

    -- request 2 replays the chatHistory the provider returned and carries the
    -- results; the outputs are asserted in oci_cohere_tool_results_carry_own_output
    expect_request_tools_aside(2, 'oci_cohere/3-2-tool-call-request', 'chatRequest', p_also_aside => 'toolResults');

    l_tool_results := request_json(2).get_object('chatRequest').get_array('toolResults');
    ut.expect(l_tool_results.get_size, 'one entry per recorded tool call').to_equal(2);
    ut.expect(item(l_tool_results, 0).get_object('call').get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(item(l_tool_results, 0).get_object('call').get_object('parameters').get_size, 'no parameters').to_equal(0);
    ut.expect(item(l_tool_results, 1).get_object('call').get_string('name')).to_equal('TT_GET_PROJETS');
    ut.expect(item(item(l_tool_results, 0).get_array('outputs'), 0).get_clob('result')).to_equal(test_uc_ai_wire.recorded_users);

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(2);
    ut.expect(l_result.get_clob('final_message')).to_be_like('I have found a project called ''Marketing Campaign 2025''%');
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(messages_of(l_result).get_size, 'system, user, assistant (2 calls), tool (2 results), assistant').to_equal(5);
    expect_usage(l_result, 167 + 1217, 28 + 27);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'oci cohere tool round trip');
    expect_all_consumed(2);
  end oci_cohere_tool_round_trip;


  procedure oci_cohere_tool_results_carry_own_output
  as
    l_result       json_object_t;
    l_tool_results json_array_t;
  begin
    register_tt_tools;
    enqueue_sample('oci_cohere/3-1-tool-call-response');
    enqueue_sample('oci_cohere/3-2-tool-call-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => tt_user_prompt
    , p_system_prompt => tt_system_prompt
    , p_provider      => uc_ai.c_provider_oci
    , p_model         => c_oci_cohere
    , p_config        => oci_config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    -- Cohere's ToolResult is {call, outputs[]}: the outputs of ONE call
    l_tool_results := request_json(2).get_object('chatRequest').get_array('toolResults');
    ut.expect(item(l_tool_results, 0).get_array('outputs').get_size, 'outputs of TT_GET_USERS').to_equal(1);
    ut.expect(item(l_tool_results, 1).get_array('outputs').get_size, 'outputs of TT_GET_PROJETS').to_equal(1);
    ut.expect(item(item(l_tool_results, 1).get_array('outputs'), 0).get_clob('result')).to_equal(recorded_projects);
    expect_all_consumed(2);
  end oci_cohere_tool_results_carry_own_output;


  procedure oci_embeddings
  as
    l_vectors json_array_t;
    l_vector  json_array_t;
  begin
    enqueue_sample('generic/6-embedding-response');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["APEX Office Print lets you create and manage print jobs directly from your APEX applications."]')
    , p_provider => uc_ai.c_provider_oci
    , p_model    => 'cohere.embed-english-v3.0'
    , p_config   => config('{"oci":{"g_compartment_id":"..."}}')
    );

    expect_url(1, c_oci_embed_url);
    expect_request(1, 'generic/6-embedding-request');
    ut.expect(uc_ai_test_http_mock.request(1).credential).to_equal(c_credential);

    ut.expect(l_vectors.get_size, 'one vector per input').to_equal(1);
    l_vector := treat(l_vectors.get(0) as json_array_t);
    ut.expect(l_vector.get_size, 'dimensions').to_equal(9);
    ut.expect(l_vector.get_number(0)).to_equal(0.014251709);
    expect_all_consumed(1);
  end oci_embeddings;


  procedure oci_missing_compartment_raises
  as
    l_result json_object_t;
    l_code   pls_integer;
  begin
    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_recipe_prompt
      , p_provider    => uc_ai.c_provider_oci
      , p_model       => c_oci_llama
      , p_config      => config
      );
      ut.fail('expected -20502');
    exception
      when e_missing_config then
        l_code := sqlcode;
    end;

    expect_error_code(l_code, uc_ai_error.c_err_missing_config, 'missing compartment id');
    expect_all_consumed(0);
  end oci_missing_compartment_raises;


  procedure oci_structured_output_unsupported
  as
    l_result json_object_t;
    l_code   pls_integer;
  begin
    begin
      l_result := uc_ai.generate_text(
        p_user_prompt          => c_recipe_prompt
      , p_provider             => uc_ai.c_provider_oci
      , p_model                => c_oci_llama
      , p_config               => oci_config
      , p_response_json_schema => uc_ai_test_utils.get_confidence_json_schema
      );
      ut.fail('expected -20307');
    exception
      when e_structured_unsupported then
        l_code := sqlcode;
    end;

    expect_error_code(l_code, uc_ai_error.c_err_structured_unsupported, 'structured output on OCI');
    expect_all_consumed(0);
  end oci_structured_output_unsupported;


  -- ---- tool calling ------------------------------------------------------------

  procedure anthropic_tool_round_trip
  as
    l_result    json_object_t;
    l_request   json_object_t;
    l_messages  json_array_t;
    l_tool_turn json_object_t;
  begin
    register_users_tool;
    enqueue(anthropic_message(
      json_array_t('[{"type":"text","text":"Let me look that up."},{"type":"tool_use","id":"toolu_wire_1","name":"TT_GET_USERS","input":{}}]')
    , 'tool_use', 50, 20));
    enqueue(anthropic_message(json_array_t('[{"type":"text","text":"' || c_jim_answer || '"}]'), 'end_turn', 300, 15));

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_users_prompt
    , p_system_prompt => c_users_system
    , p_provider      => uc_ai.c_provider_anthropic
    , p_model         => 'claude-haiku-4-5'
    , p_config        => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    -- request 1 offers the tool in Anthropic's bare form
    l_request := request_json(1);
    ut.expect(l_request.get_array('tools').get_size, 'tools offered').to_equal(1);
    ut.expect(item(l_request.get_array('tools'), 0)).to_equal(json_object_t(
      '{"name":"TT_GET_USERS","description":"Get information on all the users in the system",'
      || '"input_schema":{"type":"object","properties":{},"required":[],"$schema":"http://json-schema.org/draft-07/schema#"}}'));

    -- request 2 replays the assistant content and answers in a user turn
    l_request  := request_json(2);
    l_messages := l_request.get_array('messages');
    ut.expect(l_request.get_clob('system')).to_equal(to_clob(c_users_system));
    ut.expect(l_messages.get_size, 'user, assistant, tool results').to_equal(3);
    ut.expect(item(l_messages, 1).get_string('role')).to_equal('assistant');
    ut.expect(item(content_of(item(l_messages, 1)), 1).get_string('type')).to_equal('tool_use');
    ut.expect(item(content_of(item(l_messages, 1)), 1).get_string('id')).to_equal('toolu_wire_1');

    l_tool_turn := item(l_messages, 2);
    ut.expect(l_tool_turn.get_string('role')).to_equal('user');
    ut.expect(item(content_of(l_tool_turn), 0).get_string('type')).to_equal('tool_result');
    ut.expect(item(content_of(l_tool_turn), 0).get_string('tool_use_id')).to_equal('toolu_wire_1');
    ut.expect(item(content_of(l_tool_turn), 0).get_clob('content')).to_equal(test_uc_ai_wire.recorded_users);

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob(c_jim_answer));
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(messages_of(l_result).get_size, 'system, user, assistant, tool, assistant').to_equal(5);
    expect_usage(l_result, 350, 35, 385);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'anthropic tool round trip');
    expect_all_consumed(2);
  end anthropic_tool_round_trip;


  procedure google_tool_round_trip
  as
    l_result   json_object_t;
    l_request  json_object_t;
    l_contents json_array_t;
    l_response json_object_t;
  begin
    register_users_tool;
    enqueue(google_candidate(json_array_t('[{"functionCall":{"name":"TT_GET_USERS","args":{}}}]'), 'STOP', 40, 10));
    enqueue(google_candidate(json_array_t('[{"text":"' || c_jim_answer || '"}]'), 'STOP', 200, 12));

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_users_prompt
    , p_system_prompt => c_users_system
    , p_provider      => uc_ai.c_provider_google
    , p_model         => 'gemini-2.5-flash'
    , p_config        => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    -- request 1 wraps the declarations; Google rejects $schema and additionalProperties
    l_request := request_json(1);
    ut.expect(l_request.get_array('tools').get_size).to_equal(1);
    ut.expect(item(l_request.get_array('tools'), 0).get_array('functionDeclarations').get_size).to_equal(1);
    ut.expect(item(item(l_request.get_array('tools'), 0).get_array('functionDeclarations'), 0)).to_equal(json_object_t(
      '{"name":"TT_GET_USERS","description":"Get information on all the users in the system",'
      || '"parameters":{"type":"object","properties":{},"required":[]}}'));

    -- request 2 replays the model parts and answers with a functionResponse part
    l_contents := request_json(2).get_array('contents');
    ut.expect(l_contents.get_size, 'user, model, function response').to_equal(3);
    ut.expect(item(l_contents, 1).get_string('role')).to_equal('model');
    ut.expect(item(item(l_contents, 1).get_array('parts'), 0).get_object('functionCall').get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(item(l_contents, 2).get_string('role')).to_equal('user');

    l_response := item(item(l_contents, 2).get_array('parts'), 0).get_object('functionResponse');
    -- Gemini sent no call id, so the framework numbers the call itself
    ut.expect(l_response.get_string('id')).to_equal('tool_call_1');
    ut.expect(l_response.get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(l_response.get_object('response').get_clob('result')).to_equal(test_uc_ai_wire.recorded_users);

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob(c_jim_answer));
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(messages_of(l_result).get_size).to_equal(5);
    expect_usage(l_result, 240, 22, 262, 0);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'google tool round trip');
    expect_all_consumed(2);
  end google_tool_round_trip;


  procedure google_tool_error_returned_to_model
  as
    l_result   json_object_t;
    l_contents json_array_t;
    l_response json_object_t;
  begin
    register_raising_tool;
    enqueue(google_candidate(json_array_t('[{"functionCall":{"name":"TT_RAISING","args":{}}}]'), 'STOP', 40, 10));
    enqueue(google_candidate(json_array_t('[{"text":"The tool failed, sorry."}]'), 'STOP', 100, 8));

    l_result := uc_ai.generate_text(
      p_user_prompt => 'Try the tool.'
    , p_provider    => uc_ai.c_provider_google
    , p_model       => 'gemini-2.5-flash'
    , p_config      => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    -- the error is data for the model, not the end of the run
    l_contents := request_json(2).get_array('contents');
    l_response := item(item(l_contents, 2).get_array('parts'), 0).get_object('functionResponse');
    ut.expect(l_response.get_object('response').get_clob('result')).to_be_like('Error executing tool: ORA-20777: boom%');

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('The tool failed, sorry.'));
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(item(content_of(item(messages_of(l_result), 2)), 0).get_clob('result')).to_be_like('Error executing tool: ORA-20777%');
    expect_all_consumed(2);
  end google_tool_error_returned_to_model;


  procedure openai_chat_unknown_tool_raises
  as
    l_result json_object_t;
    l_code   pls_integer;
  begin
    register_users_tool;
    enqueue(chat_tool_call('call_wire_x', 'TT_NO_SUCH_TOOL'));

    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_users_prompt
      , p_provider    => uc_ai.c_provider_openai
      , p_model       => 'gpt-4o-mini'
      , p_config      => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],"openai":{"g_use_responses_api":false}}')
      );
      ut.fail('expected -20504');
    exception
      when e_tool_not_found then
        l_code := sqlcode;
    end;

    expect_error_code(l_code, uc_ai_error.c_err_tool_not_found, 'unknown tool');
    expect_all_consumed(1);
  end openai_chat_unknown_tool_raises;


  procedure openai_chat_tool_schema_key
  as
    l_result   json_object_t;
    l_function json_object_t;
  begin
    register_users_tool;
    enqueue(chat_completion('ok'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],"openai":{"g_use_responses_api":false}}')
    );

    -- Chat Completions: tools[].function.parameters holds the JSON schema
    l_function := item(request_json(1).get_array('tools'), 0).get_object('function');
    ut.expect(l_function.has('parameters'), 'function.parameters present').to_be_true();
    ut.expect(l_function.has('input_schema'), 'no Anthropic input_schema key').to_be_false();
    expect_all_consumed(1);
  end openai_chat_tool_schema_key;


  procedure xai_tool_round_trip
  as
    l_result    json_object_t;
    l_recorded  json_array_t := uc_ai_test_samples.get_json('xai/3-1-tool-call-request').get_array('messages');
    l_messages  json_array_t;
    l_tool_turn json_object_t;
  begin
    register_tt_tools;
    enqueue_sample('xai/3-1-tool-call-response');   -- TT_GET_USERS and TT_GET_PROJETS
    enqueue_sample('xai/3-2-tool-call-response');   -- TT_CLOCK_IN with a "parameters" wrapper
    enqueue(chat_completion('You are now clocked in to the project "Marketing Campaign 2025" with the note "meeting".', 1800, 30, p_model => 'grok-4-fast-reasoning'));

    -- Chat Completions routing for xAI is the OpenAI package's global
    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_openai.g_use_responses_api := false;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags := apex_t_varchar2(c_tool_tag);

    l_result := uc_ai.generate_text(
      p_user_prompt   => item(content_of(item(l_recorded, 1)), 0).get_clob('text')
    , p_system_prompt => item(l_recorded, 0).get_clob('content')
    , p_provider      => uc_ai.c_provider_xai
    , p_model         => 'grok-4-fast-reasoning'
    );

    expect_url(1, 'https://api.x.ai/v1/chat/completions');
    expect_request_tools_aside(1, 'xai/3-1-tool-call-request');
    expect_request_tools_aside(2, 'xai/3-2-tool-call-request');

    -- request 3 carries the clock-in result under the recorded call id
    l_messages := request_json(3).get_array('messages');
    ut.expect(l_messages.get_size, 'system, user, assistant, 2 tool, assistant, tool').to_equal(7);
    l_tool_turn := item(l_messages, 6);
    ut.expect(l_tool_turn.get_string('role')).to_equal('tool');
    ut.expect(l_tool_turn.get_string('tool_call_id')).to_equal('call_23008892');
    ut.expect(l_tool_turn.get_clob('content')).to_be_like('You are now clocked in to the project "Marketing Campaign 2025"%');

    -- the wrapper was removed before the handler saw the arguments
    ut.expect(g_last_clock_in_args.has('parameters'), 'wrapper unwrapped').to_be_false();
    ut.expect(g_last_clock_in_args.get_string('user_email')).to_equal('michael.scott@dundermifflin.com');

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(3);
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    ut.expect(l_result.get_string('model')).to_equal('grok-4-fast-reasoning');
    expect_usage(l_result, 689 + 1660 + 1800, 34 + 55 + 30, 1061 + 1960 + 1830, 338 + 245);
    uc_ai_test_message_utils.valididate_return_object(l_result, 'xai tool round trip');
    expect_all_consumed(3);
  end xai_tool_round_trip;


  procedure ollama_native_tool_round_trip
  as
    l_result   json_object_t;
    l_messages json_array_t;
  begin
    register_users_tool;
    enqueue(ollama_chat(json_object_t('{"role":"assistant","content":"","tool_calls":[{"function":{"name":"TT_GET_USERS","arguments":{}}}]}'), 30, 12));
    enqueue(ollama_chat(json_object_t('{"role":"assistant","content":"' || c_jim_answer || '"}'), 200, 15));

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_users_prompt
    , p_system_prompt => c_users_system
    , p_provider      => uc_ai.c_provider_ollama
    , p_model         => 'qwen3:4b'
    , p_config        => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"],"ollama":{"g_use_responses_api":false}}')
    );

    ut.expect(item(request_json(1).get_array('tools'), 0)).to_equal(json_object_t(
      '{"type":"function","function":{"name":"TT_GET_USERS","description":"Get information on all the users in the system",'
      || '"parameters":{"type":"object","properties":{},"required":[],"$schema":"http://json-schema.org/draft-07/schema#"}}}'));

    -- Ollama has no call ids: the result names the tool instead
    l_messages := request_json(2).get_array('messages');
    ut.expect(l_messages.get_size, 'system, user, assistant, tool').to_equal(4);
    ut.expect(item(l_messages, 2).get_array('tool_calls').get_size).to_equal(1);
    ut.expect(item(l_messages, 3).get_string('role')).to_equal('tool');
    ut.expect(item(l_messages, 3).get_string('tool_name')).to_equal('TT_GET_USERS');
    ut.expect(item(l_messages, 3).get_clob('content')).to_equal(test_uc_ai_wire.recorded_users);

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob(c_jim_answer));
    expect_usage(l_result, 230, 27, 257);
    expect_all_consumed(2);
  end ollama_native_tool_round_trip;


  procedure mistral_tool_round_trip
  as
    l_result   json_object_t;
    l_function json_object_t;
    l_messages json_array_t;
  begin
    register_echo_tool;
    enqueue(chat_tool_call('call_wire_m1', 'TT_ECHO', '{"parameters":{"name":"Jim"}}', p_model => 'mistral-small-latest'));
    enqueue(chat_completion('Echoed Jim.', 50, 5, p_model => 'mistral-small-latest'));

    l_result := uc_ai.generate_text(
      p_user_prompt   => 'Echo the name Jim.'
    , p_system_prompt => 'You echo names with your tool.'
    , p_provider      => uc_ai.c_provider_mistral
    , p_model         => 'mistral-small-latest'
    , p_config        => config('{"g_enable_tools":true,"g_tool_tags":["wire_test"]}')
    );

    -- Mistral has no Responses API: always Chat Completions, schema under parameters
    expect_url(1, 'https://api.mistral.ai/v1/chat/completions');
    l_function := item(request_json(1).get_array('tools'), 0).get_object('function');
    ut.expect(l_function.get_string('name')).to_equal('TT_ECHO');
    ut.expect(l_function.get_object('parameters').get_object('properties').get_object('name').get_string('type')).to_equal('string');
    ut.expect(l_function.get_object('parameters').get_array('required').get_string(0)).to_equal('name');
    ut.expect(l_function.has('input_schema')).to_be_false();

    -- the wrapper is removed, the run context is added, before the bind
    ut.expect(g_last_echo_args.get_string('name')).to_equal('Jim');
    ut.expect(g_last_echo_args.has('parameters'), 'wrapper unwrapped').to_be_false();
    ut.expect(g_last_echo_args.has(uc_ai.c_run_context_key), 'run context handed to the tool').to_be_true();

    l_messages := request_json(2).get_array('messages');
    ut.expect(item(l_messages, 3).get_string('tool_call_id')).to_equal('call_wire_m1');
    ut.expect(item(l_messages, 3).get_clob('content')).to_equal(to_clob('ok'));

    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Echoed Jim.'));
    ut.expect(l_result.get_string('model')).to_equal('mistral-small-latest');
    expect_all_consumed(2);
  end mistral_tool_round_trip;


  -- ---- conversation continuation -----------------------------------------------

  procedure responses_continue_conversation
  as
    l_result    json_object_t;
    l_messages  json_array_t := json_array_t();
    l_assistant json_object_t;
  begin
    enqueue_sample('openai/responses/2-continue-conv-response');

    uc_ai.g_apex_web_credential := c_credential;
    uc_ai_responses_api.g_store_responses := true;

    -- the assistant turn of a stored response remembers its id at message level
    l_assistant := uc_ai_message_api.create_simple_assistant_message('I will remember 42.');
    l_assistant.put('response_id', 'resp_07089a2b3956052a00696e57444c1081978347fd4ba12a9058');

    l_messages.append(uc_ai_message_api.create_system_message('You are a helpful assistant.'));
    l_messages.append(uc_ai_message_api.create_simple_user_message('Remember this number: 42. Say "I will remember 42".'));
    l_messages.append(l_assistant);
    l_messages.append(uc_ai_message_api.create_simple_user_message('What number did I ask you to remember?'));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_openai
    , p_model    => 'gpt-4o-mini'
    );

    -- The whole history travels as input items. The stored id is read from the
    -- message but not sent as previous_response_id: the framework owns the state,
    -- and the API refuses history next to a previous_response_id.
    expect_request(1, 'openai/responses/2-continue-conv-request');
    ut.expect(request_json(1).has('previous_response_id'), 'no previous_response_id').to_be_false();
    ut.expect(request_json(1).get_boolean('store')).to_be_true();

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('You asked me to remember the number 42.'));
    ut.expect(last_message_of(l_result).get_string('response_id'), 'new response id on the new turn')
      .to_equal('resp_07089a2b3956052a00696e5745215c8197a3e53221b6bdd314');
    ut.expect(messages_of(l_result).get_size).to_equal(5);
    expect_usage(l_result, 84, 11, 95, 0);
    expect_all_consumed(1);
  end responses_continue_conversation;


  procedure anthropic_replays_tool_history
  as
    l_result   json_object_t;
    l_request  json_object_t;
    l_messages json_array_t;
    l_block    json_object_t;
  begin
    enqueue_sample('anthropic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_messages => users_tool_history
    , p_provider => uc_ai.c_provider_anthropic
    , p_model    => 'claude-3-5-haiku-latest'
    , p_config   => config
    );

    l_request  := request_json(1);
    l_messages := l_request.get_array('messages');
    ut.expect(l_request.get_clob('system')).to_equal(to_clob(c_users_system));
    ut.expect(l_messages.get_size, 'user, assistant call, user result, assistant, user').to_equal(5);

    l_block := item(content_of(item(l_messages, 1)), 0);
    ut.expect(item(l_messages, 1).get_string('role')).to_equal('assistant');
    ut.expect(l_block.get_string('type')).to_equal('tool_use');
    ut.expect(l_block.get_string('id')).to_equal('toolu_hist_1');
    ut.expect(l_block.get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(l_block.get_object('input').get_size, 'empty input object').to_equal(0);

    l_block := item(content_of(item(l_messages, 2)), 0);
    ut.expect(item(l_messages, 2).get_string('role'), 'tool results travel as a user turn').to_equal('user');
    ut.expect(l_block.get_string('type')).to_equal('tool_result');
    ut.expect(l_block.get_string('tool_use_id')).to_equal('toolu_hist_1');
    ut.expect(l_block.get_clob('content')).to_equal(test_uc_ai_wire.recorded_users);

    ut.expect(item(content_of(item(l_messages, 3)), 0).get_clob('text')).to_equal(to_clob(c_jim_answer));
    ut.expect(item(content_of(item(l_messages, 4)), 0).get_clob('text')).to_equal(to_clob('And Pam''s?'));

    ut.expect(messages_of(l_result).get_size, 'history plus the answer').to_equal(7);
    expect_all_consumed(1);
  end anthropic_replays_tool_history;


  procedure google_replays_tool_history
  as
    l_result   json_object_t;
    l_contents json_array_t;
    l_part     json_object_t;
  begin
    enqueue_sample('google/1-simple-response');

    l_result := uc_ai.generate_text(
      p_messages => users_tool_history(json_object_t('{"thoughtSignature":"SIGNED_BY_GEMINI"}'))
    , p_provider => uc_ai.c_provider_google
    , p_model    => 'gemini-2.5-flash'
    , p_config   => config
    );

    l_contents := request_json(1).get_array('contents');
    ut.expect(l_contents.get_size, 'user, model call, user result, model, user').to_equal(5);

    -- the signature Gemini put on the call part goes back on the same part
    l_part := item(item(l_contents, 1).get_array('parts'), 0);
    ut.expect(item(l_contents, 1).get_string('role')).to_equal('model');
    ut.expect(l_part.get_object('functionCall').get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(l_part.get_object('functionCall').get_object('args').get_size).to_equal(0);
    ut.expect(l_part.get_string('thoughtSignature')).to_equal('SIGNED_BY_GEMINI');

    l_part := item(item(l_contents, 2).get_array('parts'), 0);
    ut.expect(item(l_contents, 2).get_string('role')).to_equal('user');
    ut.expect(l_part.get_object('functionResponse').get_string('name')).to_equal('TT_GET_USERS');
    ut.expect(l_part.get_object('functionResponse').get_object('response').get_clob('result')).to_equal(test_uc_ai_wire.recorded_users);

    ut.expect(messages_of(l_result).get_size).to_equal(7);
    expect_all_consumed(1);
  end google_replays_tool_history;

end test_uc_ai_wire_2;
/
