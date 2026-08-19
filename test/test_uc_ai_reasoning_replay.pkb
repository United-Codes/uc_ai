create or replace package body test_uc_ai_reasoning_replay as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  /*
   * Builds an assistant message whose content is exactly the items passed in.
   */
  function assistant_msg(
    p_item_1 in json_object_t
  , p_item_2 in json_object_t default null
  ) return json_object_t
  as
    l_content json_array_t := json_array_t();
  begin
    l_content.append(p_item_1);

    if p_item_2 is not null then
      l_content.append(p_item_2);
    end if;

    return uc_ai_message_api.create_assistant_message(l_content);
  end assistant_msg;


  /*
   * Reasoning content item with an arbitrary set of providerOptions keys.
   * A null key means "not present", which is what a real history looks like when
   * the provider did not supply that field.
   */
  function reasoning_item(
    p_text  in clob     default null
  , p_key_1 in varchar2 default null
  , p_val_1 in varchar2 default null
  , p_key_2 in varchar2 default null
  , p_val_2 in varchar2 default null
  ) return json_object_t
  as
    l_provider_options json_object_t;
  begin
    if p_key_1 is not null or p_key_2 is not null then
      l_provider_options := json_object_t();

      if p_key_1 is not null then
        l_provider_options.put(p_key_1, p_val_1);
      end if;

      if p_key_2 is not null then
        l_provider_options.put(p_key_2, p_val_2);
      end if;
    end if;

    return uc_ai_message_api.create_reasoning_content(
      p_text             => p_text
    , p_provider_options => l_provider_options
    );
  end reasoning_item;


  function simple_user_msg(
    p_text in clob
  ) return json_object_t
  as
    l_content json_array_t := json_array_t();
  begin
    l_content.append(uc_ai_message_api.create_text_content(p_text));
    return uc_ai_message_api.create_user_message(l_content);
  end simple_user_msg;


  /*
   * Returns the first item of the given type from a Responses API items array.
   */
  function first_item_of_type(
    p_items in json_array_t
  , p_type  in varchar2
  ) return json_object_t
  as
    l_item json_object_t;
  begin
    <<item_loop>>
    for i in 0 .. p_items.get_size - 1
    loop
      l_item := treat(p_items.get(i) as json_object_t);

      if l_item.get_string('type') = p_type then
        return l_item;
      end if;
    end loop item_loop;

    return null;
  end first_item_of_type;


  function count_items_of_type(
    p_items in json_array_t
  , p_type  in varchar2
  ) return pls_integer
  as
    l_count pls_integer := 0;
    l_item  json_object_t;
  begin
    <<item_loop>>
    for i in 0 .. p_items.get_size - 1
    loop
      l_item := treat(p_items.get(i) as json_object_t);

      if l_item.get_string('type') = p_type then
        l_count := l_count + 1;
      end if;
    end loop item_loop;

    return l_count;
  end count_items_of_type;


  /*
   * Content array of the message at p_index (used for the providers whose payload
   * is a messages array with a nested content/parts array).
   */
  function message_content(
    p_messages in json_array_t
  , p_index    in pls_integer
  , p_key      in varchar2 default 'content'
  ) return json_array_t
  as
  begin
    return treat(treat(p_messages.get(p_index) as json_object_t).get(p_key) as json_array_t);
  end message_content;


  procedure setup_tests
  as
  begin
    -- reset_globals is not automatic between tests, and a leftover
    -- g_store_responses from another suite would change the replayability gate.
    uc_ai.reset_globals;
  end setup_tests;


  procedure reset_globals
  as
  begin
    uc_ai.reset_globals;
  end reset_globals;


  -- ==========================================================================
  -- OpenAI Responses API (also serves xAI and OpenRouter)
  -- ==========================================================================

  procedure resp_reasoning_emits_summary
  as
    l_messages json_array_t := json_array_t();
    l_items    json_array_t;
    l_instr    varchar2(32767 char);
    l_item     json_object_t;
  begin
    -- The reported failure: reasoning summaries are off, so the item carries no
    -- text at all - only its id and the encrypted blob. 'summary' is required by
    -- the API regardless, and omitting it produced
    --   Missing required parameter: 'input[1].summary'
    l_messages.append(simple_user_msg('Calculate: What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(
        p_text  => null
      , p_key_1 => 'id'
      , p_val_1 => 'rs_0bc9ba1adf8f0765'
      , p_key_2 => 'encrypted_content'
      , p_val_2 => 'gAAAAABqa2H7l4bbahaKMTxL'
      )
    ));

    uc_ai_responses_api.convert_lm_messages_to_items(l_messages, l_items, l_instr);

    ut.expect(count_items_of_type(l_items, 'reasoning'),
              'reasoning item must be replayed').to_equal(1);
    l_item := first_item_of_type(l_items, 'reasoning');

    -- The regression assertion: summary is present even with nothing to summarize
    ut.expect(l_item.has('summary'), 'reasoning item must always carry a summary array').to_be_true();
    ut.expect(treat(l_item.get('summary') as json_array_t).get_size,
              'summary must be empty when there is no reasoning text').to_equal(0);

    -- ...and the id is what lets the provider correlate the item
    ut.expect(l_item.get_string('id')).to_equal('rs_0bc9ba1adf8f0765');
    ut.expect(l_item.get_string('encrypted_content')).to_equal('gAAAAABqa2H7l4bbahaKMTxL');

    -- A reasoning item has no top-level text field; sending one is invalid
    ut.expect(l_item.has('text'), 'reasoning item must not carry a top-level text field').to_be_false();
  end resp_reasoning_emits_summary;


  procedure resp_reasoning_summary_from_text
  as
    l_messages json_array_t := json_array_t();
    l_items    json_array_t;
    l_instr    varchar2(32767 char);
    l_item     json_object_t;
    l_summary  json_array_t;
  begin
    l_messages.append(simple_user_msg('Calculate: What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(
        p_text  => 'The user wants 2 times 2.'
      , p_key_1 => 'id'
      , p_val_1 => 'rs_withtext'
      , p_key_2 => 'encrypted_content'
      , p_val_2 => 'gAAAAAenc'
      )
    ));

    uc_ai_responses_api.convert_lm_messages_to_items(l_messages, l_items, l_instr);

    ut.expect(count_items_of_type(l_items, 'reasoning')).to_equal(1);
    l_item := first_item_of_type(l_items, 'reasoning');

    -- Reasoning text belongs in summary[].text, not in a top-level text field
    l_summary := treat(l_item.get('summary') as json_array_t);
    ut.expect(l_summary.get_size).to_equal(1);
    ut.expect(treat(l_summary.get(0) as json_object_t).get_string('type')).to_equal('summary_text');
    ut.expect(treat(l_summary.get(0) as json_object_t).get_string('text')).to_equal('The user wants 2 times 2.');
    ut.expect(l_item.has('text')).to_be_false();
  end resp_reasoning_summary_from_text;


  procedure resp_reasoning_dropped_unreplayable
  as
    l_messages json_array_t := json_array_t();
    l_items    json_array_t;
    l_instr    varchar2(32767 char);
  begin
    -- No encrypted_content and no id, with store=false: nothing the provider could
    -- reconstitute, so the item must be dropped rather than sent.
    uc_ai_responses_api.g_store_responses := false;

    l_messages.append(simple_user_msg('Calculate: What is 2*2?'));
    l_messages.append(assistant_msg(reasoning_item(p_text => 'Some stray reasoning.')));

    uc_ai_responses_api.convert_lm_messages_to_items(
      p_lm_messages   => l_messages
    , po_items        => l_items
    , po_instructions => l_instr
    , p_settings      => uc_ai_settings.build_from_globals
    );

    ut.expect(count_items_of_type(l_items, 'reasoning'),
              'an unreplayable reasoning item must not be sent').to_equal(0);
    -- the rest of the conversation still goes through
    ut.expect(count_items_of_type(l_items, 'message')).to_equal(1);
  end resp_reasoning_dropped_unreplayable;


  procedure resp_reasoning_kept_when_stored
  as
    l_messages json_array_t := json_array_t();
    l_items    json_array_t;
    l_instr    varchar2(32767 char);
    l_item     json_object_t;
  begin
    -- With store=true the bare rs_... id resolves server-side, so the item is
    -- replayable even without encrypted content.
    uc_ai_responses_api.g_store_responses := true;

    l_messages.append(simple_user_msg('Calculate: What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(p_text => 'Stored reasoning.', p_key_1 => 'id', p_val_1 => 'rs_stored')
    ));

    uc_ai_responses_api.convert_lm_messages_to_items(
      p_lm_messages   => l_messages
    , po_items        => l_items
    , po_instructions => l_instr
    , p_settings      => uc_ai_settings.build_from_globals
    );

    ut.expect(count_items_of_type(l_items, 'reasoning'),
              'an id-only reasoning item is replayable when store=true').to_equal(1);
    l_item := first_item_of_type(l_items, 'reasoning');

    ut.expect(l_item.get_string('id')).to_equal('rs_stored');
    ut.expect(l_item.has('summary')).to_be_true();
    ut.expect(l_item.has('encrypted_content')).to_be_false();
  end resp_reasoning_kept_when_stored;


  procedure resp_replays_exec_342_history
  as
    l_messages json_array_t := json_array_t();
    l_items    json_array_t;
    l_instr    varchar2(32767 char);
    l_tool_res json_array_t := json_array_t();
    l_item     json_object_t;
  begin
    -- Verbatim shape of the conversation that failed: a reasoning turn with a tool
    -- call, its result, the answer, and then a follow-up question. The 400 named
    -- input[1] - the item right after the user message, since the system message
    -- becomes 'instructions' rather than an item.
    l_messages.append(uc_ai_message_api.create_system_message('You are a math agent.'));
    l_messages.append(simple_user_msg('Calculate: What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(
        p_text  => null
      , p_key_1 => 'id'
      , p_val_1 => 'rs_0bc9ba1adf8f0765'
      , p_key_2 => 'encrypted_content'
      , p_val_2 => 'gAAAAABqa2H7'
      )
    , uc_ai_message_api.create_tool_call_content(
        p_tool_call_id => 'call_1'
      , p_tool_name    => 'MATH_CALC_TOOL'
      , p_args         => '{"expression":"2*2"}'
      )
    ));

    l_tool_res.append(uc_ai_message_api.create_tool_result_content(
      p_tool_call_id => 'call_1'
    , p_tool_name    => 'MATH_CALC_TOOL'
    , p_result       => '4'
    ));
    l_messages.append(uc_ai_message_api.create_tool_message(l_tool_res));

    l_messages.append(uc_ai_message_api.create_simple_assistant_message('4'));
    l_messages.append(simple_user_msg('And what is 3*3?'));

    uc_ai_responses_api.convert_lm_messages_to_items(l_messages, l_items, l_instr);

    -- system message is lifted out into instructions, not an input item
    ut.expect(l_instr).to_equal('You are a math agent.');

    -- user, reasoning, function_call, function_call_output, assistant, user
    ut.expect(l_items.get_size).to_equal(6);

    -- The exact item the provider rejected
    l_item := treat(l_items.get(1) as json_object_t);
    ut.expect(l_item.get_string('type'), 'input[1] must be the reasoning item').to_equal('reasoning');
    ut.expect(l_item.has('summary'), 'input[1].summary was the missing required parameter').to_be_true();
    ut.expect(l_item.has('text')).to_be_false();

    -- and the surrounding items are still correlated by call_id
    ut.expect(treat(l_items.get(2) as json_object_t).get_string('type')).to_equal('function_call');
    ut.expect(treat(l_items.get(2) as json_object_t).get_string('call_id')).to_equal('call_1');
    ut.expect(treat(l_items.get(3) as json_object_t).get_string('type')).to_equal('function_call_output');
    ut.expect(treat(l_items.get(3) as json_object_t).get_string('call_id')).to_equal('call_1');
  end resp_replays_exec_342_history;


  -- ==========================================================================
  -- Anthropic extended thinking
  -- ==========================================================================

  procedure anthropic_thinking_replayed
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_content  json_array_t;
    l_block    json_object_t;
  begin
    -- A replayed thinking block keeps its signature, and Anthropic documents that
    -- thinking comes FIRST in the content array.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      uc_ai_message_api.create_tool_call_content(
        p_tool_call_id => 'toolu_1'
      , p_tool_name    => 'MATH_CALC_TOOL'
      , p_args         => '{"expression":"2*2"}'
      )
    , reasoning_item(
        p_text  => 'I should use the calculator.'
      , p_key_1 => 'signature'
      , p_val_1 => 'EvUKCkYIChgCIkDx'
      )
    ));

    uc_ai_anthropic.convert_lm_messages_to_anthropic(l_messages, l_system, l_msgs);

    l_content := message_content(l_msgs, 1);

    -- thinking must be prepended even though it came second in the normalized array
    l_block := treat(l_content.get(0) as json_object_t);
    ut.expect(l_block.get_string('type'), 'thinking must be the first content block').to_equal('thinking');
    ut.expect(l_block.get_string('thinking')).to_equal('I should use the calculator.');
    ut.expect(l_block.get_string('signature')).to_equal('EvUKCkYIChgCIkDx');

    ut.expect(treat(l_content.get(1) as json_object_t).get_string('type')).to_equal('tool_use');
  end anthropic_thinking_replayed;


  procedure anthropic_thinking_needs_signature
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_content  json_array_t;
  begin
    -- A block with no signature has no provenance to vouch for it, so we do not
    -- invent one - stricter modes (interleaved thinking) validate what they get.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(p_text => 'Unsigned reasoning.')
    , uc_ai_message_api.create_text_content('4')
    ));

    uc_ai_anthropic.convert_lm_messages_to_anthropic(l_messages, l_system, l_msgs);

    l_content := message_content(l_msgs, 1);

    ut.expect(l_content.get_size, 'only the text block survives').to_equal(1);
    ut.expect(treat(l_content.get(0) as json_object_t).get_string('type')).to_equal('text');
  end anthropic_thinking_needs_signature;


  procedure anthropic_redacted_thinking_replayed
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_content  json_array_t;
    l_block    json_object_t;
  begin
    -- A redacted block has no readable text at all, only an opaque payload that
    -- must be handed back untouched.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(
        p_text  => null
      , p_key_1 => 'type'
      , p_val_1 => 'redacted_thinking'
      , p_key_2 => 'data'
      , p_val_2 => 'EroBCkYIBBgCKkBQb3J0'
      )
    , uc_ai_message_api.create_text_content('4')
    ));

    uc_ai_anthropic.convert_lm_messages_to_anthropic(l_messages, l_system, l_msgs);

    l_content := message_content(l_msgs, 1);

    l_block := treat(l_content.get(0) as json_object_t);
    ut.expect(l_block.get_string('type')).to_equal('redacted_thinking');
    ut.expect(l_block.get_string('data')).to_equal('EroBCkYIBBgCKkBQb3J0');
    ut.expect(l_block.has('thinking'), 'a redacted block carries no thinking text').to_be_false();
  end anthropic_redacted_thinking_replayed;


  -- ==========================================================================
  -- Google thought signatures
  -- ==========================================================================

  procedure google_signature_on_function_call
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_parts    json_array_t;
    l_part     json_object_t;
  begin
    -- Gemini 2.5+ signs the functionCall part and requires the signature back on
    -- that same part; without it multi-turn function calling breaks.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      uc_ai_message_api.create_tool_call_content(
        p_tool_call_id     => 'call_1'
      , p_tool_name        => 'MATH_CALC_TOOL'
      , p_args             => '{"expression":"2*2"}'
      , p_provider_options => json_object_t('{"thoughtSignature":"CvUKCkYIChgC"}')
      )
    ));

    uc_ai_google.convert_lm_messages_to_google(l_messages, l_system, l_msgs);

    l_parts := message_content(l_msgs, 1, 'parts');
    l_part := treat(l_parts.get(0) as json_object_t);

    ut.expect(l_part.has('functionCall')).to_be_true();
    ut.expect(l_part.get_string('thoughtSignature')).to_equal('CvUKCkYIChgC');
  end google_signature_on_function_call;


  procedure google_thought_needs_signature
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_parts    json_array_t;
  begin
    -- Thought summaries need not be returned; only signatures do. An unsigned
    -- thought part carries nothing Gemini needs.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(p_text => 'Thinking about multiplication.')
    , uc_ai_message_api.create_text_content('4')
    ));

    uc_ai_google.convert_lm_messages_to_google(l_messages, l_system, l_msgs);

    l_parts := message_content(l_msgs, 1, 'parts');

    ut.expect(l_parts.get_size, 'only the text part survives').to_equal(1);
    ut.expect(l_parts.to_clob).to_be_like('%"text":"4"%');
  end google_thought_needs_signature;


  procedure google_parse_does_not_alias
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_parts    json_array_t;
    l_part     json_object_t;
  begin
    -- Regression: converting must not mutate the normalized content it reads.
    -- The parse side used to alias the provider's own part object and strip keys
    -- out of it in place; converting the same history twice must be stable.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(
        p_text  => 'Signed thought.'
      , p_key_1 => 'thoughtSignature'
      , p_val_1 => 'CvUKsigned'
      )
    ));

    uc_ai_google.convert_lm_messages_to_google(l_messages, l_system, l_msgs);
    l_parts := message_content(l_msgs, 1, 'parts');
    l_part := treat(l_parts.get(0) as json_object_t);
    ut.expect(l_part.get_string('text')).to_equal('Signed thought.');
    ut.expect(l_part.get_boolean('thought')).to_be_true();
    ut.expect(l_part.get_string('thoughtSignature')).to_equal('CvUKsigned');

    -- second pass over the SAME normalized messages must be identical
    uc_ai_google.convert_lm_messages_to_google(l_messages, l_system, l_msgs);
    l_parts := message_content(l_msgs, 1, 'parts');
    l_part := treat(l_parts.get(0) as json_object_t);
    ut.expect(l_part.get_string('text'), 'converting must not consume the source item').to_equal('Signed thought.');
    ut.expect(l_part.get_string('thoughtSignature')).to_equal('CvUKsigned');
  end google_parse_does_not_alias;


  -- ==========================================================================
  -- Ollama
  -- ==========================================================================

  procedure ollama_thinking_replayed
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_msg      json_object_t;
  begin
    -- /api/chat accepts 'thinking' on assistant messages, so it should round-trip
    -- instead of being dropped with a warning.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(p_text => 'Two times two is four.')
    , uc_ai_message_api.create_text_content('4')
    ));

    uc_ai_ollama.convert_lm_messages_to_ollama(l_messages, l_msgs);

    l_msg := treat(l_msgs.get(1) as json_object_t);
    ut.expect(l_msg.get_string('role')).to_equal('assistant');
    ut.expect(l_msg.get_string('thinking')).to_equal('Two times two is four.');
    ut.expect(l_msg.get_string('content')).to_equal('4');
  end ollama_thinking_replayed;


  -- ==========================================================================
  -- OCI
  -- ==========================================================================

  procedure oci_cohere_reasoning_not_chatbot
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_user_msg clob;
    l_chatbot  pls_integer := 0;
    l_msg      json_object_t;
  begin
    -- Cohere has no reasoning channel. The reasoning item used to be re-sent as a
    -- CHATBOT turn built from get_clob('text'), corrupting the transcript.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(p_text => 'Internal chain of thought that must not be sent.')
    , uc_ai_message_api.create_text_content('4')
    ));
    l_messages.append(simple_user_msg('And 3*3?'));

    uc_ai_oci.convert_lm_messages_to_cohere_oci(l_messages, l_msgs, l_system, l_user_msg);

    <<msg_loop>>
    for i in 0 .. l_msgs.get_size - 1
    loop
      l_msg := treat(l_msgs.get(i) as json_object_t);

      if l_msg.get_string('role') = 'CHATBOT' then
        l_chatbot := l_chatbot + 1;
        ut.expect(l_msg.get_string('message'),
                  'no CHATBOT turn may carry the reasoning text').not_to_equal('Internal chain of thought that must not be sent.');
      end if;
    end loop msg_loop;

    ut.expect(l_chatbot, 'exactly one CHATBOT turn, from the text content').to_equal(1);
  end oci_cohere_reasoning_not_chatbot;


  procedure oci_cohere_reasoning_with_tool_call
  as
    l_messages json_array_t := json_array_t();
    l_msgs     json_array_t;
    l_system   clob;
    l_user_msg clob;
  begin
    -- With a tool call in the same message the reasoning item used to fall into the
    -- else branch and raise c_err_unsupported_content. It must simply be skipped.
    l_messages.append(simple_user_msg('What is 2*2?'));
    l_messages.append(assistant_msg(
      reasoning_item(p_text => 'I will use the calculator.')
    , uc_ai_message_api.create_tool_call_content(
        p_tool_call_id => 'call_1'
      , p_tool_name    => 'MATH_CALC_TOOL'
      , p_args         => '{"expression":"2*2"}'
      )
    ));

    uc_ai_oci.convert_lm_messages_to_cohere_oci(l_messages, l_msgs, l_system, l_user_msg);

    -- reaching here without an exception is the assertion; confirm the tool call survived
    ut.expect(l_msgs.get_size).to_be_greater_than(0);
    ut.expect(l_msgs.to_clob).to_be_like('%MATH_CALC_TOOL%');
  end oci_cohere_reasoning_with_tool_call;

end test_uc_ai_reasoning_replay;
/
