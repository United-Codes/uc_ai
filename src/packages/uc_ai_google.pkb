create or replace package body uc_ai_google as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url_base constant varchar2(255 char) := 'https://generativelanguage.googleapis.com/v1beta/models/';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops


  function internal_generate_text (
    p_messages           in json_array_t
  , p_system_prompt      in clob
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out json_object_t
  , pio_standard_messages in out json_array_t
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
    
    l_has_function_call boolean := false;
  begin
    if g_tool_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_messages := p_messages;
    l_input_obj := p_input_obj;
    l_input_obj.put('contents', l_messages);
    
    -- Add system instruction if provided (Google Gemini uses separate systemInstruction field)
    if p_system_prompt is not null then
      l_temp_obj := json_object_t();
      l_temp_obj.put('role', 'user');
      declare
        l_parts_array json_array_t := json_array_t();
        l_text_part json_object_t := json_object_t();
      begin
        l_text_part.put('text', p_system_prompt);
        l_parts_array.append(l_text_part);
        l_temp_obj.put('parts', l_parts_array);
        l_input_obj.put('systemInstruction', l_temp_obj);
      end;
    end if;

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
      
      -- Check if response contains function calls
      <<parts_loop>>
      for i in 0 .. l_parts.get_size - 1
      loop
        l_part := treat(l_parts.get(i) as json_object_t);
        logger.log('Part: ' || l_part.to_clob, l_scope);
        if l_part.has('functionCall') then
          l_has_function_call := true;
          exit parts_loop;
        end if;
      end loop parts_loop;

      logger.log('Function call detected: ' || case when l_has_function_call then 'YES' else 'NO' end, l_scope);

      if l_has_function_call then
        -- AI wants to call functions - extract calls, execute them, add results to conversation
        declare
          l_resp_message    json_object_t := json_object_t();
          l_tool_results_parts json_array_t := json_array_t();
          l_function_call   json_object_t;
          l_function_name   uc_ai_tools.code%type;
          l_function_args   json_object_t;
          l_tool_result     clob;
          l_new_msg         json_object_t;
          l_param_name      uc_ai_tool_parameters.name%type;
          l_function_response json_object_t;
          -- Standard format messages
          l_std_tool_msg    json_object_t;
        begin
          -- Add AI's message with content (including functionCall parts) to conversation history
          l_resp_message.put('role', 'model');
          l_resp_message.put('parts', l_parts);
          l_messages.append(l_resp_message);

          -- Execute each function call and collect results
          <<function_call_loop>>
          for j in 0 .. l_parts.get_size - 1
          loop
            l_part := treat(l_parts.get(j) as json_object_t);
            
            if l_part.has('functionCall') then
              logger.log('Executing function call', l_scope, l_part.to_clob);

              g_tool_calls := g_tool_calls + 1;

              l_function_call := l_part.get_object('functionCall');
              l_function_name := l_function_call.get_string('name');
              
              -- Handle function arguments (can be null for parameterless functions)
              if l_function_call.has('args') then
                l_function_args := l_function_call.get_object('args');
              else
                l_function_args := json_object_t(); -- Empty args for parameterless functions
              end if;
              
              if l_function_args is not null then
                l_param_name := uc_ai_tools_api.get_tools_object_param_name(l_function_name);
                if l_param_name is not null then
                  l_function_args := l_function_args.get_object(l_param_name);
                end if;
              end if;

              logger.log('Function call', l_scope, 'Function Name: ' || l_function_name);
              if l_function_args is not null then
                logger.log('Function args', l_scope, 'Args: ' || l_function_args.to_clob);
              else
                logger.log('Function args', l_scope, 'No args provided');
                l_function_args := json_object_t();
              end if;

              -- Execute the tool and get result
              begin
                l_tool_result := uc_ai_tools_api.execute_tool(
                  p_tool_code          => l_function_name
                , p_arguments          => l_function_args
                );
              exception
                when others then
                  logger.log_error('Tool execution failed', l_scope, 'Tool: ' || l_function_name || ', Error: ' || sqlerrm || chr(10) || sys.dbms_utility.format_error_backtrace);
                  l_tool_result := 'Error executing function: ' || sqlerrm;
              end;

              -- Add standard format tool result message
              l_std_tool_msg := json_object_t();
              l_std_tool_msg.put('role', 'tool');
              l_std_tool_msg.put('tool_call_id', 'call_' || g_tool_calls);
              l_std_tool_msg.put('content', 'parameters: ' || l_function_args.to_clob);
              l_std_tool_msg.put('function_name', l_function_name);
              pio_standard_messages.append(l_std_tool_msg);

              l_std_tool_msg := json_object_t();
              l_std_tool_msg.put('role', 'user');
              l_std_tool_msg.put('tool_call_id', 'call_' || g_tool_calls);
              l_std_tool_msg.put('content', l_tool_result);
              l_std_tool_msg.put('function_name', l_function_name);
              pio_standard_messages.append(l_std_tool_msg);

              -- Create function response part for the response
              l_function_response := json_object_t();
              declare
                l_func_resp_obj json_object_t := json_object_t();
                l_resp_content json_object_t := json_object_t();
              begin
                -- Google expects the function response in this specific format
                l_resp_content.put('result', l_tool_result);
                l_func_resp_obj.put('name', l_function_name);
                l_func_resp_obj.put('response', l_resp_content);
                l_function_response.put('functionResponse', l_func_resp_obj);
                l_tool_results_parts.append(l_function_response);
              end;
            end if;
          end loop function_call_loop;

          pio_result.put('tool_calls_count', g_tool_calls);

          -- Add function results as new user message
          l_new_msg := json_object_t();
          l_new_msg.put('role', 'user');
          l_new_msg.put('parts', l_tool_results_parts);
          l_messages.append(l_new_msg);

          -- Continue conversation with function results - recursive call
          l_messages := internal_generate_text(
            p_messages           => l_messages
          , p_system_prompt      => p_system_prompt
          , p_max_tool_calls     => p_max_tool_calls
          , p_input_obj          => p_input_obj
          , pio_result           => pio_result
          , pio_standard_messages => pio_standard_messages
          );
        end;
      else
        -- Normal completion - add AI's message to conversation
        logger.log('Normal completion received', l_scope);
        declare
          l_resp_message json_object_t := json_object_t();
          l_std_asst_msg json_object_t := json_object_t();
          l_content_text clob;
        begin
          l_resp_message.put('role', 'model');
          l_resp_message.put('parts', l_parts);
          l_messages.append(l_resp_message);
          
          -- Build standard format assistant message
          l_std_asst_msg.put('role', 'assistant');
          
          -- Extract text content from parts
          l_content_text := null;
          <<extract_text_parts>>
          for k in 0 .. l_parts.get_size - 1
          loop
            l_part := treat(l_parts.get(k) as json_object_t);
            if l_part.has('text') then
              if l_content_text is null then
                l_content_text := l_part.get_clob('text');
              else
                l_content_text := l_content_text || l_part.get_clob('text');
              end if;
            end if;
          end loop extract_text_parts;
          
          l_std_asst_msg.put('content', l_content_text);
          pio_standard_messages.append(l_std_asst_msg);
        end;
      end if;
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
   * Critical workflow for AI function calling:
   * 1. Sends contents + available tools to Google Gemini API  
   * 2. If response contains functionCall parts: extracts function calls, executes each function,
   *    adds function results as new user message, recursively calls itself
   * 3. Continues until no more function calls (conversation complete)
   * 4. g_tool_calls counter prevents infinite loops
   * 
   * Function execution flow:
   * - AI returns parts array with functionCall objects [name, args]
   * - We execute each function via uc_ai_tools_api.execute_tool()
   * - Add function results as user message with functionResponse parts
   * - Send updated conversation back to API
   * 
   * Returns comprehensive result object with:
   * - messages: full conversation history
   * - final_message: last message content for simple usage
   * - finish_reason: completion reason (stop, length, safety, etc.)
   * - usage: token usage statistics (with OpenAI compatible names)
   * - tool_calls_count: total number of function calls executed
   * - model: Google model used
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t
  as
    l_input_obj          json_object_t := json_object_t();
    l_messages           json_array_t := json_array_t();
    l_standard_messages  json_array_t := json_array_t();
    l_message            json_object_t;
    l_parts              json_array_t;
    l_part               json_object_t;
    l_tools              json_array_t;
    l_result             json_object_t := json_object_t();
    l_final_parts        json_array_t;
    l_final_text         clob;
  begin
    -- Reset global call counter
    g_tool_calls := 0;
    
    -- Initialize result object with default values
    l_result.put('tool_calls_count', 0);
    l_result.put('finish_reason', 'unknown');
    l_result.put('model', p_model);
    
    -- Add system prompt as first message to standard messages if provided
    if p_system_prompt is not null then
      l_message := json_object_t();
      l_message.put('role', 'system');
      l_message.put('content', p_system_prompt);
      l_standard_messages.append(l_message);
    end if;
    
    -- Add user message to standard messages
    l_message := json_object_t();
    l_message.put('role', 'user');
    l_message.put('content', p_user_prompt);
    l_standard_messages.append(l_message);
    
    -- Initialize messages array (Google Gemini format uses 'contents')
    l_parts := json_array_t();
    l_part := json_object_t();
    l_part.put('text', p_user_prompt);
    l_parts.append(l_part);

    l_input_obj.put('model', p_model);
    
    l_message := json_object_t();
    l_message.put('role', 'user');
    l_message.put('parts', l_parts);
    l_messages.append(l_message);

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
        logger.log('Tools configured', 'generate_text', 'Tool count: ' || l_tools.get_size);
      end;
    end if;

    l_messages := internal_generate_text(
      p_messages           => l_messages
    , p_system_prompt      => p_system_prompt
    , p_max_tool_calls     => p_max_tool_calls
    , p_input_obj          => l_input_obj
    , pio_result           => l_result
    , pio_standard_messages => l_standard_messages
    );

    -- Extract final message text content (Google format)
    if l_messages.get_size > 0 then
      l_message := treat(l_messages.get(l_messages.get_size - 1) as json_object_t);
      if l_message.has('parts') then
        l_final_parts := l_message.get_array('parts');
        l_final_text := null;
        -- Concatenate all text parts
        <<final_parts_loop>>
        for i in 0 .. l_final_parts.get_size - 1
        loop
          l_part := treat(l_final_parts.get(i) as json_object_t);
          if l_part.has('text') then
            if l_final_text is null then
              l_final_text := l_part.get_clob('text');
            else
              l_final_text := l_final_text || l_part.get_clob('text');
            end if;
          end if;
        end loop final_parts_loop;
        l_result.put('final_message', l_final_text);
      end if;
    end if;
    
    -- Add provider info to the result
    l_result.put('provider', 'google');

    -- Use the standard messages array instead of converting
    l_result.put('messages', l_standard_messages);
    
    return l_result;
  end generate_text;

end uc_ai_google;
/
