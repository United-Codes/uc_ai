create or replace package body uc_ai_agent_exec_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  -- ============================================================================
  -- Private Helper Functions
  -- ============================================================================

  /*
   * Executes a single workflow step with input mapping and optional condition checking
   * Sets po_step_output to null if the step was skipped due to a condition
   */
  procedure run_step(
    p_step             in json_object_t,
    pio_workflow_state in out nocopy json_object_t,
    p_session_id       in varchar2,
    p_exec_id          in uc_ai_agent_executions.id%type,
    p_check_condition  in boolean default false,
    p_log_prefix       in varchar2 default null,
    po_step_output     out nocopy json_object_t
  )
  as
    l_scope            uc_ai_logger.scope := gc_scope_prefix || 'run_step';
    l_step_agent       varchar2(255 char);
    l_input_mapping    json_object_t;
    l_step_input       json_object_t;
    l_condition        varchar2(32676 char);
    l_condition_result boolean;
    l_log_msg          varchar2(4000 char);
  begin
    l_step_agent := p_step.get_string('agent_code');
    
    -- Check condition if requested and present
    if p_check_condition and p_step.has('condition') then
      l_condition := p_step.get_string('condition');
      l_condition_result := uc_ai_agent_workflow_api.evaluate_condition(l_condition, pio_workflow_state);
      uc_ai_logger.log('Evaluating condition for step ' || l_step_agent || ': ' || case when l_condition_result then 'TRUE' else 'FALSE' end, l_scope);
      if not l_condition_result then
        uc_ai_logger.log('Skipping step due to condition: ' || l_step_agent, l_scope);
        po_step_output := null;
        return;
      end if;
    end if;
    
    -- Map inputs
    if p_step.has('input_mapping') then
      l_input_mapping := treat(p_step.get('input_mapping') as json_object_t);
    else
      l_input_mapping := null;
    end if;
    l_step_input := uc_ai_agent_workflow_api.map_inputs(l_input_mapping, pio_workflow_state);
    
    -- Log execution
    l_log_msg := case when p_log_prefix is not null then p_log_prefix || ', executing' else 'Executing' end ||
                 ' step: ' || l_step_agent || ' with input:';
    uc_ai_logger.log(l_log_msg, l_scope, case when l_step_input is not null then l_step_input.to_clob else 'null' end);
    
    -- Execute step agent
    po_step_output := uc_ai_agents_api.execute_agent(
      p_agent_code       => l_step_agent,
      p_input_parameters => l_step_input,
      p_session_id       => p_session_id,
      p_parent_exec_id   => p_exec_id
    );
    
    uc_ai_logger.log('Step ' || l_step_agent || ' completed with output:', l_scope, po_step_output.to_clob);
    
    -- Add result to workflow state
    uc_ai_agent_workflow_api.add_result_to_workflow_state(
      p_step             => p_step,
      p_step_output      => po_step_output,
      pio_workflow_state => pio_workflow_state
    );
  end run_step;


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
    l_step_output    json_object_t;
    l_workflow_state json_object_t := json_object_t();
    l_steps_state    json_object_t := json_object_t();
    l_iteration      number := 0;
    l_last_output    json_object_t;
  begin
    uc_ai_logger.log('Executing sequential workflow: ' || p_agent.code, l_scope);
    
    l_workflow_def := json_object_t.parse(p_agent.workflow_definition);
    l_steps := l_workflow_def.get_array('steps');
    
    -- Initialize workflow state with _steps container
    l_workflow_state.put('steps', l_steps_state);
    l_workflow_state.put('input', p_input_params);
    
    -- Execute steps in order
    <<step_loop>>
    for i in 0 .. l_steps.get_size - 1 loop
      l_step := treat(l_steps.get(i) as json_object_t);
      
      run_step(
        p_step             => l_step,
        pio_workflow_state => l_workflow_state,
        p_session_id       => p_session_id,
        p_exec_id          => p_exec_id,
        p_check_condition  => true,
        po_step_output     => l_step_output
      );
      
      -- Track output if step was executed (not skipped)
      if l_step_output is not null then
        l_last_output := l_step_output;
        l_iteration := l_iteration + 1;
      end if;
    end loop step_loop;
    
    -- Build final result
    l_workflow_state.put('_workflow_iterations', l_iteration);
    
    -- Copy final message from last step
    if l_last_output is not null and l_last_output.has('final_message') then
      l_workflow_state.put('final_message', l_last_output.get_clob('final_message'));
    end if;
    
    return l_workflow_state;
  exception
    when others then
      uc_ai_logger.log_error('Error executing sequential workflow', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
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
    l_scope           uc_ai_logger.scope := gc_scope_prefix || 'execute_loop_workflow';
    l_workflow_def    json_object_t;
    l_loop_config     json_object_t;
    l_steps           json_array_t;
    l_max_iterations  number;
    l_exit_condition  varchar2(32676 char);
    l_iteration       number := 0;
    l_workflow_state  json_object_t;
    l_step            json_object_t;
    l_step_output     json_object_t;
    l_max_it_json     number;
    l_iteration_array json_array_t := json_array_t();
    l_step_state      json_object_t;
    l_final_msg       varchar2(32676 char);
  begin
    uc_ai_logger.log('Executing loop workflow: ' || p_agent.code, l_scope);
    
    l_workflow_def := json_object_t.parse(p_agent.workflow_definition);
    
    -- Get loop configuration
    l_loop_config := l_workflow_def.get_object('loop_config');
    if l_loop_config is not null and l_loop_config.has('max_iterations') then
      l_max_it_json := l_loop_config.get_number('max_iterations');
    end if;

    l_max_iterations := coalesce(
      l_max_it_json,
      p_agent.max_iterations,
      10
    );
    
    if l_loop_config.has('exit_condition') then
      l_exit_condition := l_loop_config.get_string('exit_condition');
    end if;
    
    -- Initialize state with input
    l_workflow_state := json_object_t();
    l_workflow_state.put('input', p_input_params);

    if l_workflow_def.has('pre_steps') then
      l_steps := l_workflow_def.get_array('pre_steps');
      <<pre_step_loop>>
      for i in 0 .. l_steps.get_size - 1 loop
        l_step := treat(l_steps.get(i) as json_object_t);

        run_step(
          p_step             => l_step,
          pio_workflow_state => l_workflow_state,
          p_session_id       => p_session_id,
          p_exec_id          => p_exec_id,
          p_check_condition  => false,
          p_log_prefix       => 'Pre step ' || i,
          po_step_output     => l_step_output
        );

      end loop pre_step_loop;
    end if;

    l_steps := l_workflow_def.get_array('steps');
    
    -- Loop until exit condition or max iterations
    <<iteration_loop>>
    while l_iteration < l_max_iterations loop
      -- Execute all steps
      <<step_loop>>
      for i in 0 .. l_steps.get_size - 1 loop
        l_step := treat(l_steps.get(i) as json_object_t);
        
        run_step(
          p_step             => l_step,
          pio_workflow_state => l_workflow_state,
          p_session_id       => p_session_id,
          p_exec_id          => p_exec_id,
          p_check_condition  => false,
          p_log_prefix       => 'Iteration ' || l_iteration,
          po_step_output     => l_step_output
        );

        -- Check exit condition
        if l_exit_condition is not null then
          if uc_ai_agent_workflow_api.evaluate_condition(l_exit_condition, l_workflow_state) then
            uc_ai_logger.log('Exit condition met at iteration: ' || l_iteration, l_scope);
            exit iteration_loop;
          end if;
        end if;
      end loop step_loop;
      
      l_iteration := l_iteration + 1;

      l_step_state := l_workflow_state.get_object('steps');
      l_iteration_array.append(l_step_state);
    end loop iteration_loop;
    
    l_workflow_state.put('_loop_iterations', l_iteration);
    l_workflow_state.put('_loop_iteration_state', l_iteration_array);


    if l_workflow_def.has('post_steps') then
      l_steps := l_workflow_def.get_array('post_steps');
      <<post_step_loop>>
      for i in 0 .. l_steps.get_size - 1 loop
        l_step := treat(l_steps.get(i) as json_object_t);

        run_step(
          p_step             => l_step,
          pio_workflow_state => l_workflow_state,
          p_session_id       => p_session_id,
          p_exec_id          => p_exec_id,
          p_check_condition  => false,
          p_log_prefix       => 'Post step ' || i,
          po_step_output     => l_step_output
        );

      end loop post_step_loop;
    end if;


    if l_workflow_def.has('final_message') then
      l_final_msg := uc_ai_agent_workflow_api.evaluate_final_message(
        p_final_message => l_workflow_def.get('final_message'),
        p_workflow_state => l_workflow_state
      );
      l_workflow_state.put('final_message', l_final_msg);
    else
      -- Default final message from last step
      l_workflow_state.put('final_message', l_step_output.get_clob('final_message'));
    end if;
    
    return l_workflow_state;
  exception
    when others then
      uc_ai_logger.log_error('Error executing loop workflow', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_loop_workflow;


  -- ============================================================================
  -- Public Functions
  -- ============================================================================

  /*
   * Executes a profile-type agent (wrapper around prompt profile)
   */
  function execute_profile_agent(
    p_agent            in uc_ai_agents%rowtype,
    p_input_params     in json_object_t,
    p_exec_id          in uc_ai_agent_executions.id%type,
    p_response_schema  in json_object_t default null
  ) return json_object_t
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'execute_profile_agent';
    l_result json_object_t;
    l_config json_object_t;
    l_has_schema number;
    l_final_message clob;
  begin
    uc_ai_logger.log('Executing profile agent: ' || p_agent.code, l_scope);

    if p_response_schema is not null then
      l_config := json_object_t();
      l_config.put('response_schema', p_response_schema);
    end if;
    
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code            => p_agent.prompt_profile_code,
      p_version         => p_agent.prompt_profile_version,
      p_parameters      => p_input_params,
      p_config_override => l_config
    );

    if p_response_schema is not null then
      l_has_schema := 1;
    else
      select case when response_schema is not null then 1 else 0 end as has_schema
        into l_has_schema
        from uc_ai_prompt_profiles
       where code = p_agent.prompt_profile_code
         and (p_agent.prompt_profile_version is null or version = p_agent.prompt_profile_version);
    end if;

    if l_has_schema = 1 then
      l_final_message := l_result.get_clob('final_message');
      l_result.put('final_message', json_object_t.parse(l_final_message));
    end if;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error executing profile agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_profile_agent;


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
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'execute_workflow_agent';
    l_workflow_def  json_object_t;
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
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_workflow_type
        , p_scope      => l_scope
        , p0           => l_workflow_type
        );
    end case;
  exception
    when others then
      uc_ai_logger.log_error('Error executing workflow agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_workflow_agent;


  /*
   * Registers a child agent as a temporary tool for orchestration
   */
  function register_agent_as_tool(
    p_agent_code       in varchar2,
    p_exec_id          in uc_ai_agent_executions.id%type,
    p_tool_tag         in varchar2,
    p_session_id       in varchar2
  ) return uc_ai_tools.id%type
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'register_agent_as_tool';
    l_tool_id       uc_ai_tools.id%type;
    l_function_call clob;
    l_agent         uc_ai_agents%rowtype;
  begin
    uc_ai_logger.log('Registering agent as tool: ' || p_agent_code, l_scope);
    
    -- Get the agent to check for input schema
    begin
      l_agent := uc_ai_agents_api.get_agent(p_agent_code);
    exception
      when others then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_agent_retrieval
        , p_scope      => l_scope
        , p0           => p_agent_code
        , p_extra      => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
    end;
    
    -- Create function call that executes the agent
    l_function_call := q'!
declare
  l_input_clob clob;
  l_input json_object_t;
  l_result json_object_t;
begin
  l_input_clob := :arguments;
  l_input := json_object_t(l_input_clob);

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => '!' || p_agent_code || q'!',
    p_input_parameters => l_input,
    p_session_id       => '!' || p_session_id || q'!',
    p_parent_exec_id   => !' || p_exec_id || q'!
  );

  return l_result.get_string('final_message');
exception
  when others then
    return 'Error executing agent: ' || sqlerrm;
end;!';

    uc_ai_logger.log('Creating tool for agent: ' || p_agent_code, l_scope, l_function_call);

    -- Create the tool
    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code    => p_agent_code || '_TOOL_' || sys_guid(),
      p_description  => l_agent.description,
      p_function_call => l_function_call,
      p_json_schema  => json_object_t(l_agent.input_schema),
      p_active       => 1,
      p_tags         => apex_t_varchar2(p_tool_tag),
      p_created_by   => 'UC_AI_AGENT_EXEC_API'
    );

    return l_tool_id;
  exception
    when others then
      uc_ai_logger.log_error('Error registering agent as tool', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end register_agent_as_tool;


  /*
   * Cleans up temporary tools created for an execution
   */
  procedure cleanup_agent_tools(
    p_tool_ids in apex_t_number
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'cleanup_agent_tools';
  begin
    uc_ai_logger.log('Cleaning up ' || p_tool_ids.count || ' temporary tools', l_scope);

    -- Delete tools (cascade will handle parameters and tags)
    delete from uc_ai_tools
    where id in (
      select t.column_value from table(p_tool_ids) t
    );
  exception
    when others then
      uc_ai_logger.log_error('Error cleaning up agent tools', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
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
    l_delegate         varchar2(4000 char);
    l_tool_ids         apex_t_number := apex_t_number();
    l_tool_id          uc_ai_tools.id%type;
    l_result           json_object_t;
    l_profile_code     varchar2(255 char);
    l_original_tools   boolean;
    l_original_tags    apex_t_varchar2;
    l_tool_tag         varchar2(255 char);
    l_prompt_profile   uc_ai_prompt_profiles%rowtype;
    l_tool_arr         json_array_t := json_array_t();
    l_profile_config   json_object_t;
  begin
    uc_ai_logger.log('Executing orchestrator agent: ' || p_agent.code, l_scope);
    
    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_delegates := l_config.get_array('delegate_agents');
    l_profile_code := l_config.get_string('orchestrator_profile_code');
    l_tool_tag := lower('orchestrator_' || p_agent.code || '_' || sys_guid());

    l_prompt_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code    => l_profile_code
    );
    
    -- Save original tool settings
    --l_original_tools := uc_ai.g_enable_tools;
    --l_original_tags := uc_ai.g_tool_tags;
    
    begin
      -- Register delegate agents as tools
      <<delegate_loop>>
      for i in 0 .. l_delegates.get_size - 1 loop
        l_delegate := l_delegates.get_string(i);
        
        l_tool_id := register_agent_as_tool(
          p_agent_code       => l_delegate,
          p_exec_id          => p_exec_id,
          p_tool_tag         => l_tool_tag,
          p_session_id       => p_session_id
        );
        
        l_tool_ids.extend;
        l_tool_ids(l_tool_ids.count) := l_tool_id;
      end loop delegate_loop;

      uc_ai_logger.log('Overwriting existing model config JSON', l_scope, l_prompt_profile.model_config_json);

      l_profile_config := json_object_t.parse(coalesce(l_prompt_profile.model_config_json, '{}'));
      l_profile_config.put('g_enable_tools', true);
      l_tool_arr.append(l_tool_tag);
      l_profile_config.put('g_tool_tags', l_tool_arr);
      l_profile_config.put('g_max_tool_calls', l_config.get_number('max_delegations'));
      
      -- Enable tools for orchestrator
      uc_ai.g_enable_tools := true;
      uc_ai.g_tool_tags := apex_t_varchar2(l_tool_tag);
      
      -- Execute orchestrator profile
      l_result := uc_ai_prompt_profiles_api.execute_profile(
        p_code              => l_profile_code,
        p_parameters        => p_input_params,
        p_config_override   => l_profile_config
      );
      
    exception
      when others then
        -- Always cleanup, even on error
        uc_ai_logger.log_error('Error during orchestrator execution', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
        cleanup_agent_tools(l_tool_ids);
        --uc_ai.g_enable_tools := l_original_tools;
        --uc_ai.g_tool_tags := l_original_tags;
        raise;
    end;

    -- Cleanup temporary tools
    cleanup_agent_tools(l_tool_ids);
    
    -- Restore original settings
    uc_ai.g_enable_tools := l_original_tools;
    uc_ai.g_tool_tags := l_original_tags;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error executing orchestrator agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
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
      l_result := uc_ai_agents_api.execute_agent(
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
      l_conversation_history := uc_ai_agent_workflow_api.manage_history(
        l_conversation_history, l_history_mgmt, p_session_id
      );
      
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
    l_conv_obj        json_object_t;
    l_conversation    json_array_t := json_array_t();
    l_turn_count      number := 0;
    l_max_turns       number;
    l_current_state   json_object_t;
    l_agent_input     json_object_t;
    l_result          json_object_t;
    l_termination     json_object_t;
    l_term_type       varchar2(255 char);
    l_term_keyword    varchar2(4000 char);
    l_history_mgmt    json_object_t;
    l_moderator       json_object_t;
    l_moderator_code  varchar2(255 char);
    l_moderator_input json_object_t;
    l_moderator_summary_input json_object_t;
    l_mod_result      json_object_t;
    l_next_speaker    json_object_t;
    l_return          json_object_t;
    l_input_mapping   json_object_t;
    l_agent_descr_map json_object_t := json_object_t();
    l_agent           uc_ai_agents%rowtype;
    l_participant_info clob;

  begin
    uc_ai_logger.log('Executing conversation agent: ' || p_agent.code, l_scope);
    
    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_mode := l_config.get_string('conversation_mode');
    l_participants := l_config.get_array('agents');
    l_max_turns := coalesce(l_config.get_number('max_turns'), 10);
    
    if l_config.has('history_management') then
      l_history_mgmt := l_config.get_object('history_management');
    end if;
    
    if l_config.has('termination_condition') then
      l_termination := l_config.get_object('termination_condition');
      l_term_type := l_termination.get_string('type');

      if l_term_type = 'keyword' then
        l_term_keyword := l_termination.get_string('keyword');  
      else
        uc_ai_logger.log_warn('Unknown termination condition type: ' || l_term_type, l_scope);
      end if;
    end if;
    
    l_current_state := json_object_t();
    l_current_state.put('input', p_input_params);

    -- fill map of agent descriptions
    -- so input mapping can be used with "$.agent_description"
    <<fill_agent_descr_loop>>
    for i in 0 .. l_participants.get_size - 1 loop
      l_agent := uc_ai_agents_api.get_agent(
        p_code => treat(l_participants.get(i) as json_object_t).get_string('agent_code')
      );
      l_agent_descr_map.put(l_agent.code, l_agent.description);
    end loop fill_agent_descr_loop;

    l_conv_obj := json_object_t();
    l_conv_obj.put('agent', 'system');
    l_conv_obj.put('message', p_input_params);
    l_conv_obj.put('turn', l_turn_count);
    l_conversation.append(l_conv_obj);
    
    case l_mode
      when c_conversation_round_robin then
        -- Round-robin conversation
        <<turn_loop>>
        while l_turn_count < l_max_turns loop
          <<participant_loop>>
          for i in 0 .. l_participants.get_size - 1 loop
            l_participant := treat(l_participants.get(i) as json_object_t);
            l_input_mapping := l_participant.get_object('input_mapping');

            l_current_state.put('agent_description', l_agent_descr_map.get_string(l_participant.get_string('agent_code')));
            -- Prepare input with conversation history
            l_current_state.put('chat_history', uc_ai_toon.to_toon(l_conversation));
            l_current_state.put('role', l_participant.get_string('role'));
            l_agent_input := uc_ai_agent_workflow_api.map_inputs(l_input_mapping, l_current_state);
            
            -- Execute agent
            l_result := uc_ai_agents_api.execute_agent(
              p_agent_code       => l_participant.get_string('agent_code'),
              p_input_parameters => l_agent_input,
              p_session_id       => p_session_id,
              p_parent_exec_id   => p_exec_id
            );
            
            l_conv_obj := json_object_t();
            l_conv_obj.put('agent', l_participant.get_string('agent_code'));
            l_conv_obj.put('role', l_agent_input.get_string('role'));
            l_conv_obj.put('message', l_result.get_string('final_message'));
            l_conv_obj.put('turn', l_turn_count);
            -- Add to conversation
            l_conversation.append(l_conv_obj);
            
            -- Manage history
            l_conversation := uc_ai_agent_workflow_api.manage_history(
              l_conversation, l_history_mgmt, p_session_id
            );
            
            -- Check completion criteria
            if l_term_keyword is not null and l_conv_obj.get_string('message') like '%' || l_term_keyword || '%' then
              uc_ai_logger.log('Termination keyword "' || l_term_keyword || '" found in agent response, ending conversation', l_scope);
              exit turn_loop;
            end if;
          end loop participant_loop;
          
          l_turn_count := l_turn_count + 1;
        end loop turn_loop;

        l_return := json_object_t();
        l_return.put('conversation', l_conversation);
        l_return.put('turns', l_turn_count);
        l_return.put('completed', true);
        l_return.put('final_message', l_result.get_string('final_message'));
        
      when c_conversation_ai_driven then
        -- AI-driven (moderator) conversation
        l_moderator := l_config.get_object('moderator_agent');
        l_moderator_code := l_moderator.get_string('agent_code');
        l_moderator_input := l_moderator.get_object('input_mapping');
        l_moderator_summary_input := l_moderator.get_object('summary_mapping');

        <<participant_info_loop>>
        for i in 0 .. l_participants.get_size - 1 loop
          l_participant := treat(l_participants.get(i) as json_object_t);

          l_participant_info := l_participant_info || 'Agent Code: ' || l_participant.get_string('agent_code') || ' - Description: ' ||
            uc_ai_agents_api.get_agent(p_code => l_participant.get_string('agent_code')).description || chr(10);
        end loop participant_info_loop;

         l_current_state.put('available_agents', l_participant_info);
        
        <<ai_turn_loop>>
        while l_turn_count < l_max_turns loop
          l_current_state.put('chat_history', uc_ai_toon.to_toon(l_conversation));
          -- Ask moderator who should speak next
          l_agent_input := uc_ai_agent_workflow_api.map_inputs(l_moderator_input, l_current_state);
          
          l_mod_result := uc_ai_agents_api.execute_agent(
            p_agent_code       => l_moderator_code,
            p_input_parameters => l_agent_input,
            p_session_id       => p_session_id,
            p_parent_exec_id   => p_exec_id,
            p_response_schema  => json_object_t(
             '{
                "$schema": "http://json-schema.org/draft-07/schema#",
                "type": "object",
                "properties": {
                  "next_speaker": {
                    "type": "object",
                    "properties": {
                      "agent_code": {
                        "type": "string",
                        "description": "Code of the agent which should speak next"
                      },
                      "moderator_rationale": {
                        "type": "string",
                        "description": "Your reasoning on why you picked this agent. One sentence."
                      }
                    },
                    "required": [
                      "agent_code",
                      "moderator_rationale"
                    ]
                  },
                  "discussion_complete": {
                    "type": "boolean",
                    "description": "Set to true if you think the discussion should end as a decision has been reached or sufficient information has been gathered."
                  }
                },
                "required": [
                  "next_speaker",
                  "discussion_complete"
                ]
              }'
            )
          );
          l_mod_result := l_mod_result.get_object('final_message');
          
          -- Check if moderator says we're done
          if l_mod_result.has('discussion_complete') and l_mod_result.get_boolean('discussion_complete') then
            exit ai_turn_loop;
          end if;
          
          -- Get next speaker from moderator
          if not l_mod_result.has('next_speaker') or l_mod_result.get_object('next_speaker') is null then
            uc_ai_logger.log_warn('Moderator did not specify next speaker, ending conversation', l_scope);
            exit ai_turn_loop;
          end if;

          l_next_speaker := l_mod_result.get_object('next_speaker');
          <<find_participant_loop>>
          for i in 0 .. l_participants.get_size - 1 loop 
            l_participant := treat(l_participants.get(i) as json_object_t);
            if l_participant.get_string('agent_code') = l_next_speaker.get_string('agent_code') then
              exit find_participant_loop;
            else
              l_participant := null;
            end if;
          end loop find_participant_loop;

          if l_participant is null then
            uc_ai_error.raise_error(
              p_error_code => uc_ai_error.c_err_speaker_not_found
            , p_scope      => l_scope
            , p0           => l_next_speaker.get_string('agent_code')
            );
          end if;

          l_current_state.put('agent_description', l_agent_descr_map.get_string(l_participant.get_string('agent_code')));
          l_current_state.put('chat_history', uc_ai_toon.to_toon(l_conversation));
          l_current_state.put('role', l_participant.get_string('role'));
          l_current_state.put('moderator_rationale', l_next_speaker.get_string('moderator_rationale'));

          l_input_mapping := l_participant.get_object('input_mapping');
          -- Prepare input with conversation history
          l_agent_input := uc_ai_agent_workflow_api.map_inputs(l_input_mapping, l_current_state);
          
          l_result := uc_ai_agents_api.execute_agent(
            p_agent_code       => l_next_speaker.get_string('agent_code'),
            p_input_parameters => l_agent_input,
            p_session_id       => p_session_id,
            p_parent_exec_id   => p_exec_id
          );
          

          l_conv_obj := json_object_t();
          l_conv_obj.put('agent', l_next_speaker.get_string('agent_code'));
          l_conv_obj.put('role', l_agent_input.get_string('role'));
          l_conv_obj.put('message', l_result.get_string('final_message'));
          l_conv_obj.put('turn', l_turn_count);
          -- Add to conversation
          l_conversation.append(l_conv_obj);

          uc_ai_logger.log('Turn ' || l_turn_count || ' - Agent ' || l_next_speaker.get_string('agent_code') || ' spoke.', l_scope, 'Conversation:' || l_conversation.to_clob);
          
          -- Manage history
          l_conversation := uc_ai_agent_workflow_api.manage_history(
            l_conversation, l_history_mgmt, p_session_id
          );
          
          l_turn_count := l_turn_count + 1;
        end loop ai_turn_loop;

        l_agent_input := uc_ai_agent_workflow_api.map_inputs(l_moderator_summary_input, l_current_state);
        -- Get final summary from moderator
        l_mod_result := uc_ai_agents_api.execute_agent(
          p_agent_code       => l_moderator_code,
          p_input_parameters => l_agent_input,
          p_session_id       => p_session_id,
          p_parent_exec_id   => p_exec_id
        );

        uc_ai_logger.log('mod result - turn ' || l_turn_count, l_scope, l_mod_result.to_clob);

        l_return := json_object_t();
        l_return.put('conversation', l_conversation);
        l_return.put('turns', l_turn_count);
        l_return.put('completed', true);
        l_return.put('final_message', l_mod_result.get_string('final_message'));
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_conv_mode
        , p_scope      => l_scope
        , p0           => l_mode
        );
    end case;
    
    -- conversation_complete
   

    return l_return;
  exception
    when others then
      uc_ai_logger.log_error('Error executing conversation agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_conversation_agent;


  procedure create_apex_session_if_needed
  as
    l_ws_id  number;
    l_app_id number;
  begin
    if apex_application.g_instance is null then
      begin
        select workspace_id, application_id
          into l_ws_id, l_app_id
          from apex_applications
         fetch first 1 row only;
      exception
        when no_data_found then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_apex_session
          , p_scope      => gc_scope_prefix || 'create_apex_session_if_needed'
          );
      end;

      apex_session.create_session(
        p_app_id       => l_app_id,
        p_page_id      => 0,
        p_username     => 'UC_AI_AGENT_EXEC'
      );
    end if;
  end create_apex_session_if_needed;

end uc_ai_agent_exec_api;
/
