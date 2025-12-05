create or replace package body uc_ai_anthropic as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'https://api.anthropic.com/v1/messages';
  c_anthropic_version constant varchar2(32 char) := '2023-06-01';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  -- Chat API reference: https://docs.anthropic.com/en/api/messages

  function get_text_content (
    p_message in json_object_t
  ) return json_object_t
  as
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    l_content := p_message.get_clob('text');
    l_provider_options := p_message.clone();
    l_provider_options.remove('type');
    l_provider_options.remove('text');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    g_final_message := l_content;

    return l_lm_text_content;
  end get_text_content;


  function get_reasoning_content(
    p_message in json_object_t
  ) return json_object_t
  as
    l_reasoning_content clob;
    l_provider_options json_object_t;
    l_lm_reasoning_content json_object_t;
  begin
    l_reasoning_content := p_message.get_clob('thinking');
    l_provider_options := p_message.clone();
    l_provider_options.remove('type');
    l_provider_options.remove('thinking');

    l_lm_reasoning_content := uc_ai_message_api.create_reasoning_content(
      p_text             => l_reasoning_content
    , p_provider_options => l_provider_options
    );

    return l_lm_reasoning_content;
  end get_reasoning_content;

  /*
   * Convert standardized Language Model messages to Anthropic format
   * Returns Anthropic-compatible messages array that can be sent directly to Anthropic API
   * Also extracts system prompt separately since Anthropic uses a separate system field
   */
  procedure convert_lm_messages_to_anthropic(
    p_lm_messages in json_array_t,
    po_system_prompt out clob,
    po_anthropic_messages out json_array_t
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_lm_messages_to_anthropic';
    l_lm_message json_object_t;
    l_anthropic_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_anthropic_content json_array_t;
    l_tool_use json_object_t;
    l_tool_result json_object_t;
  begin
    uc_ai_logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to Anthropic format', l_scope);
    
    po_system_prompt := null;
    po_anthropic_messages := json_array_t();

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');

      case l_role
        when 'system' then
          -- System message: extract content for separate system field
          po_system_prompt := l_lm_message.get_clob('content');

        when 'user' then
          -- User message: extract content from content array
          l_content := l_lm_message.get_array('content');
          l_anthropic_content := json_array_t();
          
          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text content block
                declare
                  l_text_block json_object_t := json_object_t();
                begin
                  l_text_block.put('type', 'text');
                  l_text_block.put('text', l_content_item.get_clob('text'));
                  l_anthropic_content.append(l_text_block);
                end;
              when 'file' then
                declare
                  l_data       clob;
                  l_mime_type  varchar2(4000 char);
                  l_file_block json_object_t;
                begin
                  l_data := l_content_item.get_clob('data');
                  l_mime_type := l_content_item.get_string('mediaType');
                  l_file_block := json_object_t();

                  -- PDF doc: https://docs.anthropic.com/en/docs/build-with-claude/pdf-support#option-2%3A-base64-encoded-pdf-document
                  if l_mime_type = 'application/pdf' then
                    l_file_block.put('type', 'document');
                    l_file_block.put('source', json_object_t('{"type": "base64", "media_type": "application/pdf", "data": "' || l_data || '"}'));

                  -- image doc: https://docs.anthropic.com/en/docs/build-with-claude/vision#base64-encoded-image-example
                  elsif l_mime_type in ('image/jpeg', 'image/png', 'image/gif', 'image/webp') then
                    l_file_block.put('type', 'image');
                    l_file_block.put('source', json_object_t('{"type": "base64", "media_type": "' || l_mime_type || '", "data": "' || l_data || '"}'));

                  else
                    uc_ai_logger.log_error('Unsupported file type: ' || l_mime_type, l_scope, l_content_item.stringify);
                    raise uc_ai.e_unhandled_format;
                  end if;
                  
                  l_anthropic_content.append(l_file_block);
                end;
              else
                uc_ai_logger.log_error('Unknown content type in user message: ' || l_content_type, l_scope, l_content_item.stringify);
                raise uc_ai.e_unhandled_format;
            end case;
          end loop user_content_loop;
          
          if l_anthropic_content.get_size > 0 then
            l_anthropic_message := json_object_t();
            l_anthropic_message.put('role', 'user');
            l_anthropic_message.put('content', l_anthropic_content);
            po_anthropic_messages.append(l_anthropic_message);
          end if;

        when 'assistant' then
          -- Assistant message: can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          l_anthropic_content := json_array_t();
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text content block
                declare
                  l_text_block json_object_t := json_object_t();
                begin
                  l_text_block.put('type', 'text');
                  l_text_block.put('text', l_content_item.get_clob('text'));
                  l_anthropic_content.append(l_text_block);
                end;
              when 'tool_call' then
                -- Convert tool call to Anthropic tool_use format
                l_tool_use := json_object_t();
                l_tool_use.put('type', 'tool_use');
                l_tool_use.put('id', l_content_item.get_string('toolCallId'));
                l_tool_use.put('name', l_content_item.get_string('toolName'));
                
                -- Parse arguments JSON string to object
                declare
                  l_args_obj json_object_t;
                begin
                  l_args_obj := json_object_t.parse(l_content_item.get_clob('args'));
                  l_tool_use.put('input', l_args_obj);
                exception
                  when others then
                    uc_ai_logger.log_warning('Failed to parse tool call arguments JSON: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope, l_content_item.get_clob('args'));
                    -- If parsing fails, create empty input object
                    l_tool_use.put('input', json_object_t());
                end;
                
                l_anthropic_content.append(l_tool_use);
              else
                null; -- Skip unknown content types
            end case;
          end loop assistant_content_loop;
          
          if l_anthropic_content.get_size > 0 then
            l_anthropic_message := json_object_t();
            l_anthropic_message.put('role', 'assistant');
            l_anthropic_message.put('content', l_anthropic_content);
            po_anthropic_messages.append(l_anthropic_message);
          end if;

        when 'tool' then
          -- Tool message: convert tool results to Anthropic user message with tool_result content
          l_content := l_lm_message.get_array('content');
          l_anthropic_content := json_array_t();
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              -- Create tool_result content block
              l_tool_result := json_object_t();
              l_tool_result.put('type', 'tool_result');
              l_tool_result.put('tool_use_id', l_content_item.get_string('toolCallId'));
              l_tool_result.put('content', l_content_item.get_clob('result'));
              
              l_anthropic_content.append(l_tool_result);
            end if;
          end loop tool_content_loop;
          
          if l_anthropic_content.get_size > 0 then
            l_anthropic_message := json_object_t();
            l_anthropic_message.put('role', 'user');
            l_anthropic_message.put('content', l_anthropic_content);
            po_anthropic_messages.append(l_anthropic_message);
          end if;

        else
          uc_ai_logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    uc_ai_logger.log('Converted to ' || po_anthropic_messages.get_size || ' Anthropic messages', l_scope);
    if po_system_prompt is not null then
      uc_ai_logger.log('Extracted system prompt', l_scope, po_system_prompt);
    end if;
  end convert_lm_messages_to_anthropic;



  procedure internal_generate_text (
    pio_messages         in out json_array_t
  , p_system_prompt      in clob
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out json_object_t
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'internal_generate_text';
    l_input_obj    json_object_t;

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_content   json_array_t;
    l_content_prompt json_object_t;
    l_stop_reason varchar2(255 char);
    l_usage     json_object_t;
    l_model     varchar2(255 char);
    l_content_type varchar2(64 char);
    l_web_credential varchar2(255 char);
    
    l_has_tool_use boolean := false;
  begin
    if g_tool_calls >= p_max_tool_calls then
      uc_ai_logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_input_obj := p_input_obj;
    l_input_obj.put('messages', pio_messages);
    
    -- Add system prompt if provided (Anthropic uses separate system field)
    if p_system_prompt is not null then
      l_input_obj.put('system', p_system_prompt);
    end if;

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.g_request_headers(1).name := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';
    apex_web_service.g_request_headers(2).name := 'anthropic-version';
    apex_web_service.g_request_headers(2).value := c_anthropic_version;

    l_web_credential := coalesce(uc_ai.g_apex_web_credential, g_apex_web_credential);
    if l_web_credential is null then
      apex_web_service.g_request_headers(3).name := 'x-api-key';
      apex_web_service.g_request_headers(3).value := uc_ai_get_key(uc_ai.c_provider_anthropic);
    end if;

    l_resp := apex_web_service.make_rest_request(
      p_url => c_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => l_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      uc_ai_logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
      uc_ai_logger.log_error('Error message: ', l_scope, l_temp_obj.get_string('message'));
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
      l_content_prompt := treat(l_content.get(i) as json_object_t);
      l_content_type := l_content_prompt.get_string('type');
      uc_ai_logger.log('Content block type: ' || l_content_type, l_scope);
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
        l_tool_call_id varchar2(255 CHAR);
        l_tool_name       uc_ai_tools.code%type;
        l_tool_input      json_object_t;
        l_tool_result     clob;
        l_new_msg         json_object_t;
        l_param_name      uc_ai_tool_parameters.name%type;

        l_normalized_messages     json_array_t := json_array_t();
        l_normalized_tool_results json_array_t := json_array_t();
      begin
        -- Add AI's message with content (including tool_use blocks) to conversation history
        l_resp_message.put('role', 'assistant');
        l_resp_message.put('content', l_content);
        pio_messages.append(l_resp_message);

        -- Execute each tool call and collect results
        <<tool_use_loop>>
        for j in 0 .. l_content.get_size - 1
        loop
          l_content_prompt := treat(l_content.get(j) as json_object_t);
          
          case l_content_prompt.get_string('type')
            when 'tool_use' then
              uc_ai_logger.log('Executing tool use', l_scope, l_content_prompt.to_clob);

              g_tool_calls := g_tool_calls + 1;
   
              l_tool_call_id := l_content_prompt.get_string('id');
              l_tool_name := l_content_prompt.get_string('name');
              l_tool_input := l_content_prompt.get_object('input');
              if l_tool_input is not null then
                l_param_name := uc_ai_tools_api.get_tools_object_param_name(l_tool_name);
                if l_param_name is not null then
                  l_tool_input := l_tool_input.get_object(l_param_name);
                end if;
              end if;
   
              l_new_msg := uc_ai_message_api.create_tool_call_content(
                p_tool_call_id => l_tool_call_id
              , p_tool_name    => l_tool_name
              , p_args         => l_tool_input.to_clob
              );
              l_normalized_messages.append(l_new_msg);
   
              uc_ai_logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name || ', Tool ID: ' || l_tool_call_id);
              if l_tool_input is not null then
                uc_ai_logger.log('Tool input', l_scope, 'Input: ' || l_tool_input.to_clob);
              else
                uc_ai_logger.log('Tool input', l_scope, 'No input provided');
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
              l_tool_result_obj.put('tool_use_id', l_tool_call_id);
              l_tool_result_obj.put('content', l_tool_result);
              l_tool_results.append(l_tool_result_obj);
             
              l_new_msg := uc_ai_message_api.create_tool_result_content(
                p_tool_call_id => l_tool_call_id,
                p_tool_name    => l_tool_name,
                p_result       => l_tool_result
              );
              l_normalized_tool_results.append(l_new_msg);
            when 'text' then
              uc_ai_logger.log('Text content block found', l_scope, l_content_prompt.to_clob);
   
              l_new_msg := get_text_content(l_content_prompt);
              l_normalized_messages.append(l_new_msg);
            else
              uc_ai_logger.log_error('Unsupported content type in tool use: ' || l_content_prompt.get_string('type'), l_scope, l_content_prompt.to_clob);
              raise_application_error(-20001, 'Unsupported content type: ' || l_content_prompt.get_string('type'));
          end case;
        end loop tool_use_loop;

        g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));
        g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));


        pio_result.put('tool_calls_count', g_tool_calls);

        -- Add tool results as new user message with tool_result content
        l_new_msg := json_object_t();
        l_new_msg.put('role', 'user');
        l_new_msg.put('content', l_tool_results);
        pio_messages.append(l_new_msg);

        -- Continue conversation with tool results - recursive call
        internal_generate_text(
          pio_messages         => pio_messages
        , p_system_prompt      => p_system_prompt
        , p_max_tool_calls     => p_max_tool_calls
        , p_input_obj          => p_input_obj
        , pio_result           => pio_result
        );
      end;
    else
      -- Normal completion - add AI's message to conversation

      declare
        l_content_msg       json_object_t;
        l_content_array     json_array_t := json_array_t();
        l_assistant_message json_object_t;
      begin
        <<content_loop>>
        for i in 0 .. l_content.get_size - 1
        loop
          l_content_prompt := treat(l_content.get(i) as json_object_t);
          l_content_type := l_content_prompt.get_string('type');
      
          case l_content_type
            when 'text' then
              l_content_msg := get_text_content(l_content_prompt);
              l_content_array.append(l_content_msg);
            when 'thinking' then
              l_content_msg := get_reasoning_content(l_content_prompt);
              l_content_array.append(l_content_msg);
            else
              uc_ai_logger.log_error('Unknown content type: ' || l_content_type, l_scope, l_content_prompt.to_clob);
              raise_application_error(-20001, 'Unsupported content type: ' || l_content_type);
          end case; 

          pio_messages.append(l_content_prompt);
        end loop content_loop;

        l_assistant_message := uc_ai_message_api.create_assistant_message(
          p_content => l_content_array
        );
        g_normalized_messages.append(l_assistant_message);
      end;

      pio_messages.append(l_content_prompt);
    end if;

    uc_ai_logger.log('End internal_generate_text - final messages count: ' || pio_messages.get_size, l_scope);

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
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_text_with_messages';
    l_input_obj          json_object_t := json_object_t();
    l_anthropic_messages json_array_t;
    l_system_prompt      clob;
    l_tools              json_array_t;
    l_reasoning          json_object_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_reasoning_tokens   pls_integer;
  begin
    l_result := json_object_t();
    uc_ai_logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);
    
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
    
    -- Initialize result object with default values
    l_result.put('tool_calls_count', 0);
    l_result.put('finish_reason', 'unknown');
    
    -- Convert standardized messages to Anthropic format
    convert_lm_messages_to_anthropic(
      p_lm_messages => p_messages,
      po_anthropic_messages => l_anthropic_messages,
      po_system_prompt => l_system_prompt
    );

    l_input_obj.put('model', p_model);

    -- Get all available tools formatted for Anthropic
    l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_anthropic);

    if l_tools.get_size > 0 then
      l_input_obj.put('tools', l_tools);
    end if;

    if uc_ai.g_enable_reasoning then
      l_reasoning := json_object_t();
      l_reasoning.put('type', 'enabled');
      if g_reasoning_budget_tokens is not null then
        l_reasoning_tokens := g_reasoning_budget_tokens;
      elsif uc_ai.g_reasoning_level is not null then
        l_reasoning_tokens := case uc_ai.g_reasoning_level
          when uc_ai.c_reasoning_level_low then 2048
          when uc_ai.c_reasoning_level_medium then 8192
          when uc_ai.c_reasoning_level_high then 32768
          else uc_ai.g_reasoning_level
        end;
      end if;
      uc_ai_logger.log_info('Using reasoning with budget tokens: ' || l_reasoning_tokens, l_scope);
      l_reasoning.put('budget_tokens', l_reasoning_tokens);
      l_input_obj.put('thinking', l_reasoning);
    end if;

    if g_max_tokens < l_reasoning_tokens then
      raise_application_error(-20001, 'Reasoning budget tokens (' || l_reasoning_tokens || ') exceed max tokens allowed (' || g_max_tokens || '). Set a higher max tokens value (uc_ai_anthropic.g_max_tokens).');
    end if;

    l_input_obj.put('max_tokens', g_max_tokens); -- Anthropic requires max_tokens

    internal_generate_text(
      pio_messages         => l_anthropic_messages
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
    l_result.put('provider', uc_ai.c_provider_anthropic);
    
    uc_ai_logger.log('Completed generate_text with final message count: ' || g_normalized_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

end uc_ai_anthropic;
/
