create or replace package body uc_ai_ptc_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  function call_tool_json(
    p_tool_code in uc_ai_tools.code%type
  , p_args_json in clob
  ) return clob
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'call_tool_json';
    l_args  json_object_t;
  begin
    uc_ai_logger.log('Programmatic tool call', l_scope, p_tool_code);

    -- Enforce the current run's allow-list + inner-call budget and fire the
    -- per-tool-call hook. Raises if the tool is not part of this run's exposed set,
    -- the budget is exceeded or a hook vetoes; the runner turns that into a
    -- rejected callTool inside the program, so the model can self-correct.
    uc_ai_tools_api.check_ptc_tool_allowed(p_tool_code);

    if p_args_json is null or sys.dbms_lob.getlength(p_args_json) = 0 then
      l_args := json_object_t();
    else
      l_args := json_object_t(p_args_json);
    end if;

    return uc_ai_tools_api.execute_tool(
      p_tool_code => p_tool_code
    , p_arguments => l_args
    );
  exception
    when others then
      uc_ai_logger.log_error('Error in call_tool_json: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end call_tool_json;

end uc_ai_ptc_api;
/
