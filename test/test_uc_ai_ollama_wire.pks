create or replace package test_uc_ai_ollama_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Ollama native /api/chat wire tests (LLM-free))
  --%suitepath(uc_ai)

  -- Continues test_uc_ai_wire, test_uc_ai_wire_2 and test_uc_ai_wire_3 with the
  -- cases that only the native /api/chat route reaches. The same mock transport
  -- and the same shared helpers: uc_ai_http hands each request to
  -- uc_ai_test_http_mock, which records it and answers with a queued body.
  --
  -- Every test sets ollama.g_use_responses_api to false. With the default (true)
  -- uc_ai_ollama delegates to uc_ai_responses_api and none of the code under test
  -- here runs.
  --
  -- No test reads uc_ai_get_key: every call names an APEX web credential.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- Tool handler. Public because the tool registered by the tests calls it by
  -- name; it is not a test.
  function tool_answer return clob;

  -- user message conversion ----------------------------------------------------
  --%test(A user message with only a PNG and no text is sent with its images array)
  procedure file_only_user_message;

  --%test(A PDF in a user message raises -20303 instead of being sent as an image)
  procedure pdf_user_file_raises;

  --%test(A user message with text and a PNG still sends both)
  procedure text_and_image_user_message;

  -- tool calling ---------------------------------------------------------------
  --%test(A tool-call turn with empty content executes the tool and replays it with tool_name)
  procedure empty_content_tool_call;

  --%test(A tool call without an arguments key runs the tool with empty arguments)
  procedure tool_call_without_arguments;

  -- response parsing -----------------------------------------------------------
  --%test(A plain text turn is parsed unchanged)
  procedure plain_text_turn;

  --%test(A JSON null tool_calls key is not read as a tool call)
  procedure json_null_tool_calls;

  --%test(A response body without a message object raises -20304, not ORA-30625)
  procedure response_without_message;

end test_uc_ai_ollama_wire;
/
