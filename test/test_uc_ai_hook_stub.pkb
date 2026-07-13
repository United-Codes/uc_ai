create or replace package body test_uc_ai_hook_stub as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-7230): allow use of global variables in test stub
  -- @dblinter ignore(g-5040): allow special others handling in test packages

  procedure reset
  as
  begin
    g_before_count     := 0;
    g_after_count      := 0;
    g_last_agent_id    := null;
    g_last_agent_code  := null;
    g_last_created_by  := null;
    g_last_apex_app_id := null;
    g_last_session_id  := null;
    g_last_exec_id     := null;
    g_last_status      := null;
    g_last_in_tokens   := null;
    g_last_out_tokens  := null;
    g_tool_count       := 0;
    g_last_tool_code   := null;
    g_last_tool_agent  := null;
    g_last_tool_user   := null;
    g_before_raise     := false;
    g_after_raise      := false;
    g_tool_raise       := false;
  end reset;


  procedure before_execution(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_created_by  in varchar2,
    p_apex_app_id in number,
    p_session_id  in varchar2
  )
  as
  begin
    g_before_count     := nvl(g_before_count, 0) + 1;
    g_last_agent_id    := p_agent_id;
    g_last_agent_code  := p_agent_code;
    g_last_created_by  := p_created_by;
    g_last_apex_app_id := p_apex_app_id;
    g_last_session_id  := p_session_id;

    if g_before_raise then
      raise_application_error(c_before_veto_code, 'stub veto');
    end if;
  end before_execution;


  procedure after_execution(
    p_exec_id       in number,
    p_status        in varchar2,
    p_input_tokens  in number,
    p_output_tokens in number
  )
  as
  begin
    g_after_count     := nvl(g_after_count, 0) + 1;
    g_last_exec_id    := p_exec_id;
    g_last_status     := p_status;
    g_last_in_tokens  := p_input_tokens;
    g_last_out_tokens := p_output_tokens;

    if g_after_raise then
      raise_application_error(c_after_fail_code, 'stub after failure');
    end if;
  end after_execution;


  procedure before_tool_call(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_tool_code   in varchar2,
    p_created_by  in varchar2,
    p_session_id  in varchar2,
    p_apex_app_id in number
  )
  as
  begin
    g_tool_count      := nvl(g_tool_count, 0) + 1;
    g_last_tool_code  := p_tool_code;
    g_last_tool_agent := p_agent_code;
    g_last_tool_user  := p_created_by;

    if g_tool_raise then
      raise_application_error(c_tool_veto_code, 'stub tool veto');
    end if;
  end before_tool_call;

end test_uc_ai_hook_stub;
/
