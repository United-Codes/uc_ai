create or replace package body uc_ai_chat_hook as

  c_scope    constant varchar2(100 char) := 'uc_ai_chat_hook';
  c_customer constant varchar2(30 char)  := 'UC_AI_HOOK';

  -- Current turn context (per scheduler-job session).
  -- @dblinter ignore(g-7230) session-scoped context set once per job
  g_user_msg_id number;
  g_session_id  varchar2(255 char);
  g_created_by  varchar2(255 char);

  -- Resolved customer hook package (UC_AI_HOOK in this schema), cached.
  -- @dblinter ignore(g-7230)
  g_customer_pkg      varchar2(128 char);
  -- @dblinter ignore(g-7230)
  g_customer_resolved boolean := false;

  -- ==========================================================================
  -- Resolve the customer's conventional hook package once per session.
  -- ==========================================================================
  function customer_hook return varchar2
  is
  begin
    if not g_customer_resolved then
      begin
        select object_name
          into g_customer_pkg
          from user_objects
         where object_type = 'PACKAGE'
           and object_name = c_customer
           and status = 'VALID';
      exception
        when no_data_found then
          g_customer_pkg := null;
      end;
      g_customer_resolved := true;
    end if;
    return g_customer_pkg;
  end customer_hook;

  -- ==========================================================================
  -- Does the customer hook implement the given procedure?
  -- ==========================================================================
  function customer_implements(p_procedure in varchar2) return boolean
  is
    l_pkg    varchar2(128 char) := customer_hook;
    l_exists pls_integer;
  begin
    if l_pkg is null then
      return false;
    end if;

    select case
             when exists (
               select 1
                 from all_procedures
                where owner          = sys_context('userenv', 'current_schema')
                  and object_name    = l_pkg
                  and procedure_name = p_procedure
             ) then 1 else 0
           end
      into l_exists
      from dual;

    return l_exists = 1;
  end customer_implements;

  -- ==========================================================================
  -- Write a provisional "tool running" placeholder row for the current turn.
  -- Autonomous + best-effort: progress tracking must never break a run.
  -- ==========================================================================
  procedure insert_running_placeholder(p_tool_code in varchar2)
  is
    -- @dblinter ignore(G-3330) Autonomous: the placeholder must be visible to pollers now
    pragma autonomous_transaction;
  begin
    insert into uc_ai_chat_messages (
      session_id, role, tool_name, tool_status, created_by
    ) values (
      g_session_id, 'tool_call', p_tool_code, 'running', nvl(g_created_by, 'SYSTEM')
    );
    commit;
  exception
    when others then -- @dblinter ignore(G-5040)
      rollback;
      apex_debug.warn('%s | could not write tool placeholder for %s: %s | %s',
        c_scope, p_tool_code, sqlerrm, sys.dbms_utility.format_error_backtrace);
  end insert_running_placeholder;

  -- ==========================================================================
  -- set_chat_context
  -- ==========================================================================
  procedure set_chat_context(
    p_user_msg_id in number,
    p_session_id  in varchar2,
    p_created_by  in varchar2
  )
  is
  begin
    g_user_msg_id := p_user_msg_id;
    g_session_id  := p_session_id;
    g_created_by  := p_created_by;
  end set_chat_context;

  -- ==========================================================================
  -- before_execution (veto hook: delegate, propagate customer exceptions)
  -- ==========================================================================
  procedure before_execution(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_created_by  in varchar2,
    p_apex_app_id in number,
    p_session_id  in varchar2
  )
  is
    l_stmt varchar2(200 char);
  begin
    if customer_implements('BEFORE_EXECUTION') then
      l_stmt := 'begin ' || c_customer || '.before_execution(:1, :2, :3, :4, :5); end;';
      execute immediate l_stmt
        using in p_agent_id, in p_agent_code, in p_created_by, in p_apex_app_id, in p_session_id;
    end if;
  end before_execution;

  -- ==========================================================================
  -- after_execution (best-effort hook: delegate, swallow customer exceptions)
  -- ==========================================================================
  procedure after_execution(
    p_exec_id       in number,
    p_status        in varchar2,
    p_input_tokens  in number,
    p_output_tokens in number
  )
  is
    l_stmt varchar2(200 char);
  begin
    if customer_implements('AFTER_EXECUTION') then
      l_stmt := 'begin ' || c_customer || '.after_execution(:1, :2, :3, :4); end;';
      execute immediate l_stmt
        using in p_exec_id, in p_status, in p_input_tokens, in p_output_tokens;
    end if;
  exception
    when others then -- @dblinter ignore(G-5040)
      apex_debug.warn('%s | customer after_execution failed: %s | %s',
        c_scope, sqlerrm, sys.dbms_utility.format_error_backtrace);
  end after_execution;

  -- ==========================================================================
  -- before_tool_call (veto hook). Delegate FIRST so a customer veto prevents a
  -- placeholder for a tool that will not run; then write the progress row.
  -- ==========================================================================
  procedure before_tool_call(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_tool_code   in varchar2,
    p_created_by  in varchar2,
    p_session_id  in varchar2,
    p_apex_app_id in number
  )
  is
    l_stmt varchar2(200 char);
  begin
    if customer_implements('BEFORE_TOOL_CALL') then
      l_stmt := 'begin ' || c_customer || '.before_tool_call(:1, :2, :3, :4, :5, :6); end;';
      execute immediate l_stmt
        using in p_agent_id, in p_agent_code, in p_tool_code, in p_created_by, in p_session_id, in p_apex_app_id;
    end if;

    if g_user_msg_id is not null and g_session_id is not null then
      insert_running_placeholder(p_tool_code);
    end if;
  end before_tool_call;

  -- ==========================================================================
  -- augment_system_prompt (best-effort hook: delegate, swallow exceptions)
  -- ==========================================================================
  procedure augment_system_prompt(
    pio_system_prompt in out nocopy clob
  )
  is
    l_prompt clob;
    l_stmt   varchar2(200 char);
  begin
    if customer_implements('AUGMENT_SYSTEM_PROMPT') then
      l_prompt := pio_system_prompt;
      l_stmt := 'begin ' || c_customer || '.augment_system_prompt(:1); end;';
      execute immediate l_stmt
        using in out l_prompt;
      pio_system_prompt := l_prompt;
    end if;
  exception
    when others then -- @dblinter ignore(G-5040)
      apex_debug.warn('%s | customer augment_system_prompt failed; prompt left unchanged: %s | %s',
        c_scope, sqlerrm, sys.dbms_utility.format_error_backtrace);
  end augment_system_prompt;

end uc_ai_chat_hook;
/
