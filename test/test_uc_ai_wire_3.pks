create or replace package test_uc_ai_wire_3 as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Wire-level request and response tests, part 3 (LLM-free))
  --%suitepath(uc_ai)

  -- Continues test_uc_ai_wire and test_uc_ai_wire_2: the same mock transport, the
  -- same recorded samples, the same two assertions per exchange (the request UC AI
  -- built, the result it parsed). Split only for size. The shared helpers and the
  -- hand-written provider responses live in the first two packages.
  --
  -- No test reads uc_ai_get_key: every call names an APEX web credential.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- The event sink. Public because uc_ai.fire_event calls it by name; not a test.
  procedure on_event(
    p_request_id in varchar2
  , p_event_type in varchar2
  , p_event_data in clob
  );

  -- passthrough ----------------------------------------------------------------
  --%test(g_extra_body is merged into the body and reserved keys are ignored)
  procedure extra_body_protects_reserved_keys;

  --%test(Anthropic appends provider tools verbatim and passes server-side blocks through)
  procedure anthropic_provider_tools;

  --%test(OpenAI Responses API sends provider tools without local tools enabled)
  procedure responses_provider_tools;

  --%test(g_base_url replaces the host for every provider that honours it)
  procedure base_url_override;

  -- file inputs ----------------------------------------------------------------
  --%test(OpenAI Chat and Responses send images as data URLs and PDFs as file parts)
  procedure openai_file_inputs;

  --%test(Anthropic sends base64 image and document sources, Google sends inline_data)
  procedure anthropic_google_file_inputs;

  --%test(OCI sends IMAGE and DOCUMENT parts, Ollama sends the images array)
  procedure oci_ollama_file_inputs;

  --%test(Ollama refuses a document instead of sending it as an image)
  procedure ollama_rejects_a_document;

  -- finish reasons -------------------------------------------------------------
  --%test(Anthropic maps max_tokens to length and keeps the partial text)
  procedure anthropic_max_tokens_is_length;

  --%test(Google maps MAX_TOKENS to length and SAFETY to content_filter)
  procedure google_finish_reasons;

  --%test(OpenAI Chat keeps partial text on length and no text on content_filter)
  procedure openai_chat_finish_reasons;

  --%test(A response without usage yields zero token counts, not an error)
  procedure response_without_usage;

  -- reasoning replay -----------------------------------------------------------
  --%test(Anthropic replays a signed thinking block first and drops an unsigned one)
  procedure anthropic_replays_signed_thinking;

  --%test(OpenAI Responses API asks for and replays encrypted reasoning)
  procedure responses_encrypted_reasoning;

  -- embeddings -----------------------------------------------------------------
  --%test(OpenRouter embeddings with several inputs)
  procedure openrouter_embeddings;

  --%test(Google embeddings send task_type and output_dimensionality per request)
  procedure google_embeddings_config;

  --%test(Ollama embeddings request and response)
  procedure ollama_embeddings;

  -- events ---------------------------------------------------------------------
  --%test(The event callback sees tool_call, tool_result, assistant_text and response_complete)
  procedure event_callback_during_tool_round_trip;

end test_uc_ai_wire_3;
/
