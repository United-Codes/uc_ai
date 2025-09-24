create or replace package uc_ai_google as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */


  -- Google Gemini models
  -- See https://ai.google.dev/gemini-api/docs/models/gemini
  c_model_gemini_2_5_pro        constant uc_ai.model_type := 'gemini-2.5-pro';
  c_model_gemini_2_5_flash      constant uc_ai.model_type := 'gemini-2.5-flash';
  c_model_gemini_2_5_flash_lite constant uc_ai.model_type := 'gemini-2.5-flash-lite-preview-06-17';

  c_model_gemini_2_0_flash        constant uc_ai.model_type := 'gemini-2.0-flash';
  c_model_gemini_2_0_flash_lite   constant uc_ai.model_type := 'gemini-2.0-flash_lite';

  c_model_gemini_1_5_flash            constant uc_ai.model_type := 'gemini-1.5-flash';
  c_model_gemini_1_5_flash_8b         constant uc_ai.model_type := 'gemini-1.5-flash-8b';
  c_model_gemini_1_5_pro              constant uc_ai.model_type := 'gemini-1.5-pro';


  -- Guide the model on the number of thinking tokens to use when generating a response
  -- Min and max values are model-dependent, reasoning can't be disabled with 2.5 Pro
  -- More info at https://ai.google.dev/gemini-api/docs/thinking#set-budget
  g_reasoning_budget pls_integer; -- -1 → dynamic, 0 → no reasoning budget

  /*
   * Google Gemini implementation for text generation 
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  ) return json_object_t;

end uc_ai_google;
/
