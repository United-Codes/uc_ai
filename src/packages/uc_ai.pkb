create or replace package body uc_ai as

  c_scope_prefix           constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_default_max_tool_calls constant pls_integer := 10;

  function generate_text (
    p_messages              in json_array_t
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t
  as
    l_result json_object_t;
  begin
    -- assign a fresh correlation id for this AI call; used by fire_event to gate emission
    g_request_id := rawtohex(sys_guid());

    case p_provider
      when c_provider_openai then
        l_result := uc_ai_openai.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_anthropic then
        l_result := uc_ai_anthropic.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_google then
        l_result := uc_ai_google.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_ollama then
        l_result := uc_ai_ollama.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_oci then
        if p_response_json_schema is not null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_structured_unsupported
          , p_scope      => c_scope_prefix || 'generate_text'
          , p0           => p_provider
          );
        else
          l_result := uc_ai_oci.generate_text(
            p_messages       => p_messages
          , p_model          => p_model
          , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
          );
        end if;
      when c_provider_xai then
        declare
          l_prev_base_url  varchar2(4000 char) := g_base_url;
          l_prev_override  varchar2(4000 char) := g_provider_override;
        begin
          g_base_url := 'https://api.x.ai/v1';
          g_provider_override := c_provider_xai;
          begin
            l_result := uc_ai_openai.generate_text(
              p_messages       => p_messages
            , p_model          => p_model
            , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
            , p_schema         => p_response_json_schema
            );
            g_base_url := l_prev_base_url;
            g_provider_override := l_prev_override;
          exception
            when others then
              g_base_url := l_prev_base_url;
              g_provider_override := l_prev_override;
              raise;
          end;
        end;
      when c_provider_openrouter then
        declare
          l_prev_base_url  varchar2(4000 char) := g_base_url;
          l_prev_override  varchar2(4000 char) := g_provider_override;
        begin
          g_base_url := 'https://openrouter.ai/api/v1';
          g_provider_override := c_provider_openrouter;
          begin
            l_result := uc_ai_openai.generate_text(
              p_messages       => p_messages
            , p_model          => p_model
            , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
            , p_schema         => p_response_json_schema
            );
            g_base_url := l_prev_base_url;
            g_provider_override := l_prev_override;
          exception
            when others then
              g_base_url := l_prev_base_url;
              g_provider_override := l_prev_override;
              raise;
          end;
        end;
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_provider
        , p_scope      => c_scope_prefix || 'generate_text'
        , p0           => p_provider
        );
    end case;

    fire_event(c_event_response_complete, l_result);
    g_request_id := null;

    return l_result;
  end generate_text;

  function generate_text (
    p_user_prompt           in clob
  , p_system_prompt         in clob default null
  , p_provider              in provider_type
  , p_model                 in model_type
  , p_max_tool_calls        in pls_integer default null
  , p_response_json_schema  in json_object_t default null
  ) return json_object_t
  as
    l_messages json_array_t;
  begin
    -- Build message array
    l_messages := json_array_t();
    
    -- Add system message if provided
    if p_system_prompt is not null then
      l_messages.append(uc_ai_message_api.create_system_message(p_system_prompt));
    end if;
    
    -- Add user message
    l_messages.append(uc_ai_message_api.create_simple_user_message(p_user_prompt));
    
    -- Call the main generate_text function with the message array
    return generate_text(
      p_messages              => l_messages
    , p_provider              => p_provider
    , p_model                 => p_model
    , p_max_tool_calls        => p_max_tool_calls
    , p_response_json_schema  => p_response_json_schema
    );
  end generate_text;

  function generate_embeddings (
    p_input in json_array_t
  , p_provider in provider_type
  , p_model in model_type
  ) return json_array_t
  as
    l_result json_array_t;
  begin
    case p_provider
      when c_provider_openai then
        l_result := uc_ai_openai.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
      when c_provider_google then
        l_result := uc_ai_google.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
      when c_provider_oci then
        l_result := uc_ai_oci.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
      when c_provider_ollama then
        l_result := uc_ai_ollama.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
      when c_provider_openrouter then
        declare
          l_prev_base_url  varchar2(4000 char) := g_base_url;
          l_prev_override  varchar2(4000 char) := g_provider_override;
        begin
          g_base_url := 'https://openrouter.ai/api/v1';
          g_provider_override := c_provider_openrouter;
          begin
            l_result := uc_ai_openai.generate_embeddings(
              p_input => p_input
            , p_model => p_model
            );
            g_base_url := l_prev_base_url;
            g_provider_override := l_prev_override;
          exception
            when others then
              g_base_url := l_prev_base_url;
              g_provider_override := l_prev_override;
              raise;
          end;
        end;
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_provider
        , p_scope      => c_scope_prefix || 'generate_embeddings'
        , p0           => p_provider
        );

    end case;

    return l_result;
  end generate_embeddings;

  procedure reset_globals
  as
  begin
    -- @dblinter ignore(g-2135)

    -- Reset uc_ai global variables
    g_base_url := null;
    g_enable_reasoning := false;
    g_reasoning_level := null;
    g_enable_tools := false;
    g_tool_tags := apex_t_varchar2();
    g_apex_web_credential := null;
    g_provider_override := null;
    g_max_tool_calls := null;
    g_request_id := null;
    g_callback_fatal := false;
    -- g_event_callback intentionally preserved (long-lived registration)

    -- Reset OpenAI global variables
    uc_ai_openai.g_reasoning_effort := 'low';
    uc_ai_openai.g_apex_web_credential := null;
    uc_ai_openai.g_use_responses_api := true;

    -- Reset shared Responses API global variables
    uc_ai_responses_api.g_store_responses := false;
    uc_ai_responses_api.g_include_encrypted_reasoning := false;
    uc_ai_responses_api.g_reasoning_summary := null;

    -- Reset Anthropic global variables
    uc_ai_anthropic.g_max_tokens := 8192;
    uc_ai_anthropic.g_reasoning_budget_tokens := null;
    uc_ai_anthropic.g_apex_web_credential := null;

    -- Reset Google global variables
    uc_ai_google.g_reasoning_budget := null;
    uc_ai_google.g_apex_web_credential := null;
    uc_ai_google.g_embedding_task_type := 'SEMANTIC_SIMILARITY';
    uc_ai_google.g_embedding_output_dimensions := 1536;

    -- Reset Ollama global variables
    uc_ai_ollama.g_apex_web_credential := null;
    uc_ai_ollama.g_use_responses_api := true;

    -- Reset OCI global variables
    uc_ai_oci.g_compartment_id := null;
    uc_ai_oci.g_serving_type := 'ON_DEMAND';
    uc_ai_oci.g_region := 'us-ashburn-1';
    uc_ai_oci.g_apex_web_credential := null;
    uc_ai_oci.g_use_responses_api := true;

    -- Reset xAI global variables
    uc_ai_xai.g_reasoning_effort := 'low';
    uc_ai_xai.g_apex_web_credential := null;

    -- Reset OpenRouter global variables
    uc_ai_openrouter.g_reasoning_effort := 'low';
    uc_ai_openrouter.g_apex_web_credential := null;
  end reset_globals;

  procedure set_event_callback(p_proc_name in varchar2)
  as
  begin
    if p_proc_name is null then
      g_event_callback := null;
    else
      -- validates SCHEMA.PACKAGE.PROCEDURE syntax; raises ORA-44003 on bad input
      g_event_callback := sys.dbms_assert.qualified_sql_name(p_proc_name);
    end if;
  end set_event_callback;

  procedure clear_event_callback
  as
  begin
    g_event_callback := null;
  end clear_event_callback;

  procedure fire_event(
    p_event_type in varchar2
  , p_event_data in json_object_t
  )
  as
    c_scope constant varchar2(60 char) := c_scope_prefix || 'fire_event';
    l_payload clob;
    l_stmt    varchar2(32767 char);
  begin
    if g_request_id is null or g_event_callback is null then
      return;
    end if;

    -- serialize to CLOB: json_object_t is a PL/SQL type and cannot be bound via execute immediate.
    -- The CLOB is also safe for the callback to persist or forward (no lifecycle concern).
    l_payload := p_event_data.to_clob();

    l_stmt := 'begin ' || g_event_callback || '(:1, :2, :3); end;';
    execute immediate l_stmt
      using in g_request_id, in p_event_type, in l_payload;
  exception
    when others then
      uc_ai_logger.log_error(
        p_text  => 'Event callback failed: ' || sqlerrm
      , p_scope => c_scope
      , p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
      if g_callback_fatal then
        raise;
      end if;
  end fire_event;

end uc_ai;
/
