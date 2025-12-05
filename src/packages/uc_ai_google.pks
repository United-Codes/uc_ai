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

  -- Embedding models
  -- See https://ai.google.dev/gemini-api/docs/embeddings#model-versions
  c_model_gemini_embedding_001 constant uc_ai.model_type := 'gemini-embedding-001';


  -- Guide the model on the number of thinking tokens to use when generating a response
  -- Min and max values are model-dependent, reasoning can't be disabled with 2.5 Pro
  -- More info at https://ai.google.dev/gemini-api/docs/thinking#set-budget
  g_reasoning_budget pls_integer; -- -1 → dynamic, 0 → no reasoning budget

  -- type: url query string: key=your_api_key
  g_apex_web_credential varchar2(255 char);

  /*
   * Google Gemini implementation for text generation 
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  ) return json_object_t;

  -- Optimize embeddings for a specific task
  -- See https://ai.google.dev/gemini-api/docs/embeddings#supported-task-types for supported types
  g_embedding_task_type varchar2(255 char) := 'SEMANTIC_SIMILARITY';

  -- How many dimensions the embedding output should have
  -- See https://ai.google.dev/gemini-api/docs/embeddings#control-embedding-size for-details
  g_embedding_output_dimensions pls_integer := 1536; -- Default is 1536, other valid values depend on the model used

  /*
   * Google Gemini implementation for embeddings generation
   * 
   * p_input: JSON array of strings to embed
   * p_model: Embedding model to use (e.g., gemini-embedding-001)
   * 
   * Returns: JSON array of embedding arrays (one per input string)
   */
  function generate_embeddings (
    p_input in json_array_t
  , p_model in uc_ai.model_type
  ) return json_array_t;

end uc_ai_google;
/
