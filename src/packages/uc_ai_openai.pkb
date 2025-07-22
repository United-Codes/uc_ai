create or replace package body uc_ai_openai as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'https://api.openai.com/v1/chat/completions';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  -- Chat API reference: https://platform.openai.com/docs/api-reference/chat/create

  procedure process_text_message(
    p_message in json_object_t
  )
  as
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
    l_assistant_message json_object_t;
    l_arr json_array_t;
  begin
    l_content := p_message.get_clob('content');
    l_provider_options := p_message;
    l_provider_options.remove('role');
    l_provider_options.remove('content');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    l_arr := json_array_t();
    l_arr.append(l_lm_text_content);
    l_assistant_message := uc_ai_message_api.create_assistant_message(
      p_content => l_arr
    );

    g_final_message := l_content;
    g_normalized_messages.append(l_assistant_message);
  end process_text_message;



  /*
   * Convert standardized Language Model messages to OpenAI format
   * Returns OpenAI-compatible messages array that can be sent directly to OpenAI API
   */
  function convert_lm_messages_to_openai(
    p_lm_messages in json_array_t
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'convert_lm_messages_to_openai';
    l_openai_messages json_array_t := json_array_t();
    l_lm_message json_object_t;
    l_openai_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_new_content json_array_t;
    l_content_item json_object_t;
    l_new_content_item json_object_t;
    l_temp_obj json_object_t;
    l_content_type varchar2(255 char);
    l_tool_calls json_array_t;
    l_tool_call json_object_t;
    l_function json_object_t;
    l_text_content clob;
  begin
    logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to OpenAI format', l_scope);

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');
      l_openai_message := json_object_t();
      l_openai_message.put('role', l_role);

      case l_role
        when 'system' then
          -- System message: content is directly a string
          l_openai_message.put('content', l_lm_message.get_clob('content'));

        when 'user' then
          -- User message: extract text from content array
          l_content := l_lm_message.get_array('content');
          l_text_content := null;

          l_new_content := json_array_t();

          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                if l_text_content is null then
                  l_text_content := l_content_item.get_clob('text');
                else
                  l_text_content := l_text_content || l_content_item.get_clob('text');
                end if;

                l_new_content_item := json_object_t();
                l_new_content_item.put('type', 'text');
                l_new_content_item.put('text', l_content_item.get_clob('text'));
                l_new_content.append(l_new_content_item);
              when 'file' then
                 declare
                  l_data      clob;
                  l_mime_type varchar2(4000 char);
                  l_filename  varchar2(4000 char);
                  l_image_url json_object_t;
                begin
                  l_data := l_content_item.get_clob('data');
                  l_mime_type := l_content_item.get_string('mediaType');
                  l_filename := l_content_item.get_string('filename');
                  l_new_content_item := json_object_t();

                  -- PDF doc: https://platform.openai.com/docs/guides/pdf-files?api-mode=responses#base64-encoded-files
                  if l_mime_type = 'application/pdf' then
                    l_new_content_item.put('type', 'file');

                    l_temp_obj := json_object_t();
                    l_temp_obj.put('filename', l_filename);
                    l_temp_obj.put('file_data', 'data:application/pdf;base64,' ||  l_data);
                    l_new_content_item.put('file', l_temp_obj);

                  -- img doc: https://platform.openai.com/docs/guides/images-vision?api-mode=responses&format=base64-encoded#analyze-images
                  elsif l_mime_type in ('image/jpeg', 'image/png', 'image/gif', 'image/webp') then
                    l_new_content_item.put('type', 'image_url');
                    l_image_url := json_object_t();
                    l_image_url.put('url', 'data:' || l_mime_type || ';base64,' || l_data);
                    l_new_content_item.put('image_url', l_image_url);
                  else
                    logger.log_error('Unsupported file type: ' || l_mime_type, l_scope, l_content_item.stringify);
                    raise uc_ai.e_unhandled_format;
                  end if;

                  l_new_content.append(l_new_content_item);
                end;
              else
                logger.log_error('Unknown content type in user message: ' || l_content_type, l_scope, l_content_item.stringify);
                raise uc_ai.e_unhandled_format;
            end case;
          end loop user_content_loop;
          
          l_openai_message.put('content', l_new_content);

        when 'assistant' then
          -- Assistant message: can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          l_tool_calls := json_array_t();
          l_text_content := null;
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                if l_text_content is null then
                  l_text_content := l_content_item.get_clob('text');
                else
                  l_text_content := l_text_content || l_content_item.get_clob('text');
                end if;
              when 'tool_call' then
                -- Convert tool call to OpenAI format
                l_tool_call := json_object_t();
                l_tool_call.put('id', l_content_item.get_string('toolCallId'));
                l_tool_call.put('type', 'function');
                
                l_function := json_object_t();
                l_function.put('name', l_content_item.get_string('toolName'));
                l_function.put('arguments', l_content_item.get_clob('args'));
                
                l_tool_call.put('function', l_function);
                l_tool_calls.append(l_tool_call);
              else
                null; -- Skip unknown content types
            end case;
          end loop assistant_content_loop;
          
          l_openai_message.put('content', l_text_content);
          
          -- Add tool calls if any
          if l_tool_calls.get_size > 0 then
            l_openai_message.put('tool_calls', l_tool_calls);
          end if;

        when 'tool' then
          -- Tool message: convert tool results to OpenAI tool message format
          l_content := l_lm_message.get_array('content');
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              -- Create separate OpenAI tool message for each result
              declare
                l_tool_message json_object_t := json_object_t();
              begin
                l_tool_message.put('role', 'tool');
                l_tool_message.put('content', l_content_item.get_clob('result'));
                l_tool_message.put('tool_call_id', l_content_item.get_string('toolCallId'));
                
                -- For OpenAI, we add each tool result as a separate message
                l_openai_messages.append(l_tool_message);
              end;
            end if;
          end loop tool_content_loop;

        else
          logger.log_warn('Unknown message role: ' || l_role, l_scope);
          -- Add the message as-is for unknown types
          l_openai_messages.append(l_openai_message);
      end case;

      -- Add the converted message to the result array (except for tool messages which are handled separately)
      if l_role != 'tool' then
        l_openai_messages.append(l_openai_message);
      end if;
    end loop message_loop;

    logger.log('Converted to ' || l_openai_messages.get_size || ' OpenAI messages', l_scope);
    return l_openai_messages;

  exception
    when others then
      logger.log_error('Error converting LM messages to OpenAI format', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end convert_lm_messages_to_openai;



  function internal_generate_text (
    p_messages       in json_array_t
  , p_max_tool_calls in pls_integer
  , p_input_obj      in json_object_t
  , pio_result       in out json_object_t
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'internal_generate_text';
    l_message      json_object_t;
    l_messages     json_array_t := json_array_t();
    l_input_obj    json_object_t;

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_choices   json_array_t;
    l_choice    json_object_t;
    l_finish_reason varchar2(255 char);
    l_usage     json_object_t;
    l_model     varchar2(255 char);
  begin
    if g_tool_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_messages := p_messages;
    l_input_obj := p_input_obj;
    l_input_obj.put('messages', l_messages);

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json',
      p_name_02  => 'Authorization',
      p_value_02 => 'Bearer '||uc_ai_get_key(uc_ai.c_provider_openai)
    );

    l_resp := apex_web_service.make_rest_request(
      p_url => c_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob
    );

    logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
      logger.log_error('Error message: ', l_scope,l_temp_obj.get_string('message'));
      raise uc_ai.e_error_response;
    end if;

    -- Extract and store usage information
    if l_resp_json.has('usage') then
      l_usage := l_resp_json.get_object('usage');
      -- Accumulate usage if it already exists, otherwise create new
      if pio_result.has('usage') then
        declare
          l_existing_usage json_object_t := pio_result.get_object('usage');
          l_prompt_tokens number := nvl(l_existing_usage.get_number('prompt_tokens'), 0) + nvl(l_usage.get_number('prompt_tokens'), 0);
          l_completion_tokens number := nvl(l_existing_usage.get_number('completion_tokens'), 0) + nvl(l_usage.get_number('completion_tokens'), 0);
        begin
          l_existing_usage.put('prompt_tokens', l_prompt_tokens);
          l_existing_usage.put('completion_tokens', l_completion_tokens);
          l_existing_usage.put('total_tokens', l_prompt_tokens + l_completion_tokens);
        end;
      else
        pio_result.put('usage', l_usage);
      end if;
    end if;

    -- Extract model information
    if l_resp_json.has('model') then
      l_model := l_resp_json.get_string('model');
      pio_result.put('model', l_model);
    end if;

    l_choices := l_resp_json.get_array('choices');

    <<choices_loop>>
    for i in 0 .. l_choices.get_size - 1
    loop
      l_choice := treat( l_choices.get(i) as json_object_t );
      logger.log('Choice (' || i || ')', l_scope, l_choice.to_clob);
      l_finish_reason := l_choice.get_string('finish_reason');
      
      -- Store finish reason in result object
      pio_result.put('finish_reason', l_finish_reason);

      if l_finish_reason = uc_ai.c_finish_reason_tool_calls then
        -- AI wants to call tools - extract calls, execute them, add results to conversation
        declare
          l_resp_message   json_object_t;
          l_tool_calls      json_array_t;
          l_function        json_object_t;
          l_curr_call       json_object_t;
          l_call_id         varchar2(255 char);
          l_tool_id         varchar2(255 char);
          l_arguments       clob;
          l_args_json       json_object_t;
          l_tool_result     clob;
          l_new_msg         json_object_t;

          l_lm_tool_calls   json_array_t;
          l_lm_tool_results json_array_t;
        begin
          l_lm_tool_calls   := json_array_t();
          l_lm_tool_results := json_array_t();

          -- Add AI's message with tool_calls to conversation history
          l_resp_message := l_choice.get_object('message');
          l_messages.append(l_resp_message);
          l_tool_calls := l_resp_message.get_array('tool_calls');

          -- Execute each tool call and add results as tool messages
          <<tool_call_loop>>
          for j in 0 .. l_tool_calls.get_size - 1
          loop
            g_tool_calls := g_tool_calls + 1;

            l_curr_call := treat( l_tool_calls.get(j) as json_object_t );
            l_call_id := l_curr_call.get_string('id');
            l_function := l_curr_call.get_object('function');
            l_tool_id := l_function.get_string('name');
            l_arguments := l_function.get_string('arguments');

            l_lm_tool_calls.append(
              uc_ai_message_api.create_tool_call_content(
                p_tool_call_id => l_call_id
              , p_tool_name    => l_tool_id
              , p_args         => l_arguments
              )
            );


            logger.log('Tool call', l_scope, 'Tool ID: ' || l_tool_id || ', Call ID: ' || l_call_id || ', Arguments: ' || l_arguments);
            l_args_json := json_object_t.parse(l_arguments);

            -- Execute the tool and get result
            l_tool_result := uc_ai_tools_api.execute_tool(
              p_tool_code => l_tool_id
            , p_arguments => l_args_json
            );

            -- Add tool result as new message in conversation
            l_new_msg := json_object_t();
            l_new_msg.put('role', 'tool');
            l_new_msg.put('content', l_tool_result);
            l_new_msg.put('tool_call_id', l_call_id);
            l_messages.append(l_new_msg);

            l_lm_tool_results.append(
              uc_ai_message_api.create_tool_result_content(
                p_tool_call_id => l_call_id
              , p_tool_name    => l_tool_id
              , p_result       => l_tool_result
              )
            );
          end loop tool_call_loop;

          g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_lm_tool_calls));
          g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_lm_tool_results));


          pio_result.put('tool_calls_count', g_tool_calls);

          -- Continue conversation with tool results - recursive call
          l_messages := internal_generate_text(
            p_messages       => l_messages
          , p_max_tool_calls => p_max_tool_calls
          , p_input_obj      => p_input_obj
          , pio_result       => pio_result
          );
        end;
      elsif l_finish_reason = uc_ai.c_finish_reason_stop then
        -- Normal completion - add AI's message to conversation
        logger.log('Stop received', l_scope);
        l_message := l_choice.get_object('message');
        l_messages.append(l_message);

        process_text_message(l_message);
      elsif l_finish_reason = uc_ai.c_finish_reason_length then
        -- Response truncated due to length - log and continue
        logger.log_warn('Response truncated due to length', l_scope);
        l_message := l_choice.get_object('message');
        l_messages.append(l_message);

        process_text_message(l_message);
      elsif l_finish_reason = uc_ai.c_finish_reason_content_filter then
        -- Content filter triggered - log and continue
        logger.log_warn('Content filter triggered', l_scope);
        l_messages.append(l_choice.get_object('message'));
      else
        -- Unexpected finish reason - log and continue
        logger.log_warn('Unexpected finish reason: ' || l_finish_reason, l_scope);
        l_message := l_choice.get_object('message');
        l_messages.append(l_message);

        process_text_message(l_message);
      end if;
    end loop choices_loop;

    logger.log('End internal_generate_text - final messages count: ' || l_messages.get_size, l_scope);

    return l_messages;

  end internal_generate_text;


  /*
   * Core conversation handler with OpenAI API
   * 
   * Critical workflow for AI function calling:
   * 1. Sends messages + available tools to OpenAI API  
   * 2. If finish_reason = 'tool_calls': extracts tool calls, executes each tool,
   *    adds tool results as new messages, recursively calls itself
   * 3. Continues until finish_reason != 'tool_calls' (conversation complete)
   * 4. g_tool_calls counter prevents infinite loops
   * 
   * Tool execution flow:
   * - AI returns tool_calls array with [id, function.name, function.arguments]
   * - We execute each tool via uc_ai_tools_api.execute_tool()
   * - Add tool results as messages with role='tool', tool_call_id=id
   * - Send updated conversation back to API
   * 
   * Returns comprehensive result object with:
   * - messages: full conversation history
   * - final_message: last message in conversation for simple usage
   * - finish_reason: completion reason (stop, tool_calls, length, etc.)
   * - usage: token usage statistics
   * - tool_calls_count: total number of tool calls executed
   * - model: OpenAI model used
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'generate_text_with_messages';
    l_input_obj    json_object_t := json_object_t();
    l_openai_messages json_array_t;
    l_tools        json_array_t;
    l_result       json_object_t;
    l_message      json_object_t;
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
    
    -- Convert standardized messages to OpenAI format
    l_openai_messages := convert_lm_messages_to_openai(p_messages);
    
    logger.log('Converted to ' || l_openai_messages.get_size || ' OpenAI messages', l_scope);

    l_input_obj.put('model', p_model);

    -- Get all available tools formatted for OpenAI
    l_tools := uc_ai_tools_api.get_tools_array('openai');
    l_input_obj.put('tools', l_tools);

    l_openai_messages := internal_generate_text(
      p_messages       => l_openai_messages
    , p_max_tool_calls => p_max_tool_calls
    , p_input_obj      => l_input_obj
    , pio_result       => l_result
    );

    -- Add final messages to result (already in standardized format from global variable)
    l_result.put('messages', g_normalized_messages);
    
    -- Add final message (only the text)
    l_result.put('final_message', g_final_message);
 
    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_openai);
    
    logger.log('Completed generate_text with final message count: ' || g_normalized_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;
end uc_ai_openai;
/
