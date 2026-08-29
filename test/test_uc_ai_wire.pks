create or replace package test_uc_ai_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Wire-level request and response tests (LLM-free))
  --%suitepath(uc_ai)

  -- Every test runs uc_ai.generate_text or generate_embeddings end to end and stops
  -- one step short of the network: uc_ai_http hands the request to
  -- uc_ai_test_http_mock, which records it and answers with a recorded provider
  -- response from test/samples (compiled into uc_ai_test_samples).
  --
  -- Two things are asserted per exchange:
  --   1. the request body UC AI built equals the recorded request (JSON equality,
  --      key order aside), together with the URL and headers it was sent with
  --   2. the recorded response is parsed into the documented result object
  --
  -- test_uc_ai_structured_output proves the schema converter in isolation. These
  -- tests prove the converter's output reaches the wire inside the envelope each
  -- provider expects, which is what a live HTTP 400 would otherwise have caught.
  --
  -- No test reads uc_ai_get_key: every call names an APEX web credential, so the
  -- suite runs on a database without provider keys.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- The recorded tool result of the Responses API tool round trip. Public because
  -- the TT_GET_USERS tool registered by the tool tests calls it as its handler.
  function recorded_users return clob;

  -- Helpers shared with test_uc_ai_wire_2, which continues this suite in a second
  -- package. Not tests: none of them carries an annotation.
  function config(p_json in varchar2 default '{}') return json_object_t;

  procedure enqueue_sample(p_sample in varchar2);

  procedure expect_request(
    p_index  in pls_integer
  , p_sample in varchar2
  );

  procedure expect_url(
    p_index in pls_integer
  , p_url   in varchar2
  );

  procedure expect_all_consumed(p_requests in pls_integer);

  procedure expect_usage(
    p_result            in json_object_t
  , p_prompt_tokens     in number
  , p_completion_tokens in number
  , p_total_tokens      in number   default null
  , p_reasoning_tokens  in number   default null
  );

  function messages_of(p_result in json_object_t) return json_array_t;

  procedure register_users_tool;

  -- structured output ----------------------------------------------------------
  --%test(OpenAI Chat Completions sends response_format and parses the JSON text back)
  procedure openai_chat_structured_output;

  --%test(OpenAI Responses API sends text.format and parses the JSON text back)
  procedure openai_responses_structured_output;

  --%test(Anthropic sends output_config.format and parses the JSON text back)
  procedure anthropic_structured_output;

  --%test(Google sends generationConfig.responseSchema and parses the JSON text back)
  procedure google_structured_output;

  --%test(xAI sends the Chat Completions response_format with reasoning_effort)
  procedure xai_structured_output;

  --%test(Ollama sends the native format key and parses the JSON text back)
  procedure ollama_structured_output;

  -- plain text -----------------------------------------------------------------
  --%test(Anthropic plain text request and response)
  procedure anthropic_simple_text;

  --%test(Google plain text request and response)
  procedure google_simple_text;

  --%test(OpenAI Responses API plain text request and response)
  procedure openai_responses_simple_text;

  --%test(xAI plain text request and response)
  procedure xai_simple_text;

  --%test(OpenRouter plain text request and response)
  procedure openrouter_simple_text;

  -- tool calling ---------------------------------------------------------------
  --%test(OpenAI Responses API replays a recorded two-request tool round trip)
  procedure openai_responses_tool_round_trip;

  --%test(OpenAI Chat Completions sends the tool result back with its tool_call_id)
  procedure openai_chat_tool_round_trip;

  --%test(The tool loop stops at max_tool_calls before making another request)
  procedure tool_loop_stops_at_max_tool_calls;

  -- error handling -------------------------------------------------------------
  --%test(HTTP 400 with an error object raises -20302 carrying the provider message)
  procedure http_400_error_body_raises;

  --%test(HTTP 502 with a non-JSON body raises -20302)
  procedure http_502_html_body_raises;

  --%test(HTTP 404 with a JSON body but no error key still raises -20302)
  procedure http_404_without_error_key_raises;

  --%test(Anthropic error envelope raises -20302 carrying the provider message)
  procedure anthropic_error_body_raises;

  -- embeddings -----------------------------------------------------------------
  --%test(OpenAI embeddings request and response)
  procedure openai_embeddings;

  --%test(Google embeddings request and response)
  procedure google_embeddings;

  -- reasoning ------------------------------------------------------------------
  --%test(Anthropic sends the thinking budget and keeps the signed thinking block out of final_message)
  procedure anthropic_reasoning_round_trip;

  --%test(Google sends thinkingConfig and keeps the thought part out of final_message)
  procedure google_reasoning_round_trip;

  --%test(OpenAI Chat Completions sends reasoning_effort and counts reasoning tokens)
  procedure openai_chat_reasoning_tokens;

  -- transport ------------------------------------------------------------------
  --%test(Extra headers and the web credential reach the transport, no API key does)
  procedure headers_and_credential_on_the_wire;

end test_uc_ai_wire;
/
