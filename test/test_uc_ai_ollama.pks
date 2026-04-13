create or replace package test_uc_ai_ollama as

  --%suite(Ollama AI tests)

  --%test(Basic recipe assistant)
  procedure basic_recipe;

  --%test(Tool usage - get user info)
  procedure tool_user_info;

  --%test(Tool usage - clock in user)
  procedure tool_clock_in_user;

  --%test(Basic recipe assistant - Responses API)
  procedure basic_recipe_responses_api;

  --%test(Tool usage - get user info - Responses API)
  procedure tool_user_info_responses_api;

  --%test(Tool usage - clock in user - Responses API)
  procedure tool_clock_in_responses_api;

  --%test(Convert messages)
  procedure convert_messages;

  --%test(Embeddings)
  procedure embeddings;

  --%test(Embeddings generation with multiple inputs)
  procedure embeddings_multi;

end test_uc_ai_ollama;
/
