create or replace package uc_ai_openai as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */


  -- get from https://platform.openai.com/docs/pricing
  c_model_gpt_5 constant uc_ai.model_type := 'gpt-5';
  c_model_gpt_4_5 constant uc_ai.model_type := 'gpt-4.5-preview';
  c_model_gpt_4_1 constant uc_ai.model_type := 'gpt-4.1';
  c_model_gpt_4_1_mini constant uc_ai.model_type := 'gpt-4.1-mini';
  c_model_gpt_4_1_nano constant uc_ai.model_type := 'gpt-4.1-nano';
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

  -- How many reasoning tokens to generate before creating a response
  -- More info at https://platform.openai.com/docs/guides/reasoning?api-mode=responses
  g_reasoning_effort varchar2(32 char) := 'low'; -- 'low', 'medium', 'high'

  /*
   * OpenAI implementation for text generation
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  , p_schema_name    in varchar2 default 'structured_output'
  , p_strict         in boolean default true
  ) return json_object_t;

end uc_ai_openai;
/
