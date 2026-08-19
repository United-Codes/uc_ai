create or replace package body test_uc_ai_hook as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages

  gc_agent_code   constant varchar2(50 char) := 'TEST_HOOK_AGENT';
  -- deliberately references a prompt profile that is never created, so
  -- execution fails in prepare_profile_context before any generate_text call
  gc_missing_prof constant varchar2(50 char) := 'TEST_HOOK_NO_SUCH_PROFILE';
  gc_stub_pkg     constant varchar2(50 char) := 'TEST_UC_AI_HOOK_STUB';


  procedure delete_test_rows
  as
  begin
    delete from uc_ai_agent_messages
     where execution_id in (
       select id from uc_ai_agent_executions
        where agent_id in (select id from uc_ai_agents where code like 'TEST_HOOK_%'))
        or session_id in (
       select session_id from uc_ai_agent_sessions
        where root_agent_id in (select id from uc_ai_agents where code like 'TEST_HOOK_%'));
    delete from uc_ai_agent_executions
     where agent_id in (select id from uc_ai_agents where code like 'TEST_HOOK_%');
    delete from uc_ai_agent_sessions
     where root_agent_id in (select id from uc_ai_agents where code like 'TEST_HOOK_%');
    delete from uc_ai_agents where code like 'TEST_HOOK_%';
    commit;
  end delete_test_rows;


  function agent_exec_count return pls_integer
  as
    l_count pls_integer;
  begin
    select count(*)
      into l_count
      from uc_ai_agent_executions
     where agent_id in (select id from uc_ai_agents where code = gc_agent_code);
    return l_count;
  end agent_exec_count;


  procedure setup
  as
    l_id number;
  begin
    delete_test_rows;

    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_agent_code,
      p_description         => 'Hook test profile agent (dangling profile)',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_missing_prof,
      p_status              => uc_ai_agents_api.c_status_active
    );

    commit;
  end setup;


  procedure teardown
  as
  begin
    uc_ai_agents_api.set_execution_hook(null);
    delete_test_rows;
    uc_ai.reset_globals;
  end teardown;


  procedure before_each
  as
  begin
    test_uc_ai_hook_stub.reset;
    uc_ai_agents_api.set_execution_hook(null);
    -- start from a clean execution history for row-count assertions
    delete from uc_ai_agent_messages
     where execution_id in (
       select id from uc_ai_agent_executions
        where agent_id in (select id from uc_ai_agents where code = gc_agent_code));
    delete from uc_ai_agent_executions
     where agent_id in (select id from uc_ai_agents where code = gc_agent_code);
    delete from uc_ai_agent_sessions
     where root_agent_id in (select id from uc_ai_agents where code = gc_agent_code);
    commit;
  end before_each;


  procedure after_each
  as
  begin
    uc_ai_agents_api.set_execution_hook(null);
  end after_each;


  procedure veto_blocks_execution
  as
    l_res    json_object_t;
    l_before pls_integer;
  begin
    l_before := agent_exec_count;
    test_uc_ai_hook_stub.g_before_raise := true;
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    begin
      l_res := uc_ai_agents_api.execute_agent(p_agent_code => gc_agent_code);
      ut.fail('Expected the hook veto to abort execution');
    exception
      when others then
        ut.expect(sqlcode).to_equal(test_uc_ai_hook_stub.c_before_veto_code);
    end;

    ut.expect(test_uc_ai_hook_stub.g_before_count).to_equal(1);
    -- after must NOT fire: veto happened before the run started
    ut.expect(test_uc_ai_hook_stub.g_after_count).to_equal(0);
    -- and no execution row may have been created
    ut.expect(agent_exec_count).to_equal(l_before);
  end veto_blocks_execution;


  procedure before_receives_context
  as
    l_res json_object_t;
  begin
    test_uc_ai_hook_stub.g_before_raise := true;
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    begin
      l_res := uc_ai_agents_api.execute_agent(p_agent_code => gc_agent_code);
      ut.fail('Expected the hook veto to abort execution');
    exception
      when others then
        null;
    end;

    ut.expect(test_uc_ai_hook_stub.g_last_agent_code).to_equal(gc_agent_code);
    ut.expect(test_uc_ai_hook_stub.g_last_agent_id).to_be_not_null();
    ut.expect(test_uc_ai_hook_stub.g_last_created_by).to_be_not_null();
    ut.expect(test_uc_ai_hook_stub.g_last_session_id).to_be_not_null();
  end before_receives_context;


  procedure after_fires_on_failure
  as
    l_res json_object_t;
  begin
    -- before passes; the run then fails in prepare_profile_context (pre-LLM)
    test_uc_ai_hook_stub.g_before_raise := false;
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    begin
      l_res := uc_ai_agents_api.execute_agent(p_agent_code => gc_agent_code);
      ut.fail('Expected a pre-LLM failure (missing prompt profile)');
    exception
      when others then
        -- not the veto and not the after-hook error
        ut.expect(sqlcode = test_uc_ai_hook_stub.c_before_veto_code).to_be_false();
        ut.expect(sqlcode = test_uc_ai_hook_stub.c_after_fail_code).to_be_false();
    end;

    ut.expect(test_uc_ai_hook_stub.g_before_count).to_equal(1);
    ut.expect(test_uc_ai_hook_stub.g_after_count).to_equal(1);
    ut.expect(test_uc_ai_hook_stub.g_last_status).to_equal(uc_ai_agents_api.c_exec_failed);
    ut.expect(test_uc_ai_hook_stub.g_last_exec_id).to_be_not_null();
  end after_fires_on_failure;


  procedure after_error_is_swallowed
  as
    l_res json_object_t;
  begin
    test_uc_ai_hook_stub.g_before_raise := false;
    test_uc_ai_hook_stub.g_after_raise  := true;
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    begin
      l_res := uc_ai_agents_api.execute_agent(p_agent_code => gc_agent_code);
      ut.fail('Expected a pre-LLM failure (missing prompt profile)');
    exception
      when others then
        -- the run's own failure propagates; the after-hook error is swallowed
        ut.expect(sqlcode = test_uc_ai_hook_stub.c_after_fail_code).to_be_false();
    end;

    -- after_execution was still invoked (and raised internally, but swallowed)
    ut.expect(test_uc_ai_hook_stub.g_after_count).to_equal(1);
  end after_error_is_swallowed;


  procedure cleared_hook_not_called
  as
    l_res json_object_t;
  begin
    -- register then clear the override; the hook must no longer be dispatched
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);
    uc_ai_agents_api.set_execution_hook(null);
    test_uc_ai_hook_stub.g_before_raise := true;  -- would veto IF it were called

    begin
      l_res := uc_ai_agents_api.execute_agent(p_agent_code => gc_agent_code);
      ut.fail('Expected a pre-LLM failure (missing prompt profile)');
    exception
      when others then
        -- must NOT be our stub's veto
        ut.expect(sqlcode = test_uc_ai_hook_stub.c_before_veto_code).to_be_false();
    end;

    ut.expect(test_uc_ai_hook_stub.g_before_count).to_equal(0);
    ut.expect(test_uc_ai_hook_stub.g_after_count).to_equal(0);
  end cleared_hook_not_called;


  -- Builds a settings record carrying the given execution context, as the agent
  -- layer would publish it, for driving before_tool_call without an LLM call.
  function tool_settings(
    p_agent_code in varchar2,
    p_created_by in varchar2
  ) return uc_ai_settings.t_settings
  as
    l_s uc_ai_settings.t_settings;
  begin
    l_s.ctx_agent_id   := 42;
    l_s.ctx_agent_code := p_agent_code;
    l_s.ctx_created_by := p_created_by;
    l_s.ctx_session_id := 'SESS-1';
    return l_s;
  end tool_settings;


  procedure tool_hook_fires_with_context
  as
  begin
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    uc_ai_tools_api.before_tool_call(
      p_tool_code => 'GET_WEATHER'
    , p_settings  => tool_settings('WEATHER_AGENT', 'alice')
    );

    ut.expect(test_uc_ai_hook_stub.g_tool_count).to_equal(1);
    ut.expect(test_uc_ai_hook_stub.g_last_tool_code).to_equal('GET_WEATHER');
    ut.expect(test_uc_ai_hook_stub.g_last_tool_agent).to_equal('WEATHER_AGENT');
    ut.expect(test_uc_ai_hook_stub.g_last_tool_user).to_equal('alice');
  end tool_hook_fires_with_context;


  procedure tool_hook_veto_raises
  as
  begin
    test_uc_ai_hook_stub.g_tool_raise := true;
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    begin
      uc_ai_tools_api.before_tool_call(
        p_tool_code => 'GET_WEATHER'
      , p_settings  => tool_settings('WEATHER_AGENT', 'alice')
      );
      ut.fail('Expected the tool hook veto to raise');
    exception
      when others then
        ut.expect(sqlcode).to_equal(test_uc_ai_hook_stub.c_tool_veto_code);
    end;

    ut.expect(test_uc_ai_hook_stub.g_tool_count).to_equal(1);
  end tool_hook_veto_raises;


  procedure tool_hook_optional_when_absent
  as
  begin
    -- Point the hook at a valid package that does NOT implement before_tool_call.
    -- The existence probe must skip it silently rather than raising.
    uc_ai_agents_api.set_execution_hook('UC_AI');
    test_uc_ai_hook_stub.g_tool_raise := true;  -- would veto IF the stub were called

    uc_ai_tools_api.before_tool_call(
      p_tool_code => 'GET_WEATHER'
    , p_settings  => tool_settings('WEATHER_AGENT', 'alice')
    );

    ut.expect(test_uc_ai_hook_stub.g_tool_count).to_equal(0);
  end tool_hook_optional_when_absent;


  procedure prompt_hook_appends
  as
    l_prompt clob := 'You are a helpful assistant.';
  begin
    test_uc_ai_hook_stub.g_prompt_append := ' MEMORY PROTOCOL BLOCK';
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    uc_ai_agents_api.fire_augment_prompt_hook(l_prompt);

    ut.expect(test_uc_ai_hook_stub.g_prompt_count).to_equal(1);
    -- the stub received the original prompt and its change was applied
    ut.expect(dbms_lob.substr(test_uc_ai_hook_stub.g_last_prompt_in, 4000, 1))
      .to_equal('You are a helpful assistant.');
    ut.expect(dbms_lob.substr(l_prompt, 4000, 1))
      .to_equal('You are a helpful assistant. MEMORY PROTOCOL BLOCK');
  end prompt_hook_appends;


  procedure prompt_hook_on_null_prompt
  as
    l_prompt clob;
  begin
    test_uc_ai_hook_stub.g_prompt_append := 'INJECTED PROMPT';
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    uc_ai_agents_api.fire_augment_prompt_hook(l_prompt);

    ut.expect(test_uc_ai_hook_stub.g_prompt_count).to_equal(1);
    ut.expect(dbms_lob.substr(l_prompt, 4000, 1)).to_equal('INJECTED PROMPT');
  end prompt_hook_on_null_prompt;


  procedure prompt_hook_error_swallowed
  as
    l_prompt clob := 'ORIGINAL PROMPT';
  begin
    -- the stub mutates the prompt and THEN raises; the dispatcher must swallow
    -- the error and leave the caller's prompt untouched
    test_uc_ai_hook_stub.g_prompt_append := ' HALF-APPLIED CHANGE';
    test_uc_ai_hook_stub.g_prompt_raise  := true;
    uc_ai_agents_api.set_execution_hook(gc_stub_pkg);

    uc_ai_agents_api.fire_augment_prompt_hook(l_prompt);

    ut.expect(test_uc_ai_hook_stub.g_prompt_count).to_equal(1);
    ut.expect(dbms_lob.substr(l_prompt, 4000, 1)).to_equal('ORIGINAL PROMPT');
  end prompt_hook_error_swallowed;


  procedure prompt_hook_optional_when_absent
  as
    l_prompt clob := 'ORIGINAL PROMPT';
  begin
    -- Point the hook at a valid package that does NOT implement
    -- augment_system_prompt. The existence probe must skip it silently.
    uc_ai_agents_api.set_execution_hook('UC_AI');
    test_uc_ai_hook_stub.g_prompt_append := 'WOULD APPEND';  -- IF the stub were called

    uc_ai_agents_api.fire_augment_prompt_hook(l_prompt);

    ut.expect(test_uc_ai_hook_stub.g_prompt_count).to_equal(0);
    ut.expect(dbms_lob.substr(l_prompt, 4000, 1)).to_equal('ORIGINAL PROMPT');
  end prompt_hook_optional_when_absent;

end test_uc_ai_hook;
/
