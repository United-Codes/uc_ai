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
    e_unknown_provider exception;
    
    l_result json_object_t;
  begin
    case p_provider
      when c_provider_openai then
        l_result := uc_ai_openai.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        , p_schema_name    => 'structured_output'
        , p_strict         => true
        );
      when c_provider_anthropic then
        if p_response_json_schema is not null then
          raise_application_error(-20001, 'Provider ' || p_provider || ' does not support structured output');
        else
          l_result := uc_ai_anthropic.generate_text(
            p_messages       => p_messages
          , p_model          => p_model
          , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
          );
        end if;
      when c_provider_google then
        l_result := uc_ai_google.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_ollama then
        l_result := uc_ai_ollama.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_oci then
        if p_response_json_schema is not null then
          raise_application_error(-20001, 'Provider ' || p_provider || ' does not support structured output');
        else
          l_result := uc_ai_oci.generate_text(
            p_messages       => p_messages
          , p_model          => p_model
          , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
          );
        end if;
      -- when c_provider_xai then
      --   g_base_url := 'https://api.x.ai/v1';
      --   g_provider_override := c_provider_xai;

      --   l_result := uc_ai_openai.generate_text(
      --     p_messages       => p_messages
      --   , p_model          => p_model
      --   , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
      --   , p_schema         => p_response_json_schema
      --   , p_schema_name    => 'structured_output'
      --   , p_strict         => true
      --   );
      else
        raise e_unknown_provider;
    end case;
   
  
    return l_result;
  exception
    when e_unknown_provider then
      raise_application_error(-20001, 'Unknown AI provider: ' || p_provider);
    when e_max_calls_exceeded then
      raise_application_error(-20301, 'Maximum tool calls exceeded');
    when e_error_response then
      raise_application_error(-20302, 'Error response from AI provider. Check logs for details');
    when e_unhandled_format then
      raise_application_error(-20303, 'Unhandled message format encountered. Please check the message structure and logs.');
    when e_format_processing_error then
      raise_application_error(-20304, 'Error processing message format. Please check the logs for details.');
    when others then
      uc_ai_logger.log_error(
        'Unhandled exception in uc_ai.generate_text',
        c_scope_prefix || 'generate_text',
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );

      raise;

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
    e_unknown_provider exception;
    
    l_result json_array_t;
  begin
    case p_provider
      when c_provider_openai then
        l_result := uc_ai_openai.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
      when c_provider_ollama then
        l_result := uc_ai_ollama.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
      else
        raise e_unknown_provider;
      
    end case;

    return l_result;
  exception
    when e_unknown_provider then
      raise_application_error(-20001, 'Unknown AI provider: ' || p_provider);
    when others then
      uc_ai_logger.log_error(
        'Unhandled exception in uc_ai.generate_embeddings',
        c_scope_prefix || 'generate_embeddings',
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );

      raise;
  end generate_embeddings;

end uc_ai;
/
