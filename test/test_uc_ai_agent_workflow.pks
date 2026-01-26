create or replace package test_uc_ai_agent_workflow as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Workflow Agent Tests)
  --%suitepath(uc_ai.agents)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Execute a sequential workflow with two profile agents)
  procedure execute_sequential_workflow;

  --%test(Execute a loop workflow with max iterations)
  procedure execute_loop_workflow;

  --%test(Execute a loop workflow with pre step)
  procedure execute_loop_workflow_better;

end test_uc_ai_agent_workflow;
/
