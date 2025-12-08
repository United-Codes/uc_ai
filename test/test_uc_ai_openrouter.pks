create or replace package test_uc_ai_openrouter as

  --%suite(OpenRouter AI tests)

  --%test(Basic recipe assistant - system prompt and user prompt)
  procedure basic_recipe;

  --%test(Tool usage - get user info)
  procedure tool_user_info;

  --%test(Tool usage - clock in user)
  procedure tool_clock_in_user;

  --%test(Convert messages)
  procedure convert_messages;

  --%test(PDF file input)
  procedure pdf_file_input;

  --%test(image file input)
  procedure image_file_input;

  --%test(reasoning)
  procedure reasoning;

  --%test(reasoning from main package)
  procedure reasoning_main;

  --%test(Structured output)
  procedure structured_output;

  --%test(Embeddings generation)
  procedure embeddings;

  --%test(Embeddings generation with multiple inputs)
  procedure embeddings_multi;

end test_uc_ai_openrouter;
/
