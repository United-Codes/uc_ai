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

  --%test(PDF file input)
  procedure pdf_file_input;

  --%test(image file input)
  procedure image_file_input;

  --%test(reasoning)
  procedure reasoning;

  --%test(reasoning from main package)
  procedure reasoning_main;

  --%test(Basic text generation with APEX web credential)
  procedure basic_web_credential;


end test_uc_ai_anthropic;
/
