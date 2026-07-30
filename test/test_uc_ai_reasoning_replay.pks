create or replace package test_uc_ai_reasoning_replay as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Reasoning replay into provider request payloads)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for the normalized -> provider direction of reasoning
  -- content: what each convert_lm_messages_to_* emits when a conversation that
  -- already contains reasoning is replayed on a follow-up turn.
  --
  -- Regression origin: a follow-up turn against the OpenAI Responses API failed with
  --   ORA-20302 ... HTTP 400 ... Missing required parameter: 'input[1].summary'
  -- because the reasoning item was rebuilt without the required summary array,
  -- without its rs_... id, and with an illegal top-level 'text' field.

  --%beforeeach
  procedure setup_tests;

  --%aftereach
  procedure reset_globals;

  -- OpenAI Responses API (also serves xAI and OpenRouter)
  --%test(Responses API always emits the required summary array, never a top-level text)
  procedure resp_reasoning_emits_summary;

  --%test(Responses API turns reasoning text into a summary_text entry)
  procedure resp_reasoning_summary_from_text;

  --%test(Responses API drops a reasoning item the provider cannot reconstitute)
  procedure resp_reasoning_dropped_unreplayable;

  --%test(Responses API keeps an id-only reasoning item when store is enabled)
  procedure resp_reasoning_kept_when_stored;

  --%test(Responses API replays the exact history that produced the input[1].summary error)
  procedure resp_replays_exec_342_history;

  -- Anthropic extended thinking
  --%test(Anthropic replays a signed thinking block first in the content array)
  procedure anthropic_thinking_replayed;

  --%test(Anthropic drops an unsigned thinking block)
  procedure anthropic_thinking_needs_signature;

  --%test(Anthropic replays a redacted_thinking block verbatim)
  procedure anthropic_redacted_thinking_replayed;

  -- Google thought signatures
  --%test(Google replays thoughtSignature on the functionCall part)
  procedure google_signature_on_function_call;

  --%test(Google drops a thought part that carries no signature)
  procedure google_thought_needs_signature;

  --%test(Google parsing does not strip text out of the raw part it was given)
  procedure google_parse_does_not_alias;

  -- Ollama
  --%test(Ollama replays reasoning as thinking on the assistant message)
  procedure ollama_thinking_replayed;

  -- OCI
  --%test(OCI Cohere does not turn a reasoning item into a CHATBOT turn)
  procedure oci_cohere_reasoning_not_chatbot;

  --%test(OCI Cohere does not raise on reasoning alongside a tool call)
  procedure oci_cohere_reasoning_with_tool_call;

end test_uc_ai_reasoning_replay;
/
