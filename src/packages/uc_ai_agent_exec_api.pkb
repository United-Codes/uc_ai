create or replace package body uc_ai_agent_exec_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- Pending transfer requests of running handoff executions, keyed by the
  -- handoff wrapper's execution id (as string; ids can exceed pls_integer).
  -- Session-private package state: each slot lives only for the duration of
  -- one agent turn inside execute_handoff_agent and is cleared defensively on
  -- loop entry and in every error path.
  type t_transfer_requests is table of json_object_t index by varchar2(40 char);
  g_transfer_requests t_transfer_requests; -- @dblinter ignore(g-9105): package state map keyed by exec id, not a local collection


  -- ============================================================================
  -- Transfer Requests (for Handoff pattern)
  -- ============================================================================

  procedure record_transfer_request(
    p_handoff_exec_id in uc_ai_agent_executions.id%type,
    p_target_agent    in uc_ai_agents.code%type,
    p_context         in clob,
    p_reason          in varchar2 default null
  )
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'record_transfer_request';
    l_key     varchar2(40 char) := to_char(p_handoff_exec_id);
    l_request json_object_t := json_object_t();
  begin
    if g_transfer_requests.exists(l_key) then
      uc_ai_logger.log_warn(
        'Multiple transfer requests in one turn for handoff execution ' || l_key
        || ' - last one wins (new target: ' || p_target_agent || ')', l_scope);
    end if;

    l_request.put('target_agent', p_target_agent);
    l_request.put('context', p_context);
    if p_reason is not null then
      l_request.put('reason', p_reason);
    end if;
    g_transfer_requests(l_key) := l_request;

    uc_ai_logger.log('Transfer requested to agent ' || p_target_agent
      || ' (handoff execution ' || l_key || ')', l_scope, p_context);
  end record_transfer_request;


  function pop_transfer_request(
    p_handoff_exec_id in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_key     varchar2(40 char) := to_char(p_handoff_exec_id);
    l_request json_object_t;
  begin
    if g_transfer_requests.exists(l_key) then
      l_request := g_transfer_requests(l_key);
      g_transfer_requests.delete(l_key);
    end if;
    return l_request;
  end pop_transfer_request;


  procedure clear_transfer_request(
    p_handoff_exec_id in uc_ai_agent_executions.id%type
  )
  as
    l_key varchar2(40 char) := to_char(p_handoff_exec_id);
  begin
    if g_transfer_requests.exists(l_key) then
      g_transfer_requests.delete(l_key);
    end if;
  end clear_transfer_request;


  -- ============================================================================
  -- Private Helper Functions
  -- ============================================================================

  /*
   * True once a PL/SQL step has requested the workflow to stop via a
   * {"__control__": "stop"} return value (recorded as _control_stop in state).
   */
  function is_stopped(
    p_workflow_state in json_object_t
  ) return boolean
  as
  begin
    return p_workflow_state.has('_control_stop') and p_workflow_state.get_boolean('_control_stop');
  end is_stopped;


  /*
   * Executes an inline PL/SQL step. The whole workflow state is passed to the
   * snippet's single bind (conventionally :parameters) as a JSON CLOB - the
   * snippet navigates $.input / $.steps itself; there is no input_mapping.
   *
   * The returned CLOB is parsed to its real JSON type (object/array/scalar) and,
   * when output_key is present, stored under $.steps.<output_key> so downstream
   * steps can reference it. A returned object carrying "__control__": "stop"
   * halts the remaining workflow steps.
   *
   * po_step_output mirrors the agent step shape ({ final_message: <text> }) so the
   * shared executor logic (final message, iteration tracking) works unchanged.
   */
  procedure run_plsql_step(
    p_step             in json_object_t,
    pio_workflow_state in out nocopy json_object_t,
    po_step_output     out nocopy json_object_t
  )
  as
    l_scope       uc_ai_logger.scope := gc_scope_prefix || 'run_plsql_step';
    l_fc          clob;
    l_result_clob clob;
    l_result_elem json_element_t;
    l_output_key  varchar2(4000 char);
    l_steps_state json_object_t;
    l_control_obj json_object_t;
  begin
    l_fc := p_step.get_clob('plsql_function_call');
    uc_ai_logger.log('Executing PL/SQL step', l_scope, l_fc);

    begin
      l_result_clob := uc_ai_tools_api.exec_function_call(
        p_function_call => l_fc,
        p_arguments     => pio_workflow_state
      );
    exception
      when others then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_plsql_step_eval
        , p_scope      => l_scope
        , p0           => sqlerrm
        , p_extra      => l_fc || chr(10) || sys.dbms_utility.format_error_backtrace
        );
    end;

    uc_ai_logger.log('PL/SQL step result', l_scope, l_result_clob);

    -- Parse the result to its real JSON type so downstream steps see a number,
    -- boolean, object or array - not just text.
    begin
      -- objects and arrays parse directly
      l_result_elem := json_element_t.parse(l_result_clob);
    exception
      when others then -- @dblinter ignore(g-5040): parse failure is expected; fall back to scalar/string typing
        begin
          -- bare scalars (42, true, null) are not valid standalone JSON documents
          -- in some DB versions; wrap in an array to recover their real type
          l_result_elem := json_array_t.parse('[' || l_result_clob || ']').get(0);
        exception
          when others then -- @dblinter ignore(g-5040): not JSON at all; keep it as a plain string value
            declare
              l_wrap json_array_t := json_array_t();
            begin
              l_wrap.append(l_result_clob);
              l_result_elem := l_wrap.get(0);
            end;
        end;
    end;

    -- Store the typed result under output_key (optional for PL/SQL steps)
    if p_step.has('output_key') then
      l_output_key := p_step.get_string('output_key');
      if pio_workflow_state.has('steps') then
        l_steps_state := treat(pio_workflow_state.get('steps') as json_object_t);
      else
        l_steps_state := json_object_t();
      end if;
      l_steps_state.put(l_output_key, l_result_elem);
      pio_workflow_state.put('steps', l_steps_state);
    end if;

    -- Detect the stop directive
    if l_result_elem.is_object then
      l_control_obj := treat(l_result_elem as json_object_t);
      if l_control_obj.has('__control__') and l_control_obj.get_string('__control__') = 'stop' then
        pio_workflow_state.put('_control_stop', true);
        uc_ai_logger.log('PL/SQL step requested workflow stop', l_scope);
      end if;
    end if;

    -- Mirror the agent step output shape so the executors can treat it uniformly
    po_step_output := json_object_t();
    po_step_output.put('final_message', l_result_clob);
  end run_plsql_step;


  /*
   * Executes a single workflow step. A step either delegates to an agent (default,
   * step_type = 'agent') or runs an inline PL/SQL snippet (step_type = 'plsql').
   * Sets po_step_output to null if the step was skipped due to a condition.
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
    l_step_type        varchar2(20 char);
    l_step_agent       varchar2(255 char);
    l_step_label       varchar2(255 char);
    l_input_mapping    json_object_t;
    l_step_input       json_object_t;
    l_condition        varchar2(32676 char);
    l_condition_result boolean;
    l_log_msg          varchar2(4000 char);
  begin
    l_step_type  := coalesce(p_step.get_string('step_type'), uc_ai_agent_exec_api.c_step_agent);
    l_step_agent := p_step.get_string('agent_code');

    -- Step label used for logging and checkpointing (agent_code is not present on PL/SQL steps)
    l_step_label := coalesce(
      p_step.get_string('step_id'),
      l_step_agent,
      p_step.get_string('output_key'),
      l_step_type
    );

    -- Check condition if requested and present
    if p_check_condition and p_step.has('condition') then
      l_condition := p_step.get_string('condition');
      l_condition_result := uc_ai_agent_workflow_api.evaluate_condition(l_condition, pio_workflow_state);
      uc_ai_logger.log('Evaluating condition for step ' || l_step_label || ': ' || case when l_condition_result then 'TRUE' else 'FALSE' end, l_scope);
      if not l_condition_result then
        uc_ai_logger.log('Skipping step due to condition: ' || l_step_label, l_scope);
        po_step_output := null;
        return;
      end if;
    end if;

    case l_step_type
      when uc_ai_agent_exec_api.c_step_plsql then
        run_plsql_step(
          p_step             => p_step,
          pio_workflow_state => pio_workflow_state,
          po_step_output     => po_step_output
        );

      when uc_ai_agent_exec_api.c_step_agent then
        -- Map inputs
        if p_step.has('input_mapping') then
          l_input_mapping := treat(p_step.get('input_mapping') as json_object_t);
        else
          l_input_mapping := null;
        end if;
        l_step_input := uc_ai_agent_workflow_api.map_inputs(l_input_mapping, pio_workflow_state);

        -- Log execution
        l_log_msg := case when p_log_prefix is not null then p_log_prefix || ', executing' else 'Executing' end ||
                     ' step: ' || l_step_label || ' with input:';
        uc_ai_logger.log(l_log_msg, l_scope, case when l_step_input is not null then l_step_input.to_clob else 'null' end);

        -- Execute step agent
        po_step_output := uc_ai_agents_api.execute_agent(
          p_agent_code       => l_step_agent,
          p_input_parameters => l_step_input,
          p_session_id       => p_session_id,
          p_parent_exec_id   => p_exec_id
        );

        uc_ai_logger.log('Step ' || l_step_label || ' completed with output:', l_scope, po_step_output.to_clob);

        -- Add result to workflow state
        uc_ai_agent_workflow_api.add_result_to_workflow_state(
          p_step             => p_step,
          p_step_output      => po_step_output,
          pio_workflow_state => pio_workflow_state
        );

      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'step_type'
        , p1           => 'Unknown step_type: ' || l_step_type
        );
    end case;

    -- persist state so running workflows can be monitored and failed ones diagnosed
    uc_ai_agents_api.checkpoint_execution(
      p_exec_id       => p_exec_id,
      p_current_state => pio_workflow_state,
      p_last_step     => l_step_label
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
      -- A prior PL/SQL step may have requested the workflow to stop
      exit step_loop when is_stopped(l_workflow_state);

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
    l_final_msg       clob;
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
      c_default_max_iterations
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
        exit pre_step_loop when is_stopped(l_workflow_state);
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
        -- A PL/SQL step may request the whole workflow to stop
        exit iteration_loop when is_stopped(l_workflow_state);

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

      -- clone: append of a parented node copies on 23ai, but that is
      -- undocumented JSON DOM behavior - make the per-iteration snapshot explicit
      l_step_state := treat(l_workflow_state.get_object('steps').clone as json_object_t);
      l_iteration_array.append(l_step_state);
    end loop iteration_loop;
    
    l_workflow_state.put('_loop_iterations', l_iteration);
    l_workflow_state.put('_loop_iteration_state', l_iteration_array);


    if l_workflow_def.has('post_steps') then
      l_steps := l_workflow_def.get_array('post_steps');
      <<post_step_loop>>
      for i in 0 .. l_steps.get_size - 1 loop
        exit post_step_loop when is_stopped(l_workflow_state);
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
      -- Default final message from last executed step. l_step_output is null when
      -- no step ran (e.g. zero iterations / empty step list) - guard against it.
      if l_step_output is not null and l_step_output.has('final_message') then
        l_workflow_state.put('final_message', l_step_output.get_clob('final_message'));
      end if;
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
   * Loads previous conversation messages from the latest completed execution
   * in the given session for the given agent.
   *
   * Returns null if no previous execution found.
   */
  function load_previous_messages(
    p_session_id in varchar2,
    p_agent_id   in uc_ai_agents.id%type,
    p_exec_id    in uc_ai_agent_executions.id%type
  ) return json_array_t
  as
    l_scope       uc_ai_logger.scope := gc_scope_prefix || 'load_previous_messages';
    l_prev_output clob;
    l_prev_result json_object_t;
  begin
    begin
      select output_result
        into l_prev_output
        from uc_ai_agent_executions
       where session_id = p_session_id
         and agent_id   = p_agent_id
         and status     = uc_ai_agents_api.c_exec_completed
         and id        != p_exec_id
       order by completed_at desc
       fetch first 1 row only;
    exception
      when no_data_found then
        return null;
    end;

    l_prev_result := json_object_t.parse(l_prev_output);

    if not l_prev_result.has('messages') then
      uc_ai_logger.log_warn('Previous execution has no messages array', l_scope);
      return null;
    end if;

    return l_prev_result.get_array('messages');
  exception
    when others then
      uc_ai_logger.log_error('Error loading previous messages', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end load_previous_messages;


  /*
   * Applies history management to a messages array based on agent configuration.
   */
  function apply_history_management(
    p_messages   in json_array_t,
    p_agent      in uc_ai_agents%rowtype,
    p_session_id in varchar2
  ) return json_array_t
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'apply_history_management';
    l_history_mgmt json_object_t;
    l_config       json_object_t;
  begin
    -- Check orchestration_config for history_management
    if p_agent.orchestration_config is not null then
      l_config := json_object_t.parse(p_agent.orchestration_config);
      if l_config.has('history_management') then
        l_history_mgmt := l_config.get_object('history_management');
      end if;
    end if;

    -- Fall back to max_history_messages as sliding_window
    if l_history_mgmt is null and p_agent.max_history_messages is not null then
      l_history_mgmt := json_object_t();
      l_history_mgmt.put('strategy', 'sliding_window');
      l_history_mgmt.put('max_messages', p_agent.max_history_messages);
    end if;

    if l_history_mgmt is null then
      return p_messages;
    end if;

    return uc_ai_agent_workflow_api.manage_history(
      p_history            => p_messages,
      p_history_management => l_history_mgmt,
      p_session_id         => p_session_id
    );
  exception
    when others then
      uc_ai_logger.log_error('Error applying history management', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end apply_history_management;


  /*
   * Executes a profile-type agent (wrapper around prompt profile)
   */
  function execute_profile_agent(
    p_agent             in uc_ai_agents%rowtype,
    p_input_params      in json_object_t,
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_response_schema   in json_object_t default null,
    p_follow_up_message in clob default null,
    p_session_id        in varchar2 default null,
    p_files             in uc_ai_message_api.t_files default null,
    p_extra_tool_tag    in varchar2 default null
  ) return json_object_t
  as
    l_scope           uc_ai_logger.scope := gc_scope_prefix || 'execute_profile_agent';
    l_result          json_object_t;
    l_config          json_object_t;
    l_has_schema      number;
    l_final_message   clob;
    l_messages        json_array_t;
    l_provider        uc_ai_prompt_profiles.provider%type;
    l_model           uc_ai_prompt_profiles.model%type;
    l_response_schema json_object_t;
  begin
    uc_ai_logger.log('Executing profile agent: ' || p_agent.code, l_scope);

    -- Merge an engine-supplied extra tool tag (handoff transfer tools) into the
    -- profile's OWN model config. This must go through p_config_override:
    -- apply_model_config resets all session globals on every profile execution,
    -- and an override REPLACES model_config_json - so the profile's own tags
    -- are carried over explicitly and the extra tag is appended.
    if p_extra_tool_tag is not null then
      declare
        l_profile uc_ai_prompt_profiles%rowtype;
        l_tags    json_array_t;
      begin
        l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
          p_code    => p_agent.prompt_profile_code,
          p_version => p_agent.prompt_profile_version
        );
        l_config := json_object_t.parse(coalesce(l_profile.model_config_json, '{}'));

        if l_config.has('g_tool_tags') then
          l_tags := l_config.get_array('g_tool_tags');
        else
          l_tags := json_array_t();
        end if;
        l_tags.append(p_extra_tool_tag);

        l_config.put('g_tool_tags', l_tags);
        l_config.put('g_enable_tools', true);
      end;
    end if;

    -- Conversation continuation path
    if p_follow_up_message is not null and p_session_id is not null then
      uc_ai_logger.log('Continuing conversation for session: ' || p_session_id, l_scope);

      -- Load previous conversation messages
      l_messages := load_previous_messages(p_session_id, p_agent.id, p_exec_id);

      if l_messages is null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'follow_up_message'
        , p1           => 'no previous completed execution found in session ' || p_session_id
        );
      end if;

      -- Apply history management
      l_messages := apply_history_management(l_messages, p_agent, p_session_id);

      -- Append new user message (with any attached files)
      l_messages.append(uc_ai_message_api.create_user_message(p_follow_up_message, p_files));

      -- Prepare profile context (applies model config, returns provider/model/schema)
      if p_response_schema is not null then
        if l_config is null then
          l_config := json_object_t();
        end if;
        l_config.put('response_schema', p_response_schema);
      end if;

      uc_ai_prompt_profiles_api.prepare_profile_context(
        p_code             => p_agent.prompt_profile_code,
        p_version          => p_agent.prompt_profile_version,
        p_config_override  => l_config,
        po_provider        => l_provider,
        po_model           => l_model,
        po_response_schema => l_response_schema
      );

      -- Override response schema if explicitly provided
      if p_response_schema is not null then
        l_response_schema := p_response_schema;
      end if;

      -- Call generate_text with the full messages array
      l_result := uc_ai.generate_text(
        p_messages              => l_messages,
        p_provider              => l_provider,
        p_model                 => l_model,
        p_max_tool_calls        => uc_ai.g_max_tool_calls,
        p_response_json_schema  => l_response_schema
      );

      -- Parse final_message as JSON if response schema is set
      if l_response_schema is not null then
        l_final_message := l_result.get_clob('final_message');
        l_result.put('final_message', json_object_t.parse(l_final_message));
      end if;

      return l_result;
    end if;

    -- Original first-call path
    if p_response_schema is not null then
      if l_config is null then
        l_config := json_object_t();
      end if;
      l_config.put('response_schema', p_response_schema);
    end if;

    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code            => p_agent.prompt_profile_code,
      p_version         => p_agent.prompt_profile_version,
      p_parameters      => p_input_params,
      p_config_override => l_config,
      p_files           => p_files
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
        -- True parallel execution is not implemented yet (DBMS_PARALLEL_EXECUTE /
        -- scheduler jobs). Steps run sequentially, in definition order. This is
        -- surfaced both in the log and in the returned state so callers are not
        -- misled into assuming concurrency.
        declare
          l_result json_object_t;
        begin
          uc_ai_logger.log_warn('Parallel workflow executing sequentially (parallel not yet implemented)', l_scope);
          l_result := execute_sequential_workflow(p_agent, p_input_params, p_session_id, p_exec_id);
          l_result.put('_executed_sequentially', true);
          return l_result;
        end;
        
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
    l_scope           uc_ai_logger.scope := gc_scope_prefix || 'register_agent_as_tool';
    l_tool_id         uc_ai_tools.id%type;
    l_function_call   clob;
    l_agent           uc_ai_agents%rowtype;
    -- values are baked into the generated PL/SQL body as single-quoted literals;
    -- double any embedded quote so they cannot break out of the literal
    l_safe_agent_code varchar2(4000 char) := replace(p_agent_code, '''', '''''');
    l_safe_session_id varchar2(4000 char) := replace(p_session_id, '''', '''''');
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
    p_agent_code       => '!' || l_safe_agent_code || q'!',
    p_input_parameters => l_input,
    p_session_id       => '!' || l_safe_session_id || q'!',
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
      p_created_by   => 'UC_AI_AGENT_EXEC_API',
      -- direct only: delegating to a sub-agent costs LLM calls, so it stays a
      -- deliberate decision of the calling model instead of something a code-mode
      -- program can loop over unsupervised
      p_code_mode_access => 'direct'
    );

    return l_tool_id;
  exception
    when others then
      uc_ai_logger.log_error('Error registering agent as tool', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end register_agent_as_tool;


  /*
   * Registers a temporary transfer_to_<agent> tool for the handoff pattern.
   * The tool does NOT execute the target agent - it only records the transfer
   * request; execute_handoff_agent performs the actual switch after the
   * current agent's turn ends.
   */
  function register_transfer_tool(
    p_target_code     in uc_ai_agents.code%type,
    p_description     in uc_ai_agents.description%type,
    p_handoff_exec_id in uc_ai_agent_executions.id%type,
    p_tool_tag        in varchar2
  ) return uc_ai_tools.id%type
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'register_transfer_tool';
    l_tool_id       uc_ai_tools.id%type;
    l_function_call clob;
    l_schema        json_object_t;
    -- values are baked into the generated PL/SQL body as single-quoted literals;
    -- double any embedded quote so they cannot break out of the literal
    l_safe_target   varchar2(4000 char) := replace(p_target_code, '''', '''''');
  begin
    uc_ai_logger.log('Registering transfer tool for agent: ' || p_target_code, l_scope);

    l_function_call := q'!
declare
  l_input json_object_t;
begin
  l_input := json_object_t(:arguments);

  uc_ai_agent_exec_api.record_transfer_request(
    p_handoff_exec_id => !' || p_handoff_exec_id || q'!,
    p_target_agent    => '!' || l_safe_target || q'!',
    p_context         => l_input.get_clob('context'),
    p_reason          => l_input.get_string('reason')
  );

  return 'Transfer to !' || l_safe_target || q'! initiated. Briefly acknowledge the transfer and end your turn; the specialist will answer the user.';
end;!';

    l_schema := json_object_t('{
      "type": "object",
      "properties": {
        "context": {
          "type": "string",
          "description": "Summary of the user''s request and all details the specialist needs to answer it"
        },
        "reason": {
          "type": "string",
          "description": "Short reason why this specialist should take over"
        }
      },
      "required": ["context"]
    }');

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => 'transfer_to_' || lower(p_target_code) || '_' || p_handoff_exec_id,
      p_description   => 'Transfer the conversation to the specialist agent "' || p_target_code
                         || '". Use for: ' || p_description,
      p_function_call => l_function_call,
      p_json_schema   => l_schema,
      p_active        => 1,
      p_tags          => apex_t_varchar2(p_tool_tag),
      p_created_by    => 'UC_AI_AGENT_EXEC_API',
      -- handing the conversation to another agent is never a code-mode operation
      p_code_mode_access => 'direct'
    );

    return l_tool_id;
  exception
    when others then
      uc_ai_logger.log_error('Error registering transfer tool', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end register_transfer_tool;


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
    p_agent             in uc_ai_agents%rowtype,
    p_input_params      in json_object_t,
    p_session_id        in varchar2,
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_follow_up_message in clob default null,
    p_files             in uc_ai_message_api.t_files default null
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
    l_messages         json_array_t;
    l_provider         uc_ai_prompt_profiles.provider%type;
    l_model            uc_ai_prompt_profiles.model%type;
    l_response_schema  json_object_t;
  begin
    uc_ai_logger.log('Executing orchestrator agent: ' || p_agent.code, l_scope);

    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_delegates := l_config.get_array('delegate_agents');
    l_profile_code := l_config.get_string('orchestrator_profile_code');
    l_tool_tag := lower('orchestrator_' || p_agent.code || '_' || sys_guid());

    l_prompt_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code    => l_profile_code
    );

    -- Save original tool settings so they can be restored afterwards. Without
    -- this, the session-level tool globals leak (get nulled) after every
    -- orchestrator run and corrupt any later generate_text call in the session.
    l_original_tools := uc_ai.g_enable_tools;
    l_original_tags  := uc_ai.g_tool_tags;

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

      -- Conversation continuation path
      if p_follow_up_message is not null then
        uc_ai_logger.log('Continuing orchestrator conversation for session: ' || p_session_id, l_scope);

        l_messages := load_previous_messages(p_session_id, p_agent.id, p_exec_id);

        if l_messages is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_invalid_config
          , p_scope      => l_scope
          , p0           => 'follow_up_message'
          , p1           => 'no previous completed execution found in session ' || p_session_id
          );
        end if;

        -- Apply history management
        l_messages := apply_history_management(l_messages, p_agent, p_session_id);

        -- Append new user message (with any attached files)
        l_messages.append(uc_ai_message_api.create_user_message(p_follow_up_message, p_files));

        -- Prepare profile context
        uc_ai_prompt_profiles_api.prepare_profile_context(
          p_code             => l_profile_code,
          p_config_override  => l_profile_config,
          po_provider        => l_provider,
          po_model           => l_model,
          po_response_schema => l_response_schema
        );

        -- Call generate_text with messages directly
        l_result := uc_ai.generate_text(
          p_messages              => l_messages,
          p_provider              => l_provider,
          p_model                 => l_model,
          p_max_tool_calls        => uc_ai.g_max_tool_calls,
          p_response_json_schema  => l_response_schema
        );
      else
        -- Original first-call path: execute orchestrator profile
        l_result := uc_ai_prompt_profiles_api.execute_profile(
          p_code              => l_profile_code,
          p_parameters        => p_input_params,
          p_config_override   => l_profile_config,
          p_files             => p_files
        );
      end if;

    exception
      when others then
        -- Always cleanup, even on error
        uc_ai_logger.log_error('Error during orchestrator execution', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
        cleanup_agent_tools(l_tool_ids);
        -- Restore original tool settings before propagating the error
        uc_ai.g_enable_tools := l_original_tools;
        uc_ai.g_tool_tags := l_original_tags;
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
   * Resolves the active agent for a follow-up turn of a handoff agent: the
   * agent that produced the final answer of the wrapper's last completed
   * execution in the session (sticky active agent). Returns null when there
   * is no previous completed execution or it carries no final_agent_code.
   */
  function resolve_active_agent(
    p_session_id in varchar2,
    p_agent_id   in uc_ai_agents.id%type,
    p_exec_id    in uc_ai_agent_executions.id%type
  ) return varchar2
  as
    l_scope       uc_ai_logger.scope := gc_scope_prefix || 'resolve_active_agent';
    l_prev_output clob;
    l_prev_result json_object_t;
  begin
    begin
      select output_result
        into l_prev_output
        from uc_ai_agent_executions
       where session_id = p_session_id
         and agent_id   = p_agent_id
         and status     = uc_ai_agents_api.c_exec_completed
         and id        != p_exec_id
       order by completed_at desc
       fetch first 1 row only;
    exception
      when no_data_found then
        return null;
    end;

    l_prev_result := json_object_t.parse(l_prev_output);
    return l_prev_result.get_string('final_agent_code');
  exception
    when others then
      uc_ai_logger.log_error('Error resolving active agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end resolve_active_agent;


  /*
   * Executes a handoff-type agent (Swarm-style tool-based transfers).
   *
   * The engine registers a temporary transfer_to_<agent> tool per ALLOWED
   * handoff target for the currently active agent's LLM call. When the model
   * calls one, the callback records the request (see record_transfer_request)
   * and the engine switches to the target agent, threading the original input,
   * the transfer context and the conversation trail. When no transfer is
   * requested, the agent's answer is final.
   *
   * Allowed targets: a handoff_agents entry may carry "can_transfer_to" (array
   * of agent codes) restricting its outgoing edges - this expresses multi-level
   * hierarchies (triage -> product support -> product technician). Without it
   * an agent may transfer to every other entry (full mesh).
   *
   * Follow-up turns (p_follow_up_message) resume with the agent that answered
   * the previous turn (sticky active agent, see resolve_active_agent); it keeps
   * its transfer tools so it can hand off when the topic changed.
   *
   * The hop at max_handoffs runs WITHOUT transfer tools and must answer
   * (graceful cap, no error); the result then carries max_handoffs_reached.
   */
  function execute_handoff_agent(
    p_agent             in uc_ai_agents%rowtype,
    p_input_params      in json_object_t,
    p_session_id        in varchar2,
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_follow_up_message in clob default null
  ) return json_object_t
  as
    l_scope                uc_ai_logger.scope := gc_scope_prefix || 'execute_handoff_agent';
    l_config               json_object_t;
    l_handoff_agents       json_array_t;
    l_target               json_object_t;
    l_target_code          varchar2(255 char);
    l_current_agent        varchar2(255 char);
    l_handoff_count        number := 0;
    l_max_handoffs         number;
    l_conversation_history json_array_t := json_array_t();
    l_handoff_trail        json_array_t := json_array_t();
    l_result               json_object_t;
    l_transfer             json_object_t;
    l_current_input        json_object_t;
    l_history_mgmt         json_object_t;
    l_combined_messages    json_array_t := json_array_t();
    l_tool_ids             apex_t_number;
    l_tool_tag             varchar2(255 char);
    l_allowed              json_array_t;
    l_first_hop            boolean := true;
    l_is_follow_up         boolean := p_follow_up_message is not null;

    type t_entry_map is table of json_object_t index by varchar2(255 char);
    l_entries t_entry_map; -- @dblinter ignore(g-9105): handoff_agents entries keyed by agent code, not a local array

    /*
     * True when the current agent may transfer to p_code: either it has no
     * can_transfer_to list (full mesh) or p_code is listed.
     */
    function is_allowed_target(
      p_code    in varchar2,
      p_allowed in json_array_t
    ) return boolean
    as
    begin
      if p_allowed is null then
        return true;
      end if;
      <<allowed_loop>>
      for i in 0 .. p_allowed.get_size - 1 loop
        if p_allowed.get_string(i) = p_code then
          return true;
        end if;
      end loop allowed_loop;
      return false;
    end is_allowed_target;

    /*
     * Appends one hop's messages to the combined turn log. The first hop is
     * taken in full; later hops contribute only the entries AFTER their first
     * 'user' message (their composed prompts are engine-internal). This leaves
     * exactly one user message - the original one - so persist_turn_messages
     * (which persists from the LAST user message onward) records the whole
     * chain including the transfer tool calls.
     *
     * Each appended message is stamped with the hop's agent code so the
     * message log attributes it to the specialist that produced it (the
     * transfer tool_call names the target; agentCode names the producer).
     * persist_turn_messages nulls attribution for user/system rows regardless.
     */
    procedure append_hop_messages(
      p_hop_result in json_object_t,
      p_first_hop  in boolean,
      p_agent_code in varchar2
    )
    as
      l_messages  json_array_t;
      l_msg       json_object_t;
      l_seen_user boolean := false;

      procedure append_stamped(p_element in json_element_t)
      as
        l_m json_object_t;
      begin
        l_m := treat(p_element as json_object_t);
        l_m.put('agentCode', p_agent_code);
        l_combined_messages.append(l_m);
      end append_stamped;
    begin
      if not p_hop_result.has('messages') then
        return;
      end if;
      l_messages := p_hop_result.get_array('messages');

      <<hop_messages>>
      for i in 0 .. l_messages.get_size - 1 loop
        if p_first_hop then
          append_stamped(l_messages.get(i));
        elsif l_seen_user then
          append_stamped(l_messages.get(i));
        else
          l_msg := treat(l_messages.get(i) as json_object_t);
          if l_msg.has('role') and l_msg.get_string('role') = 'user' then
            l_seen_user := true;
          end if;
        end if;
      end loop hop_messages;
    end append_hop_messages;
  begin
    uc_ai_logger.log('Executing handoff agent: ' || p_agent.code, l_scope);

    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_current_agent := l_config.get_string('initial_agent_code');
    l_handoff_agents := l_config.get_array('handoff_agents');
    l_max_handoffs := coalesce(l_config.get_number('max_handoffs'), c_default_max_handoffs);

    if l_config.has('history_management') then
      l_history_mgmt := l_config.get_object('history_management');
    end if;

    -- Index handoff_agents entries by code for graph lookups
    <<entry_loop>>
    for i in 0 .. l_handoff_agents.get_size - 1 loop
      l_target := treat(l_handoff_agents.get(i) as json_object_t);
      l_entries(l_target.get_string('agent_code')) := l_target;
    end loop entry_loop;

    -- Sticky active agent: a follow-up turn resumes with the agent that
    -- answered the previous turn (falls back to the initial agent when it is
    -- unknown or no longer part of the handoff mesh).
    if l_is_follow_up then
      declare
        l_active varchar2(255 char);
      begin
        l_active := resolve_active_agent(p_session_id, p_agent.id, p_exec_id);
        if l_active is not null
          and (l_entries.exists(l_active) or l_active = l_current_agent)
        then
          l_current_agent := l_active;
        end if;
        uc_ai_logger.log('Handoff follow-up resumes with agent: ' || l_current_agent, l_scope);
      end;
    end if;

    l_current_input := p_input_params;
    if l_current_input is null then
      l_current_input := json_object_t();
    end if;

    -- Defensive: a previous failed run in this session must not leak its
    -- transfer request into this one (exec ids are unique, so this is belt
    -- and braces only).
    clear_transfer_request(p_exec_id);

    <<handoff_loop>>
    loop
      l_tool_ids := apex_t_number();
      l_tool_tag := lower('handoff_' || p_agent.code || '_' || p_exec_id || '_' || l_handoff_count);

      begin
        -- Register transfer tools for every OTHER allowed handoff target
        -- (the current agent's can_transfer_to edges; full mesh minus self
        -- when absent). At the cap the agent runs without them and must
        -- answer.
        if l_handoff_count < l_max_handoffs then
          l_allowed := null;
          if l_entries.exists(l_current_agent)
            and l_entries(l_current_agent).has('can_transfer_to')
          then
            l_allowed := l_entries(l_current_agent).get_array('can_transfer_to');
          end if;

          <<target_loop>>
          for i in 0 .. l_handoff_agents.get_size - 1 loop
            l_target := treat(l_handoff_agents.get(i) as json_object_t);
            l_target_code := l_target.get_string('agent_code');
            if l_target_code != l_current_agent
              and is_allowed_target(l_target_code, l_allowed)
            then
              l_tool_ids.extend;
              l_tool_ids(l_tool_ids.count) := register_transfer_tool(
                p_target_code     => l_target_code,
                p_description     => l_target.get_string('description'),
                p_handoff_exec_id => p_exec_id,
                p_tool_tag        => l_tool_tag
              );
            end if;
          end loop target_loop;
        end if;

        -- Execute current agent (nested execution records its own tokens).
        -- The first hop of a follow-up turn resumes the active agent's own
        -- conversation via the profile follow-up path.
        if l_first_hop and l_is_follow_up then
          l_result := uc_ai_agents_api.execute_agent(
            p_agent_code        => l_current_agent,
            p_follow_up_message => p_follow_up_message,
            p_session_id        => p_session_id,
            p_parent_exec_id    => p_exec_id,
            p_extra_tool_tag    => case when l_tool_ids.count > 0 then l_tool_tag end
          );
        else
          l_result := uc_ai_agents_api.execute_agent(
            p_agent_code       => l_current_agent,
            p_input_parameters => l_current_input,
            p_session_id       => p_session_id,
            p_parent_exec_id   => p_exec_id,
            p_extra_tool_tag   => case when l_tool_ids.count > 0 then l_tool_tag end
          );
        end if;
      exception
        when others then
          cleanup_agent_tools(l_tool_ids);
          clear_transfer_request(p_exec_id);
          raise;
      end;

      cleanup_agent_tools(l_tool_ids);

      append_hop_messages(l_result, p_first_hop => l_first_hop, p_agent_code => l_current_agent);
      l_first_hop := false;

      -- Add to conversation trail
      l_conversation_history.append(json_object_t(
        json_object(
          'agent' value l_current_agent,
          'response' value l_result.get_clob('final_message')
        )
      ));

      if l_history_mgmt is not null then
        l_conversation_history := uc_ai_agent_workflow_api.manage_history(
          l_conversation_history, l_history_mgmt, p_session_id
        );
      end if;

      -- Did the agent request a transfer?
      l_transfer := pop_transfer_request(p_exec_id);
      exit handoff_loop when l_transfer is null;

      l_handoff_count := l_handoff_count + 1;

      declare
        l_trail_entry json_object_t := json_object_t();
      begin
        l_trail_entry.put('hop', l_handoff_count);
        l_trail_entry.put('from_agent', l_current_agent);
        l_trail_entry.put('to_agent', l_transfer.get_string('target_agent'));
        if l_transfer.has('reason') then
          l_trail_entry.put('reason', l_transfer.get_string('reason'));
        end if;
        l_trail_entry.put('context', l_transfer.get_clob('context'));
        l_handoff_trail.append(l_trail_entry);
      end;

      -- Prepare the next hop's input: original input + transfer context +
      -- conversation trail (TOON-encoded, token-efficient). Targets opt in
      -- via {handoff_context} / {handoff_from} / {conversation_history}
      -- template placeholders; extra parameters without placeholders are
      -- silently ignored. On follow-up turns (no input params) the follow-up
      -- message becomes the "prompt" parameter for the receiving hop.
      if p_input_params is not null then
        l_current_input := json_object_t.parse(p_input_params.to_clob);
      else
        l_current_input := json_object_t();
        if l_is_follow_up then
          l_current_input.put('prompt', p_follow_up_message);
        end if;
      end if;
      l_current_input.put('handoff_context', l_transfer.get_clob('context'));
      l_current_input.put('handoff_from', l_current_agent);
      l_current_input.put('conversation_history', uc_ai_toon.to_toon(l_conversation_history));

      l_current_agent := l_transfer.get_string('target_agent');

      declare
        l_checkpoint json_object_t := json_object_t();
      begin
        l_checkpoint.put('handoff_count', l_handoff_count);
        l_checkpoint.put('current_agent', l_current_agent);
        l_checkpoint.put('handoff_trail', l_handoff_trail);
        uc_ai_agents_api.checkpoint_execution(
          p_exec_id       => p_exec_id,
          p_current_state => l_checkpoint,
          p_last_step     => 'handoff_' || l_handoff_count
        );
      end;
    end loop handoff_loop;

    -- The wrapper made no LLM calls itself: its child executions own all
    -- tokens. Leaving the last child's usage in place would double-count it
    -- on this execution row (see execute_agent's token extraction).
    l_result.remove('usage');

    l_result.put('messages', l_combined_messages);
    l_result.put('conversation_history', l_conversation_history);
    l_result.put('handoff_count', l_handoff_count);
    l_result.put('handoff_trail', l_handoff_trail);
    l_result.put('final_agent_code', l_current_agent);
    l_result.put('max_handoffs_reached', l_handoff_count >= l_max_handoffs);

    return l_result;
  exception
    when others then
      clear_transfer_request(p_exec_id);
      uc_ai_logger.log_error('Error executing handoff agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
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

    /*
     * Turns the internal conversation log (each entry: agent, role, message,
     * turn) into a standard messages array so persist_turn_messages records
     * the full debate instead of collapsing it to one summary row. The opening
     * 'system' entry (the caller's input) becomes a 'user' message with no
     * producing agent; every participant turn becomes an 'assistant' message
     * stamped with its 'agentCode' for attribution.
     */
    function conversation_to_messages(
      p_conversation in json_array_t
    ) return json_array_t
    as
      l_messages json_array_t := json_array_t();
      l_entry    json_object_t;
      l_msg_val  json_element_t;
      l_out      json_object_t;
      l_agent_cd varchar2(255 char);
      l_content  clob;
    begin
      <<conv_entries>>
      for i in 0 .. p_conversation.get_size - 1 loop
        l_entry := treat(p_conversation.get(i) as json_object_t);
        l_agent_cd := l_entry.get_string('agent');

        -- Message payload may be a scalar (participant text) or the input
        -- object (opening 'system' entry); serialize objects losslessly.
        l_msg_val := l_entry.get('message');
        if l_msg_val is not null and l_msg_val.is_string then
          l_content := l_entry.get_clob('message');
        elsif l_msg_val is not null then
          l_content := l_msg_val.to_clob;
        else
          l_content := null;
        end if;

        l_out := json_object_t();
        if l_agent_cd = 'system' then
          l_out.put('role', 'user');
        else
          l_out.put('role', 'assistant');
          l_out.put('agentCode', l_agent_cd);
        end if;
        l_out.put('content', l_content);
        l_messages.append(l_out);
      end loop conv_entries;

      return l_messages;
    end conversation_to_messages;

  begin
    uc_ai_logger.log('Executing conversation agent: ' || p_agent.code, l_scope);
    
    l_config := json_object_t.parse(p_agent.orchestration_config);
    l_mode := l_config.get_string('conversation_mode');
    l_participants := l_config.get_array('agents');
    l_max_turns := coalesce(l_config.get_number('max_turns'), c_default_max_turns);
    
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

          declare
            l_checkpoint json_object_t := json_object_t();
          begin
            l_checkpoint.put('turn', l_turn_count);
            l_checkpoint.put('conversation', l_conversation);
            uc_ai_agents_api.checkpoint_execution(
              p_exec_id       => p_exec_id,
              p_current_state => l_checkpoint,
              p_last_step     => 'turn_' || l_turn_count
            );
          end;
        end loop turn_loop;

        l_return := json_object_t();
        l_return.put('conversation', l_conversation);
        l_return.put('turns', l_turn_count);
        l_return.put('completed', true);
        l_return.put('final_message', l_result.get_string('final_message'));
        -- Full transcript for the message log; the terminal participant turn is
        -- already the final_message, so no extra summary row is appended.
        l_return.put('messages', conversation_to_messages(l_conversation));

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

          declare
            l_checkpoint json_object_t := json_object_t();
          begin
            l_checkpoint.put('turn', l_turn_count);
            l_checkpoint.put('conversation', l_conversation);
            uc_ai_agents_api.checkpoint_execution(
              p_exec_id       => p_exec_id,
              p_current_state => l_checkpoint,
              p_last_step     => 'turn_' || l_turn_count
            );
          end;
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

        -- Full transcript for the message log: the debate plus the moderator's
        -- closing summary (produced after the loop, so not in l_conversation),
        -- attributed to the moderator agent.
        declare
          l_msgs    json_array_t := conversation_to_messages(l_conversation);
          l_summary json_object_t := json_object_t();
        begin
          l_summary.put('role', 'assistant');
          l_summary.put('agentCode', l_moderator_code);
          l_summary.put('content', l_mod_result.get_string('final_message'));
          l_msgs.append(l_summary);
          l_return.put('messages', l_msgs);
        end;
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
    l_app_id number;
    l_ws_name apex_applications.workspace_display_name%type;
    l_sec_id number;
  begin
    if apex_application.g_instance is null then
      begin
        select workspace_display_name, application_id
          into l_ws_name, l_app_id
          from apex_applications
         where workspace_display_name != 'INTERNAL' -- if the user had admin read role, don't return the internal workspace apps
         fetch first 1 row only;
      exception
        when no_data_found then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_apex_session
          , p_scope      => gc_scope_prefix || 'create_apex_session_if_needed'
          );
      end;

      l_sec_id := apex_util.find_security_group_id(p_workspace => l_ws_name);
      apex_util.set_security_group_id (p_security_group_id => l_sec_id);

      apex_session.create_session(
        p_app_id       => l_app_id,
        p_page_id      => 0,
        p_username     => c_synthetic_apex_user
      );
    end if;
  end create_apex_session_if_needed;

end uc_ai_agent_exec_api;
/
