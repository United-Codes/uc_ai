create or replace package uc_ai as

  /*
   * Main interface for AI text generation
   * Routes to OpenAI implementation - could be extended for provider selection
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_max_tool_calls in pls_integer default null
  ) return json_array_t;

end uc_ai;
/
