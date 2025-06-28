create or replace package uc_ai as

  /*
   * Main interface for AI text generation
   * Routes to OpenAI implementation - could be extended for provider selection
   * 
   * Returns comprehensive result object with:
   * - messages: conversation history (json_array_t)
   * - final_message: last message in conversation (json_object_t)
   * - finish_reason: completion reason (varchar2)
   * - usage: token usage info (json_object_t)
   * - tool_calls_count: number of tool calls executed (number)
   * - model: model used (varchar2)
   * - provider: AI provider used (varchar2)
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_max_tool_calls in pls_integer default null
  ) return json_object_t;

end uc_ai;
/
