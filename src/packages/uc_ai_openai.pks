create or replace package uc_ai_openai as

  -- get from https://platform.openai.com/docs/pricing
  c_model_gpt_4_5 constant uc_ai.model_type := 'gpt-4.5-preview';
  c_model_gpt_4_1 constant uc_ai.model_type := 'gpt-4.1';
  c_model_gpt_4_1_mini constant uc_ai.model_type := 'gpt-4.1-mini';
  c_model_gpt_4_1_mini constant uc_ai.model_type := 'gpt-4.1-nano';
  c_model_gpt_4o constant uc_ai.model_type := 'gpt-4o';
  c_model_gpt_4o_mini constant uc_ai.model_type := 'gpt-4o-mini';

  c_model_gpt_o1 constant uc_ai.model_type := 'o1';
  c_model_gpt_o1_pro constant uc_ai.model_type := 'o1-pro';
  c_model_gpt_o1_mini constant uc_ai.model_type := 'o1-mini';
  c_model_gpt_o3 constant uc_ai.model_type := 'o3';
  c_model_gpt_o3_pro constant uc_ai.model_type := 'o3-pro';
  c_model_gpt_o3_deep_research constant uc_ai.model_type := 'o3-deep-research';
  c_model_gpt_o3_mini constant uc_ai.model_type := 'o3-mini';
  c_model_gpt_o4_mini constant uc_ai.model_type := 'o4-mini';
  c_model_gpt_o4_mini_deep_research constant uc_ai.model_type := 'o4-mini-deep-research';

  c_model_chatgpt_4o constant uc_ai.model_type := 'chatgpt-4o-latest';
  c_model_gpt_4_turbo constant uc_ai.model_type := 'gpt-4-turbo';
  c_model_gpt_4 constant uc_ai.model_type := 'gpt-4';
  c_model_gpt_4_32k constant uc_ai.model_type := 'gpt-4-32k';
  c_model_gpt_3_5_turbo constant uc_ai.model_type := 'gpt-3.5-turbo';

  /*
   * OpenAI implementation for text generation with optional system prompt
   * Converts prompt into message format and calls the full conversation handler
   * 
   * Returns comprehensive result object with:
   * - messages: conversation history (json_array_t)
   * - finish_reason: completion reason (varchar2)
   * - usage: token usage info (json_object_t)
   * - tool_calls_count: number of tool calls executed (number)
   * - model: model used (varchar2)
   * - provider: AI provider used (varchar2)
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t;

end uc_ai_openai;
/
