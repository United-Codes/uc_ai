create or replace package uc_ai_openai as

  /*
   * Simple interface for text generation with optional system prompt
   * Converts prompt into message format and calls the full conversation handler
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_max_tool_calls in pls_integer
  ) return json_array_t;

end uc_ai_openai;
/
