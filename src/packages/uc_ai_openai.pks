create or replace package uc_ai_openai as

  /*
   * OpenAI implementation for text generation with optional system prompt
   * Converts prompt into message format and calls the full conversation handler
   * 
   * Returns comprehensive result object with:
   * - messages: conversation history (json_array_t)
   * - finish_reason: completion reason (varchar2)
   * - usage: token usage info (json_object_t)
   * - tool_calls_count: number of tool calls executed (number)
   * - model: model used (varchar2)
   * - provider: AI provider used (varchar2)
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_max_tool_calls in pls_integer
  ) return json_object_t;

end uc_ai_openai;
/
