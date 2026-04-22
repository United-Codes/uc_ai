create or replace package test_uc_ai_callback as

  --%suite(Event callback tests)

  --%beforeall
  procedure setup_tests;

  --%beforeeach
  procedure reset_state;

  --%afterall
  procedure teardown;

  --%test(Input-side content construction does not fire events)
  procedure input_side_silence;

  --%test(reset_globals preserves the event callback registration)
  procedure reset_preserves_callback;

  --%test(clear_event_callback stops further firing)
  procedure clear_stops_firing;

  --%test(Callback errors are swallowed by default)
  procedure error_swallowed_default;

  --%test(g_callback_fatal=true propagates callback errors)
  procedure fatal_flag_propagates;

  --%test(set_event_callback rejects malformed procedure names)
  procedure invalid_name_rejected;

  --%test(OpenAI basic prompt fires assistant_text and response_complete)
  procedure fires_text_and_complete;

  --%test(OpenAI tool call fires tool_call, tool_result, and assistant_text)
  procedure fires_tool_events;

  --%test(Two sequential generate_text calls emit distinct request_ids)
  procedure request_id_is_per_call;

  -- callback entry points, invoked by uc_ai.fire_event via execute immediate
  procedure sink_on_ev(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  );

  procedure sink_raising(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  );

end test_uc_ai_callback;
/
