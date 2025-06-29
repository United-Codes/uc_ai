create or replace package body uc_ai_anthropic as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'https://api.anthropic.com/v1/messages';
  c_anthropic_version constant varchar2(32 char) := '2023-06-01';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops


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

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_content   json_array_t;
    l_content_block json_object_t;
    l_stop_reason varchar2(255 char);
    l_usage     json_object_t;
    l_model     varchar2(255 char);
    l_content_type varchar2(64 char);
    
    l_has_tool_use boolean := false;
  begin
    if g_tool_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_messages := p_messages;
    l_input_obj := p_input_obj;
    l_input_obj.put('messages', l_messages);
    
    -- Add system prompt if provided (Anthropic uses separate system field)
    if p_system_prompt is not null then
      l_input_obj.put('system', p_system_prompt);
    end if;

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json',
      p_name_02  => 'x-api-key',
      p_value_02 => uc_ai_get_key(uc_ai.c_provider_anthropic),
      p_name_03  => 'anthropic-version',
      p_value_03 => c_anthropic_version
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
      logger.log_error('Error message: ', l_scope, l_temp_obj.get_string('message'));
      raise uc_ai.e_error_response;
    end if;

    -- Extract and store usage information
    if l_resp_json.has('usage') then
      l_usage := l_resp_json.get_object('usage');
      -- Accumulate usage if it already exists, otherwise create new
      if pio_result.has('usage') then
        declare
          l_existing_usage json_object_t := pio_result.get_object('usage');
          l_input_tokens number := nvl(l_existing_usage.get_number('input_tokens'), 0) + nvl(l_usage.get_number('input_tokens'), 0);
          l_output_tokens number := nvl(l_existing_usage.get_number('output_tokens'), 0) + nvl(l_usage.get_number('output_tokens'), 0);
        begin
          l_existing_usage.put('input_tokens', l_input_tokens);
          l_existing_usage.put('output_tokens', l_output_tokens);
          l_existing_usage.put('total_tokens', l_input_tokens + l_output_tokens);
          -- Keep Anthropic naming but add OpenAI compatible names for consistency
          l_existing_usage.put('prompt_tokens', l_input_tokens);
          l_existing_usage.put('completion_tokens', l_output_tokens);
        end;
      else
        -- Add OpenAI compatible naming for consistency
        l_usage.put('prompt_tokens', nvl(l_usage.get_number('input_tokens'), 0));
        l_usage.put('completion_tokens', nvl(l_usage.get_number('output_tokens'), 0));
        l_usage.put('total_tokens', nvl(l_usage.get_number('input_tokens'), 0) + nvl(l_usage.get_number('output_tokens'), 0));
        pio_result.put('usage', l_usage);
      end if;
    end if;

    -- Extract model information
    if l_resp_json.has('model') then
      l_model := l_resp_json.get_string('model');
      pio_result.put('model', l_model);
    end if;

    -- Extract stop reason
    l_stop_reason := l_resp_json.get_string('stop_reason');
    
    -- Map Anthropic stop reasons to OpenAI format for consistency
    case l_stop_reason
      when 'end_turn' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
      when 'tool_use' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_tool_calls);
      when 'max_tokens' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
      when 'stop_sequence' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
      else
        pio_result.put('finish_reason', l_stop_reason);
    end case;

    -- Process content array
    l_content := l_resp_json.get_array('content');
    
    -- Check if response contains tool use
    <<content_loop>>
    for i in 0 .. l_content.get_size - 1
    loop
      l_content_block := treat(l_content.get(i) as json_object_t);
      l_content_type := l_content_block.get_string('type');
      logger.log('Content block type: ' || l_content_type, l_scope);
      if l_content_type = 'tool_use' then
        l_has_tool_use := true;
        exit content_loop;
      end if;
    end loop content_loop;

    if l_has_tool_use then
      -- AI wants to call tools - extract calls, execute them, add results to conversation
      declare
        l_resp_message    json_object_t := json_object_t();
        l_tool_results    json_array_t := json_array_t();
        l_tool_result_obj json_object_t;
        l_provider_tool_id varchar2(255 CHAR);
        l_tool_name       uc_ai_tools.code%type;
        l_tool_input      json_object_t;
        l_tool_result     clob;
        l_new_msg         json_object_t;
        l_param_name      uc_ai_tool_parameters.name%type;
      begin
        -- Add AI's message with content (including tool_use blocks) to conversation history
        l_resp_message.put('role', 'assistant');
        l_resp_message.put('content', l_content);
        l_messages.append(l_resp_message);

        -- Execute each tool call and collect results
        <<tool_use_loop>>
        for j in 0 .. l_content.get_size - 1
        loop
          l_content_block := treat(l_content.get(j) as json_object_t);
          
          if l_content_block.get_string('type') = 'tool_use' then
            logger.log('Executing tool use', l_scope, l_content_block.to_clob);

            g_tool_calls := g_tool_calls + 1;

            l_provider_tool_id := l_content_block.get_string('id');
            l_tool_name := l_content_block.get_string('name');
            l_tool_input := l_content_block.get_object('input');
            if l_tool_input is not null then
              l_param_name := uc_ai_tools_api.get_tools_object_param_name(l_tool_name);
              if l_param_name is not null then
                l_tool_input := l_tool_input.get_object(l_param_name);
              end if;
            end if;

            logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name || ', Tool ID: ' || l_provider_tool_id);
            if l_tool_input is not null then
              logger.log('Tool input', l_scope, 'Input: ' || l_tool_input.to_clob);
            else
              logger.log('Tool input', l_scope, 'No input provided');
              l_tool_input := json_object_t();
            end if;

            -- Execute the tool and get result
            l_tool_result := uc_ai_tools_api.execute_tool(
              p_tool_code          => l_tool_name
            , p_arguments          => l_tool_input
            );

            -- Create tool result object for the content array
            l_tool_result_obj := json_object_t();
            l_tool_result_obj.put('type', 'tool_result');
            l_tool_result_obj.put('tool_use_id', l_provider_tool_id);
            l_tool_result_obj.put('content', l_tool_result);
            l_tool_results.append(l_tool_result_obj);
          end if;
        end loop tool_use_loop;

        pio_result.put('tool_calls_count', g_tool_calls);

        -- Add tool results as new user message with tool_result content
        l_new_msg := json_object_t();
        l_new_msg.put('role', 'user');
        l_new_msg.put('content', l_tool_results);
        l_messages.append(l_new_msg);

        -- Continue conversation with tool results - recursive call
        l_messages := internal_generate_text(
          p_messages           => l_messages
        , p_system_prompt      => p_system_prompt
        , p_max_tool_calls     => p_max_tool_calls
        , p_input_obj          => p_input_obj
        , pio_result           => pio_result
        );
      end;
    else
      -- Normal completion - add AI's message to conversation
      logger.log('Normal completion received', l_scope);
      declare
        l_resp_message json_object_t := json_object_t();
      begin
        l_resp_message.put('role', 'assistant');
        l_resp_message.put('content', l_content);
        l_messages.append(l_resp_message);
      end;
    end if;

    logger.log('End internal_generate_text - final messages count: ' || l_messages.get_size, l_scope);

    return l_messages;

  end internal_generate_text;


  /*
   * Core conversation handler with Anthropic API
   * 
   * Critical workflow for AI function calling:
   * 1. Sends messages + available tools to Anthropic API  
   * 2. If stop_reason = 'tool_use': extracts tool_use blocks, executes each tool,
   *    adds tool results as new user message, recursively calls itself
   * 3. Continues until stop_reason != 'tool_use' (conversation complete)
   * 4. g_tool_calls counter prevents infinite loops
   * 
   * Tool execution flow:
   * - AI returns content array with tool_use blocks [id, name, input]
   * - We execute each tool via uc_ai_tools_api.execute_tool()
   * - Add tool results as user message with content array of tool_result blocks
   * - Send updated conversation back to API
   * 
   * Returns comprehensive result object with:
   * - messages: full conversation history
   * - final_message: last message content for simple usage
   * - finish_reason: completion reason (stop, tool_calls, length, etc.)
   * - usage: token usage statistics (with OpenAI compatible names)
   * - tool_calls_count: total number of tool calls executed
   * - model: Anthropic model used
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
    l_end_messages       json_array_t := json_array_t();
    l_message            json_object_t;
    l_tools              json_array_t;
    l_result             json_object_t := json_object_t();
    l_final_content      json_array_t;
    l_content_block      json_object_t;
    l_final_text         clob;
  begin
    -- Reset global call counter
    g_tool_calls := 0;
    
    -- Initialize result object with default values
    l_result.put('tool_calls_count', 0);
    l_result.put('finish_reason', 'unknown');
    
    -- Initialize messages array (no system message in messages for Anthropic)
    l_message := json_object_t();
    l_message.put('role', 'user');
    l_message.put('content', p_user_prompt);
    l_messages.append(l_message);

    l_input_obj.put('model', p_model);
    l_input_obj.put('max_tokens', 8192); -- Anthropic requires max_tokens

    -- Get all available tools formatted for Anthropic (not OpenAI format)
    l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_anthropic);

    if l_tools.get_size > 0 then
      l_input_obj.put('tools', l_tools);
    end if;

    l_messages := internal_generate_text(
      p_messages           => l_messages
    , p_system_prompt      => p_system_prompt
    , p_max_tool_calls     => p_max_tool_calls
    , p_input_obj          => l_input_obj
    , pio_result           => l_result
    );

    -- Add final messages to result
    l_result.put('messages', l_messages);
    
    -- Extract final message text content (Anthropic format is different from OpenAI)
    if l_messages.get_size > 0 then
      l_message := treat(l_messages.get(l_messages.get_size - 1) as json_object_t);
      if l_message.has('content') then
        l_final_content := l_message.get_array('content');
        l_final_text := null;
        -- Concatenate all text blocks
        <<final_content_loop>>
        for i in 0 .. l_final_content.get_size - 1
        loop
          l_content_block := treat(l_final_content.get(i) as json_object_t);
          if l_content_block.get_string('type') = 'text' then
            if l_final_text is null then
              l_final_text := l_content_block.get_clob('text');
            else
              l_final_text := l_final_text || l_content_block.get_clob('text');
            end if;
          end if;
        end loop final_content_loop;
        l_result.put('final_message', l_final_text);
      end if;
    end if;
    
    -- Add provider info to the result
    l_result.put('provider', 'anthropic');

    -- add system prompt as first mesage (consistent with OpenAI)
    if p_system_prompt is not null then
      l_message := json_object_t();
      l_message.put('role', 'system');
      l_message.put('content', p_system_prompt);

      l_end_messages.append(l_message);

      <<add_other_messages>>
      for i in 0 .. l_messages.get_size - 1
      loop
        l_message := treat(l_messages.get(i) as json_object_t);
        l_end_messages.append(l_message);
      end loop add_other_messages;

      l_result.put('messages', l_end_messages);
    end if;
    
    return l_result;
  end generate_text;

end uc_ai_anthropic;
/
