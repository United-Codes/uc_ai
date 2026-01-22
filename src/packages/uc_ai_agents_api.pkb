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
  begin
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
      case when p_input_parameters is not null then p_input_parameters.to_clob else null end,
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
    p_output_tokens     in number default 0,
    p_cost_usd          in number default 0
  )
  as
  begin
    update uc_ai_agent_executions
    set status              = p_status,
        output_result       = case when p_output_result is not null then p_output_result.to_clob else null end,
        error_message       = p_error_message,
        completed_at        = systimestamp,
        iteration_count     = p_iteration_count,
        tool_calls_count    = p_tool_calls_count,
        total_input_tokens  = p_input_tokens,
        total_output_tokens = p_output_tokens,
        total_cost_usd      = p_cost_usd
    where id = p_exec_id;
  end complete_execution;


  /*
   * Evaluates a condition expression
   */
  function evaluate_condition(
    p_condition      in json_object_t,
    p_workflow_state in json_object_t
  ) return boolean
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'evaluate_condition';
    l_type       varchar2(50 char);
    l_expression varchar2(4000 char);
    l_dyn_sql    varchar2(32676 char);
  begin
    if p_condition is null then
      return true;  -- No condition means always execute
    end if;

    l_type := p_condition.get_string('type');
    l_expression := p_condition.get_string('expression');

    case l_type
      when 'json_path' then
        declare
          l_result number;
        begin
          l_dyn_sql := 'select case when json_exists(:1, :2) then 1 else 0 end from dual';
          execute immediate l_dyn_sql
            into l_result
            using p_workflow_state.to_clob, l_expression;
          return l_result = 1;
        end;
      when 'plsql' then
        return apex_plugin_util.get_plsql_expr_result_boolean(
          p_plsql_expression => l_expression,
          p_auto_bind_items  => false
        );
      else
         uc_ai_logger.log_error('Unknown condition type: ' || l_type, l_scope);
        raise_application_error(-20010, 'Unknown condition type: ' || l_type);
    end case;
  exception
    when others then
      uc_ai_logger.log_error('Error evaluating condition: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end evaluate_condition;


  /*
   * Maps input parameters based on input_mapping configuration
   */
  function map_inputs(
    p_input_mapping  in json_object_t,
    p_workflow_state in json_object_t,
    p_original_input in json_object_t
  ) return json_object_t
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'map_inputs';
    l_result     json_object_t := json_object_t();
    l_keys       json_key_list;
    l_key        varchar2(4000 char);
    l_mapping    varchar2(4000 char);
    l_path       varchar2(4000 char);
  begin
    if p_input_mapping is null then
      -- No mapping, pass through original input
      return p_original_input;
    end if;

    l_keys := p_input_mapping.get_keys;
    
    <<mapping_loop>>
    for i in 1 .. l_keys.count loop
      l_key := l_keys(i);
      l_mapping := p_input_mapping.get_string(l_key);
      
      -- Parse mapping expression: ${source.path}
      if l_mapping like '${%}' then
        l_mapping := substr(l_mapping, 3, length(l_mapping) - 3);
        
        -- Determine source (input, workflow, step_output)
        if l_mapping like 'input.%' then
          l_path := substr(l_mapping, 7);
          if p_original_input is not null and p_original_input.has(l_path) then
            l_result.put(l_key, p_original_input.get(l_path));
          end if;
        elsif l_mapping like 'workflow.%' then
          l_path := substr(l_mapping, 10);
          if p_workflow_state is not null and p_workflow_state.has(l_path) then
            l_result.put(l_key, p_workflow_state.get(l_path));
          end if;
        else
          -- Direct reference
          if p_workflow_state is not null and p_workflow_state.has(l_mapping) then
            l_result.put(l_key, p_workflow_state.get(l_mapping));
          elsif p_original_input is not null and p_original_input.has(l_mapping) then
            l_result.put(l_key, p_original_input.get(l_mapping));
          end if;
        end if;
      else
        -- Literal value
        l_result.put(l_key, l_mapping);
      end if;
    end loop mapping_loop;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error mapping inputs', l_scope);
      raise;
  end map_inputs;


  /*
   * Merges step output into workflow state based on output_mapping
   */
  procedure merge_outputs(
    p_output_mapping in json_object_t,
    p_step_output    in json_object_t,
    pio_workflow_state in out nocopy json_object_t
  )
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'merge_outputs';
    l_keys    json_key_list;
    l_key     varchar2(4000 char);
    l_mapping varchar2(4000 char);
    l_path    varchar2(4000 char);
  begin
    if p_output_mapping is null then
      -- No mapping, merge entire output
      if p_step_output is not null then
        l_keys := p_step_output.get_keys;
        <<merge_all_loop>>
        for i in 1 .. l_keys.count loop
          pio_workflow_state.put(l_keys(i), p_step_output.get(l_keys(i)));
        end loop merge_all_loop;
      end if;
      return;
    end if;

    l_keys := p_output_mapping.get_keys;
    
    <<mapping_loop>>
    for i in 1 .. l_keys.count loop
      l_key := l_keys(i);
      l_mapping := p_output_mapping.get_string(l_key);
      
      -- Target is the key, source is the mapping
      if l_mapping like '${step_output%}' then
        l_path := substr(l_mapping, 14, length(l_mapping) - 14);
        if l_path is null then
          -- ${step_output} - entire output
          pio_workflow_state.put(l_key, p_step_output);
        elsif p_step_output is not null and p_step_output.has(l_path) then
          pio_workflow_state.put(l_key, p_step_output.get(l_path));
        end if;
      end if;
    end loop mapping_loop;
  exception
    when others then
      uc_ai_logger.log_error('Error merging outputs', l_scope);
      raise;
  end merge_outputs;


  /*
   * Manages conversation history based on strategy
   */
  function manage_history(
    p_history            in json_array_t,
    p_history_management in json_object_t,
    p_session_id         in varchar2
  ) return json_array_t
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'manage_history';
    l_strategy       varchar2(50 char);
    l_max_messages   number;
    l_result         json_array_t;
    l_summarizer     varchar2(255 char);
    l_summary_result json_object_t;
    l_summary_input  json_object_t;
  begin
    if p_history_management is null then
      return p_history;
    end if;

    l_strategy := p_history_management.get_string('strategy');
    
    case l_strategy
      when c_history_full then
        return p_history;
        
      when c_history_sliding_window then
        l_max_messages := p_history_management.get_number('max_messages');
        if l_max_messages is null then
          l_max_messages := 20;
        end if;
        
        if p_history.get_size <= l_max_messages then
          return p_history;
        end if;
        
        -- Keep only last N messages
        l_result := json_array_t();
        <<window_loop>>
        for i in (p_history.get_size - l_max_messages) .. (p_history.get_size - 1) loop
          l_result.append(p_history.get(i));
        end loop window_loop;
        
        return l_result;
        
      when c_history_summarize then
        l_max_messages := p_history_management.get_number('summarize_after');
        if l_max_messages is null then
          l_max_messages := 10;
        end if;
        
        if p_history.get_size <= l_max_messages then
          return p_history;
        end if;
        
        l_summarizer := p_history_management.get_string('summarizer_agent_code');
        if l_summarizer is null then
          -- Fall back to sliding window if no summarizer
          uc_ai_logger.log_warn('No summarizer_agent_code specified, falling back to sliding_window', l_scope);
          l_result := json_array_t();
          <<fallback_window_loop>>
          for i in (p_history.get_size - l_max_messages) .. (p_history.get_size - 1) loop
            l_result.append(p_history.get(i));
          end loop fallback_window_loop;
          return l_result;
        end if;
        
        -- Call summarizer agent
        l_summary_input := json_object_t();
        l_summary_input.put('conversation_history', p_history);
        l_summary_input.put('summarize_count', p_history.get_size - l_max_messages);
        
        l_summary_result := execute_agent(
          p_agent_code       => l_summarizer,
          p_input_parameters => l_summary_input,
          p_session_id       => p_session_id
        );
        
        -- Build result with summary + recent messages
        l_result := json_array_t();
        l_result.append(json_object_t(
          json_object(
            'role' value 'system',
            'content' value 'Previous conversation summary: ' || 
                           l_summary_result.get_string('final_message')
          )
        ));
        
        <<recent_loop>>
        for i in (p_history.get_size - l_max_messages) .. (p_history.get_size - 1) loop
          l_result.append(p_history.get(i));
        end loop recent_loop;
        
        return l_result;
        
      else
        return p_history;
    end case;
  exception
    when others then
      uc_ai_logger.log_error('Error managing history', l_scope);
      raise;
  end manage_history;


  -- ============================================================================
  -- Pattern Execution Functions
  -- ============================================================================

  /*
   * Executes a profile-type agent (wrapper around prompt profile)
   */
  function execute_profile_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'execute_profile_agent';
    l_result json_object_t;
  begin
    uc_ai_logger.log('Executing profile agent: ' || p_agent.code, l_scope);
    
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code       => p_agent.prompt_profile_code,
      p_version    => p_agent.prompt_profile_version,
      p_parameters => p_input_params
    );
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error executing profile agent', l_scope);
      raise;
  end execute_profile_agent;


  /*
   * Executes a sequential workflow
   */
  function execute_sequential_workflow(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'execute_sequential_workflow';
    l_workflow_def   json_object_t;
    l_steps          json_array_t;
    l_step           json_object_t;
    l_step_agent     varchar2(255 char);
    l_step_input     json_object_t;
    l_step_output    json_object_t;
    l_workflow_state json_object_t := json_object_t();
    l_input_mapping  json_object_t;
    l_output_mapping json_object_t;
    l_condition      json_object_t;
    l_iteration      number := 0;
  begin
    uc_ai_logger.log('Executing sequential workflow: ' || p_agent.code, l_scope);
    
    l_workflow_def := json_object_t.parse(p_agent.workflow_definition);
    l_steps := l_workflow_def.get_array('steps');
    
    -- Execute steps in order
    <<step_loop>>
    for i in 0 .. l_steps.get_size - 1 loop
      l_step := treat(l_steps.get(i) as json_object_t);
      l_step_agent := l_step.get_string('agent_code');
      
      -- Check condition if present
      if l_step.has('condition') then
        l_condition := treat(l_step.get('condition') as json_object_t);
        if not evaluate_condition(l_condition, l_workflow_state) then
          uc_ai_logger.log('Skipping step due to condition: ' || l_step_agent, l_scope);
          continue;
        end if;
      end if;
      
      -- Map inputs
      if l_step.has('input_mapping') then
        l_input_mapping := treat(l_step.get('input_mapping') as json_object_t);
      else
        l_input_mapping := null;
      end if;
      l_step_input := map_inputs(l_input_mapping, l_workflow_state, p_input_params);
      
      -- Execute step agent
      uc_ai_logger.log('Executing step: ' || l_step_agent, l_scope);
      l_step_output := execute_agent(
        p_agent_code       => l_step_agent,
        p_input_parameters => l_step_input,
        p_session_id       => p_session_id,
        p_parent_exec_id   => p_exec_id
      );
      
      -- Merge outputs
      if l_step.has('output_mapping') then
        l_output_mapping := treat(l_step.get('output_mapping') as json_object_t);
      else
        l_output_mapping := null;
      end if;
      merge_outputs(l_output_mapping, l_step_output, l_workflow_state);
      
      l_iteration := l_iteration + 1;
    end loop step_loop;
    
    -- Add workflow metadata
    l_workflow_state.put('_workflow_iterations', l_iteration);
    
    return l_workflow_state;
  exception
    when others then
      uc_ai_logger.log_error('Error executing sequential workflow', l_scope);
      raise;
  end execute_sequential_workflow;


  /*
   * Executes a loop workflow
   */
  function execute_loop_workflow(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'execute_loop_workflow';
    l_workflow_def   json_object_t;
    l_loop_config    json_object_t;
    l_steps          json_array_t;
    l_max_iterations number;
    l_exit_condition json_object_t;
    l_iteration      number := 0;
    l_workflow_state json_object_t;
    l_step           json_object_t;
    l_step_agent     varchar2(255 char);
    l_step_output    json_object_t;
  begin
    uc_ai_logger.log('Executing loop workflow: ' || p_agent.code, l_scope);
    
    l_workflow_def := json_object_t.parse(p_agent.workflow_definition);
    l_steps := l_workflow_def.get_array('steps');
    
    -- Get loop configuration
    l_loop_config := l_workflow_def.get_object('loop_config');
    l_max_iterations := coalesce(
      l_loop_config.get_number('max_iterations'),
      p_agent.max_iterations,
      10
    );
    
    if l_loop_config.has('exit_condition') then
      l_exit_condition := l_loop_config.get_object('exit_condition');
    end if;
    
    -- Initialize state with input
    l_workflow_state := p_input_params;
    if l_workflow_state is null then
      l_workflow_state := json_object_t();
    end if;
    
    -- Loop until exit condition or max iterations
    <<iteration_loop>>
    while l_iteration < l_max_iterations loop
      -- Execute all steps
      <<step_loop>>
      for i in 0 .. l_steps.get_size - 1 loop
        l_step := treat(l_steps.get(i) as json_object_t);
        l_step_agent := l_step.get_string('agent_code');
        
        l_step_output := execute_agent(
          p_agent_code       => l_step_agent,
          p_input_parameters => l_workflow_state,
          p_session_id       => p_session_id,
          p_parent_exec_id   => p_exec_id
        );
        
        -- Merge output into state (feedback loop)
        merge_outputs(null, l_step_output, l_workflow_state);
      end loop step_loop;
      
      l_iteration := l_iteration + 1;
      
      -- Check exit condition
      if l_exit_condition is not null then
        if evaluate_condition(l_exit_condition, l_workflow_state) then
          uc_ai_logger.log('Exit condition met at iteration: ' || l_iteration, l_scope);
          exit iteration_loop;
        end if;
      end if;
    end loop iteration_loop;
    
    l_workflow_state.put('_loop_iterations', l_iteration);
    
    return l_workflow_state;
  exception
    when others then
      uc_ai_logger.log_error('Error executing loop workflow', l_scope);
      raise;
  end execute_loop_workflow;


  /*
   * Executes a workflow-type agent
   */
  function execute_workflow_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'execute_workflow_agent';
    l_workflow_def json_object_t;
    l_workflow_type varchar2(50 char);
  begin
    uc_ai_logger.log('Executing workflow agent: ' || p_agent.code, l_scope);
    
    l_workflow_def := json_object_t.parse(p_agent.workflow_definition);
    l_workflow_type := l_workflow_def.get_string('workflow_type');
    
    case l_workflow_type
      when c_workflow_sequential then
        return execute_sequential_workflow(p_agent, p_input_params, p_session_id, p_exec_id);
        
      when c_workflow_loop then
        return execute_loop_workflow(p_agent, p_input_params, p_session_id, p_exec_id);
        
      when c_workflow_conditional then
        -- Conditional uses same logic as sequential but relies on step conditions
        return execute_sequential_workflow(p_agent, p_input_params, p_session_id, p_exec_id);
        
      when c_workflow_parallel then
        -- For now, parallel executes sequentially (DBMS_PARALLEL_EXECUTE requires more setup)
        -- TODO: Implement true parallel execution
        uc_ai_logger.log_warn('Parallel workflow executing sequentially (parallel not yet implemented)', l_scope);
        return execute_sequential_workflow(p_agent, p_input_params, p_session_id, p_exec_id);
        
      else
        uc_ai_logger.log_error('Unknown workflow type: ' || l_workflow_type, l_scope);
        raise_application_error(-20011, 'Unknown workflow type: ' || l_workflow_type);
    end case;
  exception
    when others then
      uc_ai_logger.log_error('Error executing workflow agent', l_scope);
      raise;
  end execute_workflow_agent;


  /*
   * Registers a child agent as a temporary tool for orchestration
   */
  function register_agent_as_tool(
    p_agent_code       in varchar2,
    p_tool_name        in varchar2,
    p_tool_description in varchar2,
    p_exec_id          in uc_ai_agent_executions.id%type
  ) return uc_ai_tools.id%type
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'register_agent_as_tool';
    l_tool_id       uc_ai_tools.id%type;
    l_function_call clob;
    l_json_schema   json_object_t;
    l_params_obj    json_object_t;
    l_agent         uc_ai_agents%rowtype;
  begin
    uc_ai_logger.log('Registering agent as tool: ' || p_agent_code || ' -> ' || p_tool_name, l_scope);
    
    -- Get the agent to check for input schema
    begin
      l_agent := get_agent(p_agent_code);
    --exception
    --  when others then
    --    -- Agent might be a prompt profile
    --    null;
    end;
    
    -- Create function call that executes the agent
    l_function_call := '
declare
  l_input json_object_t := json_object_t();
  l_result json_object_t;
  l_args json_object_t := json_object_t(:arguments);
  l_keys json_key_list;
begin
  -- Pass all arguments to agent
  l_keys := l_args.get_keys;
  for i in 1 .. l_keys.count loop
    l_input.put(l_keys(i), l_args.get(l_keys(i)));
  end loop;
  
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => ''' || p_agent_code || ''',
    p_input_parameters => l_input
  );
  
  :result := l_result.get_string(''final_message'');
exception
  when others then
    :result := ''Error executing agent: '' || sqlerrm;
end;';

    -- Create JSON schema for tool parameters
    l_json_schema := json_object_t();
    l_json_schema.put('type', 'object');
    
    l_params_obj := json_object_t();
    l_params_obj.put('type', 'object');
    l_params_obj.put('description', 'Input parameters for the agent');
    
    -- If agent has input schema, use it
    if l_agent.input_schema is not null then
      l_params_obj := json_object_t.parse(l_agent.input_schema);
    end if;
    
    l_json_schema.put('properties', json_object_t('{"parameters": ' || l_params_obj.to_clob || '}'));
    
    -- Create the tool
    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code    => p_tool_name,
      p_description  => p_tool_description,
      p_function_call => l_function_call,
      p_json_schema  => l_json_schema,
      p_active       => 1
    );
    
    -- Track temporary tool for cleanup
    insert into uc_ai_temp_tools (execution_id, tool_id)
    values (p_exec_id, l_tool_id);
    
    return l_tool_id;
  exception
    when others then
      uc_ai_logger.log_error('Error registering agent as tool', l_scope);
      raise;
  end register_agent_as_tool;


  /*
   * Cleans up temporary tools created for an execution
   */
  procedure cleanup_agent_tools(
    p_exec_id in uc_ai_agent_executions.id%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'cleanup_agent_tools';
  begin
    uc_ai_logger.log('Cleaning up temporary tools for execution: ' || p_exec_id, l_scope);
    
    -- Delete tools (cascade will handle parameters and tags)
    delete from uc_ai_tools
    where id in (
      select t.tool_id
      from uc_ai_temp_tools t
      where execution_id = p_exec_id
    );
    
    -- Temp tools records will be deleted by cascade
  exception
    when others then
      uc_ai_logger.log_error('Error cleaning up agent tools', l_scope);
      -- Don't re-raise, cleanup errors shouldn't fail the main operation
  end cleanup_agent_tools;


  /*
   * Executes an orchestrator-type agent
   */
  function execute_orchestrator_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope            uc_ai_logger.scope := gc_scope_prefix || 'execute_orchestrator_agent';
    l_config           json_object_t;
    l_delegates        json_array_t;
    l_delegate         json_object_t;
    l_tool_ids         apex_t_number := apex_t_number();
    l_tool_id          uc_ai_tools.id%type;
    l_result           json_object_t;
    l_profile_code     varchar2(255 char);
    l_original_tools   boolean;
    l_original_tags    apex_t_varchar2;
  begin
    uc_ai_logger.log('Executing orchestrator agent: ' || p_agent.code, l_scope);
    
    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_delegates := l_config.get_array('delegate_agents');
    l_profile_code := l_config.get_string('orchestrator_profile_code');
    
    -- Save original tool settings
    l_original_tools := uc_ai.g_enable_tools;
    l_original_tags := uc_ai.g_tool_tags;
    
    begin
      -- Register delegate agents as tools
      <<delegate_loop>>
      for i in 0 .. l_delegates.get_size - 1 loop
        l_delegate := treat(l_delegates.get(i) as json_object_t);
        
        l_tool_id := register_agent_as_tool(
          p_agent_code       => l_delegate.get_string('agent_code'),
          p_tool_name        => l_delegate.get_string('tool_name'),
          p_tool_description => l_delegate.get_string('tool_description'),
          p_exec_id          => p_exec_id
        );
        
        l_tool_ids.extend;
        l_tool_ids(l_tool_ids.count) := l_tool_id;
      end loop delegate_loop;
      
      -- Enable tools for orchestrator
      uc_ai.g_enable_tools := true;
      
      -- Execute orchestrator profile
      l_result := uc_ai_prompt_profiles_api.execute_profile(
        p_code       => l_profile_code,
        p_parameters => p_input_params
      );
      
    exception
      when others then
        -- Always cleanup, even on error
        cleanup_agent_tools(p_exec_id);
        uc_ai.g_enable_tools := l_original_tools;
        uc_ai.g_tool_tags := l_original_tags;
        raise;
    end;
    
    -- Cleanup temporary tools
    cleanup_agent_tools(p_exec_id);
    
    -- Restore original settings
    uc_ai.g_enable_tools := l_original_tools;
    uc_ai.g_tool_tags := l_original_tags;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error executing orchestrator agent', l_scope);
      raise;
  end execute_orchestrator_agent;


  /*
   * Executes a handoff-type agent
   */
  function execute_handoff_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope                uc_ai_logger.scope := gc_scope_prefix || 'execute_handoff_agent';
    l_config               json_object_t;
    l_current_agent        varchar2(255 char);
    l_handoff_count        number := 0;
    l_max_handoffs         number;
    l_conversation_history json_array_t := json_array_t();
    l_result               json_object_t;
    l_handoff_decision     json_object_t;
    l_current_input        json_object_t;
    l_history_mgmt         json_object_t;
  begin
    uc_ai_logger.log('Executing handoff agent: ' || p_agent.code, l_scope);
    
    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_current_agent := l_config.get_string('initial_agent_code');
    l_max_handoffs := coalesce(l_config.get_number('max_handoffs'), 3);
    
    if l_config.has('history_management') then
      l_history_mgmt := l_config.get_object('history_management');
    end if;
    
    l_current_input := p_input_params;
    if l_current_input is null then
      l_current_input := json_object_t();
    end if;
    
    -- Handoff loop
    <<handoff_loop>>
    while l_handoff_count < l_max_handoffs loop
      -- Execute current agent
      l_result := execute_agent(
        p_agent_code       => l_current_agent,
        p_input_parameters => l_current_input,
        p_session_id       => p_session_id,
        p_parent_exec_id   => p_exec_id
      );
      
      -- Add to conversation history
      l_conversation_history.append(json_object_t(
        json_object(
          'agent' value l_current_agent,
          'response' value l_result.get_string('final_message')
        )
      ));
      
      -- Manage history size
      l_conversation_history := manage_history(l_conversation_history, l_history_mgmt, p_session_id);
      
      -- Check if agent wants to handoff
      if l_result.has('handoff_decision') then
        l_handoff_decision := l_result.get_object('handoff_decision');
        
        if not l_handoff_decision.get_boolean('should_handoff') then
          exit handoff_loop;
        end if;
        
        -- Prepare for next agent
        l_current_agent := l_handoff_decision.get_string('target_agent');
        l_current_input := json_object_t();
        l_current_input.put('handoff_context', l_handoff_decision.get_string('context_for_next_agent'));
        l_current_input.put('conversation_history', l_conversation_history);
        
        if p_input_params is not null then
          -- Pass through original input
          declare
            l_keys json_key_list := p_input_params.get_keys;
          begin
            <<pass_through_loop>>
            for i in 1 .. l_keys.count loop
              if not l_current_input.has(l_keys(i)) then
                l_current_input.put(l_keys(i), p_input_params.get(l_keys(i)));
              end if;
            end loop pass_through_loop;
          end;
        end if;
        
        l_handoff_count := l_handoff_count + 1;
      else
        exit handoff_loop;
      end if;
    end loop handoff_loop;
    
    -- Return final result with full history
    l_result.put('conversation_history', l_conversation_history);
    l_result.put('handoff_count', l_handoff_count);
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error executing handoff agent', l_scope);
      raise;
  end execute_handoff_agent;


  /*
   * Executes a conversation-type agent
   */
  function execute_conversation_agent(
    p_agent          in uc_ai_agents%rowtype,
    p_input_params   in json_object_t,
    p_session_id     in varchar2,
    p_exec_id        in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope           uc_ai_logger.scope := gc_scope_prefix || 'execute_conversation_agent';
    l_config          json_object_t;
    l_mode            varchar2(50 char);
    l_participants    json_array_t;
    l_participant     json_object_t;
    l_conversation    json_array_t := json_array_t();
    l_turn_count      number := 0;
    l_max_turns       number;
    l_current_state   json_object_t;
    l_agent_input     json_object_t;
    l_result          json_object_t;
    l_completion      json_object_t;
    l_history_mgmt    json_object_t;
    l_moderator       varchar2(255 char);
    l_mod_result      json_object_t;
    l_next_speaker    json_object_t;
    l_return          json_object_t;
  begin
    uc_ai_logger.log('Executing conversation agent: ' || p_agent.code, l_scope);
    
    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_mode := l_config.get_string('conversation_mode');
    l_participants := l_config.get_array('participant_agents');
    l_max_turns := coalesce(l_config.get_number('max_turns'), 10);
    
    if l_config.has('history_management') then
      l_history_mgmt := l_config.get_object('history_management');
    end if;
    
    if l_config.has('completion_criteria') then
      l_completion := l_config.get_object('completion_criteria');
    end if;
    
    l_current_state := p_input_params;
    if l_current_state is null then
      l_current_state := json_object_t();
    end if;
    
    case l_mode
      when c_conversation_round_robin then
        -- Round-robin conversation
        <<turn_loop>>
        while l_turn_count < l_max_turns loop
          <<participant_loop>>
          for i in 0 .. l_participants.get_size - 1 loop
            l_participant := treat(l_participants.get(i) as json_object_t);
            
            -- Prepare input with conversation history
            l_agent_input := l_current_state.clone;
            l_agent_input.put('conversation_history', l_conversation);
            l_agent_input.put('your_role', l_participant.get_string('role'));
            
            -- Execute agent
            l_result := execute_agent(
              p_agent_code       => l_participant.get_string('agent_code'),
              p_input_parameters => l_agent_input,
              p_session_id       => p_session_id,
              p_parent_exec_id   => p_exec_id
            );
            
            -- Add to conversation
            l_conversation.append(json_object_t(
              json_object(
                'agent' value l_participant.get_string('agent_code'),
                'role' value l_participant.get_string('role'),
                'message' value l_result.get_string('final_message'),
                'turn' value l_turn_count
              )
            ));
            
            -- Manage history
            l_conversation := manage_history(l_conversation, l_history_mgmt, p_session_id);
            
            -- Check completion criteria
            if l_completion is not null then
              if l_result.has('discussion_complete') and l_result.get_boolean('discussion_complete') then
                exit turn_loop;
              end if;
            end if;
          end loop participant_loop;
          
          l_turn_count := l_turn_count + 1;
        end loop turn_loop;
        
      when c_conversation_ai_driven then
        -- AI-driven (moderator) conversation
        l_moderator := l_config.get_string('moderator_agent_code');
        
        <<ai_turn_loop>>
        while l_turn_count < l_max_turns loop
          -- Ask moderator who should speak next
          l_agent_input := json_object_t();
          l_agent_input.put('conversation_history', l_conversation);
          l_agent_input.put('available_agents', l_participants);
          l_agent_input.put('task', 'Decide which agent should speak next and what they should address');
          l_agent_input.put('original_request', p_input_params);
          
          l_mod_result := execute_agent(
            p_agent_code       => l_moderator,
            p_input_parameters => l_agent_input,
            p_session_id       => p_session_id,
            p_parent_exec_id   => p_exec_id
          );
          
          -- Check if moderator says we're done
          if l_mod_result.has('discussion_complete') and l_mod_result.get_boolean('discussion_complete') then
            exit ai_turn_loop;
          end if;
          
          -- Get next speaker from moderator
          l_next_speaker := l_mod_result.get_object('next_speaker');
          if l_next_speaker is null then
            uc_ai_logger.log_warn('Moderator did not specify next speaker, ending conversation', l_scope);
            exit ai_turn_loop;
          end if;
          
          -- Execute the chosen agent
          l_agent_input := l_current_state.clone;
          l_agent_input.put('conversation_history', l_conversation);
          l_agent_input.put('directive', l_next_speaker.get_string('directive'));
          
          l_result := execute_agent(
            p_agent_code       => l_next_speaker.get_string('agent_code'),
            p_input_parameters => l_agent_input,
            p_session_id       => p_session_id,
            p_parent_exec_id   => p_exec_id
          );
          
          -- Add to conversation
          l_conversation.append(json_object_t(
            json_object(
              'agent' value l_next_speaker.get_string('agent_code'),
              'directive' value l_next_speaker.get_string('directive'),
              'message' value l_result.get_string('final_message'),
              'turn' value l_turn_count
            )
          ));
          
          -- Manage history
          l_conversation := manage_history(l_conversation, l_history_mgmt, p_session_id);
          
          l_turn_count := l_turn_count + 1;
        end loop ai_turn_loop;
        
      else
        uc_ai_logger.log_error('Unknown conversation mode: ' || l_mode, l_scope);
        raise_application_error(-20012, 'Unknown conversation mode: ' || l_mode);
    end case;
    
    -- conversation_complete
    l_return := json_object_t();
    l_return.put('conversation', l_conversation);
    l_return.put('turns', l_turn_count);
    l_return.put('completed', true);
    l_return.put('final_message', l_result.get_string('final_message'));

    return l_return;
  exception
    when others then
      uc_ai_logger.log_error('Error executing conversation agent', l_scope);
      raise;
  end execute_conversation_agent;


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
        if not validate_workflow_definition(p_workflow_definition) then
          raise_application_error(-20001, 'Invalid workflow definition');
        end if;
        
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
    if not validate_agent_references(p_workflow_definition, p_orchestration_config) then
      raise_application_error(-20001, 'Invalid agent references in configuration');
    end if;
    
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
      uc_ai_logger.log_error('Error creating agent', l_scope);
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
      if not validate_agent_references(p_workflow_definition, p_orchestration_config) then
        raise_application_error(-20001, 'Invalid agent references in configuration');
      end if;
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
      uc_ai_logger.log_error('Error updating agent', l_scope);
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
      uc_ai_logger.log_error('Error deleting agent', l_scope);
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
      uc_ai_logger.log_error('Error deleting agent', l_scope);
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
      uc_ai_logger.log_error('Error changing agent status', l_scope);
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
      uc_ai_logger.log_error('Error changing agent status', l_scope);
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
      uc_ai_logger.log_error('Error creating new version of agent', l_scope);
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
      uc_ai_logger.log_error('Error getting agent', l_scope);
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
      uc_ai_logger.log_error('Error getting agent', l_scope);
      raise;
  end get_agent;


  /*
   * Validates that all agent_code references exist
   */
  function validate_agent_references(
    p_workflow_definition  in clob default null,
    p_orchestration_config in clob default null
  ) return boolean
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'validate_agent_references';
    l_codes_arr t_agent_code_list := t_agent_code_list();
    l_json      json_element_t;
  begin
    -- Extract codes from workflow definition
    if p_workflow_definition is not null then
      l_json := json_element_t.parse(p_workflow_definition);
      extract_agent_codes(l_json, l_codes_arr);
    end if;
    
    -- Extract codes from orchestration config
    if p_orchestration_config is not null then
      l_json := json_element_t.parse(p_orchestration_config);
      extract_agent_codes(l_json, l_codes_arr);
    end if;
    
    -- Validate each code exists
    <<code_loop>>
    for i in 1 .. l_codes_arr.count loop
      if not agent_exists(l_codes_arr(i)) then
        uc_ai_logger.log_error('Referenced agent does not exist: ' || l_codes_arr(i), l_scope);
        return false;
      end if;
    end loop code_loop;
    
    return true;
  exception
    when others then
      uc_ai_logger.log_error('Error validating agent references', l_scope);
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
      uc_ai_logger.log_error('Error checking agent references', l_scope);
      raise;
  end check_agent_not_referenced;


  /*
   * Validates a workflow definition JSON
   */
  function validate_workflow_definition(
    p_workflow_definition in clob
  ) return boolean
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'validate_workflow_definition';
    l_json         json_object_t;
    l_workflow_type varchar2(50 char);
    l_steps        json_array_t;
  begin
    if p_workflow_definition is null then
      return false;
    end if;
    
    l_json := json_object_t.parse(p_workflow_definition);
    
    -- Check required fields
    if not l_json.has('workflow_type') then
      uc_ai_logger.log_error('workflow_definition missing required field: workflow_type', l_scope);
      return false;
    end if;
    
    l_workflow_type := l_json.get_string('workflow_type');
    if l_workflow_type not in (c_workflow_sequential, c_workflow_conditional, c_workflow_parallel, c_workflow_loop) then
      uc_ai_logger.log_error('Invalid workflow_type: ' || l_workflow_type, l_scope);
      return false;
    end if;
    
    if not l_json.has('steps') then
      uc_ai_logger.log_error('workflow_definition missing required field: steps', l_scope);
      return false;
    end if;
    
    l_steps := l_json.get_array('steps');
    if l_steps.get_size = 0 then
      uc_ai_logger.log_error('workflow_definition steps array is empty', l_scope);
      return false;
    end if;
    
    -- Validate each step has agent_code
    <<step_loop>>
    for i in 0 .. l_steps.get_size - 1 loop
      declare
        l_step json_object_t := treat(l_steps.get(i) as json_object_t);
      begin
        if not l_step.has('agent_code') then
          uc_ai_logger.log_error('Step ' || i || ' missing required field: agent_code', l_scope);
          return false;
        end if;
      end;
    end loop step_loop;
    
    return true;
  exception
    when others then
      uc_ai_logger.log_error('Error validating workflow definition: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      return false;
  end validate_workflow_definition;


  /*
   * Validates an orchestration config JSON
   */
  function validate_orchestration_config(
    p_orchestration_config in clob
  ) return boolean
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'validate_orchestration_config';
    l_json         json_object_t;
    l_pattern_type varchar2(50 char);
  begin
    if p_orchestration_config is null then
      return false;
    end if;
    
    l_json := json_object_t.parse(p_orchestration_config);
    
    -- Check required fields based on pattern type
    if not l_json.has('pattern_type') then
      uc_ai_logger.log_error('orchestration_config missing required field: pattern_type', l_scope);
      return false;
    end if;
    
    l_pattern_type := l_json.get_string('pattern_type');
    
    case l_pattern_type
      when 'orchestrator' then
        if not l_json.has('orchestrator_profile_code') then
          uc_ai_logger.log_error('Orchestrator config missing required field: orchestrator_profile_code', l_scope);
          return false;
        end if;
        if not l_json.has('delegate_agents') then
          uc_ai_logger.log_error('Orchestrator config missing required field: delegate_agents', l_scope);
          return false;
        end if;
        
      when 'handoff' then
        if not l_json.has('initial_agent_code') then
          uc_ai_logger.log_error('Handoff config missing required field: initial_agent_code', l_scope);
          return false;
        end if;
        
      when 'conversation' then
        if not l_json.has('conversation_mode') then
          uc_ai_logger.log_error('Conversation config missing required field: conversation_mode', l_scope);
          return false;
        end if;
        if not l_json.has('participant_agents') then
          uc_ai_logger.log_error('Conversation config missing required field: participant_agents', l_scope);
          return false;
        end if;
        
      else
        uc_ai_logger.log_error('Invalid pattern_type: ' || l_pattern_type, l_scope);
        return false;
    end case;
    
    return true;
  exception
    when others then
      uc_ai_logger.log_error('Error validating orchestration config: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      return false;
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
    l_workflow_def.put('workflow_type', c_workflow_sequential);
    
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
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'create_parallel_workflow';
    l_workflow_def   json_object_t := json_object_t();
    l_parallel_config json_object_t := json_object_t();
    l_steps          json_array_t := json_array_t();
    l_step           json_object_t;
    l_agent_code     varchar2(255 char);
  begin
    -- Build workflow definition
    l_workflow_def.put('workflow_type', c_workflow_parallel);
    
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
    p_parent_exec_id   in uc_ai_agent_executions.id%type default null
  ) return json_object_t
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'execute_agent';
    l_agent      uc_ai_agents%rowtype;
    l_exec_id    uc_ai_agent_executions.id%type;
    l_session_id varchar2(255 char);
    l_result     json_object_t;
  begin
    uc_ai_logger.log('Executing agent: ' || p_agent_code, l_scope);
    
    -- Get agent
    l_agent := get_agent(p_agent_code, p_agent_version);
    
    -- Generate session ID if not provided
    l_session_id := coalesce(p_session_id, generate_session_id());
    
    -- Create execution record
    l_exec_id := create_execution(l_agent.id, l_session_id, p_parent_exec_id, p_input_parameters);
    
    begin
      -- Execute based on agent type
      case l_agent.agent_type
        when c_type_profile then
          l_result := execute_profile_agent(l_agent, p_input_parameters, l_exec_id);
          
        when c_type_workflow then
          l_result := execute_workflow_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        when c_type_orchestrator then
          l_result := execute_orchestrator_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        when c_type_handoff then
          l_result := execute_handoff_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        when c_type_conversation then
          l_result := execute_conversation_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);
          
        else
          uc_ai_logger.log_error('Unknown agent type: ' || l_agent.agent_type, l_scope);
          raise_application_error(-20010, 'Unknown agent type: ' || l_agent.agent_type);
      end case;
      
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
      uc_ai_logger.log_error('Error executing agent: ' || p_agent_code, l_scope);
      raise;
  end execute_agent;


  /*
   * Executes an agent by ID
   */
  function execute_agent(
    p_agent_id         in uc_ai_agents.id%type,
    p_input_parameters in json_object_t default null,
    p_session_id       in varchar2 default null,
    p_parent_exec_id   in uc_ai_agent_executions.id%type default null
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
      p_parent_exec_id   => p_parent_exec_id
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
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_execution_history';
    l_exec_hist_cur sys_refcursor;
  begin
    open l_exec_hist_cur for
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
             e.total_cost_usd,
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
    
    return l_exec_hist_cur;
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
    l_result.put('total_cost_usd', l_exec.total_cost_usd);
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
