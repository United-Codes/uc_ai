create or replace package test_uc_ai_decisions as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Decisions: checks before any request (LLM-free))
  --%suitepath(uc_ai)

  -- Every test runs uc_ai.decide with input that has to fail before a request is
  -- sent. The mock transport is registered with an empty queue and each test
  -- asserts that it saw no request: a check that moved behind the HTTP call would
  -- fail there. The request and response mapping is in test_uc_ai_decisions_wire,
  -- the real API calls are in test_uc_ai_decisions_live.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- provider ---------------------------------------------------------------------
  --%test(A null, unknown or chat-only provider raises -20306 and names the decision providers)
  procedure unknown_provider;

  --%test(The provider is checked before the questions)
  procedure provider_before_questions;

  --%test(Valid input reaches the transport)
  procedure valid_input_reaches_transport;

  -- questions --------------------------------------------------------------------
  --%test(A bad question id raises -20503)
  procedure bad_question_id;

  --%test(Null, empty and not-an-object questions raise -20503)
  procedure questions_null_or_empty;

  --%test(A missing or unknown type raises -20503, also the wire names predicate and noul)
  procedure bad_question_type;

  --%test(Missing, null, empty and blank instructions raise -20503)
  procedure bad_instructions;

  --%test(Choice criteria that are missing, of the wrong type, empty or one option raise -20503)
  procedure bad_choice_criteria;

  --%test(Score criteria that are missing, of the wrong type, empty or one level raise -20503)
  procedure bad_score_criteria;

  --%test(Boolean criteria with another key or a non-string value raise -20503)
  procedure bad_boolean_criteria;

  --%test(More than 255 options or 10 levels raise -20508; 255 and 10 work, see the wire tests)
  procedure provider_limits;

  -- state and files -------------------------------------------------------------
  --%test(An empty state without files raises -20503)
  procedure empty_state;

  --%test(A media type the provider cannot take raises -20508 and names the supported ones)
  procedure unsupported_media_type;

  --%test(A file object of another shape raises -20503)
  procedure bad_file_shape;

  -- options -------------------------------------------------------------------------
  --%test(An option of the wrong type raises -20503)
  procedure bad_options;

end test_uc_ai_decisions;
/
