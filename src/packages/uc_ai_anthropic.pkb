create or replace package body uc_ai_anthropic as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_api_url constant varchar2(255 char) := 'https://api.anthropic.com/v1';
  c_api_generate_text_path constant varchar2(255 char) := '/messages';
  c_anthropic_version constant varchar2(32 char) := '2023-06-01';

  -- Anthropic's documented floor for a legacy thinking budget
  c_min_reasoning_tokens constant pls_integer := 1024;

  -- space, tab, newline, carriage return - what Anthropic counts as trailing
  -- whitespace on a prefilled assistant message
  c_whitespace constant varchar2(4 char) := ' ' || chr(9) || chr(10) || chr(13);

  -- Per-call conversation state is threaded as run-state/message parameters,
  -- not package globals, so nested calls do not corrupt each other.

  -- Chat API reference: https://docs.anthropic.com/en/api/messages

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
    l_content := p_message.get_clob('text');
    l_provider_options := p_message.clone();
    l_provider_options.remove('type');
    l_provider_options.remove('text');

    l_lm_text_content := uc_ai_message_api.create_text_content(
      p_text             => l_content
    , p_provider_options => l_provider_options
    );

    -- One turn can carry several text blocks: citations split the answer, and a
    -- provider-side tool puts its commentary in its own block. Assigning here
    -- kept only the last of them, so the caller lost everything before it.
    -- Empty blocks are skipped: a text part with no text is a carrier for
    -- provider metadata, not part of the answer.
    if l_content is not null and length(l_content) > 0 then
      if pio_state.final_message is not null then
        pio_state.final_message := pio_state.final_message || chr(10);
      end if;
      pio_state.final_message := pio_state.final_message || l_content;
    end if;

    return l_lm_text_content;
  end get_text_content;


  /*
   * Normalizes an Anthropic 'thinking' or 'redacted_thinking' content block.
   *
   * Every key of the block except the reasoning text itself is kept in
   * providerOptions, because Anthropic's contract is that the block goes back
   * unmodified when the assistant turn is replayed: 'signature' is the token that
   * vouches for a thinking block, and 'data' is the opaque payload of a redacted
   * one. 'type' is kept too so the replay path can tell the two apart (a redacted
   * block has no readable text at all).
   * See convert_lm_messages_to_anthropic.
   */
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
    po_system_prompt out nocopy clob,
    po_anthropic_messages out nocopy json_array_t
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
    l_thinking_blocks json_array_t;
    l_tool_use json_object_t;
    l_tool_result json_object_t;
    l_system_text clob;
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
          -- System message: extract content for the separate system field.
          -- Several system messages are legal on the way in (a guardrail block
          -- plus a policy block, or an agent prompt plus a memory protocol).
          -- Anthropic has exactly one system field, so they are joined with a
          -- blank line instead of overwriting each other - message N used to
          -- silently delete message N-1.
          l_system_text := l_lm_message.get_clob('content');
          if l_system_text is not null and length(l_system_text) > 0 then
            if po_system_prompt is not null then
              po_system_prompt := po_system_prompt || chr(10) || chr(10);
            end if;
            po_system_prompt := po_system_prompt || l_system_text;
          end if;

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
                    uc_ai_error.raise_error(
                      p_error_code => uc_ai_error.c_err_unhandled_format
                    , p_scope      => l_scope
                    , p0           => 'file type'
                    , p1           => l_mime_type
                    , p_extra      => l_content_item.stringify
                    );
                  end if;
                  
                  l_anthropic_content.append(l_file_block);
                end;
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_unsupported_content
                , p_scope      => l_scope
                , p0           => l_content_type
                , p_extra      => l_content_item.stringify
                );
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
          l_thinking_blocks := json_array_t();

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

              when 'reasoning' then
                -- Anthropic's contract is that a thinking block is handed back
                -- unmodified, with its signature, so the model can continue the
                -- chain of thought it already paid for. (Measured against
                -- claude-haiku-4-5: the API currently TOLERATES a replayed turn
                -- whose thinking was stripped, and does not reject a bad
                -- signature - so this is about reasoning continuity and honouring
                -- the documented contract, not about avoiding an HTTP error.)
                --
                -- A block with no signature has no provenance we could vouch for,
                -- so it is dropped rather than invented - stricter modes such as
                -- interleaved thinking do validate what they are given.
                declare
                  l_provider_options json_object_t;
                  l_thinking_block json_object_t;
                  l_block_type varchar2(255 char);
                  l_signature clob;
                  l_redacted_data clob;
                begin
                  if l_content_item.has('providerOptions') and not l_content_item.get('providerOptions').is_null then
                    l_provider_options := l_content_item.get_object('providerOptions');

                    if l_provider_options.has('type') and not l_provider_options.get('type').is_null then
                      l_block_type := l_provider_options.get_string('type');
                    end if;

                    if l_provider_options.has('signature') and not l_provider_options.get('signature').is_null then
                      l_signature := l_provider_options.get_clob('signature');
                    end if;

                    if l_provider_options.has('data') and not l_provider_options.get('data').is_null then
                      l_redacted_data := l_provider_options.get_clob('data');
                    end if;
                  end if;

                  if l_block_type = 'redacted_thinking' and l_redacted_data is not null then
                    l_thinking_block := json_object_t();
                    l_thinking_block.put('type', 'redacted_thinking');
                    l_thinking_block.put('data', l_redacted_data);
                    l_thinking_blocks.append(l_thinking_block);
                  elsif l_signature is not null then
                    l_thinking_block := json_object_t();
                    l_thinking_block.put('type', 'thinking');
                    l_thinking_block.put('thinking', l_content_item.get_clob('text'));
                    l_thinking_block.put('signature', l_signature);
                    l_thinking_blocks.append(l_thinking_block);
                  else
                    uc_ai_logger.log('Skipping unsigned thinking block (cannot be verified by Anthropic)', l_scope);
                  end if;
                end;

              else
                null; -- Skip unknown content types
            end case;
          end loop assistant_content_loop;

          -- Anthropic requires thinking blocks to come FIRST in the content array,
          -- so they are collected separately above and prepended here instead of
          -- relying on the order they happen to have in the normalized message.
          if l_thinking_blocks.get_size > 0 then
            declare
              l_ordered_content json_array_t := json_array_t();
            begin
              <<thinking_first_loop>>
              for k in 0 .. l_thinking_blocks.get_size - 1
              loop
                l_ordered_content.append(treat(l_thinking_blocks.get(k) as json_object_t));
              end loop thinking_first_loop;

              <<remaining_content_loop>>
              for k in 0 .. l_anthropic_content.get_size - 1
              loop
                l_ordered_content.append(treat(l_anthropic_content.get(k) as json_object_t));
              end loop remaining_content_loop;

              l_anthropic_content := l_ordered_content;
            end;
          end if;

          -- An assistant message in last position is a prefill: Anthropic
          -- continues writing from it instead of starting a new turn, and
          -- rejects the request with HTTP 400 "final assistant content cannot
          -- end with trailing whitespace" when the text it must continue ends
          -- in a space or newline. Only the very last block is affected, and
          -- only when it is a text block - a trailing tool_use is untouched.
          -- The block is rebuilt rather than mutated in place so the array node
          -- is replaced wholesale. json_array_t.put defaults to INSERTING at the
          -- position and shifting the rest, so the overwrite flag is required -
          -- without it the trailing text block is duplicated.
          if i = p_lm_messages.get_size - 1 and l_anthropic_content.get_size > 0 then
            declare
              l_last_pos   pls_integer;
              l_last_block json_object_t;
              l_prefill    clob;
            begin
              l_last_pos := l_anthropic_content.get_size - 1;
              l_last_block := treat(l_anthropic_content.get(l_last_pos) as json_object_t);

              if l_last_block.get_string('type') = 'text' then
                l_prefill := rtrim(l_last_block.get_clob('text'), c_whitespace);
                l_last_block := json_object_t();
                l_last_block.put('type', 'text');
                l_last_block.put('text', l_prefill);
                l_anthropic_content.put(l_last_pos, l_last_block, true);
              end if;
            end;
          end if;

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

    l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.an_apex_web_credential);
    if l_web_credential is null then
      apex_web_service.g_request_headers(3).name := 'x-api-key';
      apex_web_service.g_request_headers(3).value := uc_ai_get_key(uc_ai.c_provider_anthropic);
    end if;

    uc_ai_settings.apply_extra_headers(p_settings);

    l_resp := uc_ai_http.post(
      p_url => get_generate_text_url(p_settings),
      p_body => l_input_obj.to_clob,
      p_credential_static_id => l_web_credential
    );

    uc_ai_logger.log('Response', l_scope, l_resp);

    l_resp_json := uc_ai_error.parse_json_response(l_resp, 'Anthropic', l_scope);

    if l_resp_json.has('error') then
      l_temp_obj := l_resp_json.get_object('error');
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'anthropic'
      , p1           => l_temp_obj.get_string('message')
      , p_extra      => l_temp_obj.to_clob
      );
    end if;

    -- Extract and accumulate usage information in global counters
    if l_resp_json.has('usage') then
      l_usage := l_resp_json.get_object('usage');
      pio_state.input_tokens := pio_state.input_tokens + nvl(l_usage.get_number('input_tokens'), 0);
      pio_state.output_tokens := pio_state.output_tokens + nvl(l_usage.get_number('output_tokens'), 0);
    end if;

    -- Extract model information
    if l_resp_json.has('model') then
      l_model := l_resp_json.get_string('model');
      pio_result.put('model', l_model);
    end if;

    -- Extract stop reason
    l_stop_reason := l_resp_json.get_string('stop_reason');
    
    -- Map Anthropic stop reasons to the uc_ai.c_finish_reason_* vocabulary.
    -- Anthropic sends more than the four values this used to handle, all on an
    -- HTTP 200: 'refusal' when the model declines, 'pause_turn' when a
    -- provider-side tool runs long, 'model_context_window_exceeded' when the
    -- window fills. Writing those through unchanged handed the caller a
    -- finish_reason that matches none of the constants it is told to compare
    -- against. The provider's own word is kept beside the mapped one so nothing
    -- is lost. See https://docs.anthropic.com/en/api/messages#response-stop-reason
    if l_stop_reason is not null then
      pio_result.put('provider_finish_reason', l_stop_reason);
    end if;

    case l_stop_reason
      when 'end_turn' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
      when 'stop_sequence' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
      when 'pause_turn' then
        -- the turn stopped early but nothing went wrong; the caller may send the
        -- conversation back to continue it
        pio_result.put('finish_reason', uc_ai.c_finish_reason_stop);
      when 'tool_use' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_tool_calls);
      when 'max_tokens' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
      when 'model_context_window_exceeded' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_length);
      when 'refusal' then
        pio_result.put('finish_reason', uc_ai.c_finish_reason_content_filter);
      else
        -- a null selector lands here too, which is what a truncated response
        -- looks like. 'unknown' is the value the result object starts with.
        uc_ai_logger.log_warn('Unmapped Anthropic stop_reason: ' || nvl(l_stop_reason, '<null>'), l_scope);
        pio_result.put('finish_reason', 'unknown');
    end case;

    -- Process content array
    l_content := l_resp_json.get_array('content');

    -- final_message is the answer of the LAST turn, so the text collected in the
    -- turns before this one is dropped here. Without the reset a final turn that
    -- carries no text at all (only server-side tool blocks) returned the text of
    -- an earlier turn as if the model had just written it.
    pio_state.final_message := null;
    
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

              pio_state.tool_calls := pio_state.tool_calls + 1;

              l_tool_call_id := l_content_prompt.get_string('id');
              l_tool_name := l_content_prompt.get_string('name');
              l_tool_input := l_content_prompt.get_object('input');
              if l_tool_input is not null then
                -- when we have a top-level object parameter, extract it. Anthropic wraps it into a named object
                l_param_name := uc_ai_tools_api.get_tools_object_param_name(l_tool_name);
                if l_param_name is not null then
                  l_tool_input := l_tool_input.get_object(l_param_name);
                end if;
              end if;

              uc_ai_logger.log('Tool call', l_scope, 'Tool Name: ' || l_tool_name || ', Tool ID: ' || l_tool_call_id);

              -- The unwrap above yields NULL whenever the model left the wrapper
              -- object out ({"input":{}} for a tool whose single object parameter
              -- is optional). That has to be turned into an empty object BEFORE
              -- anything dereferences it - to_clob on a NULL json_object_t raises
              -- ORA-30625, which used to kill the whole run.
              if l_tool_input is not null then
                uc_ai_logger.log('Tool input', l_scope, 'Input: ' || l_tool_input.to_clob);
              else
                uc_ai_logger.log('Tool input', l_scope, 'No input provided');
                l_tool_input := json_object_t();
              end if;

              l_new_msg := uc_ai_message_api.create_tool_call_content(
                p_tool_call_id => l_tool_call_id
              , p_tool_name    => l_tool_name
              , p_args         => l_tool_input.to_clob
              );
              l_normalized_messages.append(l_new_msg);
   
              -- Fire the per-tool-call hook (may veto by raising, stopping the run)
              uc_ai_tools_api.before_tool_call(p_tool_code => l_tool_name, p_settings => p_settings);

              -- Execute the tool (or, for the code-mode meta-tool, run the
              -- model-authored program in the sandbox) and get the result.
              l_tool_result := uc_ai_tools_api.execute_agent_tool(
                p_tool_code          => l_tool_name
              , p_arguments          => l_tool_input
              , p_settings           => p_settings
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

              l_new_msg := get_text_content(l_content_prompt, pio_state);
              l_normalized_messages.append(l_new_msg);
            when 'thinking' then
              uc_ai_logger.log('Thinking content block found', l_scope, l_content_prompt.to_clob);

              l_new_msg := get_reasoning_content(l_content_prompt);
              l_normalized_messages.append(l_new_msg);
            when 'redacted_thinking' then
              -- Encrypted reasoning we cannot read, but which must still be
              -- replayed verbatim on the next turn - normalize it so it survives
              -- a cross-call history round trip.
              uc_ai_logger.log('Redacted thinking content block found', l_scope);

              l_new_msg := get_reasoning_content(l_content_prompt);
              l_normalized_messages.append(l_new_msg);
            else
              -- Server-side tool blocks (server_tool_use, web_search_tool_result,
              -- code_execution_tool_result, ...) are produced and consumed by the
              -- provider when g_provider_tools are used. They are already part of
              -- the raw assistant message appended above; pass them through
              -- without local execution or normalization instead of erroring.
              uc_ai_logger.log('Passing through server-side content block: ' || l_content_prompt.get_string('type'), l_scope, l_content_prompt.to_clob);
          end case;
        end loop tool_use_loop;

        pio_norm_messages.append(uc_ai_message_api.create_assistant_message(l_normalized_messages));
        pio_norm_messages.append(uc_ai_message_api.create_tool_message(l_normalized_tool_results));


        pio_result.put('tool_calls_count', pio_state.tool_calls);

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
        , p_settings           => p_settings
        , pio_state            => pio_state
        , pio_norm_messages    => pio_norm_messages
        );
      end;
    else
      -- Normal completion - add AI's message to conversation

      declare
        l_content_msg       json_object_t;
        l_content_array     json_array_t := json_array_t();
        l_assistant_message json_object_t;
        l_resp_message      json_object_t := json_object_t();
      begin
        -- Add the AI's message to the raw conversation history as ONE assistant
        -- message carrying the whole content array, exactly like the tool_use
        -- path above. (This used to append each content block individually - and
        -- the last one a second time - which left bare content blocks sitting in
        -- what is meant to be a messages array.)
        l_resp_message.put('role', 'assistant');
        l_resp_message.put('content', l_content);
        pio_messages.append(l_resp_message);

        <<content_loop>>
        for i in 0 .. l_content.get_size - 1
        loop
          l_content_prompt := treat(l_content.get(i) as json_object_t);
          l_content_type := l_content_prompt.get_string('type');

          case l_content_type
            when 'text' then
              l_content_msg := get_text_content(l_content_prompt, pio_state);
              l_content_array.append(l_content_msg);
            when 'thinking' then
              l_content_msg := get_reasoning_content(l_content_prompt);
              l_content_array.append(l_content_msg);
            when 'redacted_thinking' then
              l_content_msg := get_reasoning_content(l_content_prompt);
              l_content_array.append(l_content_msg);
            else
              -- Server-side tool blocks (server_tool_use, web_search_tool_result,
              -- code_execution_tool_result, ...) from g_provider_tools are executed
              -- by the provider. Preserved in the raw conversation appended above,
              -- but skip normalization instead of erroring.
              uc_ai_logger.log('Passing through server-side content block: ' || l_content_type, l_scope, l_content_prompt.to_clob);
          end case;
        end loop content_loop;

        l_assistant_message := uc_ai_message_api.create_assistant_message(
          p_content => l_content_array
        );
        pio_norm_messages.append(l_assistant_message);
      end;
    end if;

    uc_ai_logger.log('End internal_generate_text - final messages count: ' || pio_messages.get_size, l_scope);

  end internal_generate_text;


  /*
   * True when the model takes the ADAPTIVE thinking shape
   * (thinking:{"type":"adaptive"} plus output_config.effort), false when it takes
   * the legacy budget shape (thinking:{"type":"enabled","budget_tokens":N}).
   *
   * The two are not interchangeable. Claude 4.6 and later answer the legacy shape
   * with HTTP 400 ("thinking.type.enabled is not supported for this model"), and
   * pre-4.6 models answer the adaptive shape the same way, so the request has to
   * be built for the model it is sent to.
   *
   * The test is written the other way round on purpose: the models that need the
   * LEGACY shape are named, and everything else - including a model id this
   * version of UC AI has never heard of - gets the adaptive shape. Anthropic
   * releases models faster than UC AI releases versions, and every model since
   * 4.6 is adaptive, so an unknown id is far more likely to be newer than older.
   */
  function uses_adaptive_thinking(
    p_model in uc_ai.model_type
  ) return boolean
  as
    l_model varchar2(128 char);
  begin
    l_model := lower(p_model);

    -- Opus/Sonnet 4.0 to 4.5, Haiku 4.5, and everything from Claude 3 and older
    if regexp_like(l_model, 'claude-(opus|sonnet)-4-[0-5]')
       or l_model like '%claude-haiku-4-5%'
       or regexp_like(l_model, 'claude-(3|2|instant)')
    then
      return false;
    end if;

    return true;
  end uses_adaptive_thinking;


  /*
   * 4.6 was the first model with adaptive thinking, but its efforts stop at
   * 'max'. 'xhigh' arrived with the models after it (opus-4-7, opus-4-8,
   * opus-5, sonnet-5, fable-5), so an unknown - assumed newer - id gets it too.
   */
  function supports_xhigh_effort(
    p_model in uc_ai.model_type
  ) return boolean
  as
    l_model varchar2(128 char);
  begin
    l_model := lower(p_model);

    return not (l_model like '%claude-opus-4-6%' or l_model like '%claude-sonnet-4-6%');
  end supports_xhigh_effort;


  /*
   * Maps the UC AI reasoning level to the effort adaptive thinking takes inside
   * output_config. Returns null when the level carries nothing an effort can be
   * made of - the effort key is then left out and the model picks its own depth,
   * which is the whole point of adaptive thinking.
   */
  function map_reasoning_effort(
    p_model in uc_ai.model_type
  , p_level in varchar2
  ) return varchar2
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'map_reasoning_effort';
    l_level  varchar2(100 char);
    l_effort varchar2(10 char);
  begin
    l_level := lower(p_level);

    case l_level
      when uc_ai.c_reasoning_level_low then
        l_effort := 'low';
      when uc_ai.c_reasoning_level_medium then
        l_effort := 'medium';
      when uc_ai.c_reasoning_level_high then
        l_effort := 'high';
      when 'xhigh' then
        l_effort := case when supports_xhigh_effort(p_model) then 'xhigh' else 'max' end;
      when 'max' then
        l_effort := 'max';
      else
        -- Includes a null level and a raw token budget passed as a level. A
        -- budget means nothing here: the model, not the caller, decides how long
        -- to think, so the request goes out without an effort rather than with a
        -- value Anthropic would reject.
        if l_level is not null then
          uc_ai_logger.log_warn('Reasoning level "' || p_level || '" has no adaptive thinking effort, letting the model choose', l_scope);
        end if;
    end case;

    return l_effort;
  end map_reasoning_effort;


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
  , p_schema         in json_object_t default null
  , p_settings       in uc_ai_settings.t_settings default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'generate_text_with_messages';
    l_settings           uc_ai_settings.t_settings;
    l_state              uc_ai_settings.t_run_state := uc_ai_settings.new_run_state;
    l_norm_messages      json_array_t := json_array_t();
    l_input_obj          json_object_t := json_object_t();
    l_anthropic_messages json_array_t;
    l_system_prompt      clob;
    l_tools              json_array_t;
    l_reasoning          json_object_t;
    l_result             json_object_t;
    l_message            json_object_t;
    l_reasoning_tokens   pls_integer;
    l_output_config      json_object_t;
    l_effort             varchar2(10 char);
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
    
    -- Convert standardized messages to Anthropic format
    convert_lm_messages_to_anthropic(
      p_lm_messages => p_messages,
      po_anthropic_messages => l_anthropic_messages,
      po_system_prompt => l_system_prompt
    );

    l_input_obj.put('model', p_model);

    -- Get all available tools formatted for Anthropic
    l_tools := uc_ai_tools_api.get_tools_array(uc_ai.c_provider_anthropic, p_tool_tags => l_settings.tool_tags, p_enable_tools => l_settings.enable_tools, p_provider_tools => l_settings.provider_tools, p_programmatic_tools => l_settings.enable_programmatic_tools);

    if l_tools.get_size > 0 then
      l_input_obj.put('tools', l_tools);
    end if;

    if l_settings.enable_reasoning then
      l_reasoning := json_object_t();

      if uses_adaptive_thinking(p_model) then
        -- Adaptive thinking: the model decides per turn how long to think, and
        -- the caller only says how hard to try. 'summarized' is what makes the
        -- reasoning readable in the response at all - the default is 'omitted',
        -- which would leave the normalized reasoning content empty.
        l_reasoning.put('type', 'adaptive');
        l_reasoning.put('display', 'summarized');

        -- The effort belongs INSIDE output_config, which structured output also
        -- writes to, so it is collected here and merged below.
        l_effort := map_reasoning_effort(p_model, l_settings.reasoning_level);
        uc_ai_logger.log_info('Using adaptive thinking with effort: ' || nvl(l_effort, 'model default'), l_scope);
      else
        l_reasoning.put('type', 'enabled');
        if l_settings.an_reasoning_budget_tokens is not null then
          l_reasoning_tokens := l_settings.an_reasoning_budget_tokens;
        elsif l_settings.reasoning_level is not null then
          l_reasoning_tokens := case l_settings.reasoning_level
            when uc_ai.c_reasoning_level_low then 2048
            when uc_ai.c_reasoning_level_medium then 8192
            when uc_ai.c_reasoning_level_high then 32768
            else l_settings.reasoning_level
          end;
        end if;

        -- Reasoning switched on with neither a budget nor a level used to send
        -- budget_tokens: null, which Anthropic answers with HTTP 400. The
        -- documented minimum is 1024, so that is what an unset or too small
        -- budget becomes.
        l_reasoning_tokens := greatest(nvl(l_reasoning_tokens, c_min_reasoning_tokens), c_min_reasoning_tokens);

        uc_ai_logger.log_info('Using reasoning with budget tokens: ' || l_reasoning_tokens, l_scope);
        l_reasoning.put('budget_tokens', l_reasoning_tokens);
      end if;

      l_input_obj.put('thinking', l_reasoning);
    end if;

    -- Add structured output format if schema is provided
    if p_schema is not null then
      l_output_config := uc_ai_structured_output.to_anthropic_format(
        p_schema => p_schema
      );
    end if;

    -- The reasoning effort and the structured output format live in the SAME
    -- output_config object, so the one built second is merged into the one built
    -- first instead of replacing it.
    if l_effort is not null then
      if l_output_config is null then
        l_output_config := json_object_t();
      end if;
      l_output_config.put('effort', l_effort);
    end if;

    if l_output_config is not null then
      l_input_obj.put('output_config', l_output_config);
    end if;

    -- Only the legacy shape reserves thinking tokens out of max_tokens. On the
    -- adaptive path l_reasoning_tokens stays null and there is nothing to check.
    if l_reasoning_tokens is not null and l_settings.an_max_tokens <= l_reasoning_tokens then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_reasoning_budget
      , p_scope      => l_scope
      , p0           => to_char(l_reasoning_tokens)
      , p1           => to_char(l_settings.an_max_tokens)
      );
    end if;

    l_input_obj.put('max_tokens', l_settings.an_max_tokens); -- Anthropic requires max_tokens

    -- Merge user-supplied extra body properties (before messages/system are added)
    uc_ai_settings.apply_extra_body(l_input_obj, l_settings);

    internal_generate_text(
      pio_messages         => l_anthropic_messages
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
      l_usage_obj.put('reasoning_tokens', cast(null as number)); -- anthropic does not provide separate reasoning token count
      l_usage_obj.put('total_tokens', l_state.input_tokens + l_state.output_tokens);
      l_result.put('usage', l_usage_obj);
    end;

    -- Add provider info to the result
    l_result.put('provider', uc_ai.c_provider_anthropic);

    uc_ai_logger.log('Completed generate_text with final message count: ' || l_norm_messages.get_size, l_scope);
    
    return l_result;
  end generate_text;

end uc_ai_anthropic;
/
