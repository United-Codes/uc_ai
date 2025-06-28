create or replace package uc_ai as

  /*
   * Main interface for AI text generation
   * Routes to OpenAI implementation - could be extended for provider selection
   */
  procedure generate_text (
    p_prompt        in clob
  , p_system_prompt in clob default null
  );

end uc_ai;
/
