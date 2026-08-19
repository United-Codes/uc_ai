create or replace package uc_ai_message_api 
  authid definer
as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  -- File input type: pass one or more files (documents/images) to a message.
  -- Users build a collection with t_files() and .extend, e.g.:
  --   l_files := uc_ai_message_api.t_files();
  --   l_files.extend;
  --   l_files(1).media_type := 'application/pdf';
  --   l_files(1).data_blob  := <your blob>;
  --   l_files(1).filename   := 'doc.pdf';
  type t_file is record (
    media_type       varchar2(255 char),
    data_blob        blob,
    filename         varchar2(4000 char),
    provider_options json_object_t
  );
  type t_files is table of t_file;

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

  -- Builds a user message from optional text plus a collection of files.
  -- When p_files is null/empty this is equivalent to create_simple_user_message.
  function create_user_message(
    p_text  in clob,
    p_files in t_files
  ) return json_object_t;

  function create_simple_assistant_message(
    p_text in clob
  ) return json_object_t;

end uc_ai_message_api;
/
