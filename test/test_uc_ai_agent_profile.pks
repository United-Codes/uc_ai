create or replace package test_uc_ai_agent_profile as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Profile Agent Tests)
  --%suitepath(uc_ai.agents)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Create and execute a simple profile agent)
  procedure execute_profile_agent;

  --%test(Execute profile agent with input parameters)
  procedure execute_with_parameters;

  --%test(Continue conversation with follow-up message)
  procedure execute_follow_up_message;

  --%test(Follow-up without session_id raises error)
  --%throws(-20503)
  procedure follow_up_no_session_error;

  --%test(Follow-up on non-existent session raises error)
  --%throws(-20503)
  procedure follow_up_no_prior_exec_error;

end test_uc_ai_agent_profile;
/
