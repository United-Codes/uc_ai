create or replace package test_uc_ai_oci_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Wire-level OCI request and response tests (LLM-free))
  --%suitepath(uc_ai)

  -- Continues test_uc_ai_wire and test_uc_ai_wire_2 for the OCI provider: the
  -- same mock transport, the same recorded samples, the same two assertions per
  -- exchange (the request UC AI built, the result it parsed). The shared helpers
  -- live in test_uc_ai_wire and are called from here.
  --
  -- What this package pins that the other two do not:
  --   * a GENERIC turn with two tool calls, where each TOOL message must carry
  --     only its own result
  --   * the replay converters: a returned `messages` array fed back in has to
  --     rebuild the request the live loop built, tool calls and ids included
  --   * the COHERE finishReason states that are not a completion
  --
  -- Where no recorded exchange exists the provider response is a hand-written
  -- body in the shape Oracle's own SDK types document (see
  -- reference/oci-typescript-sdk/.../generativeaiinference/lib/model).
  --
  -- No test reads uc_ai_get_key: every call names an APEX web credential.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- Tool handlers. Public because the tools registered by the tests call them by
  -- name; they are not tests.
  function echo_name(p_args in clob) return clob;
  function list_users return clob;

  -- generic ----------------------------------------------------------------------
  --%test(OCI GENERIC treats an empty toolCalls array as a normal completion)
  procedure generic_empty_tool_calls;

  --%test(OCI GENERIC replays a conversation history as SYSTEM/USER/ASSISTANT messages)
  procedure generic_continue_conversation;

  --%test(OCI GENERIC gives every TOOL message only its own result)
  procedure generic_parallel_tool_calls;

  --%test(OCI GENERIC accepts a JSON null content next to toolCalls)
  procedure generic_null_content_tool_turn;

  --%test(OCI GENERIC replays a tool history as toolCalls and TOOL messages)
  procedure generic_replays_tool_history;

  --%test(OCI GENERIC rebuilds its own request when the returned messages are fed back)
  procedure generic_round_trip_replay;

  -- cohere -----------------------------------------------------------------------
  --%test(OCI COHERE gives every toolResults entry only its own output)
  procedure cohere_tool_results_own_output;

  --%test(OCI COHERE keeps the preamble text of a tool-calling turn)
  procedure cohere_keeps_preamble_text;

  --%test(OCI COHERE rebuilds toolCalls and toolResults when the returned messages are fed back)
  procedure cohere_round_trip_replay;

  --%test(OCI COHERE sends a message when the history has no user turn left)
  procedure cohere_history_without_user_turn;

  --%test(OCI COHERE raises -20502 for an empty message history)
  procedure cohere_empty_history_raises;

  --%test(OCI COHERE maps the finishReason states that are not a completion)
  procedure cohere_finish_reason_states;

  --%test(OCI COHERE declares a flat tool schema under parameterDefinitions)
  procedure cohere_flat_parameter_definitions;

  -- serving mode -------------------------------------------------------------------
  --%test(OCI raises -20503 for servingType DEDICATED instead of sending an invalid body)
  procedure dedicated_serving_type_raises;

end test_uc_ai_oci_wire;
/
