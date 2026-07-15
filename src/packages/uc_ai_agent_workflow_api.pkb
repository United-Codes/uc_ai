create or replace package body uc_ai_agent_workflow_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  /*
   * Escapes a resolved string value so it cannot break out of the single-quoted
   * PL/SQL string literal it is substituted into. Only the quote character is
   * doubled - no surrounding quotes are added, so the documented authoring
   * convention (string tokens are wrapped in quotes by the expression author,
   * numeric/boolean tokens are not) keeps working unchanged. This is the guard
   * that stops untrusted state values (LLM output, tool results, user input)
   * from injecting PL/SQL into conditions and PL/SQL-expression mappings.
   */
  function escape_plsql_string_value(
    p_value in clob
  ) return clob
  as
  begin
    if p_value is null then
      return p_value;
    end if;
    return replace(p_value, '''', '''''');
  end escape_plsql_string_value;


  /*
   * Resolves a single path (e.g. $.steps.step_name.field, $.steps.list[1])
   * by walking the workflow state DOM directly. Array indexes are 1-based
   * (matching apex_json path semantics). Returns null when the path does not
   * resolve or points to a non-scalar value.
   *
   * When p_escape_for_plsql is true, resolved *string* values have embedded
   * single quotes doubled so they are safe to embed inside a PL/SQL string
   * literal. Numbers and booleans never need escaping. Callers that feed the
   * result into a PL/SQL expression (conditions, PL/SQL-expression mappings)
   * must pass true; callers that substitute into plain text / JSON must pass
   * false so the raw value is preserved.
   */
  function resolve_path_value(
    p_path             in varchar2,
    p_workflow_state   in json_object_t,
    p_escape_for_plsql in boolean default false
  ) return clob
  as
    l_path     varchar2(4000 char);
    l_segments apex_t_varchar2;
    l_accesses apex_t_varchar2 := apex_t_varchar2();
    l_seg      varchar2(4000 char);
    l_name     varchar2(4000 char);
    l_idx_str  varchar2(100 char);
    l_occ      pls_integer;
    l_elem     json_element_t;
    l_obj      json_object_t;
    l_arr      json_array_t;
    l_idx      pls_integer;
    l_last     boolean;
    l_acc      varchar2(4000 char);
    l_leaf     json_element_t;
  begin
    l_path := p_path;
    if l_path like '$.%' then
      l_path := substr(l_path, 3);
    end if;

    -- flatten path into a list of accesses: member names, array indexes prefixed with '#'
    l_segments := apex_string.split(l_path, '.');
    <<segments>>
    for i in 1 .. l_segments.count loop
      l_seg := l_segments(i);
      l_name := regexp_substr(l_seg, '^[^\[]+');
      if l_name is null then
        return null;
      end if;
      apex_string.push(l_accesses, l_name);

      l_occ := 1;
      <<idx_parts>>
      loop
        l_idx_str := regexp_substr(l_seg, '\[([0-9]+)\]', 1, l_occ, null, 1);
        exit idx_parts when l_idx_str is null;
        apex_string.push(l_accesses, '#' || l_idx_str);
        l_occ := l_occ + 1;
      end loop idx_parts;
    end loop segments;

    -- walk the DOM; read the leaf through its parent container for CLOB-safe access
    l_elem := p_workflow_state;
    <<walk>>
    for i in 1 .. l_accesses.count loop
      l_acc  := l_accesses(i);
      l_last := i = l_accesses.count;

      if l_acc like '#%' then
        if l_elem is null or not l_elem.is_array then
          return null;
        end if;
        l_arr := treat(l_elem as json_array_t);
        l_idx := to_number(substr(l_acc, 2)) - 1;
        if l_idx < 0 or l_idx >= l_arr.get_size then
          return null;
        end if;
        if l_last then
          l_leaf := l_arr.get(l_idx);
          if l_leaf is null then
            return null;
          elsif l_leaf.is_string then
            return case when p_escape_for_plsql then escape_plsql_string_value(l_arr.get_clob(l_idx)) else l_arr.get_clob(l_idx) end;
          elsif l_leaf.is_number then
            return to_clob(to_char(l_arr.get_number(l_idx)));
          elsif l_leaf.is_boolean then
            return case when l_arr.get_boolean(l_idx) then to_clob('true') else to_clob('false') end;
          else
            return null;  -- json null, object, array: no scalar representation
          end if;
        end if;
        l_elem := l_arr.get(l_idx);
      else
        if l_elem is null or not l_elem.is_object then
          return null;
        end if;
        l_obj := treat(l_elem as json_object_t);
        if not l_obj.has(l_acc) then
          return null;
        end if;
        if l_last then
          l_leaf := l_obj.get(l_acc);
          if l_leaf is null then
            return null;
          elsif l_leaf.is_string then
            return case when p_escape_for_plsql then escape_plsql_string_value(l_obj.get_clob(l_acc)) else l_obj.get_clob(l_acc) end;
          elsif l_leaf.is_number then
            return to_clob(to_char(l_obj.get_number(l_acc)));
          elsif l_leaf.is_boolean then
            return case when l_obj.get_boolean(l_acc) then to_clob('true') else to_clob('false') end;
          else
            return null;  -- json null, object, array: no scalar representation
          end if;
        end if;
        l_elem := l_obj.get(l_acc);
      end if;
    end loop walk;

    return null;
  end resolve_path_value;


  /*
   * Resolves a JSONPath-style expression against workflow context
   * Supports: $.input.field, $.steps.step_name.field
   */
  function resolve_jsonpath_values(
    p_expression       in clob,
    p_workflow_state   in json_object_t,
    p_escape_for_plsql in boolean default false
  ) return clob
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'resolve_jsonpath_values';
    l_expr  varchar2(4000 char);
    l_token varchar2(4010 char);
    l_eval  clob;
    l_res   clob;
    l_count pls_integer;
    l_pos   pls_integer;
    l_from  pls_integer;
  begin
    l_count := regexp_count(p_expression, '\{\$\.[^\}]+\}');

    if l_count = 0 then
      -- No expressions to resolve
      return p_expression;
    end if;

    l_res := p_expression;

    <<expressions>>
    for i in 1 .. l_count loop
      l_expr := regexp_substr(p_expression, '\{(\$\.[^\}]+)\}', 1, i, null, 1);

      l_eval := resolve_path_value(l_expr, p_workflow_state, p_escape_for_plsql);

      if l_eval is null then
        uc_ai_logger.log('JSONPath expression did not resolve any value: ' || l_expr, l_scope, p_workflow_state.to_clob);
      end if;

      -- manual splice: replace() rejects CLOB replacement values over 32k (ORA-22828)
      l_token := '{' || l_expr || '}';
      l_from  := 1;
      <<occurrences>>
      loop
        l_pos := instr(l_res, l_token, l_from);
        exit occurrences when l_pos = 0;
        l_res  := substr(l_res, 1, l_pos - 1) || l_eval || substr(l_res, l_pos + length(l_token));
        l_from := l_pos + nvl(length(l_eval), 0);
      end loop occurrences;
    end loop expressions;

    return l_res;
  exception
    when others then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_jsonpath_resolve
      , p_scope      => l_scope
      , p0           => substr(p_expression, 1, 200)
      , p1           => sqlerrm
      , p_extra      => sys.dbms_utility.format_error_backtrace
      );
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
    l_mapping      clob;
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
        l_mapping := l_mapping_obj.get_clob('expression');
        if l_mapping_obj.has('is_plsql_expression') and l_mapping_obj.get_boolean('is_plsql_expression') then
          l_is_plsqlsql := true;
        else
          l_is_plsqlsql := false;
        end if;
      else
        l_mapping := p_input_mapping.get_clob(l_key);
        l_is_plsqlsql := false;
      end if;

      -- escape resolved string values only when the result feeds a PL/SQL
      -- expression; plain mappings must keep the raw value for JSON output
      l_resolved := resolve_jsonpath_values(l_mapping, p_workflow_state, p_escape_for_plsql => l_is_plsqlsql);

      if l_is_plsqlsql then
        -- Evaluate as PL/SQL expression
        if sys.dbms_lob.getlength(l_resolved) > 32767 then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_input_mapping_eval
          , p_scope      => l_scope
          , p0           => l_key
          , p1           => 'resolved PL/SQL expression exceeds 32767 characters - reference large values via plain mappings instead of PL/SQL expressions'
          );
        end if;

        begin
          l_resolved := apex_plugin_util.get_plsql_expr_result_clob(
            p_plsql_expression => l_resolved,
            p_auto_bind_items  => false
          );
        exception
          when others then
            uc_ai_error.raise_error(
              p_error_code => uc_ai_error.c_err_input_mapping_eval
            , p_scope      => l_scope
            , p0           => l_key
            , p1           => sqlerrm
            , p_extra      => l_resolved || chr(10) || sys.dbms_utility.format_error_backtrace
            );
        end;
      end if;

      l_result.put(l_key, l_resolved);
    end loop mapping_loop;
    
    uc_ai_logger.log('Mapped inputs', l_scope, l_result.to_clob);
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error mapping inputs: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end map_inputs;

  function evaluate_final_message(
    p_final_message in json_element_t,
    p_workflow_state in json_object_t
  ) return clob
  as
    l_expr clob;
    l_is_plsqlsql boolean;
    l_tmp clob;
    l_obj json_object_t;
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'evaluate_final_message';
  begin
    if p_final_message.is_object() then
      l_obj := treat(p_final_message as json_object_t);
      l_expr := l_obj.get_clob('expression');
      if l_obj.has('is_plsql_expression') and l_obj.get_boolean('is_plsql_expression') then
        l_is_plsqlsql := true;
      else
        l_is_plsqlsql := false;
      end if;
    else
      l_is_plsqlsql := false;
      if p_final_message.is_string then
        -- read the string value through a container; to_string() would keep
        -- the surrounding JSON quotes in the final message
        declare
          l_wrap json_array_t := json_array_t();
        begin
          l_wrap.append(p_final_message);
          l_expr := l_wrap.get_clob(0);
        end;
      else
        l_expr := p_final_message.to_string();
      end if;
    end if;

    -- escape resolved string values only when evaluated as a PL/SQL expression;
    -- plain final messages must keep the raw value
    l_tmp := resolve_jsonpath_values(l_expr, p_workflow_state, p_escape_for_plsql => l_is_plsqlsql);

    uc_ai_logger.log('Evaluating final_message. Expression: ' || substr(l_expr, 1, 2000) || ' Resolved: ' || substr(l_tmp, 1, 2000), l_scope, p_workflow_state.to_clob);

    if not l_is_plsqlsql then
      return l_tmp;
    end if;

    if sys.dbms_lob.getlength(l_tmp) > 32767 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_final_message_eval
      , p_scope      => l_scope
      , p0           => substr(l_expr, 1, 200)
      , p1           => 'resolved PL/SQL expression exceeds 32767 characters - reference large values via plain expressions instead of PL/SQL expressions'
      );
    end if;

    declare
      l_resolved clob;
    begin
      l_resolved := apex_plugin_util.get_plsql_expr_result_clob(
        p_plsql_expression => l_tmp,
        p_auto_bind_items  => false
      );
      return l_resolved;
    exception
      when others then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_final_message_eval
        , p_scope      => l_scope
        , p0           => l_tmp
        , p1           => sqlerrm
        , p_extra      => sys.dbms_utility.format_error_backtrace
        );
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
    l_expression clob;
    l_result     boolean;
    l_ref_count  pls_integer;
    l_ref_path   varchar2(4000 char);
  begin
    if p_condition is null then
      return true;  -- No condition means always execute
    end if;

    -- A condition may reference state that has not been produced yet - e.g. a
    -- loop exit condition is checked after every step, so a condition on a
    -- later step's output is evaluated before that step has run. Such a
    -- reference resolves to nothing and would splice into a malformed PL/SQL
    -- expression (" >= 8"), so treat any condition with an unresolved JSONPath
    -- reference as NOT met: for a loop exit this keeps it iterating until the
    -- referenced value exists; for a step condition the guarded step is skipped.
    l_ref_count := regexp_count(p_condition, '\{\$\.[^\}]+\}');
    <<unresolved_refs>>
    for i in 1 .. l_ref_count loop
      l_ref_path := regexp_substr(p_condition, '\{(\$\.[^\}]+)\}', 1, i, null, 1);
      if resolve_path_value(l_ref_path, p_workflow_state) is null then
        uc_ai_logger.log('Condition references unresolved path ' || l_ref_path
          || ' - treating condition as not met', l_scope);
        return false;
      end if;
    end loop unresolved_refs;

    -- conditions are always evaluated as PL/SQL boolean expressions, so resolved
    -- string values must be escaped to prevent injection via untrusted state
    l_expression := resolve_jsonpath_values(p_condition, p_workflow_state, p_escape_for_plsql => true);

    if sys.dbms_lob.getlength(l_expression) > 32767 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_condition_eval
      , p_scope      => l_scope
      , p0           => p_condition
      , p1           => 'resolved condition exceeds 32767 characters - a referenced state value is too large for a PL/SQL boolean expression'
      );
    end if;

    uc_ai_logger.log('Evaluating condition: ' || substr(l_expression, 1, 4000), l_scope);

    begin
      l_result := apex_plugin_util.get_plsql_expr_result_boolean(
        p_plsql_expression => l_expression,
        p_auto_bind_items  => false
      );
    exception
      when others then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_condition_eval
        , p_scope      => l_scope
        , p0           => l_expression
        , p1           => sqlerrm
        , p_extra      => sys.dbms_utility.format_error_backtrace
        );
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
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_missing_output_key
      , p_scope      => l_scope
      , p_extra      => p_step.to_clob
      );
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

        -- Keep only last N messages, preserving system message if present
        l_result := json_array_t();
        declare
          l_first_msg json_object_t;
          l_start_idx number;
        begin
          l_first_msg := treat(p_history.get(0) as json_object_t);
          if l_first_msg.has('role') and l_first_msg.get_string('role') = 'system' then
            -- Preserve system message and take last N from the rest
            l_result.append(p_history.get(0));
            l_start_idx := greatest(p_history.get_size - l_max_messages, 1);
          else
            l_start_idx := p_history.get_size - l_max_messages;
          end if;

          <<window_loop>>
          for i in l_start_idx .. (p_history.get_size - 1) loop
            l_result.append(p_history.get(i));
          end loop window_loop;
        end;

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
