create or replace package body test_uc_ai_reasoning_replay_e2e as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  -- Recall rather than arithmetic: the follow-up answer has to prove the replayed
  -- history was actually used, without depending on the model getting a sum right
  -- (gpt-5-mini reliably accepted the replay but miscalculated 17*23*2).
  c_turn_1_prompt constant varchar2(200 char) := 'Remember this number: 782. Reply with just: OK';
  c_turn_2_prompt constant varchar2(200 char) := 'What number did I ask you to remember? Reply with just the number.';

  c_ollama_model          constant uc_ai.model_type    := 'gemma4:26b';
  c_ollama_base_url       constant varchar2(255 char)  := 'https://ai.united-codes.com/api';
  c_ollama_web_credential constant varchar2(255 char)  := 'OLLAMA';


  /*
   * Counts reasoning content items across all assistant messages of a result.
   *
   * Asserted to be > 0 in every test below: if the provider stops returning
   * reasoning, these tests would otherwise keep passing while no longer
   * exercising the replay path at all.
   */
  function count_reasoning_items(
    p_result in json_object_t
  ) return pls_integer
  as
    l_messages json_array_t := treat(p_result.get('messages') as json_array_t);
    l_message  json_object_t;
    l_content  json_array_t;
    l_count    pls_integer := 0;
  begin
    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1
    loop
      l_message := treat(l_messages.get(i) as json_object_t);

      continue when l_message.get_string('role') != 'assistant' or not l_message.has('content');

      l_content := treat(l_message.get('content') as json_array_t);

      <<content_loop>>
      for j in 0 .. l_content.get_size - 1
      loop
        if treat(l_content.get(j) as json_object_t).get_string('type') = 'reasoning' then
          l_count := l_count + 1;
        end if;
      end loop content_loop;
    end loop message_loop;

    return l_count;
  end count_reasoning_items;


  /*
   * The returned history plus a follow-up user message - the exact array a
   * conversation continuation feeds back into generate_text.
   */
  function with_follow_up(
    p_result in json_object_t
  , p_text   in clob
  ) return json_array_t
  as
    l_messages json_array_t := treat(p_result.get('messages') as json_array_t);
    l_content  json_array_t := json_array_t();
  begin
    l_content.append(uc_ai_message_api.create_text_content(p_text));
    l_messages.append(uc_ai_message_api.create_user_message(l_content));

    return l_messages;
  end with_follow_up;


  procedure assert_round_trip(
    p_result    in json_object_t
  , p_provider  in varchar2
  )
  as
    l_final_message clob := p_result.get_clob('final_message');
  begin
    sys.dbms_output.put_line(p_provider || ' follow-up answer: ' || substr(l_final_message, 1, 200));

    ut.expect(l_final_message, p_provider || ': follow-up turn must produce an answer').to_be_not_null();
    -- Reaching this at all means the provider ACCEPTED the replayed reasoning
    -- items (the production failure was an HTTP 400 on this second call). The
    -- recalled number then proves the history was really carried across.
    ut.expect(l_final_message, p_provider || ': follow-up turn must see the first turn''s context').to_be_like('%782%');
  end assert_round_trip;


  procedure setup_tests
  as
  begin
    -- reset_globals is not automatic between tests; leftover provider settings
    -- would otherwise leak into (or out of) these runs.
    uc_ai.reset_globals;
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := true;
  end setup_tests;


  procedure reset_globals
  as
  begin
    uc_ai.reset_globals;
  end reset_globals;


  procedure openai_responses_roundtrip
  as
    l_result json_object_t;
  begin
    -- The exact configuration that failed in production: reasoning on, summaries
    -- OFF and store=false, so the reasoning item carries only an rs_... id plus
    -- encrypted_content and no summary text. Replaying it without a 'summary'
    -- key produced: Missing required parameter: 'input[N].summary'.
    uc_ai_openai.g_use_responses_api := true;
    uc_ai_responses_api.g_reasoning_effort := 'low';
    uc_ai_responses_api.g_reasoning_summary := null;
    uc_ai_responses_api.g_store_responses := false;
    uc_ai_responses_api.g_include_encrypted_reasoning := true;

    l_result := uc_ai.generate_text(
      p_user_prompt => c_turn_1_prompt
    , p_provider    => uc_ai.c_provider_openai
    , p_model       => uc_ai_openai.c_model_gpt_5_mini
    );

    ut.expect(count_reasoning_items(l_result),
              'OpenAI: turn 1 must return a reasoning item, otherwise this test is not exercising replay')
      .to_be_greater_than(0);

    l_result := uc_ai.generate_text(
      p_messages => with_follow_up(l_result, c_turn_2_prompt)
    , p_provider => uc_ai.c_provider_openai
    , p_model    => uc_ai_openai.c_model_gpt_5_mini
    );

    assert_round_trip(l_result, 'OpenAI Responses');
  end openai_responses_roundtrip;


  procedure anthropic_thinking_roundtrip
  as
    l_result json_object_t;
  begin
    -- Confirms Anthropic accepts a replayed thinking block: sent back unmodified,
    -- signature included, ordered first in the content array.
    uc_ai_anthropic.g_reasoning_budget_tokens := 1024;

    l_result := uc_ai.generate_text(
      p_user_prompt => c_turn_1_prompt
    , p_provider    => uc_ai.c_provider_anthropic
    , p_model       => uc_ai_anthropic.c_model_claude_4_5_haiku
    );

    ut.expect(count_reasoning_items(l_result),
              'Anthropic: turn 1 must return a thinking block, otherwise this test is not exercising replay')
      .to_be_greater_than(0);

    l_result := uc_ai.generate_text(
      p_messages => with_follow_up(l_result, c_turn_2_prompt)
    , p_provider => uc_ai.c_provider_anthropic
    , p_model    => uc_ai_anthropic.c_model_claude_4_5_haiku
    );

    assert_round_trip(l_result, 'Anthropic');
  end anthropic_thinking_roundtrip;


  procedure anthropic_thinking_tool_roundtrip
  as
    l_result json_object_t;
    l_messages json_array_t;
    l_content json_array_t := json_array_t();
  begin
    -- The full agent shape: reasoning + tool call, then a follow-up turn that
    -- replays all of it. This is an ACCEPTANCE test, not a regression guard -
    -- measured against claude-haiku-4-5, Anthropic also accepts this turn with the
    -- thinking block stripped (the old behaviour). What it pins down is that the
    -- block we now send back - signature included, ordered ahead of the tool_use -
    -- is accepted rather than rejected.
    delete from UC_AI_TOOL_PARAMETERS where 1 = 1;
    delete from UC_AI_TOOLS where 1 = 1;
    uc_ai_test_utils.add_get_users_tool;

    uc_ai.g_enable_tools := true;
    uc_ai_anthropic.g_reasoning_budget_tokens := 1024;

    l_result := uc_ai.generate_text(
      p_user_prompt   => 'What is the email address of Jim? Use your tools.'
    , p_system_prompt => 'You are an assistant to a time tracking system. Answer concise and short.'
    , p_provider      => uc_ai.c_provider_anthropic
    , p_model         => uc_ai_anthropic.c_model_claude_4_5_haiku
    );

    ut.expect(count_reasoning_items(l_result),
              'Anthropic: turn 1 must return a thinking block, otherwise this test is not exercising replay')
      .to_be_greater_than(0);
    ut.expect(l_result.get_number('tool_calls_count'),
              'Anthropic: turn 1 must make a tool call, otherwise the mandatory-signature path is untested')
      .to_be_greater_than(0);

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_content.append(uc_ai_message_api.create_text_content('And what is her or his hire date?'));
    l_messages.append(uc_ai_message_api.create_user_message(l_content));

    l_result := uc_ai.generate_text(
      p_messages => l_messages
    , p_provider => uc_ai.c_provider_anthropic
    , p_model    => uc_ai_anthropic.c_model_claude_4_5_haiku
    );

    -- Reaching here means Anthropic accepted a replayed tool_use turn whose
    -- thinking block was preserved and correctly ordered.
    sys.dbms_output.put_line('Anthropic tool follow-up: ' || substr(l_result.get_clob('final_message'), 1, 200));
    ut.expect(l_result.get_clob('final_message'),
              'Anthropic: follow-up after a tool call must produce an answer').to_be_not_null();
  end anthropic_thinking_tool_roundtrip;


  procedure google_thought_roundtrip
  as
    l_result json_object_t;
  begin
    l_result := uc_ai.generate_text(
      p_user_prompt => c_turn_1_prompt
    , p_provider    => uc_ai.c_provider_google
    , p_model       => uc_ai_google.c_model_gemini_2_5_flash
    );

    ut.expect(count_reasoning_items(l_result),
              'Google: turn 1 must return a thought part, otherwise this test is not exercising replay')
      .to_be_greater_than(0);

    -- Guards the fix that stopped a thought summary overwriting the user-visible
    -- answer. The reply was asked to be just "OK"; a thought summary is long
    -- prose, so a short answer is the discriminator.
    ut.expect(length(l_result.get_clob('final_message')),
              'Google: a thought summary must not become final_message').to_be_less_than(100);

    l_result := uc_ai.generate_text(
      p_messages => with_follow_up(l_result, c_turn_2_prompt)
    , p_provider => uc_ai.c_provider_google
    , p_model    => uc_ai_google.c_model_gemini_2_5_flash
    );

    assert_round_trip(l_result, 'Google');
  end google_thought_roundtrip;


  procedure ollama_thinking_roundtrip
  as
    l_result json_object_t;
  begin
    uc_ai.g_base_url := c_ollama_base_url;
    uc_ai.g_apex_web_credential := c_ollama_web_credential;
    uc_ai_ollama.g_use_responses_api := false;

    l_result := uc_ai.generate_text(
      p_user_prompt => c_turn_1_prompt
    , p_provider    => uc_ai.c_provider_ollama
    , p_model       => c_ollama_model
    );

    ut.expect(count_reasoning_items(l_result),
              'Ollama: turn 1 must return a thinking block, otherwise this test is not exercising replay')
      .to_be_greater_than(0);

    l_result := uc_ai.generate_text(
      p_messages => with_follow_up(l_result, c_turn_2_prompt)
    , p_provider => uc_ai.c_provider_ollama
    , p_model    => c_ollama_model
    );

    assert_round_trip(l_result, 'Ollama');
  end ollama_thinking_roundtrip;

end test_uc_ai_reasoning_replay_e2e;
/
