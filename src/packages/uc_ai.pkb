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
        g_base_url := 'https://api.x.ai/v1';
        g_provider_override := c_provider_xai;

        l_result := uc_ai_openai.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      when c_provider_openrouter then
        g_base_url := 'https://openrouter.ai/api/v1';
        g_provider_override := c_provider_openrouter;

        l_result := uc_ai_openai.generate_text(
          p_messages       => p_messages
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, g_max_tool_calls, c_default_max_tool_calls)
        , p_schema         => p_response_json_schema
        );
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_provider
        , p_scope      => c_scope_prefix || 'generate_text'
        , p0           => p_provider
        );
    end case;


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
        g_base_url := 'https://openrouter.ai/api/v1';
        g_provider_override := c_provider_openrouter;

        l_result := uc_ai_openai.generate_embeddings(
          p_input => p_input
        , p_model => p_model
        );
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

    -- Reset OpenAI global variables
    uc_ai_openai.g_reasoning_effort := 'low';
    uc_ai_openai.g_apex_web_credential := null;

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

    -- Reset OCI global variables
    uc_ai_oci.g_compartment_id := null;
    uc_ai_oci.g_serving_type := 'ON_DEMAND';
    uc_ai_oci.g_region := 'us-ashburn-1';
    uc_ai_oci.g_apex_web_credential := null;

    -- Reset xAI global variables
    uc_ai_xai.g_reasoning_effort := 'low';
    uc_ai_xai.g_apex_web_credential := null;

    -- Reset OpenRouter global variables
    uc_ai_openrouter.g_reasoning_effort := 'low';
    uc_ai_openrouter.g_apex_web_credential := null;
  end reset_globals;

end uc_ai;
/
