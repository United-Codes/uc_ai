create or replace package test_uc_ai_agent_integration as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent Integration Tests - Nested Agents)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Orchestrator calls workflow that calls profile agents)
  procedure execute_nested_orchestrator_workflow;

  --%test(Workflow calls another workflow in sequence)
  procedure execute_workflow_calling_workflow;

  --%test(Summarize strategy invokes summarizer agent and builds summary + recent)
  procedure history_summarize_calls_agent;

end test_uc_ai_agent_integration;
/
