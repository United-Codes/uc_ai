create or replace package uc_ai as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */

  subtype provider_type is varchar2(64 char);
  c_provider_openai    constant provider_type := 'openai';
  c_provider_anthropic constant provider_type := 'anthropic';
  c_provider_google    constant provider_type := 'google';
  c_provider_ollama    constant provider_type := 'ollama';

  subtype model_type is varchar2(128 char);

  subtype finish_reason_type is varchar2(64 char);

  c_finish_reason_tool_calls     constant finish_reason_type := 'tool_calls';
  c_finish_reason_stop           constant finish_reason_type := 'stop';
  c_finish_reason_length         constant finish_reason_type := 'length';
  c_finish_reason_content_filter constant finish_reason_type := 'content_filter';

  -- general global settings
  g_base_url varchar2(4000 char);

  -- reasoning global settings
  g_enable_reasoning boolean := false;

  -- tools relevant global settings
  g_enable_tools boolean := true;


  e_max_calls_exceeded exception;
  pragma exception_init(e_max_calls_exceeded, -20301);
  e_error_response exception;
  pragma exception_init(e_error_response, -20302);
  e_unhandled_format exception;
  pragma exception_init(e_unhandled_format, -20303);
  e_format_processing_error exception;
  pragma exception_init(e_format_processing_error, -20304);

  /*
   * Main interface for AI text generation
   * Routes to OpenAI implementation - could be extended for provider selection
   * 
   * See https://www.united-codes.com/products/uc-ai/docs/api/generate_text/ for API documentation
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_provider       in provider_type
  , p_model          in model_type
  , p_max_tool_calls in pls_integer default null
  ) return json_object_t;

  function generate_text (
    p_messages       in json_array_t
  , p_provider       in provider_type
  , p_model          in model_type
  , p_max_tool_calls in pls_integer default null
  ) return json_object_t;

end uc_ai;
/
