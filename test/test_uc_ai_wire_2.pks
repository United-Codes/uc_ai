create or replace package test_uc_ai_wire_2 as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Wire-level request and response tests, part 2 (LLM-free))
  --%suitepath(uc_ai)

  -- Continues test_uc_ai_wire: the same mock transport, the same recorded samples,
  -- the same two assertions per exchange (the request UC AI built, the result it
  -- parsed). Split into a second (and third, test_uc_ai_wire_3) package only for
  -- size. The shared helpers live in test_uc_ai_wire and are called from here.
  --
  -- Where no recorded exchange exists (Anthropic, Google, Ollama, Mistral tool
  -- calls, and the part 3 tests) the provider response is a minimal hand-written
  -- body in the documented shape, built by the functions below. Those are not
  -- recorded output and deliberately live here, not in test/samples.
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
  function recorded_projects return clob;
  function recorded_clock_in(p_args in clob) return clob;
  function echo_args(p_args in clob) return clob;
  function raising_tool return clob;

  -- Helpers shared with test_uc_ai_wire_3: hand-written provider responses in the
  -- documented shapes, the OCI sample config and a user message with fake files.
  -- Not tests: none of them carries an annotation.
  function oci_config(p_json in varchar2 default '{}') return json_object_t;

  procedure enqueue(p_body in clob);

  function request_json(p_index in pls_integer) return json_object_t;

  function item(
    p_array in json_array_t
  , p_index in pls_integer
  ) return json_object_t;

  function content_of(p_message in json_object_t) return json_array_t;

  function last_message_of(p_result in json_object_t) return json_object_t;

  function chat_completion(
    p_content       in varchar2
  , p_prompt_tokens in pls_integer default 10
  , p_output_tokens in pls_integer default 5
  , p_finish_reason in varchar2    default 'stop'
  , p_model         in varchar2    default 'gpt-4o-mini-2024-07-18'
  , p_tool_calls    in json_array_t default null
  , p_with_usage    in boolean     default true
  ) return clob;

  function chat_tool_call(
    p_call_id   in varchar2
  , p_tool_name in varchar2
  , p_arguments in varchar2 default '{}'
  , p_model     in varchar2 default 'gpt-4o-mini-2024-07-18'
  ) return clob;

  function anthropic_message(
    p_content       in json_array_t
  , p_stop_reason   in varchar2 default 'end_turn'
  , p_input_tokens  in pls_integer default 10
  , p_output_tokens in pls_integer default 5
  ) return clob;

  function google_candidate(
    p_parts            in json_array_t
  , p_finish_reason    in varchar2 default 'STOP'
  , p_prompt_tokens    in pls_integer default 10
  , p_candidate_tokens in pls_integer default 5
  ) return clob;

  function ollama_chat(
    p_message     in json_object_t
  , p_prompt_eval in pls_integer default 10
  , p_eval        in pls_integer default 5
  ) return clob;

  function oci_generic_text(
    p_text              in varchar2
  , p_prompt_tokens     in pls_integer default 10
  , p_completion_tokens in pls_integer default 5
  , p_finish_reason     in varchar2    default 'stop'
  ) return clob;

  function responses_body(
    p_output        in json_array_t
  , p_id            in varchar2    default 'resp_wire'
  , p_input_tokens  in pls_integer default 10
  , p_output_tokens in pls_integer default 5
  , p_reasoning     in pls_integer default 0
  ) return clob;

  function responses_text(p_text in varchar2) return json_array_t;

  function files_message return json_array_t;

  -- oci ------------------------------------------------------------------------
  --%test(OCI GENERIC plain text request and response)
  --%disabled(BUG uc_ai_oci.pkb internal_generate_text: an empty toolCalls array on a normal completion is treated as a tool turn and triggers another request)
  procedure oci_generic_simple_text;

  --%test(OCI GENERIC converts a conversation history to SYSTEM/USER/ASSISTANT messages)
  --%disabled(BUG uc_ai_oci.pkb internal_generate_text: an empty toolCalls array on a normal completion is treated as a tool turn and triggers another request)
  procedure oci_generic_continue_conversation;

  --%test(OCI GENERIC replays the recorded six-request tool round trip)
  procedure oci_generic_tool_round_trip;

  --%test(OCI GENERIC maps finishReason length to length)
  procedure oci_generic_finish_reason_length;

  --%test(OCI COHERE sends preambleOverride, chatHistory and message)
  procedure oci_cohere_simple_text;

  --%test(OCI COHERE converts a conversation history to chatHistory and message)
  procedure oci_cohere_continue_conversation;

  --%test(OCI COHERE replays the recorded tool round trip with toolResults)
  procedure oci_cohere_tool_round_trip;

  --%test(OCI COHERE gives every toolResults entry only its own output)
  --%disabled(BUG uc_ai_oci.pkb internal_generate_text cohere branch: l_tool_outputs is shared across the tool loop, so toolResults[n].outputs carries the results of every earlier call too)
  procedure oci_cohere_tool_results_carry_own_output;

  --%test(OCI embeddings request and response)
  procedure oci_embeddings;

  --%test(OCI without a compartment id raises -20502 before any request)
  procedure oci_missing_compartment_raises;

  --%test(OCI with a response schema raises -20307 before any request)
  procedure oci_structured_output_unsupported;

  -- tool calling ---------------------------------------------------------------
  --%test(Anthropic offers input_schema tools and sends tool_result blocks in a user turn)
  procedure anthropic_tool_round_trip;

  --%test(Google offers functionDeclarations and sends functionResponse parts)
  procedure google_tool_round_trip;

  --%test(Google sends a raising tool handler's error text back as the tool result)
  procedure google_tool_error_returned_to_model;

  --%test(OpenAI Chat Completions raises -20504 when the model calls an unknown tool)
  procedure openai_chat_unknown_tool_raises;

  --%test(OpenAI Chat Completions declares tool schemas under parameters)
  --%disabled(BUG uc_ai_tools_api.input_schema_key: plain OpenAI Chat Completions gets the Anthropic key input_schema, so the model never sees a tool's parameter schema)
  procedure openai_chat_tool_schema_key;

  --%test(xAI replays the recorded tool round trip and unwraps the parameters wrapper)
  procedure xai_tool_round_trip;

  --%test(Ollama native offers tools and sends tool results with tool_name)
  --%disabled(BUG uc_ai_ollama.pkb process_llm_response: a tool-call turn with empty content raises -20304 "No content to process response" instead of executing the tool)
  procedure ollama_native_tool_round_trip;

  --%test(Mistral uses the parameters key and unwraps wrapped arguments before binding)
  procedure mistral_tool_round_trip;

  -- conversation continuation --------------------------------------------------
  --%test(OpenAI Responses API replays the recorded history as input items, without previous_response_id)
  procedure responses_continue_conversation;

  --%test(Anthropic replays tool history as tool_use and tool_result blocks)
  procedure anthropic_replays_tool_history;

  --%test(Google replays tool history with the functionCall thoughtSignature)
  procedure google_replays_tool_history;

end test_uc_ai_wire_2;
/
