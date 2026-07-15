create or replace package body uc_ai_agents_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


  -- ============================================================================
  -- Private Types
  -- ============================================================================

  type t_agent_code_list is table of uc_ai_agents.code%type;

  -- Environment/session context captured once per top-level execution
  type t_exec_env is record (
    created_by        uc_ai_agent_executions.created_by%type,
    db_user           uc_ai_agent_executions.db_user%type,
    apex_user         uc_ai_agent_executions.apex_user%type,
    apex_session_id   uc_ai_agent_executions.apex_session_id%type,
    apex_app_id       uc_ai_agent_executions.apex_app_id%type,
    apex_page_id      uc_ai_agent_executions.apex_page_id%type,
    os_user           uc_ai_agent_executions.os_user%type,
    host              uc_ai_agent_executions.host%type,
    ip_address        uc_ai_agent_executions.ip_address%type,
    module            uc_ai_agent_executions.module%type,
    action            uc_ai_agent_executions.action%type,
    client_identifier uc_ai_agent_executions.client_identifier%type,
    sid               uc_ai_agent_executions.sid%type,
    env_context       clob
  );

  -- @dblinter ignore(g-7230): allow use of global variables
  -- @dblinter ignore(g-9104): package-global record, g_ prefix is intended (not a local var)
  g_exec_env   t_exec_env;
  g_exec_depth pls_integer := 0;

  -- Guards against runaway / circular agent nesting (an agent that ultimately
  -- delegates back to itself). Bounds the recursion of nested execute_agent
  -- calls before the PL/SQL call stack overflows or costs run away.
  c_max_exec_depth constant pls_integer := 25;

  -- Execution hook: a package implementing before_execution/after_execution
  -- (see the spec's "Execution Hooks" section) that execute_agent dispatches to
  -- at the top level. Resolved by convention to a VALID package named UC_AI_HOOK
  -- unless an explicit override is registered via set_execution_hook.
  c_hook_convention constant varchar2(128 char) := 'UC_AI_HOOK';
  -- @dblinter ignore(g-7230): allow use of global variables
  g_hook_override   varchar2(128 char);          -- explicit override (null = use convention)
  g_hook_pkg        varchar2(128 char);           -- resolved package name (null = no hook)
  g_hook_resolved   boolean := false;             -- whether convention resolution has run this session
  -- before_tool_call is optional; cache whether the resolved hook implements it
  -- so we never execute-immediate a missing procedure (which would break every
  -- tool call for a hook that only implements before/after_execution).
  g_hook_tool_cb          pls_integer;            -- 1 = has before_tool_call, 0 = not, null = unknown


  -- ============================================================================
  -- Private Helper Functions
  -- ============================================================================

  /*
   * Resolves the execution hook package name: an explicit override wins;
   * otherwise the convention (a VALID package named UC_AI_HOOK in this schema),
   * resolved once and cached per session. Returns null when no hook exists.
   */
  function resolve_hook_pkg return varchar2
  as
  begin
    if g_hook_override is not null then
      return g_hook_override;
    end if;

    if not g_hook_resolved then
      begin
        select object_name
          into g_hook_pkg
          from user_objects
         where object_type = 'PACKAGE'
           and object_name = c_hook_convention
           and status = 'VALID';
      exception
        when no_data_found then
          g_hook_pkg := null;
      end;
      g_hook_resolved := true;
    end if;

    return g_hook_pkg;
  end resolve_hook_pkg;


  /*
   * Fires the pre-execution hook (top-level only). Exceptions PROPAGATE by
   * design: a hook raising here (e.g. a budget hard-cap) vetoes the execution
   * before any row is created or tokens are spent.
   */
  procedure fire_before_hook(
    p_agent_id    in uc_ai_agent_executions.agent_id%type,
    p_agent_code  in uc_ai_agents.code%type,
    p_created_by  in uc_ai_agent_executions.created_by%type,
    p_apex_app_id in uc_ai_agent_executions.apex_app_id%type,
    p_session_id  in uc_ai_agent_executions.session_id%type
  )
  as
    l_pkg  varchar2(128 char);
    l_stmt varchar2(500 char);
  begin
    l_pkg := resolve_hook_pkg();
    if l_pkg is null then
      return;
    end if;

    l_stmt := 'begin ' || l_pkg || '.before_execution(:1, :2, :3, :4, :5); end;';
    execute immediate l_stmt
      using in p_agent_id, in p_agent_code, in p_created_by, in p_apex_app_id, in p_session_id;
  end fire_before_hook;


  /*
   * Fires the post-execution hook (top-level only). Best-effort: any error is
   * logged and swallowed so cost/audit recording can never fail a finished run.
   */
  procedure fire_after_hook(
    p_exec_id       in uc_ai_agent_executions.id%type,
    p_status        in varchar2,
    p_input_tokens  in number,
    p_output_tokens in number
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'fire_after_hook';
    l_pkg   varchar2(128 char);
    l_stmt  varchar2(500 char);
  begin
    l_pkg := resolve_hook_pkg();
    if l_pkg is null then
      return;
    end if;

    l_stmt := 'begin ' || l_pkg || '.after_execution(:1, :2, :3, :4); end;';
    execute immediate l_stmt
      using in p_exec_id, in p_status, in p_input_tokens, in p_output_tokens;
  exception
    when others then
      uc_ai_logger.log_error(
        p_text  => 'after_execution hook failed for execution ' || p_exec_id
      , p_scope => l_scope
      , p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end fire_after_hook;


  /*
   * Registers/overrides/clears the execution hook package. See the spec.
   */
  procedure set_execution_hook(p_package_name in varchar2 default null)
  as
  begin
    if p_package_name is null then
      g_hook_override := null;
    else
      -- validates SCHEMA.PACKAGE syntax (raises ORA-44003 on bad input); no existence check
      g_hook_override := sys.dbms_assert.qualified_sql_name(p_package_name);
    end if;
    -- force convention re-resolution on next dispatch
    g_hook_resolved := false;
    g_hook_pkg      := null;
    g_hook_tool_cb  := null;
  end set_execution_hook;


  /*
   * Fires the optional per-tool-call hook. See the spec. Exceptions propagate
   * (a raise vetoes the tool call). The before_tool_call procedure is optional:
   * its presence on the resolved hook package is probed once and cached, so a
   * hook that only implements before/after_execution is simply never called here.
   */
  procedure fire_before_tool_hook(
    p_tool_code   in varchar2
  , p_agent_id    in number   default null
  , p_agent_code  in varchar2 default null
  , p_created_by  in varchar2 default null
  , p_session_id  in varchar2 default null
  , p_apex_app_id in number   default null
  )
  as
    l_pkg   varchar2(128 char);
    l_stmt  varchar2(500 char);
    l_owner varchar2(128 char);
    l_name  varchar2(128 char);
  begin
    l_pkg := resolve_hook_pkg();
    if l_pkg is null then
      return;
    end if;

    -- Probe once whether the resolved hook implements before_tool_call. Split a
    -- schema-qualified override (SCHEMA.PKG) so the lookup finds cross-schema hooks.
    if g_hook_tool_cb is null then
      if instr(l_pkg, '.') > 0 then
        l_owner := upper(substr(l_pkg, 1, instr(l_pkg, '.') - 1));
        l_name  := upper(substr(l_pkg, instr(l_pkg, '.') + 1));
      else
        l_owner := sys_context('userenv', 'current_schema');
        l_name  := upper(l_pkg);
      end if;

      select count(*)
        into g_hook_tool_cb
        from all_procedures
       where owner          = l_owner
         and object_name    = l_name
         and procedure_name = 'BEFORE_TOOL_CALL';
    end if;

    if g_hook_tool_cb = 0 then
      return;
    end if;

    l_stmt := 'begin ' || l_pkg || '.before_tool_call(:1, :2, :3, :4, :5, :6); end;';
    execute immediate l_stmt
      using in p_agent_id, in p_agent_code, in p_tool_code, in p_created_by, in p_session_id, in p_apex_app_id;
  end fire_before_tool_hook;

  /*
   * Extracts all agent_code references from a JSON object recursively
   */
  procedure extract_agent_codes(
    p_json       in json_element_t,
    pio_codes    in out nocopy t_agent_code_list
  )
  as
    l_scope    uc_ai_logger.scope := gc_scope_prefix || 'extract_agent_codes';
    l_obj      json_object_t;
    l_arr      json_array_t;
    l_keys     json_key_list;
    l_key      varchar2(4000 char);
    l_elem     json_element_t;
    l_code     uc_ai_agents.code%type;
  begin
    if p_json is null then
      return;
    end if;

    if p_json.is_object then
      l_obj := treat(p_json as json_object_t);
      l_keys := l_obj.get_keys;
      
      <<key_loop>>
      for i in 1 .. l_keys.count loop
        l_key := l_keys(i);
        
        -- Check for agent_code keys
        if l_key in ('agent_code', 'orchestrator_profile_code', 'moderator_agent_code', 
                     'initial_agent_code', 'summarizer_agent_code') then
          if l_obj.get(l_key).is_string then
            l_code := l_obj.get_string(l_key);
            pio_codes.extend;
            pio_codes(pio_codes.count) := l_code;
          end if;
        else
          -- Recurse into nested objects/arrays
          l_elem := l_obj.get(l_key);
          if l_elem is not null then
            extract_agent_codes(l_elem, pio_codes);
          end if;
        end if;
      end loop key_loop;
      
    elsif p_json.is_array then
      l_arr := treat(p_json as json_array_t);
      
      <<array_loop>>
      for i in 0 .. l_arr.get_size - 1 loop
        l_elem := l_arr.get(i);
        if l_elem is not null then
          extract_agent_codes(l_elem, pio_codes);
        end if;
      end loop array_loop;
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error extracting agent codes', l_scope);
      raise;
  end extract_agent_codes;


  /*
   * Checks if an agent with the given code exists
   */
  function agent_exists(
    p_agent_code in uc_ai_agents.code%type
  ) return boolean
  as
    l_count number;
  begin
    -- First check if it's a prompt profile (for orchestrator_profile_code)
    select count(*)
    into l_count
    from uc_ai_prompt_profiles
    where code = p_agent_code
      and status = 'active';
    
    if l_count > 0 then
      return true;
    end if;
    
    -- Then check agents
    select count(*)
    into l_count
    from uc_ai_agents
    where code = p_agent_code
      and status = c_status_active;
    
    return l_count > 0;
  end agent_exists;


  /*
   * Snapshots the caller's environment/session context.
   * Must run BEFORE uc_ai_agent_exec_api.create_apex_session_if_needed —
   * the synthetic APEX session persists for the DB session and would
   * mask the real caller.
   */
  function snapshot_exec_env return t_exec_env
  as
    l_env t_exec_env;
    l_ctx json_object_t := json_object_t();

    procedure put_if_set(p_key in varchar2, p_val in varchar2)
    as
    begin
      if p_val is not null then
        l_ctx.put(p_key, p_val);
      end if;
    end put_if_set;

    procedure put_if_set(p_key in varchar2, p_val in number)
    as
    begin
      if p_val is not null then
        l_ctx.put(p_key, p_val);
      end if;
    end put_if_set;
  begin
    l_env.db_user           := sys_context('userenv', 'session_user');
    l_env.os_user           := sys_context('userenv', 'os_user');
    l_env.host              := sys_context('userenv', 'host');
    l_env.ip_address        := sys_context('userenv', 'ip_address');
    l_env.module            := sys_context('userenv', 'module');
    l_env.action            := sys_context('userenv', 'action');
    l_env.client_identifier := sys_context('userenv', 'client_identifier');
    l_env.sid               := to_number(sys_context('userenv', 'sid'));

    l_env.apex_user := sys_context('APEX$SESSION', 'APP_USER');
    if l_env.apex_user = uc_ai_agent_exec_api.c_synthetic_apex_user then
      -- uc_ai's own synthetic session — not real caller context
      l_env.apex_user := null;
    elsif l_env.apex_user is not null then
      l_env.apex_session_id := to_number(sys_context('APEX$SESSION', 'APP_SESSION'));
      l_env.apex_app_id     := apex_application.g_flow_id;
      l_env.apex_page_id    := apex_application.g_flow_step_id;
    end if;

    l_env.created_by := coalesce(l_env.apex_user, l_env.db_user);

    put_if_set('session_user', l_env.db_user);
    put_if_set('current_schema', sys_context('userenv', 'current_schema'));
    put_if_set('os_user', l_env.os_user);
    put_if_set('client_identifier', l_env.client_identifier);
    put_if_set('client_info', sys_context('userenv', 'client_info'));
    put_if_set('ip_address', l_env.ip_address);
    put_if_set('host', l_env.host);
    put_if_set('terminal', sys_context('userenv', 'terminal'));
    put_if_set('module', l_env.module);
    put_if_set('action', l_env.action);
    put_if_set('sid', l_env.sid);
    put_if_set('apex_user', l_env.apex_user);
    put_if_set('apex_session_id', l_env.apex_session_id);
    put_if_set('apex_app_id', l_env.apex_app_id);
    put_if_set('apex_page_id', l_env.apex_page_id);

    l_env.env_context := l_ctx.to_clob;

    return l_env;
  end snapshot_exec_env;


  /*
   * Creates an execution record and returns its ID.
   * Commits in an autonomous transaction (Logger-style telemetry): execution
   * rows are immediately visible to other sessions and survive a rollback of
   * the calling transaction.
   */
  function create_execution(
    p_agent_id         in uc_ai_agents.id%type,
    p_session_id       in varchar2,
    p_parent_exec_id   in uc_ai_agent_executions.id%type,
    p_input_parameters in json_object_t
  ) return uc_ai_agent_executions.id%type
  as
    -- @dblinter ignore(g-3330): intentional Logger-style telemetry; execution rows must survive a rollback of the calling transaction
    pragma autonomous_transaction;
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'create_execution';
    l_exec_id uc_ai_agent_executions.id%type;
    l_params clob;
    l_turn_index uc_ai_agent_executions.turn_index%type;
    e_fk_violation exception;
    pragma exception_init(e_fk_violation, -2291);
    -- Self-deadlock: the autonomous insert blocks on the agent_id FK because the
    -- referenced agent row is still uncommitted in the calling transaction, which
    -- is in turn suspended waiting for this autonomous transaction to return.
    e_deadlock exception;
    pragma exception_init(e_deadlock, -60);
  begin
    if p_input_parameters is not null then
      l_params := p_input_parameters.to_clob;
    end if;

    -- Top-level turn: make sure the conversation header exists and assign the
    -- next turn number. Nested sub-agent runs (p_parent_exec_id set) inherit the
    -- session their parent already created and leave turn_index null, so their
    -- own tokens still roll into the session total without being counted as turns.
    if p_parent_exec_id is null then
      merge into uc_ai_agent_sessions s
      using (select p_session_id as session_id from sys.dual) src
      on (s.session_id = src.session_id)
      when not matched then insert (
        session_id, root_agent_id, status, started_at, last_activity_at,
        created_by, db_user, apex_user, apex_session_id, apex_app_id, apex_page_id,
        os_user, host, ip_address, module, action, client_identifier, sid, env_context
      ) values (
        p_session_id, p_agent_id, c_exec_running, systimestamp, systimestamp,
        g_exec_env.created_by, g_exec_env.db_user, g_exec_env.apex_user,
        g_exec_env.apex_session_id, g_exec_env.apex_app_id, g_exec_env.apex_page_id,
        g_exec_env.os_user, g_exec_env.host, g_exec_env.ip_address,
        g_exec_env.module, g_exec_env.action, g_exec_env.client_identifier,
        g_exec_env.sid, g_exec_env.env_context
      );

      select coalesce(max(turn_index), 0) + 1
        into l_turn_index
        from uc_ai_agent_executions
       where session_id = p_session_id;
    end if;

    insert into uc_ai_agent_executions (
      agent_id,
      parent_execution_id,
      session_id,
      turn_index,
      input_parameters,
      status,
      created_by,
      db_user,
      apex_user,
      apex_session_id,
      apex_app_id,
      apex_page_id,
      os_user,
      host,
      ip_address,
      module,
      action,
      client_identifier,
      sid,
      env_context
    ) values (
      p_agent_id,
      p_parent_exec_id,
      p_session_id,
      l_turn_index,
      l_params,
      c_exec_running,
      g_exec_env.created_by,
      g_exec_env.db_user,
      g_exec_env.apex_user,
      g_exec_env.apex_session_id,
      g_exec_env.apex_app_id,
      g_exec_env.apex_page_id,
      g_exec_env.os_user,
      g_exec_env.host,
      g_exec_env.ip_address,
      g_exec_env.module,
      g_exec_env.action,
      g_exec_env.client_identifier,
      g_exec_env.sid,
      g_exec_env.env_context
    )
    returning id into l_exec_id;

    commit;
    return l_exec_id;
  exception
    when e_fk_violation then
      rollback;
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'execution'
      , p1           => 'agent (id ' || p_agent_id || ') must be committed before execution because execution telemetry uses autonomous transactions'
      );
    when e_deadlock then
      rollback;
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'execution'
      , p1           => 'agent (id ' || p_agent_id || ') and any parent records must be committed before execution: execution telemetry runs in an autonomous transaction that cannot see rows still uncommitted in the calling transaction (raised ORA-00060 self-deadlock)'
      );
    when others then
      rollback;
      raise;
  end create_execution;


  /*
   * Updates execution with completion status and results.
   * Commits in an autonomous transaction; failed/timeout rows keep their last
   * state checkpoint for diagnosis, successful ones clear it (the final state
   * lives in output_result).
   */
  procedure complete_execution(
    p_exec_id           in uc_ai_agent_executions.id%type,
    p_status            in varchar2,
    p_output_result     in json_object_t default null,
    p_error_message     in varchar2 default null,
    p_iteration_count   in number default 0,
    p_tool_calls_count  in number default 0,
    p_input_tokens      in number default 0,
    p_output_tokens     in number default 0
  )
  as
    -- @dblinter ignore(g-3330): intentional autonomous transaction; failed/timeout state checkpoints must persist even when the run rolls back
    pragma autonomous_transaction;
    l_output_result clob;
  begin
    l_output_result := case when p_output_result is not null then p_output_result.to_clob else null end;

    update uc_ai_agent_executions
    set status              = p_status,
        output_result       = l_output_result,
        error_message       = p_error_message,
        completed_at        = systimestamp,
        iteration_count     = p_iteration_count,
        tool_calls_count    = p_tool_calls_count,
        total_input_tokens  = p_input_tokens,
        total_output_tokens = p_output_tokens,
        current_state       = case when p_status = c_exec_completed then null else current_state end
    where id = p_exec_id;

    commit;
  exception
    when others then
      rollback;
      raise;
  end complete_execution;


  /*
   * Recomputes and stores the conversation header aggregates for a session.
   * Runs top-level only, once per turn, after complete_execution and message
   * persistence have committed. Token totals SUM the OWN tokens of every
   * execution in the session (each row holds only the tokens of the LLM calls
   * it made itself, so nested sub-agent runs add in without double counting).
   * Best-effort: never raises (audit/reporting must not fail a finished run).
   */
  procedure maintain_session(
    p_session_id in varchar2,
    p_status     in varchar2
  )
  as
    -- @dblinter ignore(g-3330): intentional autonomous transaction; session telemetry must survive a rollback of the calling transaction, like create_execution/complete_execution
    pragma autonomous_transaction;
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'maintain_session';
  begin
    if p_session_id is null then
      return;
    end if;

    update uc_ai_agent_sessions s
       set s.status              = p_status,
           s.last_activity_at    = systimestamp,
           s.turn_count          = (select count(*)
                                      from uc_ai_agent_executions e
                                     where e.session_id = p_session_id
                                       and e.turn_index is not null),
           s.total_input_tokens  = (select nvl(sum(e.total_input_tokens), 0)
                                      from uc_ai_agent_executions e
                                     where e.session_id = p_session_id),
           s.total_output_tokens = (select nvl(sum(e.total_output_tokens), 0)
                                      from uc_ai_agent_executions e
                                     where e.session_id = p_session_id),
           s.message_count       = (select count(*)
                                      from uc_ai_agent_messages m
                                     where m.session_id = p_session_id)
     where s.session_id = p_session_id;

    commit;
  exception
    when others then
      rollback;
      uc_ai_logger.log_error(
        p_text  => 'Failed to maintain session ' || p_session_id
      , p_scope => l_scope
      , p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end maintain_session;


  /*
   * Persists the current turn's NEW messages into uc_ai_agent_messages, in
   * conversation order. The framework returns the full accumulated messages
   * array on follow-ups, so we only persist from the last 'user' message
   * onward (this turn's delta); earlier turns were persisted when they ran.
   *
   * Because trimming (apply_history_management) only governs what is sent to
   * the LLM, the delta persisted here is the complete, untrimmed record.
   * Best-effort: never raises.
   */
  procedure persist_turn_messages(
    p_exec_id    in uc_ai_agent_executions.id%type,
    p_session_id in varchar2,
    p_result     in json_object_t
  )
  as
    -- @dblinter ignore(g-3330): intentional autonomous transaction; message log must survive a rollback of the calling transaction
    pragma autonomous_transaction;
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'persist_turn_messages';
    l_messages     json_array_t;
    l_msg          json_object_t;
    l_content      json_element_t;
    l_content_arr  json_array_t;
    l_item         json_object_t;
    l_role         varchar2(50 char);
    l_type         varchar2(50 char);
    l_start_idx    pls_integer := 0;
    l_seq          number;
    l_msg_agent    uc_ai_agents.code%type;
    -- Attribution fallback: the executing turn's own agent. Wrapper patterns
    -- (conversation, handoff) override this per message via an 'agentCode'
    -- field so each row attributes to the sub-agent that produced it.
    l_exec_agent   uc_ai_agents.code%type;

    procedure ins(
      p_role        in varchar2,
      p_content     in clob     default null,
      p_agent_code  in varchar2 default null,
      p_tool_name   in varchar2 default null,
      p_tool_input  in clob     default null,
      p_tool_output in clob     default null,
      p_tool_status in varchar2 default null
    )
    as
    begin
      l_seq := l_seq + 1;
      insert into uc_ai_agent_messages (
        session_id, execution_id, seq, role, content, agent_code,
        tool_name, tool_input, tool_output, tool_status
      ) values (
        p_session_id, p_exec_id, l_seq, p_role, p_content, p_agent_code,
        p_tool_name, p_tool_input, p_tool_output, p_tool_status
      );
    end ins;
  begin
    if p_session_id is null or p_result is null then
      return;
    end if;

    -- Continue the session's global ordering
    select nvl(max(seq), 0)
      into l_seq
      from uc_ai_agent_messages
     where session_id = p_session_id;

    -- Attribution fallback for messages that carry no explicit 'agentCode'
    -- (direct patterns: profile/orchestrator run under their own agent).
    begin
      select a.code
        into l_exec_agent
        from uc_ai_agent_executions e
        join uc_ai_agents a on a.id = e.agent_id
       where e.id = p_exec_id;
    exception
      when no_data_found then
        l_exec_agent := null;
    end;

    -- No structured message array (e.g. some workflow agents): store the
    -- final_message as a single assistant row so the turn is not lost.
    if not p_result.has('messages') then
      if p_result.has('final_message') then
        ins(p_role => 'assistant', p_content => p_result.get_clob('final_message'),
            p_agent_code => l_exec_agent);
        commit;
      end if;
      return;
    end if;

    l_messages := p_result.get_array('messages');

    -- Find this turn's start: the index of the LAST 'user' message.
    <<find_turn_start>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_msg := treat(l_messages.get(i) as json_object_t);
      if l_msg.has('role') and l_msg.get_string('role') = 'user' then
        l_start_idx := i;
      end if;
    end loop find_turn_start;

    <<turn_messages>>
    for i in l_start_idx .. l_messages.get_size - 1 loop
      l_msg  := treat(l_messages.get(i) as json_object_t);
      l_role := l_msg.get_string('role');

      if not l_msg.has('content') then
        continue;
      end if;

      -- Attribution: caller input (user/system) has no producing agent; every
      -- other role attributes to the message's own 'agentCode' when a wrapper
      -- stamped one, else the executing turn's agent.
      if l_role in ('user', 'system') then
        l_msg_agent := null;
      else
        l_msg_agent := coalesce(l_msg.get_string('agentCode'), l_exec_agent);
      end if;

      l_content := l_msg.get('content');

      -- Content may be a plain string or an array of typed content items.
      if not l_content.is_array then
        ins(p_role => l_role, p_content => l_msg.get_clob('content'),
            p_agent_code => l_msg_agent);
        continue;
      end if;

      l_content_arr := treat(l_content as json_array_t);
      <<content_items>>
      for j in 0 .. l_content_arr.get_size - 1 loop
        l_item := treat(l_content_arr.get(j) as json_object_t);
        l_type := l_item.get_string('type');

        case l_type
          when 'text' then
            ins(p_role => l_role, p_content => l_item.get_clob('text'),
                p_agent_code => l_msg_agent);
          when 'reasoning' then
            ins(p_role => 'reasoning', p_content => l_item.get_clob('text'),
                p_agent_code => l_msg_agent);
          when 'tool_call' then
            ins(
              p_role       => 'tool_call',
              p_agent_code => l_msg_agent,
              p_tool_name  => l_item.get_string('toolName'),
              p_tool_input => l_item.get_clob('args')
            );
          when 'tool_result' then
            ins(
              p_role        => 'tool_result',
              p_agent_code  => l_msg_agent,
              p_tool_name   => l_item.get_string('toolName'),
              p_tool_output => l_item.get_clob('result'),
              p_tool_status => 'success'
            );
          else
            null; -- ignore unknown content types
        end case;
      end loop content_items;
    end loop turn_messages;

    commit;
  exception
    when others then
      rollback;
      uc_ai_logger.log_error(
        p_text  => 'Failed to persist messages for execution ' || p_exec_id
      , p_scope => l_scope
      , p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end persist_turn_messages;


  /*
   * Persists a mid-run state checkpoint for a running execution.
   * Commits in an autonomous transaction so running workflows can be monitored
   * from other sessions and crashed runs keep their last known state in
   * uc_ai_agent_executions.current_state. Best-effort: never raises.
   */
  procedure checkpoint_execution(
    p_exec_id       in uc_ai_agent_executions.id%type,
    p_current_state in json_object_t,
    p_last_step     in varchar2 default null
  )
  as
    -- @dblinter ignore(g-3330): intentional autonomous transaction; lets other sessions monitor running workflows and preserves last-known state of crashed runs
    pragma autonomous_transaction;
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'checkpoint_execution';
    l_state json_object_t;
    l_state_clob clob;
  begin
    if p_exec_id is null or p_current_state is null then
      return;
    end if;

    l_state := treat(p_current_state.clone as json_object_t);
    if p_last_step is not null then
      l_state.put('_last_completed_step', p_last_step);
    end if;
    l_state.put('_checkpoint_at', to_char(systimestamp, 'YYYY-MM-DD"T"HH24:MI:SS.FF3'));
    l_state_clob := l_state.to_clob;

    update uc_ai_agent_executions
    set current_state = l_state_clob
    where id = p_exec_id;

    commit;
  exception
    when others then
      -- best-effort telemetry: a checkpoint failure must never abort the run
      rollback;
      uc_ai_logger.log_error('Error writing execution checkpoint for execution ' || p_exec_id, l_scope, sqlerrm || chr(10) || sys.dbms_utility.format_error_backtrace);
  end checkpoint_execution;


  -- ============================================================================
  -- Public API Implementation
  -- ============================================================================

  /*
   * Generates a new session ID
   */
  function generate_session_id return varchar2
  as
  begin
    return sys_guid();
  end generate_session_id;


  /*
   * Creates a new agent
   */
  function create_agent(
    p_code                   in uc_ai_agents.code%type,
    p_description            in uc_ai_agents.description%type,
    p_agent_type             in uc_ai_agents.agent_type%type,
    p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
    p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
    p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
    p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
    p_input_schema           in uc_ai_agents.input_schema%type default null,
    p_output_schema          in uc_ai_agents.output_schema%type default null,
    p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
    p_max_iterations         in uc_ai_agents.max_iterations%type default null,
    p_max_history_messages   in uc_ai_agents.max_history_messages%type default null,
    p_version                in uc_ai_agents.version%type default 1,
    p_status                 in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'create_agent';
    l_id    uc_ai_agents.id%type;
  begin
    -- Validate agent type requirements
    case p_agent_type
      when c_type_profile then
        if p_prompt_profile_code is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_missing_config
          , p_scope      => l_scope
          , p0           => 'Profile agent'
          , p1           => 'prompt_profile_code'
          );
        end if;
        
      when c_type_workflow then
        if p_workflow_definition is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_missing_config
          , p_scope      => l_scope
          , p0           => 'Workflow agent'
          , p1           => 'workflow_definition'
          );
        end if;
        declare
          l_validation t_validation_result;
        begin
          l_validation := validate_workflow_definition(p_workflow_definition);
          if not l_validation.is_valid then
            uc_ai_error.raise_error(
              p_error_code => uc_ai_error.c_err_invalid_config
            , p_scope      => l_scope
            , p0           => 'workflow definition'
            , p1           => l_validation.error_reason
            );
          end if;
        end;
        
      when c_type_orchestrator then
        if p_orchestration_config is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_missing_config
          , p_scope      => l_scope
          , p0           => 'Orchestrator agent'
          , p1           => 'orchestration_config'
          );
        end if;
        
      when c_type_handoff then
        if p_orchestration_config is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_missing_config
          , p_scope      => l_scope
          , p0           => 'Handoff agent'
          , p1           => 'orchestration_config'
          );
        end if;
        declare
          l_validation t_validation_result;
        begin
          -- Only wired in for the handoff type: the validator's conversation
          -- branch expects participant_agents while the engine reads agents.
          l_validation := validate_orchestration_config(p_orchestration_config);
          if not l_validation.is_valid then
            uc_ai_error.raise_error(
              p_error_code => uc_ai_error.c_err_invalid_config
            , p_scope      => l_scope
            , p0           => 'orchestration config'
            , p1           => l_validation.error_reason
            );
          end if;
        end;
        -- v1: transfer tools are injected via the profile execution path, so the
        -- initial agent and every handoff target must be an ACTIVE profile agent
        declare
          l_config  json_object_t := json_object_t.parse(p_orchestration_config);
          l_targets json_array_t;
          l_codes   apex_t_varchar2 := apex_t_varchar2();
          l_bad     varchar2(4000 char);
        begin
          l_targets := l_config.get_array('handoff_agents');
          l_codes.extend;
          l_codes(l_codes.count) := l_config.get_string('initial_agent_code');
          <<collect_targets>>
          for i in 0 .. l_targets.get_size - 1 loop
            l_codes.extend;
            l_codes(l_codes.count) := treat(l_targets.get(i) as json_object_t).get_string('agent_code');
          end loop collect_targets;

          select listagg(t.column_value, ', ')
            into l_bad
            from table(l_codes) t
           where not exists (
                   select 1
                     from uc_ai_agents a
                    where a.code = t.column_value
                      and a.status = c_status_active
                      and a.agent_type = c_type_profile
                 );

          if l_bad is not null then
            uc_ai_error.raise_error(
              p_error_code => uc_ai_error.c_err_invalid_config
            , p_scope      => l_scope
            , p0           => 'handoff agents'
            , p1           => 'initial agent and handoff targets must be existing active profile agents; invalid: ' || l_bad
            );
          end if;
        end;

      when c_type_conversation then
        if p_orchestration_config is null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_missing_config
          , p_scope      => l_scope
          , p0           => 'Conversation agent'
          , p1           => 'orchestration_config'
          );
        end if;
        
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unknown_agent_type
        , p_scope      => l_scope
        , p0           => p_agent_type
        );
    end case;
    
    -- Validate agent references in configs
    declare
      l_validation t_validation_result;
    begin
      l_validation := validate_agent_references(p_workflow_definition, p_orchestration_config);
      if not l_validation.is_valid then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'agent references in configuration'
        , p1           => l_validation.error_reason
        );
      end if;
    end;

    insert into uc_ai_agents (
      code,
      version,
      status,
      description,
      agent_type,
      prompt_profile_code,
      prompt_profile_version,
      workflow_definition,
      orchestration_config,
      input_schema,
      output_schema,
      timeout_seconds,
      max_iterations,
      max_history_messages
    ) values (
      p_code,
      p_version,
      p_status,
      p_description,
      p_agent_type,
      p_prompt_profile_code,
      p_prompt_profile_version,
      p_workflow_definition,
      p_orchestration_config,
      p_input_schema,
      p_output_schema,
      p_timeout_seconds,
      p_max_iterations,
      p_max_history_messages
    )
    returning id into l_id;
    
    return l_id;
  exception
    when others then
      uc_ai_logger.log_error('Error creating agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end create_agent;


  /*
   * Updates an existing agent by ID
   */
  procedure update_agent(
    p_id                     in uc_ai_agents.id%type,
    p_description            in uc_ai_agents.description%type default null,
    p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
    p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
    p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
    p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
    p_input_schema           in uc_ai_agents.input_schema%type default null,
    p_output_schema          in uc_ai_agents.output_schema%type default null,
    p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
    p_max_iterations         in uc_ai_agents.max_iterations%type default null,
    p_max_history_messages   in uc_ai_agents.max_history_messages%type default null
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'update_agent';
  begin
    -- Validate agent references if configs are being updated
    if p_workflow_definition is not null or p_orchestration_config is not null then
      declare
        l_validation t_validation_result;
      begin
        l_validation := validate_agent_references(p_workflow_definition, p_orchestration_config);
        if not l_validation.is_valid then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_invalid_config
          , p_scope      => l_scope
          , p0           => 'agent references in configuration'
          , p1           => l_validation.error_reason
          );
        end if;
      end;
    end if;

    update uc_ai_agents
    set description            = coalesce(p_description, description),
        prompt_profile_code    = coalesce(p_prompt_profile_code, prompt_profile_code),
        prompt_profile_version = coalesce(p_prompt_profile_version, prompt_profile_version),
        workflow_definition    = coalesce(p_workflow_definition, workflow_definition),
        orchestration_config   = coalesce(p_orchestration_config, orchestration_config),
        input_schema           = coalesce(p_input_schema, input_schema),
        output_schema          = coalesce(p_output_schema, output_schema),
        timeout_seconds        = coalesce(p_timeout_seconds, timeout_seconds),
        max_iterations         = coalesce(p_max_iterations, max_iterations),
        max_history_messages   = coalesce(p_max_history_messages, max_history_messages)
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_id
      );
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error updating agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end update_agent;


  /*
   * Deletes an agent by ID
   */
  procedure delete_agent(
    p_id in uc_ai_agents.id%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'delete_agent';
    l_code  uc_ai_agents.code%type;
  begin
    -- Get the code first
    select code into l_code
    from uc_ai_agents
    where id = p_id;
    
    -- Check if referenced
    check_agent_not_referenced(l_code);
    
    delete from uc_ai_agents
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_id
      );
    end if;
  exception
    when no_data_found then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_id
      );
    when others then
      uc_ai_logger.log_error('Error deleting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end delete_agent;


  /*
   * Deletes an agent by code and version
   */
  procedure delete_agent(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'delete_agent';
  begin
    -- Check if referenced
    check_agent_not_referenced(p_code);
    
    delete from uc_ai_agents
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_code || ' v' || p_version
      );
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error deleting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end delete_agent;


  /*
   * Changes the status of an agent by ID
   */
  procedure change_status(
    p_id     in uc_ai_agents.id%type,
    p_status in uc_ai_agents.status%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'change_status';
  begin
    if p_status not in (c_status_draft, c_status_active, c_status_archived) then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_status
      , p_scope      => l_scope
      , p0           => p_status
      , p1           => 'draft, active, archived'
      );
    end if;

    update uc_ai_agents
    set status = p_status
    where id = p_id;

    if sql%rowcount = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_id
      );
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error changing agent status', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end change_status;


  /*
   * Changes the status of an agent by code and version
   */
  procedure change_status(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type,
    p_status  in uc_ai_agents.status%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'change_status';
  begin
    if p_status not in (c_status_draft, c_status_active, c_status_archived) then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_status
      , p_scope      => l_scope
      , p0           => p_status
      , p1           => 'draft, active, archived'
      );
    end if;

    update uc_ai_agents
    set status = p_status
    where code = p_code
      and version = p_version;

    if sql%rowcount = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_code || ' v' || p_version
      );
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error changing agent status', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end change_status;


  /*
   * Creates a new version of an existing agent
   */
  function create_new_version(
    p_code           in uc_ai_agents.code%type,
    p_source_version in uc_ai_agents.version%type,
    p_new_version    in uc_ai_agents.version%type default null
  ) return uc_ai_agents.id%type
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'create_new_version';
    l_source_agent uc_ai_agents%rowtype;
    l_new_id       uc_ai_agents.id%type;
    l_version      uc_ai_agents.version%type;
  begin
    -- Get source agent
    begin
      select *
      into l_source_agent
      from uc_ai_agents
      where code = p_code
        and version = p_source_version;
    exception
      when no_data_found then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_not_found
        , p_scope      => l_scope
        , p0           => 'Source agent'
        , p1           => p_code || ' v' || p_source_version
        );
    end;

    -- Determine new version number
    if p_new_version is null then
      select nvl(max(version), 0) + 1
      into l_version
      from uc_ai_agents
      where code = p_code;
    else
      l_version := p_new_version;
    end if;

    -- Create new version
    insert into uc_ai_agents (
      code,
      version,
      status,
      description,
      agent_type,
      prompt_profile_code,
      prompt_profile_version,
      workflow_definition,
      orchestration_config,
      input_schema,
      output_schema,
      timeout_seconds,
      max_iterations,
      max_history_messages
    ) values (
      l_source_agent.code,
      l_version,
      c_status_draft,
      l_source_agent.description,
      l_source_agent.agent_type,
      l_source_agent.prompt_profile_code,
      l_source_agent.prompt_profile_version,
      l_source_agent.workflow_definition,
      l_source_agent.orchestration_config,
      l_source_agent.input_schema,
      l_source_agent.output_schema,
      l_source_agent.timeout_seconds,
      l_source_agent.max_iterations,
      l_source_agent.max_history_messages
    )
    returning id into l_new_id;
    
    return l_new_id;
  exception
    when others then
      uc_ai_logger.log_error('Error creating new version of agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end create_new_version;


  /*
   * Gets an agent by ID
   */
  function get_agent(
    p_id in uc_ai_agents.id%type
  ) return uc_ai_agents%rowtype
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_agent';
    l_agent uc_ai_agents%rowtype;
  begin
    select *
    into l_agent
    from uc_ai_agents
    where id = p_id;

    return l_agent;
  exception
    when no_data_found then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Agent'
      , p1           => p_id
      );
    when others then
      uc_ai_logger.log_error('Error getting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end get_agent;


  /*
   * Gets an agent by code and version
   */
  function get_agent(
    p_code    in uc_ai_agents.code%type,
    p_version in uc_ai_agents.version%type default null
  ) return uc_ai_agents%rowtype
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_agent';
    l_agent uc_ai_agents%rowtype;
  begin
    if p_version is null then
      -- Get latest active version
      select *
      into l_agent
      from uc_ai_agents
      where code = p_code
        and status = c_status_active
      order by version desc
      fetch first 1 row only;
    else
      select *
      into l_agent
      from uc_ai_agents
      where code = p_code
        and version = p_version;
    end if;

    return l_agent;
  exception
    when no_data_found then
      if p_version is null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_not_found
        , p_scope      => l_scope
        , p0           => 'Active agent'
        , p1           => p_code
        );
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_not_found
        , p_scope      => l_scope
        , p0           => 'Agent'
        , p1           => p_code || ' v' || p_version
        );
      end if;
    when others then
      uc_ai_logger.log_error('Error getting agent', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end get_agent;


  /*
   * Validates that all agent_code references exist
   */
  function validate_agent_references(
    p_workflow_definition  in clob default null,
    p_orchestration_config in clob default null
  ) return t_validation_result
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'validate_agent_references';
    l_result    t_validation_result;
    l_codes_arr t_agent_code_list := t_agent_code_list();
    l_json      json_element_t;
  begin
    l_result.is_valid := true;
    l_result.error_reason := null;
    
    -- Extract codes from workflow definition
    if p_workflow_definition is not null then
      l_json := json_element_t.parse(p_workflow_definition);
      extract_agent_codes(l_json, l_codes_arr);
    end if;
    
    -- Extract codes from orchestration config
    if p_orchestration_config is not null then
      begin
        l_json := json_element_t.parse(p_orchestration_config);
      exception
        when others then
          l_result.is_valid := false;
          l_result.error_reason := 'Invalid JSON in orchestration_config: ' || sqlerrm;
          uc_ai_logger.log_error('Invalid JSON in orchestration_config.', l_scope, 'json:' || p_orchestration_config || ' | ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
          return l_result;
      end;
      extract_agent_codes(l_json, l_codes_arr);
    end if;
    
    -- Validate each code exists
    <<code_loop>>
    for i in 1 .. l_codes_arr.count loop
      if not agent_exists(l_codes_arr(i)) then
        l_result.is_valid := false;
        l_result.error_reason := 'Referenced agent or profile does not exist: ' || l_codes_arr(i);
        uc_ai_logger.log_error(l_result.error_reason, l_scope);
        return l_result;
      end if;
    end loop code_loop;
    
    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error validating agent references', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end validate_agent_references;


  /*
   * Checks if an agent is referenced by other agents
   */
  procedure check_agent_not_referenced(
    p_agent_code in uc_ai_agents.code%type
  )
  as
    l_scope       uc_ai_logger.scope := gc_scope_prefix || 'check_agent_not_referenced';
    l_ref_count   number;
    l_search_expr varchar2(4000 char);
  begin
    -- Build search expression
    l_search_expr := '"agent_code"[[:space:]]*:[[:space:]]*"' || p_agent_code || '"';
    
    -- Search in workflow definitions and orchestration configs
    select count(*)
    into l_ref_count
    from uc_ai_agents
    where (workflow_definition is not null and regexp_like(workflow_definition, l_search_expr))
       or (orchestration_config is not null and regexp_like(orchestration_config, l_search_expr));
    
    if l_ref_count > 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_has_references
      , p_scope      => l_scope
      , p0           => p_agent_code
      , p1           => l_ref_count
      );
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error checking agent references', l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end check_agent_not_referenced;


  /*
   * Validates a workflow definition JSON
   */
  function validate_workflow_definition(
    p_workflow_definition in clob
  ) return t_validation_result
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'validate_workflow_definition';
    l_result        t_validation_result;
    l_json          json_object_t;
    l_workflow_type varchar2(50 char);
    l_steps         json_array_t;
  begin
    l_result.is_valid := true;
    l_result.error_reason := null;
    
    if p_workflow_definition is null then
      l_result.is_valid := false;
      l_result.error_reason := 'workflow_definition is null';
      return l_result;
    end if;
    
    l_json := json_object_t.parse(p_workflow_definition);
    
    -- Check required fields
    if not l_json.has('workflow_type') then
      l_result.is_valid := false;
      l_result.error_reason := 'Missing required field: workflow_type';
      uc_ai_logger.log_error('workflow_definition ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    l_workflow_type := l_json.get_string('workflow_type');
    if l_workflow_type not in (
      uc_ai_agent_exec_api.c_workflow_sequential, 
      uc_ai_agent_exec_api.c_workflow_conditional, 
      uc_ai_agent_exec_api.c_workflow_parallel, 
      uc_ai_agent_exec_api.c_workflow_loop
    ) then
      l_result.is_valid := false;
      l_result.error_reason := 'Invalid workflow_type: ' || l_workflow_type || '. Must be one of: sequential, conditional, parallel, loop';
      uc_ai_logger.log_error(l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    if not l_json.has('steps') then
      l_result.is_valid := false;
      l_result.error_reason := 'Missing required field: steps';
      uc_ai_logger.log_error('workflow_definition ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    l_steps := l_json.get_array('steps');
    if l_steps.get_size = 0 then
      l_result.is_valid := false;
      l_result.error_reason := 'steps array is empty';
      uc_ai_logger.log_error('workflow_definition ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    -- Validate each step: agent steps need agent_code, PL/SQL steps need plsql_function_call
    <<step_loop>>
    for i in 0 .. l_steps.get_size - 1 loop
      declare
        l_step      json_object_t := treat(l_steps.get(i) as json_object_t);
        l_step_type varchar2(20 char);
      begin
        l_step_type := coalesce(l_step.get_string('step_type'), uc_ai_agent_exec_api.c_step_agent);

        case l_step_type
          when uc_ai_agent_exec_api.c_step_agent then
            if not l_step.has('agent_code') then
              l_result.is_valid := false;
              l_result.error_reason := 'Step ' || i || ' missing required field: agent_code';
              uc_ai_logger.log_error(l_result.error_reason, l_scope);
              return l_result;
            end if;
          when uc_ai_agent_exec_api.c_step_plsql then
            -- agent_code and output_key are optional for PL/SQL steps
            if not l_step.has('plsql_function_call') or l_step.get_clob('plsql_function_call') is null then
              l_result.is_valid := false;
              l_result.error_reason := 'Step ' || i || ' (plsql) missing required field: plsql_function_call';
              uc_ai_logger.log_error(l_result.error_reason, l_scope);
              return l_result;
            end if;
          else
            l_result.is_valid := false;
            l_result.error_reason := 'Step ' || i || ' has invalid step_type: ' || l_step_type || '. Must be one of: agent, plsql';
            uc_ai_logger.log_error(l_result.error_reason, l_scope);
            return l_result;
        end case;

        -- condition must be a string holding a PL/SQL boolean expression;
        -- other types would be silently ignored at execution time
        if l_step.has('condition') and not l_step.get('condition').is_string() then
          l_result.is_valid := false;
          l_result.error_reason := 'Step ' || i || ' condition must be a string containing a PL/SQL boolean expression';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
      end;
    end loop step_loop;
    
    return l_result;
  exception
    when others then
      l_result.is_valid := false;
      l_result.error_reason := 'Error parsing workflow definition: ' || sqlerrm;
      uc_ai_logger.log_error('Error validating workflow definition: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end validate_workflow_definition;


  /*
   * Validates an orchestration config JSON
   */
  function validate_orchestration_config(
    p_orchestration_config in clob
  ) return t_validation_result
  as
    l_scope        uc_ai_logger.scope := gc_scope_prefix || 'validate_orchestration_config';
    l_result       t_validation_result;
    l_json         json_object_t;
    l_pattern_type varchar2(50 char);
  begin
    l_result.is_valid := true;
    l_result.error_reason := null;
    
    if p_orchestration_config is null then
      l_result.is_valid := false;
      l_result.error_reason := 'orchestration_config is null';
      return l_result;
    end if;
    
    l_json := json_object_t.parse(p_orchestration_config);
    
    -- Check required fields based on pattern type
    if not l_json.has('pattern_type') then
      l_result.is_valid := false;
      l_result.error_reason := 'Missing required field: pattern_type';
      uc_ai_logger.log_error('orchestration_config ' || l_result.error_reason, l_scope);
      return l_result;
    end if;
    
    l_pattern_type := l_json.get_string('pattern_type');
    
    case l_pattern_type
      when 'orchestrator' then
        if not l_json.has('orchestrator_profile_code') then
          l_result.is_valid := false;
          l_result.error_reason := 'Orchestrator config missing required field: orchestrator_profile_code';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        if not l_json.has('delegate_agents') then
          l_result.is_valid := false;
          l_result.error_reason := 'Orchestrator config missing required field: delegate_agents';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        
      when 'handoff' then
        if not l_json.has('initial_agent_code') then
          l_result.is_valid := false;
          l_result.error_reason := 'Handoff config missing required field: initial_agent_code';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        if not (l_json.has('handoff_agents') and l_json.get('handoff_agents').is_array) then
          l_result.is_valid := false;
          l_result.error_reason := 'Handoff config missing required field: handoff_agents (array)';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        declare
          l_handoff_agents json_array_t := l_json.get_array('handoff_agents');
          l_target         json_object_t;
          l_transfer_to    json_array_t;
          l_edge           varchar2(255 char);
          type t_code_set is table of boolean index by varchar2(255 char);
          l_codes          t_code_set; -- @dblinter ignore(g-9105): set of entry codes for edge validation, not a local array
        begin
          if l_handoff_agents.get_size = 0 then
            l_result.is_valid := false;
            l_result.error_reason := 'Handoff config handoff_agents must not be empty';
            uc_ai_logger.log_error(l_result.error_reason, l_scope);
            return l_result;
          end if;
          <<handoff_targets>>
          for i in 0 .. l_handoff_agents.get_size - 1 loop
            if not l_handoff_agents.get(i).is_object then
              l_result.is_valid := false;
              l_result.error_reason := 'Handoff config handoff_agents entry ' || i || ' must be an object';
              uc_ai_logger.log_error(l_result.error_reason, l_scope);
              return l_result;
            end if;
            l_target := treat(l_handoff_agents.get(i) as json_object_t);
            if l_target.get_string('agent_code') is null then
              l_result.is_valid := false;
              l_result.error_reason := 'Handoff config handoff_agents entry ' || i || ' missing required field: agent_code';
              uc_ai_logger.log_error(l_result.error_reason, l_scope);
              return l_result;
            end if;
            l_codes(l_target.get_string('agent_code')) := true;
          end loop handoff_targets;

          -- can_transfer_to edges must reference other handoff_agents entries
          <<edge_validation>>
          for i in 0 .. l_handoff_agents.get_size - 1 loop
            l_target := treat(l_handoff_agents.get(i) as json_object_t);
            if l_target.has('can_transfer_to') then
              if not l_target.get('can_transfer_to').is_array then
                l_result.is_valid := false;
                l_result.error_reason := 'Handoff config handoff_agents entry ' || i || ' can_transfer_to must be an array';
                uc_ai_logger.log_error(l_result.error_reason, l_scope);
                return l_result;
              end if;
              l_transfer_to := l_target.get_array('can_transfer_to');
              if l_transfer_to.get_size = 0 then
                l_result.is_valid := false;
                l_result.error_reason := 'Handoff config handoff_agents entry ' || i || ' can_transfer_to must not be empty (omit it for full mesh)';
                uc_ai_logger.log_error(l_result.error_reason, l_scope);
                return l_result;
              end if;
              <<edge_loop>>
              for j in 0 .. l_transfer_to.get_size - 1 loop
                l_edge := l_transfer_to.get_string(j);
                if l_edge is null or not l_codes.exists(l_edge) then
                  l_result.is_valid := false;
                  l_result.error_reason := 'Handoff config handoff_agents entry ' || i
                    || ' can_transfer_to references unknown agent: ' || coalesce(l_edge, '(null)');
                  uc_ai_logger.log_error(l_result.error_reason, l_scope);
                  return l_result;
                end if;
                if l_edge = l_target.get_string('agent_code') then
                  l_result.is_valid := false;
                  l_result.error_reason := 'Handoff config handoff_agents entry ' || i
                    || ' can_transfer_to must not reference itself';
                  uc_ai_logger.log_error(l_result.error_reason, l_scope);
                  return l_result;
                end if;
              end loop edge_loop;
            end if;
          end loop edge_validation;
        end;
        if l_json.has('max_handoffs')
          and coalesce(l_json.get_number('max_handoffs'), 0) < 1
        then
          l_result.is_valid := false;
          l_result.error_reason := 'Handoff config max_handoffs must be a number >= 1';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;

      when 'conversation' then
        if not l_json.has('conversation_mode') then
          l_result.is_valid := false;
          l_result.error_reason := 'Conversation config missing required field: conversation_mode';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        if not l_json.has('participant_agents') then
          l_result.is_valid := false;
          l_result.error_reason := 'Conversation config missing required field: participant_agents';
          uc_ai_logger.log_error(l_result.error_reason, l_scope);
          return l_result;
        end if;
        
      else
        l_result.is_valid := false;
        l_result.error_reason := 'Invalid pattern_type: ' || l_pattern_type || '. Must be one of: orchestrator, handoff, conversation';
        uc_ai_logger.log_error(l_result.error_reason, l_scope);
        return l_result;
    end case;
    
    return l_result;
  exception
    when others then
      l_result.is_valid := false;
      l_result.error_reason := 'Error parsing orchestration config: ' || sqlerrm;
      uc_ai_logger.log_error('Error validating orchestration config: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace, l_scope);
      return l_result;
  end validate_orchestration_config;


  /*
   * Creates a sequential workflow agent
   */
  function create_sequential_workflow(
    p_code        in uc_ai_agents.code%type,
    p_description in uc_ai_agents.description%type,
    p_agent_steps in json_array_t,
    p_status      in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type
  as
    l_scope          uc_ai_logger.scope := gc_scope_prefix || 'create_sequential_workflow';
    l_workflow_def   json_object_t := json_object_t();
    l_steps          json_array_t := json_array_t();
    l_step           json_object_t;
    l_agent_code     varchar2(255 char);
  begin
    -- Build workflow definition
    l_workflow_def.put('workflow_type', uc_ai_agent_exec_api.c_workflow_sequential);
    
    -- Convert simple array of agent codes to step objects
    <<step_loop>>
    for i in 0 .. p_agent_steps.get_size - 1 loop
      l_agent_code := p_agent_steps.get_string(i);
      l_step := json_object_t();
      l_step.put('step_id', 'step_' || (i + 1));
      l_step.put('agent_code', l_agent_code);
      l_steps.append(l_step);
    end loop step_loop;
    
    l_workflow_def.put('steps', l_steps);
    
    return create_agent(
      p_code                => p_code,
      p_description         => p_description,
      p_agent_type          => c_type_workflow,
      p_workflow_definition => l_workflow_def.to_clob,
      p_status              => p_status
    );
  exception
    when others then
      uc_ai_logger.log_error('Error creating sequential workflow', l_scope);
      raise;
  end create_sequential_workflow;


  /*
   * Creates a parallel workflow agent
   */
  function create_parallel_workflow(
    p_code                 in uc_ai_agents.code%type,
    p_description          in uc_ai_agents.description%type,
    p_agent_steps          in json_array_t,
    p_aggregation_strategy in varchar2 default 'merge',
    p_status               in uc_ai_agents.status%type default c_status_draft
  ) return uc_ai_agents.id%type
  as
    l_scope           uc_ai_logger.scope := gc_scope_prefix || 'create_parallel_workflow';
    l_workflow_def    json_object_t := json_object_t();
    l_parallel_config json_object_t := json_object_t();
    l_steps           json_array_t := json_array_t();
    l_step            json_object_t;
    l_agent_code      varchar2(255 char);
  begin
    -- Build workflow definition
    l_workflow_def.put('workflow_type', uc_ai_agent_exec_api.c_workflow_parallel);
    
    -- Convert simple array of agent codes to step objects
    <<step_loop>>
    for i in 0 .. p_agent_steps.get_size - 1 loop
      l_agent_code := p_agent_steps.get_string(i);
      l_step := json_object_t();
      l_step.put('step_id', 'step_' || (i + 1));
      l_step.put('agent_code', l_agent_code);
      l_step.put('parallel_group', 1);  -- All in same parallel group
      l_steps.append(l_step);
    end loop step_loop;
    
    l_workflow_def.put('steps', l_steps);
    
    -- Add parallel config
    l_parallel_config.put('execution_mode', 'wait_all');
    l_parallel_config.put('aggregation_strategy', p_aggregation_strategy);
    l_workflow_def.put('parallel_config', l_parallel_config);
    
    return create_agent(
      p_code                => p_code,
      p_description         => p_description,
      p_agent_type          => c_type_workflow,
      p_workflow_definition => l_workflow_def.to_clob,
      p_status              => p_status
    );
  exception
    when others then
      uc_ai_logger.log_error('Error creating parallel workflow', l_scope);
      raise;
  end create_parallel_workflow;


  /*
   * Executes an agent by code
   */
  function execute_agent(
    p_agent_code        in uc_ai_agents.code%type,
    p_agent_version     in uc_ai_agents.version%type default null,
    p_input_parameters  in json_object_t default null,
    p_follow_up_message in clob default null,
    p_session_id        in varchar2 default null,
    p_parent_exec_id    in uc_ai_agent_executions.id%type default null,
    p_response_schema   in json_object_t default null,
    p_files             in uc_ai_message_api.t_files default null,
    p_extra_tool_tag    in varchar2 default null
  ) return json_object_t
  as
    l_scope         uc_ai_logger.scope := gc_scope_prefix || 'execute_agent';
    l_agent         uc_ai_agents%rowtype;
    l_exec_id       uc_ai_agent_executions.id%type;
    l_session_id    varchar2(255 char);
    l_result        json_object_t;
    l_usage         json_object_t;
    l_input_tokens  number := 0;
    l_output_tokens number := 0;
    l_is_top_level  boolean;
    l_prev_ctx      uc_ai.t_exec_context;
    l_this_ctx      uc_ai.t_exec_context;
  begin
    uc_ai_logger.log('Executing agent: ' || p_agent_code, l_scope);

    -- Capture caller context once per top-level execution, before the
    -- synthetic APEX session masks it; nested executions reuse it
    l_is_top_level := (g_exec_depth = 0);
    if l_is_top_level then
      g_exec_env := snapshot_exec_env();
    end if;
    g_exec_depth := g_exec_depth + 1;

    -- Bail out before creating an execution row if nesting is too deep. The
    -- outer exception handler below decrements g_exec_depth as it unwinds.
    if g_exec_depth > c_max_exec_depth then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_max_exec_depth
      , p_scope      => l_scope
      , p0           => c_max_exec_depth
      );
    end if;

    uc_ai_agent_exec_api.create_apex_session_if_needed;

    -- Get agent
    l_agent := get_agent(p_agent_code, p_agent_version);

    -- Validate response_schema usage
    if p_response_schema is not null and l_agent.agent_type != c_type_profile then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'response_schema'
      , p1           => 'can only be used with profile agents, not ' || l_agent.agent_type
      );
    end if;

    -- Validate extra_tool_tag usage (engine-internal, handoff transfer tools)
    if p_extra_tool_tag is not null and l_agent.agent_type != c_type_profile then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'extra_tool_tag'
      , p1           => 'can only be used with profile agents, not ' || l_agent.agent_type
      );
    end if;

    -- Validate follow_up_message usage
    if p_follow_up_message is not null then
      if l_agent.agent_type not in (c_type_profile, c_type_orchestrator, c_type_handoff) then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'follow_up_message'
        , p1           => 'can only be used with profile, orchestrator or handoff agents, not ' || l_agent.agent_type
        );
      end if;

      if p_session_id is null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'follow_up_message'
        , p1           => 'requires p_session_id to identify the conversation to continue'
        );
      end if;
    end if;

    -- Validate file input usage (only profile/orchestrator agents build a user message)
    if p_files is not null and p_files.count > 0
       and l_agent.agent_type not in (c_type_profile, c_type_orchestrator) then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'files'
      , p1           => 'can only be used with profile or orchestrator agents, not ' || l_agent.agent_type
      );
    end if;

    -- Generate session ID if not provided
    l_session_id := coalesce(p_session_id, generate_session_id());

    -- Fire the pre-execution hook (top-level only). A hook may veto by raising,
    -- aborting before any execution row is created or tokens are spent.
    if l_is_top_level then
      fire_before_hook(
        p_agent_id    => l_agent.id
      , p_agent_code  => p_agent_code
      , p_created_by  => g_exec_env.created_by
      , p_apex_app_id => g_exec_env.apex_app_id
      , p_session_id  => l_session_id
      );
    end if;

    -- Create execution record
    l_exec_id := create_execution(l_agent.id, l_session_id, p_parent_exec_id, p_input_parameters);

    -- Publish this agent's context so the per-tool-call hook (fired deep inside
    -- generate_text) can attribute a tool call to its agent and caller. Set per
    -- execution (not just top-level) so a nested agent reports its own code;
    -- save the caller's context and restore it on every exit below.
    l_prev_ctx             := uc_ai.get_exec_context;
    l_this_ctx.agent_id    := l_agent.id;
    l_this_ctx.agent_code  := p_agent_code;
    l_this_ctx.created_by  := g_exec_env.created_by;
    l_this_ctx.session_id  := l_session_id;
    l_this_ctx.apex_app_id := g_exec_env.apex_app_id;
    uc_ai.set_exec_context(l_this_ctx);

    begin
      -- Execute based on agent type (delegating to sub-package)
      case l_agent.agent_type
        when c_type_profile then
          l_result := uc_ai_agent_exec_api.execute_profile_agent(l_agent, p_input_parameters, l_exec_id, p_response_schema, p_follow_up_message, l_session_id, p_files, p_extra_tool_tag);

        when c_type_workflow then
          l_result := uc_ai_agent_exec_api.execute_workflow_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);

        when c_type_orchestrator then
          l_result := uc_ai_agent_exec_api.execute_orchestrator_agent(l_agent, p_input_parameters, l_session_id, l_exec_id, p_follow_up_message, p_files);

        when c_type_handoff then
          l_result := uc_ai_agent_exec_api.execute_handoff_agent(l_agent, p_input_parameters, l_session_id, l_exec_id, p_follow_up_message);

        when c_type_conversation then
          l_result := uc_ai_agent_exec_api.execute_conversation_agent(l_agent, p_input_parameters, l_session_id, l_exec_id);

        else
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_unknown_agent_type
          , p_scope      => l_scope
          , p0           => l_agent.agent_type
          );
      end case;

      l_result.put('execution_id', l_exec_id);
      l_result.put('agent_code', p_agent_code);
      l_result.put('agent_version', l_agent.version);
      l_result.put('session_id', l_session_id);
      l_result.put('status', c_exec_completed);

      uc_ai_logger.log('Agent execution completed: ' || p_agent_code, l_scope, l_result.to_clob);

      -- Extract token usage from result. Each execution records only the OWN
      -- tokens of the LLM calls it made itself: profile and orchestrator agents
      -- return a generate_text() usage object, while workflow/handoff/
      -- conversation agents make no direct LLM calls (all their tokens live on
      -- their child executions) and therefore keep their own totals at 0.
      -- Conversation-wide totals are the SUM across every execution in the
      -- session and are maintained on the session header (see maintain_session).
      if l_result.has('usage') then
        l_usage := l_result.get_object('usage');
        l_input_tokens := nvl(l_usage.get_number('prompt_tokens'), 0);
        l_output_tokens := nvl(l_usage.get_number('completion_tokens'), 0);
      end if;

      -- Update execution as completed
      complete_execution(
        p_exec_id        => l_exec_id,
        p_status         => c_exec_completed,
        p_output_result  => l_result,
        p_input_tokens   => l_input_tokens,
        p_output_tokens  => l_output_tokens
      );

      -- Persist this turn's messages and refresh the conversation header
      -- (top-level only; nested sub-agent runs are captured via their parent
      -- turn's result). Message persistence runs before maintain_session so the
      -- header's message_count includes the messages just written.
      if l_is_top_level then
        persist_turn_messages(l_exec_id, l_session_id, l_result);
        maintain_session(l_session_id, c_exec_completed);
      end if;

      -- Fire the post-execution hook (top-level only); best-effort, never raises.
      if l_is_top_level then
        fire_after_hook(l_exec_id, c_exec_completed, l_input_tokens, l_output_tokens);
      end if;

    exception
      when others then
        -- Update execution as failed
        complete_execution(
          p_exec_id       => l_exec_id,
          p_status        => c_exec_failed,
          p_error_message => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );

        -- Refresh the conversation header to reflect the failed turn (top-level
        -- only). No messages are persisted: the turn produced no usable result.
        if l_is_top_level then
          maintain_session(l_session_id, c_exec_failed);
        end if;

        -- Fire the post-execution hook for the failed run (top-level only).
        if l_is_top_level then
          fire_after_hook(l_exec_id, c_exec_failed, l_input_tokens, l_output_tokens);
        end if;

        -- Restore the caller's execution context before unwinding.
        uc_ai.set_exec_context(l_prev_ctx);
        raise;
    end;

    -- Restore the caller's execution context (nested runs) / clear it (top level).
    uc_ai.set_exec_context(l_prev_ctx);
    g_exec_depth := g_exec_depth - 1;
    return l_result;
  exception
    when others then
      g_exec_depth := greatest(g_exec_depth - 1, 0);
      uc_ai_logger.log_error('Error executing agent: ' || p_agent_code, l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_agent;


  /*
   * Executes an agent by ID
   */
  function execute_agent(
    p_agent_id          in uc_ai_agents.id%type,
    p_input_parameters  in json_object_t default null,
    p_follow_up_message in clob default null,
    p_session_id        in varchar2 default null,
    p_parent_exec_id    in uc_ai_agent_executions.id%type default null,
    p_response_schema   in json_object_t default null,
    p_files             in uc_ai_message_api.t_files default null,
    p_extra_tool_tag    in varchar2 default null
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'execute_agent';
    l_agent uc_ai_agents%rowtype;
  begin
    l_agent := get_agent(p_agent_id);

    return execute_agent(
      p_agent_code        => l_agent.code,
      p_agent_version     => l_agent.version,
      p_input_parameters  => p_input_parameters,
      p_follow_up_message => p_follow_up_message,
      p_session_id        => p_session_id,
      p_parent_exec_id    => p_parent_exec_id,
      p_response_schema   => p_response_schema,
      p_files             => p_files,
      p_extra_tool_tag    => p_extra_tool_tag
    );
  exception
    when others then
      uc_ai_logger.log_error('Error executing agent by ID', l_scope);
      raise;
  end execute_agent;


  /*
   * Gets the execution history with optional filters
   */
  function get_execution_history(
    p_session_id in varchar2 default null,
    p_agent_code in uc_ai_agents.code%type default null,
    p_status     in varchar2 default null,
    p_start_date in timestamp default null,
    p_end_date   in timestamp default null
  ) return sys_refcursor
  as
    l_scope            uc_ai_logger.scope := gc_scope_prefix || 'get_execution_history';
    l_exec_history_cur sys_refcursor;
  begin
    open l_exec_history_cur for
      select e.id,
             e.agent_id,
             a.code as agent_code,
             a.version as agent_version,
             a.agent_type,
             e.parent_execution_id,
             e.session_id,
             e.status,
             e.iteration_count,
             e.tool_calls_count,
             e.total_input_tokens,
             e.total_output_tokens,
             e.started_at,
             e.completed_at,
             e.error_message,
             e.created_by
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
      where (p_session_id is null or e.session_id = p_session_id)
        and (p_agent_code is null or a.code = p_agent_code)
        and (p_status is null or e.status = p_status)
        and (p_start_date is null or e.started_at >= p_start_date)
        and (p_end_date is null or e.started_at <= p_end_date)
      order by e.started_at desc;
    
    return l_exec_history_cur;
  exception
    when others then
      uc_ai_logger.log_error('Error getting execution history', l_scope);
      raise;
  end get_execution_history;


  /*
   * Gets detailed information about a specific execution
   */
  function get_execution_details(
    p_execution_id in uc_ai_agent_executions.id%type
  ) return json_object_t
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'get_execution_details';
    l_result json_object_t := json_object_t();
    l_exec   uc_ai_agent_executions%rowtype;
    l_agent  uc_ai_agents%rowtype;
  begin
    select *
    into l_exec
    from uc_ai_agent_executions
    where id = p_execution_id;
    
    select *
    into l_agent
    from uc_ai_agents
    where id = l_exec.agent_id;
    
    l_result.put('execution_id', l_exec.id);
    l_result.put('agent_id', l_exec.agent_id);
    l_result.put('agent_code', l_agent.code);
    l_result.put('agent_version', l_agent.version);
    l_result.put('agent_type', l_agent.agent_type);
    l_result.put('parent_execution_id', l_exec.parent_execution_id);
    l_result.put('session_id', l_exec.session_id);
    l_result.put('status', l_exec.status);
    l_result.put('iteration_count', l_exec.iteration_count);
    l_result.put('tool_calls_count', l_exec.tool_calls_count);
    l_result.put('total_input_tokens', l_exec.total_input_tokens);
    l_result.put('total_output_tokens', l_exec.total_output_tokens);
    l_result.put('started_at', to_char(l_exec.started_at, 'YYYY-MM-DD"T"HH24:MI:SS'));
    l_result.put('completed_at', to_char(l_exec.completed_at, 'YYYY-MM-DD"T"HH24:MI:SS'));
    l_result.put('error_message', l_exec.error_message);
    l_result.put('created_by', l_exec.created_by);
    l_result.put('db_user', l_exec.db_user);
    l_result.put('apex_user', l_exec.apex_user);
    l_result.put('apex_app_id', l_exec.apex_app_id);
    l_result.put('apex_page_id', l_exec.apex_page_id);
    l_result.put('module', l_exec.module);
    l_result.put('client_identifier', l_exec.client_identifier);

    if l_exec.env_context is not null then
      l_result.put('env_context', json_object_t.parse(l_exec.env_context));
    end if;

    if l_exec.input_parameters is not null then
      l_result.put('input_parameters', json_object_t.parse(l_exec.input_parameters));
    end if;
    
    if l_exec.output_result is not null then
      l_result.put('output_result', json_object_t.parse(l_exec.output_result));
    end if;

    if l_exec.current_state is not null then
      l_result.put('current_state', json_object_t.parse(l_exec.current_state));
    end if;

    return l_result;
  exception
    when no_data_found then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_not_found
      , p_scope      => l_scope
      , p0           => 'Execution'
      , p1           => p_execution_id
      );
    when others then
      uc_ai_logger.log_error('Error getting execution details', l_scope);
      raise;
  end get_execution_details;


  /*
   * Lists conversation sessions (one row per session_id) with maintained
   * aggregates. This is the conversation-level counterpart to
   * get_execution_history, which drills down into the individual turns and
   * nested sub-agent runs of a session.
   */
  function list_sessions(
    p_agent_code in uc_ai_agents.code%type default null,
    p_status     in varchar2 default null,
    p_created_by in varchar2 default null,
    p_start_date in timestamp default null,
    p_end_date   in timestamp default null
  ) return sys_refcursor
  as
    l_scope    uc_ai_logger.scope := gc_scope_prefix || 'list_sessions';
    l_cur      sys_refcursor;
  begin
    open l_cur for
      select s.session_id,
             s.root_agent_id,
             a.code as agent_code,
             a.version as agent_version,
             a.agent_type,
             s.status,
             s.turn_count,
             s.message_count,
             s.total_input_tokens,
             s.total_output_tokens,
             s.started_at,
             s.last_activity_at,
             s.created_by
      from uc_ai_agent_sessions s
      left join uc_ai_agents a on a.id = s.root_agent_id
      where (p_agent_code is null or a.code = p_agent_code)
        and (p_status is null or s.status = p_status)
        and (p_created_by is null or s.created_by = p_created_by)
        and (p_start_date is null or s.started_at >= p_start_date)
        and (p_end_date is null or s.started_at <= p_end_date)
      order by s.last_activity_at desc;

    return l_cur;
  exception
    when others then
      uc_ai_logger.log_error('Error listing sessions', l_scope);
      raise;
  end list_sessions;


  /*
   * Returns the full, untrimmed message log of a session in conversation order.
   */
  function get_session_messages(
    p_session_id in varchar2
  ) return sys_refcursor
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_session_messages';
    l_cur   sys_refcursor;
  begin
    open l_cur for
      select m.id,
             m.session_id,
             m.execution_id,
             m.seq,
             m.role,
             m.content,
             m.tool_name,
             m.tool_input,
             m.tool_output,
             m.tool_status,
             m.input_tokens,
             m.output_tokens,
             m.created_at
      from uc_ai_agent_messages m
      where m.session_id = p_session_id
      order by m.seq;

    return l_cur;
  exception
    when others then
      uc_ai_logger.log_error('Error getting session messages', l_scope);
      raise;
  end get_session_messages;

end uc_ai_agents_api;
/
