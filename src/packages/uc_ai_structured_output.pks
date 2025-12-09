create or replace package uc_ai_structured_output as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  /*
   * Convert a standard JSON schema to OpenAI format for structured output
   * 
   * p_schema: Standard JSON schema as json_object_t
   * p_name: Optional name for the schema (required for OpenAI)
   * p_strict: Whether to use strict mode (OpenAI-specific)
   * 
   * Returns: OpenAI-formatted response_format object
   */
  function to_openai_format(
    p_schema in json_object_t,
    p_name in varchar2 default 'structured_output',
    p_strict in boolean default true
  ) return json_object_t;

  /*
   * Convert a standard JSON schema to Google Gemini format for structured output
   * 
   * p_schema: Standard JSON schema as json_object_t
   * 
   * Returns: Google-formatted responseSchema object
   */
  function to_google_format(
    p_schema in json_object_t
  ) return json_object_t;

  /*
   * Convert a standard JSON schema to Ollama format for structured output
   * 
   * p_schema: Standard JSON schema as json_object_t
   * 
   * Returns: Ollama-formatted format object (directly uses the schema)
   */
  function to_ollama_format(
    p_schema in json_object_t
  ) return json_object_t;

  /*
   * Generic function to convert schema based on provider
   * 
   * p_schema: Standard JSON schema as json_object_t
   * p_provider: AI provider ('openai', 'google', 'ollama')
   * p_name: Optional name for the schema (used by OpenAI)
   * p_strict: Whether to use strict mode (OpenAI-specific)
   * 
   * Returns: Provider-specific formatted schema
   */
  function format_schema(
    p_schema in json_object_t,
    p_provider in uc_ai.provider_type,
    p_name in varchar2 default 'structured_output',
    p_strict in boolean default true
  ) return json_object_t;

end uc_ai_structured_output;
/
