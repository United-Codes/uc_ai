create or replace package test_uc_ai_anthropic as

  --%suite(Anthropic AI tests)

  --%test(Basic recipe assistant - system prompt and user prompt)
  procedure basic_recipe;

  --%test(Tool usage - get user info)
  procedure tool_user_info;

  --%test(Tool usage - clock in user)
  procedure tool_clock_in_user;

  --%test(Convert messages)
  procedure convert_messages;

end test_uc_ai_anthropic;
/
