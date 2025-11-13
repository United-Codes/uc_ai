create or replace package body uc_ai_oci as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url_base constant varchar2(255 char) := 'https://inference.generativeai.';
  c_api_endpoint constant varchar2(255 char) := '/20231130/actions/chat';

  g_tool_calls number := 0;  -- Global counter to prevent infinite tool calling loops
  g_normalized_messages json_array_t;  -- Global messages array to keep conversation history
  g_final_message clob;

  gc_mode_generic constant varchar2(255 char) := 'generic';
  gc_mode_cohere  constant varchar2(255 char) := 'cohere';

  g_mode varchar2(255 char) := gc_mode_generic;

  g_cohere_system_prompt clob;
  g_cohere_user_message clob;

  -- OCI Generative AI reference: https://docs.oracle.com/en-us/iaas/api/#/en/generative-ai-inference/20231130/
  function get_text_content_generic (
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
      uc_ai_logger.log_error('Message type is not TEXT.', c_scope_prefix || 'get_text_content_generic', l_message.to_clob);
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
  end get_text_content_generic;


  function get_text_content_cohere (
    p_chat_response in json_object_t
  ) return json_object_t
  as
    l_text             clob;
    l_lm_text_content  json_object_t;
  begin
    if not p_chat_response.has('text') then
      uc_ai_logger.log_error('Cohere response does not contain text field', c_scope_prefix || 'get_text_content_cohere');
      raise uc_ai.e_unhandled_format;
    end if;

    l_text := p_chat_response.get_clob('text');
    g_final_message := l_text;

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text => l_text
    );
    return l_lm_text_content;
  end get_text_content_cohere;

  /*
   * Convert standardized Language Model messages to the generic OCI format
   * Returns OCI generic compatible messages array that can be sent directly to OCI Generative AI API
   * OCI uses a messages array similar to OpenAI but with specific content structure
   */
  procedure convert_lm_messages_to_generic_oci(
    p_lm_messages in json_array_t,
    po_oci_messages out nocopy json_array_t
  )
  as
    l_scope uc_ai_logger.scope%type := c_scope_prefix || 'convert_lm_messages_to_generic_oci';
    l_lm_message json_object_t;
    l_oci_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_oci_content json_array_t;
    l_oci_content_item json_object_t;
  begin
    uc_ai_logger.log('Converting ' || p_lm_messages.get_size || ' LLM messages to OCI generic format', l_scope);
    
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
              -- TODO: validate if this is correct:
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
          uc_ai_logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    uc_ai_logger.log('Converted to ' || po_oci_messages.get_size || ' OCI messages', l_scope);
  end convert_lm_messages_to_generic_oci;

  /*
   * Convert standardized Language Model messages to the cohere OCI format
   * Returns OCI cohere compatible messages array that can be sent directly to OCI Generative AI API
   * OCI uses a messages array similar to OpenAI but with specific content structure
   */
  procedure convert_lm_messages_to_cohere_oci(
    p_lm_messages in json_array_t,
    po_oci_messages out nocopy json_array_t
  )
  as
    l_scope uc_ai_logger.scope%type := c_scope_prefix || 'convert_lm_messages_to_cohere_oci';
    l_lm_message json_object_t;
    l_oci_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_oci_content_item json_object_t;

    l_has_tool_call boolean := false;
    l_tool_call json_object_t;
    l_tool_call_message clob;
    l_tool_calls json_array_t;
  begin
    uc_ai_logger.log('Converting ' || p_lm_messages.get_size || ' LLM messages to OCI cohere format', l_scope, p_lm_messages.to_clob);
    
    po_oci_messages := json_array_t();

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');
      uc_ai_logger.log('Processing LLM message', l_scope, l_lm_message.to_clob);

      case l_role
        when 'system' then
          g_cohere_system_prompt := l_lm_message.get_clob('content');
        when 'user' then
          -- User message: extract content from content array
          l_content := l_lm_message.get_array('content');
          uc_ai_logger.log('User message content', l_scope, l_content.to_clob);

          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text content
                l_oci_message := json_object_t();
                l_oci_message.put('role', 'USER');
                l_oci_message.put('message', l_content_item.get_clob('text'));
                uc_ai_logger.log('Append user message', l_scope, l_oci_message.to_clob);
                po_oci_messages.append(l_oci_message);
              when 'file' then
                uc_ai_logger.log_error('Cohere cannot handle files', l_scope);
                raise uc_ai.e_unhandled_format;
              else
                uc_ai_logger.log_error('Unknown content type in user message: ' || l_content_type, l_scope);
                raise uc_ai.e_unhandled_format;
            end case;
          end loop user_content_loop;
          

        when 'assistant' then
          -- Assistant message: convert to ASSISTANT role
          l_content := l_lm_message.get_array('content');

          <<check_if_has_tool_call>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            if l_content_type = 'tool_call' then
              l_has_tool_call := true;
              exit check_if_has_tool_call;
            end if;
          end loop check_if_has_tool_call;
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');

            if not l_has_tool_call then
              l_oci_message := json_object_t();
              l_oci_message.put('role', 'CHATBOT');
              l_oci_message.put('message', l_content_item.get_clob('text'));
              po_oci_messages.append(l_oci_message);
            else
              l_tool_calls := json_array_t();

              case l_content_type
                when 'text' then
                  l_tool_call_message := l_content_item.get_clob('text');
                when 'tool_call' then
                  -- OCI tool calls handling would need to be implemented based on OCI's format
                  -- For now, we'll convert to text description
                  l_tool_call := json_object_t();
                  l_tool_call.put('name', l_content_item.get_string('toolName'));
                  l_tool_call.put('parameters', l_content_item.get_clob('args'));

                  l_tool_calls.append(l_tool_call);
                else
                  uc_ai_logger.log_error('Unknown content type in assistant message: ' || l_content_type, l_scope);
                  raise uc_ai.e_unhandled_format;
              end case;
                l_oci_message := json_object_t();
                l_oci_message.put('role', 'CHATBOT');
                l_oci_message.put('message', l_tool_call_message);
                l_oci_message.put('toolCalls', l_tool_calls);
                po_oci_messages.append(l_oci_message);

            end if;
          end loop assistant_content_loop;

        when 'tool' then
          -- Tool results are typically sent as user messages in OCI
          l_content := l_lm_message.get_array('content');
          l_tool_calls := json_array_t();
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              l_oci_content_item := json_object_t();
              l_oci_content_item.put('outputs', l_content_item.get_clob('result'));
              l_tool_call := json_object_t();
              l_tool_call.put('name', l_content_item.get_string('toolName'));
              l_tool_call.put('parameters', l_content_item.get_clob('args'));
              l_oci_content_item.put('call', l_tool_call);
              l_tool_calls.append(l_oci_content_item);
            end if;
          end loop tool_content_loop;
          
          if l_tool_calls.get_size > 0 then
            l_oci_message := json_object_t();
            l_oci_message.put('role', 'TOOL');
            l_oci_message.put('toolResults', l_tool_calls);
            po_oci_messages.append(l_oci_message);
          end if;

        else
          uc_ai_logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    uc_ai_logger.log('Cohere messages after conversion: ', l_scope, po_oci_messages.to_clob);

    declare
      l_last_message json_object_t;
      l_last_message_role varchar2(255 char);
    begin
      l_last_message := treat(po_oci_messages.get(po_oci_messages.get_size - 1) as json_object_t);
      l_last_message_role := l_last_message.get_string('role');

      if l_last_message_role = 'USER' then
        g_cohere_user_message := l_last_message.get_clob('message');

        -- remove last message as cohere expects it in the body (message) and not in the chat history
        po_oci_messages.remove(po_oci_messages.get_size - 1);
      end if;
    end;

    uc_ai_logger.log('Converted to ' || po_oci_messages.get_size || ' OCI messages', l_scope);
  end convert_lm_messages_to_cohere_oci;

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

  procedure internal_generate_text (
    pio_messages         in out nocopy json_array_t
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out nocopy json_object_t
  )
  as
    l_scope uc_ai_logger.scope%type := c_scope_prefix || 'internal_generate_text';
    l_input_obj    json_object_t;
    l_chat_request json_object_t;
    l_api_url      varchar2(500 char);

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_chat_response json_object_t;
    l_code varchar2(255 char);
  begin
    if g_tool_calls >= p_max_tool_calls then
      uc_ai_logger.log_warn('Max calls reached', l_scope, 'Max calls: ' || g_tool_calls);
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      raise uc_ai.e_max_calls_exceeded;
    end if;
    l_input_obj := p_input_obj;
    l_chat_request := l_input_obj.get_object('chatRequest');

    if g_mode = gc_mode_generic then
      l_chat_request.put('messages', pio_messages);
    else
      l_chat_request.put('chatHistory', pio_messages);
      l_chat_request.put('message', g_cohere_user_message);

      if g_cohere_system_prompt is not null then
        l_chat_request.put('preambleOverride', g_cohere_system_prompt);
      end if;
    end if;
    l_input_obj.put('chatRequest', l_chat_request);

    -- Build API URL
    l_api_url := build_api_url();

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers('Content-Type', 'application/json; charset=utf-8');   

    -- Make the API call using credential (OCI authentication should be configured)
    l_resp := apex_web_service.make_rest_request(
      p_url => l_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => g_apex_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := json_object_t.parse(l_resp);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      uc_ai_logger.log_error('Error in response', l_scope, l_temp_obj.to_clob);
      raise uc_ai.e_error_response;
    elsif l_resp_json.has('code') then
      l_code := l_resp_json.get_string('code');
      uc_ai_logger.log('API returned code: ' || l_code, l_scope);
      case l_code 
        when '400' then
          uc_ai_logger.log_error('Bad request', l_scope);
          raise uc_ai.e_error_response;
        when '401' then
          uc_ai_logger.log_error('Authentication error', l_scope);
          raise uc_ai.e_error_response;
        when '404' then
          uc_ai_logger.log_error('Model not found', l_scope);
          raise uc_ai.e_model_not_found_error;
        else
          null;
      end case;
    end if;

    -- Extract model information
    if l_resp_json.has('modelId') then
      pio_result.put('model', l_resp_json.get_string('modelId'));
    end if;

    -- Process OCI response format
    if l_resp_json.has('chatResponse') then
      l_chat_response := l_resp_json.get_object('chatResponse');


      if g_mode = gc_mode_generic then
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
                  
                    l_new_msg := get_text_content_generic(l_oci_content_item);
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
                    pio_messages.append(l_tool_response);

                    <<tool_calls>>
                    for k in 0 .. l_tool_call_arr.get_size - 1 
                    loop
                      g_tool_calls := g_tool_calls + 1;
                      l_tool_call_item := treat(l_tool_call_arr.get(k) as json_object_t);

                      l_tool_call_id := l_tool_call_item.get_string('id');
                      l_tool_name := l_tool_call_item.get_string('name');
                      l_tool_args_str := l_tool_call_item.get_string('arguments');

                      uc_ai_logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name);

                      if l_tool_args_str is not null then
                        -- Parse tool arguments if available
                        l_tool_args := json_object_t.parse(l_tool_args_str);
                        uc_ai_logger.log('Tool args', l_scope, 'Args: ' || l_tool_args.to_clob);
                      else
                        l_tool_args := json_object_t();
                        uc_ai_logger.log('Tool args', l_scope, 'No args provided');
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
                          uc_ai_logger.log_error('Tool execution failed', l_scope, 'Tool: ' || l_tool_name || ', Error: ' || sqlerrm || chr(10) || sys.dbms_utility.format_error_backtrace);
                          l_tool_result := 'Error executing tool: ' || sqlerrm;
                      end;

                      uc_ai_logger.log('Tool result', l_scope, l_tool_result);

                      l_tool_response := json_object_t();
                      l_tool_response.put('role', 'TOOL');
                      l_tool_response.put('toolCallId', l_tool_call_id);
                      l_tool_response_content := json_object_t();
                      l_tool_response_content.put('type', 'TEXT');
                      l_tool_response_content.put('text', l_tool_result);
                      l_tool_content.append(l_tool_response_content);
                      l_tool_response.put('content', l_tool_content);
                      pio_messages.append(l_tool_response);

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
                uc_ai_logger.log_error('Unknown role in OCI response: ' || l_role, l_scope);
              end if;
            end loop choices_loop;
            
            g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));
            

            if l_used_tool then
              g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
              pio_result.put('tool_calls_count', g_tool_calls);

              -- Continue conversation with tool results - recursive call
              internal_generate_text(
                pio_messages         => pio_messages
              , p_max_tool_calls     => p_max_tool_calls
              , p_input_obj          => p_input_obj
              , pio_result           => pio_result
              );
            end if;

            -- Set finish reason to stop for successful completion
            pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
          end;
        else
          uc_ai_logger.log_error('No text in OCI chatResponse', l_scope);
          pio_result.put('finish_reason', 'error');
        end if;
      else
        pio_messages := l_chat_response.get_array('chatHistory');

        -- cohere
        if l_chat_response.has('toolCalls') then
          declare
            l_tool_calls json_array_t := json_array_t();
            l_tool_call_item json_object_t;
            l_tool_call_id   varchar2(255 char);
            l_tool_name      varchar2(255 char);
            l_tool_args      json_object_t;
            l_tool_result    clob;

            l_normalized_messages json_array_t := json_array_t();
            l_normalized_tool_results json_array_t := json_array_t();
            l_oci_tool_results json_array_t := json_array_t();
            l_new_msg json_object_t;
            l_tool_response json_object_t;
            l_tool_response_call json_object_t;
            l_tool_outputs json_array_t := json_array_t();

            l_tmp_obj json_object_t;
          begin
            l_tool_calls := l_chat_response.get_array('toolCalls');
            <<tool_calls_loop>>
            for i in 0 .. l_tool_calls.get_size - 1 loop
              g_tool_calls := g_tool_calls + 1;

              l_tool_call_item := treat(l_tool_calls.get(i) as json_object_t);

              l_tool_call_id := 'tool_call_' || i;
              l_tool_name := l_tool_call_item.get_string('name');
              uc_ai_logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name);

              l_tool_args := treat(l_tool_call_item.get('parameters') as json_object_t);
              uc_ai_logger.log('Tool call', l_scope, 'Tool Args: ' || l_tool_args.to_clob);

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
                  uc_ai_logger.log_error('Tool execution failed', l_scope, 'Tool: ' || l_tool_name || ', Error: ' || sqlerrm || chr(10) || sys.dbms_utility.format_error_backtrace);
                  l_tool_result := 'Error executing tool: ' || sqlerrm;
              end;

              uc_ai_logger.log('Tool result', l_scope, l_tool_result);

              l_tool_response := json_object_t();

              l_tool_response_call := json_object_t();
              l_tool_response_call.put('name', l_tool_name);
              l_tool_response_call.put('parameters', l_tool_args);
              l_tool_response.put('call', l_tool_response_call);

              -- Cohere wants an array of objects for some reason
              -- so just return [ { result: <value> } ]
              l_tmp_obj := json_object_t();
              l_tmp_obj.put('result', l_tool_result);
              l_tool_outputs.append(l_tmp_obj);
              l_tool_response.put('outputs', l_tool_outputs);

              l_oci_tool_results.append(l_tool_response);

              l_new_msg := uc_ai_message_api.create_tool_result_content(
                p_tool_call_id => l_tool_call_id,
                p_tool_name    => l_tool_name,
                p_result       => l_tool_result
              );
              l_normalized_tool_results.append(l_new_msg);
            end loop tool_calls_loop;

            l_tool_response := json_object_t();
            l_tool_response.put('role', 'TOOL');
            l_tool_response.put('toolResults', l_oci_tool_results);
            --l_messages.append(l_tool_response);

            g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));

            g_normalized_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
            pio_result.put('tool_calls_count', g_tool_calls);

            -- clear user message for subsequent calls
            g_cohere_user_message := 'Continue processing the user prompt with the provided tool results.';
            l_chat_request.put('toolResults', l_oci_tool_results);
            l_input_obj.put('chatRequest', l_chat_request);

            internal_generate_text(
              pio_messages         => pio_messages
            , p_max_tool_calls     => p_max_tool_calls
            , p_input_obj          => p_input_obj
            , pio_result           => pio_result
              );
          end;
        elsif l_chat_response.has('text') then
          declare
            l_new_msg json_object_t;
            l_normalized_messages json_array_t := json_array_t();
          begin
            l_new_msg := get_text_content_cohere(l_chat_response);
            l_normalized_messages.append(l_new_msg);

            g_normalized_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));
          end;
        else
          uc_ai_logger.log_error('No text in OCI chatResponse', l_scope);
          pio_result.put('finish_reason', 'error');
        end if;

      end if;
    else
      uc_ai_logger.log_error('No chatResponse in OCI response', l_scope);
      pio_result.put('finish_reason', 'error');
    end if;

    uc_ai_logger.log('End internal_generate_text - final messages count: ' || pio_messages.get_size, l_scope);

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
    l_scope uc_ai_logger.scope%type := c_scope_prefix || 'generate_text_with_messages';
    l_input_obj          json_object_t := json_object_t();
    l_oci_messages       json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_serving_mode       json_object_t;
    l_chat_request       json_object_t;
    l_tools              json_array_t;
  begin
    l_result := json_object_t();
    uc_ai_logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);

    if p_model like 'cohere.%' then
      g_mode := gc_mode_cohere;
    else
      g_mode := gc_mode_generic;
    end if;

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

    -- Build OCI request structure
    -- Set compartment ID (must be configured)
    if g_compartment_id is null then
      uc_ai_logger.log_error('OCI compartment ID not configured', l_scope);
      raise_application_error(-20001, 'OCI compartment ID (g_compartment_id) must be configured');
    end if;
    
    l_input_obj.put('compartmentId', g_compartment_id);
    
    -- Set serving mode
    l_serving_mode := json_object_t();
    l_serving_mode.put('modelId', p_model);
    l_serving_mode.put('servingType', coalesce(g_serving_type, 'ON_DEMAND'));
    l_input_obj.put('servingMode', l_serving_mode);

    if g_mode = gc_mode_generic then
      -- Convert standardized messages to OCI format
      convert_lm_messages_to_generic_oci(
        p_lm_messages => p_messages,
        po_oci_messages => l_oci_messages
      );

      -- Set chat request
      l_chat_request := json_object_t();
      l_chat_request.put('apiFormat', 'GENERIC');
      l_chat_request.put('maxTokens', 600);
      l_chat_request.put('isStream', false);
      l_chat_request.put('numGenerations', 1);
      --l_chat_request.put('frequencyPenalty', 0);
      --l_chat_request.put('presencePenalty', 0);
      --l_chat_request.put('temperature', 1);
      --l_chat_request.put('topP', 1.0);
      --l_chat_request.put('topK', 1);
    else
      -- Convert standardized messages to OCI format
      convert_lm_messages_to_cohere_oci(
        p_lm_messages => p_messages,
        po_oci_messages => l_oci_messages
      );

      l_chat_request := json_object_t();
      l_chat_request.put('apiFormat', 'COHERE');
      l_chat_request.put('isEcho', false);
      l_chat_request.put('frequencyPenalty', 0);
      l_chat_request.put('isStream', false);
      l_chat_request.put('maxTokens', 600);
      if uc_ai.g_enable_tools then
        l_chat_request.put('isForceSingleStep', true);
      end if;
      --l_chat_request.put('presencePenalty', 0);
      --l_chat_request.put('temperature', 1);
      --l_chat_request.put('topP', 1.0);
      --l_chat_request.put('topK', 1);
    end if;

    -- Get all available tools formatted for Google (function declarations)
    l_tools := uc_ai_tools_api.get_tools_array(
      uc_ai.c_provider_oci
    , case when g_mode = gc_mode_cohere then uc_ai_tools_api.gc_cohere else 'generic' end
    );

    if l_tools.get_size > 0 then
      l_chat_request.put('tools', l_tools);
    end if;
    
    l_input_obj.put('chatRequest', l_chat_request);

    -- Note: Tool support would need to be added here if OCI supports it
    -- This would require additional research into OCI's tool calling capabilities

    internal_generate_text(
      pio_messages         => l_oci_messages
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
    
    uc_ai_logger.log('Completed generate_text with final message count: ' || g_normalized_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

end uc_ai_oci;
/
