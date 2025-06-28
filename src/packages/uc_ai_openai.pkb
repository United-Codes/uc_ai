create or replace package body uc_ai_openai as 

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  g_calls number := 0;  -- Global counter to prevent infinite tool calling loops


  function internal_generate_text (
    p_messages       in json_array_t
  , p_max_tool_calls in pls_integer
  , p_input_obj      in json_object_t
  ) return json_array_t
  as
    e_max_calls_exceeded exception;
    e_error_response exception;

    l_scope logger_logs.scope%type := gc_scope_prefix || 'internal_generate_text';
    l_messages     json_array_t := json_array_t();
    l_new_messages json_array_t;
    l_input_obj    json_object_t;

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_choices   json_array_t;
    l_choice    json_object_t;
    l_finish_reason varchar2(255 char);
  begin
    if g_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_calls);
      raise e_max_calls_exceeded;
    end if;

    l_messages := p_messages;
    l_input_obj := p_input_obj;
    l_input_obj.put('messages', l_messages);

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json',
      p_name_02  => 'Authorization',
      p_value_02 => 'Bearer '||OPENAI_KEY
    );

    g_calls := g_calls + 1;
    l_resp := apex_web_service.make_rest_request(
      p_url => 'https://api.openai.com/v1/chat/completions',
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob
    );

    logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
      logger.log_error('Error message: ', l_scope,l_temp_obj.get_string('message'));
      raise e_error_response;
    end if;

    l_choices := l_resp_json.get_array('choices');

    <<choices_loop>>
    for i in 0 .. l_choices.get_size - 1
    loop
      l_choice := treat( l_choices.get(i) as json_object_t );
      logger.log('Choice', l_scope, l_choice.to_clob);
      l_finish_reason := l_choice.get_string('finish_reason');

      if l_finish_reason = 'tool_calls' then
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

          -- Continue conversation with tool results - recursive call
          l_new_messages := internal_generate_text(
            p_messages       => l_messages
          , p_max_tool_calls => p_max_tool_calls
          , p_input_obj      => p_input_obj
          );

          -- Merge new messages into existing conversation
          <<l_new_messages_loop>>
          for k in 0 .. l_new_messages.get_size - 1
          loop
            l_messages.append(l_new_messages.get(k));
          end loop l_new_messages_loop;
        end;
      elsif l_finish_reason = 'stop' then
        -- Normal completion - add AI's message to conversation
        l_messages.append(l_choice.get_object('message'));
      elsif l_finish_reason = 'length' then
        -- Response truncated due to length - log and continue
        logger.log_warn('Response truncated due to length', l_scope);
        l_messages.append(l_choice.get_object('message'));
      elsif l_finish_reason = 'content_filter' then
        -- Content filter triggered - log and continue
        logger.log_warn('Content filter triggered', l_scope);
        l_messages.append(l_choice.get_object('message'));
      else
        -- Unexpected finish reason - log and continue
        logger.log_warn('Unexpected finish reason: ' || l_finish_reason, l_scope);
        l_messages.append(l_choice.get_object('message'));
      end if;
    end loop choices_loop;

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
   * 4. g_calls counter prevents infinite loops
   * 
   * Tool execution flow:
   * - AI returns tool_calls array with [id, function.name, function.arguments]
   * - We execute each tool via uc_ai_tools_api.execute_tool()
   * - Add tool results as messages with role='tool', tool_call_id=id
   * - Send updated conversation back to API
   */
  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_max_tool_calls in pls_integer
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := gc_scope_prefix || 'generate_text';

    l_input_obj    json_object_t := json_object_t();
    l_messages     json_array_t := json_array_t();
    l_message      json_object_t;
    l_tools        json_array_t;
  begin
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

    -- Build request body with messages and available tools
    l_input_obj.put('model', 'gpt-4o-mini');
    --l_input_obj.put('transfer_timeout', '60');

    -- Get all available tools formatted for OpenAI
    l_tools := uc_ai_tools_api.get_tools_array('openai');
    l_input_obj.put('tools', l_tools);

    l_messages := internal_generate_text(
      p_messages       => l_messages
    , p_max_tool_calls => p_max_tool_calls
    , p_input_obj      => l_input_obj
    );

    return l_messages;
  end generate_text;

end uc_ai_openai;
/
