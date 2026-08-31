create or replace package body uc_ai_google as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'https://generativelanguage.googleapis.com/v1beta/models';

  -- Per-call conversation state is threaded as run-state/message parameters,
  -- not package globals, so nested calls do not corrupt each other.

  -- Chat API reference: https://ai.google.dev/api/generate-content

  function get_api_url_base(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    if p_settings.base_url is not null then
      return rtrim(p_settings.base_url, '/');
    end if;

    return c_api_url;
  end get_api_url_base;

  function get_generate_text_url(
    p_model in varchar2
  , p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    return get_api_url_base(p_settings) || '/' || p_model || ':generateContent';
  end get_generate_text_url;

  function get_generate_embeddings_url(
    p_model in varchar2
  , p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    return get_api_url_base(p_settings) || '/' || p_model || ':batchEmbedContents';
  end get_generate_embeddings_url;

  /*
   * json_object_t.get_array hands back a NULL collection both for a missing key
   * and for a JSON null, and every method call on that NULL raises ORA-30625.
   * Google answers HTTP 200 with shapes that hit exactly that: a prompt-level
   * block carries no `candidates` at all, and a candidate stopped by
   * MALFORMED_FUNCTION_CALL, SAFETY or MAX_TOKENS carries no `content`. Reading
   * through these two helpers keeps a filtered answer a result instead of an
   * Oracle error.
   */
  function get_array_or_null (
    p_obj in json_object_t
  , p_key in varchar2
  ) return json_array_t
  as
  begin
    if p_obj is null or not p_obj.has(p_key) or p_obj.get(p_key).is_null then
      return null;
    end if;

    return p_obj.get_array(p_key);
  end get_array_or_null;


  function get_object_or_null (
    p_obj in json_object_t
  , p_key in varchar2
  ) return json_object_t
  as
  begin
    if p_obj is null or not p_obj.has(p_key) or p_obj.get(p_key).is_null then
      return null;
    end if;

    return p_obj.get_object(p_key);
  end get_object_or_null;


  /*
   * Gemini 3 replaced generationConfig.thinkingConfig.thinkingBudget with
   * thinkingLevel. Model ids are open-ended and Google keeps shipping new ones,
   * so the classification is by exclusion: only the generations known to need
   * the legacy budget shape get it, and everything unrecognized - including the
   * next model released - gets the current shape.
   * Mirrors google-model-capabilities.ts of the reference SDK.
   */
  function uses_thinking_level (
    p_model in uc_ai.model_type
  ) return boolean
  as
    l_model varchar2(255 char);
  begin
    l_model := lower(p_model);

    -- gemini-1.x, gemini-2.x (2.5 included) and the old gemini-pro aliases
    if regexp_like(l_model, '(^|/)gemini-(1|2)([.-]|$)')
       or regexp_like(l_model, '(^|/)gemini-pro(-vision)?$')
       or regexp_like(l_model, '(^|/)gemini-robotics-er-1\.5([.-]|$)')
    then
      return false;
    end if;

    return true;
  end uses_thinking_level;


  function get_thought_content (
    p_message in json_object_t
  -- @dblinter ignore(g-7170): in out kept for a uniform signature across the get_*_content accumulator family
  -- @dblinter ignore(g-7440): pio_state is a run-state accumulator threaded through the call, so in out is intentional
  -- @dblinter ignore(g-7330): intentionally reads but never writes pio_state - a thought summary must NOT become final_message (see below)
  , pio_state in out nocopy uc_ai_settings.t_run_state
  ) return json_object_t
  as
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    l_content := p_message.get_clob('text');
    -- A zero-length text is no reasoning text at all - Gemini 3 sends one on the
    -- part that only carries a thoughtSignature. Blank it to NULL so
    -- create_reasoning_content omits the key instead of writing an empty string.
    if l_content is not null and sys.dbms_lob.getlength(l_content) = 0 then
      l_content := null;
    end if;

    -- Must clone: the part object is already referenced by the raw conversation
    -- history handed to the provider, so stripping 'text' from it in place would
    -- silently blank the text out of the request sent on the next turn.
    l_provider_options := p_message.clone();
    l_provider_options.remove('text');

    l_lm_text_content := uc_ai_message_api.create_reasoning_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    -- Deliberately NOT setting pio_state.final_message: a thought summary is
    -- reasoning, not the user-visible answer, and it would otherwise overwrite
    -- the real final message when it is the last text-bearing part.

    return l_lm_text_content;
  end get_thought_content;

  function get_text_content (
    p_message in json_object_t
  -- @dblinter ignore(g-7440): pio_state is a run-state accumulator threaded through the call, so in out is intentional
  , pio_state in out nocopy uc_ai_settings.t_run_state
  ) return json_object_t
  as
    l_thought boolean;
    l_content clob;
    l_provider_options json_object_t;
    l_lm_text_content  json_object_t;
  begin
    if p_message.has('thought') then
      l_thought := p_message.get_boolean('thought');
    else
      l_thought := false;
    end if;

    if l_thought then
      return get_thought_content(p_message, pio_state);
    end if;

    l_content := p_message.get_clob('text');
    -- Must clone - see get_thought_content above.
    l_provider_options := p_message.clone();
    l_provider_options.remove('text');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    -- Append, never assign: a turn can carry several visible text parts and only
    -- their concatenation is the answer. Gemini 3 also ends a turn with a
    -- zero-length text part that exists only to carry a thoughtSignature, and
    -- assigning that part would blank the answer out. The parts of one candidate
    -- are contiguous text, so they are joined without a separator (the reference
    -- SDK joins them the same way). pio_state.final_message is reset at the
    -- start of every turn in internal_generate_text, so the last turn wins.
    if l_content is not null and sys.dbms_lob.getlength(l_content) > 0 then
      pio_state.final_message := pio_state.final_message || l_content;
    end if;

    return l_lm_text_content;
  end get_text_content;

  /*
   * Convert standardized Language Model messages to Google Gemini format
   * Returns Google-compatible messages array that can be sent directly to Gemini API
   * Also extracts system prompt separately since Google uses a separate systemInstruction field
   */
  procedure convert_lm_messages_to_google(
    p_lm_messages in json_array_t,
    po_system_prompt out nocopy clob,
    po_google_messages out nocopy json_array_t
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_lm_messages_to_google';
    l_lm_message json_object_t;
    l_google_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_parts json_array_t;
    l_part json_object_t;
    l_function_call json_object_t;
    l_function_response json_object_t;
  begin
    uc_ai_logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to Google format', l_scope);
    
    po_system_prompt := null;
    po_google_messages := json_array_t();

    <<message_loop>>
    for i in 0 .. p_lm_messages.get_size - 1
    loop
      l_lm_message := treat(p_lm_messages.get(i) as json_object_t);
      l_role := l_lm_message.get_string('role');

      case l_role
        when 'system' then
          -- System message: extract content for separate systemInstruction field
          po_system_prompt := l_lm_message.get_clob('content');

        when 'user' then
          -- User message: extract text from content array
          l_content := l_lm_message.get_array('content');
          l_parts := json_array_t();
          
          <<user_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text part
                l_part := json_object_t();
                l_part.put('text', l_content_item.get_clob('text'));
                l_parts.append(l_part);
              when 'file' then
                -- document understanding API: https://ai.google.dev/gemini-api/docs/document-processing#rest
                l_part := json_object_t();

                declare
                  l_data clob;
                  l_inline_data json_object_t := json_object_t();
                begin
                  l_data := l_content_item.get_clob('data');
                  l_inline_data.put('mime_type', l_content_item.get_string('mediaType'));
                  l_inline_data.put('data', l_data);

                  l_part.put('inline_data', l_inline_data);
                  l_parts.append(l_part);
                end;
            end case;
          end loop user_content_loop;
          
          if l_parts.get_size > 0 then
            l_google_message := json_object_t();
            l_google_message.put('role', 'user');
            l_google_message.put('parts', l_parts);
            po_google_messages.append(l_google_message);
          end if;

        when 'assistant' then
          -- Assistant message: can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          l_parts := json_array_t();
          
          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            case l_content_type
              when 'text' then
                -- Add text part
                l_part := json_object_t();
                l_part.put('text', l_content_item.get_clob('text'));
                l_parts.append(l_part);
              when 'tool_call' then
                -- Convert tool call to Google functionCall format
                l_function_call := json_object_t();
                l_function_call.put('name', l_content_item.get_string('toolName'));
                
                -- Parse arguments JSON string to object
                declare
                  l_args_obj json_object_t;
                begin
                  if l_content_item.get_clob('args') is not null then
                    l_args_obj := json_object_t.parse(l_content_item.get_clob('args'));
                    l_function_call.put('args', l_args_obj);
                  end if;
                exception
                  when others then
                    uc_ai_logger.log_warning('Failed to parse tool call arguments JSON: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope, l_content_item.get_clob('args'));
                    -- If parsing fails, don't add args
                    null;
                end;
                
                l_part := json_object_t();
                l_part.put('functionCall', l_function_call);

                -- Gemini 2.5+ signs the parts it produced and requires the
                -- signature back on the same part in later turns; a function-call
                -- part replayed without it breaks multi-turn function calling.
                if l_content_item.has('providerOptions') and not l_content_item.get('providerOptions').is_null then
                  declare
                    l_provider_options json_object_t;
                  begin
                    l_provider_options := l_content_item.get_object('providerOptions');
                    if l_provider_options.has('thoughtSignature')
                       and not l_provider_options.get('thoughtSignature').is_null then
                      l_part.put('thoughtSignature', l_provider_options.get_clob('thoughtSignature'));
                    end if;
                  end;
                end if;

                l_parts.append(l_part);

              when 'reasoning' then
                -- Thought summaries themselves need not be sent back, but a signed
                -- thought part must be replayed with its signature intact. Without
                -- a signature there is nothing Gemini needs, so skip the part.
                declare
                  l_signature clob;
                begin
                  if l_content_item.has('providerOptions') and not l_content_item.get('providerOptions').is_null then
                    declare
                      l_provider_options json_object_t;
                    begin
                      l_provider_options := l_content_item.get_object('providerOptions');
                      if l_provider_options.has('thoughtSignature')
                         and not l_provider_options.get('thoughtSignature').is_null then
                        l_signature := l_provider_options.get_clob('thoughtSignature');
                      end if;
                    end;
                  end if;

                  if l_signature is not null then
                    l_part := json_object_t();

                    -- Gemini also emits signature-only parts (no thought text at
                    -- all). Keep those as a bare signed part rather than sending a
                    -- part with a null text field.
                    if l_content_item.get_clob('text') is not null then
                      l_part.put('text', l_content_item.get_clob('text'));
                      l_part.put('thought', true);
                    end if;

                    l_part.put('thoughtSignature', l_signature);
                    l_parts.append(l_part);
                  else
                    uc_ai_logger.log('Skipping unsigned thought part (nothing to replay)', l_scope);
                  end if;
                end;

              else
                null; -- Skip unknown content types
            end case;
          end loop assistant_content_loop;
          
          if l_parts.get_size > 0 then
            l_google_message := json_object_t();
            l_google_message.put('role', 'model');
            l_google_message.put('parts', l_parts);
            po_google_messages.append(l_google_message);
          end if;

        when 'tool' then
          -- Tool message: convert tool results to Google user message with functionResponse parts
          l_content := l_lm_message.get_array('content');
          l_parts := json_array_t();
          
          <<tool_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');
            
            if l_content_type = 'tool_result' then
              -- Create functionResponse part
              l_function_response := json_object_t();
              l_function_response.put('name', l_content_item.get_string('toolName'));
              
              declare
                l_response_content json_object_t := json_object_t();
              begin
                l_response_content.put('result', l_content_item.get_clob('result'));
                l_function_response.put('response', l_response_content);
              end;
              
              l_part := json_object_t();
              l_part.put('functionResponse', l_function_response);
              l_parts.append(l_part);
            end if;
          end loop tool_content_loop;
          
          if l_parts.get_size > 0 then
            l_google_message := json_object_t();
            l_google_message.put('role', 'user');
            l_google_message.put('parts', l_parts);
            po_google_messages.append(l_google_message);
          end if;

        else
          uc_ai_logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    uc_ai_logger.log('Converted to ' || po_google_messages.get_size || ' Google messages', l_scope);
    if po_system_prompt is not null then
      uc_ai_logger.log('Extracted system prompt', l_scope, po_system_prompt);
    end if;
  end convert_lm_messages_to_google;


  procedure internal_generate_text (
    pio_messages         in out nocopy json_array_t
  , p_system_prompt      in clob
  , p_max_tool_calls     in pls_integer
  , p_input_obj          in json_object_t
  , pio_result           in out nocopy json_object_t
  , p_settings           in uc_ai_settings.t_settings
  , pio_state            in out nocopy uc_ai_settings.t_run_state
  , pio_norm_messages    in out nocopy json_array_t
  )
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'internal_generate_text';
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
    l_block_reason  varchar2(255 char);
    l_usage_metadata json_object_t;
    l_web_credential varchar2(255 char);
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
    l_input_obj.put('contents', pio_messages);


    -- Build API URL with model
    l_model := pio_result.get_string('model');

    l_api_url := get_generate_text_url(l_model, p_settings);

    l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.go_apex_web_credential);

    if l_web_credential is null then
      l_api_url := l_api_url || '?key=' || uc_ai_get_key(uc_ai.c_provider_google);
    end if;


    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json'
    );
    uc_ai_settings.apply_extra_headers(p_settings);

    l_resp := uc_ai_http.post(
      p_url => l_api_url,
      p_body => l_input_obj.to_clob,
      p_credential_static_id => l_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'Google', l_scope);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'google'
      , p1           => l_temp_obj.get_string('message')
      , p_extra      => l_temp_obj.to_clob
      );
    end if;

    -- Extract and accumulate usage information in global counters
    if l_resp_json.has('usageMetadata') then
      l_usage_metadata := l_resp_json.get_object('usageMetadata');
      pio_state.input_tokens := pio_state.input_tokens + nvl(l_usage_metadata.get_number('promptTokenCount'), 0);
      pio_state.output_tokens := pio_state.output_tokens + nvl(l_usage_metadata.get_number('candidatesTokenCount'), 0);
      pio_state.reasoning_tokens := pio_state.reasoning_tokens + nvl(l_usage_metadata.get_number('thoughtsTokenCount'), 0);
      pio_state.total_tokens := pio_state.total_tokens + nvl(l_usage_metadata.get_number('totalTokenCount'), 0);
    end if;

    -- Extract model information (Google returns it in response)
    if l_resp_json.has('modelVersion') then
      pio_result.put('model', l_resp_json.get_string('modelVersion'));
    end if;

    -- Process candidates array (Google Gemini format)
    -- Google answers HTTP 200 when it blocks the prompt itself: the body then
    -- carries promptFeedback.blockReason and no `candidates` key at all.
    l_candidates := get_array_or_null(l_resp_json, 'candidates');

    if l_candidates is not null and l_candidates.get_size > 0 then
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

      -- Process content and parts.
      -- A candidate can arrive without content: MALFORMED_FUNCTION_CALL, SAFETY
      -- and a MAX_TOKENS budget spent entirely on thinking all produce one. The
      -- finish reason mapped above is then the whole answer, so an empty parts
      -- array carries the turn through without a NULL dereference.
      l_content := get_object_or_null(l_candidate, 'content');
      l_parts := coalesce(get_array_or_null(l_content, 'parts'), json_array_t());
      if l_parts.get_size = 0 then
        uc_ai_logger.log_warn('Google candidate without content parts, finish reason: ' || l_finish_reason, l_scope);
      end if;
    
      declare
        l_resp_message       json_object_t := json_object_t();
        l_tool_results_parts json_array_t := json_array_t();
        l_tool_call          json_object_t;
        l_tool_name          uc_ai_tools.code%type;
        l_tool_args          json_object_t;
        l_tool_call_id       varchar2(255 char);
        l_tool_result        clob;
        l_new_msg            json_object_t;
        l_param_name         uc_ai_tool_parameters.name%type;
        l_tool_response      json_object_t;
        l_used_tool          boolean := false;

        l_normalized_messages     json_array_t := json_array_t();
        l_normalized_tool_results json_array_t := json_array_t();
      begin
        -- Every turn recomputes the final message from its own text parts, so a
        -- turn that answers with tool calls only (or with nothing at all) does
        -- not leave the previous turn's text standing as the answer.
        pio_state.final_message := null;

        -- Add AI's message with content (including functionCall parts) to
        -- conversation history. Skipped when the candidate had no content: an
        -- empty model turn is not valid input for the next request.
        if l_parts.get_size > 0 then
          l_resp_message.put('role', 'model');
          l_resp_message.put('parts', l_parts);
          pio_messages.append(l_resp_message);
        end if;

        -- Execute each function call and collect results
        <<parts_loop>>
        for j in 0 .. l_parts.get_size - 1
        loop
          l_part := treat(l_parts.get(j) as json_object_t);

          
          if l_part.has('functionCall') then
            uc_ai_logger.log('Executing function call', l_scope, l_part.to_clob);

            pio_state.tool_calls := pio_state.tool_calls + 1;
            l_used_tool := true;

            l_tool_call := l_part.get_object('functionCall');
            l_tool_call_id := coalesce(l_tool_call.get_string('id'), 'tool_call_' || pio_state.tool_calls);
            l_tool_name := l_tool_call.get_string('name');
            
            -- Handle function arguments (can be null for parameterless functions)
            if l_tool_call.has('args') then
              uc_ai_logger.log('Function call has args', l_scope, l_tool_call.get_object('args').to_clob);
              l_tool_args := l_tool_call.get_object('args');
            else
              l_tool_args := json_object_t(); -- Empty args for parameterless functions
            end if;
            
            if l_tool_args is not null then
              -- when we have a top-level object parameter, extract it. Google wraps it into a named object
              l_param_name := uc_ai_tools_api.get_tools_object_param_name(l_tool_name);
              uc_ai_logger.log('Top-level object parameter name', l_scope, 'Tool: ' || l_tool_name || ', Param: ' || nvl(l_param_name, 'null'));
              if l_param_name is not null then
                l_tool_args := l_tool_args.get_object(l_param_name);
              end if;
            end if;

            uc_ai_logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name);
            if l_tool_args is not null then
              uc_ai_logger.log('Tool args', l_scope, 'Args: ' || l_tool_args.to_clob);
            else
              uc_ai_logger.log('Tool args', l_scope, 'No args provided');
              l_tool_args := json_object_t();
            end if;

            -- Gemini 2.5+ attaches thoughtSignature to the functionCall PART (not
            -- to a thought part), and requires it back on that part in later turns.
            -- Carry it through the normalized tool call so a cross-call replay can
            -- restore it (see convert_lm_messages_to_google).
            declare
              l_tool_provider_options json_object_t;
            begin
              if l_part.has('thoughtSignature') and not l_part.get('thoughtSignature').is_null then
                l_tool_provider_options := json_object_t();
                l_tool_provider_options.put('thoughtSignature', l_part.get_clob('thoughtSignature'));
              end if;

              l_new_msg := uc_ai_message_api.create_tool_call_content(
                p_tool_call_id     => l_tool_call_id
              , p_tool_name        => l_tool_name
              , p_args             => l_tool_args.to_clob
              , p_provider_options => l_tool_provider_options
              );
            end;
            l_normalized_messages.append(l_new_msg);

            -- Fire the per-tool-call hook OUTSIDE the handler below (which swallows
            -- tool errors) so a hook veto raising propagates and stops the run.
            uc_ai_tools_api.before_tool_call(p_tool_code => l_tool_name, p_settings => p_settings);

            -- Execute the tool and get result
            begin
              l_tool_result := uc_ai_tools_api.execute_agent_tool(
                p_tool_code          => l_tool_name
              , p_arguments          => l_tool_args
              , p_settings           => p_settings
              );
            exception
              when others then
                uc_ai_logger.log_error('Tool execution failed', l_scope, 'Tool: ' || l_tool_name || ', Error: ' || sqlerrm || chr(10) || sys.dbms_utility.format_error_backtrace);
                l_tool_result := 'Error executing tool: ' || sqlerrm;
            end;

            l_tool_response := json_object_t();
            declare
              l_tool_resp_obj json_object_t := json_object_t();
              l_resp_content json_object_t := json_object_t();
            begin
              -- Google expects the function response in this specific format
              l_tool_resp_obj.put('id', l_tool_call_id);
              l_tool_resp_obj.put('name', l_tool_name);
              l_resp_content.put('result', l_tool_result);
              l_tool_resp_obj.put('response', l_resp_content);
              l_tool_response.put('functionResponse', l_tool_resp_obj);
              l_tool_results_parts.append(l_tool_response);
            end;

            l_new_msg := uc_ai_message_api.create_tool_result_content(
              p_tool_call_id => l_tool_call_id,
              p_tool_name    => l_tool_name,
              p_result       => l_tool_result
            );
            l_normalized_tool_results.append(l_new_msg);

          -- Normal text part. A zero-length text carries no answer: Gemini 3
          -- ends a turn with {"text":"","thoughtSignature":...} whose only
          -- purpose is to hand the signature back. Such a part falls through to
          -- the signature branch below, so the signature survives and no empty
          -- text item enters the message history.
          elsif l_part.has('text') and sys.dbms_lob.getlength(l_part.get_clob('text')) > 0 then
            uc_ai_logger.log('Text received', l_scope, l_part.to_clob);
            l_new_msg := get_text_content(l_part, pio_state);
            l_normalized_messages.append(l_new_msg);

          -- Signature-only part: no text and no functionCall, just the signed
          -- token Gemini wants back on the next turn. Normalize it as a text-less
          -- reasoning item so it survives a cross-call history round trip.
          elsif l_part.has('thoughtSignature') and not l_part.get('thoughtSignature').is_null then
            uc_ai_logger.log('Signature-only thought part received', l_scope);
            l_new_msg := get_thought_content(l_part, pio_state);
            l_normalized_messages.append(l_new_msg);
          end if;
        end loop parts_loop;

        -- No content means no assistant turn to report either.
        if l_normalized_messages.get_size > 0 then
          pio_norm_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));
        end if;


        if l_used_tool then
          pio_norm_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));
          pio_result.put('tool_calls_count', pio_state.tool_calls);

          -- Add tool results as new user message
          l_new_msg := json_object_t();
          l_new_msg.put('role', 'user');
          l_new_msg.put('parts', l_tool_results_parts);
          pio_messages.append(l_new_msg);

          -- Continue conversation with tool results - recursive call
          internal_generate_text(
            pio_messages         => pio_messages
          , p_system_prompt      => p_system_prompt
          , p_max_tool_calls     => p_max_tool_calls
          , p_input_obj          => p_input_obj
          , pio_result           => pio_result
          , p_settings           => p_settings
          , pio_state            => pio_state
          , pio_norm_messages    => pio_norm_messages
          );
        end if;
      end;
  
    else
      l_temp_obj := get_object_or_null(l_resp_json, 'promptFeedback');
      if l_temp_obj is not null then
        l_block_reason := l_temp_obj.get_string('blockReason');
      end if;

      if l_block_reason is null then
        -- No candidates and no reason given: the body is not a Gemini response.
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_provider_response
        , p_scope      => l_scope
        , p_message    => 'No candidates in Google API response'
        );
      end if;

      -- A blocked prompt is a filtered turn, not a transport failure. Report it
      -- through finish_reason, the way every other refusal is reported, so the
      -- caller reads a result instead of catching ORA-30625.
      uc_ai_logger.log_warn('Google blocked the prompt: ' || l_block_reason, l_scope);
      pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
      pio_result.put('block_reason', l_block_reason);
      pio_state.final_message := null;
    end if;

    uc_ai_logger.log('End internal_generate_text - final messages count: ' || pio_messages.get_size, l_scope);

  end internal_generate_text;


  /*
   * Core conversation handler with Google Gemini API
   * 
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  , p_schema         in json_object_t default null
  , p_settings       in uc_ai_settings.t_settings default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_text_with_messages';
    l_settings           uc_ai_settings.t_settings;
    l_state              uc_ai_settings.t_run_state := uc_ai_settings.new_run_state;
    l_norm_messages      json_array_t := json_array_t();
    l_input_obj          json_object_t := json_object_t();
    l_google_messages    json_array_t;
    l_system_prompt      clob;
    l_tools              json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_parts              json_array_t;
    l_part               json_object_t;
    l_generation_config  json_object_t;
    l_response_schema    json_object_t;
  begin
    l_result := json_object_t();
    uc_ai_logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);

    if nvl(p_settings.initialized, false) then
      l_settings := p_settings;
    else
      l_settings := uc_ai_settings.build_from_globals;
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
    l_input_obj.put('model', p_model);
    
    -- Convert standardized messages to Google format
    convert_lm_messages_to_google(
      p_lm_messages => p_messages,
      po_system_prompt => l_system_prompt,
      po_google_messages => l_google_messages
    );

    -- Add system prompt as systemInstruction if extracted
    if l_system_prompt is not null then
      l_parts := json_array_t();
      l_part := json_object_t();
      l_part.put('text', l_system_prompt);
      l_parts.append(l_part);

      l_message := json_object_t();
      l_message.put('role', 'user');
      l_message.put('parts', l_parts);
      l_input_obj.put('systemInstruction', l_message);
    end if;

    -- Setup generation config
    l_generation_config := json_object_t();

    -- Add structured output schema if provided
    if p_schema is not null then
      l_response_schema := uc_ai_structured_output.to_google_format(p_schema);
      l_generation_config.put('responseSchema', l_response_schema);
      l_generation_config.put('responseMimeType', 'application/json');
    end if;

    -- Add reasoning configuration if enabled
    if l_settings.enable_reasoning then
      declare
        l_thinking_config json_object_t := json_object_t();
        l_thinking_level  varchar2(10 char);
        l_thinking_budget pls_integer;
      begin
        l_thinking_config.put('includeThoughts', true);

        -- go_reasoning_budget is the provider-specific escape hatch: the caller
        -- named an exact number of thinking tokens, so it is sent unchanged on
        -- every generation. Google still accepts and honours thinkingBudget on
        -- Gemini 3 (measured 2026-08: 0 buys no thinking, 24576 buys a lot,
        -- 999999 is rejected as out of range), so translating it would only
        -- lose precision.
        if l_settings.go_reasoning_budget is not null then
          l_thinking_config.put('thinkingBudget', l_settings.go_reasoning_budget);

        elsif l_settings.reasoning_level is not null then
          if uses_thinking_level(p_model) then
            -- Gemini 3 takes the depth as thinkingLevel
            -- (minimal | low | medium | high), and a request that carries both
            -- keys is refused with "You can only set only one of thinking budget
            -- and thinking level" - hence the elsif above. uc_ai's three levels
            -- map one for one onto the three upper values, so low, medium and
            -- high keep meaning what they meant on 2.5. `minimal` has no uc_ai
            -- level of its own and stays reachable through
            -- go_reasoning_budget = 0.
            -- Sending thinkingLevel to gemini-2.5 is an HTTP 400
            -- ("Thinking level is not supported for this model"), which is why
            -- this branch exists at all.
            l_thinking_level := case l_settings.reasoning_level
              when uc_ai.c_reasoning_level_low then 'low'
              when uc_ai.c_reasoning_level_medium then 'medium'
              when uc_ai.c_reasoning_level_high then 'high'
              else null
            end;

            if l_thinking_level is not null then
              l_thinking_config.put('thinkingLevel', l_thinking_level);
            else
              -- An unknown level sends no depth at all and lets Google pick its
              -- default. It used to reach a numeric assignment and raise
              -- ORA-06502, and an unknown value forwarded verbatim would be an
              -- HTTP 400 anyway.
              uc_ai_logger.log_warn('Unknown reasoning level: ' || l_settings.reasoning_level, l_scope);
            end if;

          else
            -- gemini-2.5 and older: reasoning depth is a token budget.
            l_thinking_budget := case l_settings.reasoning_level
              when uc_ai.c_reasoning_level_low then 2048
              when uc_ai.c_reasoning_level_medium then 8192
              when uc_ai.c_reasoning_level_high then 32768
              else null
            end;

            if l_thinking_budget is not null then
              l_thinking_config.put('thinkingBudget', l_thinking_budget);
            else
              -- Same guard as above: an unknown level used to reach the numeric
              -- ELSE of this CASE and raise ORA-06502.
              uc_ai_logger.log_warn('Unknown reasoning level: ' || l_settings.reasoning_level, l_scope);
            end if;
          end if;
        end if;

        l_generation_config.put('thinkingConfig', l_thinking_config);
      end;
    end if;

    -- Get all available tools formatted for Google (function declarations).
    -- Google expects tools as {"tools": [{"functionDeclarations": [...]}, <provider tools...>]}
    -- so provider (server-side) tools are appended as siblings of the function
    -- declarations wrapper, NOT via get_tools_array (which would nest them inside
    -- functionDeclarations).
    if l_settings.enable_tools
       or (l_settings.provider_tools is not null and l_settings.provider_tools.get_size > 0) then
      declare
        l_tools_array   json_array_t := json_array_t();
        l_tools_wrapper json_object_t;
      begin
        if l_settings.enable_tools then
          l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_google, p_tool_tags => l_settings.tool_tags, p_enable_tools => l_settings.enable_tools, p_programmatic_tools => l_settings.enable_programmatic_tools);
          if l_tools.get_size > 0 then
            l_tools_wrapper := json_object_t();
            l_tools_wrapper.put('functionDeclarations', l_tools);
            l_tools_array.append(l_tools_wrapper);
          end if;
        end if;

        -- Append raw provider tool definitions verbatim (e.g. {"googleSearch": {}})
        if l_settings.provider_tools is not null then
          <<provider_tools_loop>>
          for i in 0 .. l_settings.provider_tools.get_size - 1 loop
            l_tools_array.append(l_settings.provider_tools.get(i));
          end loop provider_tools_loop;
        end if;

        if l_tools_array.get_size > 0 then
          l_input_obj.put('tools', l_tools_array);
          uc_ai_logger.log('Tools configured', l_scope, 'Entry count: ' || l_tools_array.get_size);
        end if;
      end;
    end if;

    -- Apply generation config if any settings were added
    if l_generation_config.get_keys().count > 0 then
      l_input_obj.put('generationConfig', l_generation_config);
    end if;

    -- Merge user-supplied extra body properties (before messages are added)
    uc_ai_settings.apply_extra_body(l_input_obj, l_settings);

    internal_generate_text(
      pio_messages         => l_google_messages
    , p_system_prompt      => l_system_prompt
    , p_max_tool_calls     => p_max_tool_calls
    , p_input_obj          => l_input_obj
    , pio_result           => l_result
    , p_settings           => l_settings
    , pio_state            => l_state
    , pio_norm_messages    => l_norm_messages
    );

    -- Add final messages to result (per-call conversation history)
    l_result.put('messages', l_norm_messages);

    -- Add final message (only the text)
    l_result.put('final_message', l_state.final_message);

    -- Add usage information from the per-call run state
    declare
      l_usage_obj json_object_t := json_object_t();
    begin
      l_usage_obj.put('prompt_tokens', l_state.input_tokens);
      l_usage_obj.put('completion_tokens', l_state.output_tokens);
      l_usage_obj.put('reasoning_tokens', l_state.reasoning_tokens);
      l_usage_obj.put('total_tokens', l_state.total_tokens);
      l_result.put('usage', l_usage_obj);
    end;

    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_google);

    uc_ai_logger.log('Completed generate_text with final message count: ' || l_norm_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;


  /*
   * Generate embeddings using Google Gemini API
   * 
   * API reference: https://ai.google.dev/api/embeddings
   * Uses batchEmbedContents for multiple inputs
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
    l_temp_obj      json_object_t;
    l_embeddings    json_array_t;
    l_embedding_obj json_object_t;
    l_input_obj     json_object_t := json_object_t();
    l_requests      json_array_t := json_array_t();
    l_request       json_object_t;
    l_content       json_object_t;
    l_parts         json_array_t;
    l_part          json_object_t;
    l_text          clob;
    l_web_credential varchar2(255 char);
  begin
    uc_ai_logger.log('Starting generate_embeddings with ' || p_input.get_size || ' input items', l_scope);

    if nvl(p_settings.initialized, false) then
      l_settings := p_settings;
    else
      l_settings := uc_ai_settings.build_from_globals;
    end if;

    -- Build requests array for batchEmbedContents
    -- Each request needs: {"model": "models/...", "content": {"parts": [{"text": "..."}]}}
    <<build_requests_loop>>
    for i in 0 .. p_input.get_size - 1
    loop
      l_text := p_input.get_clob(i);
      
      l_part := json_object_t();
      l_part.put('text', l_text);
      
      l_parts := json_array_t();
      l_parts.append(l_part);
      
      l_content := json_object_t();
      l_content.put('parts', l_parts);
      
      l_request := json_object_t();
      l_request.put('model', 'models/' || p_model);
      l_request.put('content', l_content);

      if l_settings.go_embedding_task_type is not null then
        l_request.put('task_type', l_settings.go_embedding_task_type);
      end if;

      if l_settings.go_embedding_output_dimensions is not null then
        l_request.put('output_dimensionality', l_settings.go_embedding_output_dimensions);
      end if;
      
      l_requests.append(l_request);
    end loop build_requests_loop;
    
    l_input_obj.put('requests', l_requests);

    -- Build API URL
    l_api_url := get_generate_embeddings_url(p_model, l_settings);

    l_web_credential := coalesce(l_settings.apex_web_credential, l_settings.go_apex_web_credential);
    if l_web_credential is null then
      l_api_url := l_api_url || '?key=' || uc_ai_get_key(uc_ai.c_provider_google);
    end if;

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json'
    );
    uc_ai_settings.apply_extra_headers(l_settings);

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);
    uc_ai_logger.log('Request URL: ' || l_api_url, l_scope);

    l_resp := uc_ai_http.post(
      p_url => l_api_url,
      p_body => l_input_obj.to_clob,
      p_credential_static_id => l_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'Google', l_scope);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'google'
      , p1           => l_temp_obj.get_string('message')
      , p_extra      => l_temp_obj.to_clob
      );
    end if;

    -- Google returns embeddings in "embeddings" array, each item has "values" array
    l_embeddings := json_array_t();
    
    declare
      l_resp_embeddings json_array_t;
    begin
      -- Same NULL trap as on the chat path: a 200 body without an embeddings
      -- array must not become ORA-30625.
      l_resp_embeddings := get_array_or_null(l_resp_json, 'embeddings');

      if l_resp_embeddings is null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_provider_response
        , p_scope      => l_scope
        , p_message    => 'No embeddings in Google API response'
        );
      end if;

      
      <<embeddings_loop>>
      for i in 0 .. l_resp_embeddings.get_size - 1
      loop
        l_embedding_obj := treat(l_resp_embeddings.get(i) as json_object_t);
        l_embeddings.append(l_embedding_obj.get_array('values'));
      end loop embeddings_loop;
    end;

    uc_ai_logger.log('Returning ' || l_embeddings.get_size || ' embeddings', l_scope);

    return l_embeddings;
  end generate_embeddings;

end uc_ai_google;
/
