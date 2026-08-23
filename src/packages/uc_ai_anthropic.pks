create or replace package uc_ai_anthropic 
  authid definer
as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */


  -- Anthropic Claude models
  -- See https://platform.claude.com/docs/en/about-claude/models/overview
  c_model_claude_5_fable    constant uc_ai.model_type := 'claude-fable-5';
  c_model_claude_5_opus     constant uc_ai.model_type := 'claude-opus-5';
  c_model_claude_5_sonnet   constant uc_ai.model_type := 'claude-sonnet-5';
  c_model_claude_4_5_haiku  constant uc_ai.model_type := 'claude-haiku-4-5';

  c_model_claude_4_8_opus   constant uc_ai.model_type := 'claude-opus-4-8';
  c_model_claude_4_7_opus   constant uc_ai.model_type := 'claude-opus-4-7';

  c_model_claude_4_6_opus   constant uc_ai.model_type := 'claude-opus-4-6';
  c_model_claude_4_6_sonnet constant uc_ai.model_type := 'claude-sonnet-4-6';

  c_model_claude_4_5_opus   constant uc_ai.model_type := 'claude-opus-4-5';
  c_model_claude_4_5_sonnet constant uc_ai.model_type := 'claude-sonnet-4-5';

  -- Anthropic retired these models. Requests to them fail.
  -- They stay here for backward compatibility of code that references the constants.
  -- See https://platform.claude.com/docs/en/about-claude/model-deprecations
  c_model_claude_4_1_opus   constant uc_ai.model_type := 'claude-opus-4-1';
  c_model_claude_4_sonnet   constant uc_ai.model_type := 'claude-sonnet-4-0';
  c_model_claude_3_7_sonnet constant uc_ai.model_type := 'claude-3-7-sonnet-latest';
  c_model_claude_3_5_sonnet constant uc_ai.model_type := 'claude-3-5-sonnet-latest';
  c_model_claude_3_5_haiku  constant uc_ai.model_type := 'claude-3-5-haiku-latest';
  c_model_claude_4_opus     constant uc_ai.model_type := 'claude-opus-4-0';
  c_model_claude_3_opus     constant uc_ai.model_type := 'claude-3-opus-latest';

  g_max_tokens pls_integer := 8192; -- Default maximum tokens for Claude models

  -- Maximum number of tokens Claude is allowed to use for its internal reasoning process
  -- More info at https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking#how-to-use-extended-thinking
  g_reasoning_budget_tokens pls_integer; -- Minimum is 1024

  -- type: HTTP-Header, credential-name: x-api-key
  g_apex_web_credential varchar2(255 char);

  /*
   * Anthropic implementation for text generation
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  , p_settings       in uc_ai_settings.t_settings default null
  ) return json_object_t;


  /*
   * Converts standardized LM messages into Anthropic's messages array, lifting the
   * system prompt out into its own field.
   *
   * Exposed so the request payload can be asserted without an HTTP call (see
   * test_uc_ai_reasoning_replay). Not part of the stable public API - the message
   * shape follows whatever the provider requires and may change.
   */
  procedure convert_lm_messages_to_anthropic(
    p_lm_messages in json_array_t,
    po_system_prompt out nocopy clob,
    po_anthropic_messages out nocopy json_array_t
  );

end uc_ai_anthropic;
/
