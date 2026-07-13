create or replace package body uc_ai_oci as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url_base constant varchar2(255 char) := 'https://inference.generativeai.';
  c_api_generate_text_path constant varchar2(255 char) := '/20231130/actions/chat';
  c_api_generate_embeddings_path constant varchar2(255 char) := '/20231130/actions/embedText';

  gc_mode_generic constant varchar2(255 char) := 'generic';
  gc_mode_cohere  constant varchar2(255 char) := 'cohere';

  -- Per-call conversation state (tool-call count, message history, final message,
  -- token counters, mode, cohere prompts) is threaded as parameters, not package
  -- globals, so nested calls do not corrupt each other.

  -- OCI Generative AI reference: https://docs.oracle.com/en-us/iaas/api/#/en/generative-ai-inference/20231130/
  function get_text_content_generic (
    p_message in json_object_t
  -- @dblinter ignore(g-7170): in out kept for a uniform signature across the get_*_content accumulator family
  -- @dblinter ignore(g-7440): pio_state is a run-state accumulator threaded through the call, so in out is intentional
  , pio_state in out nocopy uc_ai_settings.t_run_state
  ) return json_object_t
  as
    l_message json_object_t;
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    l_message := p_message.clone();

    if l_message.get_string('type') != 'TEXT' then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unsupported_content
      , p_scope      => c_scope_prefix || 'get_text_content_generic'
      , p0           => l_message.get_string('type')
      , p_extra      => l_message.to_clob
      );
    end if;

    l_content := l_message.get_clob('text');
    l_provider_options := l_message.clone();
    l_provider_options.remove('text');
    l_provider_options.remove('type');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    pio_state.final_message := l_content;

    return l_lm_text_content;
  end get_text_content_generic;


  function get_text_content_cohere (
    p_chat_response in json_object_t
  -- @dblinter ignore(g-7170): in out kept for a uniform signature across the get_*_content accumulator family
  -- @dblinter ignore(g-7440): pio_state is a run-state accumulator threaded through the call, so in out is intentional
  , pio_state in out nocopy uc_ai_settings.t_run_state
  ) return json_object_t
  as
    l_text             clob;
    l_lm_text_content  json_object_t;
  begin
    if not p_chat_response.has('text') then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unhandled_format
      , p_scope      => c_scope_prefix || 'get_text_content_cohere'
      , p0           => 'response format'
      , p1           => 'Cohere response does not contain text field'
      );
    end if;

    l_text := p_chat_response.get_clob('text');
    pio_state.final_message := l_text;

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
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_lm_messages_to_generic_oci';
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
                -- OCI GENERIC chat expects polymorphic content parts keyed by "type":
                --   IMAGE    -> { imageUrl:    { url: "data:<mime>;base64,..", detail } }  (PNG/JPG, <= 5 MB)
                --   DOCUMENT -> { documentUrl: { url: "data:application/pdf;base64,..", detail } }  (PDF)
                -- data URI encoding matches the other providers; see uc_ai_openai.pkb 'file' branch.
                declare
                  l_data      clob := l_content_item.get_clob('data');
                  l_mime_type varchar2(4000 char) := l_content_item.get_string('mediaType');
                  l_url_obj   json_object_t;
                  l_detail    varchar2(20 char);
                  l_opts      json_object_t := l_content_item.get_object('providerOptions');
                begin
                  l_oci_content_item := json_object_t();
                  l_url_obj := json_object_t();
                  -- optional per-file detail via providerOptions => {"detail":"HIGH"}; default AUTO
                  l_detail := coalesce(case when l_opts is not null then l_opts.get_string('detail') end, 'AUTO');

                  if l_mime_type in ('image/png', 'image/jpeg', 'image/jpg') then
                    l_oci_content_item.put('type', 'IMAGE');
                    l_url_obj.put('url', 'data:' || l_mime_type || ';base64,' || l_data);
                    l_url_obj.put('detail', l_detail);
                    l_oci_content_item.put('imageUrl', l_url_obj);
                  elsif l_mime_type = 'application/pdf' then
                    l_oci_content_item.put('type', 'DOCUMENT');
                    l_url_obj.put('url', 'data:application/pdf;base64,' || l_data);
                    l_url_obj.put('detail', l_detail);
                    l_oci_content_item.put('documentUrl', l_url_obj);
                  else
                    -- OCI only supports PNG/JPG images and PDF documents in GENERIC mode
                    uc_ai_error.raise_error(
                      p_error_code => uc_ai_error.c_err_unhandled_format
                    , p_scope      => l_scope
                    , p0           => 'file type'
                    , p1           => l_mime_type
                    , p_extra      => l_content_item.stringify
                    );
                  end if;

                  l_oci_content.append(l_oci_content_item);
                end;
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
    po_oci_messages out nocopy json_array_t,
    po_system_prompt out nocopy clob,
    po_user_message out nocopy clob
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_lm_messages_to_cohere_oci';
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
          po_system_prompt := l_lm_message.get_clob('content');
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
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_unsupported_content
                , p_scope      => l_scope
                , p0           => 'file (Cohere cannot handle files)'
                );
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_unsupported_content
                , p_scope      => l_scope
                , p0           => l_content_type
                );
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
                  uc_ai_error.raise_error(
                    p_error_code => uc_ai_error.c_err_unsupported_content
                  , p_scope      => l_scope
                  , p0           => l_content_type
                  );
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
        po_user_message := l_last_message.get_clob('message');

        -- remove last message as cohere expects it in the body (message) and not in the chat history
        po_oci_messages.remove(po_oci_messages.get_size - 1);
      end if;
    end;

    uc_ai_logger.log('Converted to ' || po_oci_messages.get_size || ' OCI messages', l_scope);
  end convert_lm_messages_to_cohere_oci;

  /*
   * Get OCI region from global setting or use default
   */
  function get_oci_region(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    return coalesce(p_settings.oc_region, 'us-ashburn-1');
  end get_oci_region;

  /*
   * Build the full API URL for OCI Generative AI chat
   */
  function get_generate_text_url(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
    l_region varchar2(64 char);
  begin
    if p_settings.base_url is not null then
      return rtrim(p_settings.base_url, '/') || c_api_generate_text_path;
    end if;

    l_region := get_oci_region(p_settings);
    return c_api_url_base || l_region || '.oci.oraclecloud.com' || c_api_generate_text_path;
  end get_generate_text_url;

  /*
   * Build the full API URL for OCI Generative AI embeddings
   */
  function get_generate_embeddings_url(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
    l_region varchar2(64 char);
  begin
    if p_settings.base_url is not null then
      return rtrim(p_settings.base_url, '/') || c_api_generate_embeddings_path;
    end if;

    l_region := get_oci_region(p_settings);
    return c_api_url_base || l_region || '.oci.oraclecloud.com' || c_api_generate_embeddings_path;
  end get_generate_embeddings_url;

  procedure internal_generate_text (
    pio_messages             in out nocopy json_array_t
  , p_max_tool_calls         in pls_integer
  , p_input_obj              in json_object_t
  , pio_result               in out nocopy json_object_t
  , p_settings               in uc_ai_settings.t_settings
  , pio_state                in out nocopy uc_ai_settings.t_run_state
  , pio_norm_messages        in out nocopy json_array_t
  , p_mode                   in varchar2
  , p_cohere_system_prompt   in clob
  , pio_cohere_user_message  in out nocopy clob
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'internal_generate_text';
    l_input_obj    json_object_t;
    l_chat_request json_object_t;
    l_api_url      varchar2(500 char);

    l_resp      clob;
    l_resp_json json_object_t;
    l_temp_obj  json_object_t;
    l_chat_response json_object_t;
    l_code varchar2(255 char);
  begin
    if pio_state.tool_calls >= p_max_tool_calls then
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_max_calls_exceeded
      , p_scope      => l_scope
      , p0           => to_char(p_max_tool_calls)
      );
    end if;
    l_input_obj := p_input_obj;
    l_chat_request := l_input_obj.get_object('chatRequest');

    if p_mode = gc_mode_generic then
      l_chat_request.put('messages', pio_messages);
    else
      l_chat_request.put('chatHistory', pio_messages);
      l_chat_request.put('message', pio_cohere_user_message);

      if p_cohere_system_prompt is not null then
        l_chat_request.put('preambleOverride', p_cohere_system_prompt);
      end if;
    end if;
    l_input_obj.put('chatRequest', l_chat_request);

    -- Build API URL
    l_api_url := get_generate_text_url(p_settings);

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers('Content-Type', 'application/json; charset=utf-8');
    uc_ai_settings.apply_extra_headers(p_settings);

    -- Make the API call using credential (OCI authentication should be configured)
    l_resp := apex_web_service.make_rest_request(
      p_url => l_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => coalesce(p_settings.apex_web_credential, p_settings.oc_apex_web_credential)
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'OCI', l_scope);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'oci'
      , p1           => 'Error in response'
      , p_extra      => l_temp_obj.to_clob
      );
    elsif l_resp_json.has('code') then
      l_code := l_resp_json.get_string('code');
      uc_ai_logger.log('API returned code: ' || l_code, l_scope);
      case l_code
        when '400' then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_provider_response
          , p_scope      => l_scope
          , p0           => 'oci'
          , p1           => 'Bad request (400)'
          , p_extra      => l_resp
          );
        when '401' then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_provider_response
          , p_scope      => l_scope
          , p0           => 'oci'
          , p1           => 'Authentication error (401)'
          , p_extra      => l_resp
          );
        when '404' then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_model_not_found
          , p_scope      => l_scope
          , p0           => l_resp_json.get_string('message')
          , p_extra      => l_resp
          );
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

      -- Extract and accumulate usage information
      if l_chat_response.has('usage') then
        l_temp_obj := l_chat_response.get_object('usage');
        pio_state.input_tokens := pio_state.input_tokens + nvl(l_temp_obj.get_number('promptTokens'), 0);
        pio_state.output_tokens := pio_state.output_tokens + nvl(l_temp_obj.get_number('completionTokens'), 0);
      end if;

      if p_mode = gc_mode_generic then
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
            l_finish_reason varchar2(255 char);

            l_new_msg json_object_t;
          begin
            l_choices := l_chat_response.get_array('choices');

            <<choices_loop>>
            for i in 0 .. l_choices.get_size - 1 loop
              l_choice := treat(l_choices.get(i) as json_object_t);
              l_resp_message :=  l_choice.get_object('message');
              l_finish_reason := l_choice.get_string('finishReason');

              l_role := l_resp_message.get_string('role');

              if l_role = 'ASSISTANT' then
                -- NOTE: In the OCI GENERIC apiFormat an assistant message can carry
                -- BOTH `content` and `toolCalls` at the same time (they are independent
                -- optional fields on AssistantMessage in OCI's SDK). Some models (e.g.
                -- xai.grok-*) return an empty `content` array *together* with `toolCalls`
                -- on a tool-calling turn. These must therefore be handled as two separate
                -- `if` branches: an `if/elsif` would let a present-but-empty `content`
                -- short-circuit the tool-call handling, yielding an empty final message
                -- and tool_calls_count = 0.
                if l_resp_message.has('content') then
                  l_content_arr := l_resp_message.get_array('content');

                  <<content_loop>>
                  for j in 0 .. l_content_arr.get_size - 1 loop
                    l_oci_content_item := treat(l_content_arr.get(j) as json_object_t);

                    l_new_msg := get_text_content_generic(l_oci_content_item, pio_state);
                    l_normalized_messages.append(l_new_msg);
                  end loop content_loop;
                end if;

                if l_resp_message.has('toolCalls') then
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
                      pio_state.tool_calls := pio_state.tool_calls + 1;
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

                      -- Fire the per-tool-call hook OUTSIDE the handler below (which
                      -- swallows tool errors) so a hook veto propagates and stops the run.
                      uc_ai_tools_api.before_tool_call(p_tool_code => l_tool_name, p_settings => p_settings);

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
            
            pio_norm_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));


            if l_used_tool then
              pio_norm_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
              pio_result.put('tool_calls_count', pio_state.tool_calls);

              -- Continue conversation with tool results - recursive call
              internal_generate_text(
                pio_messages             => pio_messages
              , p_max_tool_calls         => p_max_tool_calls
              , p_input_obj              => p_input_obj
              , pio_result               => pio_result
              , p_settings               => p_settings
              , pio_state                => pio_state
              , pio_norm_messages        => pio_norm_messages
              , p_mode                   => p_mode
              , p_cohere_system_prompt   => p_cohere_system_prompt
              , pio_cohere_user_message  => pio_cohere_user_message
              );
            end if;

            -- Map OCI's GENERIC finishReason to UC AI's finish reasons so callers
            -- can detect truncation (length). When tools were used we recursed above
            -- and the nested (final) turn already set finish_reason, so don't clobber it.
            if not l_used_tool then
              case lower(l_finish_reason)
                when 'length' then
                  pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
                when 'content_filter' then
                  pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
                when 'tool_calls' then
                  pio_result.put('finish_reason', uc_ai.c_finish_reason_tool_calls);
                else
                  -- 'stop', null, or anything unknown -> treat as a normal completion
                  pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
              end case;
            end if;
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
              pio_state.tool_calls := pio_state.tool_calls + 1;

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

              -- Fire the per-tool-call hook OUTSIDE the handler below (which
              -- swallows tool errors) so a hook veto propagates and stops the run.
              uc_ai_tools_api.before_tool_call(p_tool_code => l_tool_name, p_settings => p_settings);

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

            pio_norm_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));

            pio_norm_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
            pio_result.put('tool_calls_count', pio_state.tool_calls);

            -- clear user message for subsequent calls
            pio_cohere_user_message := 'Continue processing the user prompt with the provided tool results.';
            l_chat_request.put('toolResults', l_oci_tool_results);
            l_input_obj.put('chatRequest', l_chat_request);

            internal_generate_text(
              pio_messages             => pio_messages
            , p_max_tool_calls         => p_max_tool_calls
            , p_input_obj              => p_input_obj
            , pio_result               => pio_result
            , p_settings               => p_settings
            , pio_state                => pio_state
            , pio_norm_messages        => pio_norm_messages
            , p_mode                   => p_mode
            , p_cohere_system_prompt   => p_cohere_system_prompt
            , pio_cohere_user_message  => pio_cohere_user_message
              );
          end;
        elsif l_chat_response.has('text') then
          declare
            l_new_msg json_object_t;
            l_normalized_messages json_array_t := json_array_t();
          begin
            l_new_msg := get_text_content_cohere(l_chat_response, pio_state);
            l_normalized_messages.append(l_new_msg);

            pio_norm_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));

            -- Map OCI COHERE finishReason so callers can detect truncation (length)
            case upper(l_chat_response.get_string('finishReason'))
              when 'MAX_TOKENS' then
                pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
              when 'CONTENT_FILTER' then
                pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
              else
                -- COMPLETE, STOP_SEQUENCE, null, or unknown -> normal completion
                pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
            end case;
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
  , p_settings       in uc_ai_settings.t_settings default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_text_with_messages';
    l_settings           uc_ai_settings.t_settings;
    l_state              uc_ai_settings.t_run_state := uc_ai_settings.new_run_state;
    l_norm_messages      json_array_t := json_array_t();
    l_mode               varchar2(255 char);
    l_cohere_system_prompt clob;
    l_cohere_user_message  clob;
    l_region varchar2(64 char);
    l_input_obj          json_object_t := json_object_t();
    l_oci_messages       json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_serving_mode       json_object_t;
    l_chat_request       json_object_t;
    l_tools              json_array_t;
  begin
    uc_ai_logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);

    if nvl(p_settings.initialized, false) then
      l_settings := p_settings;
    else
      l_settings := uc_ai_settings.build_from_globals;
    end if;

    l_region := coalesce(l_settings.oc_region, 'us-ashburn-1');

    -- OCI exposes an OpenAI-compatible "/openai/v1/responses" endpoint, but it
    -- only accepts openai.* models. Non-OpenAI families (xai.*, meta.*,
    -- cohere.* ...) are rejected there ("Non-OpenAI models require
    -- 'OpenAI-Project' or 'opc-conversation-store-id' header"), so route only
    -- openai.* models through the Responses delegate and fall through to the
    -- native GENERIC/COHERE chat endpoint for everything else, regardless of
    -- the oc_use_responses_api setting.
    if l_settings.oc_use_responses_api and p_model like 'openai.%' then
      declare
        l_resp_settings uc_ai_settings.t_settings := l_settings;
      begin
        -- Build a settings copy for the Responses API delegate. No package
        -- globals are mutated.
        l_resp_settings.ra_base_url := c_api_url_base || l_region || '.oci.oraclecloud.com/openai/v1';
        l_resp_settings.ra_apex_web_credential := coalesce(l_settings.apex_web_credential, l_settings.oc_apex_web_credential);
        l_resp_settings.extra_headers('opc-compartment-id') := l_settings.oc_compartment_id;
        l_resp_settings.provider_override := uc_ai.c_provider_oci;
        l_resp_settings.base_url := null;

        return uc_ai_responses_api.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => p_max_tool_calls
        , p_settings       => l_resp_settings
        );
      end;
    elsif l_settings.oc_use_responses_api then
      uc_ai_logger.log(
        'Responses API is enabled but model "' || p_model || '" is not an openai.* model; '
        || 'using the native OCI chat endpoint instead.', l_scope);
    end if;

    l_result := json_object_t();

    if p_model like 'cohere.%' then
      l_mode := gc_mode_cohere;
    else
      l_mode := gc_mode_generic;
    end if;

    -- Copy input messages to the per-call conversation history
    <<copy_messages_loop>>
    for i in 0 .. p_messages.get_size - 1
    loop
      l_message := treat(p_messages.get(i) as json_object_t);
      l_norm_messages.append(l_message);
    end loop copy_messages_loop;

    -- Initialize result object with default values
    l_result.put('tool_calls_count', 0);
    l_result.put('finish_reason', 'unknown');
    l_result.put('model', p_model);

    -- Build OCI request structure
    -- Set compartment ID (must be configured)
    if l_settings.oc_compartment_id is null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_missing_config
      , p_scope      => l_scope
      , p0           => 'OCI provider'
      , p1           => 'g_compartment_id to be configured'
      );
    end if;

    l_input_obj.put('compartmentId', l_settings.oc_compartment_id);

    -- Set serving mode
    l_serving_mode := json_object_t();
    l_serving_mode.put('modelId', p_model);
    l_serving_mode.put('servingType', coalesce(l_settings.oc_serving_type, 'ON_DEMAND'));
    l_input_obj.put('servingMode', l_serving_mode);

    if l_mode = gc_mode_generic then
      -- Convert standardized messages to OCI format
      convert_lm_messages_to_generic_oci(
        p_lm_messages => p_messages,
        po_oci_messages => l_oci_messages
      );

      -- Set chat request
      l_chat_request := json_object_t();
      l_chat_request.put('apiFormat', 'GENERIC');
      l_chat_request.put('maxTokens', coalesce(l_settings.oc_max_tokens, 4096));
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
        po_oci_messages => l_oci_messages,
        po_system_prompt => l_cohere_system_prompt,
        po_user_message => l_cohere_user_message
      );

      l_chat_request := json_object_t();
      l_chat_request.put('apiFormat', 'COHERE');
      l_chat_request.put('isEcho', false);
      l_chat_request.put('frequencyPenalty', 0);
      l_chat_request.put('isStream', false);
      l_chat_request.put('maxTokens', coalesce(l_settings.oc_max_tokens, 4096));
      if l_settings.enable_tools then
        l_chat_request.put('isForceSingleStep', true);
      end if;
      --l_chat_request.put('presencePenalty', 0);
      --l_chat_request.put('temperature', 1);
      --l_chat_request.put('topP', 1.0);
      --l_chat_request.put('topK', 1);
    end if;

    -- Get all available tools formatted for OCI (function declarations)
    l_tools := uc_ai_tools_api.get_tools_array(
      uc_ai.c_provider_oci
    , case when l_mode = gc_mode_cohere then uc_ai_tools_api.gc_cohere else 'generic' end
    , p_tool_tags => l_settings.tool_tags
    , p_enable_tools => l_settings.enable_tools
    );

    if l_tools.get_size > 0 then
      l_chat_request.put('tools', l_tools);
    end if;

    l_input_obj.put('chatRequest', l_chat_request);

    internal_generate_text(
      pio_messages             => l_oci_messages
    , p_max_tool_calls         => p_max_tool_calls
    , p_input_obj              => l_input_obj
    , pio_result               => l_result
    , p_settings               => l_settings
    , pio_state                => l_state
    , pio_norm_messages        => l_norm_messages
    , p_mode                   => l_mode
    , p_cohere_system_prompt   => l_cohere_system_prompt
    , pio_cohere_user_message  => l_cohere_user_message
    );

    -- Add final messages to result (per-call conversation history)
    l_result.put('messages', l_norm_messages);

    -- Add final message (only the text)
    l_result.put('final_message', l_state.final_message);

    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_oci);

    -- Add usage information
    declare
      l_usage_obj json_object_t := json_object_t();
    begin
      l_usage_obj.put('prompt_tokens', l_state.input_tokens);
      l_usage_obj.put('completion_tokens', l_state.output_tokens);
      l_usage_obj.put('reasoning_tokens', cast(null as number));
      l_usage_obj.put('total_tokens', l_state.input_tokens + l_state.output_tokens);
      l_result.put('usage', l_usage_obj);
    end;

    uc_ai_logger.log('Completed generate_text with final message count: ' || l_norm_messages.get_size, l_scope);

    return l_result;
  end generate_text;


  /*
   * Generate embeddings using OCI Generative AI API
   * 
   * API reference: https://docs.oracle.com/en-us/iaas/api/#/en/generative-ai-inference/20231130/EmbedTextResult/EmbedText
   * 
   * Returns array of embedding arrays (one per input string)
   */
  function generate_embeddings (
    p_input in json_array_t
  , p_model in uc_ai.model_type
  , p_settings in uc_ai_settings.t_settings default null
  ) return json_array_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_embeddings';
    l_settings      uc_ai_settings.t_settings;
    l_api_url       varchar2(4000 char);
    l_resp          clob;
    l_resp_json     json_object_t;
    l_embeddings    json_array_t;
    l_input_obj     json_object_t := json_object_t();
    l_serving_mode  json_object_t := json_object_t();
    l_inputs        json_array_t := json_array_t();
  begin
    uc_ai_logger.log('Starting generate_embeddings with ' || p_input.get_size || ' input items', l_scope);

    if nvl(p_settings.initialized, false) then
      l_settings := p_settings;
    else
      l_settings := uc_ai_settings.build_from_globals;
    end if;

    -- Build inputs array (OCI expects array of strings)
    <<build_inputs_loop>>
    for i in 0 .. p_input.get_size - 1
    loop
      l_inputs.append(p_input.get_clob(i));
    end loop build_inputs_loop;

    -- Build serving mode
    l_serving_mode.put('servingType', l_settings.oc_serving_type);
    l_serving_mode.put('modelId', p_model);

    -- Build request body
    l_input_obj.put('inputs', l_inputs);
    l_input_obj.put('servingMode', l_serving_mode);
    l_input_obj.put('compartmentId', l_settings.oc_compartment_id);
    l_input_obj.put('truncate', 'NONE');

    -- Build API URL
    l_api_url := get_generate_embeddings_url(l_settings);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json'
    );
    uc_ai_settings.apply_extra_headers(l_settings);

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);
    uc_ai_logger.log('Request URL: ' || l_api_url, l_scope);

    l_resp := apex_web_service.make_rest_request(
      p_url => l_api_url,
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob,
      p_credential_static_id => coalesce(l_settings.apex_web_credential, l_settings.oc_apex_web_credential)
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'OCI', l_scope);

    -- Check for error in response
    if l_resp_json.has('code') and l_resp_json.has('message') then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'oci'
      , p1           => l_resp_json.get_string('message')
      , p_extra      => l_resp_json.to_clob
      );
    end if;

    -- OCI returns embeddings directly as an array of arrays
    l_embeddings := l_resp_json.get_array('embeddings');

    uc_ai_logger.log('Returning ' || l_embeddings.get_size || ' embeddings', l_scope);

    return l_embeddings;
  end generate_embeddings;

end uc_ai_oci;
/
