create or replace package body test_uc_ai_agent_purge as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-5080): three tests assert THAT an error is raised; sqlerrm is the assertion and a backtrace would only add noise to the test log

  gc_main_code   constant varchar2(50 char) := 'TEST_PURGE_MAIN';
  gc_sub_code    constant varchar2(50 char) := 'TEST_PURGE_SUB';
  gc_keep_code   constant varchar2(50 char) := 'TEST_PURGE_KEEP';
  gc_orch_code   constant varchar2(50 char) := 'TEST_PURGE_ORCH';
  gc_del_code    constant varchar2(50 char) := 'TEST_PURGE_DELEGATE';

  gc_sub_tool    constant varchar2(50 char) := 'TEST_PURGE_SUB_TOOL';
  gc_tool_tag    constant varchar2(50 char) := 'test_purge';
  gc_profile     constant varchar2(50 char) := 'TEST_PURGE_PROFILE';

  -- a one-step workflow that answers from its input, no model call
  gc_echo_def constant varchar2(600 char) := q'#{
    "workflow_type": "sequential",
    "steps": [
      {
        "step_type": "plsql",
        "plsql_function_call": "return 'ok';",
        "output_key": "answer"
      }
    ]
  }#';


  procedure delete_tool(p_code in varchar2)
  as
  begin
    delete from uc_ai_tools where code = p_code;
    commit;
  end delete_tool;


  procedure drop_test_data
  as
  begin
    -- purge_agent is the thing under test, so the fixtures are removed with the
    -- shared cascade helper instead
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_PURGE%');

    -- Every store this suite makes carries "test_purge" somewhere in its key,
    -- including the shared and global ones a purge is supposed to KEEP. The
    -- files go with the store through the foreign key.
    delete from uc_ai_memory_stores
     where lower(store_key) like '%test\_purge%' escape '\';

    delete from uc_ai_memory_config
     where agent_code like 'TEST\_PURGE%' escape '\';

    delete_tool(gc_sub_tool);

    -- by row: delete_prompt_profile needs a version, and the profile is only a
    -- fixture here
    delete from uc_ai_prompt_profiles
     where code like 'TEST\_PURGE%' escape '\';
    commit;
  end drop_test_data;


  procedure create_workflow(
    p_code    in varchar2,
    p_def     in clob default null,
    p_version in number default 1,
    p_status  in varchar2 default uc_ai_agents_api.c_status_active
  )
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Purge test agent ' || p_code,
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => coalesce(p_def, gc_echo_def),
      p_version             => p_version,
      p_status              => p_status
    );
    commit; -- agents must be committed before execution (autonomous telemetry)
    ut.expect(l_id).to_be_not_null();
  end create_workflow;


  -- One memory store with one file in it, written directly: the suite asserts
  -- which rows a purge takes, not how the memory tool fills them.
  procedure make_store(
    p_store_key in varchar2,
    p_scope     in varchar2,
    p_agent     in varchar2 default null,
    p_session   in varchar2 default null
  )
  as
    l_id number;
  begin
    insert into uc_ai_memory_stores (store_key, scope, agent_code, session_id)
      values (p_store_key, p_scope, p_agent, p_session)
      returning id into l_id;

    insert into uc_ai_memory_files (store_id, path, content)
      values (l_id, '/memories/notes.md', 'content of ' || p_store_key);
    commit;
  end make_store;


  function store_exists(p_store_key in varchar2) return boolean
  as
    l_dummy pls_integer;
  begin
    select 1
      into l_dummy
      from uc_ai_memory_stores
     where store_key = p_store_key
       and rownum = 1;
    return true;
  exception
    when no_data_found then
      return false;
  end store_exists;


  function agent_rows(p_code in varchar2) return pls_integer
  as
    l_count pls_integer;
  begin
    select count(*) into l_count from uc_ai_agents where code = p_code;
    return l_count;
  end agent_rows;


  function exec_rows(p_code in varchar2) return pls_integer
  as
    l_count pls_integer;
  begin
    select count(*)
      into l_count
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
     where a.code = p_code;
    return l_count;
  end exec_rows;


  procedure setup
  as
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    drop_test_data;
  end setup;


  procedure teardown
  as
  begin
    drop_test_data;
  end teardown;


  procedure delete_agent_keeps_history
  as
    l_result json_object_t;
    l_raised boolean := false;
  begin
    create_workflow(gc_main_code);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_main_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => uc_ai_agents_api.generate_session_id
    );
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    begin
      uc_ai_agents_api.delete_agent(p_code => gc_main_code, p_version => 1);
      commit;
    exception
      when others then
        l_raised := true;
        sys.dbms_output.put_line('delete_agent_keeps_history: ' || sqlerrm);
    end;

    -- the definition cannot go while its history points at it
    ut.expect(l_raised).to_be_true();
    ut.expect(agent_rows(gc_main_code)).to_equal(1);

    uc_ai_agents_api.purge_agent(gc_main_code);
    commit;
  end delete_agent_keeps_history;


  procedure purge_removes_history
  as
    l_result     json_object_t;
    l_session_id varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_sessions   pls_integer;
    l_messages   pls_integer;
  begin
    create_workflow(gc_main_code);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_main_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => l_session_id
    );
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(exec_rows(gc_main_code)).to_be_greater_than(0);

    uc_ai_agents_api.purge_agent(gc_main_code);
    commit;

    ut.expect(agent_rows(gc_main_code)).to_equal(0);
    ut.expect(exec_rows(gc_main_code)).to_equal(0);

    select count(*) into l_sessions
      from uc_ai_agent_sessions where session_id = l_session_id;
    ut.expect(l_sessions).to_equal(0);

    select count(*) into l_messages
      from uc_ai_agent_messages where session_id = l_session_id;
    ut.expect(l_messages).to_equal(0);
  end purge_removes_history;


  procedure purge_removes_all_versions
  as
  begin
    create_workflow(gc_main_code, p_version => 1, p_status => uc_ai_agents_api.c_status_archived);
    create_workflow(gc_main_code, p_version => 2);

    ut.expect(agent_rows(gc_main_code)).to_equal(2);

    uc_ai_agents_api.purge_agent(gc_main_code);
    commit;

    ut.expect(agent_rows(gc_main_code)).to_equal(0);
  end purge_removes_all_versions;


  procedure purge_removes_nested_runs
  as
    l_result     json_object_t;
    l_session_id varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_id         number;
  begin
    -- the sub-agent is a separate agent; its run hangs under the run of the
    -- caller, so purging the caller has to take it too
    create_workflow(gc_sub_code);

    l_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => gc_sub_tool,
      p_description   => 'Runs the sub-agent',
      p_function_call => 'return uc_ai_agents_api.run_agent_as_tool(''' || gc_sub_code || ''', :parameters);',
      p_json_schema   => json_object_t('{"type":"object","properties":{}}'),
      p_tags          => apex_t_varchar2(gc_tool_tag)
    );
    commit;

    create_workflow(gc_main_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return uc_ai_tools_api.execute_tool('TEST_PURGE_SUB_TOOL', json_object_t('{}'));",
          "output_key": "delegated"
        }
      ]
    }#');

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_main_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => l_session_id
    );
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(exec_rows(gc_sub_code)).to_be_greater_than(0);

    uc_ai_agents_api.purge_agent(gc_main_code);
    commit;

    -- the run of the sub-agent went with the run that started it
    ut.expect(exec_rows(gc_sub_code)).to_equal(0);
    -- the sub-agent itself stays: it is an agent of its own
    ut.expect(agent_rows(gc_sub_code)).to_equal(1);

    uc_ai_agents_api.purge_agent(gc_sub_code);
    commit;
  end purge_removes_nested_runs;


  procedure purge_removes_own_memory
  as
    l_session_id varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_result     json_object_t;
    l_config     pls_integer;
    l_files      pls_integer;
  begin
    create_workflow(gc_main_code);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_main_code,
      p_input_parameters => json_object_t('{}'),
      p_session_id       => l_session_id
    );
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    make_store('agent:' || gc_main_code, 'agent', gc_main_code);
    make_store('user:' || gc_main_code || ':SOMEUSER', 'user', gc_main_code);
    make_store('context:' || gc_main_code || ':document_id:7', 'context', gc_main_code);
    make_store('session:' || l_session_id, 'session', null, l_session_id);

    insert into uc_ai_memory_config (agent_code, scope) values (gc_main_code, 'agent');
    commit;

    uc_ai_agents_api.purge_agent(gc_main_code);
    commit;

    ut.expect(store_exists('agent:' || gc_main_code)).to_be_false();
    ut.expect(store_exists('user:' || gc_main_code || ':SOMEUSER')).to_be_false();
    ut.expect(store_exists('context:' || gc_main_code || ':document_id:7')).to_be_false();
    ut.expect(store_exists('session:' || l_session_id)).to_be_false();

    select count(*) into l_config from uc_ai_memory_config where agent_code = gc_main_code;
    ut.expect(l_config).to_equal(0);

    -- the files went with their stores
    select count(*) into l_files
      from uc_ai_memory_files f
     where f.content like '%' || gc_main_code || '%';
    ut.expect(l_files).to_equal(0);
  end purge_removes_own_memory;


  procedure purge_keeps_shared_memory
  as
  begin
    create_workflow(gc_main_code);

    -- these three do not belong to one agent
    make_store('shared:test_purge_kb', 'shared', gc_main_code);
    make_store('test_purge_global_probe', 'global');
    -- a context store under a namespace that store_code shares between agents
    make_store('context:test_purge_ns:document_id:7', 'context', gc_main_code);

    uc_ai_agents_api.purge_agent(gc_main_code);
    commit;

    ut.expect(agent_rows(gc_main_code)).to_equal(0);
    ut.expect(store_exists('shared:test_purge_kb')).to_be_true();
    ut.expect(store_exists('test_purge_global_probe')).to_be_true();
    ut.expect(store_exists('context:test_purge_ns:document_id:7')).to_be_true();
  end purge_keeps_shared_memory;


  procedure purge_keeps_prompt_profile
  as
    l_id      number;
    l_profile pls_integer;
  begin
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => gc_profile,
      p_description            => 'Purge test profile',
      p_system_prompt_template => 'You answer questions.',
      p_user_prompt_template   => '{prompt}',
      p_provider               => uc_ai.c_provider_openai,
      p_model                  => uc_ai_openai.c_model_gpt_4o_mini,
      p_status                 => uc_ai_prompt_profiles_api.c_status_active
    );
    commit;

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_keep_code,
      p_description         => 'Profile agent for the purge test',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_profile,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    uc_ai_agents_api.purge_agent(gc_keep_code);
    commit;

    ut.expect(agent_rows(gc_keep_code)).to_equal(0);

    -- a profile lives without an agent, and other agents can use it
    select count(*) into l_profile
      from uc_ai_prompt_profiles where code = gc_profile;
    ut.expect(l_profile).to_be_greater_than(0);
  end purge_keeps_prompt_profile;


  procedure purge_refuses_referenced_agent
  as
    l_id     number;
    l_raised boolean := false;
  begin
    create_workflow(gc_del_code);

    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_orch_code,
      p_description          => 'Orchestrator that delegates',
      p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
      p_orchestration_config => '{"pattern_type": "orchestrator",'
                             || ' "orchestrator_profile_code": "' || gc_profile || '",'
                             || ' "delegate_agents": ["' || gc_del_code || '"],'
                             || ' "max_delegations": 3}',
      p_status               => uc_ai_agents_api.c_status_draft
    );
    commit;

    begin
      uc_ai_agents_api.purge_agent(gc_del_code);
      commit;
    exception
      when others then
        l_raised := true;
        sys.dbms_output.put_line('purge_refuses_referenced_agent: ' || sqlerrm);
    end;

    -- purging it would leave the orchestrator pointing at nothing
    ut.expect(l_raised).to_be_true();
    ut.expect(agent_rows(gc_del_code)).to_equal(1);
  end purge_refuses_referenced_agent;


  procedure purge_unknown_agent_raises
  as
    l_raised boolean := false;
  begin
    begin
      uc_ai_agents_api.purge_agent('TEST_PURGE_NOT_THERE');
    exception
      when others then
        l_raised := true;
        sys.dbms_output.put_line('purge_unknown_agent_raises: ' || sqlerrm);
    end;

    ut.expect(l_raised).to_be_true();
  end purge_unknown_agent_raises;

end test_uc_ai_agent_purge;
/
