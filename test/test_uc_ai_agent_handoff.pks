create or replace package test_uc_ai_agent_handoff as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Handoff Agent Tests)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Routes a product question to the product specialist via transfer tool)
  procedure route_product_question;

  --%test(Routes a shipping question to the shipping specialist)
  procedure route_shipping_question;

  --%test(Routes a customer account question to the customer specialist)
  procedure route_customer_question;

  --%test(Triage answers greetings directly without any handoff)
  procedure direct_answer_no_handoff;

  --%test(Hop at max_handoffs runs without transfer tools and must answer)
  procedure max_handoffs_guard;

  -- Multi-level routing (can_transfer_to graph) --------------------------------

  --%test(Tech question routes two levels: triage -> product support -> technician)
  procedure multi_level_tech_question;

  --%test(Returns question routes two levels: triage -> shipping -> return policy)
  procedure multi_level_returns_question;

  --%test(Mid-level agent answers itself without descending further)
  procedure mid_level_answers_itself;

  -- Sticky multi-turn (follow_up_message) --------------------------------------

  --%test(Follow-up turn resumes with the agent that answered the previous turn)
  procedure sticky_follow_up_same_agent;

  --%test(Follow-up turn can transfer onward when the topic changes)
  procedure sticky_follow_up_with_transfer;

end test_uc_ai_agent_handoff;
/
