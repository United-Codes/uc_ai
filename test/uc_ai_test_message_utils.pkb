create or replace package body uc_ai_test_message_utils as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  g_has_reasoning_content boolean := false;

  procedure validate_text_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  )
  as
    l_text varchar2(32767 char);
  begin
    -- Text content should have 'text' field
    ut.expect(p_content_item.has('text'), 
             p_test_name || ': Text content ' || p_content_index || ' in message ' || p_message_index || ' should have text field').to_be_true();
    --sys.dbms_output.put_line('Validating text content: ' || p_content_item.to_string);
    
    l_text := p_content_item.get_string('text');
    ut.expect(l_text, 
             p_test_name || ': Text content ' || p_content_index || ' in message ' || p_message_index || ' text should not be null').to_be_not_null();
  end validate_text_content;

  procedure validate_file_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  )
  as
    l_media_type varchar2(100 char);
    l_data clob;
  begin
    -- File content should have 'mediaType' field
    ut.expect(p_content_item.has('mediaType'), 
             p_test_name || ': File content ' || p_content_index || ' in message ' || p_message_index || ' should have mediaType field').to_be_true();
    
    -- File content should have 'data' field
    ut.expect(p_content_item.has('data'), 
             p_test_name || ': File content ' || p_content_index || ' in message ' || p_message_index || ' should have data field').to_be_true();
    
    l_media_type := p_content_item.get_string('mediaType');
    ut.expect(l_media_type, 
             p_test_name || ': File content ' || p_content_index || ' in message ' || p_message_index || ' mediaType should not be null').to_be_not_null();
    
    l_data := p_content_item.get_clob('data');
    ut.expect(l_data, 
             p_test_name || ': File content ' || p_content_index || ' in message ' || p_message_index || ' data should not be null').to_be_not_null();
  end validate_file_content;

  procedure validate_reasoning_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  )
  as
    l_text varchar2(32767 char);
    l_provider_options json_object_t;
    l_has_encrypted_content boolean := false;
  begin
    -- Reasoning content should have 'text' field
    ut.expect(p_content_item.has('text'), 
             p_test_name || ': Reasoning content ' || p_content_index || ' in message ' || p_message_index || ' should have text field').to_be_true();
    

    if p_content_item.has('providerOptions') then
      l_provider_options := treat(p_content_item.get('providerOptions') as json_object_t);
      if l_provider_options.has('encrypted_content') and not l_provider_options.get('encrypted_content').is_null then
        l_has_encrypted_content := true;
      end if;
    end if;

    if not l_has_encrypted_content then
      l_text := p_content_item.get_string('text');
      ut.expect(l_text, 
              p_test_name || ': Reasoning content ' || p_content_index || ' in message ' || p_message_index || ' text should not be null').to_be_not_null();
    end if;
  end validate_reasoning_content;

  procedure validate_tool_call_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  )
  as
    l_tool_call_id varchar2(100 char);
    l_tool_name varchar2(100 char);
    l_args clob;
  begin
    -- Tool call content should have required fields
    ut.expect(p_content_item.has('toolCallId'), 
             p_test_name || ': Tool call content ' || p_content_index || ' in message ' || p_message_index || ' should have toolCallId field').to_be_true();
    
    ut.expect(p_content_item.has('toolName'), 
             p_test_name || ': Tool call content ' || p_content_index || ' in message ' || p_message_index || ' should have toolName field').to_be_true();
    
    ut.expect(p_content_item.has('args'), 
             p_test_name || ': Tool call content ' || p_content_index || ' in message ' || p_message_index || ' should have args field').to_be_true();
    
    l_tool_call_id := p_content_item.get_string('toolCallId');
    l_tool_name := p_content_item.get_string('toolName');
    l_args := p_content_item.get_clob('args');
    
    ut.expect(l_tool_call_id, 
             p_test_name || ': Tool call content ' || p_content_index || ' in message ' || p_message_index || ' toolCallId should not be null').to_be_not_null();
    
    ut.expect(l_tool_name, 
             p_test_name || ': Tool call content ' || p_content_index || ' in message ' || p_message_index || ' toolName should not be null').to_be_not_null();
    
    ut.expect(l_args, 
             p_test_name || ': Tool call content ' || p_content_index || ' in message ' || p_message_index || ' args should not be null').to_be_not_null();
  end validate_tool_call_content;

  procedure validate_tool_result_content(
    p_content_item in json_object_t,
    p_content_index in pls_integer,
    p_message_index in pls_integer,
    p_test_name in varchar2
  )
  as
    l_tool_call_id varchar2(100 char);
    l_tool_name varchar2(100 char);
    l_result clob;
  begin
    -- Tool result content should have required fields
    ut.expect(p_content_item.has('toolCallId'), 
             p_test_name || ': Tool result content ' || p_content_index || ' in message ' || p_message_index || ' should have toolCallId field').to_be_true();
    
    ut.expect(p_content_item.has('toolName'), 
             p_test_name || ': Tool result content ' || p_content_index || ' in message ' || p_message_index || ' should have toolName field').to_be_true();
    
    ut.expect(p_content_item.has('result'), 
             p_test_name || ': Tool result content ' || p_content_index || ' in message ' || p_message_index || ' should have result field').to_be_true();
    
    l_tool_call_id := p_content_item.get_string('toolCallId');
    l_tool_name := p_content_item.get_string('toolName');
    l_result := p_content_item.get_clob('result');
    
    ut.expect(l_tool_call_id, 
             p_test_name || ': Tool result content ' || p_content_index || ' in message ' || p_message_index || ' toolCallId should not be null').to_be_not_null();
    
    ut.expect(l_tool_name, 
             p_test_name || ': Tool result content ' || p_content_index || ' in message ' || p_message_index || ' toolName should not be null').to_be_not_null();
    
    ut.expect(l_result, 
             p_test_name || ': Tool result content ' || p_content_index || ' in message ' || p_message_index || ' result should not be null').to_be_not_null();
  end validate_tool_result_content;

  procedure validate_content_array(
    p_content in json_array_t,
    p_message_index in pls_integer,
    p_test_name in varchar2,
    p_role in varchar2
  )
  as
    l_content_item json_object_t;
    l_content_type varchar2(20 char);
    l_content_count pls_integer;
  begin
    --ut.expect(p_content, p_test_name || ': Message ' || p_message_index || ' content array should not be null').to_be_not_null();
    
    l_content_count := p_content.get_size;
    ut.expect(l_content_count, p_test_name || ': Message ' || p_message_index || ' content array should not be empty').to_be_greater_than(0);
    
    -- Validate each content item
    <<content_loop>>
    for j in 0 .. l_content_count - 1 loop
      l_content_item := treat(p_content.get(j) as json_object_t);
      
      -- Check that content item has required 'type' field
      ut.expect(l_content_item.has('type'), 
               p_test_name || ': Content item ' || j || ' in message ' || p_message_index || ' should have type field').to_be_true();
      
      l_content_type := l_content_item.get_string('type');
      ut.expect(l_content_type, 
               p_test_name || ': Content item ' || j || ' in message ' || p_message_index || ' type should not be null').to_be_not_null();
      
      -- Validate content type based on role
      case p_role
        when 'user' then
          ut.expect(l_content_type in ('text', 'file'), 
                   p_test_name || ': User message content type "' || l_content_type || '" should be text or file').to_be_true();
        when 'assistant' then
          ut.expect(l_content_type in ('text', 'file', 'reasoning', 'tool_call'), 
                   p_test_name || ': Assistant message content type "' || l_content_type || '" should be text, file, reasoning, or tool_call').to_be_true();
        when 'tool' then
          ut.expect(l_content_type in ('tool_result'), 
                   p_test_name || ': Tool message content type "' || l_content_type || '" should be tool_result').to_be_true();
      end case;
      
      -- Validate specific content type requirements
      case l_content_type
        when 'text' then
          validate_text_content(l_content_item, j, p_message_index, p_test_name);
        when 'file' then
          validate_file_content(l_content_item, j, p_message_index, p_test_name);
        when 'reasoning' then
          validate_reasoning_content(l_content_item, j, p_message_index, p_test_name);
          g_has_reasoning_content := true;
        when 'tool_call' then
          validate_tool_call_content(l_content_item, j, p_message_index, p_test_name);
        when 'tool_result' then
          validate_tool_result_content(l_content_item, j, p_message_index, p_test_name);
      end case;
    end loop content_loop;
  end validate_content_array;



  procedure validate_message_array(
    p_messages in json_array_t,
    p_test_name in varchar2 default 'Message Array Validation',
    p_should_have_reasoning in boolean default false
  )
  as
    l_message json_object_t;
    l_message_role varchar2(20 char);
    l_content json_array_t;
    l_message_count pls_integer;
  begin
    g_has_reasoning_content := false;
    -- Check if messages array is not null
    --ut.expect(p_messages, p_test_name || ': Messages array should not be null').to_be_not_null();
    
    l_message_count := p_messages.get_size;
    ut.expect(l_message_count, p_test_name || ': Messages array should not be empty').to_be_greater_than(0);
    
    -- Validate each message in the array
    <<message_loop>>
    for i in 0 .. l_message_count - 1 loop
      l_message := treat(p_messages.get(i) as json_object_t);
      
      -- Check that message has required 'role' field
      ut.expect(l_message.has('role'), p_test_name || ': Message ' || i || ' should have role field').to_be_true();
      
      l_message_role := l_message.get_string('role');
      ut.expect(l_message_role, p_test_name || ': Message ' || i || ' role should not be null').to_be_not_null();
      
      -- Validate role is one of the allowed values
      ut.expect(l_message_role in ('system', 'user', 'assistant', 'tool'), 
               p_test_name || ': Message ' || i || ' role "' || l_message_role || '" should be valid').to_be_true();
      
      -- Check that message has required 'content' field
      ut.expect(l_message.has('content'), p_test_name || ': Message ' || i || ' should have content field').to_be_true();
      
      -- Validate content based on role type
      case l_message_role
        when 'system' then
          -- System messages should have string content
          declare
            l_system_content varchar2(32767 char);
          begin
            l_system_content := l_message.get_string('content');
            ut.expect(l_system_content, p_test_name || ': System message ' || i || ' content should be string').to_be_not_null();
          exception
            when others then
              logger.log_warning(p_text => 'exception in validate_message_array for system message ' || i, p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
              ut.fail(p_test_name || ': System message ' || i || ' content should be a string');
          end;
          
        when 'user' then
          -- User messages should have array content
          begin
            l_content := treat(l_message.get('content') as json_array_t);
            validate_content_array(l_content, i, p_test_name, 'user');
          exception
            when others then
              logger.log_warning(p_text => 'exception in validate_message_array for user message ' || i, p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
              ut.fail(p_test_name || ': User message ' || i || ' content should be an array');
          end;
          
        when 'assistant' then
          -- Assistant messages should have array content
          begin
            l_content := treat(l_message.get('content') as json_array_t);
            validate_content_array(l_content, i, p_test_name, 'assistant');
          exception
            when others then
              logger.log_warning(p_text => 'exception in validate_message_array for assistant message ' || i, p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
              ut.fail(p_test_name || ': Assistant message ' || i || ' content should be an array');
          end;
          
        when 'tool' then
          -- Tool messages should have array content
          begin
            l_content := treat(l_message.get('content') as json_array_t);
            validate_content_array(l_content, i, p_test_name, 'tool');
          exception
            when others then
              logger.log_warning(p_text => 'exception in validate_message_array for tool message ' || i, p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
              ut.fail(p_test_name || ': Tool message ' || i || ' content should be an array');
          end;
      end case;
    end loop message_loop;

    if p_should_have_reasoning then
      ut.expect(g_has_reasoning_content, p_test_name || ': Messages should include reasoning content').to_be_true();
    end if;

  end validate_message_array;


  procedure validate_usage_object (
    p_usage in json_object_t,
    p_test_name in varchar2 default 'Usage Object Validation'
  )
  as
    l_keys json_key_list;
  begin
    -- Check that usage object has all required fields
    ut.expect(p_usage.has('prompt_tokens'), 
             p_test_name || ': Usage object should have prompt_tokens field').to_be_true();
    
    ut.expect(p_usage.has('completion_tokens'), 
             p_test_name || ': Usage object should have completion_tokens field').to_be_true();
    
    ut.expect(p_usage.has('reasoning_tokens'), 
             p_test_name || ': Usage object should have reasoning_tokens field').to_be_true();
    
    ut.expect(p_usage.has('total_tokens'), 
             p_test_name || ': Usage object should have total_tokens field').to_be_true();
    
    -- Check that usage object has exactly 4 keys (no extra keys)
    l_keys := p_usage.get_keys();
    ut.expect(l_keys.count, 
             p_test_name || ': Usage object should have exactly 4 keys').to_equal(4);
    
    -- Note: Values can be null or numeric, so we only check for presence, not value validation    
  end validate_usage_object;


  procedure valididate_return_object (
    p_response in json_object_t,
    p_test_name in varchar2 default 'Response Object Validation',
    p_should_have_reasoning in boolean default false
  )
  as
  begin
    ut.expect(p_response.has('provider'), 
             p_test_name || ': Return object should have provider field').to_be_true();
    
    ut.expect(not p_response.get('provider').is_null, 
             p_test_name || ': Return object provider field should not be null').to_be_true();
    
    ut.expect(p_response.has('model'), 
             p_test_name || ': Return object should have model field').to_be_true();
    
    ut.expect(not p_response.get('model').is_null, 
             p_test_name || ': Return object model field should not be null').to_be_true();

    ut.expect(p_response.has('usage'),
             p_test_name || ': Return object should have usage field').to_be_true();

    if p_response.has('usage') then
      ut.expect(not p_response.get('usage').is_null,
               p_test_name || ': Return object usage field should not be null').to_be_true();

      validate_usage_object(
        p_usage => treat(p_response.get('usage') as json_object_t),
        p_test_name => p_test_name || ' - Usage Object Validation'
      );
    end if;

    validate_message_array(
      p_messages => treat(p_response.get('messages') as json_array_t),
      p_test_name => p_test_name || ' - Messages Validation',
      p_should_have_reasoning => p_should_have_reasoning
    );
  end valididate_return_object;
  
end uc_ai_test_message_utils;
/
