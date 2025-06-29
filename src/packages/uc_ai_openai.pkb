create or replace package body uc_ai_openai as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'https://api.openai.com/v1/chat/completions';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops


  function internal_generate_text (
    p_messages       in json_array_t
  , p_max_tool_calls in pls_integer
  , p_input_obj      in json_object_t
  , pio_result       in out json_object_t
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'internal_generate_text';
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
        begin
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
          end loop tool_call_loop;

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
        l_messages.append(l_choice.get_object('message'));
      elsif l_finish_reason = uc_ai.c_finish_reason_length then
        -- Response truncated due to length - log and continue
        logger.log_warn('Response truncated due to length', l_scope);
        l_messages.append(l_choice.get_object('message'));
      elsif l_finish_reason = uc_ai.c_finish_reason_content_filter then
        -- Content filter triggered - log and continue
        logger.log_warn('Content filter triggered', l_scope);
        l_messages.append(l_choice.get_object('message'));
      else
        -- Unexpected finish reason - log and continue
        logger.log_warn('Unexpected finish reason: ' || l_finish_reason, l_scope);
        l_messages.append(l_choice.get_object('message'));
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
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t
  as
    l_input_obj    json_object_t := json_object_t();
    l_messages     json_array_t := json_array_t();
    l_message      json_object_t;
    l_tools        json_array_t;
    l_result       json_object_t := json_object_t();
  begin
    -- Reset global call counter
    g_tool_calls := 0;
    
    -- Initialize result object with default values
    l_result.put('tool_calls_count', 0);
    l_result.put('finish_reason', 'unknown');
    
    -- Initialize messages array
    l_message := json_object_t();
    if p_system_prompt is not null then
      -- Add system prompt as first message
      l_message.put('role', 'system');
      l_message.put('content', p_system_prompt);
      l_messages.append(l_message);
    end if;
    l_message := json_object_t();
    l_message.put('role', 'user');
    l_message.put('content', p_user_prompt);
    l_messages.append(l_message);

    l_input_obj.put('model', p_model);
    --l_input_obj.put('transfer_timeout', '60');

    -- Get all available tools formatted for OpenAI
    l_tools := uc_ai_tools_api.get_tools_array('openai');
    l_input_obj.put('tools', l_tools);

    l_messages := internal_generate_text(
      p_messages       => l_messages
    , p_max_tool_calls => p_max_tool_calls
    , p_input_obj      => l_input_obj
    , pio_result       => l_result
    );

    -- Add final messages to result
    l_result.put('messages', l_messages);
    
    -- Add final message (only the text)
    if l_messages.get_size > 0 then
      l_message := treat(l_messages.get(l_messages.get_size - 1) as json_object_t);
      l_result.put('final_message', l_message.get_clob('content'));
    end if;
    
    -- Add provider info to the result
    l_result.put('provider', 'openai');
    
    return l_result;
  end generate_text;

end uc_ai_openai;
/
