create or replace package body test_uc_ai_tools_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  -- Own tools and own tag, so the tools of the other wire suites never reach a
  -- request built here, and theirs never see these.
  c_tag        constant varchar2(30 char) := 'wire_h_test';
  c_flat       constant uc_ai_tools.code%type := 'WIRE_H_FLAT';
  c_wrapped    constant uc_ai_tools.code%type := 'WIRE_H_WRAPPED';
  c_no_args    constant uc_ai_tools.code%type := 'WIRE_H_NO_ARGS';
  c_mixed      constant uc_ai_tools.code%type := 'WIRE_H_MIXED';
  c_big        constant uc_ai_tools.code%type := 'WIRE_H_BIG';

  c_prompt     constant varchar2(200 char) := 'What is the weather in Paris?';

  c_cohere_model  constant uc_ai.model_type := 'cohere.command-a-03-2025';
  c_llama_model   constant uc_ai.model_type := 'meta.llama-3.3-70b-instruct';

  -- The arguments the last tool handler was given, so a test can assert on the
  -- shape a handler actually sees rather than on the shape that went out.
  g_last_args json_object_t;


  -- ---- helpers -----------------------------------------------------------------

  function config(p_json in varchar2 default '{}') return json_object_t
  as
    l_config json_object_t := test_uc_ai_wire.config(p_json);
  begin
    l_config.put('g_enable_tools', true);
    l_config.put('g_tool_tags', json_array_t('["' || c_tag || '"]'));
    return l_config;
  end config;


  /*
   * The Chat Completions route, not the Responses API: this suite is about the
   * `function` envelope of /v1/chat/completions.
   */
  function chat_config return json_object_t
  as
    l_config json_object_t := config;
  begin
    l_config.put('openai', json_object_t('{"g_use_responses_api":false}'));
    return l_config;
  end chat_config;


  function oci_config return json_object_t
  as
    l_config json_object_t := test_uc_ai_wire_2.oci_config;
  begin
    l_config.put('g_enable_tools', true);
    l_config.put('g_tool_tags', json_array_t('["' || c_tag || '"]'));
    return l_config;
  end oci_config;


  procedure enqueue(p_body in clob)
  as
  begin
    test_uc_ai_wire_2.enqueue(p_body);
  end enqueue;


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


  /*
   * A COHERE chat result with plain text. The OCI response shape is documented by
   * Oracle's own SDK types (reference/oci-typescript-sdk/.../cohere-chat-response).
   */
  function cohere_text(p_text in varchar2) return clob
  as
    l_body  json_object_t := json_object_t();
    l_chat  json_object_t := json_object_t();
    l_usage json_object_t := json_object_t();
  begin
    l_usage.put('completionTokens', 5);
    l_usage.put('promptTokens', 10);
    l_usage.put('totalTokens', 15);

    l_chat.put('apiFormat', 'COHERE');
    l_chat.put('text', p_text);
    l_chat.put('chatHistory', json_array_t());
    l_chat.put('finishReason', 'COMPLETE');
    l_chat.put('usage', l_usage);

    l_body.put('modelId', c_cohere_model);
    l_body.put('modelVersion', '1.0');
    l_body.put('chatResponse', l_chat);

    return l_body.to_clob;
  end cohere_text;


  /*
   * One OCI GENERIC assistant turn with a single tool call. `arguments` is the
   * JSON text the model produced, not an object.
   */
  function generic_tool_call(
    p_name      in varchar2
  , p_arguments in varchar2
  ) return clob
  as
    l_body    json_object_t := json_object_t();
    l_chat    json_object_t := json_object_t();
    l_choice  json_object_t := json_object_t();
    l_choices json_array_t  := json_array_t();
    l_message json_object_t := json_object_t();
    l_calls   json_array_t  := json_array_t();
    l_call    json_object_t := json_object_t();
    l_usage   json_object_t := json_object_t();
  begin
    l_call.put('type', 'FUNCTION');
    l_call.put('id', 'call_wire_h');
    l_call.put('name', p_name);
    l_call.put('arguments', p_arguments);
    l_calls.append(l_call);

    l_message.put('role', 'ASSISTANT');
    l_message.put('toolCalls', l_calls);

    l_choice.put('index', 0);
    l_choice.put('message', l_message);
    l_choice.put('finishReason', 'tool_calls');
    l_choices.append(l_choice);

    l_usage.put('completionTokens', 10);
    l_usage.put('promptTokens', 100);
    l_usage.put('totalTokens', 110);

    l_chat.put('apiFormat', 'GENERIC');
    l_chat.put('choices', l_choices);
    l_chat.put('usage', l_usage);

    l_body.put('modelId', c_llama_model);
    l_body.put('modelVersion', '1.0');
    l_body.put('chatResponse', l_chat);

    return l_body.to_clob;
  end generic_tool_call;


  /*
   * The flat schema, exactly as it was registered: two string properties, one of
   * them required. Asserted in full, because a key that survives while the
   * properties are lost is the failure this suite exists for.
   */
  procedure expect_flat_schema(
    p_schema in json_object_t
  , p_label  in varchar2
  )
  as
    l_props json_object_t;
  begin
    ut.expect(p_schema, p_label || ': schema present').to_be_not_null();
    ut.expect(p_schema.get_string('type'), p_label || ': type').to_equal('object');

    l_props := p_schema.get_object('properties');
    ut.expect(l_props, p_label || ': properties present').to_be_not_null();
    ut.expect(l_props.get_size, p_label || ': two properties').to_equal(2);
    ut.expect(l_props.get_object('city').get_string('type'), p_label || ': city type').to_equal('string');
    ut.expect(l_props.get_object('city').get_string('description'), p_label || ': city description').to_equal('City name');
    ut.expect(l_props.get_object('unit').get_string('type'), p_label || ': unit type').to_equal('string');

    ut.expect(p_schema.get_array('required').get_size, p_label || ': one required') .to_equal(1);
    ut.expect(p_schema.get_array('required').get_string(0), p_label || ': required city').to_equal('city');
  end expect_flat_schema;


  /*
   * The tool definition carries the schema under p_key and under no other schema
   * key: a tool emitted under a key the provider ignores looks fine until the
   * model answers with empty arguments.
   */
  procedure expect_schema_under(
    p_tool  in json_object_t
  , p_key   in varchar2
  , p_label in varchar2
  )
  as
    l_other varchar2(30 char) := case p_key when 'parameters' then 'input_schema' else 'parameters' end;
  begin
    ut.expect(p_tool.has(p_key), p_label || ': schema under ' || p_key).to_be_true();
    ut.expect(p_tool.has(l_other), p_label || ': nothing under ' || l_other).to_be_false();
    expect_flat_schema(p_tool.get_object(p_key), p_label);
  end expect_schema_under;


  -- ---- tool handlers -------------------------------------------------------------

  function capture_args(p_args in clob) return clob
  as
  begin
    g_last_args := json_object_t.parse(p_args);
    return 'It is 21 degrees.';
  end capture_args;


  /*
   * Reports the length of the payload it was given, so an assertion can prove the
   * whole argument reached the handler and not a truncated head of it.
   */
  function args_length(p_args in clob) return clob
  as
    l_args json_object_t := json_object_t.parse(p_args);
  begin
    g_last_args := l_args;
    return to_char(sys.dbms_lob.getlength(l_args.get_clob('blob')));
  end args_length;


  -- ---- tool registration ----------------------------------------------------------

  procedure register_tool(
    p_code   in uc_ai_tools.code%type
  , p_schema in varchar2
  , p_call   in varchar2
  )
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    -- every tool of this suite, not just p_code: one test commits (it needs an
    -- APEX session), so a row can outlive its test and would then be offered
    -- alongside the tool the next test registers
    delete from uc_ai_tools where code in (c_flat, c_wrapped, c_no_args, c_mixed, c_big);

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => p_code
    , p_description   => 'Get the weather for a city'
    , p_function_call => p_call
    , p_json_schema   => json_object_t(p_schema)
    , p_tags          => apex_t_varchar2(c_tag)
    );

    ut.expect(l_tool_id, p_code || ' registered').to_be_not_null();
  end register_tool;


  /*
   * Two top-level string parameters, one required. The shape get_tool_schema
   * produces for every multi-parameter tool, and the shape the docs teach.
   */
  procedure register_flat_tool
  as
  begin
    register_tool(
      c_flat
    , '{"type":"object","properties":{'
      || '"city":{"type":"string","description":"City name"},'
      || '"unit":{"type":"string","description":"Celsius or Fahrenheit"}},'
      || '"required":["city"]}'
    , 'return test_uc_ai_tools_wire.capture_args(:args);'
    );
  end register_flat_tool;


  /*
   * The legacy wrapper shape: one top-level object parameter that carries the real
   * arguments. Still in the recorded fixtures (TT_CLOCK_IN), so it has to keep
   * working.
   */
  procedure register_wrapped_tool
  as
  begin
    register_tool(
      c_wrapped
    , '{"type":"object","properties":{'
      || '"parameters":{"type":"object","description":"JSON object containing parameters",'
      || '"properties":{"city":{"type":"string","description":"City name"},'
      || '"unit":{"type":"string","description":"Celsius or Fahrenheit"}},'
      || '"required":["city"]}},"required":["parameters"]}'
    , 'return test_uc_ai_tools_wire.capture_args(:args);'
    );
  end register_wrapped_tool;


  -- ---- fixtures ---------------------------------------------------------------

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
    g_last_args := null;
  end reset_state;


  -- ---- tool schemas on the wire ---------------------------------------------------

  procedure flat_schema_reaches_every_provider
  as
    l_result json_object_t;
    l_tools  json_array_t;
    l_config json_object_t := config;
  begin
    register_flat_tool;

    -- one plain-text answer per provider; none of them is asked to call the tool,
    -- because what is under test is the request UC AI built
    enqueue(test_uc_ai_wire_2.chat_completion('ok'));                                                  -- 1 openai chat
    enqueue(test_uc_ai_wire_2.chat_completion('ok', p_model => 'grok-4-fast-non-reasoning'));          -- 2 xai
    enqueue(test_uc_ai_wire_2.anthropic_message(json_array_t('[{"type":"text","text":"ok"}]')));       -- 3 anthropic
    enqueue(test_uc_ai_wire_2.google_candidate(json_array_t('[{"text":"ok"}]')));                      -- 4 google
    enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t('{"role":"assistant","content":"ok"}')));      -- 5 ollama
    enqueue(test_uc_ai_wire_2.responses_body(test_uc_ai_wire_2.responses_text('ok')));                 -- 6 responses api
    enqueue(test_uc_ai_wire_2.oci_generic_text('ok'));                                                 -- 7 oci generic
    enqueue(cohere_text('ok'));                                                                        -- 8 oci cohere

    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_openai,    p_model => 'gpt-4o-mini', p_config => chat_config);

    -- xAI shares the OpenAI implementation, and its Chat Completions route is
    -- selected by the OpenAI package's global. A config-driven call starts from
    -- the default settings and has no xai key for it, so this one leg is driven
    -- by globals, exactly like test_uc_ai_wire.xai_structured_output.
    uc_ai.g_apex_web_credential := l_config.get_string('g_apex_web_credential');
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags := apex_t_varchar2(c_tag);
    uc_ai_openai.g_use_responses_api := false;
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_xai,       p_model => 'grok-4-fast-non-reasoning');
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_anthropic, p_model => 'claude-haiku-4-5', p_config => config);
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_google,    p_model => 'gemini-2.5-flash', p_config => config);
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_ollama,    p_model => 'qwen3.5:9b', p_config => config('{"ollama":{"g_use_responses_api":false}}'));
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_openai,    p_model => 'gpt-4o-mini', p_config => config('{"openai":{"g_use_responses_api":true}}'));
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_oci,       p_model => c_llama_model, p_config => oci_config);
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_oci,       p_model => c_cohere_model, p_config => oci_config);

    -- 1 OpenAI Chat Completions: tools[].function.parameters
    l_tools := request_json(1).get_array('tools');
    ut.expect(l_tools.get_size, 'openai chat: one tool offered').to_equal(1);
    expect_schema_under(item(l_tools, 0).get_object('function'), 'parameters', 'openai chat');

    -- 2 xAI runs on the same Chat Completions envelope
    l_tools := request_json(2).get_array('tools');
    expect_schema_under(item(l_tools, 0).get_object('function'), 'parameters', 'xai');

    -- 3 Anthropic is the one provider that reads input_schema
    l_tools := request_json(3).get_array('tools');
    expect_schema_under(item(l_tools, 0), 'input_schema', 'anthropic');

    -- 4 Google nests the declarations under a wrapper object
    l_tools := request_json(4).get_array('tools');
    expect_schema_under(item(item(l_tools, 0).get_array('functionDeclarations'), 0), 'parameters', 'google');

    -- 5 Ollama uses the OpenAI-compatible function envelope
    l_tools := request_json(5).get_array('tools');
    expect_schema_under(item(l_tools, 0).get_object('function'), 'parameters', 'ollama');

    -- 6 Responses API carries name/description/parameters flat on the tool
    l_tools := request_json(6).get_array('tools');
    expect_schema_under(item(l_tools, 0), 'parameters', 'responses api');

    -- 7 OCI GENERIC: a FUNCTION tool with the schema under parameters
    l_tools := request_json(7).get_object('chatRequest').get_array('tools');
    ut.expect(item(l_tools, 0).get_string('type'), 'oci generic: FUNCTION').to_equal('FUNCTION');
    expect_schema_under(item(l_tools, 0), 'parameters', 'oci generic');

    -- 8 OCI COHERE: parameterDefinitions instead of a JSON schema
    l_tools := request_json(8).get_object('chatRequest').get_array('tools');
    ut.expect(item(l_tools, 0).has('parameters'), 'oci cohere: no parameters key').to_be_false();
    ut.expect(item(l_tools, 0).get_object('parameterDefinitions').get_size, 'oci cohere: both parameters').to_equal(2);

    test_uc_ai_wire.expect_all_consumed(8);
  end flat_schema_reaches_every_provider;


  procedure cohere_flat_parameter_definitions
  as
    l_result json_object_t;
    l_defs   json_object_t;
  begin
    register_flat_tool;
    enqueue(cohere_text('ok'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere_model
    , p_config      => oci_config
    );

    -- CohereTool.parameterDefinitions is a map of name -> {type, description,
    -- isRequired}. A flat schema used to arrive as {} - the model was told the
    -- tool takes no arguments and could not fill any.
    l_defs := item(request_json(1).get_object('chatRequest').get_array('tools'), 0).get_object('parameterDefinitions');

    ut.expect(l_defs.get_size, 'both parameters declared').to_equal(2);
    ut.expect(l_defs.get_object('city').get_string('type')).to_equal('string');
    ut.expect(l_defs.get_object('city').get_string('description')).to_equal('City name');
    ut.expect(l_defs.get_object('city').get_boolean('isRequired'), 'city is required').to_be_true();
    ut.expect(l_defs.get_object('unit').get_string('type')).to_equal('string');
    ut.expect(l_defs.get_object('unit').get_boolean('isRequired'), 'unit is optional').to_be_false();

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('ok'));
    test_uc_ai_wire.expect_all_consumed(1);
  end cohere_flat_parameter_definitions;


  procedure legacy_wrapper_schema_still_works
  as
    l_result  json_object_t;
    l_defs    json_object_t;
    l_params  json_object_t;
  begin
    register_wrapped_tool;
    enqueue(cohere_text('ok'));
    enqueue(test_uc_ai_wire_2.oci_generic_text('ok'));

    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_oci, p_model => c_cohere_model, p_config => oci_config);
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_oci, p_model => c_llama_model,  p_config => oci_config);

    -- COHERE: descend exactly one level into the single object property, which is
    -- what the recorded TT_CLOCK_IN fixture expects
    l_defs := item(request_json(1).get_object('chatRequest').get_array('tools'), 0).get_object('parameterDefinitions');
    ut.expect(l_defs.get_size, 'wrapper flattened to its two parameters').to_equal(2);
    ut.expect(l_defs.get_object('city').get_boolean('isRequired'), 'city is required').to_be_true();
    ut.expect(l_defs.get_object('unit').get_boolean('isRequired'), 'unit is optional').to_be_false();
    ut.expect(l_defs.has('parameters'), 'the wrapper itself is not a parameter').to_be_false();

    -- GENERIC keeps the JSON schema as it is, wrapper and all
    l_params := item(request_json(2).get_object('chatRequest').get_array('tools'), 0).get_object('parameters');
    ut.expect(l_params.get_object('properties').get_size, 'one top-level property').to_equal(1);
    ut.expect(l_params.get_object('properties').get_object('parameters').get_object('properties').get_size, 'two inner properties').to_equal(2);

    test_uc_ai_wire.expect_all_consumed(2);
  end legacy_wrapper_schema_still_works;


  procedure cohere_no_parameter_tool
  as
    l_result json_object_t;
  begin
    register_tool(c_no_args, '{"type":"object","properties":{}}', 'return ''done'';');
    enqueue(cohere_text('ok'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_cohere_model
    , p_config      => oci_config
    );

    ut.expect(
      item(request_json(1).get_object('chatRequest').get_array('tools'), 0).get_object('parameterDefinitions').get_size
    , 'a tool without parameters declares none'
    ).to_equal(0);

    test_uc_ai_wire.expect_all_consumed(1);
  end cohere_no_parameter_tool;


  procedure schema_keywords_left_out_where_rejected
  as
    l_result json_object_t;
    l_schema json_object_t;
  begin
    register_flat_tool;
    enqueue(test_uc_ai_wire_2.chat_completion('ok'));
    enqueue(test_uc_ai_wire_2.google_candidate(json_array_t('[{"text":"ok"}]')));
    enqueue(test_uc_ai_wire_2.oci_generic_text('ok'));

    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_openai, p_model => 'gpt-4o-mini',    p_config => chat_config);
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_google, p_model => 'gemini-2.5-flash', p_config => config);
    l_result := uc_ai.generate_text(p_user_prompt => c_prompt, p_provider => uc_ai.c_provider_oci,    p_model => c_llama_model,    p_config => oci_config);

    -- OpenAI ignores both keywords, so they stay
    l_schema := item(request_json(1).get_array('tools'), 0).get_object('function').get_object('parameters');
    ut.expect(l_schema.has('$schema'), 'openai keeps $schema').to_be_true();
    ut.expect(l_schema.has('additionalProperties'), 'openai keeps additionalProperties').to_be_true();

    -- Google answers HTTP 400 "Unknown name" for either of them
    l_schema := item(item(request_json(2).get_array('tools'), 0).get_array('functionDeclarations'), 0).get_object('parameters');
    ut.expect(l_schema.has('$schema'), 'google gets no $schema').to_be_false();
    ut.expect(l_schema.has('additionalProperties'), 'google gets no additionalProperties').to_be_false();

    -- OCI GENERIC forwards `parameters` to the model's own vendor, so a google.*
    -- model on OCI produced exactly that 400 until both were dropped here too
    l_schema := item(request_json(3).get_object('chatRequest').get_array('tools'), 0).get_object('parameters');
    ut.expect(l_schema.has('$schema'), 'oci gets no $schema').to_be_false();
    ut.expect(l_schema.has('additionalProperties'), 'oci gets no additionalProperties').to_be_false();

    test_uc_ai_wire.expect_all_consumed(3);
  end schema_keywords_left_out_where_rejected;


  -- ---- tool arguments ----------------------------------------------------------

  procedure wrapped_arguments_arrive_flat
  as
    l_result json_object_t;
  begin
    register_wrapped_tool;

    -- OpenAI Chat Completions: the model answers with the wrapper it was shown
    enqueue(test_uc_ai_wire_2.chat_tool_call('call_1', c_wrapped, '{"parameters":{"city":"Paris","unit":"c"}}'));
    enqueue(test_uc_ai_wire_2.chat_completion('It is 21 degrees in Paris.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => chat_config
    );

    ut.expect(g_last_args.has('parameters'), 'openai chat: wrapper removed').to_be_false();
    ut.expect(g_last_args.get_string('city'), 'openai chat: city').to_equal('Paris');
    ut.expect(g_last_args.get_string('unit'), 'openai chat: unit').to_equal('c');
    ut.expect(g_last_args.has(uc_ai.c_run_context_key), 'openai chat: run context still at the top level').to_be_true();

    -- Ollama, the same wrapper, the native route
    g_last_args := null;
    enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t(
      '{"role":"assistant","content":"","tool_calls":[{"function":{"name":"' || c_wrapped
      || '","arguments":{"parameters":{"city":"Berlin","unit":"c"}}}}]}')));
    enqueue(test_uc_ai_wire_2.ollama_chat(json_object_t('{"role":"assistant","content":"It is 21 degrees."}')));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => 'qwen3.5:9b'
    , p_config      => config('{"ollama":{"g_use_responses_api":false}}')
    );

    ut.expect(g_last_args.has('parameters'), 'ollama: wrapper removed').to_be_false();
    ut.expect(g_last_args.get_string('city'), 'ollama: city').to_equal('Berlin');

    -- OCI GENERIC, the same wrapper again
    g_last_args := null;
    enqueue(generic_tool_call(c_wrapped, '{"parameters":{"city":"Rome","unit":"c"}}'));
    enqueue(test_uc_ai_wire_2.oci_generic_text('It is 21 degrees.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_llama_model
    , p_config      => oci_config
    );

    ut.expect(g_last_args.has('parameters'), 'oci generic: wrapper removed').to_be_false();
    ut.expect(g_last_args.get_string('city'), 'oci generic: city').to_equal('Rome');

    test_uc_ai_wire.expect_all_consumed(6);
  end wrapped_arguments_arrive_flat;


  procedure unwrap_is_idempotent
  as
    l_result json_object_t;
    l_answer clob;
  begin
    register_wrapped_tool;

    -- Anthropic strips the wrapper itself before it calls the tools layer. The
    -- layer must not strip a second time, which would hand the handler the value
    -- of `city` or nothing at all.
    enqueue(test_uc_ai_wire_2.anthropic_message(
      json_array_t('[{"type":"tool_use","id":"toolu_1","name":"' || c_wrapped
        || '","input":{"parameters":{"city":"Paris","unit":"c"}}}]')
    , 'tool_use'));
    enqueue(test_uc_ai_wire_2.anthropic_message(json_array_t('[{"type":"text","text":"It is 21 degrees."}]')));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_anthropic
    , p_model       => 'claude-haiku-4-5'
    , p_config      => config
    );

    ut.expect(g_last_args.get_string('city'), 'anthropic: city survived the second pass').to_equal('Paris');
    ut.expect(g_last_args.get_string('unit'), 'anthropic: unit survived the second pass').to_equal('c');

    -- The same call made directly, with a payload that is already flat
    l_answer := uc_ai_tools_api.execute_tool(
      p_tool_code => c_wrapped
    , p_arguments => json_object_t('{"city":"Lisbon","unit":"c"}')
    );
    ut.expect(l_answer, 'the handler answered').to_be_not_null();
    ut.expect(g_last_args.get_string('city'), 'direct call: flat payload untouched').to_equal('Lisbon');

    test_uc_ai_wire.expect_all_consumed(2);
  end unwrap_is_idempotent;


  /*
   * Builds a JSON argument text well over the 32767-byte varchar2 limit:
   * {"blob":"xxx...x"} with 42767 x characters.
   */
  function big_arguments return clob
  as
    l_filler clob;
  begin
    l_filler := to_clob(rpad('x', 32000, 'x')) || to_clob(rpad('x', 10767, 'x'));
    return to_clob('{"blob":"') || l_filler || to_clob('"}');
  end big_arguments;


  procedure large_arguments_reach_the_handler
  as
    l_result   json_object_t;
    l_args     clob := big_arguments;
    l_body     clob;
    l_expected pls_integer := 42767;
  begin
    register_tool(
      c_big
    , '{"type":"object","properties":{"blob":{"type":"string","description":"A large payload"}},"required":["blob"]}'
    , 'return test_uc_ai_tools_wire.args_length(:args);'
    );

    -- Hand-built, because the arguments have to be a CLOB: the tool call the model
    -- makes carries the whole payload as a JSON string
    l_body := to_clob('{"id":"chatcmpl-big","object":"chat.completion","model":"gpt-4o-mini",'
      || '"choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":'
      || '[{"id":"call_big","type":"function","function":{"name":"' || c_big || '","arguments":"')
      || replace(l_args, '"', '\"')
      || to_clob('"}}]},"finish_reason":"tool_calls"}],'
      || '"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}');

    enqueue(l_body);
    enqueue(test_uc_ai_wire_2.chat_completion('Got it.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => chat_config
    );

    -- the handler saw every byte: apex_plugin_util.t_bind.value is a
    -- varchar2(32767), so this only works when the bind is a CLOB
    ut.expect(sys.dbms_lob.getlength(g_last_args.get_clob('blob')), 'payload length at the handler').to_equal(l_expected);
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(1);
    test_uc_ai_wire.expect_all_consumed(2);
  end large_arguments_reach_the_handler;


  procedure large_arguments_through_execute_tool
  as
    l_reported clob;
    l_args     json_object_t := json_object_t(big_arguments);
  begin
    register_tool(
      c_big
    , '{"type":"object","properties":{"blob":{"type":"string","description":"A large payload"}},"required":["blob"]}'
    , 'return test_uc_ai_tools_wire.args_length(:args);'
    );

    l_reported := uc_ai_tools_api.execute_tool(
      p_tool_code => c_big
    , p_arguments => l_args
    );

    -- the handler reports the length it was given, so a truncated bind cannot pass
    ut.expect(to_number(l_reported), 'payload length reported by the handler').to_equal(42767);
    test_uc_ai_wire.expect_all_consumed(0);
  end large_arguments_through_execute_tool;


  /*
   * The same payload through the OTHER branch of exec_function_call.
   *
   * exec_function_call picks its branch on apex_application.g_instance alone, so
   * setting it is enough to take the APEX branch - and no APEX session has to be
   * created, which would commit and leave the suite unable to roll itself back.
   * The branch cannot carry this payload through apex_plugin_util at all
   * (t_bind.value is a varchar2(32767)); it has to fall back to DBMS_SQL instead
   * of raising ORA-06502.
   */
  procedure large_arguments_on_the_apex_branch
  as
    l_reported clob;
    l_args     json_object_t := json_object_t(big_arguments);
  begin
    register_tool(
      c_big
    , '{"type":"object","properties":{"blob":{"type":"string","description":"A large payload"}},"required":["blob"]}'
    , 'return test_uc_ai_tools_wire.args_length(:args);'
    );

    apex_application.g_instance := -1;

    begin
      l_reported := uc_ai_tools_api.execute_tool(
        p_tool_code => c_big
      , p_arguments => l_args
      );
      apex_application.g_instance := null;
    exception
      when others then
        apex_application.g_instance := null;
        raise;
    end;

    ut.expect(to_number(l_reported), 'payload length reported by the handler').to_equal(42767);
    test_uc_ai_wire.expect_all_consumed(0);
  end large_arguments_on_the_apex_branch;


  -- ---- parameter lookup ------------------------------------------------------------

  procedure two_top_level_params_no_error
  as
    l_result json_object_t;
    l_name   uc_ai_tool_parameters.name%type;
  begin
    -- Two top-level parameters, one of them an object. The count used to look at
    -- object-typed rows only, so it found exactly one and then selected BOTH
    -- top-level rows: TOO_MANY_ROWS, re-raised out of the middle of a tool call.
    register_tool(
      c_mixed
    , '{"type":"object","properties":{'
      || '"payload":{"type":"object","description":"Wrapper","properties":{"q":{"type":"string","description":"Anything"}}},'
      || '"mode":{"type":"string","description":"Mode"}},"required":["mode"]}'
    , 'return test_uc_ai_tools_wire.capture_args(:args);'
    );

    l_name := uc_ai_tools_api.get_tools_object_param_name(c_mixed);
    ut.expect(l_name, 'a two-parameter tool has no wrapper').to_be_null();

    -- and the run goes through: both parameters reach the handler unchanged
    enqueue(test_uc_ai_wire_2.chat_tool_call('call_1', c_mixed, '{"payload":{"q":"x"},"mode":"fast"}'));
    enqueue(test_uc_ai_wire_2.chat_completion('Done.'));

    l_result := uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => 'gpt-4o-mini'
    , p_config      => chat_config
    );

    ut.expect(g_last_args.get_object('payload').get_string('q'), 'object parameter kept').to_equal('x');
    ut.expect(g_last_args.get_string('mode'), 'sibling parameter kept').to_equal('fast');
    test_uc_ai_wire.expect_all_consumed(2);
  end two_top_level_params_no_error;

end test_uc_ai_tools_wire;
/
