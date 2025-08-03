create or replace package test_uc_ai_ollama as

  --%suite(Ollama AI tests)

  -- Base procedures with model parameter
  procedure basic_recipe(
    p_model in uc_ai.model_type,
    p_base_url in varchar2 default 'host.containers.internal:11434/api',
    p_reasoning_enabled in boolean default true
  );
  procedure tool_user_info(
    p_model in uc_ai.model_type,
    p_base_url in varchar2 default 'host.containers.internal:11434/api',
    p_reasoning_enabled in boolean default true
  );
  procedure tool_clock_in_user(
    p_model in uc_ai.model_type,
    p_base_url in varchar2 default 'host.containers.internal:11434/api',
    p_reasoning_enabled in boolean default true
  );

  -- Test procedures for specific models
  --%test(Basic recipe assistant - Qwen 1.7b)
  procedure basic_recipe_qwen_1b;

  --%test(Basic recipe assistant - Gemma3 4b)
  procedure basic_recipe_gemma_4b;

  --%test(Tool usage - get user info - Qwen 4b)
  procedure tool_user_info_qwen_4b;

  --%test(Tool usage - clock in user - Qwen 4b)
  procedure tool_clock_in_user_qwen_4b;

  --%test(Convert messages)
  procedure convert_messages;

  --%test(image file input)
  procedure image_file_input_gemma_4b;

  --%test(reasoning)
  procedure reasoning;

end test_uc_ai_ollama;
/
