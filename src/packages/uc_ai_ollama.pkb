create or replace package body uc_ai_ollama as 

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'http://localhost:11434/api';
  c_api_generate_text_path constant varchar2(255 char) := '/chat';
  c_api_generate_embeddings_path constant varchar2(255 char) := '/embed';

  -- Per-call conversation state is threaded as run-state/message parameters,
  -- not package globals, so nested calls do not corrupt each other.

  -- Chat API reference: https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion

  function get_generate_text_url(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    if p_settings.base_url is not null then
      return rtrim(p_settings.base_url, '/') || c_api_generate_text_path;
    end if;

    return c_api_url || c_api_generate_text_path;
  end get_generate_text_url;

  function get_generate_embeddings_url(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    if p_settings.base_url is not null then
      return rtrim(p_settings.base_url, '/') || c_api_generate_embeddings_path;
    end if;

    return c_api_url || c_api_generate_embeddings_path;
  end get_generate_embeddings_url;

  function get_text_content (
    p_message in json_object_t
  -- @dblinter ignore(g-7170): in out kept for a uniform signature across the get_*_content accumulator family
  -- @dblinter ignore(g-7440): pio_state is a run-state accumulator threaded through the call, so in out is intentional
  , pio_state in out nocopy uc_ai_settings.t_run_state
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

    pio_state.final_message := l_content;

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

  /*
   * p_has_tool_calls tells this function that the turn it is looking at also
   * carries tool calls. A native /api/chat tool-call turn looks exactly like
   * {"role":"assistant","content":"","tool_calls":[...]} - no text and no
   * thinking - so an empty result is expected there and must not raise. Only a
   * turn that carries neither content nor tool calls is a response we cannot use.
   */
  function process_llm_response(
    p_message in json_object_t
  -- @dblinter ignore(g-7440): pio_state is a run-state accumulator threaded through the call, so in out is intentional
  , pio_state in out nocopy uc_ai_settings.t_run_state
  , p_has_tool_calls in boolean default false
  ) return json_array_t
  as
    l_lm_text_content  json_object_t;
    l_lm_reasoning_content json_object_t;
    l_arr json_array_t;
  begin
    l_lm_text_content := get_text_content(p_message, pio_state);
    l_lm_reasoning_content := get_reasoning_content(p_message);

    if l_lm_reasoning_content is null and l_lm_text_content is null and not p_has_tool_calls then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_format_processing
      , p_scope      => c_scope_prefix || 'process_llm_response'
      , p0           => 'No content to process response'
      , p_extra      => p_message.to_clob
      );
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
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_lm_messages_to_ollama';
    l_lm_message json_object_t;
    l_ollama_message json_object_t;
    l_role varchar2(255 char);
    l_content json_array_t;
    l_content_item json_object_t;
    l_content_type varchar2(255 char);
    l_media_type varchar2(255 char);
    l_ollama_content clob;
    l_ollama_thinking clob;
    l_images json_array_t;
    l_tool_calls json_array_t;
    l_tool_call json_object_t;
    l_function json_object_t;
  begin
    uc_ai_logger.log('Converting ' || p_lm_messages.get_size || ' LM messages to Ollama format', l_scope);
    
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
                -- /api/chat carries attachments only as base64 images in `images`;
                -- it has no envelope for anything else. Appending a PDF here would
                -- send it as an image and the model would read garbage, so reject
                -- every non-image media type instead, like uc_ai_openai does.
                l_media_type := l_content_item.get_string('mediaType');

                if l_media_type like 'image/%' then
                  l_images.append(l_content_item.get_clob('data'));
                else
                  uc_ai_error.raise_error(
                    p_error_code => uc_ai_error.c_err_unhandled_format
                  , p_scope      => l_scope
                  , p0           => 'file type'
                  , p1           => l_media_type
                  , p_extra      => l_content_item.stringify
                  );
                end if;
              else
                uc_ai_logger.log_warn('Unsupported user content type for Ollama: ' || l_content_type, l_scope);
            end case;
          end loop user_content_loop;

          -- A user message that carries only files is legal in the normalized
          -- format. The former guard `length(l_ollama_content) > 0` is NULL - and
          -- so not TRUE - when there is no text part, which dropped the whole
          -- message and every image with it.
          if l_ollama_content is not null or l_images.get_size > 0 then
            l_ollama_message := json_object_t();
            l_ollama_message.put('role', 'user');
            -- /api/chat wants a content string on every message; an images-only
            -- turn sends an empty one rather than a JSON null.
            l_ollama_message.put('content', coalesce(l_ollama_content, empty_clob()));
            if l_images.get_size > 0 then
              l_ollama_message.put('images', l_images);
            end if;
            po_ollama_messages.append(l_ollama_message);
          end if;

        when 'assistant' then
          -- Assistant message: can have text content and/or tool calls
          l_content := l_lm_message.get_array('content');
          l_ollama_content := null;
          l_ollama_thinking := null;
          l_tool_calls := json_array_t();

          <<assistant_content_loop>>
          for j in 0 .. l_content.get_size - 1
          loop
            l_content_item := treat(l_content.get(j) as json_object_t);
            l_content_type := l_content_item.get_string('type');

            case l_content_type
              when 'text' then
                l_ollama_content := l_ollama_content || l_content_item.get_clob('text');
              when 'reasoning' then
                -- /api/chat accepts 'thinking' on assistant messages, so replay it
                -- instead of dropping the model's chain of thought.
                l_ollama_thinking := l_ollama_thinking || l_content_item.get_clob('text');
              when 'tool_call' then
                -- Convert to OpenAI-style tool call format that Ollama expects
                l_tool_call := json_object_t();
                l_tool_call.put('id', l_content_item.get_string('toolCallId'));
                l_tool_call.put('type', 'function');
                
                l_function := json_object_t();
                l_function.put('name', l_content_item.get_string('toolName'));
                l_function.put('arguments', json_object_t(l_content_item.get_clob('args')));
                
                l_tool_call.put('function', l_function);
                l_tool_calls.append(l_tool_call);
              else
                uc_ai_logger.log_warn('Unsupported assistant content type for Ollama: ' || l_content_type, l_scope);
            end case;
          end loop assistant_content_loop;
          
          l_ollama_message := json_object_t();
          l_ollama_message.put('role', 'assistant');
          l_ollama_message.put('content', l_ollama_content);

          if l_ollama_thinking is not null then
            l_ollama_message.put('thinking', l_ollama_thinking);
          end if;

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
          uc_ai_logger.log_warn('Unknown message role: ' || l_role, l_scope);
      end case;
    end loop message_loop;

    uc_ai_logger.log('Converted to ' || po_ollama_messages.get_size || ' Ollama messages', l_scope);
  end convert_lm_messages_to_ollama;



  procedure internal_generate_text (
    pio_messages         in out nocopy json_array_t
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
    if pio_state.tool_calls >= p_max_tool_calls then
      pio_result.put('finish_reason', 'max_tool_calls_exceeded');
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_max_calls_exceeded
      , p_scope      => l_scope
      , p0           => to_char(p_max_tool_calls)
      );
    end if;

    l_input_obj := p_input_obj;
    l_input_obj.put('messages', pio_messages);
    l_input_obj.put('think', p_settings.enable_reasoning);

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json'
    );
    uc_ai_settings.apply_extra_headers(p_settings);

    l_resp := uc_ai_http.post(
      p_url => get_generate_text_url(p_settings),
      p_body => l_input_obj.to_clob,
      p_credential_static_id => coalesce(p_settings.apex_web_credential, p_settings.ol_apex_web_credential)
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'Ollama', l_scope);

    if l_resp_json.has('error') then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'ollama'
      , p1           => l_resp_json.get_clob('error')
      , p_extra      => l_resp
      );
    end if;

    -- Ollama's native /api/chat reports prompt_eval_count and eval_count; the
    -- OpenAI-compatible route reports a usage object. Normalize both, so the result
    -- carries usage on either route.
    if l_resp_json.has('usage') then
      l_usage := l_resp_json.get_object('usage');
    elsif l_resp_json.has('prompt_eval_count') or l_resp_json.has('eval_count') then
      l_usage := json_object_t();
      l_usage.put('prompt_tokens', nvl(l_resp_json.get_number('prompt_eval_count'), 0));
      l_usage.put('completion_tokens', nvl(l_resp_json.get_number('eval_count'), 0));
    else
      l_usage := null;
    end if;

    if l_usage is not null then
      -- Sum over the tool loop and keep the four documented keys, like every other
      -- provider. Ollama reports no separate reasoning count.
      declare
        l_prompt_tokens     number;
        l_completion_tokens number;
        l_result_usage      json_object_t;
      begin
        l_prompt_tokens     := nvl(l_usage.get_number('prompt_tokens'), 0);
        l_completion_tokens := nvl(l_usage.get_number('completion_tokens'), 0);

        if pio_result.has('usage') then
          l_result_usage      := pio_result.get_object('usage');
          l_prompt_tokens     := l_prompt_tokens + nvl(l_result_usage.get_number('prompt_tokens'), 0);
          l_completion_tokens := l_completion_tokens + nvl(l_result_usage.get_number('completion_tokens'), 0);
        else
          l_result_usage := json_object_t();
        end if;

        l_result_usage.put('prompt_tokens', l_prompt_tokens);
        l_result_usage.put('completion_tokens', l_completion_tokens);
        l_result_usage.put('reasoning_tokens', cast(null as number));
        l_result_usage.put('total_tokens', l_prompt_tokens + l_completion_tokens);
        pio_result.put('usage', l_result_usage);
      end;
    end if;

    -- Extract model information
    if l_resp_json.has('model') then
      l_model := l_resp_json.get_string('model');
      pio_result.put('model', l_model);
    end if;

    -- Extract message from response
    l_message := l_resp_json.get_object('message');

    -- A body without a usable message object would otherwise reach l_message.has
    -- below and fail with ORA-30625 instead of a UC AI error the caller can read.
    if l_message is null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_format_processing
      , p_scope      => l_scope
      , p0           => 'Response has no message object'
      , p_extra      => l_resp
      );
    end if;

    -- Check if response contains tool calls. has() is true for a JSON null as
    -- well, and OpenAI-compatible servers behind the same route do send
    -- "tool_calls": null, so the array itself has to be checked.
    if l_message.has('tool_calls') then
      l_tool_calls := l_message.get_array('tool_calls');
      l_has_tool_calls := l_tool_calls is not null and l_tool_calls.get_size > 0;
    end if;

    -- add response text to the per-call conversation history. A tool-call turn
    -- legitimately carries no text, so the empty-content guard is skipped there.
    l_assistant_content := process_llm_response(l_message, pio_state, l_has_tool_calls);

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
        -- A tool-call turn has no text. Replay it as an empty string, not as a
        -- JSON null, which is not a valid content value for /api/chat.
        l_resp_message.put('content', coalesce(l_message.get_clob('content'), empty_clob()));
        l_resp_message.put('tool_calls', l_tool_calls);
        pio_messages.append(l_resp_message);

        -- Process each tool call and collect results
        <<tool_calls_loop>>
        for j in 0 .. l_tool_calls.get_size - 1
        loop
          l_tool_call := treat(l_tool_calls.get(j) as json_object_t);
          uc_ai_logger.log('Processing tool call', l_scope, 'Tool Call: ' || l_tool_call.to_clob);
          
          pio_state.tool_calls := pio_state.tool_calls + 1;

          l_tool_call_id := 'tool_call_' || pio_state.tool_calls; -- Generate unique ID for tool call
          l_function := l_tool_call.get_object('function');
          l_tool_name := l_function.get_string('name');
          
          -- Parse tool arguments. has() is true for "arguments": null too, and
          -- get_object returns NULL for anything that is not an object, so a
          -- no-argument call from a compatible server must fall back to {}
          -- rather than carry a NULL into execute_agent_tool (ORA-30625).
          if l_function.has('arguments') then
            l_tool_input := l_function.get_object('arguments');
          else
            -- reset: the variable outlives one iteration of this loop
            l_tool_input := null;
          end if;

          if l_tool_input is null then
            l_tool_input := json_object_t();
          end if;

          l_new_msg := uc_ai_message_api.create_tool_call_content(
            p_tool_call_id => l_tool_call_id
          , p_tool_name    => l_tool_name
          , p_args         => l_tool_input.to_clob
          );
          l_assistant_content.append(l_new_msg);

          uc_ai_logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name || ', Tool ID: ' || l_tool_call_id);
          uc_ai_logger.log('Tool input', l_scope, 'Input: ' || l_tool_input.to_clob);

          -- Fire the per-tool-call hook (may veto by raising, stopping the run)
          uc_ai_tools_api.before_tool_call(p_tool_code => l_tool_name, p_settings => p_settings);

          -- Execute the tool (or run the code-mode program in the sandbox)
          l_tool_result := uc_ai_tools_api.execute_agent_tool(
            p_tool_code          => l_tool_name
          , p_arguments          => l_tool_input
          , p_settings           => p_settings
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
        pio_norm_messages.append(l_assistant_message);

        pio_norm_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));

        pio_result.put('tool_calls_count', pio_state.tool_calls);

        -- Continue conversation with tool results - recursive call
        internal_generate_text(
          pio_messages         => pio_messages
        , p_max_tool_calls     => p_max_tool_calls
        , p_input_obj          => p_input_obj
        , pio_result           => pio_result
        , p_settings           => p_settings
        , pio_state            => pio_state
        , pio_norm_messages    => pio_norm_messages
        );
      end;
    else
      -- Normal completion - add AI's message to conversation
      uc_ai_logger.log('Normal completion received', l_scope);
      pio_messages.append(l_message);

      l_assistant_message := uc_ai_message_api.create_assistant_message(
        p_content => l_assistant_content
      );
      pio_norm_messages.append(l_assistant_message);
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

    uc_ai_logger.log('End internal_generate_text - final messages count: ' || pio_messages.get_size, l_scope);
  exception
    when others then
      uc_ai_logger.log_error('Exception in internal_generate_text', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace );
      raise;
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
   * - final_message: last message content for simple usage. With a response
   *   schema this holds the JSON as TEXT; nothing parses it here
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
  , p_settings       in uc_ai_settings.t_settings default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_text_with_messages';
    l_settings           uc_ai_settings.t_settings;
    l_state              uc_ai_settings.t_run_state := uc_ai_settings.new_run_state;
    l_norm_messages      json_array_t := json_array_t();
    l_input_obj          json_object_t := json_object_t();
    l_ollama_messages    json_array_t;
    l_tools              json_array_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_format             json_object_t;
  begin
    uc_ai_logger.log('Starting generate_text with ' || p_messages.get_size || ' input messages', l_scope);

    if nvl(p_settings.initialized, false) then
      l_settings := p_settings;
    else
      l_settings := uc_ai_settings.build_from_globals;
    end if;

    if l_settings.ol_use_responses_api then
      declare
        l_base          varchar2(500 char);
        l_resp_settings uc_ai_settings.t_settings := l_settings;
      begin
        l_base := coalesce(l_settings.base_url, c_api_url);
        if l_base is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_missing_config
          , p_scope      => l_scope
          , p0           => 'Ollama Responses API'
          , p1           => 'a base URL (set uc_ai.g_base_url)'
          );
        end if;
        -- Replace /api suffix with /v1 for OpenAI-compatible endpoint
        if l_base like '%/api' then
          l_base := substr(l_base, 1, length(l_base) - 4) || '/v1';
        else
          l_base := rtrim(l_base, '/') || '/v1';
        end if;
        -- Build a settings copy for the Responses API delegate. No package
        -- globals are mutated. The responses URL lives in ra_base_url; base_url
        -- is cleared so get_generate_text_url falls through to ra_base_url.
        l_resp_settings.ra_base_url := l_base;
        l_resp_settings.ra_apex_web_credential := coalesce(l_settings.apex_web_credential, l_settings.ol_apex_web_credential);
        l_resp_settings.ra_skip_auth := l_resp_settings.ra_apex_web_credential is null;
        l_resp_settings.provider_override := uc_ai.c_provider_ollama;
        l_resp_settings.base_url := null;

        return uc_ai_responses_api.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => p_max_tool_calls
        , p_schema         => p_schema
        , p_settings       => l_resp_settings
        );
      end;
    end if;

    l_result := json_object_t();

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

    -- Get all available tools formatted for Ollama. Fetch when local tools are
    -- enabled OR when provider (server-side) tools were supplied.
    if l_settings.enable_tools
       or (l_settings.provider_tools is not null and l_settings.provider_tools.get_size > 0) then
      l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_ollama, p_tool_tags => l_settings.tool_tags, p_enable_tools => l_settings.enable_tools, p_provider_tools => l_settings.provider_tools, p_programmatic_tools => l_settings.enable_programmatic_tools);

      if l_tools.get_size > 0 then
        l_input_obj.put('tools', l_tools);
      end if;
    end if;

    -- Merge user-supplied extra body properties (before messages are added)
    uc_ai_settings.apply_extra_body(l_input_obj, l_settings);

    internal_generate_text(
      pio_messages         => l_ollama_messages
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

    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_ollama);

    uc_ai_logger.log('Completed generate_text with final message count: ' || l_norm_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

  function generate_embeddings (
    p_input in json_array_t
  , p_model in uc_ai.model_type
  , p_settings in uc_ai_settings.t_settings default null
  ) return json_array_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_embeddings';
    l_settings      uc_ai_settings.t_settings;
    l_url           varchar2(4000 char);
    l_resp          clob;
    l_resp_json     json_object_t;
    l_embeddings    json_array_t;
    l_input_obj     json_object_t := json_object_t();
  begin
    uc_ai_logger.log('Starting generate_embeddings with ' || p_input.get_size || ' input items',
      l_scope);

    if nvl(p_settings.initialized, false) then
      l_settings := p_settings;
    else
      l_settings := uc_ai_settings.build_from_globals;
    end if;

    l_input_obj.put('model', p_model);
    l_input_obj.put('input', p_input);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(
      p_name_01  => 'content-type',
      p_value_01 => 'application/json'
    );
    uc_ai_settings.apply_extra_headers(l_settings);

    uc_ai_logger.log('Request body', l_scope, l_input_obj.to_clob);

    l_url := get_generate_embeddings_url(l_settings);
    uc_ai_logger.log('Request URL: ' || l_url, l_scope);

    l_resp := uc_ai_http.post(
      p_url => l_url,
      p_body => l_input_obj.to_clob,
      p_credential_static_id => coalesce(l_settings.apex_web_credential, l_settings.ol_apex_web_credential)
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'Ollama', l_scope);

    if l_resp_json.has('error') then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'Ollama'
      , p1           => l_resp_json.get_clob('error')
      , p_extra      => l_resp
      );
    end if;

    l_embeddings := l_resp_json.get_array('embeddings');

    return l_embeddings;
  end generate_embeddings;

end uc_ai_ollama;
/
