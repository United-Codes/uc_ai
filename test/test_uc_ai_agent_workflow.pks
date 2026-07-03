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
  -- currently not working/ check if it makes sense to fix
  procedure execute_loop_workflow;

  --%test(Execute a loop workflow with pre step)
  procedure execute_loop_workflow_better;

  --%test(Execute a conditional workflow - only the step with a matching condition runs)
  procedure execute_conditional_workflow;

  --%test(Conditional workflow completes with zero iterations when no condition matches)
  procedure conditional_workflow_all_skipped;

  --%test(Creating a workflow with a non-string condition is rejected)
  procedure conditional_rejects_object_cond;

end test_uc_ai_agent_workflow;
/
