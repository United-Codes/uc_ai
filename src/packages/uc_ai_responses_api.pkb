create or replace package body uc_ai_responses_api as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_generate_text_path constant varchar2(255 char) := '/responses';

  g_previous_response_id varchar2(255 char);
  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  -- Responses API reference: https://www.openresponses.org/reference
  
  
  function get_generate_text_url return varchar2
  as
  begin
    if uc_ai.g_base_url is not null then
      return rtrim(uc_ai.g_base_url, '/') || c_api_generate_text_path;
    end if;
    
    return rtrim(g_base_url, '/') || c_api_generate_text_path;
  end get_generate_text_url;


  /*
   * Convert standardized Language Model messages to Responses API format
   * 
   * The Responses API uses "items" instead of "messages", with different structure:
   * - Each item has a "type" field (e.g., "message", "function_call", "function_call_output", "reasoning")
   * - Messages have role and content array
   * - Function calls and outputs are separate items linked by call_id
   * - System messages are handled via "instructions" parameter instead
   * 
   * Returns items array compatible with the Responses API input parameter
   */
  procedure convert_lm_messages_to_items(
    p_lm_messages in json_array_t
  , po_items out nocopy json_array_t
  , po_instructions out nocopy varchar2
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_lm_messages_to_items';
    l_items json_array_t := json_array_t();
    l_lm_message json_object_t;
    l_item json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_new_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_system_instructions varchar2(32767 char);
    l_media_type varchar2(255 char);
    l_has_reasoning_content boolean := false;
    l_reasoning_text clob;
  begin
    uc_ai_logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to Responses API items', l_scope);

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');

      case l_role
        when 'system' then
          -- System messages are handled via instructions parameter in Responses API
          if l_system_instructions is not null then
            l_system_instructions := l_system_instructions || chr(10) || chr(10);
          end if;
          l_system_instructions := l_system_instructions || l_lm_message.get_clob('content');

        when 'user' then
          -- User message item
          l_item := json_object_t();
          l_item.put('type', 'message');
          l_item.put('role', 'user');
          
          -- Convert content array to Responses API format
          l_content := l_lm_message.get_array('content');
          l_new_content := json_array_t();

          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            -- Convert to Responses API content types
            declare
              l_resp_content_item json_object_t;
            begin
              l_content_item := treat(l_content.get(j) as json_object_t);
              l_resp_content_item := json_object_t();

              case l_content_item.get_string('type')
                when 'text' then
                  l_resp_content_item.put('type', 'input_text');
                  l_resp_content_item.put('text', l_content_item.get_clob('text'));
                when 'file' then
                  l_media_type := l_content_item.get_string('mediaType');

                  if lower(l_media_type) like 'image/%' then
                    l_resp_content_item.put('type', 'input_image');
                    l_resp_content_item.put('image_url', 'data:' || l_media_type || ';base64,' || l_content_item.get_clob('data'));
                    l_resp_content_item.put('detail', 'auto');
                  elsif lower(l_media_type) = 'application/pdf' then
                    l_resp_content_item.put('type', 'input_file');
                    l_resp_content_item.put('filename', l_content_item.get_string('filename'));
                    l_resp_content_item.put('file_data', 'data:application/pdf;base64,' || l_content_item.get_clob('data'));
                  else
                    uc_ai_error.raise_error(
                      p_error_code => uc_ai_error.c_err_unhandled_format
                    , p_scope      => l_scope
                    , p0           => 'file media type'
                    , p1           => l_media_type
                    );
                  end if;

                else
                  uc_ai_error.raise_error(
                    p_error_code => uc_ai_error.c_err_unsupported_content
                  , p_scope      => l_scope
                  , p0           => l_content_item.get_string('type')
                  );
              end case;

              l_new_content.append(l_resp_content_item);
            end;
          end loop user_content_loop;

          l_item.put('content', l_new_content);
          
          l_items.append(l_item);

        when 'assistant' then
          -- Assistant message - can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Text message item
                l_item := json_object_t();
                l_item.put('type', 'message');
                l_item.put('role', 'assistant');
                l_item.put('content', json_array_t('[{"type":"output_text","text":"' || l_content_item.get_string('text') || '"}]'));
                l_items.append(l_item);
                
              when 'tool_use' then
                -- Function call item (separate from message in Responses API)
                l_item := json_object_t();
                l_item.put('type', 'function_call');
                l_item.put('call_id', l_content_item.get_string('id'));
                l_item.put('name', l_content_item.get_string('name'));
                
                -- Convert input object to JSON string for arguments
                declare
                  l_input_obj json_object_t := l_content_item.get_object('input');
                begin
                  l_item.put('arguments', l_input_obj.to_clob);
                end;
                
                l_items.append(l_item);
                
              when 'reasoning' then
                l_has_reasoning_content := false;

                -- Reasoning item (for multi-turn conversations with reasoning)
                l_item := json_object_t();
                l_item.put('type', 'reasoning');
                l_reasoning_text := l_content_item.get_clob('text');
                l_item.put('text', l_reasoning_text);

                if l_reasoning_text is not null then
                  l_has_reasoning_content := true;
                end if;
                
                -- Extract providerOptions if present
                if l_content_item.has('providerOptions') and not l_content_item.get('providerOptions').is_null then
                  declare
                    l_provider_options json_object_t := l_content_item.get_object('providerOptions');
                  begin
                    -- Add encrypted_content if present
                    if l_provider_options.has('encrypted_content') and not l_provider_options.get('encrypted_content').is_null then
                      l_item.put('encrypted_content', l_provider_options.get_clob('encrypted_content'));
                      l_has_reasoning_content := true;
                    end if;
                  end;
                end if;
                
                if l_has_reasoning_content then
                  l_items.append(l_item);
                end if;
                
              else
                uc_ai_logger.log_warn('Unknown assistant content type: ' || l_content_type, l_scope);
            end case;
          end loop assistant_content_loop;

        when 'tool' then
          -- Tool result - becomes function_call_output item
          l_content := l_lm_message.get_array('content');
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              l_item := json_object_t();
              l_item.put('type', 'function_call_output');
              l_item.put('call_id', l_content_item.get_string('tool_use_id'));
              
              -- Output can be string or structured content
              if l_content_item.has('content') then
                declare
                  l_result_content json_element_t := l_content_item.get('content');
                begin
                  if l_result_content.is_string then
                    l_item.put('output', l_content_item.get_string('content'));
                  else
                    l_item.put('output', l_content_item.get_clob('content'));
                  end if;
                end;
              end if;
              
              l_items.append(l_item);
            end if;
          end loop tool_content_loop;

        else
          uc_ai_logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    po_items := l_items;
    po_instructions := l_system_instructions;
    uc_ai_logger.log('Converted to ' || l_items.get_size || ' Responses API items', l_scope);

  exception
    when others then
      uc_ai_logger.log_error('Error converting LM messages to Responses API items', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end convert_lm_messages_to_items;


  /*
   * Convert Responses API output items to standardized Language Model format
   * 
   * Responses API returns an "output" array containing various item types:
   * - message items (with role and content)
   * - function_call items (tool calls initiated by model)
   * - function_call_output items (tool results from execution)
   * - reasoning items (model reasoning process)
   * 
   * This converts them back to the standardized LM message format
   * 
   * p_response_id: Optional response ID to add to providerOptions for multi-turn conversations
   */
  function convert_output_to_lm_messages(
    p_output in json_array_t
  , p_response_id in varchar2 default null
  ) return json_array_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_output_to_lm_messages';
    l_messages json_array_t := json_array_t();
    l_output_item json_object_t;
    l_message json_object_t;
    l_item_type varchar2(255 char);
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    
    -- For collecting assistant message content
    l_assistant_content json_array_t;
    l_has_text boolean := false;
  begin
    uc_ai_logger.log('Converting ' || p_output.get_size || ' output items to LM messages', l_scope);
    
    l_assistant_content := json_array_t();
    
    <<output_loop>>
    for i in 0 .. p_output.get_size - 1
    loop
      l_output_item := treat(p_output.get(i) as json_object_t);
      uc_ai_logger.log('Processing output item', l_scope, l_output_item.to_clob);
      l_item_type := l_output_item.get_string('type');
      
      case l_item_type
        when 'message' then
          l_role := l_output_item.get_string('role');
          
          if l_role = 'assistant' then
            -- Collect assistant message content
            l_content := l_output_item.get_array('content');
            
            <<message_content_loop>>
            for j in 0 .. l_content.get_size - 1
            loop
              l_content_item := treat(l_content.get(j) as json_object_t);
              uc_ai_logger.log('Processing output item content', l_scope, l_content_item.to_clob);
              
              if l_content_item.get_string('type') = 'output_text' then
                -- Convert to standardized text content
                declare
                  l_text_content json_object_t := json_object_t();
                begin
                  l_text_content.put('type', 'text');
                  l_text_content.put('text', l_content_item.get_string('text'));

                  l_assistant_content.append(l_text_content);
                  l_has_text := true;
                end;
              end if;
            end loop message_content_loop;
          else
            -- Non-assistant message - convert directly
            l_message := json_object_t();
            l_message.put('role', l_role);
            l_message.put('content', l_output_item.get_array('content'));
            l_messages.append(l_message);
          end if;
          
        when 'function_call' then
          -- Convert function call to tool_use content
          declare
            l_tool_use json_object_t := json_object_t();
            l_arguments_str clob;
            l_arguments_obj json_object_t;
          begin
            l_tool_use.put('type', 'tool_use');
            l_tool_use.put('id', l_output_item.get_string('call_id'));
            l_tool_use.put('name', l_output_item.get_string('name'));
            
            -- Parse arguments string to object
            l_arguments_str := l_output_item.get_clob('arguments');
            if l_arguments_str is not null then
              l_arguments_obj := json_object_t.parse(l_arguments_str);
              l_tool_use.put('input', l_arguments_obj);
            else
              l_tool_use.put('input', json_object_t());
            end if;
            
            l_assistant_content.append(l_tool_use);
          end; 
        when 'function_call_output' then
          -- Convert to tool result message
          declare
            l_tool_result json_object_t := json_object_t();
            l_tool_content json_array_t := json_array_t();
          begin
            l_tool_result.put('type', 'tool_result');
            l_tool_result.put('tool_use_id', l_output_item.get_string('call_id'));
            l_tool_result.put('content', l_output_item.get_string('output'));
            
            l_tool_content.append(l_tool_result);
            
            l_message := json_object_t();
            l_message.put('role', 'tool');
            l_message.put('content', l_tool_content);
            
            -- Flush any pending assistant message before tool result
            if l_assistant_content.get_size > 0 then
              declare
                l_assistant_msg json_object_t := json_object_t();
              begin
                l_assistant_msg.put('role', 'assistant');
                l_assistant_msg.put('content', l_assistant_content);
                l_messages.append(l_assistant_msg);
                
                -- Reset for next assistant message
                l_assistant_content := json_array_t();
                l_has_text := false;
              end;
            end if;
            
            l_messages.append(l_message);
          end;
          
        when 'reasoning' then
          declare
            l_encrypted_content clob;
            l_summary_arr json_array_t;
            l_summary_text clob;

            l_provider_options json_object_t := json_object_t();
            l_reasoning_content json_object_t;
          begin
            if l_output_item.has('encrypted_content') and not l_output_item.get('encrypted_content').is_null then
              l_encrypted_content := l_output_item.get_clob('encrypted_content');
            end if;

            if l_output_item.has('summary') and not l_output_item.get('summary').is_null then
              l_summary_arr := l_output_item.get_array('summary');
            end if;

            if l_summary_arr is not null and l_summary_arr.get_size > 0 then
              <<summary_loop>>
              for i in 0 .. l_summary_arr.get_size - 1 loop
                declare
                  l_summary_item json_object_t;
                begin
                  l_summary_item := treat(l_summary_arr.get(i) as json_object_t);
                  if l_summary_text is not null then
                    l_summary_text := l_summary_text || chr(10);
                  end if;

                  l_summary_text := l_summary_text || l_summary_item.get_clob('text');
                end;
              end loop summary_loop;
            end if;

            if l_encrypted_content is not null or l_summary_text is not null then
              l_provider_options.put('encrypted_content', l_encrypted_content);
              l_provider_options.put('text', l_summary_text);

              l_reasoning_content := uc_ai_message_api.create_reasoning_content(
                p_text => l_output_item.get_clob('text'),
                p_provider_options => l_provider_options
              );

              l_assistant_content.append(l_reasoning_content);
            end if;


          end;
          
        else
          uc_ai_logger.log_warn('Unknown output item type: ' || l_item_type, l_scope);
      end case;
    end loop output_loop;
    
    -- Flush any remaining assistant content
    if l_assistant_content.get_size > 0 then
      l_message := json_object_t();
      l_message.put('role', 'assistant');
      l_message.put('content', l_assistant_content);

      -- Add response_id to assistant message if provided
      if p_response_id is not null then
        l_message.put('response_id', p_response_id);
      end if;

      l_messages.append(l_message);
    end if;
    
    uc_ai_logger.log('Converted to ' || l_messages.get_size || ' LM messages', l_scope);
    return l_messages;

  exception
    when others then
      uc_ai_logger.log_error('Error converting output items to LM messages', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end convert_output_to_lm_messages;


  /*
   * Extract text content from Responses API output
   * Helper function to get the simple text response for easy usage
   */
  function extract_output_text(
    p_output in json_array_t
  ) return clob
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'extract_output_text';
    l_output_item json_object_t;
    l_item_type varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_text clob;
  begin
    <<output_loop>>
    for i in 0 .. p_output.get_size - 1
    loop
      l_output_item := treat(p_output.get(i) as json_object_t);
      l_item_type := l_output_item.get_string('type');
      
      if l_item_type = 'message' and l_output_item.get_string('role') = 'assistant' then
        l_content := l_output_item.get_array('content');
        
        <<content_loop>>
        for j in 0 .. l_content.get_size - 1
        loop
          l_content_item := treat(l_content.get(j) as json_object_t);
          
          if l_content_item.get_string('type') = 'output_text' then
            if l_text is not null then
              l_text := l_text || chr(10);
            end if;
            l_text := l_text || l_content_item.get_string('text');
          end if;
        end loop content_loop;
      end if;
    end loop output_loop;
    
    return l_text;
  exception
    when others then
      uc_ai_logger.log_error('Error extracting output text', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end extract_output_text;


  /*
   * Process a single Responses API request
   * Handles tool calling loop internally within the API
   */
  function internal_generate_text (
    p_input_obj      in json_object_t
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'internal_generate_text';
    l_url          varchar2(4000 char);
    l_resp         clob;
    l_resp_json    json_object_t;
    l_temp_obj     json_object_t;
    l_web_credential varchar2(255 char);
    l_input_copy json_object_t;
  begin

    l_input_copy := p_input_obj.clone();

    -- Currently don't use previous_response_id.
    -- We handle our state internally and when we would use it we are not allowed to send history
    -- This can be quite tricky for multi-provider conversations as 
    -- they can't handle the same response_id across different providers

    -- Add previous_response_id for multi-turn conversations
    -- if g_previous_response_id is not null then
    --   l_input_copy.put('previous_response_id', g_previous_response_id);
    -- end if;

    uc_ai_logger.log('Request body', l_scope, l_input_copy.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.g_request_headers(1).name := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';

    l_web_credential := coalesce(g_apex_web_credential, uc_ai.g_apex_web_credential);

    if l_web_credential is null and not g_skip_auth then
      apex_web_service.g_request_headers(2).name := 'Authorization';
      apex_web_service.g_request_headers(2).value := 'Bearer '||uc_ai_get_key(uc_ai.g_provider_override);
    end if;

    if g_extra_header_name is not null then
      apex_web_service.g_request_headers(apex_web_service.g_request_headers.count + 1).name := g_extra_header_name;
      apex_web_service.g_request_headers(apex_web_service.g_request_headers.count).value := g_extra_header_value;
    end if;

    l_url := get_generate_text_url;
    uc_ai_logger.log('Calling Responses API at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null'), l_scope);

    l_resp := apex_web_service.make_rest_request(
      p_url => l_url,
      p_http_method => 'POST',
      p_body => l_input_copy.to_clob,
      p_credential_static_id => l_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'Responses API', l_scope);

    if l_resp_json.has('error') and not l_resp_json.get('error').is_null then
      if l_resp_json.get('error').is_object then
        l_temp_obj := l_resp_json.get_object('error');
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_provider_response
        , p_scope      => l_scope
        , p0           => 'Responses API'
        , p1           => l_temp_obj.get_string('message')
        , p_extra      => l_temp_obj.to_clob
        );
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_provider_response
        , p_scope      => l_scope
        , p0           => 'Responses API'
        , p1           => l_resp_json.get_string('error')
        );
      end if;
    end if;

    return l_resp_json;

  exception
    when others then
      uc_ai_logger.log_error('Error in internal_generate_text', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end internal_generate_text;


  /*
   * Responses API implementation for text generation
   * 
   * The Responses API is a unified, agentic interface that:
   * - Accepts standardized LM message arrays
   * - Handles multi-turn conversations via previous_response_id in providerOptions
   * - Manages tool calling loops internally (unlike Chat Completions)
   * - Returns structured output with items array
   * - Supports encrypted reasoning for ZDR compliance
   * 
   * Key advantages:
   * - Better performance (3% improvement on SWE-bench)
   * - Lower costs (40-80% better cache utilization)
   * - Stateful context with store parameter
   * - Native tool support (web_search, file_search, code_interpreter, etc.)
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_text';
    l_input_obj        json_object_t := json_object_t();
    l_items            json_array_t;
    l_tools            json_array_t;
    l_result           json_object_t;
    l_api_response     json_object_t;
    l_response_format  json_object_t;
    l_text_config      json_object_t;
    l_reasoning_config json_object_t;
    l_include_array    json_array_t;
    l_instructions     varchar2(32767 char);
    l_message          json_object_t;
    l_output           json_array_t;
    l_output_text      clob;
    l_normalized_messages json_array_t;
    l_curr_response_id varchar2(255 char);
  begin
    uc_ai_logger.log('Starting generate_text with Responses API', l_scope);
    g_previous_response_id := null;
    
    -- Reset global variables
    g_tool_calls := 0;
    g_final_message := null;
    g_normalized_messages := json_array_t();
    
    -- Copy input messages to global normalized messages array
    <<copy_messages_loop>>
    for i in 0 .. p_messages.get_size - 1
    loop
      l_message := treat(p_messages.get(i) as json_object_t);
      g_normalized_messages.append(l_message);
    end loop copy_messages_loop;
    
    l_input_obj.put('model', p_model);

    -- Extract previous response_id from assistant message if present
    <<extract_provider_options_loop>>
    for i in 0 .. p_messages.get_size - 1
    loop
      l_message := treat(p_messages.get(i) as json_object_t);

      continue when l_message.has('role') and l_message.get_string('role') != 'assistant';

      if l_message.has('response_id') then
        g_previous_response_id := l_message.get_string('response_id');
        uc_ai_logger.log('Found previous_response_id in assistant message', l_scope, g_previous_response_id);
        exit extract_provider_options_loop;
      end if;

      -- exit when we found an assistant message but no response_id
      -- @dblinter ignore (g-4365): safe to exit here unconditionally
      exit extract_provider_options_loop;
    end loop extract_provider_options_loop;

    -- Convert LM messages to Responses items (extracts system messages as instructions)
    convert_lm_messages_to_items(p_messages.clone, l_items, l_instructions);
    l_input_obj.put('input', l_items);

    -- Add instructions (extracted from system messages)
    if l_instructions is not null then
      l_input_obj.put('instructions', l_instructions);
    end if;

    -- Configure structured output via text.format (not response_format)
    if p_schema is not null then
      l_text_config := json_object_t();
      
      l_response_format := uc_ai_structured_output.to_responses_api_format(
        p_schema => p_schema,
        p_strict => true
      );
      
      l_text_config.put('format', l_response_format);
      
      -- Add verbosity if configured
      if g_text_verbosity is not null then
        l_text_config.put('verbosity', g_text_verbosity);
      end if;
      
      l_input_obj.put('text', l_text_config);
    elsif g_text_verbosity is not null then
      -- Just verbosity, no format
      l_text_config := json_object_t();
      l_text_config.put('verbosity', g_text_verbosity);
      l_input_obj.put('text', l_text_config);
    end if;

    -- Get all available tools formatted for Responses API (if tools are enabled)
    if uc_ai.g_enable_tools then
      l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_responses_api);
      l_input_obj.put('tools', l_tools);
    end if;

    -- Configure reasoning
    if uc_ai.g_enable_reasoning then
      l_reasoning_config := json_object_t();
      
      -- Set reasoning effort
      l_reasoning_config.put('effort', coalesce(g_reasoning_effort, uc_ai.g_reasoning_level, 'medium'));
      
      -- Set reasoning summary verbosity
      if g_reasoning_summary is not null then
        l_reasoning_config.put('summary', coalesce(g_reasoning_summary, 'auto'));
      end if;
      
      l_input_obj.put('reasoning', l_reasoning_config);
    end if;

    -- Set max tool calls
    if p_max_tool_calls is not null then
      l_input_obj.put('max_tool_calls', p_max_tool_calls);
    end if;

    -- Configure storage and encrypted reasoning
    l_input_obj.put('store', case when coalesce(g_store_responses, false) then true else false end);
    
    if g_include_encrypted_reasoning then
      l_include_array := json_array_t();
      l_include_array.append('reasoning.encrypted_content');
      l_input_obj.put('include', l_include_array);
    end if;

    -- Make the API call
    l_api_response := internal_generate_text(l_input_obj);

    -- Initialize unified result object
    l_result := json_object_t();
    l_result.put('tool_calls_count', 0);
    
    -- Convert output to normalized LM messages (with response_id embedded)
    if l_api_response.has('output') then
      l_output := l_api_response.get_array('output');
      
      -- Check if output contains function calls that need execution
      declare
        l_has_function_calls boolean := false;
        l_output_item json_object_t;
        l_tool_calls_count pls_integer := 0;
        l_current_items json_array_t := l_items.clone;
        l_current_response json_object_t := l_api_response;
        l_current_output json_array_t;
      begin
        -- Loop to handle tool calling
        <<tool_execution_loop>>
        loop
          l_has_function_calls := false;
          l_current_output := l_current_response.get_array('output');
          l_curr_response_id := l_api_response.get_string('id');
          g_previous_response_id := l_curr_response_id;
          
          -- Check for function calls in output
          <<check_function_calls>>
          for i in 0 .. l_current_output.get_size - 1
          loop
            l_output_item := treat(l_current_output.get(i) as json_object_t);
            if l_output_item.get_string('type') = 'function_call' then
              l_has_function_calls := true;
              exit check_function_calls;
            end if;
          end loop check_function_calls;
          
          -- If no function calls or max tool calls exceeded, exit loop
          exit tool_execution_loop when not l_has_function_calls or l_tool_calls_count >= p_max_tool_calls;
          
          uc_ai_logger.log('Found function calls in output, executing tools', l_scope, 'Previous response_id: ' || g_previous_response_id);
          
          -- Convert function calls to normalized assistant message and add to global array
          declare
            l_assistant_content json_array_t := json_array_t();
            l_assistant_message json_object_t;
            l_tool_use_content json_object_t;
            l_has_tool_calls boolean := false;
          begin
            <<convert_function_calls>>
            for i in 0 .. l_current_output.get_size - 1
            loop
              l_output_item := treat(l_current_output.get(i) as json_object_t);
              
              if l_output_item.get_string('type') = 'function_call' then
                l_has_tool_calls := true;
                
                -- Create tool_use content item
                l_tool_use_content := uc_ai_message_api.create_tool_call_content(
                  p_tool_call_id => l_output_item.get_string('call_id'),
                  p_tool_name    => l_output_item.get_string('name'),
                  p_args         => l_output_item.get_clob('arguments')
                );
                
                l_assistant_content.append(l_tool_use_content);
              end if;
            end loop convert_function_calls;
            
            -- Add assistant message with tool_use content to normalized messages
            if l_has_tool_calls then
              l_assistant_message := uc_ai_message_api.create_assistant_message(
                p_content => l_assistant_content
              );
              g_normalized_messages.append(l_assistant_message);
            end if;
          end;
          
          -- Add current output items to the items array
          <<add_output_items>>
          for i in 0 .. l_current_output.get_size - 1
          loop
            l_current_items.append(l_current_output.get(i));
          end loop add_output_items;
          
          -- Execute each function call and add results
          declare
            l_tool_content json_array_t := json_array_t();
            l_tool_message json_object_t;
          begin
            <<execute_function_calls>>
            for i in 0 .. l_current_output.get_size - 1
            loop
              l_output_item := treat(l_current_output.get(i) as json_object_t);
              
              if l_output_item.get_string('type') = 'function_call' then
                declare
                  l_call_id varchar2(255 char);
                  l_tool_name varchar2(255 char);
                  l_arguments_str clob;
                  l_arguments_obj json_object_t;
                  l_tool_result clob;
                  l_function_output_item json_object_t;
                  l_tool_result_content json_object_t;
                begin
                  l_call_id := l_output_item.get_string('call_id');
                  l_tool_name := l_output_item.get_string('name');
                  l_arguments_str := l_output_item.get_clob('arguments');

                  if l_arguments_str is null or l_arguments_str = '{}' then
                    l_arguments_obj := json_object_t();
                  else
                    l_arguments_obj := json_object_t.parse(l_arguments_str);
                    if l_arguments_obj.has('parameters') then
                      l_arguments_obj := l_arguments_obj.get_object('parameters');
                    end if;
                  end if;
                  
                  uc_ai_logger.log('Executing tool: ' || l_tool_name, l_scope, 'Arguments: ' || l_arguments_str);
                  
                  -- Execute the tool
                  l_tool_result := uc_ai_tools_api.execute_tool(
                    p_tool_code => l_tool_name,
                    p_arguments => l_arguments_obj
                  );
                  
                  uc_ai_logger.log('Tool result for ' || l_tool_name, l_scope, l_tool_result);
                  
                  -- Create function_call_output item for API
                  l_function_output_item := json_object_t();
                  l_function_output_item.put('type', 'function_call_output');
                  l_function_output_item.put('call_id', l_call_id);
                  l_function_output_item.put('output', l_tool_result);
                  
                  -- Add to items array
                  l_current_items.append(l_function_output_item);
                  
                  -- Create tool_result content for normalized message
                  l_tool_result_content := uc_ai_message_api.create_tool_result_content(
                    p_tool_call_id => l_call_id,
                    p_tool_name    => l_tool_name,
                    p_result       => l_tool_result
                  );
                  l_tool_content.append(l_tool_result_content);
                  
                  l_tool_calls_count := l_tool_calls_count + 1;
                  g_tool_calls := g_tool_calls + 1;
                exception
                  when others then
                    uc_ai_logger.log_error('Error executing tool: ' || l_tool_name, l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
                    raise;
                end;
              end if;
            end loop execute_function_calls;
            
            -- Add user message with tool results to normalized messages
            if l_tool_content.get_size > 0 then
              l_tool_message := uc_ai_message_api.create_tool_message(
                p_content => l_tool_content
              );
              g_normalized_messages.append(l_tool_message);
            end if;
          end;
          
          -- Make another API call with updated items
          l_input_obj.put('input', l_current_items);
          l_current_response := internal_generate_text(l_input_obj);
          
          uc_ai_logger.log('Made follow-up API call after tool execution', l_scope);
        end loop tool_execution_loop;
        
        -- Store final tool calls count
        l_result.put('tool_calls_count', l_tool_calls_count);
        
        -- Use the final response output for conversion
        l_output := l_current_response.get_array('output');
        l_api_response := l_current_response;
      end;
      
      -- Convert final output to normalized messages and add to global array
      if l_curr_response_id is not null then
        l_normalized_messages := convert_output_to_lm_messages(l_output, l_curr_response_id);
      else
        l_normalized_messages := convert_output_to_lm_messages(l_output);
      end if;
      
      -- Add final output messages to global normalized messages
      <<add_final_messages>>
      for i in 0 .. l_normalized_messages.get_size - 1
      loop
        g_normalized_messages.append(l_normalized_messages.get(i));
      end loop add_final_messages;
      
      -- Extract output text for simple usage
      l_output_text := extract_output_text(l_output);
      if l_output_text is not null then
        l_result.put('final_message', l_output_text);
        g_final_message := l_output_text;
      end if;
    else
      l_normalized_messages := json_array_t();
    end if;
    
    -- Use global normalized messages array (already contains full conversation history)
    l_result.put('messages', g_normalized_messages);
    
    -- Add finish_reason (Responses API uses 'stop_reason')
    if l_api_response.has('stop_reason') then
      l_result.put('finish_reason', l_api_response.get_string('stop_reason'));
    else
      l_result.put('finish_reason', 'stop');
    end if;
    
    -- Add normalized usage information
    if l_api_response.has('usage') then
      declare
        l_api_usage json_object_t := l_api_response.get_object('usage');
        l_usage_obj json_object_t := json_object_t();
        l_input_tokens number := nvl(l_api_usage.get_number('input_tokens'), 0);
        l_output_tokens number := nvl(l_api_usage.get_number('output_tokens'), 0);
        l_reasoning_tokens number := null;
      begin
        if l_api_usage.has('output_tokens_details') and not l_api_usage.get('output_tokens_details').is_null then
          l_reasoning_tokens := l_api_usage.get_object('output_tokens_details').get_number('reasoning_tokens');
        end if;
        l_usage_obj.put('prompt_tokens', l_input_tokens);
        l_usage_obj.put('completion_tokens', l_output_tokens);
        l_usage_obj.put('reasoning_tokens', l_reasoning_tokens);
        l_usage_obj.put('total_tokens', nvl(l_api_usage.get_number('total_tokens'), l_input_tokens + l_output_tokens));
        l_result.put('usage', l_usage_obj);
      end;
    end if;
    
    -- Add model information
    if l_api_response.has('model') then
      l_result.put('model', l_api_response.get_string('model'));
    end if;
    
    -- Add provider info
    l_result.put('provider', coalesce(uc_ai.g_provider_override, uc_ai.c_provider_openai));
    
    uc_ai_logger.log('Completed generate_text with Responses API', l_scope);
    
    return l_result;

  exception
    when others then
      uc_ai_logger.log_error('Error in generate_text', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end generate_text;

end uc_ai_responses_api;
/
