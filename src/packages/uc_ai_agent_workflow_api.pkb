create or replace package body uc_ai_agent_workflow_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  /*
   * Resolves a JSONPath-style expression against workflow context
   * Supports: $.input.field, $.steps.step_name.field
   */
  function resolve_jsonpath_values(
    p_expression     in varchar2,
    p_workflow_state in json_object_t
  ) return varchar2
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'resolve_jsonpath_values';
    l_expr       varchar2(4000 char);
    l_eval       varchar2(32767 char);
    l_res        varchar2(32767 char);
    l_expr_arr apex_t_varchar2;

    l_apex_json apex_json.t_values;
  begin
    -- get list of {$.path} expressions
    l_expr_arr := apex_string.grep (
                     p_str => p_expression,
                     p_pattern => '\{(\$\.[^\}]+)\}',
                     p_modifier => 'i',	
                     p_subexpression => '1'
                   );

    if l_expr_arr is null or l_expr_arr.count = 0 then
      -- No expressions to resolve
      return p_expression;
    end if;

    apex_json.parse(l_apex_json, p_workflow_state.to_clob);
    l_res := p_expression;

    <<expressions>>
    for i in 1 .. l_expr_arr.count loop
      l_expr := l_expr_arr(i);
      
      -- Remove leading $. if present
      if l_expr like '$.%' then
        l_expr := substr(l_expr, 3);
      end if;

      l_eval := apex_json.get_varchar2(p_path => l_expr, p_values => l_apex_json);

      if l_eval is null then 
        uc_ai_logger.log('JSONPath expression did not resolve any value: ' || l_expr, l_scope, p_workflow_state.to_clob);
      end if;

      l_res := replace(l_res, '{' || l_expr_arr(i) || '}', l_eval);
    end loop expressions;

    return l_res;
  exception
    when others then
      uc_ai_logger.log_error('Error resolving JSONPath: ' || p_expression || ' - ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      return null;
  end resolve_jsonpath_values;


  /*
   * Maps input parameters based on input_mapping configuration
   * Supports JSONPath-style expressions: $.input.field, $.steps.step_name.field
   */
  function map_inputs(
    p_input_mapping  in json_object_t,
    p_workflow_state in json_object_t
  ) return json_object_t
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'map_inputs';
    l_result       json_object_t := json_object_t();
    l_keys         json_key_list;
    l_key          varchar2(4000 char);
    l_mapping      varchar2(4000 char);
    l_mapping_obj  json_object_t;
    l_is_plsqlsql  boolean;
    l_resolved     clob;
  begin
    l_keys := p_input_mapping.get_keys;
    
    <<mapping_loop>>
    for i in 1 .. l_keys.count loop
      l_key := l_keys(i);

      if p_input_mapping.get_type(l_key) = 'OBJECT' then
        l_mapping_obj := p_input_mapping.get_object(l_key);
        l_mapping := l_mapping_obj.get_string('expression');
        if l_mapping_obj.has('is_plsql_expression') and l_mapping_obj.get_boolean('is_plsql_expression') then
          l_is_plsqlsql := true;
        else
          l_is_plsqlsql := false;
        end if;
      else
        l_mapping := p_input_mapping.get_string(l_key);
      end if;

      l_resolved := resolve_jsonpath_values(l_mapping, p_workflow_state);

      if l_is_plsqlsql then
        -- Evaluate as PL/SQL expression
        begin
          l_resolved := apex_plugin_util.get_plsql_expr_result_clob(
            p_plsql_expression => l_resolved,
            p_auto_bind_items  => false
          );
        exception
          when others then
            uc_ai_logger.log_error('Error evaluating PL/SQL expression for input mapping key ' || l_key || ': ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope, l_resolved);
            raise_application_error(-20022, 'Error evaluating PL/SQL expression for input mapping key ' || l_key || ': ' || l_resolved || ' - ' || sqlerrm);
        end;
      end if;

      l_result.put(l_key, l_resolved);
    end loop mapping_loop;
    
    uc_ai_logger.log('Mapped inputs: ' || l_result.to_string, l_scope);
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error mapping inputs: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end map_inputs;

  function evaluate_final_message(
    p_final_message in json_element_t,
    p_workflow_state in json_object_t
  ) return varchar2
  as
    l_expr varchar2(32767 char);
    l_is_plsqlsql boolean;
    l_tmp varchar2(32767 char);
    l_obj json_object_t;
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'evaluate_final_message';
  begin
    if p_final_message.is_object() then
      l_obj := treat(p_final_message as json_object_t);
      l_expr := l_obj.get_string('expression');
      if l_obj.has('is_plsql_expression') and l_obj.get_boolean('is_plsql_expression') then
        l_is_plsqlsql := true;
      else
        l_is_plsqlsql := false;
      end if;
    else
      l_is_plsqlsql := false;
      l_expr := p_final_message.to_string();
    end if;

    l_tmp := resolve_jsonpath_values(l_expr, p_workflow_state);

    uc_ai_logger.log('Evaluating final_message. Expression: ' || l_expr || ' Resolved: ' || l_tmp, l_scope, p_workflow_state.to_clob);

    if not l_is_plsqlsql then
      return l_tmp;
    end if;

    declare
      l_resolved varchar2(32767 char);
    begin
      l_resolved := apex_plugin_util.get_plsql_expr_result_clob(
        p_plsql_expression => l_tmp,
        p_auto_bind_items  => false
      );
      return l_resolved;
    exception
      when others then
        uc_ai_logger.log_error('Error evaluating PL/SQL expression for final_message: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope, l_tmp);
        raise_application_error(-20023, 'Error evaluating PL/SQL expression for final_message: ' || l_tmp || ' - ' || sqlerrm );
    end;
  end evaluate_final_message;


  /*
   * Evaluates a condition expression
   */
  function evaluate_condition(
    p_condition      in varchar2,
    p_workflow_state in json_object_t
  ) return boolean
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'evaluate_condition';
    l_expression varchar2(4000 char);
    l_result     boolean;
  begin
    if p_condition is null then
      return true;  -- No condition means always execute
    end if;

    l_expression := resolve_jsonpath_values(p_condition, p_workflow_state);

    uc_ai_logger.log('Evaluating condition: ' || l_expression, l_scope);

    begin
      l_result := apex_plugin_util.get_plsql_expr_result_boolean(
        p_plsql_expression => l_expression,
        p_auto_bind_items  => false
      );
    exception
      when others then
        uc_ai_logger.log_error('Error evaluating condition expression: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope, l_expression);
        raise_application_error(-20021, 'Error evaluating condition expression: ' || l_expression || ' - ' || sqlerrm);
    end;


    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error evaluating condition: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end evaluate_condition;


  /*
   * Merges step output into workflow state based on output_mapping
   */
  procedure add_result_to_workflow_state(
    p_step             in json_object_t,
    p_step_output      in json_object_t,
    pio_workflow_state in out nocopy json_object_t
  )
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'add_result_to_workflow_state';
    l_steps_state json_object_t;
    l_output_key varchar2(4000 char);
  begin
    -- Store step output using output_key
    if p_step.has('output_key') then
      l_output_key := p_step.get_string('output_key');
    else
      uc_ai_logger.log_error('Step definition missing output_key', l_scope, p_step.to_clob);
      raise_application_error(-20020, 'Step definition missing output_key');
    end if;
    
    -- Update _steps in workflow state
    if not pio_workflow_state.has('steps') then
      l_steps_state := json_object_t();
    else
      l_steps_state := treat(pio_workflow_state.get('steps') as json_object_t);
    end if;

    l_steps_state.put(l_output_key, p_step_output.get('final_message'));
    pio_workflow_state.put('steps', l_steps_state);
  exception
    when others then
      uc_ai_logger.log_error('Error merging outputs', l_scope);
      raise;
  end add_result_to_workflow_state;


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
        
        l_summary_result := uc_ai_agents_api.execute_agent(
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

end uc_ai_agent_workflow_api;
/
