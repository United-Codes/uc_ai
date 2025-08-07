create or replace package body uc_ai_oci as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url_base constant varchar2(255 char) := 'https://inference.generativeai.';
  c_api_endpoint constant varchar2(255 char) := '/20231130/actions/chat';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  -- OCI Generative AI reference: https://docs.oracle.com/en-us/iaas/api/#/en/generative-ai-inference/20231130/
  function get_text_content (
    p_message in json_object_t
  ) return json_object_t
  as
    l_message json_object_t;
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    l_message := p_message.clone();

    if l_message.get_string('type') != 'TEXT' then
      logger.log_error('Message type is not TEXT.', c_scope_prefix || 'get_text_content', l_message.to_clob);
      raise uc_ai.e_unhandled_format;
    end if;

    l_content := l_message.get_clob('text');
    l_provider_options := l_message.clone();
    l_provider_options.remove('text');
    l_provider_options.remove('type');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    g_final_message := l_content;

    return l_lm_text_content;
  end get_text_content;

  /*
   * Convert standardized Language Model messages to OCI format
   * Returns OCI-compatible messages array that can be sent directly to OCI Generative AI API
   * OCI uses a messages array similar to OpenAI but with specific content structure
   */
  procedure convert_lm_messages_to_oci(
    p_lm_messages in json_array_t,
    po_oci_messages out json_array_t
  )
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'convert_lm_messages_to_oci';
    l_lm_message json_object_t;
    l_oci_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_oci_content json_array_t;
    l_oci_content_item json_object_t;
  begin
    logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to OCI format', l_scope);
    
    po_oci_messages := json_array_t();

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');

      case l_role
        when 'system' then
          -- System messages are typically handled as the first user message in OCI
          l_oci_content := json_array_t();
          l_oci_content_item := json_object_t();
          l_oci_content_item.put('type', 'TEXT');
          l_oci_content_item.put('text', l_lm_message.get_clob('content'));
          l_oci_content.append(l_oci_content_item);
          
          l_oci_message := json_object_t();
          l_oci_message.put('role', 'SYSTEM');
          l_oci_message.put('content', l_oci_content);
          po_oci_messages.append(l_oci_message);

        when 'user' then
          -- User message: extract content from content array
          l_content := l_lm_message.get_array('content');
          l_oci_content := json_array_t();
          
          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text content
                l_oci_content_item := json_object_t();
                l_oci_content_item.put('type', 'TEXT');
                l_oci_content_item.put('text', l_content_item.get_clob('text'));
                l_oci_content.append(l_oci_content_item);
              when 'file' then
                -- OCI supports file content in specific formats
                l_oci_content_item := json_object_t();
                l_oci_content_item.put('type', 'IMAGE'); -- or other supported types
                -- Note: OCI may require different format for file content
                -- This would need to be adapted based on OCI's exact requirements
                l_oci_content_item.put('data', l_content_item.get_clob('data'));
                l_oci_content_item.put('mediaType', l_content_item.get_string('mediaType'));
                l_oci_content.append(l_oci_content_item);
            end case;
          end loop user_content_loop;
          
          if l_oci_content.get_size > 0 then
            l_oci_message := json_object_t();
            l_oci_message.put('role', 'USER');
            l_oci_message.put('content', l_oci_content);
            po_oci_messages.append(l_oci_message);
          end if;

        when 'assistant' then
          -- Assistant message: convert to ASSISTANT role
          l_content := l_lm_message.get_array('content');
          l_oci_content := json_array_t();
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text content
                l_oci_content_item := json_object_t();
                l_oci_content_item.put('type', 'TEXT');
                l_oci_content_item.put('text', l_content_item.get_clob('text'));
                l_oci_content.append(l_oci_content_item);
              when 'tool_call' then
                -- OCI tool calls handling would need to be implemented based on OCI's format
                -- For now, we'll convert to text description
                l_oci_content_item := json_object_t();
                l_oci_content_item.put('type', 'TEXT');
                l_oci_content_item.put('text', 'Tool call: ' || l_content_item.get_string('toolName'));
                l_oci_content.append(l_oci_content_item);
              else
                null; -- Skip unknown content types
            end case;
          end loop assistant_content_loop;
          
          if l_oci_content.get_size > 0 then
            l_oci_message := json_object_t();
            l_oci_message.put('role', 'ASSISTANT');
            l_oci_message.put('content', l_oci_content);
            po_oci_messages.append(l_oci_message);
          end if;

        when 'tool' then
          -- Tool results are typically sent as user messages in OCI
          l_content := l_lm_message.get_array('content');
          l_oci_content := json_array_t();
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              l_oci_content_item := json_object_t();
              l_oci_content_item.put('type', 'TEXT');
              l_oci_content_item.put('text', 'Tool result from ' || l_content_item.get_string('toolName') || ': ' || l_content_item.get_clob('result'));
              l_oci_content.append(l_oci_content_item);
            end if;
          end loop tool_content_loop;
          
          if l_oci_content.get_size > 0 then
            l_oci_message := json_object_t();
            l_oci_message.put('role', 'USER');
            l_oci_message.put('content', l_oci_content);
            po_oci_messages.append(l_oci_message);
          end if;

        else
          logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    logger.log('Converted to ' || po_oci_messages.get_size || ' OCI messages', l_scope);
  end convert_lm_messages_to_oci;

  /*
   * Get OCI region from global setting or use default
   */
  function get_oci_region return varchar2
  as
  begin
    return coalesce(g_region, 'us-ashburn-1');
  end get_oci_region;

  /*
   * Build the full API URL for OCI Generative AI
   */
  function build_api_url return varchar2
  as
    l_region varchar2(64 char);
  begin
    l_region := get_oci_region();
    return c_api_url_base || l_region || '.oci.oraclecloud.com' || c_api_endpoint;
  end build_api_url;

  function internal_generate_text (
    p_messages           in json_array_t
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out json_object_t
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'internal_generate_text';
    l_messages     json_array_t := json_array_t();
    l_input_obj    json_object_t;
    l_chat_request json_object_t;
    l_api_url      varchar2(500 char);

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_chat_response json_object_t;
  begin
    if g_tool_calls >= p_max_tool_calls then
      logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;

    l_messages := p_messages;
    l_input_obj := p_input_obj;
    l_chat_request := l_input_obj.get_object('chatRequest');

    l_chat_request.put('messages', l_messages);
    l_input_obj.put('chatRequest', l_chat_request);

    -- Build API URL
    l_api_url := build_api_url();

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers('Content-Type', 'application/json; charset=utf-8');   

    -- Make the API call using credential (OCI authentication should be configured)
    l_resp := apex_web_service.make_rest_request(
      p_url => l_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => g_apex_web_credential
    );

    logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
      raise uc_ai.e_error_response;
    end if;

    -- Extract model information
    if l_resp_json.has('modelId') then
      pio_result.put('model', l_resp_json.get_string('modelId'));
    end if;

    -- Process OCI response format
    if l_resp_json.has('chatResponse') then
      l_chat_response := l_resp_json.get_object('chatResponse');

      -- OCI response structure is different from OpenAI/Google
      -- It has a direct text response in chatResponse
      if l_chat_response.has('choices') then
        declare
          l_choices json_array_t;
          l_choice json_object_t;
          l_resp_message json_object_t;
          l_role varchar2(255 char);
          l_content_arr json_array_t;
          l_oci_content_item json_object_t;

          l_normalized_messages json_array_t := json_array_t();
          l_normalized_tool_results json_array_t := json_array_t();

          l_used_tool boolean := false;

          l_new_msg json_object_t;
          l_content clob;
          l_oci_content json_array_t;
        begin
          l_choices := l_chat_response.get_array('choices');

          <<choices_loop>>
          for i in 0 .. l_choices.get_size - 1 loop
            l_choice := treat(l_choices.get(i) as json_object_t);
            l_resp_message :=  l_choice.get_object('message');

            l_role := l_resp_message.get_string('role');

            if l_role = 'ASSISTANT' then
              if l_resp_message.has('content') then
                l_content_arr := l_resp_message.get_array('content');

                <<content_loop>>
                for j in 0 .. l_content_arr.get_size - 1 loop
                  l_oci_content_item := treat(l_content_arr.get(j) as json_object_t);
                
                  l_new_msg := get_text_content(l_oci_content_item);
                  l_normalized_messages.append(l_new_msg);
                end loop content_loop;
              elsif l_resp_message.has('toolCalls') then
                declare
                  l_tool_call_arr  json_array_t;
                  l_tool_call_item json_object_t;
                  l_tool_call_id   varchar2(255 char);
                  l_tool_name      uc_ai_tools.code%type;
                  l_tool_args_str  varchar2(32767 char);
                  l_tool_args      json_object_t;
                  l_tool_result    clob;
                  l_tool_response  json_object_t;
                  l_tool_response_content json_object_t;
                  l_tool_content   json_array_t := json_array_t();
                begin
                  l_used_tool := true;
                  l_tool_call_arr := l_resp_message.get_array('toolCalls');

                  l_tool_response := json_object_t();
                  l_tool_response.put('role', 'ASSISTANT');
                  l_tool_response.put('toolCalls', l_tool_call_arr);
                  l_messages.append(l_tool_response);

                  <<tool_calls>>
                  for k in 0 .. l_tool_call_arr.get_size - 1 
                  loop
                    g_tool_calls := g_tool_calls + 1;
                    l_tool_call_item := treat(l_tool_call_arr.get(k) as json_object_t);

                    l_tool_call_id := l_tool_call_item.get_string('id');
                    l_tool_name := l_tool_call_item.get_string('name');
                    l_tool_args_str := l_tool_call_item.get_string('arguments');

                    logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name);

                    if l_tool_args_str is not null then
                      -- Parse tool arguments if available
                      l_tool_args := json_object_t.parse(l_tool_args_str);
                      logger.log('Tool args', l_scope, 'Args: ' || l_tool_args.to_clob);
                    else
                      l_tool_args := json_object_t();
                      logger.log('Tool args', l_scope, 'No args provided');
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

                    logger.log('Tool result', l_scope, l_tool_result);

                    l_tool_response := json_object_t();
                    l_tool_response.put('role', 'TOOL');
                    l_tool_response.put('toolCallId', l_tool_call_id);
                    l_tool_response_content := json_object_t();
                    l_tool_response_content.put('type', 'TEXT');
                    l_tool_response_content.put('text', l_tool_result);
                    l_tool_content.append(l_tool_response_content);
                    l_tool_response.put('content', l_tool_content);
                    l_messages.append(l_tool_response);

                    l_new_msg := uc_ai_message_api.create_tool_result_content(
                      p_tool_call_id => l_tool_call_id,
                      p_tool_name    => l_tool_name,
                      p_result       => l_tool_result
                    );
                    l_normalized_tool_results.append(l_new_msg);

                  end loop tool_calls;
                end;
              end if;

            else
              logger.log_error('Unknown role in OCI response: ' || l_role, l_scope);
            end if;
          end loop choices_loop;
          
          g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));
          

          if l_used_tool then
            g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
            pio_result.put('tool_calls_count', g_tool_calls);

            -- Continue conversation with tool results - recursive call
            l_messages := internal_generate_text(
              p_messages           => l_messages
            , p_max_tool_calls     => p_max_tool_calls
            , p_input_obj          => p_input_obj
            , pio_result           => pio_result
            );
          end if;

          -- Set finish reason to stop for successful completion
          pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
        end;
      else
        logger.log_error('No text in OCI chatResponse', l_scope);
        pio_result.put('finish_reason', 'error');
      end if;
    else
      logger.log_error('No chatResponse in OCI response', l_scope);
      pio_result.put('finish_reason', 'error');
    end if;

    logger.log('End internal_generate_text - final messages count: ' || l_messages.get_size, l_scope);

    return l_messages;

  end internal_generate_text;

  /*
   * Core conversation handler with OCI Generative AI API
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t
  as
    l_scope logger_logs.scope%type := c_scope_prefix || 'generate_text_with_messages';
    l_input_obj          json_object_t := json_object_t();
    l_oci_messages       json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_serving_mode       json_object_t;
    l_chat_request       json_object_t;
    l_tools              json_array_t;
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
    l_result.put('model', p_model);
    
    -- Convert standardized messages to OCI format
    convert_lm_messages_to_oci(
      p_lm_messages => p_messages,
      po_oci_messages => l_oci_messages
    );

    -- Build OCI request structure
    -- Set compartment ID (must be configured)
    if g_compartment_id is null then
      logger.log_error('OCI compartment ID not configured', l_scope);
      raise_application_error(-20001, 'OCI compartment ID (g_compartment_id) must be configured');
    end if;
    
    l_input_obj.put('compartmentId', g_compartment_id);
    
    -- Set serving mode
    l_serving_mode := json_object_t();
    l_serving_mode.put('modelId', p_model);
    l_serving_mode.put('servingType', coalesce(g_serving_type, 'ON_DEMAND'));
    l_input_obj.put('servingMode', l_serving_mode);
    
    -- Set chat request
    l_chat_request := json_object_t();
    l_chat_request.put('apiFormat', 'GENERIC');
    l_chat_request.put('maxTokens', 600);
    l_chat_request.put('isStream', false);
    l_chat_request.put('numGenerations', 1);
    l_chat_request.put('frequencyPenalty', 0);
    l_chat_request.put('presencePenalty', 0);
    l_chat_request.put('temperature', 1);
    l_chat_request.put('topP', 1.0);
    l_chat_request.put('topK', 1);

    -- Get all available tools formatted for Google (function declarations)
    l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_oci);

    if l_tools.get_size > 0 then
      l_chat_request.put('tools', l_tools);
    end if;
    
    l_input_obj.put('chatRequest', l_chat_request);

    -- Note: Tool support would need to be added here if OCI supports it
    -- This would require additional research into OCI's tool calling capabilities

    l_oci_messages := internal_generate_text(
      p_messages           => l_oci_messages
    , p_max_tool_calls     => p_max_tool_calls
    , p_input_obj          => l_input_obj
    , pio_result           => l_result
    );

    -- Add final messages to result (already in standardized format from global variable)
    l_result.put('messages', g_normalized_messages);
    
    -- Add final message (only the text)
    l_result.put('final_message', g_final_message);
 
    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_oci);
    
    logger.log('Completed generate_text with final message count: ' || g_normalized_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

end uc_ai_oci;
/
