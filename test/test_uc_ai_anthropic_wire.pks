create or replace package test_uc_ai_anthropic_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Anthropic wire-level request and response tests (LLM-free))
  --%suitepath(uc_ai)

  -- Continues test_uc_ai_wire for the Anthropic provider: every test runs
  -- uc_ai.generate_text end to end and stops one step short of the network.
  -- uc_ai_test_http_mock records the request UC AI built and answers it with a
  -- hand-written response in the shape Anthropic documents.
  --
  -- The responses are written out here instead of being recorded, because each
  -- one carries a value a recorded exchange does not have: a stop_reason nobody
  -- asks for, two text blocks in one turn, or a tool_use with an empty input.
  --
  -- No test reads uc_ai_get_key: every call names an APEX web credential, so the
  -- suite runs on a database without provider keys. Tools registered here use the
  -- WIRE_A_ prefix so they cannot collide with another suite's rows.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- reasoning: the thinking shape follows the model --------------------------
  --%test(A model with adaptive thinking gets thinking.type adaptive and output_config.effort)
  procedure adaptive_thinking_on_new_model;

  --%test(A pre-4.6 model keeps the legacy thinking budget and gets no output_config)
  procedure legacy_thinking_on_old_model;

  --%test(A model id UC AI does not know defaults to the adaptive thinking shape)
  procedure unknown_model_uses_adaptive;

  --%test(The reasoning effort and the structured output format share one output_config)
  procedure effort_merges_with_schema;

  --%test(Reasoning without a budget and without a level sends the documented minimum)
  procedure reasoning_without_budget;

  -- tool calling ---------------------------------------------------------------
  --%test(A tool_use with an empty input runs the tool instead of raising ORA-30625)
  procedure tool_use_with_empty_input;

  -- stop reasons ---------------------------------------------------------------
  --%test(stop_reason refusal maps to content_filter)
  procedure refusal_maps_content_filter;

  --%test(stop_reason pause_turn maps to stop and model_context_window_exceeded to length)
  procedure pause_and_context_window;

  --%test(An unmapped stop_reason falls back to unknown and is kept as provider_finish_reason)
  procedure unmapped_stop_reason;

  -- final_message --------------------------------------------------------------
  --%test(Every text block of a turn reaches final_message, not just the last one)
  procedure two_text_blocks_are_joined;

  --%test(A last turn without text leaves no stale final_message from the turn before)
  procedure textless_turn_clears_message;

  -- message conversion ---------------------------------------------------------
  --%test(Two system messages both reach the single Anthropic system field)
  procedure two_system_messages_join;

  --%test(A trailing assistant prefill is sent without its trailing whitespace)
  procedure prefill_is_sent_rtrimmed;

end test_uc_ai_anthropic_wire;
/
