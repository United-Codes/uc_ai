create or replace package test_uc_ai_decisions_live as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Decisions: live OpenAI Decisions and TypeSafe jev API calls)
  --%suitepath(uc_ai)
  --%rollback(manual)

  -- Each test calls the OpenAI Decisions API (model gpt-6-luna) with the APEX web
  -- credential OPENAI, or the TypeSafe jev API (model jev-latest) with the APEX web
  -- credential TYPESAFE_AI. A call costs a few hundred input tokens and no output
  -- tokens (OpenAI), or a fraction of a cent (TypeSafe). A test that cannot reach
  -- the API because the credential is missing
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

  --%test(TypeSafe triage example: a choice, a score and a boolean on one message)
  procedure ts_triage_example;

  --%test(TypeSafe: a bad model name raises -20302 with the vendor message)
  procedure ts_bad_model;

  --%test(Decision agent: a triage run on OpenAI records the tokens on the execution)
  procedure agent_triage_example;

  --%test(Decision agent: a triage run on TypeSafe records the tokens on the execution)
  procedure ts_agent_triage_example;

end test_uc_ai_decisions_live;
/
