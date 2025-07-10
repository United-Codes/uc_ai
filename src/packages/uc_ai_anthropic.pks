create or replace package uc_ai_anthropic as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */


  -- Anthropic Claude models
  -- See https://docs.anthropic.com/en/docs/about-claude/models
  c_model_claude_4_opus constant uc_ai.model_type := 'claude-opus-4-0';
  c_model_claude_4_sonnet constant uc_ai.model_type := 'claude-sonnet-4-0';

  c_model_claude_3_7_sonnet constant uc_ai.model_type := 'claude-3-7-sonnet-latest';
  c_model_claude_3_5_sonnet constant uc_ai.model_type := 'claude-3-5-sonnet-latest';
  c_model_claude_3_5_haiku  constant uc_ai.model_type := 'claude-3-5-haiku-latest';
  c_model_claude_3_opus     constant uc_ai.model_type := 'claude-3-opus-latest';

  /*
   * Anthropic implementation for text generation
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t;

end uc_ai_anthropic;
/
