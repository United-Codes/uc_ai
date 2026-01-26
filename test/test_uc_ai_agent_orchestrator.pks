create or replace package test_uc_ai_agent_orchestrator as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Orchestrator Agent Tests)
  --%suitepath(uc_ai.agents)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Execute orchestrator that routes to math or geography agent)
  procedure execute_orchestrator_routing;

end test_uc_ai_agent_orchestrator;
/
