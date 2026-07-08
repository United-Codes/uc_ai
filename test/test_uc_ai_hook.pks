create or replace package test_uc_ai_hook as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent execution hook tests (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- LLM-free tests for the generic execution-hook mechanism in
  -- uc_ai_agents_api (set_execution_hook + before_execution/after_execution
  -- dispatch). All cases abort before any generate_text call: the veto tests
  -- stop in before_execution, and the failure tests stop when a profile agent
  -- references a non-existent prompt profile (prepare_profile_context raises
  -- before the HTTP request).

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%beforeeach
  procedure before_each;

  --%aftereach
  procedure after_each;

  --%test(before_execution raising vetoes the run before any execution row is created)
  procedure veto_blocks_execution;

  --%test(before_execution receives the caller context)
  procedure before_receives_context;

  --%test(after_execution fires with failed status when the run fails)
  procedure after_fires_on_failure;

  --%test(an error raised by after_execution is swallowed, not propagated)
  procedure after_error_is_swallowed;

  --%test(clearing the hook override stops dispatch)
  procedure cleared_hook_not_called;

end test_uc_ai_hook;
/
