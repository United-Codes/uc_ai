create or replace package uc_ai_anthropic as

  -- Anthropic Claude models
  -- See https://docs.anthropic.com/en/docs/about-claude/models
  c_model_claude_4_opus constant uc_ai.model_type := 'claude-opus-4-0';
  c_model_claude_4_sonnet constant uc_ai.model_type := 'claude-sonnet-4-0';

  c_model_claude_3_7_sonnet constant uc_ai.model_type := 'claude-3-7-sonnet-latest';
  c_model_claude_3_5_sonnet constant uc_ai.model_type := 'claude-3-5-sonnet-latest';
  c_model_claude_3_5_haiku  constant uc_ai.model_type := 'claude-3-5-haiku-latest';
  c_model_claude_3_opus     constant uc_ai.model_type := 'claude-3-opus-latest';

  /*
   * Anthropic implementation for text generation with optional system prompt
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
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t;

end uc_ai_anthropic;
/
