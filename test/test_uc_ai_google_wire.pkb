create or replace package body test_uc_ai_google_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on it; a backtrace adds nothing

  c_model_25    constant uc_ai.model_type := uc_ai_google.c_model_gemini_2_5_flash;
  c_model_3     constant uc_ai.model_type := uc_ai_google.c_model_gemini_3_flash;
  -- A model id no release of this package knows. It must get the current request
  -- shape, not the legacy one: Google keeps shipping ids faster than this list.
  c_model_next  constant uc_ai.model_type := 'gemini-4.0-flash';

  c_prompt      constant varchar2(200 char) := 'What is the capital of France?';
  c_users_prompt constant varchar2(200 char) := 'What is the email address of Jim?';

  -- Prefixed so this suite cannot collide with the tool rows of another suite.
  c_tool_code   constant uc_ai_tools.code%type := 'WIRE_B_GET_USERS';
  c_tool_tag    constant varchar2(30 char) := 'wire_b_google';


  -- ---- helpers -----------------------------------------------------------------

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


  function recorded_users return clob
  as
  begin
    return '[{"name":"Jim","email":"jim.halpert@dundermifflin.com"}]';
  end recorded_users;


  /*
   * generationConfig.thinkingConfig of the p_index-th request, or null when the
   * request carried no generation config at all.
   */
  function thinking_config_of(p_index in pls_integer) return json_object_t
  as
    l_body json_object_t := uc_ai_test_http_mock.request_json(p_index);
  begin
    if not l_body.has('generationConfig') then
      return null;
    end if;

    return l_body.get_object('generationConfig').get_object('thinkingConfig');
  end thinking_config_of;


  /*
   * The content array of the first assistant message of a result.
   */
  function assistant_content_of(p_result in json_object_t) return json_array_t
  as
    l_messages json_array_t := test_uc_ai_wire.messages_of(p_result);
    l_message  json_object_t;
  begin
    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_message := treat(l_messages.get(i) as json_object_t);
      if l_message.get_string('role') = 'assistant' then
        return treat(l_message.get('content') as json_array_t);
      end if;
    end loop message_loop;

    return null;
  end assistant_content_of;


  /*
   * A tool with no parameters that answers with a fixed result, tagged so only
   * this suite offers it. The row is rolled back with the test.
   */
  procedure register_users_tool
  as
    l_tool_id uc_ai_tools.id%type;
  begin
    delete from uc_ai_tools where code = c_tool_code;

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => c_tool_code
    , p_description   => 'Get information on all the users in the system'
    , p_function_call => 'return test_uc_ai_google_wire.recorded_users;'
    , p_json_schema   => json_object_t('{"type":"object","properties":{}}')
    , p_tags          => apex_t_varchar2(c_tool_tag)
    );

    ut.expect(l_tool_id, 'tool registered').to_be_not_null();
  end register_users_tool;


  function google_config(p_json in varchar2 default '{}') return json_object_t
  as
  begin
    return test_uc_ai_wire.config(p_json);
  end google_config;


  function generate(
    p_model  in uc_ai.model_type
  , p_config in json_object_t
  ) return json_object_t
  as
  begin
    return uc_ai.generate_text(
      p_user_prompt => c_prompt
    , p_provider    => uc_ai.c_provider_google
    , p_model       => p_model
    , p_config      => p_config
    );
  end generate;


  -- ---- B3: 200 bodies without a usable candidate --------------------------------

  procedure prompt_block_returns_content_filter
  as
    l_result json_object_t;
  begin
    -- Google refuses the prompt itself with HTTP 200 and no candidates key at
    -- all. Reading candidates unguarded raised ORA-30625 here.
    uc_ai_test_http_mock.enqueue('{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT","safetyRatings":[]},'
      || '"usageMetadata":{"promptTokenCount":9,"totalTokenCount":9}}');

    l_result := generate(c_model_25, google_config);

    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_content_filter);
    ut.expect(l_result.get_string('block_reason'), 'block_reason').to_equal('PROHIBITED_CONTENT');
    ut.expect(l_result.get_clob('final_message'), 'final_message').to_be_null();
    -- only the user message: the model said nothing
    ut.expect(test_uc_ai_wire.messages_of(l_result).get_size, 'messages').to_equal(1);
    test_uc_ai_wire.expect_usage(l_result, 9, 0, 9);
    test_uc_ai_wire.expect_all_consumed(1);
  end prompt_block_returns_content_filter;


  procedure no_candidates_and_no_reason_raises
  as
    l_result json_object_t;
    l_raised boolean := false;
  begin
    -- No candidates and nothing that explains why: that body is not a Gemini
    -- response, so it stays an error - but a documented one, not an ORA-30625.
    uc_ai_test_http_mock.enqueue('{"candidates":[],"usageMetadata":{"promptTokenCount":9,"totalTokenCount":9}}');

    begin
      l_result := generate(c_model_25, google_config);
    exception
      when uc_ai.e_error_response then
        l_raised := true;
    end;

    ut.expect(l_raised, 'raised -20302').to_be_true();
    test_uc_ai_wire.expect_all_consumed(1);
  end no_candidates_and_no_reason_raises;


  procedure candidate_with_empty_content
  as
    l_result json_object_t;
  begin
    -- MALFORMED_FUNCTION_CALL: the candidate is there, its content is not.
    uc_ai_test_http_mock.enqueue('{"candidates":[{"content":{},"finishReason":"MALFORMED_FUNCTION_CALL","index":0}],'
      || '"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":0,"totalTokenCount":12},'
      || '"modelVersion":"gemini-2.5-flash"}');

    l_result := generate(c_model_25, google_config);

    -- unmapped Google reasons are passed through unchanged
    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal('MALFORMED_FUNCTION_CALL');
    ut.expect(l_result.get_clob('final_message'), 'final_message').to_be_null();
    ut.expect(test_uc_ai_wire.messages_of(l_result).get_size, 'messages').to_equal(1);
    test_uc_ai_wire.expect_all_consumed(1);
  end candidate_with_empty_content;


  procedure candidate_without_content_key
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue('{"candidates":[{"finishReason":"SAFETY","index":0}],'
      || '"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":0,"totalTokenCount":12},'
      || '"modelVersion":"gemini-2.5-flash"}');

    l_result := generate(c_model_25, google_config);

    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_content_filter);
    ut.expect(l_result.get_clob('final_message'), 'final_message').to_be_null();
    test_uc_ai_wire.expect_all_consumed(1);
  end candidate_without_content_key;


  procedure max_tokens_spent_on_thinking
  as
    l_result json_object_t;
  begin
    -- The whole output budget went into thinking, so the candidate ends without
    -- content. The finish reason is the entire answer.
    uc_ai_test_http_mock.enqueue('{"candidates":[{"finishReason":"MAX_TOKENS","index":0}],'
      || '"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":0,"thoughtsTokenCount":500,"totalTokenCount":520},'
      || '"modelVersion":"gemini-3-flash-preview"}');

    l_result := generate(c_model_3, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"high"}'));

    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_length);
    ut.expect(l_result.get_clob('final_message'), 'final_message').to_be_null();
    test_uc_ai_wire.expect_usage(l_result, 20, 0, 520, 500);
    test_uc_ai_wire.expect_all_consumed(1);
  end max_tokens_spent_on_thinking;


  procedure embeddings_without_array_raises
  as
    l_embeddings json_array_t;
    l_raised     boolean := false;
  begin
    uc_ai_test_http_mock.enqueue('{"model":"models/gemini-embedding-001"}');

    begin
      l_embeddings := uc_ai.generate_embeddings(
        p_input    => json_array_t('["hello"]')
      , p_provider => uc_ai.c_provider_google
      , p_model    => uc_ai_google.c_model_gemini_embedding_001
      , p_config   => google_config
      );
    exception
      when uc_ai.e_error_response then
        l_raised := true;
    end;

    ut.expect(l_raised, 'raised -20302').to_be_true();
    ut.expect(l_embeddings is null, 'nothing was returned').to_be_true();
    test_uc_ai_wire.expect_all_consumed(1);
  end embeddings_without_array_raises;


  -- ---- B16: final_message accumulation ------------------------------------------

  procedure all_text_parts_reach_final_message
  as
    l_result  json_object_t;
    l_content json_array_t;
    l_last    json_object_t;
  begin
    -- One answer split over two visible text parts, a thought part between them,
    -- and the trailing zero-length part Gemini 3 uses to hand back a signature.
    uc_ai_test_http_mock.enqueue('{"candidates":[{"content":{"role":"model","parts":['
      || '{"text":"The capital of France "},'
      || '{"text":"Checking which city is the seat of government.","thought":true},'
      || '{"text":"is Paris."},'
      || '{"text":"","thoughtSignature":"Ct4BAcu98signature"}'
      || ']},"finishReason":"STOP","index":0}],'
      || '"usageMetadata":{"promptTokenCount":11,"candidatesTokenCount":7,"thoughtsTokenCount":31,"totalTokenCount":49},'
      || '"modelVersion":"gemini-3-flash-preview"}');

    l_result := generate(c_model_3, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"low"}'));

    -- both visible parts, in order, and nothing else
    ut.expect(l_result.get_clob('final_message'), 'final_message').to_equal(to_clob('The capital of France is Paris.'));

    l_content := assistant_content_of(l_result);
    ut.expect(l_content.get_size, 'text, reasoning, text, signature').to_equal(4);

    -- the zero-length part keeps its signature and adds no empty text item
    l_last := treat(l_content.get(3) as json_object_t);
    ut.expect(l_last.get_string('type'), 'last content type').to_equal('reasoning');
    ut.expect(l_last.has('text'), 'signature part carries no text').to_be_false();
    ut.expect(treat(l_last.get('providerOptions') as json_object_t).get_string('thoughtSignature'), 'thoughtSignature')
      .to_equal('Ct4BAcu98signature');

    test_uc_ai_wire.expect_all_consumed(1);
  end all_text_parts_reach_final_message;


  procedure final_turn_without_text_clears_it
  as
    l_result json_object_t;
    l_parts  json_array_t;
  begin
    register_users_tool;

    -- turn 1 says something and calls a tool
    uc_ai_test_http_mock.enqueue('{"candidates":[{"content":{"role":"model","parts":['
      || '{"text":"Let me look that up."},'
      || '{"functionCall":{"name":"WIRE_B_GET_USERS","args":{}}}'
      || ']},"finishReason":"STOP","index":0}],'
      || '"usageMetadata":{"promptTokenCount":30,"candidatesTokenCount":8,"totalTokenCount":38},'
      || '"modelVersion":"gemini-2.5-flash"}');

    -- turn 2 answers with nothing at all
    uc_ai_test_http_mock.enqueue('{"candidates":[{"finishReason":"MAX_TOKENS","index":0}],'
      || '"usageMetadata":{"promptTokenCount":90,"candidatesTokenCount":0,"thoughtsTokenCount":120,"totalTokenCount":210},'
      || '"modelVersion":"gemini-2.5-flash"}');

    l_result := uc_ai.generate_text(
      p_user_prompt => c_users_prompt
    , p_provider    => uc_ai.c_provider_google
    , p_model       => c_model_25
    , p_config      => google_config('{"g_enable_tools":true,"g_tool_tags":["wire_b_google"]}')
    );

    -- the second request answered the tool call
    l_parts := treat(uc_ai_test_http_mock.request_json(2).get_array('contents').get(2) as json_object_t).get_array('parts');
    ut.expect(treat(l_parts.get(0) as json_object_t).get_object('functionResponse').get_string('name'), 'tool answered')
      .to_equal(c_tool_code);

    ut.expect(l_result.get_number('tool_calls_count'), 'tool_calls_count').to_equal(1);
    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_length);
    -- the text of turn 1 is not the answer of turn 2
    ut.expect(l_result.get_clob('final_message'), 'final_message').to_be_null();
    test_uc_ai_wire.expect_all_consumed(2);
  end final_turn_without_text_clears_it;


  -- ---- B17: reasoning parameter per model generation -----------------------------

  procedure gemini3_sends_thinking_level
  as
    l_result   json_object_t;
    l_thinking json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));

    l_result := generate(c_model_3, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"high"}'));

    l_thinking := thinking_config_of(1);
    ut.expect(l_thinking.get_string('thinkingLevel'), 'thinkingLevel').to_equal('high');
    ut.expect(l_thinking.has('thinkingBudget'), 'no thinkingBudget on gemini-3').to_be_false();
    ut.expect(l_thinking.get_boolean('includeThoughts'), 'includeThoughts').to_be_true();
    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(1);
  end gemini3_sends_thinking_level;


  procedure gemini25_sends_thinking_budget
  as
    l_result   json_object_t;
    l_thinking json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));

    l_result := generate(c_model_25, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"medium"}'));

    l_thinking := thinking_config_of(1);
    ut.expect(l_thinking.get_number('thinkingBudget'), 'thinkingBudget').to_equal(8192);
    ut.expect(l_thinking.has('thinkingLevel'), 'no thinkingLevel on gemini-2.5').to_be_false();
    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(1);
  end gemini25_sends_thinking_budget;


  procedure unknown_model_uses_thinking_level
  as
    l_result   json_object_t;
    l_thinking json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));

    l_result := generate(c_model_next, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"low"}'));

    l_thinking := thinking_config_of(1);
    ut.expect(l_thinking.get_string('thinkingLevel'), 'thinkingLevel').to_equal('low');
    ut.expect(l_thinking.has('thinkingBudget'), 'no thinkingBudget').to_be_false();
    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(1);
  end unknown_model_uses_thinking_level;


  procedure explicit_budget_is_sent_verbatim
  as
    l_result   json_object_t;
    l_thinking json_object_t;
  begin
    -- go_reasoning_budget names an exact number of thinking tokens. Google still
    -- accepts and honours thinkingBudget on Gemini 3 (measured against the live
    -- API), so the number is sent unchanged rather than translated into a level.
    -- Both keys in one request is an HTTP 400, so only one is ever sent.
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));

    -- zero, the way "think as little as possible" is expressed
    l_result := generate(c_model_3, google_config('{"g_enable_reasoning":true,"google":{"g_reasoning_budget":0}}'));
    l_thinking := thinking_config_of(1);
    ut.expect(l_thinking.get_number('thinkingBudget'), 'gemini-3 budget 0').to_equal(0);
    ut.expect(l_thinking.has('thinkingLevel'), 'gemini-3 sends no level next to a budget').to_be_false();

    -- an explicit budget wins over the level, on Gemini 3 as on gemini-2.5
    l_result := generate(c_model_3
                       , google_config('{"g_enable_reasoning":true,"g_reasoning_level":"high","google":{"g_reasoning_budget":4096}}'));
    l_thinking := thinking_config_of(2);
    ut.expect(l_thinking.get_number('thinkingBudget'), 'explicit budget wins').to_equal(4096);
    ut.expect(l_thinking.has('thinkingLevel'), 'never both keys at once').to_be_false();

    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(2);
  end explicit_budget_is_sent_verbatim;


  procedure unknown_reasoning_level_is_dropped
  as
    l_result   json_object_t;
    l_thinking json_object_t;
  begin
    -- Both branches used to assign a string to a numeric CASE and raise
    -- ORA-06502. An unknown level now sends no depth at all.
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('google/1-simple-response'));

    l_result := generate(c_model_3, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"ultra"}'));
    l_thinking := thinking_config_of(1);
    ut.expect(l_thinking.get_boolean('includeThoughts'), 'gemini-3 includeThoughts').to_be_true();
    ut.expect(l_thinking.has('thinkingLevel'), 'gemini-3 no level').to_be_false();
    ut.expect(l_thinking.has('thinkingBudget'), 'gemini-3 no budget').to_be_false();

    l_result := generate(c_model_25, google_config('{"g_enable_reasoning":true,"g_reasoning_level":"ultra"}'));
    l_thinking := thinking_config_of(2);
    ut.expect(l_thinking.get_boolean('includeThoughts'), 'gemini-2.5 includeThoughts').to_be_true();
    ut.expect(l_thinking.has('thinkingLevel'), 'gemini-2.5 no level').to_be_false();
    ut.expect(l_thinking.has('thinkingBudget'), 'gemini-2.5 no budget').to_be_false();

    ut.expect(l_result.get_string('finish_reason'), 'finish_reason').to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(2);
  end unknown_reasoning_level_is_dropped;

end test_uc_ai_google_wire;
/
