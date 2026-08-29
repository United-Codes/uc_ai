create or replace package test_uc_ai_google_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Google Gemini wire-level regression tests (LLM-free))
  --%suitepath(uc_ai)

  -- Continues the test_uc_ai_wire suite for the Google provider and covers the
  -- three shapes a live call is hard to produce on demand:
  --
  --   * an HTTP 200 body that Google returns when it refuses the prompt or ends
  --     a candidate without content. Both used to raise ORA-30625 instead of a
  --     finish reason.
  --   * a turn whose answer is spread over several text parts, and a turn that
  --     answers with nothing at all after an earlier turn produced text.
  --   * the reasoning parameter, which Gemini 3 reads under a different key than
  --     gemini-2.5.
  --
  -- Same rules as test_uc_ai_wire: uc_ai_test_http_mock stands in for the
  -- network, every call names an APEX web credential so no test reads a provider
  -- key (and no ?key= reaches the URL), and every test ends by asserting that
  -- every queued response was consumed.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- B3: HTTP 200 bodies that carry no usable candidate -------------------------
  --%test(A prompt blocked by Google returns content_filter with the block reason)
  procedure prompt_block_returns_content_filter;

  --%test(A 200 body with neither candidates nor a block reason raises -20302)
  procedure no_candidates_and_no_reason_raises;

  --%test(A candidate with an empty content object keeps its mapped finish reason)
  procedure candidate_with_empty_content;

  --%test(A candidate without a content key on SAFETY returns content_filter)
  procedure candidate_without_content_key;

  --%test(MAX_TOKENS spent entirely on thinking returns length and counts the tokens)
  procedure max_tokens_spent_on_thinking;

  --%test(An embeddings response without an embeddings array raises -20302)
  procedure embeddings_without_array_raises;

  -- B16: final_message accumulation ---------------------------------------------
  --%test(Every visible text part of a turn reaches final_message)
  procedure all_text_parts_reach_final_message;

  --%test(A final turn without text clears final_message instead of keeping the old one)
  procedure final_turn_without_text_clears_it;

  -- B17: reasoning parameter per model generation --------------------------------
  --%test(A gemini-3 request carries thinkingLevel and no thinkingBudget)
  procedure gemini3_sends_thinking_level;

  --%test(A gemini-2.5 request keeps the thinking budget)
  procedure gemini25_sends_thinking_budget;

  --%test(An unrecognized model id gets the current thinkingLevel shape)
  procedure unknown_model_uses_thinking_level;

  --%test(An explicit reasoning budget stays a thinkingBudget on every generation)
  procedure explicit_budget_is_sent_verbatim;

  --%test(A reasoning level outside low, medium and high does not raise)
  procedure unknown_reasoning_level_is_dropped;

  -- The handler of the WIRE_B_GET_USERS tool.
  function recorded_users return clob;

end test_uc_ai_google_wire;
/
