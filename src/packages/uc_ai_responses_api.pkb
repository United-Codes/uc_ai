create or replace package body uc_ai_responses_api as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_generate_text_path constant varchar2(255 char) := '/responses';

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
              l_resp_content_item := treat(l_content.get(j) as json_object_t);

              case l_resp_content_item.get_string('type')
                when 'text' then
                  l_resp_content_item.put('type', 'input_text');
                else
                  -- For other content types, copy as-is (could extend for more types)
                  l_resp_content_item := treat(l_content.get(j) as json_object_t);
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
    l_has_tool_calls boolean := false;
  begin
    uc_ai_logger.log('Converting ' || p_output.get_size || ' output items to LM messages', l_scope);
    
    l_assistant_content := json_array_t();
    
    <<output_loop>>
    for i in 0 .. p_output.get_size - 1
    loop
      l_output_item := treat(p_output.get(i) as json_object_t);
      uc_ai_logger.log('Processing output item: ' || l_output_item.stringify, l_scope);
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
              uc_ai_logger.log('Processing output item content: ' || l_content_item.stringify, l_scope);
              
              if l_content_item.get_string('type') = 'output_text' then
                -- Convert to standardized text content
                declare
                  l_text_content json_object_t := json_object_t();
                begin
                  l_text_content.put('type', 'text');
                  l_text_content.put('text', l_content_item.get_string('text'));

                   if p_response_id is not null then
                     -- Add providerOptions with response_id
                     declare
                       l_provider_options json_object_t := json_object_t();
                     begin
                       l_provider_options.put('response_id', p_response_id);
                       l_text_content.put('providerOptions', l_provider_options);
                     end;
                   end if;

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
            l_has_tool_calls := true;
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
                l_has_tool_calls := false;
              end;
            end if;
            
            l_messages.append(l_message);
          end;
          
        when 'reasoning' then
          -- Skip reasoning items - they're internal to the model
          uc_ai_logger.log('Skipping reasoning item', l_scope);
          
        else
          uc_ai_logger.log_warn('Unknown output item type: ' || l_item_type, l_scope);
      end case;
    end loop output_loop;
    
    -- Flush any remaining assistant content
    if l_assistant_content.get_size > 0 then
      l_message := json_object_t();
      l_message.put('role', 'assistant');
      l_message.put('content', l_assistant_content);
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
      uc_ai_logger.log_error('Error extracting output text', l_scope, sqlerrm);
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
  begin
    uc_ai_logger.log('Request body', l_scope, p_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.g_request_headers(1).name := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';

    case uc_ai.g_provider_override
      when uc_ai.c_provider_xai then
         l_web_credential := coalesce(uc_ai.g_apex_web_credential, uc_ai_xai.g_apex_web_credential);
      when uc_ai.c_provider_openrouter then
         l_web_credential := coalesce(uc_ai.g_apex_web_credential, uc_ai_openrouter.g_apex_web_credential);
      else
         l_web_credential := coalesce(uc_ai.g_apex_web_credential, g_apex_web_credential);
    end case;

    if l_web_credential is null then
      apex_web_service.g_request_headers(2).name := 'Authorization';
      apex_web_service.g_request_headers(2).value := 'Bearer '||uc_ai_get_key(coalesce(uc_ai.g_provider_override, uc_ai.c_provider_openai));
    end if;

    l_url := get_generate_text_url;
    uc_ai_logger.log('Calling Responses API at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null'), l_scope);

    l_resp := apex_web_service.make_rest_request(
      p_url => l_url,
      p_http_method => 'POST',
      p_body => p_input_obj.to_clob,
      p_credential_static_id => l_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    begin
      l_resp_json := json_object_t.parse(l_resp);
    exception
      when others then
        uc_ai_logger.log_error('Response is not JSON, probable error', l_scope, l_resp);
        raise uc_ai.e_error_response;
    end;

    if l_resp_json.has('error') and not l_resp_json.get('error').is_null then
      if l_resp_json.get('error').is_object then
        l_temp_obj := l_resp_json.get_object('error');
        uc_ai_logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
        uc_ai_logger.log_error('Error message: ', l_scope, l_temp_obj.get_string('message'));
      else
        uc_ai_logger.log_error('Error in response', l_scope, l_resp_json.get_string('error'));
      end if;
      raise uc_ai.e_error_response;
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
  , p_schema_name    in varchar2 default 'structured_output'
  , p_strict         in boolean default true
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
    l_previous_response_id varchar2(255 char);
    l_message          json_object_t;
    l_content          json_array_t;
    l_content_item     json_object_t;
    l_provider_options json_object_t;
    l_output           json_array_t;
    l_output_text      clob;
    l_normalized_messages json_array_t;
  begin
    uc_ai_logger.log('Starting generate_text with Responses API', l_scope);
    
    l_input_obj.put('model', p_model);

    -- Extract previous_response_id from providerOptions if present
    <<extract_provider_options_loop>>
    for i in 0 .. p_messages.get_size - 1
    loop
      l_message := treat(p_messages.get(i) as json_object_t);
      
      -- Check if message has content array with providerOptions
      if l_message.has('content') and l_message.get('content').is_array then
        l_content := l_message.get_array('content');
        
        <<content_loop>>
        for j in 0 .. l_content.get_size - 1
        loop
          l_content_item := treat(l_content.get(j) as json_object_t);
          
          if l_content_item.has('providerOptions') then
            l_provider_options := l_content_item.get_object('providerOptions');
            
            if l_provider_options.has('response_id') then
              l_previous_response_id := l_provider_options.get_string('response_id');
              uc_ai_logger.log('Found previous_response_id in providerOptions', l_scope, l_previous_response_id);
              exit extract_provider_options_loop;
            end if;
          end if;
        end loop content_loop;
      end if;
    end loop extract_provider_options_loop;

    -- Convert LM messages to Responses items (extracts system messages as instructions)
    convert_lm_messages_to_items(p_messages.clone, l_items, l_instructions);
    l_input_obj.put('input', l_items);

    -- Add instructions (extracted from system messages)
    if l_instructions is not null then
      l_input_obj.put('instructions', l_instructions);
    end if;

    -- Add previous_response_id for multi-turn conversations
    if l_previous_response_id is not null then
      l_input_obj.put('previous_response_id', l_previous_response_id);
    end if;

    -- Configure structured output via text.format (not response_format)
    if p_schema is not null then
      l_text_config := json_object_t();
      
      l_response_format := uc_ai_structured_output.to_openai_format(
        p_schema => p_schema,
        p_name => p_schema_name,
        p_strict => p_strict
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
      l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_openai, uc_ai.g_provider_override);
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
    
    -- Convert output to normalized LM messages (with response_id embedded)
    if l_api_response.has('output') then
      l_output := l_api_response.get_array('output');
      
      -- Pass response_id to conversion function
      if l_api_response.has('id') then
        l_normalized_messages := convert_output_to_lm_messages(l_output, l_api_response.get_string('id'));
      else
        l_normalized_messages := convert_output_to_lm_messages(l_output);
      end if;
      
      -- Extract output text for simple usage
      l_output_text := extract_output_text(l_output);
      if l_output_text is not null then
        l_result.put('final_message', l_output_text);
      end if;
    else
      l_normalized_messages := json_array_t();
    end if;
    
    -- Combine input messages with output messages to create full conversation history
    declare
      l_all_messages json_array_t := json_array_t();
    begin
      -- Add input messages
      <<input_messages>>
      for i in 0 .. p_messages.get_size - 1
      loop
        l_all_messages.append(p_messages.get(i));
      end loop input_messages;
      
      -- Add output messages
      <<output_messages>>
      for i in 0 .. l_normalized_messages.get_size - 1
      loop
        l_all_messages.append(l_normalized_messages.get(i));
      end loop output_messages;
      
      l_result.put('messages', l_all_messages);
    end;
    
    -- Add finish_reason (Responses API uses 'stop_reason')
    if l_api_response.has('stop_reason') then
      l_result.put('finish_reason', l_api_response.get_string('stop_reason'));
    else
      l_result.put('finish_reason', 'stop');
    end if;
    
    -- Add usage information
    if l_api_response.has('usage') then
      l_result.put('usage', l_api_response.get_object('usage'));
    end if;
    
    -- Add model information
    if l_api_response.has('model') then
      l_result.put('model', l_api_response.get_string('model'));
    end if;
    
    -- Add provider info
    l_result.put('provider', uc_ai.c_provider_openai);
    
    uc_ai_logger.log('Completed generate_text with Responses API', l_scope);
    
    return l_result;

  exception
    when others then
      uc_ai_logger.log_error('Error in generate_text', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end generate_text;

end uc_ai_responses_api;
/
