create or replace package test_uc_ai_oci as

  --%suite(UC AI Oracle Cloud Infrastructure Tests)

  --%test(Basic recipe generation with OCI in Generic Mode)
  procedure basic_recipe_generic;

  --%test(Continue conversations with OCI in Generic Mode)
  procedure continue_conversation_generic;

  --%test(Tool usage - get user info in Generic Mode)
  procedure tool_user_info_generic;

  --%test(Tool usage - clock in user in Generic Mode)
  procedure tool_clock_in_user_generic;

  --%test(Basic recipe generation with OCI in Cohere Mode)
  procedure basic_recipe_cohere;

  --%test(Continue conversations with OCI in Cohere Mode)
  procedure continue_conversation_cohere;

end test_uc_ai_oci;
/
