create or replace package uc_ai as

  subtype finish_reason_type is varchar2(64 char);

  c_finish_reason_tool_calls     constant finish_reason_type := 'tool_calls';
  c_finish_reason_stop           constant finish_reason_type := 'stop';
  c_finish_reason_length         constant finish_reason_type := 'length';
  c_finish_reason_content_filter constant finish_reason_type := 'content_filter';


  e_max_calls_exceeded exception;
  pragma exception_init(e_max_calls_exceeded, -28301);
  e_error_response exception;
  pragma exception_init(e_error_response, -28302);

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
