create or replace package test_uc_ai_agent_conversation as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Conversation Agent Tests)
  --%suitepath(uc_ai.agents)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Execute round-robin conversation between two agents)
  procedure execute_round_robin_conversation;

  --%test(Conversation terminates after max turns)
  procedure execute_max_turns_conversation;

end test_uc_ai_agent_conversation;
/
