create or replace package body uc_ai_ollama as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'http://localhost:1143/api';
  c_api_generate_text_path constant varchar2(255 char) := '/chat';
  c_api_generate_embeddings_path constant varchar2(255 char) := '/embed';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  -- Chat API reference: https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion

  function get_generate_text_url return varchar2
  as
  begin
    if uc_ai.g_base_url is not null then
      return rtrim(uc_ai.g_base_url, '/') || c_api_generate_text_path;
    end if;
    
    return c_api_url || c_api_generate_text_path;
  end get_generate_text_url;

  function get_generate_embeddings_url return varchar2
  as
  begin
    if uc_ai.g_base_url is not null then
      return rtrim(uc_ai.g_base_url, '/') || c_api_generate_embeddings_path;
    end if;

    return c_api_url || c_api_generate_embeddings_path;
  end get_generate_embeddings_url;

  function get_text_content (
    p_message in json_object_t
  ) return json_object_t
  as
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    l_content := p_message.get_clob('content');
    -- for example when only reasoning is present
    if l_content is null or length(trim(l_content)) = 0 then
      return null; -- No content to process
    end if;

    l_provider_options := p_message.clone();
    l_provider_options.remove('role');
    l_provider_options.remove('content');
    l_provider_options.remove('thinking');
    l_provider_options.remove('tool_calls');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    g_final_message := l_content;

    return l_lm_text_content;
  end get_text_content;

  function get_reasoning_content (
    p_message in json_object_t
  ) return json_object_t
  as
    l_thinking clob;
    l_provider_options json_object_t;
  begin
    l_thinking := p_message.get_clob('thinking');
    if l_thinking is null or length(trim(l_thinking)) = 0 then
      return null; -- No reasoning to process
    end if;

    l_provider_options := p_message.clone();
    l_provider_options.remove('role');
    l_provider_options.remove('thinking');
    l_provider_options.remove('content');
    l_provider_options.remove('tool_calls');

    return uc_ai_message_api.create_reasoning_content(
      p_text => l_thinking,
      p_provider_options => l_provider_options
    );
  end get_reasoning_content;

  function process_llm_response(
    p_message in json_object_t
  ) return json_array_t
  as
    l_lm_text_content  json_object_t;
    l_lm_reasoning_content json_object_t;
    l_arr json_array_t;
  begin
    l_lm_text_content := get_text_content(p_message);
    l_lm_reasoning_content := get_reasoning_content(p_message);

    if l_lm_reasoning_content is null and l_lm_text_content is null then
      logger.LOG_ERROR(
        'No content to process response',
        c_scope_prefix || 'process_llm_response',
        p_message.to_clob
      );
      raise uc_ai.e_format_processing_error;
    end if;

    l_arr := json_array_t();
    if l_lm_reasoning_content is not null then
      l_arr.append(l_lm_reasoning_content);
    end if;
    if l_lm_text_content is not null then
      l_arr.append(l_lm_text_content);
    end if;

    return l_arr;
  end process_llm_response;


  /*
   * Convert standardized Language Model messages to Ollama format
   * Returns Ollama-compatible messages array that can be sent directly to Ollama API
   * Ollama uses OpenAI-compatible message format: role + content
   */
  procedure convert_lm_messages_to_ollama(
    p_lm_messages in json_array_t,
    po_ollama_messages out nocopy json_array_t
  )
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'convert_lm_messages_to_ollama';
    l_lm_message json_object_t;
    l_ollama_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_ollama_content varchar2(32767 char);
    l_images json_array_t;
    l_tool_calls json_array_t;
    l_tool_call json_object_t;
    l_function json_object_t;
  begin
    logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to Ollama format', l_scope);
    
    po_ollama_messages := json_array_t();

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');

      case l_role
        when 'system' then
          -- System message: keep as-is (Ollama supports system messages)
          l_ollama_message := json_object_t();
          l_ollama_message.put('role', 'system');
          l_ollama_message.put('content', l_lm_message.get_clob('content'));
          po_ollama_messages.append(l_ollama_message);

        when 'user' then
          -- User message: extract content from content array
          l_content := l_lm_message.get_array('content');
          l_ollama_content := null;
          l_images := json_array_t();

          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                l_ollama_content := l_ollama_content || l_content_item.get_clob('text');
              when 'file' then
                l_images.append(l_content_item.get_clob('data'));
              else
                logger.log_warn('Unsupported user content type for Ollama: ' || l_content_type, l_scope);
            end case;
          end loop user_content_loop;
          
          if length(l_ollama_content) > 0 then
            l_ollama_message := json_object_t();
            l_ollama_message.put('role', 'user');
            l_ollama_message.put('content', l_ollama_content);
            if l_images.get_size > 0 then
              l_ollama_message.put('images', l_images);
            end if;
            po_ollama_messages.append(l_ollama_message);
          end if;

        when 'assistant' then
          -- Assistant message: can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          l_ollama_content := null;
          l_tool_calls := json_array_t();
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                l_ollama_content := l_ollama_content || l_content_item.get_clob('text');
              when 'tool_call' then
                -- Convert to OpenAI-style tool call format that Ollama expects
                l_tool_call := json_object_t();
                l_tool_call.put('id', l_content_item.get_string('toolCallId'));
                l_tool_call.put('type', 'function');
                
                l_function := json_object_t();
                l_function.put('name', l_content_item.get_string('toolName'));
                l_function.put('arguments', l_content_item.get_clob('args'));
                
                l_tool_call.put('function', l_function);
                l_tool_calls.append(l_tool_call);
              else
                logger.log_warn('Unsupported assistant content type for Ollama: ' || l_content_type, l_scope);
            end case;
          end loop assistant_content_loop;
          
          l_ollama_message := json_object_t();
          l_ollama_message.put('role', 'assistant');
          l_ollama_message.put('content', l_ollama_content);
          
          -- Add tool calls if any
          if l_tool_calls.get_size > 0 then
            l_ollama_message.put('tool_calls', l_tool_calls);
          end if;
          
          po_ollama_messages.append(l_ollama_message);

        when 'tool' then
          -- Tool message: convert tool results to OpenAI-style tool messages
          l_content := l_lm_message.get_array('content');
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              -- Create separate tool message for each result (like OpenAI)
              l_ollama_message := json_object_t();
              l_ollama_message.put('role', 'tool');
              l_ollama_message.put('content', l_content_item.get_clob('result'));
              l_ollama_message.put('tool_call_id', l_content_item.get_string('toolCallId'));
              po_ollama_messages.append(l_ollama_message);
            end if;
          end loop tool_content_loop;

        else
          logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    logger.log('Converted to ' || po_ollama_messages.get_size || ' Ollama messages', l_scope);
  end convert_lm_messages_to_ollama;



  procedure internal_generate_text (
    pio_messages         in out nocopy json_array_t
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out nocopy json_object_t
  )
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'internal_generate_text';
    l_input_obj    json_object_t;

    l_resp          clob;
    l_resp_json     json_object_t;
    l_message       json_object_t;
    l_tool_calls    json_array_t;
    l_finish_reason varchar2(255 char);
    l_usage     json_object_t;
    l_model     varchar2(255 char);

    l_assistant_content json_array_t;
    l_assistant_message json_object_t;

    l_has_tool_calls boolean := false;
  begin
    if g_tool_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_input_obj := p_input_obj;
    l_input_obj.put('messages', pio_messages);
    l_input_obj.put('think', uc_ai.g_enable_reasoning);

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json'
    );

    l_resp := apex_web_service.make_rest_request(
      p_url => get_generate_text_url(),
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => g_apex_web_credential
    );

    logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_resp := l_resp_json.get_clob('error');
      logger.log_error('Error in response', l_scope, l_resp);
      raise uc_ai.e_error_response;
    end if;

    -- Extract and store usage information (if available in Ollama response)
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
          -- Add compatibility names
          l_existing_usage.put('input_tokens', l_prompt_tokens);
          l_existing_usage.put('output_tokens', l_completion_tokens);
        end;
      else
        -- Add compatibility names for consistency with other providers
        l_usage.put('input_tokens', nvl(l_usage.get_number('prompt_tokens'), 0));
        l_usage.put('output_tokens', nvl(l_usage.get_number('completion_tokens'), 0));
        l_usage.put('total_tokens', nvl(l_usage.get_number('prompt_tokens'), 0) + nvl(l_usage.get_number('completion_tokens'), 0));
        pio_result.put('usage', l_usage);
      end if;
    end if;

    -- Extract model information
    if l_resp_json.has('model') then
      l_model := l_resp_json.get_string('model');
      pio_result.put('model', l_model);
    end if;

    -- Extract message from response
    l_message := l_resp_json.get_object('message');
    
    -- Check if response contains tool calls
    if l_message.has('tool_calls') then
      l_tool_calls := l_message.get_array('tool_calls');
      l_has_tool_calls := l_tool_calls.get_size > 0;
    end if;

    -- add response text to global messages
    l_assistant_content := process_llm_response(l_message);

    if l_has_tool_calls then
      -- AI wants to call tools - extract calls, execute them, add results to conversation
      declare
        l_resp_message        json_object_t := json_object_t();
        l_tool_call           json_object_t;
        l_tool_call_id        varchar2(255 CHAR);
        l_tool_name           uc_ai_tools.code%type;
        l_tool_input          json_object_t;
        l_tool_result         clob;
        l_new_msg             json_object_t;
        l_function            json_object_t;

        l_normalized_tool_results json_array_t := json_array_t();
      begin
        -- Add AI's message with tool calls to conversation history
        l_resp_message.put('role', 'assistant');
        l_resp_message.put('content', nvl(l_message.get_clob('content'), null));
        l_resp_message.put('tool_calls', l_tool_calls);
        pio_messages.append(l_resp_message);

        -- Process each tool call and collect results
        <<tool_calls_loop>>
        for j in 0 .. l_tool_calls.get_size - 1
        loop
          l_tool_call := treat(l_tool_calls.get(j) as json_object_t);
          logger.log('Processing tool call', l_scope, 'Tool Call: ' || l_tool_call.to_clob);
          
          g_tool_calls := g_tool_calls + 1;

          l_tool_call_id := 'tool_call_' || g_tool_calls; -- Generate unique ID for tool call
          l_function := l_tool_call.get_object('function');
          l_tool_name := l_function.get_string('name');
          
          -- Parse tool arguments
          if l_function.has('arguments') then
            l_tool_input := l_function.get_object('arguments');
          else
            l_tool_input := json_object_t();
          end if;

          l_new_msg := uc_ai_message_api.create_tool_call_content(
            p_tool_call_id => l_tool_call_id
          , p_tool_name    => l_tool_name
          , p_args         => l_tool_input.to_clob
          );
          l_assistant_content.append(l_new_msg);

          logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name || ', Tool ID: ' || l_tool_call_id);
          logger.log('Tool input', l_scope, 'Input: ' || l_tool_input.to_clob);

          -- Execute the tool and get result
          l_tool_result := uc_ai_tools_api.execute_tool(
            p_tool_code          => l_tool_name
          , p_arguments          => l_tool_input
          );

          -- Create tool result message for Ollama format
          l_new_msg := json_object_t();
          l_new_msg.put('role', 'tool');
          l_new_msg.put('content', l_tool_result);
          l_new_msg.put('tool_name', l_tool_name);
          pio_messages.append(l_new_msg);
           
          l_normalized_tool_results.append(uc_ai_message_api.create_tool_result_content(
            p_tool_call_id => l_tool_call_id
          , p_tool_name    => l_tool_name
          , p_result       => l_tool_result
          ));
        end loop tool_calls_loop;


        l_assistant_message := uc_ai_message_api.create_assistant_message(
          p_content => l_assistant_content
        );
        g_normalized_messages.append(l_assistant_message);

        g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));

        pio_result.put('tool_calls_count', g_tool_calls);

        -- Continue conversation with tool results - recursive call
        internal_generate_text(
          pio_messages         => pio_messages
        , p_max_tool_calls     => p_max_tool_calls
        , p_input_obj          => p_input_obj
        , pio_result           => pio_result
        );
      end;
    else
      -- Normal completion - add AI's message to conversation
      logger.log('Normal completion received', l_scope);
      pio_messages.append(l_message);

      l_assistant_message := uc_ai_message_api.create_assistant_message(
        p_content => l_assistant_content
      );
      g_normalized_messages.append(l_assistant_message);
    end if;


    -- Extract finish reason (if available)
    if l_resp_json.has('done_reason') then
      l_finish_reason := l_resp_json.get_string('done_reason');
    end if;
    
    -- Map finish reasons to standard format
    if l_has_tool_calls then
      -- ollama uses stop even for tool calls
      l_finish_reason := uc_ai.c_finish_reason_tool_calls;
    else
      case l_finish_reason
        when 'stop' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
        when 'length' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
        when 'content_filter' then
          pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
        else
          pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
      end case;
    end if;

    logger.log('End internal_generate_text - final messages count: ' || pio_messages.get_size, l_scope);

  end internal_generate_text;


  /*
   * Core conversation handler with Ollama API
   * 
   * Critical workflow for AI function calling:
   * 1. Sends messages + available tools to Ollama API  
   * 2. If response contains tool_calls: extracts tool calls, executes each tool,
   *    adds tool results as new tool messages, recursively calls itself
   * 3. Continues until no more tool calls (conversation complete)
   * 4. g_tool_calls counter prevents infinite loops
   * 
   * Tool execution flow:
   * - AI returns message with tool_calls array [id, function: {name, arguments}]
   * - We execute each tool via uc_ai_tools_api.execute_tool()
   * - Add tool results as tool messages with content and tool_call_id
   * - Send updated conversation back to API
   * 
   * Returns comprehensive result object with:
   * - messages: full conversation history
   * - final_message: last message content for simple usage
   * - structured_output: parsed JSON object (when schema provided)
   * - finish_reason: completion reason (stop, tool_calls, length, etc.)
   * - usage: token usage statistics (if provided by Ollama)
   * - tool_calls_count: total number of tool calls executed
   * - model: Ollama model used
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  ) return json_object_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'generate_text_with_messages';
    l_input_obj          json_object_t := json_object_t();
    l_ollama_messages    json_array_t;
    l_tools              json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_format             json_object_t;
  begin
    l_result := json_object_t();
    logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);
    
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
    
    -- Convert standardized messages to Ollama format
    convert_lm_messages_to_ollama(
      p_lm_messages => p_messages,
      po_ollama_messages => l_ollama_messages
    );

    l_input_obj.put('model', p_model);
    l_input_obj.put('stream', false); -- We want the complete response, not streaming

    -- Add structured output format if schema is provided
    if p_schema is not null then
      l_format := uc_ai_structured_output.to_ollama_format(p_schema);
      l_input_obj.put('format', l_format);
    end if;

    -- Get all available tools formatted for Ollama (if tools are enabled)
    if uc_ai.g_enable_tools then
      l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_ollama);

      if l_tools.get_size > 0 then
        l_input_obj.put('tools', l_tools);
      end if;
    end if;

    internal_generate_text(
      pio_messages         => l_ollama_messages
    , p_max_tool_calls     => p_max_tool_calls
    , p_input_obj          => l_input_obj
    , pio_result           => l_result
    );

    -- Add final messages to result (already in standardized format from global variable)
    l_result.put('messages', g_normalized_messages);
    
    -- Add final message (only the text)
    l_result.put('final_message', g_final_message);
 
    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_ollama);
    
    logger.log('Completed generate_text with final message count: ' || g_normalized_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

  function generate_embeddings (
    p_input in json_array_t
  , p_model in uc_ai.model_type
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'generate_embeddings';
    l_url           varchar2(4000 char);
    l_resp          clob;
    l_resp_json     json_object_t;
    l_embeddings    json_array_t;
    l_input_obj     json_object_t := json_object_t();
  begin
    logger.log('Starting generate_embeddings with ' || p_input.get_size || ' input items',
      l_scope);
    
    l_input_obj.put('model', p_model);
    l_input_obj.put('input', p_input);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'content-type',
      p_value_01 => 'application/json'
    );

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    l_url := get_generate_embeddings_url();
    logger.log('Request URL: ' || l_url, l_scope);

    l_resp := apex_web_service.make_rest_request(
      p_url => l_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => g_apex_web_credential
    );

    logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);
    l_embeddings := l_resp_json.get_array('embeddings');

    return l_embeddings;
  end generate_embeddings;

end uc_ai_ollama;
/
