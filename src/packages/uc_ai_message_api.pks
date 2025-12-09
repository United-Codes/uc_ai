create or replace package uc_ai_message_api as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  -- Content type builders
  function create_text_content(
    p_text in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t;

  function create_file_content(
    p_media_type in varchar2,
    p_data_base64 in clob,
    p_filename in varchar2 default null,
    p_provider_options in json_object_t default null
  ) return json_object_t;

  function create_file_content(
    p_media_type in varchar2,
    p_data_blob in blob,
    p_filename in varchar2 default null,
    p_provider_options in json_object_t default null
  ) return json_object_t;


  function create_reasoning_content(
    p_text in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t;

  function create_tool_call_content(
    p_tool_call_id in varchar2,
    p_tool_name in varchar2,
    p_args in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t;

  function create_tool_result_content(
    p_tool_call_id in varchar2,
    p_tool_name in varchar2,
    p_result in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t;

  -- Message type builders
  function create_system_message(
    p_content in clob
  ) return json_object_t;

  function create_user_message(
    p_content in json_array_t
  ) return json_object_t;

  function create_assistant_message(
    p_content in json_array_t
  ) return json_object_t;

  function create_tool_message(
    p_content in json_array_t
  ) return json_object_t;

  -- Helper functions for common patterns
  function create_simple_user_message(
    p_text in clob
  ) return json_object_t;

  function create_simple_assistant_message(
    p_text in clob
  ) return json_object_t;

end uc_ai_message_api;
/
