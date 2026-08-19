create or replace package test_uc_ai_reasoning_replay_e2e as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Reasoning replay end-to-end against live providers)
  --%suitepath(uc_ai)

  -- LIVE tests (real API calls, needs uc_ai_get_key / web credentials configured).
  -- The LLM-free counterpart is test_uc_ai_reasoning_replay, which asserts the
  -- request payload; these confirm the providers actually ACCEPT that payload.
  --
  -- Each test is deliberately small - two calls, no tools, short prompts:
  --   turn 1: ask something with reasoning enabled
  --   turn 2: replay the full returned history plus a follow-up question
  -- Turn 2 is what broke in production (ORA-20302 / HTTP 400 from the provider),
  -- so a green run here means the reasoning items survived the round trip.

  --%beforeeach
  procedure setup_tests;

  --%aftereach
  procedure reset_globals;

  --%test(OpenAI Responses API replays encrypted, summary-less reasoning)
  procedure openai_responses_roundtrip;

  --%test(Anthropic replays a signed extended-thinking block)
  procedure anthropic_thinking_roundtrip;

  --%test(Anthropic replays a thinking block alongside a tool call)
  procedure anthropic_thinking_tool_roundtrip;

  --%test(Google replays a thought part)
  procedure google_thought_roundtrip;

  --%test(Ollama replays thinking)
  procedure ollama_thinking_roundtrip;

end test_uc_ai_reasoning_replay_e2e;
/
