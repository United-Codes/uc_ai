create or replace package body uc_ai_message_api as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */

  -- Content type builders
  function create_text_content(
    p_text in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t is
    l_content json_object_t;
  begin
    l_content := json_object_t();
    l_content.put('type', 'text');
    l_content.put('text', p_text);
    if p_provider_options is not null then
      l_content.put('providerOptions', p_provider_options);
    end if;

    return l_content;
  end create_text_content;

  function create_file_content(
    p_media_type in varchar2,
    p_data in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t is
    l_content json_object_t;
  begin
    l_content := json_object_t();
    l_content.put('type', 'file');
    l_content.put('mediaType', p_media_type);
    l_content.put('data', p_data);
    
    if p_provider_options is not null then
      l_content.put('providerOptions', p_provider_options);
    end if;
    
    return l_content;
  end create_file_content;

  function create_reasoning_content(
    p_text in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t is
    l_content json_object_t;
  begin
    l_content := json_object_t();
    l_content.put('type', 'reasoning');
    l_content.put('text', p_text);
    
    if p_provider_options is not null then
      l_content.put('providerOptions', p_provider_options);
    end if;
    
    return l_content;
  end create_reasoning_content;

  function create_tool_call_content(
    p_tool_call_id in varchar2,
    p_tool_name in varchar2,
    p_args in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t is
    l_content json_object_t;
  begin
    l_content := json_object_t();
    l_content.put('type', 'tool_call');
    l_content.put('toolCallId', p_tool_call_id);
    l_content.put('toolName', p_tool_name);
    l_content.put('args', p_args);
    
    if p_provider_options is not null then
      l_content.put('providerOptions', p_provider_options);
    end if;
    
    return l_content;
  end create_tool_call_content;

  function create_tool_result_content(
    p_tool_call_id in varchar2,
    p_tool_name in varchar2,
    p_result in clob,
    p_provider_options in json_object_t default null
  ) return json_object_t is
    l_content json_object_t;
  begin
    l_content := json_object_t();
    l_content.put('type', 'tool_result');
    l_content.put('toolCallId', p_tool_call_id);
    l_content.put('toolName', p_tool_name);
    l_content.put('result', p_result);
    
    if p_provider_options is not null then
      l_content.put('providerOptions', p_provider_options);
    end if;
    
    return l_content;
  end create_tool_result_content;

  -- Message type builders
  function create_system_message(
    p_content in clob
  ) return json_object_t is
    l_message json_object_t;
  begin
    l_message := json_object_t();
    l_message.put('role', 'system');
    l_message.put('content', p_content);
    return l_message;
  end create_system_message;

  function create_user_message(
    p_content in json_array_t
  ) return json_object_t is
    l_message json_object_t;
  begin
    l_message := json_object_t();
    l_message.put('role', 'user');
    l_message.put('content', p_content);
    return l_message;
  end create_user_message;

  function create_assistant_message(
    p_content in json_array_t
  ) return json_object_t is
    l_message json_object_t;
  begin
    l_message := json_object_t();
    l_message.put('role', 'assistant');
    l_message.put('content', p_content);
    return l_message;
  end create_assistant_message;

  function create_tool_message(
    p_content in json_array_t
  ) return json_object_t is
    l_message json_object_t;
  begin
    l_message := json_object_t();
    l_message.put('role', 'tool');
    l_message.put('content', p_content);
    return l_message;
  end create_tool_message;

  -- Helper functions for common patterns
  function create_simple_user_message(
    p_text in clob
  ) return json_object_t is
    l_content_array json_array_t;
    l_text_content json_object_t;
  begin
    l_content_array := json_array_t();
    l_text_content := create_text_content(p_text);
    l_content_array.append(l_text_content);
    return create_user_message(l_content_array);
  end create_simple_user_message;

  function create_simple_assistant_message(
    p_text in clob
  ) return json_object_t is
    l_content_array json_array_t;
    l_text_content json_object_t;
  begin
    l_content_array := json_array_t();
    l_text_content := create_text_content(p_text);
    l_content_array.append(l_text_content);
    return create_assistant_message(l_content_array);
  end create_simple_assistant_message;

end uc_ai_message_api;
/
