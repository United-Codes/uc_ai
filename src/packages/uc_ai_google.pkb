create or replace package body uc_ai_google as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url_base constant varchar2(255 char) := 'https://generativelanguage.googleapis.com/v1beta/models/';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  -- Chat API reference: https://ai.google.dev/api/generate-content

  function get_text_content (
    p_message in json_object_t
  ) return json_object_t
  as
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    l_content := p_message.get_clob('text');
    l_provider_options := p_message;
    l_provider_options.remove('text');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    g_final_message := l_content;

    return l_lm_text_content;
  end get_text_content;


/*
   * Convert standardized Language Model messages to Google Gemini format
   * Returns Google-compatible messages array that can be sent directly to Gemini API
   * Also extracts system prompt separately since Google uses a separate systemInstruction field
   */
  procedure convert_lm_messages_to_google(
    p_lm_messages in json_array_t,
    po_system_prompt out clob,
    po_google_messages out json_array_t
  )
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'convert_lm_messages_to_google';
    l_lm_message json_object_t;
    l_google_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_parts json_array_t;
    l_part json_object_t;
    l_function_call json_object_t;
    l_function_response json_object_t;
  begin
    logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to Google format', l_scope);
    
    po_system_prompt := null;
    po_google_messages := json_array_t();

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');

      case l_role
        when 'system' then
          -- System message: extract content for separate systemInstruction field
          po_system_prompt := l_lm_message.get_clob('content');

        when 'user' then
          -- User message: extract text from content array
          l_content := l_lm_message.get_array('content');
          l_parts := json_array_t();
          
          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text part
                l_part := json_object_t();
                l_part.put('text', l_content_item.get_clob('text'));
                l_parts.append(l_part);
              when 'file' then
                null;
                -- TODO: implement file handling if needed
            end case;
          end loop user_content_loop;
          
          if l_parts.get_size > 0 then
            l_google_message := json_object_t();
            l_google_message.put('role', 'user');
            l_google_message.put('parts', l_parts);
            po_google_messages.append(l_google_message);
          end if;

        when 'assistant' then
          -- Assistant message: can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          l_parts := json_array_t();
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text part
                l_part := json_object_t();
                l_part.put('text', l_content_item.get_clob('text'));
                l_parts.append(l_part);
              when 'tool_call' then
                -- Convert tool call to Google functionCall format
                l_function_call := json_object_t();
                l_function_call.put('name', l_content_item.get_string('toolName'));
                
                -- Parse arguments JSON string to object
                declare
                  l_args_obj json_object_t;
                begin
                  if l_content_item.get_clob('args') is not null then
                    l_args_obj := json_object_t.parse(l_content_item.get_clob('args'));
                    l_function_call.put('args', l_args_obj);
                  end if;
                exception
                  when others then
                    -- If parsing fails, don't add args
                    null;
                end;
                
                l_part := json_object_t();
                l_part.put('functionCall', l_function_call);
                l_parts.append(l_part);
              else
                null; -- Skip unknown content types
            end case;
          end loop assistant_content_loop;
          
          if l_parts.get_size > 0 then
            l_google_message := json_object_t();
            l_google_message.put('role', 'model');
            l_google_message.put('parts', l_parts);
            po_google_messages.append(l_google_message);
          end if;

        when 'tool' then
          -- Tool message: convert tool results to Google user message with functionResponse parts
          l_content := l_lm_message.get_array('content');
          l_parts := json_array_t();
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              -- Create functionResponse part
              l_function_response := json_object_t();
              l_function_response.put('name', l_content_item.get_string('toolName'));
              
              declare
                l_response_content json_object_t := json_object_t();
              begin
                l_response_content.put('result', l_content_item.get_clob('result'));
                l_function_response.put('response', l_response_content);
              end;
              
              l_part := json_object_t();
              l_part.put('functionResponse', l_function_response);
              l_parts.append(l_part);
            end if;
          end loop tool_content_loop;
          
          if l_parts.get_size > 0 then
            l_google_message := json_object_t();
            l_google_message.put('role', 'user');
            l_google_message.put('parts', l_parts);
            po_google_messages.append(l_google_message);
          end if;

        else
          logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    logger.log('Converted to ' || po_google_messages.get_size || ' Google messages', l_scope);
    if po_system_prompt is not null then
      logger.log('Extracted system prompt', l_scope, po_system_prompt);
    end if;
  end convert_lm_messages_to_google;


  function internal_generate_text (
    p_messages           in json_array_t
  , p_system_prompt      in clob
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out json_object_t
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'internal_generate_text';
    l_messages     json_array_t := json_array_t();
    l_input_obj    json_object_t;
    l_api_url      varchar2(500 char);
    l_model        varchar2(255 char);

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_candidates json_array_t;
    l_candidate json_object_t;
    l_content   json_object_t;
    l_parts     json_array_t;
    l_part      json_object_t;
    l_finish_reason varchar2(255 char);
    l_usage_metadata json_object_t;
  begin
    if g_tool_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_messages := p_messages;
    l_input_obj := p_input_obj;
    l_input_obj.put('contents', l_messages);


    -- Build API URL with model
    l_model := pio_result.get_string('model');
    l_api_url := c_api_url_base || l_model || ':generateContent?key=' || uc_ai_get_key(uc_ai.c_provider_google);

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json'
    );

    l_resp := apex_web_service.make_rest_request(
      p_url => l_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob
    );

    logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
      logger.log_error('Error message: ', l_scope, l_temp_obj.get_string('message'));
      raise uc_ai.e_error_response;
    end if;

    -- Extract and store usage information
    if l_resp_json.has('usageMetadata') then
      l_usage_metadata := l_resp_json.get_object('usageMetadata');
      -- Accumulate usage if it already exists, otherwise create new
      if pio_result.has('usage') then
        declare
          l_existing_usage json_object_t := pio_result.get_object('usage');
          l_input_tokens number := nvl(l_existing_usage.get_number('input_tokens'), 0) + nvl(l_usage_metadata.get_number('promptTokenCount'), 0);
          l_output_tokens number := nvl(l_existing_usage.get_number('output_tokens'), 0) + nvl(l_usage_metadata.get_number('candidatesTokenCount'), 0);
        begin
          l_existing_usage.put('input_tokens', l_input_tokens);
          l_existing_usage.put('output_tokens', l_output_tokens);
          l_existing_usage.put('total_tokens', l_input_tokens + l_output_tokens);
          -- Add OpenAI compatible names for consistency
          l_existing_usage.put('prompt_tokens', l_input_tokens);
          l_existing_usage.put('completion_tokens', l_output_tokens);
        end;
      else
        -- Create usage object with Google naming and OpenAI compatible names
        declare
          l_usage json_object_t := json_object_t();
          l_input_tokens number := nvl(l_usage_metadata.get_number('promptTokenCount'), 0);
          l_output_tokens number := nvl(l_usage_metadata.get_number('candidatesTokenCount'), 0);
        begin
          l_usage.put('input_tokens', l_input_tokens);
          l_usage.put('output_tokens', l_output_tokens);
          l_usage.put('total_tokens', l_input_tokens + l_output_tokens);
          l_usage.put('prompt_tokens', l_input_tokens);
          l_usage.put('completion_tokens', l_output_tokens);
          pio_result.put('usage', l_usage);
        end;
      end if;
    end if;

    -- Extract model information (Google returns it in response)
    if l_resp_json.has('modelVersion') then
      pio_result.put('model', l_resp_json.get_string('modelVersion'));
    end if;

    -- Process candidates array (Google Gemini format)
    l_candidates := l_resp_json.get_array('candidates');
    if l_candidates.get_size > 0 then
      l_candidate := treat(l_candidates.get(0) as json_object_t);
      
      -- Extract finish reason
      l_finish_reason := l_candidate.get_string('finishReason');
      
      -- Map Google finish reasons to OpenAI format for consistency
      case l_finish_reason
        when 'STOP' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
        when 'MAX_TOKENS' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
        when 'SAFETY' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
        when 'RECITATION' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
        else
          pio_result.put('finish_reason', l_finish_reason);
      end case;

      -- Process content and parts
      l_content := l_candidate.get_object('content');
      l_parts := l_content.get_array('parts');
    
      declare
        l_resp_message       json_object_t := json_object_t();
        l_tool_results_parts json_array_t := json_array_t();
        l_tool_call          json_object_t;
        l_tool_name          uc_ai_tools.code%type;
        l_tool_args          json_object_t;
        l_tool_call_id       varchar2(255 char);
        l_tool_result        clob;
        l_new_msg            json_object_t;
        l_param_name         uc_ai_tool_parameters.name%type;
        l_tool_response      json_object_t;
        l_used_tool          boolean := false;

        l_normalized_messages     json_array_t := json_array_t();
        l_normalized_tool_results json_array_t := json_array_t();
      begin
        -- Add AI's message with content (including functionCall parts) to conversation history
        l_resp_message.put('role', 'model');
        l_resp_message.put('parts', l_parts);
        l_messages.append(l_resp_message);

        -- Execute each function call and collect results
        <<parts_loop>>
        for j in 0 .. l_parts.get_size - 1
        loop
          l_part := treat(l_parts.get(j) as json_object_t);

          
          if l_part.has('functionCall') then
            logger.log('Executing function call', l_scope, l_part.to_clob);

            g_tool_calls := g_tool_calls + 1;
            l_used_tool := true;

            l_tool_call := l_part.get_object('functionCall');
            l_tool_call_id := coalesce(l_tool_call.get_string('id'), 'tool_call_' || g_tool_calls);
            l_tool_name := l_tool_call.get_string('name');
            
            -- Handle function arguments (can be null for parameterless functions)
            if l_tool_call.has('args') then
              l_tool_args := l_tool_call.get_object('args');
            else
              l_tool_args := json_object_t(); -- Empty args for parameterless functions
            end if;
            
            if l_tool_args is not null then
              l_param_name := uc_ai_tools_api.get_tools_object_param_name(l_tool_name);
              if l_param_name is not null then
                l_tool_args := l_tool_args.get_object(l_param_name);
              end if;
            end if;

            logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name);
            if l_tool_args is not null then
              logger.log('Tool args', l_scope, 'Args: ' || l_tool_args.to_clob);
            else
              logger.log('Tool args', l_scope, 'No args provided');
              l_tool_args := json_object_t();
            end if;

            l_new_msg := uc_ai_message_api.create_tool_call_content(
              p_tool_call_id => l_tool_call_id
            , p_tool_name    => l_tool_name
            , p_args         => l_tool_args.to_clob
            );
            l_normalized_messages.append(l_new_msg);

            -- Execute the tool and get result
            begin
              l_tool_result := uc_ai_tools_api.execute_tool(
                p_tool_code          => l_tool_name
              , p_arguments          => l_tool_args
              );
            exception
              when others then
                logger.log_error('Tool execution failed', l_scope, 'Tool: ' || l_tool_name || ', Error: ' || sqlerrm || chr(10) || sys.dbms_utility.format_error_backtrace);
                l_tool_result := 'Error executing tool: ' || sqlerrm;
            end;

            l_tool_response := json_object_t();
            declare
              l_tool_resp_obj json_object_t := json_object_t();
              l_resp_content json_object_t := json_object_t();
            begin
              -- Google expects the function response in this specific format
              l_tool_resp_obj.put('id', l_tool_call_id);
              l_tool_resp_obj.put('name', l_tool_name);
              l_resp_content.put('result', l_tool_result);
              l_tool_resp_obj.put('response', l_resp_content);
              l_tool_response.put('functionResponse', l_tool_resp_obj);
              l_tool_results_parts.append(l_tool_response);
            end;

            l_new_msg := uc_ai_message_api.create_tool_result_content(
              p_tool_call_id => l_tool_call_id,
              p_tool_name    => l_tool_name,
              p_result       => l_tool_result
            );
            l_normalized_tool_results.append(l_new_msg);

          -- normal text part
          elsif l_part.has('text') then
            logger.log('Text received', l_scope, l_part.to_clob);
            l_new_msg := get_text_content(l_part);
            l_normalized_messages.append(l_new_msg);
          end if;
        end loop parts_loop;

        g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));


        if l_used_tool then
          g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
          pio_result.put('tool_calls_count', g_tool_calls);

          -- Add tool results as new user message
          l_new_msg := json_object_t();
          l_new_msg.put('role', 'user');
          l_new_msg.put('parts', l_tool_results_parts);
          l_messages.append(l_new_msg);

          -- Continue conversation with tool results - recursive call
          l_messages := internal_generate_text(
            p_messages           => l_messages
          , p_system_prompt      => p_system_prompt
          , p_max_tool_calls     => p_max_tool_calls
          , p_input_obj          => p_input_obj
          , pio_result           => pio_result
          );
        end if;
      end;
  
    else
      -- No candidates returned
      logger.log_error('No candidates in response', l_scope);
      pio_result.put('finish_reason', 'error');
    end if;

    logger.log('End internal_generate_text - final messages count: ' || l_messages.get_size, l_scope);

    return l_messages;

  end internal_generate_text;


  /*
   * Core conversation handler with Google Gemini API
   * 
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'generate_text_with_messages';
    l_input_obj          json_object_t := json_object_t();
    l_google_messages    json_array_t;
    l_system_prompt      clob;
    l_tools              json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_parts              json_array_t;
    l_part               json_object_t;
  begin
    l_result := json_object_t();
    logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);
    
    -- Reset global call counter
    g_tool_calls := 0;
    
    -- Initialize normalized messages with input messages
    g_normalized_messages := json_array_t();
    
    -- Copy input messages to global normalized messages array
    <<copy_messages_loop>>
    for i in 0 .. p_messages.get_size - 1
    loop
      l_message := treat(p_messages.get(i) as json_object_t);
      g_normalized_messages.append(l_message);
    end loop copy_messages_loop;
    
    -- Initialize result object with default values
    l_result.put('tool_calls_count', 0);
    l_result.put('finish_reason', 'unknown');
    l_result.put('model', p_model);
    l_input_obj.put('model', p_model);
    
    -- Convert standardized messages to Google format
    convert_lm_messages_to_google(
      p_lm_messages => p_messages,
      po_system_prompt => l_system_prompt,
      po_google_messages => l_google_messages
    );

    -- Add system prompt as systemInstruction if extracted
    if l_system_prompt is not null then
      l_parts := json_array_t();
      l_part := json_object_t();
      l_part.put('text', l_system_prompt);
      l_parts.append(l_part);

      l_message := json_object_t();
      l_message.put('role', 'user');
      l_message.put('parts', l_parts);
      l_input_obj.put('systemInstruction', l_message);
    end if;
    
    -- Get all available tools formatted for Google (function declarations)
    l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_google);

    if l_tools.get_size > 0 then
      -- Google expects tools in this format: {"tools": [{"functionDeclarations": [...]}]}
      declare
        l_tools_wrapper json_object_t := json_object_t();
        l_tools_array json_array_t := json_array_t();
      begin
        l_tools_wrapper.put('functionDeclarations', l_tools);
        l_tools_array.append(l_tools_wrapper);
        l_input_obj.put('tools', l_tools_array);
        logger.log('Tools configured', l_scope, 'Tool count: ' || l_tools.get_size);
      end;
    end if;

    l_google_messages := internal_generate_text(
      p_messages           => l_google_messages
    , p_system_prompt      => l_system_prompt
    , p_max_tool_calls     => p_max_tool_calls
    , p_input_obj          => l_input_obj
    , pio_result           => l_result
    );

    -- Add final messages to result (already in standardized format from global variable)
    l_result.put('messages', g_normalized_messages);
    
    -- Add final message (only the text)
    l_result.put('final_message', g_final_message);
 
    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_google);
    
    logger.log('Completed generate_text with final message count: ' || g_normalized_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

end uc_ai_google;
/
