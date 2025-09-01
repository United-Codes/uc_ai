create or replace package uc_ai_ollama as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */

  -- See https://ollama.com/library for available models

  /*
   * Ollama implementation for text generation
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  ) return json_object_t;

end uc_ai_ollama;
/
