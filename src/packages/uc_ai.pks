create or replace package uc_ai as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  c_version     constant varchar2(16 char) := '25.7';
  c_version_num constant number := 20250700;

  subtype provider_type is varchar2(64 char);
  c_provider_openai     constant provider_type := 'openai';
  c_provider_anthropic  constant provider_type := 'anthropic';
  c_provider_google     constant provider_type := 'google';
  c_provider_ollama     constant provider_type := 'ollama';
  c_provider_oci        constant provider_type := 'oci';
  c_provider_xai        constant provider_type := 'xai';
  c_provider_openrouter constant provider_type := 'openrouter';

  subtype model_type is varchar2(128 char);

  subtype finish_reason_type is varchar2(64 char);

  c_finish_reason_tool_calls     constant finish_reason_type := 'tool_calls';
  c_finish_reason_stop           constant finish_reason_type := 'stop';
  c_finish_reason_length         constant finish_reason_type := 'length';
  c_finish_reason_content_filter constant finish_reason_type := 'content_filter';

  -- general global settings
  g_base_url varchar2(4000 char);

  -- reasoning level constants
  c_reasoning_level_low    constant varchar2(10 char) := 'low';
  c_reasoning_level_medium constant varchar2(10 char) := 'medium';
  c_reasoning_level_high   constant varchar2(10 char) := 'high';

  -- reasoning global settings
  g_enable_reasoning boolean := false;
  g_reasoning_level varchar2(10 char); -- use c_reasoning_level_* constants

  -- tools relevant global settings
  g_enable_tools boolean := false;
  g_tool_tags apex_t_varchar2;

  -- global settings for APEX Web Credentials
  g_apex_web_credential varchar2(255 char);

  -- internal use only
  g_provider_override varchar2(4000 char);

  e_max_calls_exceeded exception;
  pragma exception_init(e_max_calls_exceeded, -20301);
  e_error_response exception;
  pragma exception_init(e_error_response, -20302);
  e_unhandled_format exception;
  pragma exception_init(e_unhandled_format, -20303);
  e_format_processing_error exception;
  pragma exception_init(e_format_processing_error, -20304);
  e_model_not_found_error exception;
  pragma exception_init(e_model_not_found_error, -20305);

  /*
   * Main interface for AI text generation
   * Routes to OpenAI implementation - could be extended for provider selection
   * 
   * See https://www.united-codes.com/products/uc-ai/docs/api/generate_text/ for API documentation
   */
  function generate_text (
    p_user_prompt           in clob
  , p_system_prompt         in clob default null
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t;

  function generate_text (
    p_messages              in json_array_t
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t;

  function generate_embeddings (
    p_input in json_array_t
  , p_provider in provider_type
  , p_model in model_type
  ) return json_array_t;

end uc_ai;
/
