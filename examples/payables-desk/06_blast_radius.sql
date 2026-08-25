-- ============================================================================
-- UC AI tutorial — "Secure an Agent" — Lesson 6
-- Assume you lost: bound the run, veto it, and be able to take it back
-- ============================================================================
-- Everything so far tries to stop a bad decision. This lesson assumes one got
-- through, and bounds what it can cost.
--
--   1. A hook that vetoes by TOOL and by CALLER. It cannot see the arguments,
--      so capability rules go here and value rules stay in the handler.
--   2. A kill switch that is a row, so switching the desk off needs no
--      deployment and nobody has to compile anything.
--   3. The transaction. The handler does not commit, so the caller can take the
--      whole run back -- and one thing does not come back with it.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

create or replace package ap_desk_hook
  authid definer
as
  /**
  * UC AI tutorial — "Secure an Agent" — lesson 6
  *
  * An execution hook for the payables desk.
  *
  * before_tool_call receives the tool code, the caller and the session. It does
  * NOT receive the arguments, and it cannot change them. So it can decide WHO
  * may call a tool, HOW OFTEN, and WHETHER the tool is switched on at all. It
  * cannot decide HOW MUCH. An amount rule belongs in the handler, where the
  * amount is.
  *
  * A raise here ends the run. It is not a refusal the model gets to read and
  * explain, which is what makes it a control rather than a suggestion.
  */
  procedure before_execution(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_created_by  in varchar2
  , p_apex_app_id in number
  , p_session_id  in varchar2
  );

  procedure after_execution(
    p_exec_id      in number
  , p_status       in varchar2
  , p_input_tokens in number
  , p_output_tokens in number
  );

  procedure before_tool_call(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_tool_code   in varchar2
  , p_created_by  in varchar2
  , p_session_id  in varchar2
  , p_apex_app_id in number
  );
end ap_desk_hook;
/

create or replace package body ap_desk_hook
as
  -- @dblinter ignore(g-7150): the three hook procedures must match the signatures UC AI
  -- calls them with. A hook that uses only some of what it is handed still has to
  -- declare all of it, so the unused parameters here are the contract, not dead code.
  -- One approval attempt for each run. The counter is per session, and it is
  -- reset when a run starts.
  g_approve_attempts pls_integer := 0;

  procedure before_execution(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_created_by  in varchar2
  , p_apex_app_id in number
  , p_session_id  in varchar2
  )
  as
  begin
    -- The reset lives here, and before_execution fires ONLY for execute_agent.
    -- A plain uc_ai.generate_text call never resets it, so on that path rule 3
    -- below bounds the SESSION and not the run. Lessons 4 and 5 use that path.
    g_approve_attempts := 0;
  end before_execution;


  procedure after_execution(
    p_exec_id       in number
  , p_status        in varchar2
  , p_input_tokens  in number
  , p_output_tokens in number
  )
  as
  begin
    null;
  end after_execution;


  procedure before_tool_call(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_tool_code   in varchar2
  , p_created_by  in varchar2
  , p_session_id  in varchar2
  , p_apex_app_id in number
  )
  as
    l_ctx     uc_ai.t_exec_context;
    l_clerk   varchar2(255 char);
    l_enabled pls_integer;
  begin
    -- Narrow the control to the agent it is meant for. before_tool_call fires
    -- for every agent and every plain generate_text call in the schema, so a
    -- hook that reads only p_tool_code vetoes that tool for everybody.
    if p_agent_code != 'AP_DESK' or p_tool_code != 'AP_APPROVE_INVOICE' then
      return;
    end if;

    -- Rule 1, a standing switch. Turning the desk off is an update, not a
    -- deployment, and somebody who is not you can do it.
    select count(*)
      into l_enabled
      from ap_controls c
     where c.control_code = 'AGENT_APPROVALS_ENABLED'
       and c.control_value = 'Y'
       and rownum = 1;

    if l_enabled = 0 then
      raise_application_error(-20993, 'Agent approvals are switched off.');
    end if;

    -- Rule 2, identity. UC AI publishes the run context to the hook, so a rule
    -- about WHO is asking works here. get_exec_context is filled by the time
    -- before_tool_call runs; it is not filled in before_execution.
    l_ctx   := uc_ai.get_exec_context;
    l_clerk := uc_ai.run_context_value(l_ctx.run_context, 'clerk');

    if l_clerk is null then
      raise_application_error(-20991
        , 'An approval needs a named clerk in the run context.');
    end if;

    -- Rule 3, frequency. However many times the model asks, it asks once.
    g_approve_attempts := g_approve_attempts + 1;

    if g_approve_attempts > 1 then
      raise_application_error(-20992, 'One approval attempt for each run.');
    end if;
  end before_tool_call;

end ap_desk_hook;
/

-- Register it FOR THIS SESSION. A package named UC_AI_HOOK would activate
-- itself for every agent in the schema, with no registration call at all, which
-- is the wrong shape for an experiment.
begin
  uc_ai_agents_api.set_execution_hook('AP_DESK_HOOK');
end;
/

-- ---------------------------------------------------------------------------
-- Verification 1 — test the hook with no run, no model and no tokens
-- ---------------------------------------------------------------------------
declare
  procedure expect_veto(p_label in varchar2, p_tool in varchar2)
  as
  begin
    ap_desk_hook.before_tool_call(
      p_agent_id    => null
    , p_agent_code  => 'AP_DESK'
    , p_tool_code   => p_tool
    , p_created_by  => 'petra.k'
    , p_session_id  => 'no-run'
    , p_apex_app_id => null
    );
    sys.dbms_output.put_line(rpad(p_label, 44) || ' -> NOT VETOED');
  exception
    when others then
      -- @dblinter ignore(g-5040): the veto is an exception, and this is the assertion
      -- @dblinter ignore(g-5080): sqlerrm is the assertion; a backtrace would add nothing
      sys.dbms_output.put_line(rpad(p_label, 44) || ' -> ' || sqlerrm);
  end expect_veto;
begin
  -- Called outside a run, so get_exec_context is empty and there is no clerk.
  expect_veto('a read tool, outside a run', 'AP_GET_INVOICE');
  expect_veto('the write tool, with no clerk bound', 'AP_APPROVE_INVOICE');

  update ap_controls set control_value = 'N'
   where control_code = 'AGENT_APPROVALS_ENABLED';

  expect_veto('the write tool, approvals switched off', 'AP_APPROVE_INVOICE');

  update ap_controls set control_value = 'Y'
   where control_code = 'AGENT_APPROVALS_ENABLED';
  commit;
exception
  when others then
    -- Whatever went wrong, the desk must not be left switched off.
    -- @dblinter ignore(g-5040): one recovery is correct for every failure here
    update ap_controls set control_value = 'Y'
     where control_code = 'AGENT_APPROVALS_ENABLED';
    commit;
    raise;
end;
/

-- ---------------------------------------------------------------------------
-- The veto in a real run
-- ---------------------------------------------------------------------------
-- The hook is registered for this session, so the next agent run that asks for
-- an approval with no clerk bound ends with the veto, out of execute_agent. It
-- is not a refusal the model reads and explains: the run is over.
declare
  l_result json_object_t;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'AP_DESK'
  , p_input_parameters => json_object_t('{"entity":"Ferrolux Deutschland GmbH"
      ,"clerk_name":"Petra","today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"INV-88001 is in order. Approve it."}')
  , p_session_id       => uc_ai_agents_api.generate_session_id
    -- An invoice and a vendor, because lesson 5 scoped the memory of this agent
    -- on vendor_no and a run that omits it is stopped before it starts. And
    -- deliberately no clerk, which is what the hook is about to notice.
  , p_run_context      => json_object_t('{"invoice_id":"7001","vendor_no":"V-1001"}')
  );
  sys.dbms_output.put_line('NOT VETOED: ' || l_result.get_clob('final_message'));
  commit;
exception
  when others then
    -- @dblinter ignore(g-5040): the veto is an exception, and this is the assertion
    -- @dblinter ignore(g-5080): sqlerrm is the assertion
    sys.dbms_output.put_line('the veto ended the run: ' || sqlerrm);
    rollback;
end;
/

set feedback off
prompt
prompt What a vetoed run recorded:
select e.status, e.tool_calls_count, e.total_input_tokens, e.total_output_tokens
     , substr(e.error_message, 1, 60) as error_message
  from uc_ai_agent_executions e
 where e.agent_id = ( select a.id from uc_ai_agents a
                       where a.code = 'AP_DESK' and a.version = 1 )
 order by e.started_at desc
 fetch first 1 rows only;
set feedback on

-- ---------------------------------------------------------------------------
-- Verification 2 — the rollback, and the one thing that does not come back
-- ---------------------------------------------------------------------------
declare
  l_before pls_integer;
  l_after  pls_integer;
  l_first  number;
  l_second number;
  l_args   json_object_t;
begin
  select count(*) into l_before from ap_approvals;
  l_first := ap_approvals_no_seq.nextval;

  l_args := json_object_t('{"note":"a run that is about to be taken back"}');
  l_args.put(uc_ai.c_run_context_key
           , json_object_t('{"invoice_id":"7001","clerk":"petra.k"}'));

  sys.dbms_output.put_line(ap_desk_pkg.approve_invoice(l_args.to_clob));

  rollback;

  select count(*) into l_after from ap_approvals;
  l_second := ap_approvals_no_seq.nextval;

  sys.dbms_output.put_line('approvals before ' || l_before
    || ', after the rollback ' || l_after);
  -- The row went. The number did not come back with it, so a gap in the
  -- approval numbers is the record of an attempt that was taken back.
  sys.dbms_output.put_line('approval numbers went ' || l_first || ' -> ' || l_second
    || ', so ' || (l_second - l_first - 1) || ' number(s) are gone');
end;
/

-- ---------------------------------------------------------------------------
-- Verification 3 — what the model is told when your own code breaks
-- ---------------------------------------------------------------------------
-- The same failure, shaped two ways. A handler that returns sqlerrm hands the
-- model your table names, your column names and your line numbers, and the
-- model repeats them to the clerk, who forwards the mail to the supplier.
declare
  l_num   number;
  l_naive varchar2(4000 char);
  l_ref   varchar2(30 char);
begin
  begin
    -- The kind of thing that goes wrong in a real handler.
    select i.po_no into l_num from ap_invoices i where i.id = 7001;
  exception
    when others then
      -- @dblinter ignore(g-5040): this block exists to capture one error in two shapes
      l_naive := 'Error executing tool: ' || sqlerrm;
      l_ref   := ap_desk_pkg.log_error(sqlerrm, sys.dbms_utility.format_error_backtrace);
  end;

  sys.dbms_output.put_line('a handler that returns sqlerrm hands the model:');
  sys.dbms_output.put_line('   ' || l_naive);
  sys.dbms_output.put_line('ap_desk_pkg hands the model:');
  sys.dbms_output.put_line('   The approval could not be completed. Quote reference '
    || l_ref || ' to support.');
end;
/

prompt
prompt What was recorded, and never shown to the model:
set feedback off
select error_ref, substr(message, 1, 60) as message
  from ap_desk_errors order by id desc fetch first 3 rows only;
set feedback on

-- Clear the hook, so it does not affect your next experiment.
begin
  uc_ai_agents_api.set_execution_hook(null);
  rollback;
end;
/
