create or replace package test_uc_ai_agent_checkpoint as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent Execution Checkpoint Tests)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(checkpoint_execution writes state and never raises for unknown executions)
  procedure checkpoint_execution_direct;

  --%test(Successful workflow clears current_state and keeps output_result)
  procedure checkpoint_cleared_on_success;

  --%test(Failed workflow keeps the last step checkpoint in current_state)
  procedure checkpoint_survives_failure;

end test_uc_ai_agent_checkpoint;
/
