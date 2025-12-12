create or replace package body uc_ai_prompt_profiles_api as 

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  /*
   * Creates a new prompt profile
   */
  function create_prompt_profile(
    p_code                    in uc_ai_prompt_profiles.code%type,
    p_description             in uc_ai_prompt_profiles.description%type,
    p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
    p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
    p_provider                in uc_ai_prompt_profiles.provider%type,
    p_model                   in uc_ai_prompt_profiles.model%type,
    p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
    p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
    p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null,
    p_version                 in uc_ai_prompt_profiles.version%type default 1,
    p_status                  in uc_ai_prompt_profiles.status%type default c_status_draft
  ) return uc_ai_prompt_profiles.id%type
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'create_prompt_profile';
    l_id         uc_ai_prompt_profiles.id%type;
  begin

    insert into uc_ai_prompt_profiles (
      code,
      version,
      status,
      description,
      system_prompt_template,
      user_prompt_template,
      provider,
      model,
      model_config_json,
      response_schema,
      parameters_schema
    ) values (
      p_code,
      p_version,
      p_status,
      p_description,
      p_system_prompt_template,
      p_user_prompt_template,
      p_provider,
      p_model,
      p_model_config_json,
      p_response_schema,
      p_parameters_schema
    )
    returning id into l_id;
    
    return l_id;
  exception
    when others then
      uc_ai_logger.log_error('Error creating prompt profile', l_scope);
      raise;
  end create_prompt_profile;


  /*
   * Updates an existing prompt profile by ID
   */
  procedure update_prompt_profile(
    p_id                      in uc_ai_prompt_profiles.id%type,
    p_description             in uc_ai_prompt_profiles.description%type,
    p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
    p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
    p_provider                in uc_ai_prompt_profiles.provider%type,
    p_model                   in uc_ai_prompt_profiles.model%type,
    p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
    p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
    p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'update_prompt_profile';
  begin

    update uc_ai_prompt_profiles
    set description            = p_description,
        system_prompt_template = p_system_prompt_template,
        user_prompt_template   = p_user_prompt_template,
        provider               = p_provider,
        model                  = p_model,
        model_config_json      = p_model_config_json,
        response_schema        = p_response_schema,
        parameters_schema      = p_parameters_schema
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Prompt profile not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with ID: ' || p_id);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error updating prompt profile', l_scope);
      raise;
  end update_prompt_profile;


  /*
   * Updates an existing prompt profile by code and version
   */
  procedure update_prompt_profile(
    p_code                    in uc_ai_prompt_profiles.code%type,
    p_version                 in uc_ai_prompt_profiles.version%type,
    p_description             in uc_ai_prompt_profiles.description%type,
    p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
    p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
    p_provider                in uc_ai_prompt_profiles.provider%type,
    p_model                   in uc_ai_prompt_profiles.model%type,
    p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
    p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
    p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'update_prompt_profile';
  begin

    update uc_ai_prompt_profiles
    set description            = p_description,
        system_prompt_template = p_system_prompt_template,
        user_prompt_template   = p_user_prompt_template,
        provider               = p_provider,
        model                  = p_model,
        model_config_json      = p_model_config_json,
        response_schema        = p_response_schema,
        parameters_schema      = p_parameters_schema
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Prompt profile not found with code: ' || p_code || ', version: ' || p_version, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with code: ' || p_code || ', version: ' || p_version);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error updating prompt profile', l_scope);
      raise;
  end update_prompt_profile;


  /*
   * Deletes a prompt profile by ID
   */
  procedure delete_prompt_profile(
    p_id in uc_ai_prompt_profiles.id%type
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'delete_prompt_profile';
  begin

    delete from uc_ai_prompt_profiles
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Prompt profile not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with ID: ' || p_id);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error deleting prompt profile', l_scope);
      raise;
  end delete_prompt_profile;


  /*
   * Deletes a prompt profile by code and version
   */
  procedure delete_prompt_profile(
    p_code    in uc_ai_prompt_profiles.code%type,
    p_version in uc_ai_prompt_profiles.version%type
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'delete_prompt_profile';
  begin

    delete from uc_ai_prompt_profiles
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Prompt profile not found with code: ' || p_code || ', version: ' || p_version, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with code: ' || p_code || ', version: ' || p_version);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error deleting prompt profile', l_scope);
      raise;
  end delete_prompt_profile;


  /*
   * Changes the status of a prompt profile by ID
   */
  procedure change_status(
    p_id         in uc_ai_prompt_profiles.id%type,
    p_status     in uc_ai_prompt_profiles.status%type
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'change_status';
  begin

    -- Validate status value
    if p_status not in ('draft', 'active', 'archived') then
      uc_ai_logger.log_error('Invalid status value: ' || p_status, l_scope);
      raise_application_error(-20002, 'Invalid status. Must be: draft, active, or archived');
    end if;

    update uc_ai_prompt_profiles
    set status     = p_status
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Prompt profile not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with ID: ' || p_id);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error changing prompt profile status', l_scope);
      raise;
  end change_status;


  /*
   * Changes the status of a prompt profile by code and version
   */
  procedure change_status(
    p_code       in uc_ai_prompt_profiles.code%type,
    p_version    in uc_ai_prompt_profiles.version%type,
    p_status     in uc_ai_prompt_profiles.status%type
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'change_status';
  begin

    -- Validate status value
    if p_status not in (c_status_draft, c_status_active, c_status_archived) then
      uc_ai_logger.log_error('Invalid status value: ' || p_status, l_scope);
      raise_application_error(-20002, 'Invalid status. Must be: draft, active, or archived');
    end if;

    update uc_ai_prompt_profiles
    set status     = p_status
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Prompt profile not found with code: ' || p_code || ', version: ' || p_version, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with code: ' || p_code || ', version: ' || p_version);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error changing prompt profile status', l_scope);
      raise;
  end change_status;


  /*
   * Creates a new version of an existing prompt profile
   */
  function create_new_version(
    p_code           in uc_ai_prompt_profiles.code%type,
    p_source_version in uc_ai_prompt_profiles.version%type,
    p_new_version    in uc_ai_prompt_profiles.version%type default null
  ) return uc_ai_prompt_profiles.id%type
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'create_new_version';
    l_source_profile uc_ai_prompt_profiles%rowtype;
    l_new_id         uc_ai_prompt_profiles.id%type;
    l_version        uc_ai_prompt_profiles.version%type;
  begin

    -- Get source profile
    begin
      select *
      into l_source_profile
      from uc_ai_prompt_profiles
      where code = p_code
        and version = p_source_version;
    exception
      when no_data_found then
        uc_ai_logger.log_error('Source profile not found with code: ' || p_code || ', version: ' || p_source_version, l_scope);
        raise_application_error(-20001, 'Source profile not found with code: ' || p_code || ', version: ' || p_source_version);
    end;

    -- Determine new version number
    if p_new_version is null then
      select nvl(max(version), 0) + 1
      into l_version
      from uc_ai_prompt_profiles
      where code = p_code;
    else
      l_version := p_new_version;
    end if;

    -- Create new version
    insert into uc_ai_prompt_profiles (
      code,
      version,
      status,
      description,
      system_prompt_template,
      user_prompt_template,
      provider,
      model,
      model_config_json,
      response_schema,
      parameters_schema
    ) values (
      l_source_profile.code,
      l_version,
      c_status_draft, -- new versions start as draft
      l_source_profile.description,
      l_source_profile.system_prompt_template,
      l_source_profile.user_prompt_template,
      l_source_profile.provider,
      l_source_profile.model,
      l_source_profile.model_config_json,
      l_source_profile.response_schema,
      l_source_profile.parameters_schema
    )
    returning id into l_new_id;
    
    return l_new_id;
  exception
    when others then
      uc_ai_logger.log_error('Error creating new version of prompt profile', l_scope);
      raise;
  end create_new_version;


  /*
   * Gets a prompt profile by ID
   */
  function get_prompt_profile(
    p_id in uc_ai_prompt_profiles.id%type
  ) return uc_ai_prompt_profiles%rowtype
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'get_prompt_profile';
    l_profile uc_ai_prompt_profiles%rowtype;
  begin

    select *
    into l_profile
    from uc_ai_prompt_profiles
    where id = p_id;

    return l_profile;
  exception
    when no_data_found then
      uc_ai_logger.log_error('Prompt profile not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Prompt profile not found with ID: ' || p_id);
    when others then
      uc_ai_logger.log_error('Error getting prompt profile', l_scope);
      raise;
  end get_prompt_profile;


  /*
   * Gets a prompt profile by code and version
   */
  function get_prompt_profile(
    p_code    in uc_ai_prompt_profiles.code%type,
    p_version in uc_ai_prompt_profiles.version%type default null
  ) return uc_ai_prompt_profiles%rowtype
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'get_prompt_profile';
    l_profile uc_ai_prompt_profiles%rowtype;
  begin

    if p_version is null then
      -- Get latest active version
      select *
      into l_profile
      from uc_ai_prompt_profiles
      where code = p_code
        and status = 'active'
      order by version desc
      fetch first 1 row only;
    else
      select *
      into l_profile
      from uc_ai_prompt_profiles
      where code = p_code
        and version = p_version;
    end if;

    return l_profile;
  exception
    when no_data_found then
      if p_version is null then
        uc_ai_logger.log_error('No active prompt profile found with code: ' || p_code, l_scope);
        raise_application_error(-20001, 'No active prompt profile found with code: ' || p_code);
      else
        uc_ai_logger.log_error('Prompt profile not found with code: ' || p_code || ', version: ' || p_version, l_scope);
        raise_application_error(-20001, 'Prompt profile not found with code: ' || p_code || ', version: ' || p_version);
      end if;
    when others then
      uc_ai_logger.log_error('Error getting prompt profile', l_scope);
      raise;
  end get_prompt_profile;


  /*
   * Replaces placeholders (#placeholder#) in a template with values from parameters JSON
   * Case-insensitive replacement
   */
  function replace_placeholders(
    p_template   in clob,
    p_parameters in json_object_t
  ) return clob
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'replace_placeholders';
    l_result clob := p_template;
    l_key_arr   json_key_list;
    l_key    varchar2(4000 char);
    l_value  varchar2(32767 char);
  begin
    if p_parameters is null then
      return l_result;
    end if;

    l_key_arr := p_parameters.get_keys;
    
    <<parameter_keys>>
    for i in 1 .. l_key_arr.count loop
      l_key := l_key_arr(i);
      
      -- Get value as string
      if p_parameters.get(l_key).is_string then
        l_value := p_parameters.get_string(l_key);
      elsif p_parameters.get(l_key).is_number then
        l_value := to_char(p_parameters.get_number(l_key));
      elsif p_parameters.get(l_key).is_boolean then
        l_value := case when p_parameters.get_boolean(l_key) then 'true' else 'false' end;
      else
        l_value := p_parameters.get(l_key).to_string;
      end if;
      
      -- Replace placeholder (case-insensitive)
      l_result := regexp_replace(
        l_result,
        '#' || l_key || '#',
        l_value,
        1, 0, 'i'
      );
    end loop parameter_keys;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error replacing placeholders', l_scope);
      raise;
  end replace_placeholders;


  /*
   * Validates that all placeholders in templates have corresponding parameters
   */
  procedure validate_parameters(
    p_system_template in clob,
    p_user_template   in clob,
    p_parameters      in json_object_t
  )
  as
    l_scope             uc_ai_logger.scope := gc_scope_prefix || 'validate_parameters';
    l_combined_template clob;
    l_placeholder       varchar2(4000 char);
    l_placeholder_name  varchar2(4000 char);
    l_position          pls_integer := 1;
    l_key_arr           json_key_list;
    l_found             boolean;
  begin
    -- Combine both templates for checking
    l_combined_template := p_system_template || chr(10) || p_user_template;
    
    -- Find all placeholders in templates (only alphanumeric and underscore allowed)
    <<placeholder_loop>>
    loop
      l_placeholder := regexp_substr(l_combined_template, '#[A-Za-z0-9_]+#', l_position);
      exit placeholder_loop when l_placeholder is null;
      
      -- Extract placeholder name (without the # symbols)
      l_placeholder_name := substr(l_placeholder, 2, length(l_placeholder) - 2);
      
      -- Check if parameter exists (case-insensitive)
      l_found := false;
      if p_parameters is not null then
        l_key_arr := p_parameters.get_keys;
        <<check_keys>>
        for i in 1 .. l_key_arr.count loop
          if upper(l_key_arr(i)) = upper(l_placeholder_name) then
            l_found := true;
            exit check_keys;
          end if;
        end loop check_keys;
      end if;
      
      if not l_found then
        uc_ai_logger.log_error('Missing parameter for placeholder: ' || l_placeholder, l_scope);
        raise_application_error(-20003, 'Missing parameter for placeholder: ' || l_placeholder);
      end if;
      
      -- Move to next placeholder
      l_position := regexp_instr(l_combined_template, '#[A-Za-z0-9_]+#', l_position) + length(l_placeholder);
    end loop placeholder_loop;
  end validate_parameters;


  /*
   * Applies model configuration to global variables
   */
  procedure apply_model_config(
    p_config   in json_object_t,
    p_provider in uc_ai_prompt_profiles.provider%type
  )
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'apply_model_config';
    l_key_arr       json_key_list;
    l_key           varchar2(4000 char);
    l_value         json_element_t;
    l_provider_obj  json_object_t;
    l_provider_key_arr json_key_list;
  begin
    -- reset to defaults before applying new config
    uc_ai.reset_globals;


    if p_config is null then
      return;
    end if;

    l_key_arr := p_config.get_keys;
    
    <<root_keys_loop>>
    for i in 1 .. l_key_arr.count loop
      l_key := l_key_arr(i);
      l_value := p_config.get(l_key);
      
      case l_key
        when 'g_base_url' then
          if l_value.is_string then
            uc_ai.g_base_url := p_config.get_string(l_key);
          end if;
        when 'g_enable_reasoning' then
          if l_value.is_boolean then
            uc_ai.g_enable_reasoning := p_config.get_boolean(l_key);
          end if;
        when 'g_reasoning_level' then
          if l_value.is_string then
            uc_ai.g_reasoning_level := p_config.get_string(l_key);
          end if;
        when 'g_enable_tools' then
          if l_value.is_boolean then
            uc_ai.g_enable_tools := p_config.get_boolean(l_key);
          end if;
        when 'g_apex_web_credential' then
          if l_value.is_string then
            uc_ai.g_apex_web_credential := p_config.get_string(l_key);
          end if;
        when 'g_tool_tags' then
          declare
            l_tags_array json_array_t;
            l_tags apex_t_varchar2 := apex_t_varchar2();
          begin
            if l_value.is_string then
              -- Single string value
              l_tags.extend;
              l_tags(l_tags.count) := p_config.get_string(l_key);
            elsif l_value.is_array then
              -- Array of strings
              l_tags_array := treat(p_config.get(l_key) as json_array_t);
              <<tags_array>>
              for j in 0 .. l_tags_array.get_size - 1 loop
                l_tags.extend;
                l_tags(l_tags.count) := l_tags_array.get_string(j);
              end loop tags_array;
            end if;
            uc_ai.g_tool_tags := l_tags;
          end;
        else
          null; -- Ignore unknown keys at root level (might be provider-specific)
      end case;
    end loop root_keys_loop;
    
    -- Process provider-specific settings
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
                uc_ai_openai.g_reasoning_effort := l_provider_obj.get_string(l_key);
              when 'g_apex_web_credential' then
                uc_ai_openai.g_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_logger.log_warn('Unknown OpenAI provider config key: ' || l_key, l_scope);
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
                uc_ai_anthropic.g_max_tokens := l_provider_obj.get_number(l_key);
              when 'g_reasoning_budget_tokens' then
                uc_ai_anthropic.g_reasoning_budget_tokens := l_provider_obj.get_number(l_key);
              when 'g_apex_web_credential' then
                uc_ai_anthropic.g_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_logger.log_warn('Unknown Anthropic provider config key: ' || l_key, l_scope);
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
                uc_ai_google.g_reasoning_budget := l_provider_obj.get_number(l_key);
              when 'g_apex_web_credential' then
                uc_ai_google.g_apex_web_credential := l_provider_obj.get_string(l_key);
              when 'g_embedding_task_type' then
                uc_ai_google.g_embedding_task_type := l_provider_obj.get_string(l_key);
              when 'g_embedding_output_dimensions' then
                uc_ai_google.g_embedding_output_dimensions := l_provider_obj.get_number(l_key);
              else
                uc_ai_logger.log_warn('Unknown Google provider config key: ' || l_key, l_scope);
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
                uc_ai_ollama.g_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_logger.log_warn('Unknown Ollama provider config key: ' || l_key, l_scope);
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
                uc_ai_xai.g_reasoning_effort := l_provider_obj.get_string(l_key);
              when 'g_apex_web_credential' then
                uc_ai_xai.g_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_logger.log_warn('Unknown XAI provider config key: ' || l_key, l_scope);
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
                uc_ai_openrouter.g_reasoning_effort := l_provider_obj.get_string(l_key);
              when 'g_apex_web_credential' then
                uc_ai_openrouter.g_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_logger.log_warn('Unknown OpenRouter provider config key: ' || l_key, l_scope);
            end case;
          end loop openrouter_keys_loop;
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
                uc_ai_oci.g_apex_web_credential := l_provider_obj.get_string(l_key);
              else
                uc_ai_logger.log_warn('Unknown OCI provider config key: ' || l_key, l_scope);
            end case;
          end loop oci_keys_loop;
        end if;
        
      else
        uc_ai_logger.log_warn('Unknown provider in model config: ' || p_provider, l_scope);
    end case;
  exception
    when others then
      uc_ai_logger.log_error('Error applying model config', l_scope);
      raise;
  end apply_model_config;


  /*
   * Executes a prompt profile with parameter substitution (by code/version)
   */
  function execute_profile(
    p_code              in uc_ai_prompt_profiles.code%type,
    p_version           in uc_ai_prompt_profiles.version%type default null,
    p_parameters        in json_object_t default null,
    p_provider_override in uc_ai_prompt_profiles.provider%type default null,
    p_model_override    in uc_ai_prompt_profiles.model%type default null,
    p_config_override   in json_object_t default null,
    p_max_tool_calls    in pls_integer default null
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'execute_profile';
    l_profile        uc_ai_prompt_profiles%rowtype;
    l_system_prompt  clob;
    l_user_prompt    clob;
    l_provider       uc_ai_prompt_profiles.provider%type;
    l_model          uc_ai_prompt_profiles.model%type;
    l_config         json_object_t;
    l_response_schema json_object_t;
  begin
    -- Get profile
    l_profile := get_prompt_profile(p_code, p_version);
    
    -- Validate all placeholders have corresponding parameters
    validate_parameters(
      p_system_template => l_profile.system_prompt_template,
      p_user_template   => l_profile.user_prompt_template,
      p_parameters      => p_parameters
    );
    
    -- Replace placeholders in templates
    l_system_prompt := replace_placeholders(l_profile.system_prompt_template, p_parameters);
    l_user_prompt := replace_placeholders(l_profile.user_prompt_template, p_parameters);
    
    -- Determine final provider and model (overrides take precedence)
    l_provider := coalesce(p_provider_override, l_profile.provider);
    l_model := coalesce(p_model_override, l_profile.model);
    
    -- Determine final config (override takes precedence)
    if p_config_override is not null then
      l_config := p_config_override;
    elsif l_profile.model_config_json is not null then
      l_config := json_object_t.parse(l_profile.model_config_json);
    end if;
    
    -- Apply model configuration to global variables
    apply_model_config(l_config, l_provider);
    
    -- Parse response schema if provided
    if l_profile.response_schema is not null then
      l_response_schema := json_object_t.parse(l_profile.response_schema);
    end if;
    
    -- Call uc_ai.generate_text
    return uc_ai.generate_text(
      p_user_prompt          => l_user_prompt,
      p_system_prompt        => l_system_prompt,
      p_provider             => l_provider,
      p_model                => l_model,
      p_max_tool_calls       => p_max_tool_calls,
      p_response_json_schema => l_response_schema
    );
  exception
    when others then
      uc_ai_logger.log_error('Error executing prompt profile', l_scope);
      raise;
  end execute_profile;


  /*
   * Executes a prompt profile with parameter substitution (by ID)
   */
  function execute_profile(
    p_id                in uc_ai_prompt_profiles.id%type,
    p_parameters        in json_object_t default null,
    p_provider_override in uc_ai_prompt_profiles.provider%type default null,
    p_model_override    in uc_ai_prompt_profiles.model%type default null,
    p_config_override   in json_object_t default null,
    p_max_tool_calls    in pls_integer default null
  ) return json_object_t
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'execute_profile';
    l_profile uc_ai_prompt_profiles%rowtype;
  begin
    -- Get profile by ID
    l_profile := get_prompt_profile(p_id);
    
    -- Call the code/version version of execute_profile
    return execute_profile(
      p_code              => l_profile.code,
      p_version           => l_profile.version,
      p_parameters        => p_parameters,
      p_provider_override => p_provider_override,
      p_model_override    => p_model_override,
      p_config_override   => p_config_override,
      p_max_tool_calls    => p_max_tool_calls
    );
  exception
    when others then
      uc_ai_logger.log_error('Error executing prompt profile by ID', l_scope);
      raise;
  end execute_profile;

end uc_ai_prompt_profiles_api;
/
