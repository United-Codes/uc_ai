create or replace package test_uc_ai_reentrancy as

  --%suite(Provider generate_text is isolated from global-state changes mid-call)
  --%suitepath(uc_ai)
  --%rollback(manual)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  -- Tool body: sabotage the config globals to simulate a nested agent that ran
  -- reset_globals + apply_model_config while the parent's tool loop is suspended.
  function sabotage return clob;

  --%test(OpenAI chat loop continues correctly after a tool rewrites the globals)
  procedure globals_sabotaged_mid_call;

end test_uc_ai_reentrancy;
/
