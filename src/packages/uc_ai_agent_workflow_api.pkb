create or replace package body uc_ai_agent_workflow_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


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
   * Resolves a JSONPath-style expression against workflow context
   * Supports: $.input.field, $.steps.step_name.field, $.workflow.field
   */
  function resolve_jsonpath(
    p_expression     in varchar2,
    p_workflow_state in json_object_t,
    p_original_input in json_object_t
  ) return clob
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'resolve_jsonpath';
    l_expr       varchar2(4000 char) := p_expression;
    l_steps_obj  json_object_t;
    l_mixed_obj  json_object_t;
    l_res        clob;

    l_apex_json apex_json.t_values;
  begin
    -- Remove leading $. if present
    if l_expr like '$.%' then
      l_expr := substr(l_expr, 3);
    end if;
    
    l_mixed_obj := json_object_t();
    l_mixed_obj.put('input', p_original_input);
    if p_workflow_state.has('_steps') then
      l_steps_obj := treat(p_workflow_state.get('_steps') as json_object_t);
      l_mixed_obj.put('steps', l_steps_obj);
    end if;
    l_mixed_obj.put('workflow', p_workflow_state);

    apex_json.parse(l_apex_json, l_mixed_obj.to_clob);

    l_res := apex_json.get_clob(p_path => l_expr, p_values => l_apex_json);

    if l_res is null then 
      logger.log_error('JSONPath expression did not resolve any value: ' || p_expression, l_scope, l_mixed_obj.to_clob);
      raise_application_error(-20020, 'JSONPath expression did not resolve any value: ' || p_expression);
    end if;

    return l_res;
  exception
    when others then
      uc_ai_logger.log_error('Error resolving JSONPath: ' || p_expression || ' - ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      return null;
  end resolve_jsonpath;


  /*
   * Maps input parameters based on input_mapping configuration
   * Supports JSONPath-style expressions: $.input.field, $.steps.step_name.field
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
    l_mapping_tmp varchar2(4000 char);
    l_path       varchar2(4000 char);
    l_resolved   clob;
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
      
      -- Handle JSONPath-style expressions: $.input.field, $.steps.name.field
      if l_mapping like '$.%' then
        l_resolved := resolve_jsonpath(l_mapping, p_workflow_state, p_original_input);
        if l_resolved is not null then
          l_result.put(l_key, l_resolved);
        else
          uc_ai_logger.log_warn('Could not resolve mapping: ' || l_mapping || ' for key: ' || l_key, l_scope);
        end if;
        
      -- Handle legacy ${source.path} format
      elsif l_mapping like '${%}' then
        l_mapping_tmp :=  '$.' || rtrim(ltrim(l_mapping, '${'), '}');

        l_resolved := resolve_jsonpath(l_mapping_tmp, p_workflow_state, p_original_input);
        if l_resolved is not null then
          l_result.put(l_key, l_resolved);
        else
          uc_ai_logger.log_warn('Could not resolve mapping: ' || l_mapping || ' for key: ' || l_key, l_scope);
        end if;
      else
        -- Literal value
        l_result.put(l_key, l_mapping);
      end if;
    end loop mapping_loop;
    
    uc_ai_logger.log('Mapped inputs: ' || l_result.to_string, l_scope);
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error mapping inputs: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end map_inputs;


  /*
   * Merges step output into workflow state based on output_mapping
   */
  procedure merge_outputs(
    p_output_mapping   in json_object_t,
    p_step_output      in json_object_t,
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
