create or replace package test_uc_ai_openai_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(OpenAI Chat Completions wire-level regression tests (LLM-free))
  --%suitepath(uc_ai)

  -- The Chat Completions implementation in uc_ai_openai also serves xAI,
  -- OpenRouter and Mistral, so a defect here reaches four providers. Every test
  -- below pins one such defect found by the reference audit.
  --
  -- Same mechanics as test_uc_ai_wire, whose public helpers this suite reuses:
  -- uc_ai_test_http_mock replaces the network, the test enqueues the response the
  -- provider would have sent, and the assertions read the request UC AI built and
  -- the result object it returned. No test reads uc_ai_get_key: every call names
  -- an APEX web credential.
  --
  -- The Chat Completions route is not the default. OpenAI reaches it with
  -- openai:{g_use_responses_api:false}; xAI reaches it through the package global,
  -- because the xai config block cannot address the OpenAI package.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- B4 -------------------------------------------------------------------------
  --%test(xAI reasoning is sent as reasoning_effort, the key xAI actually reads)
  procedure xai_sends_reasoning_effort;

  -- B5 -------------------------------------------------------------------------
  --%test(xAI flat tool arguments reach the tool unchanged)
  procedure xai_flat_tool_arguments;

  --%test(xAI arguments wrapped in parameters are still unwrapped)
  procedure xai_wrapped_tool_arguments;

  -- B13 ------------------------------------------------------------------------
  --%test(A 40 KB tool argument string survives the 32 KB varchar2 ceiling)
  procedure chat_large_tool_arguments;

  -- B20 ------------------------------------------------------------------------
  --%test(Assistant text sent next to tool calls stays in the returned messages)
  procedure chat_text_next_to_tool_calls;

  -- response robustness --------------------------------------------------------
  --%test(A JSON-null usage object is tolerated instead of raising ORA-30625)
  procedure null_usage_is_tolerated;

  --%test(A response without a choices array raises -20302, not ORA-30625)
  procedure missing_choices_raises;

end test_uc_ai_openai_wire;
/
