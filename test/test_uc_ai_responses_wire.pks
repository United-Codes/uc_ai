create or replace package test_uc_ai_responses_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-7230): allow package state in test helper

  --%suite(OpenAI Responses API wire-level regression tests (LLM-free))
  --%suitepath(uc_ai)

  -- Continues test_uc_ai_wire for the Responses API. Same construction: every test
  -- runs uc_ai.generate_text end to end and stops one step short of the network,
  -- because uc_ai_http hands the request to uc_ai_test_http_mock instead of
  -- apex_web_service. No test reads uc_ai_get_key - every call names an APEX web
  -- credential - so the suite runs on a database without provider keys.
  --
  -- Where test_uc_ai_wire replays the recorded exchanges, this package pins the
  -- edges those recordings do not contain: a truncated response, a filtered one,
  -- a run that uses up its tool budget, a response with no output at all, results
  -- and answers above the 32 KB varchar2 limit, and the request keys that reasoning
  -- with store=false needs.
  --
  -- Tool codes start with WIRE_D_ so the suite cannot collide with another suite
  -- on a uc_ai_tools row.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- Tool handlers. Public because the registered tools call them by name.
  function echo_args(p_args in clob) return clob;

  function users_result return clob;

  -- Event sink registered with uc_ai.set_event_callback in one test.
  procedure sink_on_ev(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  );

  -- finish_reason ---------------------------------------------------------------
  --%test(A completed response finishes with stop)
  procedure finish_reason_stop_on_completed;

  --%test(incomplete_details.reason max_output_tokens finishes with length)
  procedure finish_reason_length_on_truncation;

  --%test(incomplete_details.reason content_filter finishes with content_filter)
  procedure finish_reason_content_filter;

  --%test(An unmapped incomplete reason still reports a documented finish_reason)
  procedure finish_reason_unmapped_incomplete;

  --%test(Using up the tool budget finishes with max_tool_calls_exceeded)
  procedure finish_reason_max_tool_calls;

  --%test(A response without an output array raises -20302 instead of answering null)
  procedure missing_output_raises;

  -- normalized history ----------------------------------------------------------
  --%test(A tool call left over at the tool budget replays as a function_call item)
  procedure tool_call_replays_after_budget;

  --%test(An echoed function_call_output replays as a function_call_output item)
  procedure tool_result_replays_as_output_item;

  -- 32 KB ceilings ---------------------------------------------------------------
  --%test(A 40 KB tool result replays whole)
  procedure large_tool_result_replays_whole;

  --%test(A 40 KB answer is returned whole)
  procedure large_answer_is_not_truncated;

  -- request building ---------------------------------------------------------------
  --%test(A scalar property named parameters is not mistaken for an argument wrapper)
  procedure scalar_parameters_is_not_unwrapped;

  --%test(Reasoning with store false asks for the encrypted reasoning blob)
  procedure encrypted_reasoning_included_when_not_stored;

  --%test(Reasoning with store true does not ask for the encrypted reasoning blob)
  procedure encrypted_reasoning_omitted_when_stored;

end test_uc_ai_responses_wire;
/
