create or replace package uc_ai_responses_api as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */


  g_base_url varchar2(255 char);

  -- Reasoning effort levels for Responses API
  -- More info at https://platform.openai.com/docs/guides/reasoning
  g_reasoning_effort varchar2(32 char); -- 'none', 'low', 'medium', 'high', 'xhigh'
  
  -- Reasoning summary verbosity
  g_reasoning_summary varchar2(32 char); -- 'concise', 'detailed', 'auto'

  -- Text verbosity level
  g_text_verbosity varchar2(32 char) := 'medium'; -- 'low', 'medium', 'high'

  -- Whether to store responses for retrieval later (default: true)
  g_store_responses boolean;

  -- Whether to include encrypted reasoning content for ZDR compliance
  g_include_encrypted_reasoning boolean := false;

  -- type: HTTP-Header, credential-name: Authorization, value: Bearer <token>
  g_apex_web_credential varchar2(255 char);


  /*
   * Responses API implementation for text generation
   * 
   * This is the recommended API for building with OpenAI and other providers 
   * that support the Open Responses standard.
   * 
   * Key differences from Chat Completions:
   * - Uses "input" instead of "messages" (but accepts both strings and message arrays)
   * - Returns "output" array of items instead of "choices" with messages
   * - Native support for previous_response_id for multi-turn conversations
   * - Function calls and outputs are separate items with call_id correlation
   * - Supports encrypted reasoning for Zero Data Retention (ZDR) compliance
   * 
   * p_messages: Standard LM message array. System messages become instructions.
   *             To use previous_response_id, include it in providerOptions of any message:
   *             {"type":"text","text":"...","providerOptions":{"previous_response_id":"resp_..."}}
   * p_model: Model to use for generation
   * p_max_tool_calls: Maximum number of tool calls to allow in one request
   * p_schema: Optional JSON schema for structured output
   * p_schema_name: Name for the structured output schema
   * p_strict: Whether to enforce strict schema validation
   * 
   * Returns: JSON object with response data including:
   *   - id: Unique response ID
   *   - output: Array of output items (messages, function calls, reasoning, etc.)
   *   - output_text: Helper field with text from first message (for simple usage)
   *   - usage: Token usage statistics
   *   - model: Model that generated the response
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  , p_schema_name    in varchar2 default 'structured_output'
  , p_strict         in boolean default true
  ) return json_object_t;

end uc_ai_responses_api;
/
