create or replace package body uc_ai_agent_exec_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  -- ============================================================================
  -- Private Helper Functions
  -- ============================================================================

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
    l_steps_state    json_object_t := json_object_t();
    l_input_mapping  json_object_t;
    l_output_key     varchar2(255 char);
    l_condition      json_object_t;
    l_iteration      number := 0;
    l_last_output    json_object_t;
  begin
    uc_ai_logger.log('Executing sequential workflow: ' || p_agent.code, l_scope);
    
    l_workflow_def := json_object_t.parse(p_agent.workflow_definition);
    l_steps := l_workflow_def.get_array('steps');
    
    -- Initialize workflow state with _steps container
    l_workflow_state.put('_steps', l_steps_state);
    
    -- Execute steps in order
    <<step_loop>>
    for i in 0 .. l_steps.get_size - 1 loop
      l_step := treat(l_steps.get(i) as json_object_t);
      l_step_agent := l_step.get_string('agent_code');
      
      -- Check condition if present
      if l_step.has('condition') then
        l_condition := treat(l_step.get('condition') as json_object_t);
        l_condition_result := uc_ai_agent_workflow_api.evaluate_condition(l_condition, l_workflow_state);
        uc_ai_logger.log('Evaluating condition for step ' || l_step_agent || ': ' || case when l_condition_result then 'TRUE' else 'FALSE' end, l_scope);
        if not l_condition_result then
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
      l_step_input := uc_ai_agent_workflow_api.map_inputs(l_input_mapping, l_workflow_state, p_input_params);
      
      -- Execute step agent
      uc_ai_logger.log('Executing step: ' || l_step_agent || ' with input: ' || case when l_step_input is not null then l_step_input.to_string else 'null' end, l_scope);
      l_step_output := uc_ai_agents_api.execute_agent(
        p_agent_code       => l_step_agent,
        p_input_parameters => l_step_input,
        p_session_id       => p_session_id,
        p_parent_exec_id   => p_exec_id
      );
      
      -- Store step output using output_key
      if l_step.has('output_key') then
        l_output_key := l_step.get_string('output_key');
      else
        l_output_key := 'step_' || i;
      end if;
      
      -- Update _steps in workflow state
      l_steps_state := treat(l_workflow_state.get('_steps') as json_object_t);
      l_steps_state.put(l_output_key, l_step_output);
      l_workflow_state.put('_steps', l_steps_state);
      
      l_last_output := l_step_output;
      l_iteration := l_iteration + 1;
      
      uc_ai_logger.log('Step ' || l_output_key || ' completed with output: ' || case when l_step_output is not null then substr(l_step_output.to_string, 1, 500) else 'null' end, l_scope);
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
        
        l_step_output := uc_ai_agents_api.execute_agent(
          p_agent_code       => l_step_agent,
          p_input_parameters => l_workflow_state,
          p_session_id       => p_session_id,
          p_parent_exec_id   => p_exec_id
        );
        
        -- Merge output into state (feedback loop)
        uc_ai_agent_workflow_api.merge_outputs(null, l_step_output, l_workflow_state);
      end loop step_loop;
      
      l_iteration := l_iteration + 1;
      
      -- Check exit condition
      if l_exit_condition is not null then
        if uc_ai_agent_workflow_api.evaluate_condition(l_exit_condition, l_workflow_state) then
          uc_ai_logger.log('Exit condition met at iteration: ' || l_iteration, l_scope);
          exit iteration_loop;
        end if;
      end if;
    end loop iteration_loop;
    
    l_workflow_state.put('_loop_iterations', l_iteration);
    
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
        uc_ai_logger.log_error('Unknown workflow type: ' || l_workflow_type, l_scope);
        raise_application_error(-20011, 'Unknown workflow type: ' || l_workflow_type);
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
      l_agent := uc_ai_agents_api.get_agent(p_agent_code);
    exception
      when others then
        -- Agent might be a prompt profile
        null;
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
      where t.execution_id = p_exec_id
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
            l_result := uc_ai_agents_api.execute_agent(
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
            l_conversation := uc_ai_agent_workflow_api.manage_history(
              l_conversation, l_history_mgmt, p_session_id
            );
            
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
          
          l_mod_result := uc_ai_agents_api.execute_agent(
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
          
          l_result := uc_ai_agents_api.execute_agent(
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
          l_conversation := uc_ai_agent_workflow_api.manage_history(
            l_conversation, l_history_mgmt, p_session_id
          );
          
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

end uc_ai_agent_exec_api;
/
