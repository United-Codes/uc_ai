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

  --%test(Execute AI-driven conversation between multiple agents)
  procedure execute_ai_driven_conversation;

end test_uc_ai_agent_conversation;
/
