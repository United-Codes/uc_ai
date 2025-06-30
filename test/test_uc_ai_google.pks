create or replace package test_uc_ai_google as

  --%suite(UC AI Google Tests)
  
  --%test(Basic recipe generation with Google Gemini)
  procedure basic_recipe;

  --%test(Tool usage - get user info)
  procedure tool_user_info;

  --%test(Tool usage - clock in user)
  procedure tool_clock_in_user;

end test_uc_ai_google;
/
