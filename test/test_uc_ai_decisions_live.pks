create or replace package test_uc_ai_decisions_live as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Decisions: live OpenAI Decisions API calls)
  --%suitepath(uc_ai)

  -- Each test calls the OpenAI Decisions API (model gpt-6-luna) with the APEX web
  -- credential OPENAI. A call costs a few hundred input tokens and no output
  -- tokens. A test that cannot reach the API because the credential is missing
  -- prints a skip message and returns without an expectation. Any other error,
  -- and any wrong answer, still fails the test. The request and response
  -- mapping is tested without a network in test_uc_ai_decisions_wire.

  --%beforeeach
  procedure reset_state;

  --%test(Triage example: a choice, a score and a boolean on one message)
  procedure triage_example;

  --%test(An image: a boolean and a choice about a picture)
  procedure image_question;

  --%test(A bad model name raises -20302 with the provider message)
  procedure bad_model;

end test_uc_ai_decisions_live;
/
