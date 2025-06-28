create or replace package uc_ai_openai as

  /*
   * Simple interface for text generation with optional system prompt
   * Converts prompt into message format and calls the full conversation handler
   */
  procedure generate_text (
    p_prompt        in clob
  , p_system_prompt in clob default null
  );

end uc_ai_openai;
/
