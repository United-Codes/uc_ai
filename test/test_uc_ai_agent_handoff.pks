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

end test_uc_ai_agent_handoff;
/
