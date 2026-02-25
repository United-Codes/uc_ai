create or replace package body uc_ai_agents_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  -- ============================================================================
  -- Private Types
  -- ============================================================================
  
  type t_agent_code_list is table of uc_ai_agents.code%type;


  -- ============================================================================
  -- Private Helper Functions
  -- ============================================================================

  /*
   * Extracts all agent_code references from a JSON object recursively
   */
  procedure extract_agent_codes(
    p_json       in json_element_t,
    pio_codes    in out nocopy t_agent_code_list
  )
  as
    l_scope    uc_ai_logger.scope := gc_scope_prefix || 'extract_agent_codes';
    l_obj      json_object_t;
    l_arr      json_array_t;
    l_keys     json_key_list;
    l_key      varchar2(4000 char);
    l_elem     json_element_t;
    l_code     uc_ai_agents.code%type;
  begin
    if p_json is null then
      return;
    end if;

    if p_json.is_object then
      l_obj := treat(p_json as json_object_t);
      l_keys := l_obj.get_keys;
      
      <<key_loop>>
      for i in 1 .. l_keys.count loop
        l_key := l_keys(i);
        
        -- Check for agent_code keys
        if l_key in ('agent_code', 'orchestrator_profile_code', 'moderator_agent_code', 
                     'initial_agent_code', 'summarizer_agent_code') then
          if l_obj.get(l_key).is_string then
            l_code := l_obj.get_string(l_key);
            pio_codes.extend;
            pio_codes(pio_codes.count) := l_code;
          end if;
        else
          -- Recurse into nested objects/arrays
          l_elem := l_obj.get(l_key);
          if l_elem is not null then
            extract_agent_codes(l_elem, pio_codes);
          end if;
        end if;
      end loop key_loop;
      
    elsif p_json.is_array then
      l_arr := treat(p_json as json_array_t);
      
      <<array_loop>>
      for i in 0 .. l_arr.get_size - 1 loop
        l_elem := l_arr.get(i);
        if l_elem is not null then
          extract_agent_codes(l_elem, pio_codes);
        end if;
      end loop array_loop;
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error extracting agent codes', l_scope);
      raise;
  end extract_agent_codes;


  /*
   * Checks if an agent with the given code exists
   */
  function agent_exists(
    p_agent_code in uc_ai_agents.code%type
  ) return boolean
  as
    l_count number;
  begin
    -- First check if it's a prompt profile (for orchestrator_profile_code)
    select count(*)
    into l_count
    from uc_ai_prompt_profiles
    where code = p_agent_code
      and status = 'active';
    
    if l_count > 0 then
      return true;
    end if;
    
    -- Then check agents
    select count(*)
    into l_count
    from uc_ai_agents
    where code = p_agent_code
      and status = c_status_active;
    
    return l_count > 0;
  end agent_exists;


  /*
   * Creates an execution record and returns its ID
   */
  function create_execution(
    p_agent_id         in uc_ai_agents.id%type,
    p_session_id       in varchar2,
    p_parent_exec_id   in uc_ai_agent_executions.id%type,
    p_input_parameters in json_object_t
  ) return uc_ai_agent_executions.id%type
  as
    l_exec_id uc_ai_agent_executions.id%type;
    l_params clob;
  begin
    l_params := p_input_parameters.to_clob;

    insert into uc_ai_agent_executions (
      agent_id,
      parent_execution_id,
      session_id,
      input_parameters,
      status
    ) values (
      p_agent_id,
      p_parent_exec_id,
      p_session_id,
      l_params,
      c_exec_running
    )
    returning id into l_exec_id;
    
    return l_exec_id;
  end create_execution;


  /*
   * Updates execution with completion status and results
   */
  procedure complete_execution(
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_status            in varchar2,
    p_output_result     in json_object_t default null,
    p_error_message     in varchar2 default null,
    p_iteration_count   in number default 0,
    p_tool_calls_count  in number default 0,
    p_input_tokens      in number default 0,
    p_output_tokens     in number default 0
  )
  as
    l_output_result clob;
  begin
    l_output_result := case when p_output_result is not null then p_output_result.to_clob else null end;  

    update uc_ai_agent_executions
    set status              = p_status,
        output_result       = l_output_result,
        error_message       = p_error_message,
        completed_at        = systimestamp,
        iteration_count     = p_iteration_count,
        tool_calls_count    = p_tool_calls_count,
        total_input_tokens  = p_input_tokens,
        total_output_tokens = p_output_tokens
    where id = p_exec_id;
  end complete_execution;


  -- ============================================================================
  -- Public API Implementation
  -- ============================================================================

  /*
   * Generates a new session ID
   */
  function generate_session_id return varchar2
  as
  begin
    return sys_guid();
  end generate_session_id;


  /*
   * Creates a new agent
   */
  function create_agent(
    p_code                   in uc_ai_agents.code%type,
    p_description            in uc_ai_agents.description%type,
    p_agent_type             in uc_ai_agents.agent_type%type,
    p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
    p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
    p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
    p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
    p_input_schema           in uc_ai_agents.input_schema%type default null,
    p_output_schema          in uc_ai_agents.output_schema%type default null,
    p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
    p_max_iterations         in uc_ai_agents.max_iterations%type default null,
    p_max_history_messages   in uc_ai_agents.max_history_messages%type default null,
    p_version                in uc_ai_agents.version%type default 1,
    p_status                 in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'create_agent';
    l_id    uc_ai_agents.id%type;
  begin
    -- Validate agent type requirements
    case p_agent_type
      when c_type_profile then
        if p_prompt_profile_code is null then
          uc_ai_logger.log_error('Profile agent requires prompt_profile_code', l_scope);
          raise_application_error(-20001, 'Profile agent requires prompt_profile_code');
        end if;
        
      when c_type_workflow then
        if p_workflow_definition is null then
          uc_ai_logger.log_error('Workflow agent requires workflow_definition', l_scope);
          raise_application_error(-20001, 'Workflow agent requires workflow_definition');
        end if;
        declare
          l_validation t_validation_result;
        begin
          l_validation := validate_workflow_definition(p_workflow_definition);
          if not l_validation.is_valid then
            raise_application_error(-20001, 'Invalid workflow definition: ' || l_validation.error_reason);
          end if;
        end;
        
      when c_type_orchestrator then
        if p_orchestration_config is null then
          uc_ai_logger.log_error('Orchestrator agent requires orchestration_config', l_scope);
          raise_application_error(-20001, 'Orchestrator agent requires orchestration_config');
        end if;
        
      when c_type_handoff then
        if p_orchestration_config is null then
          uc_ai_logger.log_error('Handoff agent requires orchestration_config', l_scope);
          raise_application_error(-20001, 'Handoff agent requires orchestration_config');
        end if;
        
      when c_type_conversation then
        if p_orchestration_config is null then
          uc_ai_logger.log_error('Conversation agent requires orchestration_config', l_scope);
          raise_application_error(-20001, 'Conversation agent requires orchestration_config');
        end if;
        
      else
        uc_ai_logger.log_error('Invalid agent_type: ' || p_agent_type, l_scope);
        raise_application_error(-20001, 'Invalid agent_type: ' || p_agent_type);
    end case;
    
    -- Validate agent references in configs
    declare
      l_validation t_validation_result;
    begin
      l_validation := validate_agent_references(p_workflow_definition, p_orchestration_config);
      if not l_validation.is_valid then
        raise_application_error(-20001, 'Invalid agent references in configuration: ' || l_validation.error_reason);
      end if;
    end;
    
    insert into uc_ai_agents (
      code,
      version,
      status,
      description,
      agent_type,
      prompt_profile_code,
      prompt_profile_version,
      workflow_definition,
      orchestration_config,
      input_schema,
      output_schema,
      timeout_seconds,
      max_iterations,
      max_history_messages
    ) values (
      p_code,
      p_version,
      p_status,
      p_description,
      p_agent_type,
      p_prompt_profile_code,
      p_prompt_profile_version,
      p_workflow_definition,
      p_orchestration_config,
      p_input_schema,
      p_output_schema,
      p_timeout_seconds,
      p_max_iterations,
      p_max_history_messages
    )
    returning id into l_id;
    
    return l_id;
  exception
    when others then
      uc_ai_logger.log_error('Error creating agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end create_agent;


  /*
   * Updates an existing agent by ID
   */
  procedure update_agent(
    p_id                     in uc_ai_agents.id%type,
    p_description            in uc_ai_agents.description%type default null,
    p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
    p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
    p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
    p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
    p_input_schema           in uc_ai_agents.input_schema%type default null,
    p_output_schema          in uc_ai_agents.output_schema%type default null,
    p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
    p_max_iterations         in uc_ai_agents.max_iterations%type default null,
    p_max_history_messages   in uc_ai_agents.max_history_messages%type default null
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'update_agent';
  begin
    -- Validate agent references if configs are being updated
    if p_workflow_definition is not null or p_orchestration_config is not null then
      declare
        l_validation t_validation_result;
      begin
        l_validation := validate_agent_references(p_workflow_definition, p_orchestration_config);
        if not l_validation.is_valid then
          raise_application_error(-20001, 'Invalid agent references in configuration: ' || l_validation.error_reason);
        end if;
      end;
    end if;

    update uc_ai_agents
    set description            = coalesce(p_description, description),
        prompt_profile_code    = coalesce(p_prompt_profile_code, prompt_profile_code),
        prompt_profile_version = coalesce(p_prompt_profile_version, prompt_profile_version),
        workflow_definition    = coalesce(p_workflow_definition, workflow_definition),
        orchestration_config   = coalesce(p_orchestration_config, orchestration_config),
        input_schema           = coalesce(p_input_schema, input_schema),
        output_schema          = coalesce(p_output_schema, output_schema),
        timeout_seconds        = coalesce(p_timeout_seconds, timeout_seconds),
        max_iterations         = coalesce(p_max_iterations, max_iterations),
        max_history_messages   = coalesce(p_max_history_messages, max_history_messages)
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Agent not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Agent not found with ID: ' || p_id);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error updating agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end update_agent;


  /*
   * Deletes an agent by ID
   */
  procedure delete_agent(
    p_id in uc_ai_agents.id%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'delete_agent';
    l_code  uc_ai_agents.code%type;
  begin
    -- Get the code first
    select code into l_code
    from uc_ai_agents
    where id = p_id;
    
    -- Check if referenced
    check_agent_not_referenced(l_code);
    
    delete from uc_ai_agents
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Agent not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Agent not found with ID: ' || p_id);
    end if;
  exception
    when no_data_found then
      uc_ai_logger.log_error('Agent not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Agent not found with ID: ' || p_id);
    when others then
      uc_ai_logger.log_error('Error deleting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end delete_agent;


  /*
   * Deletes an agent by code and version
   */
  procedure delete_agent(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'delete_agent';
  begin
    -- Check if referenced
    check_agent_not_referenced(p_code);
    
    delete from uc_ai_agents
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Agent not found with code: ' || p_code || ', version: ' || p_version, l_scope);
      raise_application_error(-20001, 'Agent not found with code: ' || p_code || ', version: ' || p_version);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error deleting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end delete_agent;


  /*
   * Changes the status of an agent by ID
   */
  procedure change_status(
    p_id     in uc_ai_agents.id%type,
    p_status in uc_ai_agents.status%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'change_status';
  begin
    if p_status not in (c_status_draft, c_status_active, c_status_archived) then
      uc_ai_logger.log_error('Invalid status value: ' || p_status, l_scope);
      raise_application_error(-20002, 'Invalid status. Must be: draft, active, or archived');
    end if;

    update uc_ai_agents
    set status = p_status
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Agent not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Agent not found with ID: ' || p_id);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error changing agent status', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end change_status;


  /*
   * Changes the status of an agent by code and version
   */
  procedure change_status(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type,
    p_status  in uc_ai_agents.status%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'change_status';
  begin
    if p_status not in (c_status_draft, c_status_active, c_status_archived) then
      uc_ai_logger.log_error('Invalid status value: ' || p_status, l_scope);
      raise_application_error(-20002, 'Invalid status. Must be: draft, active, or archived');
    end if;

    update uc_ai_agents
    set status = p_status
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_logger.log_error('Agent not found with code: ' || p_code || ', version: ' || p_version, l_scope);
      raise_application_error(-20001, 'Agent not found with code: ' || p_code || ', version: ' || p_version);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error changing agent status', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end change_status;


  /*
   * Creates a new version of an existing agent
   */
  function create_new_version(
    p_code           in uc_ai_agents.code%type,
    p_source_version in uc_ai_agents.version%type,
    p_new_version    in uc_ai_agents.version%type default null
  ) return uc_ai_agents.id%type
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'create_new_version';
    l_source_agent uc_ai_agents%rowtype;
    l_new_id       uc_ai_agents.id%type;
    l_version      uc_ai_agents.version%type;
  begin
    -- Get source agent
    begin
      select *
      into l_source_agent
      from uc_ai_agents
      where code = p_code
        and version = p_source_version;
    exception
      when no_data_found then
        uc_ai_logger.log_error('Source agent not found with code: ' || p_code || ', version: ' || p_source_version, l_scope);
        raise_application_error(-20001, 'Source agent not found with code: ' || p_code || ', version: ' || p_source_version);
    end;

    -- Determine new version number
    if p_new_version is null then
      select nvl(max(version), 0) + 1
      into l_version
      from uc_ai_agents
      where code = p_code;
    else
      l_version := p_new_version;
    end if;

    -- Create new version
    insert into uc_ai_agents (
      code,
      version,
      status,
      description,
      agent_type,
      prompt_profile_code,
      prompt_profile_version,
      workflow_definition,
      orchestration_config,
      input_schema,
      output_schema,
      timeout_seconds,
      max_iterations,
      max_history_messages
    ) values (
      l_source_agent.code,
      l_version,
      c_status_draft,
      l_source_agent.description,
      l_source_agent.agent_type,
      l_source_agent.prompt_profile_code,
      l_source_agent.prompt_profile_version,
      l_source_agent.workflow_definition,
      l_source_agent.orchestration_config,
      l_source_agent.input_schema,
      l_source_agent.output_schema,
      l_source_agent.timeout_seconds,
      l_source_agent.max_iterations,
      l_source_agent.max_history_messages
    )
    returning id into l_new_id;
    
    return l_new_id;
  exception
    when others then
      uc_ai_logger.log_error('Error creating new version of agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end create_new_version;


  /*
   * Gets an agent by ID
   */
  function get_agent(
    p_id in uc_ai_agents.id%type
  ) return uc_ai_agents%rowtype
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_agent';
    l_agent uc_ai_agents%rowtype;
  begin
    select *
    into l_agent
    from uc_ai_agents
    where id = p_id;

    return l_agent;
  exception
    when no_data_found then
      uc_ai_logger.log_error('Agent not found with ID: ' || p_id, l_scope);
      raise_application_error(-20001, 'Agent not found with ID: ' || p_id);
    when others then
      uc_ai_logger.log_error('Error getting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end get_agent;


  /*
   * Gets an agent by code and version
   */
  function get_agent(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type default null
  ) return uc_ai_agents%rowtype
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_agent';
    l_agent uc_ai_agents%rowtype;
  begin
    if p_version is null then
      -- Get latest active version
      select *
      into l_agent
      from uc_ai_agents
      where code = p_code
        and status = c_status_active
      order by version desc
      fetch first 1 row only;
    else
      select *
      into l_agent
      from uc_ai_agents
      where code = p_code
        and version = p_version;
    end if;

    return l_agent;
  exception
    when no_data_found then
      if p_version is null then
        uc_ai_logger.log_error('No active agent found with code: ' || p_code, l_scope);
        raise_application_error(-20001, 'No active agent found with code: ' || p_code);
      else
        uc_ai_logger.log_error('Agent not found with code: ' || p_code || ', version: ' || p_version, l_scope);
        raise_application_error(-20001, 'Agent not found with code: ' || p_code || ', version: ' || p_version);
      end if;
    when others then
      uc_ai_logger.log_error('Error getting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end get_agent;


  /*
   * Validates that all agent_code references exist
   */
  function validate_agent_references(
    p_workflow_definition  in clob default null,
    p_orchestration_config in clob default null
  ) return t_validation_result
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'validate_agent_references';
    l_result    t_validation_result;
    l_codes_arr t_agent_code_list := t_agent_code_list();
    l_json      json_element_t;
  begin
    l_result.is_valid := true;
    l_result.error_reason := null;
    
    -- Extract codes from workflow definition
    if p_workflow_definition is not null then
      l_json := json_element_t.parse(p_workflow_definition);
      extract_agent_codes(l_json, l_codes_arr);
    end if;
    
    -- Extract codes from orchestration config
    if p_orchestration_config is not null then
      begin
        l_json := json_element_t.parse(p_orchestration_config);
      exception
        when others then
          l_result.is_valid := false;
          l_result.error_reason := 'Invalid JSON in orchestration_config: ' || sqlerrm;
          uc_ai_logger.log_error('Invalid JSON in orchestration_config.', l_scope, 'json:' || p_orchestration_config || ' | ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
          return l_result;
      end;
      extract_agent_codes(l_json, l_codes_arr);
    end if;
    
    -- Validate each code exists
    <<code_loop>>
    for i in 1 .. l_codes_arr.count loop
      if not agent_exists(l_codes_arr(i)) then
        l_result.is_valid := false;
        l_result.error_reason := 'Referenced agent or profile does not exist: ' || l_codes_arr(i);
        uc_ai_logger.log_error(l_result.error_reason, l_scope);
        return l_result;
      end if;
    end loop code_loop;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error validating agent references', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end validate_agent_references;


  /*
   * Checks if an agent is referenced by other agents
   */
  procedure check_agent_not_referenced(
    p_agent_code in uc_ai_agents.code%type
  )
  as
    l_scope       uc_ai_logger.scope := gc_scope_prefix || 'check_agent_not_referenced';
    l_ref_count   number;
    l_search_expr varchar2(4000 char);
  begin
    -- Build search expression
    l_search_expr := '"agent_code"[[:space:]]*:[[:space:]]*"' || p_agent_code || '"';
    
    -- Search in workflow definitions and orchestration configs
    select count(*)
    into l_ref_count
    from uc_ai_agents
    where (workflow_definition is not null and regexp_like(workflow_definition, l_search_expr))
       or (orchestration_config is not null and regexp_like(orchestration_config, l_search_expr));
    
    if l_ref_count > 0 then
      uc_ai_logger.log_error('Agent is referenced by ' || l_ref_count || ' other agent(s): ' || p_agent_code, l_scope);
      raise_application_error(-20003, 'Cannot delete agent "' || p_agent_code || '": it is referenced by ' || l_ref_count || ' other agent(s)');
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error checking agent references', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end check_agent_not_referenced;


  /*
   * Validates a workflow definition JSON
   */
  function validate_workflow_definition(
    p_workflow_definition in clob
  ) return t_validation_result
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'validate_workflow_definition';
    l_result        t_validation_result;
    l_json          json_object_t;
    l_workflow_type varchar2(50 char);
    l_steps         json_array_t;
  begin
    l_result.is_valid := true;
    l_result.error_reason := null;
    
    if p_workflow_definition is null then
      l_result.is_valid := false;
      l_result.error_reason := 'workflow_definition is null';
      return l_result;
    end if;
    
    l_json := json_object_t.parse(p_workflow_definition);
    
    -- Check required fields
    if not l_json.has('workflow_type') then
      l_result.is_valid := false;
      l_result.error_reason := 'Missing required field: workflow_type';
      uc_ai_logger.log_error('workflow_definition ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    l_workflow_type := l_json.get_string('workflow_type');
    if l_workflow_type not in (
      uc_ai_agent_exec_api.c_workflow_sequential, 
      uc_ai_agent_exec_api.c_workflow_conditional, 
      uc_ai_agent_exec_api.c_workflow_parallel, 
      uc_ai_agent_exec_api.c_workflow_loop
    ) then
      l_result.is_valid := false;
      l_result.error_reason := 'Invalid workflow_type: ' || l_workflow_type || '. Must be one of: sequential, conditional, parallel, loop';
      uc_ai_logger.log_error(l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    if not l_json.has('steps') then
      l_result.is_valid := false;
      l_result.error_reason := 'Missing required field: steps';
      uc_ai_logger.log_error('workflow_definition ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    l_steps := l_json.get_array('steps');
    if l_steps.get_size = 0 then
      l_result.is_valid := false;
      l_result.error_reason := 'steps array is empty';
      uc_ai_logger.log_error('workflow_definition ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    -- Validate each step has agent_code
    <<step_loop>>
    for i in 0 .. l_steps.get_size - 1 loop
      declare
        l_step json_object_t := treat(l_steps.get(i) as json_object_t);
      begin
        if not l_step.has('agent_code') then
          l_result.is_valid := false;
          l_result.error_reason := 'Step ' || i || ' missing required field: agent_code';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
      end;
    end loop step_loop;
    
    return l_result;
  exception
    when others then
      l_result.is_valid := false;
      l_result.error_reason := 'Error parsing workflow definition: ' || sqlerrm;
      uc_ai_logger.log_error('Error validating workflow definition: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end validate_workflow_definition;


  /*
   * Validates an orchestration config JSON
   */
  function validate_orchestration_config(
    p_orchestration_config in clob
  ) return t_validation_result
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'validate_orchestration_config';
    l_result       t_validation_result;
    l_json         json_object_t;
    l_pattern_type varchar2(50 char);
  begin
    l_result.is_valid := true;
    l_result.error_reason := null;
    
    if p_orchestration_config is null then
      l_result.is_valid := false;
      l_result.error_reason := 'orchestration_config is null';
      return l_result;
    end if;
    
    l_json := json_object_t.parse(p_orchestration_config);
    
    -- Check required fields based on pattern type
    if not l_json.has('pattern_type') then
      l_result.is_valid := false;
      l_result.error_reason := 'Missing required field: pattern_type';
      uc_ai_logger.log_error('orchestration_config ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    l_pattern_type := l_json.get_string('pattern_type');
    
    case l_pattern_type
      when 'orchestrator' then
        if not l_json.has('orchestrator_profile_code') then
          l_result.is_valid := false;
          l_result.error_reason := 'Orchestrator config missing required field: orchestrator_profile_code';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        if not l_json.has('delegate_agents') then
          l_result.is_valid := false;
          l_result.error_reason := 'Orchestrator config missing required field: delegate_agents';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        
      when 'handoff' then
        if not l_json.has('initial_agent_code') then
          l_result.is_valid := false;
          l_result.error_reason := 'Handoff config missing required field: initial_agent_code';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        
      when 'conversation' then
        if not l_json.has('conversation_mode') then
          l_result.is_valid := false;
          l_result.error_reason := 'Conversation config missing required field: conversation_mode';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        if not l_json.has('participant_agents') then
          l_result.is_valid := false;
          l_result.error_reason := 'Conversation config missing required field: participant_agents';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        
      else
        l_result.is_valid := false;
        l_result.error_reason := 'Invalid pattern_type: ' || l_pattern_type || '. Must be one of: orchestrator, handoff, conversation';
        uc_ai_logger.log_error(l_result.error_reason, l_scope);
        return l_result;
    end case;
    
    return l_result;
  exception
    when others then
      l_result.is_valid := false;
      l_result.error_reason := 'Error parsing orchestration config: ' || sqlerrm;
      uc_ai_logger.log_error('Error validating orchestration config: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      return l_result;
  end validate_orchestration_config;


  /*
   * Creates a sequential workflow agent
   */
  function create_sequential_workflow(
    p_code        in uc_ai_agents.code%type,
    p_description in uc_ai_agents.description%type,
    p_agent_steps in json_array_t,
    p_status      in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'create_sequential_workflow';
    l_workflow_def   json_object_t := json_object_t();
    l_steps          json_array_t := json_array_t();
    l_step           json_object_t;
    l_agent_code     varchar2(255 char);
  begin
    -- Build workflow definition
    l_workflow_def.put('workflow_type', uc_ai_agent_exec_api.c_workflow_sequential);
    
    -- Convert simple array of agent codes to step objects
    <<step_loop>>
    for i in 0 .. p_agent_steps.get_size - 1 loop
      l_agent_code := p_agent_steps.get_string(i);
      l_step := json_object_t();
      l_step.put('step_id', 'step_' || (i + 1));
      l_step.put('agent_code', l_agent_code);
      l_steps.append(l_step);
    end loop step_loop;
    
    l_workflow_def.put('steps', l_steps);
    
    return create_agent(
      p_code                => p_code,
      p_description         => p_description,
      p_agent_type          => c_type_workflow,
      p_workflow_definition => l_workflow_def.to_clob,
      p_status              => p_status
    );
  exception
    when others then
      uc_ai_logger.log_error('Error creating sequential workflow', l_scope);
      raise;
  end create_sequential_workflow;


  /*
   * Creates a parallel workflow agent
   */
  function create_parallel_workflow(
    p_code                 in uc_ai_agents.code%type,
    p_description          in uc_ai_agents.description%type,
    p_agent_steps          in json_array_t,
    p_aggregation_strategy in varchar2 default 'merge',
    p_status               in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type
  as
    l_scope           uc_ai_logger.scope := gc_scope_prefix || 'create_parallel_workflow';
    l_workflow_def    json_object_t := json_object_t();
    l_parallel_config json_object_t := json_object_t();
    l_steps           json_array_t := json_array_t();
    l_step            json_object_t;
    l_agent_code      varchar2(255 char);
  begin
    -- Build workflow definition
    l_workflow_def.put('workflow_type', uc_ai_agent_exec_api.c_workflow_parallel);
    
    -- Convert simple array of agent codes to step objects
    <<step_loop>>
    for i in 0 .. p_agent_steps.get_size - 1 loop
      l_agent_code := p_agent_steps.get_string(i);
      l_step := json_object_t();
      l_step.put('step_id', 'step_' || (i + 1));
      l_step.put('agent_code', l_agent_code);
      l_step.put('parallel_group', 1);  -- All in same parallel group
      l_steps.append(l_step);
    end loop step_loop;
    
    l_workflow_def.put('steps', l_steps);
    
    -- Add parallel config
    l_parallel_config.put('execution_mode', 'wait_all');
    l_parallel_config.put('aggregation_strategy', p_aggregation_strategy);
    l_workflow_def.put('parallel_config', l_parallel_config);
    
    return create_agent(
      p_code                => p_code,
      p_description         => p_description,
      p_agent_type          => c_type_workflow,
      p_workflow_definition => l_workflow_def.to_clob,
      p_status              => p_status
    );
  exception
    when others then
      uc_ai_logger.log_error('Error creating parallel workflow', l_scope);
      raise;
  end create_parallel_workflow;


  /*
   * Executes an agent by code
   */
  function execute_agent(
    p_agent_code       in uc_ai_agents.code%type,
    p_agent_version    in uc_ai_agents.version%type default null,
    p_input_parameters in json_object_t default null,
    p_session_id       in varchar2 default null,
    p_parent_exec_id   in uc_ai_agent_executions.id%type default null,
    p_response_schema  in json_object_t default null
  ) return json_object_t
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'execute_agent';
    l_agent      uc_ai_agents%rowtype;
    l_exec_id    uc_ai_agent_executions.id%type;
    l_session_id varchar2(255 char);
    l_result     json_object_t;
  begin
    uc_ai_logger.log('Executing agent: ' || p_agent_code, l_scope);

    uc_ai_agent_exec_api.create_apex_session_if_needed;
    
    -- Get agent
    l_agent := get_agent(p_agent_code, p_agent_version);
    
    -- Validate response_schema usage
    if p_response_schema is not null and l_agent.agent_type != c_type_profile then
      uc_ai_logger.log_error('response_schema can only be used with profile agents, not: ' || l_agent.agent_type, l_scope);
      raise_application_error(-20011, 'response_schema can only be used with profile agents');
    end if;
    
    -- Generate session ID if not provided
    l_session_id := coalesce(p_session_id, generate_session_id());
    
    -- Create execution record
    l_exec_id := create_execution(l_agent.id, l_session_id, p_parent_exec_id, p_input_parameters);
    

    begin
      -- Execute based on agent type (delegating to sub-package)
      case l_agent.agent_type
        when c_type_profile then
          l_result := uc_ai_agent_exec_api.execute_profile_agent(l_agent, p_input_parameters, l_exec_id, p_response_schema);
          
        when c_type_workflow then
          l_result := uc_ai_agent_exec_api.execute_workflow_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        when c_type_orchestrator then
          l_result := uc_ai_agent_exec_api.execute_orchestrator_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        when c_type_handoff then
          l_result := uc_ai_agent_exec_api.execute_handoff_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        when c_type_conversation then
          l_result := uc_ai_agent_exec_api.execute_conversation_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        else
          uc_ai_logger.log_error('Unknown agent type: ' || l_agent.agent_type, l_scope);
          raise_application_error(-20010, 'Unknown agent type: ' || l_agent.agent_type);
      end case;

      l_result.put('execution_id', l_exec_id);
      l_result.put('agent_code', p_agent_code);
      l_result.put('agent_version', l_agent.version);
      l_result.put('session_id', l_session_id);
      l_result.put('status', c_exec_completed);

      uc_ai_logger.log('Agent execution completed: ' || p_agent_code, l_scope, l_result.to_clob);
      
      -- Update execution as completed
      complete_execution(
        p_exec_id       => l_exec_id,
        p_status        => c_exec_completed,
        p_output_result => l_result
      );
      
    exception
      when others then
        -- Update execution as failed
        complete_execution(
          p_exec_id       => l_exec_id,
          p_status        => c_exec_failed,
          p_error_message => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
        raise;
    end;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error executing agent: ' || p_agent_code, l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_agent;


  /*
   * Executes an agent by ID
   */
  function execute_agent(
    p_agent_id         in uc_ai_agents.id%type,
    p_input_parameters in json_object_t default null,
    p_session_id       in varchar2 default null,
    p_parent_exec_id   in uc_ai_agent_executions.id%type default null,
    p_response_schema  in json_object_t default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'execute_agent';
    l_agent uc_ai_agents%rowtype;
  begin
    l_agent := get_agent(p_agent_id);
    
    return execute_agent(
      p_agent_code       => l_agent.code,
      p_agent_version    => l_agent.version,
      p_input_parameters => p_input_parameters,
      p_session_id       => p_session_id,
      p_parent_exec_id   => p_parent_exec_id,
      p_response_schema  => p_response_schema
    );
  exception
    when others then
      uc_ai_logger.log_error('Error executing agent by ID', l_scope);
      raise;
  end execute_agent;


  /*
   * Gets the execution history with optional filters
   */
  function get_execution_history(
    p_session_id in varchar2 default null,
    p_agent_code in uc_ai_agents.code%type default null,
    p_status     in varchar2 default null,
    p_start_date in timestamp default null,
    p_end_date   in timestamp default null
  ) return sys_refcursor
  as
    l_scope            uc_ai_logger.scope := gc_scope_prefix || 'get_execution_history';
    l_exec_history_cur sys_refcursor;
  begin
    open l_exec_history_cur for
      select e.id,
             e.agent_id,
             a.code as agent_code,
             a.version as agent_version,
             a.agent_type,
             e.parent_execution_id,
             e.session_id,
             e.status,
             e.iteration_count,
             e.tool_calls_count,
             e.total_input_tokens,
             e.total_output_tokens,
             e.started_at,
             e.completed_at,
             e.error_message
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
      where (p_session_id is null or e.session_id = p_session_id)
        and (p_agent_code is null or a.code = p_agent_code)
        and (p_status is null or e.status = p_status)
        and (p_start_date is null or e.started_at >= p_start_date)
        and (p_end_date is null or e.started_at <= p_end_date)
      order by e.started_at desc;
    
    return l_exec_history_cur;
  exception
    when others then
      uc_ai_logger.log_error('Error getting execution history', l_scope);
      raise;
  end get_execution_history;


  /*
   * Gets detailed information about a specific execution
   */
  function get_execution_details(
    p_execution_id in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'get_execution_details';
    l_result json_object_t := json_object_t();
    l_exec   uc_ai_agent_executions%rowtype;
    l_agent  uc_ai_agents%rowtype;
  begin
    select *
    into l_exec
    from uc_ai_agent_executions
    where id = p_execution_id;
    
    select *
    into l_agent
    from uc_ai_agents
    where id = l_exec.agent_id;
    
    l_result.put('execution_id', l_exec.id);
    l_result.put('agent_id', l_exec.agent_id);
    l_result.put('agent_code', l_agent.code);
    l_result.put('agent_version', l_agent.version);
    l_result.put('agent_type', l_agent.agent_type);
    l_result.put('parent_execution_id', l_exec.parent_execution_id);
    l_result.put('session_id', l_exec.session_id);
    l_result.put('status', l_exec.status);
    l_result.put('iteration_count', l_exec.iteration_count);
    l_result.put('tool_calls_count', l_exec.tool_calls_count);
    l_result.put('total_input_tokens', l_exec.total_input_tokens);
    l_result.put('total_output_tokens', l_exec.total_output_tokens);
    l_result.put('started_at', to_char(l_exec.started_at, 'YYYY-MM-DD"T"HH24:MI:SS'));
    l_result.put('completed_at', to_char(l_exec.completed_at, 'YYYY-MM-DD"T"HH24:MI:SS'));
    l_result.put('error_message', l_exec.error_message);
    
    if l_exec.input_parameters is not null then
      l_result.put('input_parameters', json_object_t.parse(l_exec.input_parameters));
    end if;
    
    if l_exec.output_result is not null then
      l_result.put('output_result', json_object_t.parse(l_exec.output_result));
    end if;
    
    return l_result;
  exception
    when no_data_found then
      uc_ai_logger.log_error('Execution not found with ID: ' || p_execution_id, l_scope);
      raise_application_error(-20001, 'Execution not found with ID: ' || p_execution_id);
    when others then
      uc_ai_logger.log_error('Error getting execution details', l_scope);
      raise;
  end get_execution_details;

end uc_ai_agents_api;
/
