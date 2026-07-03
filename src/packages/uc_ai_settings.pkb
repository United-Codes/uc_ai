create or replace package body uc_ai_settings
as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- Framework defaults, mirroring the values uc_ai.reset_globals restores.
  -- build_from_config starts from these and overlays whatever the config supplies,
  -- so a config that omits a key behaves exactly like a freshly reset global.
  function default_settings return t_settings
  as
    l_s t_settings;
  begin
    l_s.initialized                    := true;

    -- common
    l_s.base_url                       := null;
    l_s.provider_override              := null;
    l_s.apex_web_credential            := null;
    l_s.enable_tools                   := false;
    l_s.enable_reasoning               := false;
    l_s.reasoning_level                := null;
    l_s.tool_tags                      := apex_t_varchar2();
    l_s.max_tool_calls                 := null;
    l_s.extra_headers.delete();

    -- openai
    l_s.oa_use_responses_api           := true;
    l_s.oa_reasoning_effort            := 'low';
    l_s.oa_apex_web_credential         := null;

    -- anthropic
    l_s.an_max_tokens                  := 8192;
    l_s.an_reasoning_budget_tokens     := null;
    l_s.an_apex_web_credential         := null;

    -- google
    l_s.go_reasoning_budget            := null;
    l_s.go_apex_web_credential         := null;
    l_s.go_embedding_task_type         := 'SEMANTIC_SIMILARITY';
    l_s.go_embedding_output_dimensions := 1536;

    -- ollama
    l_s.ol_apex_web_credential         := null;
    l_s.ol_use_responses_api           := true;

    -- oci
    l_s.oc_compartment_id              := null;
    l_s.oc_serving_type                := 'ON_DEMAND';
    l_s.oc_region                      := 'us-ashburn-1';
    l_s.oc_apex_web_credential         := null;
    l_s.oc_use_responses_api           := true;

    -- xai
    l_s.xa_reasoning_effort            := 'low';
    l_s.xa_apex_web_credential         := null;

    -- openrouter
    l_s.or_reasoning_effort            := 'low';
    l_s.or_apex_web_credential         := null;

    -- mistral
    l_s.ms_apex_web_credential         := null;

    -- responses api
    l_s.ra_base_url                    := null;
    l_s.ra_apex_web_credential         := null;
    l_s.ra_reasoning_effort            := null;
    l_s.ra_reasoning_summary           := null;
    l_s.ra_text_verbosity              := 'medium';
    l_s.ra_store_responses             := false;
    l_s.ra_include_encrypted_reasoning := false;
    l_s.ra_skip_auth                   := false;

    return l_s;
  end default_settings;

  function build_from_globals return t_settings
  as
    l_s t_settings;
  begin
    l_s.initialized                    := true;

    -- common
    l_s.base_url                       := uc_ai.g_base_url;
    l_s.provider_override              := uc_ai.g_provider_override;
    l_s.apex_web_credential            := uc_ai.g_apex_web_credential;
    l_s.enable_tools                   := uc_ai.g_enable_tools;
    l_s.enable_reasoning               := uc_ai.g_enable_reasoning;
    l_s.reasoning_level                := uc_ai.g_reasoning_level;
    l_s.tool_tags                      := uc_ai.g_tool_tags;
    l_s.max_tool_calls                 := uc_ai.g_max_tool_calls;
    l_s.extra_headers                  := uc_ai.g_extra_headers;

    -- openai
    l_s.oa_use_responses_api           := uc_ai_openai.g_use_responses_api;
    l_s.oa_reasoning_effort            := uc_ai_openai.g_reasoning_effort;
    l_s.oa_apex_web_credential         := uc_ai_openai.g_apex_web_credential;

    -- anthropic
    l_s.an_max_tokens                  := uc_ai_anthropic.g_max_tokens;
    l_s.an_reasoning_budget_tokens     := uc_ai_anthropic.g_reasoning_budget_tokens;
    l_s.an_apex_web_credential         := uc_ai_anthropic.g_apex_web_credential;

    -- google
    l_s.go_reasoning_budget            := uc_ai_google.g_reasoning_budget;
    l_s.go_apex_web_credential         := uc_ai_google.g_apex_web_credential;
    l_s.go_embedding_task_type         := uc_ai_google.g_embedding_task_type;
    l_s.go_embedding_output_dimensions := uc_ai_google.g_embedding_output_dimensions;

    -- ollama
    l_s.ol_apex_web_credential         := uc_ai_ollama.g_apex_web_credential;
    l_s.ol_use_responses_api           := uc_ai_ollama.g_use_responses_api;

    -- oci
    l_s.oc_compartment_id              := uc_ai_oci.g_compartment_id;
    l_s.oc_serving_type                := uc_ai_oci.g_serving_type;
    l_s.oc_region                      := uc_ai_oci.g_region;
    l_s.oc_apex_web_credential         := uc_ai_oci.g_apex_web_credential;
    l_s.oc_use_responses_api           := uc_ai_oci.g_use_responses_api;

    -- xai
    l_s.xa_reasoning_effort            := uc_ai_xai.g_reasoning_effort;
    l_s.xa_apex_web_credential         := uc_ai_xai.g_apex_web_credential;

    -- openrouter
    l_s.or_reasoning_effort            := uc_ai_openrouter.g_reasoning_effort;
    l_s.or_apex_web_credential         := uc_ai_openrouter.g_apex_web_credential;

    -- mistral
    l_s.ms_apex_web_credential         := uc_ai_mistral.g_apex_web_credential;

    -- responses api
    l_s.ra_base_url                    := uc_ai_responses_api.g_base_url;
    l_s.ra_apex_web_credential         := uc_ai_responses_api.g_apex_web_credential;
    l_s.ra_reasoning_effort            := uc_ai_responses_api.g_reasoning_effort;
    l_s.ra_reasoning_summary           := uc_ai_responses_api.g_reasoning_summary;
    l_s.ra_text_verbosity              := uc_ai_responses_api.g_text_verbosity;
    l_s.ra_store_responses             := uc_ai_responses_api.g_store_responses;
    l_s.ra_include_encrypted_reasoning := uc_ai_responses_api.g_include_encrypted_reasoning;
    l_s.ra_skip_auth                   := uc_ai_responses_api.g_skip_auth;

    return l_s;
  end build_from_globals;

  function build_from_config(
    p_config   in json_object_t
  , p_provider in varchar2
  ) return t_settings
  as
    l_scope            uc_ai_logger.scope := c_scope_prefix || 'build_from_config';
    l_s                t_settings := default_settings;
    l_key_arr          json_key_list;
    l_key              varchar2(4000 char);
    l_value            json_element_t;
    l_provider_obj     json_object_t;
    l_provider_key_arr json_key_list;
  begin
    if p_config is null then
      return l_s;
    end if;

    -- Root-level keys (mirror uc_ai_prompt_profiles_api.apply_model_config, but
    -- written to the record instead of the globals).
    l_key_arr := p_config.get_keys;
    <<root_keys_loop>>
    for i in 1 .. l_key_arr.count loop
      l_key := l_key_arr(i);
      l_value := p_config.get(l_key);

      case l_key
        when 'g_base_url' then
          if l_value.is_string then
            l_s.base_url := p_config.get_string(l_key);
          end if;
        when 'g_enable_reasoning' then
          if l_value.is_boolean then
            l_s.enable_reasoning := p_config.get_boolean(l_key);
          end if;
        when 'g_reasoning_level' then
          if l_value.is_string then
            l_s.reasoning_level := p_config.get_string(l_key);
          end if;
        when 'g_enable_tools' then
          if l_value.is_boolean then
            l_s.enable_tools := p_config.get_boolean(l_key);
          end if;
        when 'g_max_tool_calls' then
          if l_value.is_number then
            l_s.max_tool_calls := p_config.get_number(l_key);
          end if;
        when 'g_apex_web_credential' then
          if l_value.is_string then
            l_s.apex_web_credential := p_config.get_string(l_key);
          end if;
        when 'g_tool_tags' then
          declare
            l_tags_array json_array_t;
            l_tags       apex_t_varchar2 := apex_t_varchar2();
          begin
            if l_value.is_string then
              l_tags.extend;
              l_tags(l_tags.count) := p_config.get_string(l_key);
            elsif l_value.is_array then
              l_tags_array := treat(p_config.get(l_key) as json_array_t);
              <<tags_array>>
              for j in 0 .. l_tags_array.get_size - 1 loop
                l_tags.extend;
                l_tags(l_tags.count) := l_tags_array.get_string(j);
              end loop tags_array;
            end if;
            l_s.tool_tags := l_tags;
          end;
        when 'g_extra_headers' then
          if l_value.is_object then
            declare
              l_hdr_obj  json_object_t := treat(p_config.get(l_key) as json_object_t);
              l_hdr_keys json_key_list := l_hdr_obj.get_keys;
              l_headers  uc_ai.t_extra_headers;
            begin
              <<extra_headers_keys>>
              for j in 1 .. l_hdr_keys.count loop
                l_headers(l_hdr_keys(j)) := l_hdr_obj.get_string(l_hdr_keys(j));
              end loop extra_headers_keys;
              l_s.extra_headers := l_headers;
            end;
          end if;
        when 'response_schema' then
          -- Not part of the settings record; pass the schema via
          -- p_response_json_schema on uc_ai.generate_text instead.
          null;
        else
          -- Allow provider-name keys with nested objects (processed below).
          if l_key in (
            uc_ai.c_provider_openai
          , uc_ai.c_provider_anthropic
          , uc_ai.c_provider_google
          , uc_ai.c_provider_ollama
          , uc_ai.c_provider_oci
          , uc_ai.c_provider_xai
          , uc_ai.c_provider_openrouter
          , uc_ai.c_provider_mistral
          ) and l_value.is_object then
            null;
          else
            uc_ai_error.raise_error(
              p_error_code => uc_ai_error.c_err_invalid_config
            , p_scope      => l_scope
            , p0           => 'model config key'
            , p1           => l_key
            , p_extra      => p_config.to_clob
            );
          end if;
      end case;
    end loop root_keys_loop;

    -- Provider-specific nested settings for the active provider.
    case p_provider
      when uc_ai.c_provider_openai then
        if p_config.has(uc_ai.c_provider_openai) and p_config.get(uc_ai.c_provider_openai).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_openai) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<openai_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_reasoning_effort' then
                l_s.oa_reasoning_effort := l_provider_obj.get_string(l_key);
              when 'g_apex_web_credential' then
                l_s.oa_apex_web_credential := l_provider_obj.get_string(l_key);
              when 'g_use_responses_api' then
                l_s.oa_use_responses_api := l_provider_obj.get_boolean(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'OpenAI provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop openai_keys_loop;
        end if;

      when uc_ai.c_provider_anthropic then
        if p_config.has(uc_ai.c_provider_anthropic) and p_config.get(uc_ai.c_provider_anthropic).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_anthropic) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<anthropic_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_max_tokens' then
                l_s.an_max_tokens := l_provider_obj.get_number(l_key);
              when 'g_reasoning_budget_tokens' then
                l_s.an_reasoning_budget_tokens := l_provider_obj.get_number(l_key);
              when 'g_apex_web_credential' then
                l_s.an_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'Anthropic provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop anthropic_keys_loop;
        end if;

      when uc_ai.c_provider_google then
        if p_config.has(uc_ai.c_provider_google) and p_config.get(uc_ai.c_provider_google).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_google) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<google_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_reasoning_budget' then
                l_s.go_reasoning_budget := l_provider_obj.get_number(l_key);
              when 'g_apex_web_credential' then
                l_s.go_apex_web_credential := l_provider_obj.get_string(l_key);
              when 'g_embedding_task_type' then
                l_s.go_embedding_task_type := l_provider_obj.get_string(l_key);
              when 'g_embedding_output_dimensions' then
                l_s.go_embedding_output_dimensions := l_provider_obj.get_number(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'Google provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop google_keys_loop;
        end if;

      when uc_ai.c_provider_ollama then
        if p_config.has(uc_ai.c_provider_ollama) and p_config.get(uc_ai.c_provider_ollama).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_ollama) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<ollama_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_apex_web_credential' then
                l_s.ol_apex_web_credential := l_provider_obj.get_string(l_key);
              when 'g_use_responses_api' then
                l_s.ol_use_responses_api := l_provider_obj.get_boolean(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'Ollama provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop ollama_keys_loop;
        end if;

      when uc_ai.c_provider_xai then
        if p_config.has(uc_ai.c_provider_xai) and p_config.get(uc_ai.c_provider_xai).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_xai) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<xai_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_reasoning_effort' then
                l_s.xa_reasoning_effort := l_provider_obj.get_string(l_key);
              when 'g_apex_web_credential' then
                l_s.xa_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'XAI provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop xai_keys_loop;
        end if;

      when uc_ai.c_provider_openrouter then
        if p_config.has(uc_ai.c_provider_openrouter) and p_config.get(uc_ai.c_provider_openrouter).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_openrouter) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<openrouter_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_reasoning_effort' then
                l_s.or_reasoning_effort := l_provider_obj.get_string(l_key);
              when 'g_apex_web_credential' then
                l_s.or_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'OpenRouter provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop openrouter_keys_loop;
        end if;

      when uc_ai.c_provider_mistral then
        if p_config.has(uc_ai.c_provider_mistral) and p_config.get(uc_ai.c_provider_mistral).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_mistral) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<mistral_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_apex_web_credential' then
                l_s.ms_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'Mistral provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop mistral_keys_loop;
        end if;

      when uc_ai.c_provider_oci then
        if p_config.has(uc_ai.c_provider_oci) and p_config.get(uc_ai.c_provider_oci).is_object then
          l_provider_obj := treat(p_config.get(uc_ai.c_provider_oci) as json_object_t);
          l_provider_key_arr := l_provider_obj.get_keys;
          <<oci_keys_loop>>
          for i in 1 .. l_provider_key_arr.count loop
            l_key := l_provider_key_arr(i);
            case l_key
              when 'g_apex_web_credential' then
                l_s.oc_apex_web_credential := l_provider_obj.get_string(l_key);
              when 'g_compartment_id' then
                l_s.oc_compartment_id := l_provider_obj.get_string(l_key);
              when 'g_serving_type' then
                l_s.oc_serving_type := l_provider_obj.get_string(l_key);
              when 'g_region' then
                l_s.oc_region := l_provider_obj.get_string(l_key);
              when 'g_use_responses_api' then
                l_s.oc_use_responses_api := l_provider_obj.get_boolean(l_key);
              else
                uc_ai_error.raise_error(
                  p_error_code => uc_ai_error.c_err_invalid_config
                , p_scope      => l_scope
                , p0           => 'OCI provider config key'
                , p1           => l_key
                , p_extra      => p_config.to_clob
                );
            end case;
          end loop oci_keys_loop;
        end if;

      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_provider
        , p_scope      => l_scope
        , p0           => p_provider
        , p_extra      => p_config.to_clob
        );
    end case;

    return l_s;
  end build_from_config;

  procedure apply_extra_headers(
    p_settings in t_settings
  )
  as
    l_name varchar2(255 char);
  begin
    l_name := p_settings.extra_headers.first;
    <<extra_headers_loop>>
    while l_name is not null loop
      apex_web_service.g_request_headers(apex_web_service.g_request_headers.count + 1).name := l_name;
      apex_web_service.g_request_headers(apex_web_service.g_request_headers.count).value := p_settings.extra_headers(l_name);
      l_name := p_settings.extra_headers.next(l_name);
    end loop extra_headers_loop;
  end apply_extra_headers;

  function new_run_state return t_run_state
  as
    l_r t_run_state;
  begin
    l_r.tool_calls       := 0;
    l_r.final_message    := null;
    l_r.input_tokens     := 0;
    l_r.output_tokens    := 0;
    l_r.reasoning_tokens := 0;
    l_r.total_tokens     := 0;
    return l_r;
  end new_run_state;

end uc_ai_settings;
/
