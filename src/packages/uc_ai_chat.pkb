-- @dblinter ignore(G-7210): one package per plug-in entry point is the APEX
-- contract here -- render_region, ajax_region and the scheduler job's
-- execute_agent_job must live together because the job reads rows the AJAX
-- handler wrote and both share the private helpers. Splitting on size alone
-- would put that shared state behind a package boundary for no gain. Revisit by
-- extracting a cohesive area (the AI turn lifecycle, say), not by cutting at a
-- line count.
-- @dblinter ignore(G-7220): the private helpers are not forward declared. Each one sits
-- immediately above its first use, which is what makes a 2000-line plug-in body readable
-- top to bottom; forward declaring all nineteen would duplicate every signature and add a
-- second place to keep in step for no reader's benefit.
create or replace package body uc_ai_chat as

  -- ============================================================================
  -- Constants
  -- ============================================================================
  c_scope constant varchar2(100 char) := 'uc_ai_chat';

  -- Guardrail vocabulary reported to the client. Deliberately coarse: the client
  -- turns a kind into generic copy that names no limit, no figure and no
  -- percentage, so nothing about the governance configuration leaks to an end
  -- user. The precise sqlerrm stays in error_detail behind the show_errors flag.
  c_gr_state_warn  constant varchar2(10 char) := 'warn';
  c_gr_state_hit   constant varchar2(10 char) := 'hit';

  c_gr_budget      constant varchar2(20 char) := 'budget';
  c_gr_rate        constant varchar2(20 char) := 'rate';
  c_gr_tool_rate   constant varchar2(20 char) := 'tool_rate';
  c_gr_concurrency constant varchar2(20 char) := 'concurrency';

  -- What to do when the run context resolved for a turn no longer matches the
  -- one the conversation is already bound to (a page item changed under an open
  -- chat). UC AI binds the context on a session's first turn and refuses a
  -- changed key with ORA-20507, so the plug-in has to take a position -- and
  -- which position is right depends on the app, so the developer picks it.
  c_ctx_drift_error  constant varchar2(20 char) := 'error';
  c_ctx_drift_new    constant varchar2(20 char) := 'new_session';
  c_ctx_drift_ignore constant varchar2(20 char) := 'ignore';

  -- Whether the optional UC AI Pro guardrail APIs are callable from here.
  -- Resolved lazily on first probe and cached for the session (see
  -- probe_guardrails for why this is a call attempt rather than a dictionary
  -- lookup).
  -- @dblinter ignore(g-7230): session-scoped feature-detection cache, resolved once
  g_gr_probe_ok    boolean := true;

  -- ============================================================================
  -- Helper: get region ID string (R<id> or static ID)
  -- ============================================================================
  function get_region_id_rec(
    p_region in apex_plugin.t_region
  ) return varchar2
  is
    l_static_id apex_application_page_regions.static_id%type;
  begin
    select static_id
      into l_static_id
      from apex_application_page_regions
     where region_id = p_region.id
       and application_id = v('APP_ID')
       and page_id = v('APP_PAGE_ID');

    if l_static_id is not null then
      return l_static_id;
    end if;

    return 'R' || p_region.id;
  exception
    when no_data_found then
      return 'R' || p_region.id;
  end get_region_id_rec;

  -- ============================================================================
  -- Helper: parse debug_config JSON attribute into Y/N flags
  -- ============================================================================
  procedure get_debug_flags(
    p_region          in  apex_plugin.t_region,
    po_show_reasoning out varchar2,
    po_show_tools     out varchar2,
    po_show_metadata  out varchar2,
    po_show_errors    out varchar2,
    po_show_debug     out varchar2
  )
  is
    l_func_body  varchar2(32767 char);
    l_config_str clob;
    l_config_obj json_object_t;
  begin
    po_show_reasoning := 'N';
    po_show_tools     := 'N';
    po_show_metadata  := 'N';
    po_show_errors    := 'N';
    po_show_debug     := 'N';

    -- The debug_config plug-in attribute is a "PL/SQL Function Body" type:
    -- the stored value is the source of a function that returns a JSON
    -- string. get_varchar2 returns the raw source; we must execute it via
    -- apex_plugin_util.get_plsql_func_result_clob to get the JSON.
    l_func_body := p_region.attributes.get_varchar2('debug_config');

    if l_func_body is null then
      return;
    end if;

    begin
      l_config_str := apex_plugin_util.get_plsql_func_result_clob(
        p_plsql_function => l_func_body
      );
    exception
      when others then -- @dblinter ignore(G-5040)
        apex_debug.warn(
          '%s | debug_config function raised an error, defaulting all flags to off: %s - %s',
          c_scope,
          sqlerrm,
          sys.dbms_utility.format_error_backtrace
        );
        return;
    end;

    if l_config_str is null or sys.dbms_lob.getlength(l_config_str) = 0 then
      return;
    end if;

    begin
      l_config_obj := json_object_t.parse(l_config_str);
    exception
      when others then -- @dblinter ignore(G-5040)
        apex_debug.warn(
          '%s | Invalid debug_config JSON, defaulting all flags to off: %s - %s',
          c_scope,
          sqlerrm,
          sys.dbms_utility.format_error_backtrace
        );
        return;
    end;

    if l_config_obj.has('show_reasoning') and l_config_obj.get_boolean('show_reasoning') then
      po_show_reasoning := 'Y';
    end if;
    if l_config_obj.has('show_tools') and l_config_obj.get_boolean('show_tools') then
      po_show_tools := 'Y';
    end if;
    if l_config_obj.has('show_metadata') and l_config_obj.get_boolean('show_metadata') then
      po_show_metadata := 'Y';
    end if;
    if l_config_obj.has('show_errors') and l_config_obj.get_boolean('show_errors') then
      po_show_errors := 'Y';
    end if;
    if l_config_obj.has('show_debug') and l_config_obj.get_boolean('show_debug') then
      po_show_debug := 'Y';
    end if;
  end get_debug_flags;

  -- ============================================================================
  -- Helper: assert the current user owns the given AI chat session.
  -- A brand-new session (no rows yet) is allowed: the caller establishes
  -- ownership with the first message. Once a session has rows, only the user
  -- who created them may read or append to it.
  -- ============================================================================
  procedure assert_session_owner(
    p_session_id in varchar2,
    p_user       in varchar2
  )
  is
    l_session_cnt   pls_integer;
    l_owned_cnt     pls_integer;
    l_core_owner    uc_ai_agent_sessions.apex_user%type;
  begin
    select count(*)
      into l_session_cnt
      from uc_ai_chat_messages
     where session_id = p_session_id
       and rownum = 1;

    -- New session (no plug-in rows yet): the first message establishes
    -- ownership. Guard against claiming a session id that the core agent
    -- framework already opened under a different APEX user.
    if l_session_cnt = 0 then
      begin
        select apex_user
          into l_core_owner
          from uc_ai_agent_sessions
         where session_id = p_session_id;
      exception
        when no_data_found then
          l_core_owner := null;
      end;

      if l_core_owner is not null and l_core_owner != p_user then
        apex_debug.error(
          '%s | User %s attempted to claim session %s already owned by %s in the core framework',
          c_scope, p_user, p_session_id, l_core_owner
        );
        raise_application_error(-20002, 'You are not authorized to access this conversation.');
      end if;

      return;
    end if;

    select count(*)
      into l_owned_cnt
      from uc_ai_chat_messages
     where session_id = p_session_id
       and created_by = p_user
       and rownum = 1;

    if l_owned_cnt = 0 then
      apex_debug.error(
        '%s | User %s attempted to access session %s owned by another user',
        c_scope, p_user, p_session_id
      );
      raise_application_error(-20002, 'You are not authorized to access this conversation.');
    end if;
  end assert_session_owner;

  -- ============================================================================
  -- Helper: set the lifecycle status of a turn (the 'user' row) in its own
  -- autonomous transaction, so status flips are visible to pollers immediately
  -- and independent of the caller's transaction. The update is guarded by the
  -- expected current status (optimistic concurrency): a legacy NULL status is
  -- treated as 'pending'. po_updated reports whether the row actually changed.
  -- ============================================================================
  procedure set_turn_status(
    p_user_msg_id  in number,
    p_status       in varchar2,
    p_expected     in apex_t_varchar2,
    p_error_detail in varchar2 default null,
    p_execution_id in number   default null,
    po_updated     out boolean
  )
  is
    -- @dblinter ignore(G-3330) Autonomous: status must be visible to pollers now
    pragma autonomous_transaction;
    l_rows pls_integer;
  begin
    update uc_ai_chat_messages
       set turn_status  = p_status,
           error_detail = coalesce(p_error_detail, error_detail),
           execution_id = coalesce(p_execution_id, execution_id)
     where id = p_user_msg_id
       and role = 'user'
       and (turn_status member of p_expected or turn_status is null);

    l_rows := sql%rowcount;
    commit;
    po_updated := l_rows > 0;
  end set_turn_status;

  -- ============================================================================
  -- Helper: read the conversation title from the core session header. The core
  -- framework owns the conversation (uc_ai_agent_sessions is keyed on the same
  -- session_id we use), so the title lives there and any uc-ai front end can
  -- read it. Returns null while the header does not exist yet: a session only
  -- gets one once its first top-level execution starts.
  -- ============================================================================
  function get_session_title(
    p_session_id in varchar2
  ) return varchar2
  is
    l_title varchar2(200 char);
  begin
    select s.title
      into l_title
      from uc_ai_agent_sessions s
     where s.session_id = p_session_id;

    return l_title;
  exception
    when no_data_found then
      return null;
  end get_session_title;

  -- ============================================================================
  -- Helper: read the end user's feedback from the core session header, which is
  -- where it lives for the same reason the title does — rating a conversation is
  -- not specific to this plug-in. Both OUT params stay null while the header does
  -- not exist yet, and a null rating means "not rated", never "rated neutral".
  -- ============================================================================
  procedure get_session_feedback(
    p_session_id in            varchar2,
    po_rating    out nocopy    varchar2,
    po_comment   out nocopy    varchar2
  )
  is
  begin
    select s.feedback_rating
         , s.feedback_comment
      into po_rating
         , po_comment
      from uc_ai_agent_sessions s
     where s.session_id = p_session_id;
  exception
    when no_data_found then
      po_rating  := null;
      po_comment := null;
  end get_session_feedback;

  -- ============================================================================
  -- Helper: detect and mark a turn whose background job never ran or died.
  -- Called from AI_FETCH_MESSAGES for the latest user row. Best-effort: any
  -- error here is logged and swallowed so a fetch can never fail because of it.
  -- ============================================================================
  procedure check_orphaned_turn(
    p_user_msg_id in number,
    p_session_id  in varchar2,
    p_status      in varchar2,
    p_created_at  in timestamp
  )
  is
    c_pending_grace_min constant number := 2;
    c_running_grace_min constant number := 1;
    l_job_exists    pls_integer;
    l_answer_exists pls_integer;
    l_updated       boolean;
    l_grace_min  number;
    l_detail     varchar2(4000 char);
  begin
    -- Only a pending/processing (or legacy NULL) turn can be orphaned.
    if p_status is not null and p_status not in ('pending', 'processing') then
      return;
    end if;

    -- A turn that already has a later assistant row is complete, not orphaned.
    -- (Covers upgraded installs whose historical user rows were never backfilled
    -- and so still have a NULL turn_status.)
    select case
             when exists (
               select 1
                 from uc_ai_chat_messages
                where session_id = p_session_id
                  and role = 'assistant'
                  and id > p_user_msg_id
             ) then 1 else 0
           end
      into l_answer_exists
      from dual;

    if l_answer_exists = 1 then
      return;
    end if;

    if p_status = 'processing' then
      l_grace_min := c_running_grace_min;
      l_detail    := 'Background job UC_AI_EXEC_' || p_user_msg_id || ' terminated unexpectedly.';
    else
      l_grace_min := c_pending_grace_min;
      l_detail    := 'Background job UC_AI_EXEC_' || p_user_msg_id || ' is not scheduled; it may have failed to start.';
    end if;

    -- Still inside the grace window: give the job time to start/finish.
    --
    -- cast(systimestamp as timestamp), not systimestamp: created_at is a plain
    -- TIMESTAMP filled from systimestamp, so it holds the DB HOST wall clock with
    -- the zone truncated. Comparing it against a TIMESTAMP WITH TIME ZONE makes
    -- Oracle promote the naked side using SESSIONTIMEZONE, which shifts it by the
    -- session/host offset -- with a session ahead of the host (e.g. Europe/Berlin
    -- against a UTC host) every turn instantly looks older than the grace window
    -- and healthy in-flight turns get marked as errors. The cast puts both sides
    -- in the same frame the column was written in, so the arithmetic is honest
    -- regardless of the caller's time zone.
    -- @dblinter ignore(G-9010): a format model is meaningless here -- this casts TIMESTAMP WITH TIME ZONE to TIMESTAMP, with no string representation involved
    if p_created_at >= cast(systimestamp as timestamp)
                       - numtodsinterval(l_grace_min * 60, 'SECOND') then
      return;
    end if;

    select case
             when exists (
               select 1
                 from user_scheduler_jobs
                where job_name = 'UC_AI_EXEC_' || p_user_msg_id
             ) then 1 else 0
           end
      into l_job_exists
      from dual;

    if l_job_exists = 0 then
      set_turn_status(
        p_user_msg_id  => p_user_msg_id,
        p_status       => 'error',
        p_expected     => apex_t_varchar2('pending', 'processing'),
        p_error_detail => l_detail,
        po_updated     => l_updated
      );
      apex_debug.warn('%s | Marked orphaned turn %s as error: %s', c_scope, p_user_msg_id, l_detail);
    end if;
  exception
    when others then -- @dblinter ignore(G-5040)
      apex_debug.warn(
        '%s | check_orphaned_turn failed for msg %s: %s',
        c_scope, p_user_msg_id, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end check_orphaned_turn;

  -- ============================================================================
  -- Helper: is the optional progressive-progress hook safe to activate?
  -- Requires UC_AI_CHAT_HOOK (a valid package body in this schema) AND that the
  -- core agent framework can actually call back into it. When the core lives in
  -- another schema (the usual shared install), the core dispatches before_execution
  -- unconditionally and PROPAGATES a failure, so a missing cross-schema EXECUTE
  -- grant would veto every run — hence we only enable when a grant (or PUBLIC)
  -- exists. Same-schema installs need no grant.
  -- ============================================================================
  function progress_hook_ready return boolean
  is
    -- @dblinter ignore(G-2160): reading standard session context does not raise in practice
    l_schema      varchar2(128 char) := sys_context('userenv', 'current_schema');
    l_hook_exists pls_integer;
    l_core_owner  varchar2(128 char);
    l_grant_exists pls_integer;
  begin
    select case
             when exists (
               select 1
                 from user_objects
                where object_name = 'UC_AI_CHAT_HOOK'
                  and object_type = 'PACKAGE BODY'
                  and status = 'VALID'
             ) then 1 else 0
           end
      into l_hook_exists
      from dual;

    if l_hook_exists = 0 then
      return false;
    end if;

    -- Which schema owns the core package this plug-in dispatches through?
    begin
      select referenced_owner
        into l_core_owner
        from all_dependencies
       where owner = l_schema
         and name = 'UC_AI_CHAT'
         and type = 'PACKAGE BODY'
         and referenced_name = 'UC_AI_AGENTS_API'
         and rownum = 1;
    exception
      when no_data_found then
        l_core_owner := l_schema;
    end;

    if l_core_owner = l_schema then
      return true; -- same schema: no grant needed
    end if;

    select case
             when exists (
               select 1
                 from all_tab_privs
                where table_schema = l_schema
                  and table_name = 'UC_AI_CHAT_HOOK'
                  and privilege = 'EXECUTE'
                  and grantee in (l_core_owner, 'PUBLIC')
             ) then 1 else 0
           end
      into l_grant_exists
      from dual;

    if l_grant_exists = 0 then
      apex_debug.warn(
        '%s | UC_AI_CHAT_HOOK is installed but %s has no EXECUTE grant on it; ' ||
        'progressive tool progress disabled. Grant execute on %s.UC_AI_CHAT_HOOK to %s to enable.',
        c_scope, l_core_owner, l_schema, l_core_owner
      );
      return false;
    end if;

    return true;
  exception
    when others then -- @dblinter ignore(G-5040)
      apex_debug.warn('%s | progress_hook_ready check failed, disabling hook: %s', c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      return false;
  end progress_hook_ready;

  -- ============================================================================
  -- Helper: classify a captured error as a guardrail denial.
  --
  -- Pure text classification of a stored sqlerrm, so it needs no UC AI Pro
  -- objects and stays testable on a plain core install. Returns null for
  -- anything that is not a guardrail, which is what keeps a provider outage
  -- reading as an outage.
  -- ============================================================================
  function guardrail_kind(
    p_error in varchar2
  ) return varchar2
  is
  begin
    if p_error is null then
      return null;
    end if;

    -- ORA-20411/20412/20413 belong to the pro rate-limit hook alone, so the code
    -- identifies them on its own. ORA-20401 does NOT: core's uc_ai_error declares
    -- c_err_unknown_workflow_type as -20401 as well, so the budget hook's message
    -- text has to confirm it. That text is a deliberately stable contract - both
    -- pro hook bodies note that customers match on it.
    if instr(p_error, 'ORA-20411') > 0 then
      return c_gr_rate;
    elsif instr(p_error, 'ORA-20412') > 0 then
      return c_gr_tool_rate;
    elsif instr(p_error, 'ORA-20413') > 0 then
      return c_gr_concurrency;
    elsif instr(p_error, 'ORA-20401') > 0
      and p_error like '%Budget "%" exceeded%'
    then
      return c_gr_budget;
    end if;

    return null;
  end guardrail_kind;

  -- ============================================================================
  -- Helper: does a captured error say the run context was re-bound?
  --
  -- uc_ai_error.c_err_run_context_conflict is -20507 and belongs to that one
  -- check, so the code identifies it on its own -- no message match needed, and
  -- no compile-time reference to a uc_ai constant that older cores lack.
  --
  -- The pre-flight check in AI_SEND_MESSAGE normally catches this first; this
  -- covers what slips past it (a second tab sending concurrently, or a turn
  -- whose baseline row was not written yet), so a re-binding reads as a
  -- re-binding rather than as a generic outage.
  -- ============================================================================
  function is_context_conflict(
    p_error in varchar2
  ) return boolean
  is
  begin
    return p_error is not null and instr(p_error, 'ORA-20507') > 0;
  end is_context_conflict;

  -- ============================================================================
  -- Helper: ask the optional UC AI Pro guardrails where the caller stands.
  --
  -- Returns po_state 'warn' (past a limit's warn threshold) or 'hit' (a hard
  -- limit is already exhausted, so the next run will be refused), else null.
  -- Never raises and never blocks a send: the database guardrail stays the only
  -- enforcer, this only makes its verdict legible.
  --
  -- Invoked through dynamic PL/SQL because the pro packages are absent on a core
  -- install and a static reference would not compile. There is deliberately no
  -- dictionary pre-check: whether the packages are *callable* from here depends
  -- on schema, synonyms and grants, and the one thing that answers all three at
  -- once is trying. The outcome is cached for the session, so a core install pays
  -- a single failed parse.
  --
  -- p_audience / p_apex_session_id are deliberately left to the APIs, which
  -- classify the caller from the live APEX session. That is only the same caller
  -- the background job will present if session_init_code attaches an APEX
  -- session - see docs/ai-chat-mode.md.
  -- ============================================================================
  procedure probe_guardrails(
    p_agent_code in  varchar2,
    p_user       in  varchar2,
    po_state     out varchar2,
    po_kind      out varchar2
  )
  is
    l_rate_dec  varchar2(10 char);
    l_rate_type varchar2(20 char);
    l_tool_dec  varchar2(10 char);
    l_budg_dec  varchar2(10 char);

    -- @dblinter ignore(G-2160): reading standard APEX session state (v) does not raise in practice
    l_app_id    number := to_number(v('APP_ID'));

    -- Binds are copied into locals so every placeholder appears exactly once.
    c_stmt constant varchar2(1400 char) := q'[
declare
  l_user  varchar2(255 char) := :b_user;
  l_agent varchar2(255 char) := :b_agent;
  l_app   number             := :b_app;
  l_rate  uc_ai_ratelimit_api.t_rate_check;
  l_tool  uc_ai_ratelimit_api.t_rate_check;
  l_budg  uc_ai_budget_api.t_budget_check;
begin
  l_rate := uc_ai_ratelimit_api.check_limits(
              p_created_by  => l_user,
              p_agent_code  => l_agent,
              p_apex_app_id => l_app
            );
  l_tool := uc_ai_ratelimit_api.check_tool_limit(
              p_created_by  => l_user,
              p_agent_code  => l_agent,
              p_apex_app_id => l_app
            );
  l_budg := uc_ai_budget_api.check_budgets(
              p_created_by  => l_user,
              p_agent_code  => l_agent,
              p_apex_app_id => l_app
            );
  :o_rate_dec  := l_rate.decision;
  :o_rate_type := l_rate.limit_type;
  :o_tool_dec  := l_tool.decision;
  :o_budg_dec  := l_budg.decision;
end;]';
  begin
    if not g_gr_probe_ok then
      return;
    end if;

    execute immediate c_stmt
      using in p_user, in p_agent_code, in l_app_id,
            out l_rate_dec, out l_rate_type, out l_tool_dec, out l_budg_dec;

    -- Rate limiting registers ahead of budgets in the pro dispatcher (sort_order
    -- 50 vs 100), so a rate denial short-circuits before any cost pricing runs.
    -- Attribute the notice in that same order, so the reason the user is given
    -- matches the reason a run would actually be refused. 'advisory' limits never
    -- yield warn or deny, so they correctly stay invisible here.
    if l_rate_dec = 'deny' then
      po_state := c_gr_state_hit;
      po_kind  := case when l_rate_type = 'CONCURRENCY' then c_gr_concurrency else c_gr_rate end;
    elsif l_tool_dec = 'deny' then
      po_state := c_gr_state_hit;
      po_kind  := c_gr_tool_rate;
    elsif l_budg_dec = 'deny' then
      po_state := c_gr_state_hit;
      po_kind  := c_gr_budget;
    elsif l_rate_dec = 'warn' then
      po_state := c_gr_state_warn;
      po_kind  := case when l_rate_type = 'CONCURRENCY' then c_gr_concurrency else c_gr_rate end;
    elsif l_tool_dec = 'warn' then
      po_state := c_gr_state_warn;
      po_kind  := c_gr_tool_rate;
    elsif l_budg_dec = 'warn' then
      po_state := c_gr_state_warn;
      po_kind  := c_gr_budget;
    end if;
  exception
    when others then -- @dblinter ignore(G-5040)
      -- No guardrails installed, not callable from here, or a transient failure.
      -- Either way this is a nicety: stop probing for the session rather than
      -- risk repeating the cost, and never let it affect the chat.
      g_gr_probe_ok := false;
      po_state      := null;
      po_kind       := null;
      -- Backtrace included because absence is only the benign cause; an invalid
      -- pro package body or a missing cross-schema grant lands here too, and
      -- that is not diagnosable from sqlerrm alone.
      apex_debug.info(
        '%s | guardrail probe unavailable, disabled for this session: %s',
        c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end probe_guardrails;

  -- ============================================================================
  -- Helper: emit the "guardrail" member of an open AJAX response object.
  -- Written unconditionally when there is something to say (it is user-facing
  -- and carries no figures), unlike errorDetail which is show_errors-gated.
  -- ============================================================================
  procedure write_guardrail(
    p_agent_code in varchar2,
    p_user       in varchar2
  )
  is
    l_state varchar2(10 char);
    l_kind  varchar2(20 char);
  begin
    probe_guardrails(
      p_agent_code => p_agent_code,
      p_user       => p_user,
      po_state     => l_state,
      po_kind      => l_kind
    );

    if l_state is not null then
      apex_json.open_object('guardrail');
      apex_json.write('state', l_state);
      apex_json.write('kind', l_kind);
      apex_json.close_object;
    end if;
  end write_guardrail;

  -- ============================================================================
  -- Helper: recursively substitute APEX item references (&ITEM.) and the
  -- #USER_MESSAGE# placeholder inside every string value of a parsed JSON
  -- object/array. Substituting *after* parsing means an item value (or the user
  -- message) containing a double quote can no longer break JSON parsing or
  -- inject structure — the JSON API re-escapes each value on put().
  -- ============================================================================
  procedure substitute_json_strings(
    pio_obj        in out nocopy json_object_t,
    p_user_message in clob
  );

  procedure substitute_json_value_array(
    pio_arr        in out nocopy json_array_t,
    p_user_message in clob
  )
  is
    l_el      json_element_t;
    l_val     clob;
    l_child_o json_object_t;
    l_child_a json_array_t;
  begin
    <<array_elements>>
    for i in 0 .. pio_arr.get_size - 1 loop
      l_el := pio_arr.get(i);
      if l_el.is_string then
        l_val := pio_arr.get_string(i);
        l_val := apex_plugin_util.replace_substitutions(l_val);
        l_val := replace(l_val, '#USER_MESSAGE#', p_user_message);
        pio_arr.put(i, l_val);
      elsif l_el.is_object then
        l_child_o := treat(l_el as json_object_t);
        substitute_json_strings(l_child_o, p_user_message);
        pio_arr.put(i, l_child_o);
      elsif l_el.is_array then
        l_child_a := treat(l_el as json_array_t);
        substitute_json_value_array(l_child_a, p_user_message);
        pio_arr.put(i, l_child_a);
      end if;
    end loop array_elements;
  end substitute_json_value_array;

  procedure substitute_json_strings(
    pio_obj        in out nocopy json_object_t,
    p_user_message in clob
  )
  is
    l_keys    json_key_list := pio_obj.get_keys;
    l_el      json_element_t;
    l_val     clob;
    l_child_o json_object_t;
    l_child_a json_array_t;
  begin
    <<object_keys>>
    for i in 1 .. l_keys.count loop
      l_el := pio_obj.get(l_keys(i));
      if l_el.is_string then
        l_val := pio_obj.get_clob(l_keys(i));
        l_val := apex_plugin_util.replace_substitutions(l_val);
        l_val := replace(l_val, '#USER_MESSAGE#', p_user_message);
        pio_obj.put(l_keys(i), l_val);
      elsif l_el.is_object then
        l_child_o := pio_obj.get_object(l_keys(i));
        substitute_json_strings(l_child_o, p_user_message);
        pio_obj.put(l_keys(i), l_child_o);
      elsif l_el.is_array then
        l_child_a := pio_obj.get_array(l_keys(i));
        substitute_json_value_array(l_child_a, p_user_message);
        pio_obj.put(l_keys(i), l_child_a);
      end if;
    end loop object_keys;
  end substitute_json_strings;

  -- ============================================================================
  -- Helper: read one run-context key as a scalar string.
  --
  -- Mirrors uc_ai.run_context_value's reading so the plug-in's pre-flight check
  -- and the engine's own binding check agree on what "bound" means: a key that
  -- is absent, or present as JSON null, carries no value. Non-strings are
  -- compared by their JSON rendering, which is what makes 7 and "7" different
  -- values rather than a false match.
  -- ============================================================================
  function ctx_value(
    p_obj in json_object_t,
    p_key in varchar2
  ) return varchar2
  is
    l_el json_element_t;
  begin
    if p_obj is null or not p_obj.has(p_key) then
      return null;
    end if;

    l_el := p_obj.get(p_key);

    if l_el is null or l_el.is_null then
      return null;
    elsif l_el.is_string then
      return substr(p_obj.get_string(p_key), 1, 4000);
    end if;

    return substr(l_el.to_string, 1, 4000);
  end ctx_value;

  -- ============================================================================
  -- Helper: has the run context drifted away from what this conversation is
  -- bound to? Returns the name of the first re-bound key, or null.
  --
  -- The baseline is the newest non-null run_context this region already stored
  -- on the conversation, not uc_ai_agent_sessions.run_context: keys only ever
  -- accumulate, so the newest row holds the whole effective bag, and reading our
  -- own table answers the question that actually matters here ("what did this
  -- region bind") without depending on a core column.
  --
  -- Adding a key is not a conflict -- UC AI allows that, and so does this. Only
  -- changing a key that already holds a value is.
  -- ============================================================================
  function run_context_conflict(
    p_session_id in varchar2,
    p_new_ctx    in json_object_t
  ) return varchar2
  is
    l_base_str clob;
    l_base     json_object_t;
    l_keys     json_key_list;
    l_key      varchar2(4000 char);
    l_existing varchar2(4000 char);
    l_new      varchar2(4000 char);
  begin
    if p_session_id is null or p_new_ctx is null then
      return null;
    end if;

    begin
      select run_context
        into l_base_str
        from uc_ai_chat_messages
       where session_id = p_session_id
         and role = 'user'
         and run_context is not null
       order by id desc
       fetch first 1 rows only;
    exception
      when no_data_found then
        -- First turn of the conversation: nothing is bound yet.
        return null;
    end;

    begin
      l_base := json_object_t.parse(l_base_str);
    exception
      when others then -- @dblinter ignore(G-5040)
        -- A baseline we cannot read must not block the send; the engine's own
        -- -20507 check remains as the backstop.
        apex_debug.warn(
          '%s | Stored run context for session %s is not readable, skipping drift check: %s',
          c_scope, p_session_id, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
        return null;
    end;

    l_keys := p_new_ctx.get_keys;

    <<context_keys>>
    for i in 1 .. l_keys.count loop
      l_key      := l_keys(i);
      l_existing := ctx_value(l_base, l_key);
      l_new      := ctx_value(p_new_ctx, l_key);

      if l_existing is not null and l_new is not null and l_new != l_existing then
        return l_key;
      end if;
    end loop context_keys;

    return null;
  end run_context_conflict;

  -- ============================================================================
  -- Widgets (see uc_ai_chat_widgets)
  --
  -- The enabled types come from the region attribute only, are normalised here
  -- and stored on the user row. The job renders once after the run and stores
  -- the parts on the assistant row; AI_FETCH_MESSAGES only emits that snapshot.
  -- ============================================================================

  -- One attribute as text; null when it is empty or the export does not have it
  -- (the attributes are added to the plug-in by a re-export).
  function widget_attribute(
    p_region in apex_plugin.t_region,
    p_name   in varchar2
  ) return varchar2
  is
  begin
    return p_region.attributes.get_varchar2(p_name);
  exception
    when others then -- @dblinter ignore(G-5040): a missing or unreadable attribute means "none", never a failed send
      apex_debug.warn(
        '%s | attribute %s not readable: %s - %s',
        c_scope, p_name, sqlerrm, sys.dbms_utility.format_error_backtrace
      );
      return null;
  end widget_attribute;

  -- The widget types this region enables, normalised; null = feature off.
  -- "widgets" holds the checked built-in types (colon separated by APEX);
  -- "custom_widgets" holds registered custom types, written by hand,
  -- separated by colon, comma, semicolon or white space. Both go through
  -- uc_ai_chat_widgets.normalize_types, which drops anything that is not a
  -- built-in type or a registered, enabled one, so a typo only switches that
  -- type off.
  function region_widget_types(
    p_region in apex_plugin.t_region
  ) return varchar2
  is
    l_builtin varchar2(4000 char);
    l_custom  varchar2(4000 char);
    l_types   varchar2(4000 char);
    l_result  varchar2(200 char);
  begin
    l_builtin := widget_attribute(p_region, 'widgets');
    l_custom := regexp_replace(trim(widget_attribute(p_region, 'custom_widgets')), '[,;:[:space:]]+', ':');
    l_types := case
                 when l_builtin is not null and l_custom is not null then l_builtin || ':' || l_custom
                 else coalesce(l_builtin, l_custom)
               end;
    l_result := uc_ai_chat_widgets.normalize_types(l_types);

    -- a name in the custom list that did not survive is a typo or an unregistered type
    <<c_loop>>
    for i in 1 .. nvl(regexp_count(l_custom, '[^:]+'), 0) loop
      if not uc_ai_chat_widgets.type_in_list(l_result, lower(regexp_substr(l_custom, '[^:]+', 1, i))) then
        apex_debug.warn(
          '%s | custom widget type "%s" is not registered or not enabled and is ignored',
          c_scope, regexp_substr(l_custom, '[^:]+', 1, i)
        );
      end if;
    end loop c_loop;
    return l_result;
  end region_widget_types;

  -- The tool calls of one execution in call order, shaped for
  -- uc_ai_chat_widgets.render: {"name","args","output"}. A call is paired with
  -- its result on tool_call_id; a row from before the core column has none, so
  -- those pair by order within the same tool name. Output that is not valid JSON
  -- is left out of the entry.
  function widget_tool_calls(
    p_execution_id in number
  ) return json_array_t
  is
    l_calls json_array_t := json_array_t();
    l_call  json_object_t;
    l_el    json_element_t;
  begin
    <<call_loop>>
    for rec in (
      with calls as (
        select m.seq, m.tool_name, m.tool_input, m.tool_call_id,
               row_number() over (partition by m.tool_name order by m.seq) as rn
          from uc_ai_agent_messages m
         where m.execution_id = p_execution_id
           and m.role = 'tool_call'
      ),
      results as (
        select m.tool_name, m.tool_output, m.tool_call_id,
               row_number() over (partition by m.tool_name order by m.seq) as rn
          from uc_ai_agent_messages m
         where m.execution_id = p_execution_id
           and m.role = 'tool_result'
      )
      select c.tool_name, c.tool_input, r.tool_output
        from calls c
        left join results r
          on (c.tool_call_id is not null and r.tool_call_id = c.tool_call_id)
          or (c.tool_call_id is null and r.tool_call_id is null
              and r.tool_name = c.tool_name and r.rn = c.rn)
       order by c.seq
    ) loop
      l_call := json_object_t();
      l_call.put('name', rec.tool_name);

      begin
        l_call.put('args', json_object_t.parse(rec.tool_input));
      exception
        when others then -- @dblinter ignore(G-5040): arguments that are not JSON are kept as text and match no "args"
          l_call.put('args', rec.tool_input);
      end;

      if rec.tool_output is not null then
        begin
          l_el := json_element_t.parse(rec.tool_output);
          l_call.put('output', l_el);
        exception
          when others then -- @dblinter ignore(G-5040): output that is not JSON has no usable rows; the call stays without 'output'
            null;
        end;
      end if;

      l_calls.append(l_call);
    end loop call_loop;

    return l_calls;
  end widget_tool_calls;

  -- The snapshot to store on the assistant row: the rendered parts as JSON, but
  -- only when the answer holds a widget or a rejected one. A plain answer (or
  -- widgets off) returns null and costs nothing. Never raises: a failure in the
  -- widgets code must not fail the turn, the answer then shows as plain text.
  function render_parts_snapshot(
    p_answer       in clob,
    p_types        in varchar2,
    p_execution_id in number
  ) return clob
  is
    l_parts json_array_t;
    l_part  json_object_t;
    l_keep  boolean := false;
  begin
    if p_types is null or p_answer is null then
      return null;
    end if;

    l_parts := uc_ai_chat_widgets.render(
      p_answer     => p_answer,
      p_types      => p_types,
      p_tool_calls => widget_tool_calls(p_execution_id)
    );

    <<part_loop>>
    for i in 0 .. l_parts.get_size - 1 loop
      l_part := treat(l_parts.get(i) as json_object_t);
      if l_part.get_string('kind') = 'widget' or l_part.has('rejected') then
        l_keep := true;
        exit part_loop;
      end if;
    end loop part_loop;

    if l_keep then
      return l_parts.to_clob;
    end if;
    return null;
  exception
    when others then -- @dblinter ignore(G-5040): a failure in the widgets code must never fail the turn
      apex_debug.error(
        '%s | widget snapshot failed for execution %s, answer stays plain text: %s - %s',
        c_scope, p_execution_id, sqlerrm, sys.dbms_utility.format_error_backtrace
      );
      return null;
  end render_parts_snapshot;

  -- ============================================================================
  -- RENDER_REGION
  -- ============================================================================
  procedure render_region(
    -- @dblinter ignore(G-7150)
    p_plugin in            apex_plugin.t_plugin,
    p_region in            apex_plugin.t_region,
    p_param  in            apex_plugin.t_region_render_param,
    p_result in out nocopy apex_plugin.t_region_render_result -- @dbLinter ignore(G-9110,G-7150,G-7330) For API compatibility
  )
  is
    l_region_id      varchar2(255 char);
    l_agent_code     varchar2(255 char);
    l_agent_version  varchar2(255 char);
    l_session_item   varchar2(255 char);
    l_session_id     varchar2(255 char);
    l_display_mode   varchar2(50 char);
    -- @dbLinter ignore(G-2410) Y/N flags (not boolean) so they can be used in SQL on pre-23ai databases
    l_show_reasoning varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_tools     varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_metadata  varchar2(1 char);
    -- @dbLinter ignore(G-2410) parsed for API symmetry; render_region does not expose it
    l_show_errors    varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_debug     varchar2(1 char);
    l_wc_id          varchar2(4000 char);
    l_prompts_raw    varchar2(32767 char);
    l_prompts_arr    json_array_t;
    l_prompts_json   varchar2(32767 char);
    l_header_title   varchar2(255 char);
    l_avatar_icon    varchar2(255 char);
    l_welcome_msg    varchar2(4000 char);
    l_min_height     varchar2(50 char);
    l_thinking_anim  varchar2(50 char);
    l_thinking_det   varchar2(50 char);
    -- @dbLinter ignore(G-2410) Y/N flag for consistency with the other plug-in switches
    l_auto_title     varchar2(1 char);
    -- @dbLinter ignore(G-2410) Y/N flag for consistency with the other plug-in switches
    l_collect_fb     varchar2(1 char);
  begin
    l_region_id     := get_region_id_rec(p_region);
    l_agent_code    := p_region.attributes.get_varchar2('agent_code');
    l_agent_version := p_region.attributes.get_varchar2('agent_version');
    l_session_item  := p_region.attributes.get_varchar2('session_item');
    l_display_mode  := nvl(p_region.attributes.get_varchar2('display_mode'), 'region');
    l_header_title  := p_region.attributes.get_varchar2('header_title');
    l_avatar_icon   := p_region.attributes.get_varchar2('avatar_icon');
    l_welcome_msg   := p_region.attributes.get_varchar2('welcome_message');
    l_min_height    := p_region.attributes.get_varchar2('min_height');
    l_auto_title    := nvl(upper(p_region.attributes.get_varchar2('auto_title')), 'N');
    l_collect_fb    := nvl(upper(p_region.attributes.get_varchar2('collect_feedback')), 'N');

    -- Style of the "AI is thinking" indicator. An unknown value falls back to
    -- the default rather than shipping a variant the frontend cannot render.
    l_thinking_anim := lower(p_region.attributes.get_varchar2('thinking_animation'));
    if l_thinking_anim not in ('dots', 'braille', 'plasma', 'matrix') then
      l_thinking_anim := null;
    end if;

    -- How much the indicator says while a turn runs. 'tools' names the running
    -- tool, 'status' shows only "Thinking..." + elapsed, 'off' shows no text.
    l_thinking_det := lower(p_region.attributes.get_varchar2('thinking_detail'));
    if l_thinking_det not in ('off', 'status', 'tools') then
      l_thinking_det := null;
    end if;

    -- Suggested prompts: a textarea attribute, one prompt per line. Build a JSON
    -- array so a prompt may safely contain commas / quotes.
    l_prompts_raw := p_region.attributes.get_varchar2('suggested_prompts');
    if l_prompts_raw is not null then
      l_prompts_arr := json_array_t();
      <<split_prompts>>
      for r in (
        select trim(column_value) as prompt
          from table(apex_string.split(l_prompts_raw, chr(10)))
         where trim(column_value) is not null
      ) loop
        l_prompts_arr.append(r.prompt);
      end loop split_prompts;
      if l_prompts_arr.get_size > 0 then
        l_prompts_json := l_prompts_arr.to_string;
      end if;
    end if;

    get_debug_flags(
      p_region          => p_region,
      po_show_reasoning => l_show_reasoning,
      po_show_tools     => l_show_tools,
      po_show_metadata  => l_show_metadata,
      po_show_errors    => l_show_errors,
      po_show_debug     => l_show_debug
    );

    -- Get session ID from page item if configured
    if l_session_item is not null then
      l_session_id := v(l_session_item);
    end if;

    l_wc_id := l_region_id || '_wc';

    -- Output the web component container
    sys.htp.p('<div id="' || apex_escape.html_attribute(l_wc_id) || '"></div>');

    -- Initialize the web component via JavaScript
    apex_javascript.add_onload_code(
      p_code => '(function(){let wc = document.createElement("uc-apex-chat");' ||
                'wc.regionId = ' || apex_escape.js_literal(l_region_id) || ';' ||
                'wc.ajaxId = ' || apex_escape.js_literal(apex_plugin.get_ajax_identifier) || ';' ||
                'wc.chatMode = "ai";' ||
                'wc.displayMode = ' || apex_escape.js_literal(l_display_mode) || ';' ||
                'wc.agentCode = ' || apex_escape.js_literal(l_agent_code) || ';' ||
                case when l_agent_version is not null
                  then 'wc.agentVersion = ' || to_number(l_agent_version default null on conversion error, '9999999999999999999999999999D9999999999', q'[nls_numeric_characters='.,']') || ';'
                  else cast(null as varchar2)
                end ||
                case when l_session_id is not null
                  then 'wc.sessionId = ' || apex_escape.js_literal(l_session_id) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_show_reasoning = 'Y'
                  then 'wc.showReasoning = true;'
                  else cast(null as varchar2)
                end ||
                case when l_show_tools = 'Y'
                  then 'wc.showTools = true;'
                  else cast(null as varchar2)
                end ||
                case when l_show_metadata = 'Y'
                  then 'wc.showMetadata = true;'
                  else cast(null as varchar2)
                end ||
                case when l_show_debug = 'Y'
                  then 'wc.showDebug = true;'
                  else cast(null as varchar2)
                end ||
                case when l_prompts_json is not null
                  then 'wc.suggestedPrompts = ' || apex_escape.js_literal(l_prompts_json) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_header_title is not null
                  then 'wc.headerTitle = ' || apex_escape.js_literal(l_header_title) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_avatar_icon is not null
                  then 'wc.avatarIcon = ' || apex_escape.js_literal(l_avatar_icon) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_welcome_msg is not null
                  then 'wc.welcomeMessage = ' || apex_escape.js_literal(l_welcome_msg) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_min_height is not null
                  then 'wc.minHeight = ' || apex_escape.js_literal(l_min_height) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_thinking_anim is not null
                  then 'wc.thinkingAnimation = ' || apex_escape.js_literal(l_thinking_anim) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_thinking_det is not null
                  then 'wc.thinkingDetail = ' || apex_escape.js_literal(l_thinking_det) || ';'
                  else cast(null as varchar2)
                end ||
                case when l_auto_title = 'Y'
                  then 'wc.autoTitle = true;'
                  else cast(null as varchar2)
                end ||
                case when l_collect_fb = 'Y'
                  then 'wc.collectFeedback = true;'
                  else cast(null as varchar2)
                end ||
                'document.getElementById(' || apex_escape.js_literal(l_wc_id) || ').appendChild(wc);})();'
    );
  end render_region;

  -- ============================================================================
  -- Helper: insert user message + submit scheduler job (autonomous transaction
  -- so the row is visible to the background job immediately)
  -- ============================================================================
  procedure submit_agent_job(
    p_session_id        in  varchar2,
    p_message_text      in  clob,
    p_agent_code        in  varchar2,
    p_agent_version     in number,
    p_input_params      in  clob,
    p_session_init_code in  clob,
    p_run_context       in  clob,
    p_widgets           in  varchar2,
    p_created_by        in  varchar2,
    po_user_msg_id      out number
  )
  is
    -- @dblinter ignore(G-3330) Autonomous transaction required: APEX commits after
    -- the AJAX response, but the scheduler job must see the row immediately
    pragma autonomous_transaction;
    l_job_name varchar2(128 char);
  begin
    insert into uc_ai_chat_messages (
      session_id, role, content,
      agent_code, agent_version, agent_request_params,
      session_init_code,
      run_context,
      widgets,
      turn_status,
      created_by
    ) values (
      p_session_id, 'user', p_message_text,
      p_agent_code, p_agent_version, p_input_params,
      p_session_init_code,
      p_run_context,
      p_widgets,
      'pending',
      p_created_by
    ) returning id into po_user_msg_id;

    l_job_name := 'UC_AI_EXEC_' || po_user_msg_id;

    sys.dbms_scheduler.create_job(
      job_name   => l_job_name,
      job_type   => 'PLSQL_BLOCK',
      job_action => 'begin uc_ai_chat.execute_agent_job(p_user_msg_id => ' || po_user_msg_id || '); end;',
      start_date => systimestamp,
      enabled    => true,
      auto_drop  => true
    );

    commit;
  exception
    when others then
      -- Roll back the pending row so a failed job launch (e.g. exhausted job
      -- slots) never leaves a phantom turn that pollers wait on forever, and
      -- surface the failure to the browser instead of silently swallowing it.
      rollback;
      apex_debug.error(
        '%s | submit_agent_job failed for session %s: %s - %s',
        c_scope, p_session_id, sqlerrm, sys.dbms_utility.format_error_backtrace
      );
      raise;
  end submit_agent_job;

  -- ============================================================================
  -- Background job: execute AI agent and store response messages
  -- ============================================================================
  procedure execute_agent_job(
    p_user_msg_id in number
  )
  is
    l_session_id       varchar2(255 char);
    l_agent_code       varchar2(255 char);
    l_agent_version    number;
    l_input_params_str clob;
    l_message_text     clob;
    l_session_init_code clob;
    l_run_context_str  clob;
    l_widgets          varchar2(200 char);
    l_parts            clob;
    l_created_by       varchar2(255 char);
    l_is_follow_up     boolean := false;

    l_input_params     json_object_t;
    l_run_context      json_object_t;
    l_ai_response      json_object_t;
    l_usage            json_object_t;

    l_exec_id          number;
    l_input_tokens     number;
    l_output_tokens    number;
    l_reasoning        clob;
    l_final_message    clob;

    l_claimed          boolean;
    l_updated          boolean;
    l_err              varchar2(4000 char);
    l_gr_kind          varchar2(20 char);
    l_hook_ctx_stmt    varchar2(200 char) := 'begin uc_ai_chat_hook.set_chat_context(:1, :2, :3); end;';
  begin
    -- Read request data from the user message row
    select session_id, agent_code, agent_version, agent_request_params, content, session_init_code, run_context, widgets, created_by
      into l_session_id, l_agent_code, l_agent_version, l_input_params_str, l_message_text, l_session_init_code, l_run_context_str, l_widgets, l_created_by
      from uc_ai_chat_messages
     where id = p_user_msg_id;

    -- Normalise again on read: the column is only ever written by AI_SEND_MESSAGE,
    -- but whatever it holds must not enable more than the supported types.
    l_widgets := uc_ai_chat_widgets.normalize_types(l_widgets);

    -- Claim the turn: flip 'pending' -> 'processing'. If the row is no longer
    -- pending, the user cancelled before the job started: exit without spending
    -- any tokens.
    set_turn_status(
      p_user_msg_id => p_user_msg_id,
      p_status      => 'processing',
      p_expected    => apex_t_varchar2('pending'),
      po_updated    => l_claimed
    );

    if not l_claimed then
      apex_debug.info(
        '%s | Turn %s was not pending (cancelled before start); skipping execution',
        c_scope, p_user_msg_id
      );
      return;
    end if;

    -- Enable progressive "tool running" placeholder rows if the optional hook
    -- package is installed, valid, and callable by the core framework (see
    -- progress_hook_ready). Gated so the core never dispatches to a missing,
    -- broken, or un-granted package (before_execution errors would veto the run).
    -- The hook delegates to a customer's UC_AI_HOOK if present.
    if progress_hook_ready then
      begin
        -- Invoked dynamically so uc_ai_chat compiles even when the optional
        -- UC_AI_CHAT_HOOK package is not installed (progress_hook_ready has
        -- already confirmed it exists and is valid here).
        execute immediate l_hook_ctx_stmt
          using in p_user_msg_id, in l_session_id, in l_created_by;
        uc_ai_agents_api.set_execution_hook(
          sys_context('userenv', 'current_schema') || '.UC_AI_CHAT_HOOK'
        );
      exception
        when others then -- @dblinter ignore(G-5040)
          apex_debug.warn('%s | Could not enable progress hook: %s', c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      end;
    end if;

    -- Run session init code (if configured on the plug-in) so the agent's
    -- scheduler session has any required context set before execution.
    if l_session_init_code is not null then
      declare
        l_init_block clob := 'begin ' || l_session_init_code || ' end;';
      begin
        execute immediate l_init_block;
      end;
    end if;

    -- Check if this is a follow-up message (session already has a prior assistant response)
    declare
      l_prior_count pls_integer;
    begin
      select count(*)
        into l_prior_count
        from uc_ai_chat_messages
       where session_id = l_session_id
         and role = 'assistant'
         and id < p_user_msg_id
         and rownum = 1;

      l_is_follow_up := l_prior_count > 0;
    end;

    -- Run context bound to this turn, resolved from page items back when the
    -- APEX session was still live (see AI_SEND_MESSAGE). Null when the region
    -- configures none, which is what execute_agent expects for "no context".
    if l_run_context_str is not null then
      l_run_context := json_object_t.parse(l_run_context_str);
    end if;

    -- Call UC AI agent
    if l_is_follow_up then
      -- Follow-up: conversation history is loaded automatically by the agent
      -- framework. The context is passed again anyway: re-passing the same
      -- values is idempotent, it is what lets a later turn ADD a key, and it
      -- keeps the engine's own -20507 check as a backstop behind the pre-flight
      -- one in AI_SEND_MESSAGE.
      l_ai_response := uc_ai_agents_api.execute_agent(
        p_agent_code        => l_agent_code,
        p_agent_version     => l_agent_version,
        p_follow_up_message => l_message_text,
        p_session_id        => l_session_id,
        p_run_context       => l_run_context
      );
    else
      -- Initial call: pass input parameters. The WIDGET PROTOCOL goes on the first
      -- turn only: it is appended to the system prompt, which later turns reuse
      -- from the stored conversation (get_protocol is null when widgets are off).
      l_input_params := json_object_t.parse(l_input_params_str);

      l_ai_response := uc_ai_agents_api.execute_agent(
        p_agent_code       => l_agent_code,
        p_agent_version    => l_agent_version,
        p_input_parameters => l_input_params,
        p_session_id       => l_session_id,
        p_run_context      => l_run_context,
        p_prompt_addendum  => uc_ai_chat_widgets.get_protocol(l_widgets)
      );
    end if;

    -- Get execution ID from response
    if l_ai_response.has('execution_id') then
      l_exec_id := l_ai_response.get_number('execution_id');
    end if;

    -- Get token usage from response
    if l_ai_response.has('usage') then
      l_usage := l_ai_response.get_object('usage');
      l_input_tokens  := l_usage.get_number('prompt_tokens');
      l_output_tokens := l_usage.get_number('completion_tokens');
    end if;

    -- The agent framework now persists a normalized, per-turn message log in
    -- uc_ai_agent_messages (keyed by execution_id), so we no longer walk the
    -- output_result JSON here. Read this turn's reasoning and tool rows from it.

    -- Reasoning for this turn: the last reasoning entry (matches the previous
    -- behaviour of keeping the final reasoning block of the turn).
    begin
      select content
        into l_reasoning
        from (
          select content
            from uc_ai_agent_messages
           where execution_id = l_exec_id
             and role = 'reasoning'
           order by seq desc
        )
       where rownum = 1;
    exception
      when no_data_found then
        l_reasoning := null;
    end;

    -- Discard any provisional "tool running" placeholder rows written by the
    -- progress hook during this turn; the authoritative rows below replace them.
    delete from uc_ai_chat_messages
     where session_id = l_session_id
       and role = 'tool_call'
       and tool_status = 'running'
       and id > p_user_msg_id;

    -- Persist tool rows FIRST so they get lower ids than the assistant row that
    -- produced them. This keeps the final answer as the highest-id row of the
    -- turn: pollers that stop on the assistant row won't truncate a tool-heavy
    -- turn, and the UI renders the tools before the answer.
    -- Copy straight from the core message log (scoped to this execution and in
    -- conversation order).
    insert into uc_ai_chat_messages (
      execution_id, session_id, role,
      tool_call_id, tool_name, tool_input, tool_output, tool_status,
      created_by
    )
    select m.execution_id,
           l_session_id,
           m.role,
           m.tool_call_id,
           m.tool_name,
           m.tool_input,
           m.tool_output,
           case when m.role = 'tool_result' then coalesce(m.tool_status, 'success') end,
           l_created_by
      from uc_ai_agent_messages m
     where m.execution_id = l_exec_id
       and m.role in ('tool_call', 'tool_result')
     order by m.seq;

    -- Handle main assistant response (final_message) LAST so it is the highest
    -- id of the turn.
    if l_ai_response.has('final_message') then
      l_final_message := l_ai_response.get_clob('final_message');

      -- Widget snapshot, rendered once here against THIS turn's tool calls. Null
      -- (stored as nothing) unless the answer holds a widget or a rejected one;
      -- never raises, so widgets code cannot fail the turn.
      l_parts := render_parts_snapshot(l_final_message, l_widgets, l_exec_id);

      insert into uc_ai_chat_messages (
        execution_id, session_id, role, content,
        reasoning_content, parts,
        input_tokens, output_tokens,
        created_by
      ) values (
        l_exec_id,
        l_session_id,
        'assistant',
        l_final_message,
        l_reasoning,
        l_parts,
        l_input_tokens,
        l_output_tokens,
        l_created_by
      );
    end if;

    commit;

    -- Finish the turn. If it was cancelled mid-run the claim guard fails; keep
    -- the 'cancelled' status but still record the execution id. Results stay
    -- persisted (the core conversation history contains them regardless, so
    -- discarding them would desync the model context from the UI transcript).
    set_turn_status(
      p_user_msg_id => p_user_msg_id,
      p_status      => 'done',
      p_expected    => apex_t_varchar2('processing'),
      p_execution_id => l_exec_id,
      po_updated    => l_updated
    );

    if not l_updated then
      set_turn_status(
        p_user_msg_id => p_user_msg_id,
        p_status      => 'cancelled',
        p_expected    => apex_t_varchar2('cancelled'),
        p_execution_id => l_exec_id,
        po_updated    => l_updated
      );
      apex_debug.info(
        '%s | Turn %s finished after a cancel request; results kept, status left cancelled',
        c_scope, p_user_msg_id
      );
    end if;
  exception
    when others then -- @dblinter ignore(G-5040)
      -- Capture the message before any further statement can overwrite sqlerrm.
      l_err := substr(sqlerrm, 1, 4000);
      -- Log the full detail (with backtrace) server-side only.
      apex_debug.error(
        '%s | execute_agent_job failed for msg %s: %s - %s',
        c_scope, p_user_msg_id, sqlerrm, sys.dbms_utility.format_error_backtrace
      );

      -- Discard any partial assistant/tool rows from this turn FIRST so the
      -- error handler can never persist a half-written answer alongside the
      -- generic error message.
      rollback;

      -- Clear provisional progress rows (committed by the hook) in their own
      -- transaction.
      begin
        delete from uc_ai_chat_messages
         where session_id = l_session_id
           and role = 'tool_call'
           and tool_status = 'running'
           and id > p_user_msg_id;
        commit;
      exception
        when others then -- @dblinter ignore(G-5040)
          rollback;
      end;

      -- Mark the turn errored and store the real message in error_detail
      -- (exposed to the client only when the show_errors debug flag is on).
      -- Skips a turn the user cancelled ('cancelled' is not in the expected set).
      set_turn_status(
        p_user_msg_id  => p_user_msg_id,
        p_status       => 'error',
        p_expected     => apex_t_varchar2('processing', 'pending'),
        p_error_detail => l_err,
        po_updated     => l_updated
      );

      -- Keep a generic assistant row for backward compatibility (old frontends
      -- stop polling on it); the real message lives in error_detail. A guardrail
      -- denial gets its own fallback wording so the persisted row still says
      -- something true when show_errors is off - the copy the user actually sees
      -- is chosen client-side from turn.guardrail.
      if l_session_id is not null then
        -- Classify in PL/SQL, not in the INSERT: guardrail_kind is private to this
        -- body, and a package-private function cannot be called from a SQL
        -- statement (PLS-00231) -- doing so stops the whole body from compiling.
        l_gr_kind := guardrail_kind(l_err);

        begin
          insert into uc_ai_chat_messages (
            session_id, role, content, created_by
          ) values (
            l_session_id,
            'assistant',
            case
              when l_gr_kind is not null
                then 'This request could not be completed because an AI usage limit was reached.'
              else 'An error occurred while processing your request. Please try again.'
            end,
            nvl(l_created_by, 'SYSTEM')
          );
          commit;
        exception
          when others then -- @dblinter ignore(G-5040)
            rollback;
        end;
      end if;
  end execute_agent_job;

  -- ============================================================================
  -- AJAX_REGION
  -- ============================================================================
  procedure ajax_region(
    -- @dblinter ignore(G-7150)
    p_plugin in            apex_plugin.t_plugin,
    p_region in            apex_plugin.t_region,
    p_param  in            apex_plugin.t_region_ajax_param,
    p_result in out nocopy apex_plugin.t_region_ajax_result -- @dbLinter ignore(G-9110,G-7150,G-7330) For API compatibility
  )
  is
    l_method        varchar2(100 char);
    l_session_id    varchar2(255 char);
    l_message_text  clob;
    l_agent_code    varchar2(255 char);
    l_agent_version number;
    l_last_msg_id   number;
    l_direction     varchar2(20 char);
    l_session_item  varchar2(255 char);
    l_param_template varchar2(32676 char);
    l_session_init_code clob;

    -- Run context (AI_SEND_MESSAGE): the template, the resolved bag, the drift
    -- policy, the key that drifted, and whether we re-bound the conversation.
    l_ctx_template   varchar2(32676 char);
    l_run_context    json_object_t;
    l_ctx_drift      varchar2(20 char);
    l_ctx_conflict   varchar2(4000 char);
    l_ctx_reset      boolean := false;

    -- Widget types enabled for this turn (AI_SEND_MESSAGE), from the region only
    l_widgets        varchar2(200 char);
    -- @dbLinter ignore(G-2410) Y/N flags (not boolean) so they can be used in SQL on pre-23ai databases
    l_show_reasoning varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_tools     varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_metadata  varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_errors    varchar2(1 char);
    -- @dbLinter ignore(G-2410)
    l_show_debug     varchar2(1 char);

    l_input_params  json_object_t;

    -- AI_EXEC_DETAILS: latest execution + session aggregates for the debug panel
    l_exec_id       number;
    l_exec_details  json_object_t;
    l_sess          uc_ai_agent_sessions%rowtype;

    l_new_msg_id    number;
    l_updated       boolean;

    -- Latest user row of a session, used for the turn status / orphan sweep
    l_turn_msg_id   number;
    l_turn_status   uc_ai_chat_messages.turn_status%type;
    l_turn_error    uc_ai_chat_messages.error_detail%type;
    l_turn_created  uc_ai_chat_messages.created_at%type;

    -- Guardrail kind of a failed turn, when a UC AI Pro limit refused it
    l_gr_turn_kind  varchar2(20 char);

    -- Conversation title (AI_SET_TITLE / AI_FETCH_MESSAGES), owned by the core
    -- session header rather than this plug-in's tables
    l_session_title uc_ai_agent_sessions.title%type;
    l_new_title     uc_ai_agent_sessions.title%type;

    -- End-user verdict on the conversation (AI_SET_FEEDBACK / AI_FETCH_MESSAGES),
    -- stored on the same core session header
    l_fb_rating     uc_ai_agent_sessions.feedback_rating%type;
    l_fb_comment    uc_ai_agent_sessions.feedback_comment%type;

    -- @dblinter ignore(G-2160): reading standard APEX session state (v) does not raise in practice
    l_curr_user     varchar2(255 char) := v('APP_USER');

    -- Offset of the DB host clock. Timestamps are plain TIMESTAMPs written from
    -- systimestamp, so they carry no zone; sending them naked made the browser
    -- read them as browser-local time (a DB in UTC then renders every message
    -- hours off). Appending the offset makes the value an unambiguous instant.
    l_tz_offset     varchar2(10 char) := to_char(systimestamp, 'TZH:TZM');

    c_page_size     constant pls_integer := 50;
  begin
    l_method := apex_application.g_x01;

    get_debug_flags(
      p_region          => p_region,
      po_show_reasoning => l_show_reasoning,
      po_show_tools     => l_show_tools,
      po_show_metadata  => l_show_metadata,
      po_show_errors    => l_show_errors,
      po_show_debug     => l_show_debug
    );

    apex_debug.info('%s | ajax_region method=%s', c_scope, l_method);

    case l_method
    -- ========================================================================
    -- AI_NEW_SESSION
    -- ========================================================================
    when 'AI_NEW_SESSION' then
      l_agent_code    := apex_application.g_x02;
      l_agent_version := to_number(apex_application.g_x03);

      l_session_id := rawtohex(sys_guid());

      -- Store session ID in page item if configured
      l_session_item := p_region.attributes.get_varchar2('session_item');
      if l_session_item is not null then
        apex_util.set_session_state(l_session_item, l_session_id);
      end if;

      apex_json.open_object;
      apex_json.write('sessionId', l_session_id);
      apex_json.close_object;

    -- ========================================================================
    -- AI_SET_TITLE (name a conversation; the title is generated in the browser
    -- by the on-device model, so the server only validates and stores it. The
    -- store is the core session header, via uc_ai_agents_api.)
    -- ========================================================================
    when 'AI_SET_TITLE' then
      l_session_id  := apex_application.g_x02;
      l_new_title   := trim(substr(apex_application.g_x03, 1, 200));

      -- Authorization: only the session owner may name the conversation
      assert_session_owner(p_session_id => l_session_id, p_user => l_curr_user);

      -- Write-once is this plug-in's policy, not the core's: the title is
      -- generated from the first exchange, so a later turn (or a second tab)
      -- must not silently rename a conversation. The core setter itself
      -- overwrites, leaving room for a deliberate rename feature later.
      l_session_title := get_session_title(p_session_id => l_session_id);

      if l_session_title is null and l_new_title is not null then
        -- p_created_by is deliberately null. The core header's created_by is
        -- snapshotted from whoever opened the session, and that is execute_agent_job
        -- running under dbms_scheduler with no APEX session -- so it holds the DB
        -- user, not APP_USER. Passing APP_USER here would match zero rows and the
        -- write would be silently lost. Authorization is assert_session_owner
        -- above, which checks uc_ai_chat_messages.created_by (written from this
        -- request, where APP_USER is real).
        uc_ai_agents_api.set_session_title(
          p_session_id => l_session_id,
          p_title      => l_new_title,
          p_created_by => null
        );
        l_session_title := get_session_title(p_session_id => l_session_id);
      end if;

      apex_json.open_object;
      if l_session_title is not null then
        apex_json.write('sessionTitle', l_session_title);
      end if;
      apex_json.close_object;

    -- ========================================================================
    -- AI_SET_FEEDBACK (record the end user's verdict on the conversation. Stored
    -- on the core session header, like the title: one verdict per conversation,
    -- deliberately changeable, and readable by any uc-ai front end or report.)
    -- ========================================================================
    when 'AI_SET_FEEDBACK' then
      l_session_id := apex_application.g_x02;
      -- substr before the assignment: l_fb_rating is only as wide as the column,
      -- so an over-long value would raise ORA-06502 here instead of reaching the
      -- clean "Invalid feedback rating" below. Truncating cannot create a false
      -- match -- only an exact 'up'/'down' survives.
      l_fb_rating  := lower(trim(substr(apex_application.g_x03, 1, 10)));
      l_fb_comment := trim(substr(apex_application.g_x04, 1, 2000));

      -- Authorization: only the session owner may rate the conversation
      assert_session_owner(p_session_id => l_session_id, p_user => l_curr_user);

      -- An empty rating is a deliberate withdrawal (the user un-voted); anything
      -- else unrecognized is a bug in the caller, so say so rather than quietly
      -- turning a mistyped rating into a withdrawal.
      if l_fb_rating is not null and l_fb_rating not in ('up', 'down') then
        apex_debug.error('%s | Invalid feedback rating: %s', c_scope, l_fb_rating);
        raise_application_error(-20004, 'Invalid feedback rating.');
      end if;

      -- No write-once read-first here, unlike the title: changing your mind about
      -- a conversation is the point, so the core setter's overwrite is what we want.
      -- p_created_by is null for the same reason as in AI_SET_TITLE above.
      uc_ai_agents_api.set_session_feedback(
        p_session_id => l_session_id,
        p_rating     => l_fb_rating,
        p_comment    => l_fb_comment,
        p_created_by => null
      );

      -- Re-read so the client learns the effective value: the write is a no-op
      -- when the core header does not exist yet, and the UI must not keep showing
      -- a vote that was never stored.
      get_session_feedback(
        p_session_id => l_session_id,
        po_rating    => l_fb_rating,
        po_comment   => l_fb_comment
      );

      apex_json.open_object;
      if l_fb_rating is not null then
        apex_json.write('feedbackRating', l_fb_rating);
        if l_fb_comment is not null then
          apex_json.write('feedbackComment', l_fb_comment);
        end if;
      end if;
      apex_json.close_object;

    -- ========================================================================
    -- AI_SEND_MESSAGE (async: insert user message, submit background job)
    -- ========================================================================
    when 'AI_SEND_MESSAGE' then
      l_session_id    := apex_application.g_x02;
      l_message_text  := apex_application.g_x03;
      l_agent_code    := apex_application.g_x04;
      l_agent_version := to_number(apex_application.g_x05);

      -- Authorization: only the session owner may append to the conversation
      assert_session_owner(p_session_id => l_session_id, p_user => l_curr_user);

      -- Authorization: the REGION decides which agent runs, never the caller.
      --
      -- The code and the version travel in the request because the client keeps
      -- them beside the session id, but they are not trusted. Without this
      -- check any authenticated user of the application could post this
      -- plug-in's ajax identifier with a different agent code and run ANY agent
      -- registered in the schema -- including one holding privileged write
      -- tools -- under their own APEX session and carrying this region's
      -- resolved run context.
      --
      -- assert_session_owner above does not cover this: it guards who may
      -- append to a conversation, not which agent answers.
      --
      -- Compared exactly, not case-folded: render_region emits the attribute
      -- verbatim and the client echoes it back, so anything else is a forged
      -- or stale payload. A pinned version is checked too, otherwise a caller
      -- could name a draft or archived version the region never offered.
      declare
        l_cfg_code    varchar2(255 char) := p_region.attributes.get_varchar2('agent_code');
        l_cfg_version number :=
          to_number(
            p_region.attributes.get_varchar2('agent_version') default null on conversion error
          , '9999999999999999999999999999D9999999999'
          , q'[nls_numeric_characters='.,']'
          );
      begin
        if l_cfg_code is null
           or l_agent_code is null
           or l_agent_code != l_cfg_code
           or nvl(l_agent_version, -1) != nvl(l_cfg_version, -1)
        then
          apex_debug.error(
            '%s | Agent mismatch on AI_SEND_MESSAGE: request named %s (version %s), region is configured for %s (version %s)',
            c_scope, l_agent_code, l_agent_version, l_cfg_code, l_cfg_version
          );
          raise_application_error(-20005, 'Unknown or unauthorized agent.');
        end if;
      end;

      -- Build input parameters from template or default (needs APEX session context)
      l_param_template := p_region.attributes.get_varchar2('agent_input_mapping');

      if l_param_template is not null then
        apex_debug.info('%s | Using input mapping template: %s', c_scope, l_param_template);

        -- Parse the RAW template first, then substitute inside each string value.
        -- Substituting after parsing means an item value (or the user message)
        -- containing a double quote can no longer break JSON parsing or inject
        -- structure. Falls back to the legacy substitute-then-parse path for
        -- templates that are only valid JSON after substitution (e.g. a numeric
        -- placeholder like {"n": &P1_NUM.}).
        begin
          l_input_params := json_object_t.parse(l_param_template);
          substitute_json_strings(l_input_params, l_message_text);
        exception
          when others then -- @dblinter ignore(G-5040)
            apex_debug.warn(
              '%s | Raw template is not valid JSON, using legacy substitute-then-parse: %s',
              c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
            );
            l_param_template := apex_plugin_util.replace_substitutions(l_param_template);
            l_param_template := replace(l_param_template, '#USER_MESSAGE#', '__UC_MSG_PLACEHOLDER__');
            l_input_params := json_object_t.parse(l_param_template);
            declare
              l_keys json_key_list := l_input_params.get_keys;
              l_el   json_element_t;
            begin
              <<template_keys_loop>>
              for i in 1 .. l_keys.count loop
                l_el := l_input_params.get(l_keys(i));
                if l_el.is_string
                   and l_input_params.get_string(l_keys(i)) = '__UC_MSG_PLACEHOLDER__' then
                  l_input_params.put(l_keys(i), l_message_text);
                end if;
              end loop template_keys_loop;
            end;
        end;

        apex_debug.info('%s | Final input parameters: %s', c_scope, l_input_params.to_string);
      else
        apex_debug.info('%s | No input mapping template found, using default', c_scope);
        l_input_params := json_object_t();
        l_input_params.put('message', l_message_text);
      end if;


      l_session_init_code := p_region.attributes.get_varchar2('session_init_code');

      -- Resolve APEX item references here, while the APEX session is live.
      -- The scheduler job runs without an APEX session, so &ITEM. / :ITEM
      -- references would be unresolved at execute_immediate time.
      if l_session_init_code is not null then
        -- 1) &ITEM. substitution syntax (handled natively by APEX)
        l_session_init_code := apex_plugin_util.replace_substitutions(l_session_init_code);

        -- 2) :ITEM bind-style references — inline as quoted SQL literals.
        -- apex_plugin_util.replace_substitutions does not handle this syntax.
        -- Limitation: matches :IDENT anywhere, including inside string literals;
        -- prefer &ITEM. syntax if your code embeds ":" inside strings.
        declare
          c_bind_pattern constant varchar2(60 char) := ':([A-Z][A-Z0-9_]{0,254})';
          l_pos          pls_integer := 1;
          l_match_pos    pls_integer;
          l_match_end    pls_integer;
          l_match_name   varchar2(255 char);
          l_value        varchar2(4000 char);
          l_literal      varchar2(8000 char);
        begin
          <<bind_subst_loop>>
          loop
            l_match_pos := regexp_instr(l_session_init_code, c_bind_pattern, l_pos, 1, 0, 'i');
            exit bind_subst_loop when l_match_pos = 0;
            l_match_end  := regexp_instr(l_session_init_code, c_bind_pattern, l_pos, 1, 1, 'i');
            l_match_name := upper(substr(l_session_init_code, l_match_pos + 1, l_match_end - l_match_pos - 1));
            l_value      := v(l_match_name);
            l_literal    := '''' || replace(l_value, '''', '''''') || '''';
            l_session_init_code :=
                 substr(l_session_init_code, 1, l_match_pos - 1)
              || l_literal
              || substr(l_session_init_code, l_match_end);
            l_pos := l_match_pos + length(l_literal);
          end loop bind_subst_loop;
        end;

        apex_debug.info('%s | Resolved session_init_code: %s', c_scope, l_session_init_code);
      end if;

      -- Run context: name/value pairs bound to the run, which every tool of the
      -- turn receives and no model can see or choose. Resolved here, while the
      -- APEX session is still live, using the same parse-then-substitute
      -- mechanic as the input mapping above -- so an item value containing a
      -- double quote cannot break the JSON or inject structure.
      --
      -- #USER_MESSAGE# is deliberately NOT supported here: a run context scopes
      -- the run, it does not carry the prompt. Passing null below strips the
      -- token rather than leaving it to reach a tool as literal text.
      l_ctx_template := p_region.attributes.get_varchar2('agent_run_context');

      if l_ctx_template is not null then
        begin
          l_run_context := json_object_t.parse(l_ctx_template);
          substitute_json_strings(l_run_context, null);
          apex_debug.info('%s | Resolved run context: %s', c_scope, l_run_context.to_string);
        exception
          when others then -- @dblinter ignore(G-5040)
            -- A template we cannot read must not kill the send: the turn runs
            -- unbound, which is exactly the behaviour before this attribute.
            l_run_context := null;
            apex_debug.warn(
              '%s | agent_run_context is not valid JSON, running without a run context: %s',
              c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
            );
        end;
      end if;

      -- Has a page item moved under an open conversation? UC AI binds the
      -- context on a session's first turn and refuses a changed key, so decide
      -- here -- before a row is written or a token is spent -- rather than
      -- letting the background job fail.
      if l_run_context is not null then
        l_ctx_drift := lower(p_region.attributes.get_varchar2('run_context_drift'));

        if l_ctx_drift is null
           or l_ctx_drift not in (c_ctx_drift_error, c_ctx_drift_new, c_ctx_drift_ignore)
        then
          l_ctx_drift := c_ctx_drift_error;
        end if;

        l_ctx_conflict := run_context_conflict(
                            p_session_id => l_session_id,
                            p_new_ctx    => l_run_context
                          );

        if l_ctx_conflict is not null then
          apex_debug.info(
            '%s | Run context key "%s" is already bound on session %s, drift policy is %s',
            c_scope, l_ctx_conflict, l_session_id, l_ctx_drift
          );

          case l_ctx_drift
            when c_ctx_drift_ignore then
              -- Freeze the binding: keep answering under what the first turn
              -- bound, the same way agent_input_mapping stops applying after
              -- the first message of a session.
              l_run_context := null;

            when c_ctx_drift_new then
              -- The page moved to other data, so the conversation moves with
              -- it. A fresh session id is an unbound session, which this turn
              -- then binds to the new values.
              l_session_id   := rawtohex(sys_guid());
              l_session_item := p_region.attributes.get_varchar2('session_item');

              if l_session_item is not null then
                apex_util.set_session_state(l_session_item, l_session_id);
              end if;

              l_ctx_reset := true;

            else
              -- c_ctx_drift_error: refuse the turn and say so. The key name
              -- stays server-side, the same reticence the guardrail notices
              -- keep: the client turns a bare flag into plain-language copy.
              apex_json.open_object;
              apex_json.write('contextConflict', true);
              apex_json.close_object;
              return;
          end case;
        end if;
      end if;

      -- Widgets: which types the model may use is the REGION's decision, resolved
      -- here and stored on the user row. Nothing the client sends is read, so a
      -- crafted request cannot enable a type the developer left off.
      l_widgets := region_widget_types(p_region);

      -- Insert user message and submit background job (autonomous transaction
      -- so the scheduler job can see the row immediately)
      submit_agent_job(
        p_session_id        => l_session_id,
        p_message_text      => l_message_text,
        p_agent_code        => l_agent_code,
        p_agent_version     => l_agent_version,
        p_input_params      => l_input_params.to_clob,
        p_session_init_code => l_session_init_code,
        p_run_context       => case
                                 when l_run_context is null then null
                                 else l_run_context.to_clob
                               end,
        p_widgets           => l_widgets,
        p_created_by        => l_curr_user,
        po_user_msg_id      => l_new_msg_id
      );

      -- Return immediately so the frontend can start polling
      apex_json.open_object;
      apex_json.write('userMessageId', l_new_msg_id);
      apex_json.write('turnStatus', 'pending');
      -- The conversation was re-bound: the client drops the transcript it has
      -- and follows this session id, which is where the turn was queued.
      if l_ctx_reset then
        apex_json.write('sessionReset', true);
        apex_json.write('sessionId', l_session_id);
      end if;
      -- Where this caller stands against the optional guardrails. Probed here
      -- rather than on every poll cycle: each check aggregates over
      -- uc_ai_agent_executions, and the numbers only move per completed run.
      write_guardrail(p_agent_code => l_agent_code, p_user => l_curr_user);
      apex_json.close_object;

    -- ========================================================================
    -- AI_FETCH_MESSAGES
    -- ========================================================================
    when 'AI_FETCH_MESSAGES' then
      l_session_id  := apex_application.g_x02;
      l_last_msg_id := to_number(apex_application.g_x03);
      l_direction   := nvl(apex_application.g_x04, 'older');

      -- Authorization: only the session owner may read the conversation
      assert_session_owner(p_session_id => l_session_id, p_user => l_curr_user);

      -- Stored conversation title, so a reloaded page gets its header back.
      -- Ownership was just asserted above, so reading the core header directly
      -- adds no exposure.
      l_session_title := get_session_title(p_session_id => l_session_id);

      -- Stored feedback, so a reloaded page shows the vote already given instead
      -- of asking for it again.
      get_session_feedback(
        p_session_id => l_session_id,
        po_rating    => l_fb_rating,
        po_comment   => l_fb_comment
      );

      -- Locate the latest user row of this session (one turn = one user row) so
      -- we can report its lifecycle status and detect an orphaned background job.
      begin
        select id, turn_status, error_detail, created_at, agent_code
          into l_turn_msg_id, l_turn_status, l_turn_error, l_turn_created, l_agent_code
          from (
            select id, turn_status, error_detail, created_at, agent_code
              from uc_ai_chat_messages
             where session_id = l_session_id
               and created_by = l_curr_user
               and role = 'user'
             order by id desc
          )
         where rownum = 1;
      exception
        when no_data_found then
          l_turn_msg_id := null;
          -- SELECT INTO leaves its targets indeterminate on no_data_found
          l_agent_code  := null;
      end;

      -- The client does not send the agent code on a fetch, so an empty session
      -- (or one whose rows predate the column) would probe with none and silently
      -- skip every agent-scoped limit. Fall back to the region's own attribute.
      if l_agent_code is null then
        l_agent_code := p_region.attributes.get_varchar2('agent_code');
      end if;

      if l_turn_msg_id is not null then
        check_orphaned_turn(
          p_user_msg_id => l_turn_msg_id,
          p_session_id  => l_session_id,
          p_status      => l_turn_status,
          p_created_at  => l_turn_created
        );
        -- Re-read after a possible orphan flip so the turn object is current.
        select turn_status, error_detail
          into l_turn_status, l_turn_error
          from uc_ai_chat_messages
         where id = l_turn_msg_id;
      end if;

      apex_json.open_object;
      apex_json.open_array('messages');

      <<fetch_messages_loop>>
      for rec in (
        select id as message_id,
               role,
               content,
               reasoning_content,
               tool_name,
               tool_input,
               tool_output,
               tool_status,
               turn_status,
               parts,
               input_tokens,
               output_tokens,
               to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS') || l_tz_offset as message_date
          from uc_ai_chat_messages
         where session_id = l_session_id
           and created_by = l_curr_user
           and (
             l_last_msg_id is null
             or (l_direction = 'older' and id < l_last_msg_id)
             or (l_direction = 'newer' and id > l_last_msg_id)
           )
           -- Filter out tool rows (tool_call, tool_result) when show_tools is off
           and (l_show_tools = 'Y' or role not in ('tool_call', 'tool_result'))
         order by case when l_direction = 'older' then id end desc,
                  case when l_direction = 'newer' then id end asc
         fetch first c_page_size rows only
      ) loop
        apex_json.open_object;
        apex_json.write('messageId', rec.message_id);
        apex_json.write('role', rec.role);
        apex_json.write('content', rec.content);
        -- Widget snapshot: server-resolved at the end of the turn, so it needs no
        -- tool rows and renders with show_tools off. The reason a widget was
        -- rejected is a debug detail and follows show_errors.
        if rec.role = 'assistant' and rec.parts is not null then
          uc_ai_chat_widgets.write_parts(rec.parts, l_show_errors = 'Y');
        end if;
        -- Lets a reloaded page mark the right turn as in-flight / errored.
        if rec.role = 'user' and rec.turn_status is not null then
          apex_json.write('turnStatus', rec.turn_status);
        end if;
        -- Per-flag server-side field gating: omitted keys never leave the server
        if l_show_reasoning = 'Y' and rec.reasoning_content is not null then
          apex_json.write('reasoningContent', rec.reasoning_content);
        end if;
        if l_show_tools = 'Y' then
          if rec.tool_name is not null then
            apex_json.write('toolName', rec.tool_name);
          end if;
          if rec.tool_input is not null then
            apex_json.write('toolInput', rec.tool_input);
          end if;
          if rec.tool_output is not null then
            apex_json.write('toolOutput', rec.tool_output);
          end if;
          if rec.tool_status is not null then
            apex_json.write('toolStatus', rec.tool_status);
          end if;
        end if;
        if l_show_metadata = 'Y' then
          if rec.input_tokens is not null then
            apex_json.write('inputTokens', rec.input_tokens);
          end if;
          if rec.output_tokens is not null then
            apex_json.write('outputTokens', rec.output_tokens);
          end if;
        end if;
        apex_json.write('messageDate', rec.message_date);
        apex_json.close_object;
      end loop fetch_messages_loop;

      apex_json.close_array;

      -- Turn lifecycle for the latest user row so the frontend can stop polling
      -- on a terminal status instead of guessing from the assistant row.
      if l_turn_msg_id is not null then
        apex_json.open_object('turn');
        apex_json.write('userMessageId', l_turn_msg_id);
        -- A legacy NULL status means a turn that predates lifecycle tracking; it
        -- is by definition already complete.
        apex_json.write('status', nvl(l_turn_status, 'done'));
        -- Real error text is exposed only when the show_errors debug flag is on.
        if l_turn_status = 'error' and l_show_errors = 'Y' and l_turn_error is not null then
          apex_json.write('errorDetail', l_turn_error);
        end if;
        -- Why the turn failed, when a guardrail refused it. Ungated on purpose:
        -- the kind alone carries no limit, figure or percentage, and without it
        -- a quota denial is indistinguishable from a provider outage.
        if l_turn_status = 'error' then
          l_gr_turn_kind := guardrail_kind(l_turn_error);
          if l_gr_turn_kind is not null then
            apex_json.write('guardrail', l_gr_turn_kind);
          end if;
          -- Same reasoning for a run context the engine refused to re-bind:
          -- without this the turn reads as a generic outage. Ungated, and it
          -- names neither the key nor either value.
          if is_context_conflict(l_turn_error) then
            apex_json.write('contextConflict', true);
          end if;
        end if;
        apex_json.close_object;
      end if;

      if l_session_title is not null then
        apex_json.write('sessionTitle', l_session_title);
      end if;

      -- Omitted entirely when nothing was rated, so an absent member means "not
      -- rated" and the client can leave the control in its unvoted state.
      if l_fb_rating is not null then
        apex_json.open_object('feedback');
        apex_json.write('rating', l_fb_rating);
        if l_fb_comment is not null then
          apex_json.write('comment', l_fb_comment);
        end if;
        apex_json.close_object;
      end if;

      -- Where this caller now stands against the optional guardrails. Narrow on
      -- purpose: the initial (cursorless) load, and the one poll cycle that sees a
      -- turn go terminal. Not mid-turn (the poll runs every couple of seconds) and
      -- not while paging older history (that has nothing to do with quota), because
      -- each check aggregates over uc_ai_agent_executions and the figures only move
      -- when a run completes.
      if l_last_msg_id is null
         or (l_direction = 'newer'
             and nvl(l_turn_status, 'done') in ('done', 'error', 'cancelled'))
      then
        write_guardrail(p_agent_code => l_agent_code, p_user => l_curr_user);
      end if;

      apex_json.close_object;

    -- ========================================================================
    -- AI_EXEC_DETAILS (developer debug panel: agent config + session aggregates
    -- + the latest turn's execution internals. Gated behind the show_debug flag.)
    -- ========================================================================
    when 'AI_EXEC_DETAILS' then
      l_session_id := apex_application.g_x02;

      -- Authorization: only the session owner may inspect the conversation
      assert_session_owner(p_session_id => l_session_id, p_user => l_curr_user);

      apex_json.open_object;

      -- Gate: never trust the client. The button is only rendered when the flag
      -- is on, but re-check here so the rich internals cannot be scraped without it.
      if l_show_debug != 'Y' then
        apex_json.write('enabled', false);
        apex_json.close_object;
      else
        apex_json.write('enabled', true);

        -- The chat turn's own captured error (the sqlerrm stored by
        -- execute_agent_job). This is the most reliable error source for a
        -- failed turn and is shown even when the core execution row cannot be
        -- read. show_debug is already asserted above, so no extra gate needed.
        begin
          select turn_status, error_detail
            into l_turn_status, l_turn_error
            from (
              select turn_status, error_detail
                from uc_ai_chat_messages
               where session_id = l_session_id
                 and created_by = l_curr_user
                 and role = 'user'
               order by id desc
            )
           where rownum = 1;

          if l_turn_status = 'error' and l_turn_error is not null then
            apex_json.write('turnError', l_turn_error);
          end if;
        exception
          when no_data_found then
            null; -- no user row yet
        end;

        -- Session aggregates (conversation-wide), maintained by the core API.
        begin
          select *
            into l_sess
            from uc_ai_agent_sessions
           where session_id = l_session_id;

          apex_json.open_object('session');
          apex_json.write('sessionId', l_session_id);
          apex_json.write('status', l_sess.status);
          apex_json.write('turnCount', l_sess.turn_count);
          apex_json.write('messageCount', l_sess.message_count);
          apex_json.write('totalInputTokens', l_sess.total_input_tokens);
          apex_json.write('totalOutputTokens', l_sess.total_output_tokens);
          apex_json.write('startedAt', to_char(l_sess.started_at, 'YYYY-MM-DD"T"HH24:MI:SS') || l_tz_offset);
          apex_json.write('lastActivityAt', to_char(l_sess.last_activity_at, 'YYYY-MM-DD"T"HH24:MI:SS') || l_tz_offset);
          apex_json.close_object;
        exception
          when no_data_found then
            null; -- no core session row yet (e.g. before the first turn finishes)
        end;

        -- Latest execution for this session. Prefer the core executions table
        -- so a FAILED turn -- which never stamps an execution_id back onto the
        -- chat rows -- is still surfaced (with its status + error_message).
        l_exec_id := null;
        begin
          select id
            into l_exec_id
            from (
              select id
                from uc_ai_agent_executions
               where session_id = l_session_id
                 and parent_execution_id is null
               order by id desc
            )
           where rownum = 1;
        exception
          when no_data_found then
            null;
          when others then -- @dblinter ignore(G-5040) degrade if the core table is not readable
            apex_debug.warn(
              '%s | AI_EXEC_DETAILS: executions lookup failed, falling back to chat rows: %s',
              c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
            );
        end;

        -- Fallback: whatever execution id the chat rows recorded.
        if l_exec_id is null then
          begin
            select max(execution_id)
              into l_exec_id
              from uc_ai_chat_messages
             where session_id = l_session_id
               and created_by = l_curr_user
               and execution_id is not null;
          exception
            when no_data_found then
              l_exec_id := null;
          end;
        end if;

        if l_exec_id is null then
          -- No completed turn yet; the panel still shows session/agent context.
          apex_json.write('execution', to_char(null));
        else
          -- Isolated handler so an edge/missing execution degrades gracefully
          -- rather than failing the whole request.
          begin
            l_exec_details := uc_ai_agents_api.get_execution_details(
              p_execution_id => l_exec_id
            );

            apex_json.open_object('agent');
            apex_json.write('code', l_exec_details.get_string('agent_code'));
            apex_json.write('version', l_exec_details.get_number('agent_version'));
            apex_json.write('type', l_exec_details.get_string('agent_type'));
            -- 'status' on the execution object reflects this turn's run status.
            apex_json.close_object;

            apex_json.open_object('execution');
            apex_json.write('executionId', l_exec_details.get_number('execution_id'));
            apex_json.write('status', l_exec_details.get_string('status'));
            apex_json.write('iterationCount', l_exec_details.get_number('iteration_count'));
            apex_json.write('toolCallsCount', l_exec_details.get_number('tool_calls_count'));
            apex_json.write('inputTokens', l_exec_details.get_number('total_input_tokens'));
            apex_json.write('outputTokens', l_exec_details.get_number('total_output_tokens'));
            apex_json.write('startedAt', l_exec_details.get_string('started_at'));
            apex_json.write('completedAt', l_exec_details.get_string('completed_at'));
            apex_json.write('errorMessage', l_exec_details.get_string('error_message'));
            apex_json.close_object;

            -- Raw payloads as strings for collapsible display. Kept out of the
            -- headline view; owner-checked + dev-flag-gated so this is acceptable.
            apex_json.open_object('raw');
            if l_exec_details.has('input_parameters') then
              apex_json.write('inputParameters',
                treat(l_exec_details.get('input_parameters') as json_object_t).to_clob);
            end if;
            if l_exec_details.has('output_result') then
              apex_json.write('outputResult',
                treat(l_exec_details.get('output_result') as json_object_t).to_clob);
            end if;
            if l_exec_details.has('env_context') then
              apex_json.write('envContext',
                treat(l_exec_details.get('env_context') as json_object_t).to_clob);
            end if;
            apex_json.close_object;
          exception
            when others then -- @dblinter ignore(G-5040)
              apex_debug.warn(
                '%s | AI_EXEC_DETAILS: get_execution_details failed for exec %s: %s',
                c_scope, l_exec_id, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
              );
              apex_json.write('execution', to_char(null));
          end;
        end if;

        apex_json.close_object;
      end if;

    -- ========================================================================
    -- AI_CANCEL (cooperative: mark the turn cancelled; the job checks before it
    -- claims/finishes. A pending turn is stopped before any tokens are spent.)
    -- ========================================================================
    when 'AI_CANCEL' then
      l_session_id  := apex_application.g_x02;
      l_last_msg_id := to_number(apex_application.g_x03);

      -- Authorization: only the session owner may cancel
      assert_session_owner(p_session_id => l_session_id, p_user => l_curr_user);

      -- The referenced row must be a user row of this session owned by the caller
      begin
        select turn_status
          into l_turn_status
          from uc_ai_chat_messages
         where id = l_last_msg_id
           and session_id = l_session_id
           and created_by = l_curr_user
           and role = 'user';
      exception
        when no_data_found then
          raise_application_error(-20003, 'Unknown or unauthorized message.');
      end;

      set_turn_status(
        p_user_msg_id => l_last_msg_id,
        p_status      => 'cancelled',
        p_expected    => apex_t_varchar2('pending', 'processing'),
        po_updated    => l_updated
      );

      apex_json.open_object;
      apex_json.write('cancelled', l_updated);
      -- Report the resulting status (unchanged if it was already terminal).
      select turn_status into l_turn_status
        from uc_ai_chat_messages where id = l_last_msg_id;
      apex_json.write('turnStatus', nvl(l_turn_status, 'done'));
      apex_json.close_object;

    -- ========================================================================
    -- Unknown method
    -- ========================================================================
    else
      apex_debug.error('%s | Unknown method: %s', c_scope, l_method);
      raise_application_error(-20001, 'Unknown method: ' || l_method);
    end case;
  exception
    when others then
      apex_debug.error('%s | %s', c_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end ajax_region;

end uc_ai_chat;
/
