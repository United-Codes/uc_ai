create or replace package body test_uc_ai_memory as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages

  gc_prof    constant varchar2(50 char) := 'TEST_MEM_PROFILE';
  gc_agent_a constant varchar2(50 char) := 'TEST_MEM_AGENT_A';
  gc_agent_b constant varchar2(50 char) := 'TEST_MEM_AGENT_B';
  gc_shared  constant varchar2(50 char) := 'TEST_MEM_SHARED';


  -- ==========================================================================
  -- Helpers
  -- ==========================================================================

  function run(p_json in varchar2) return clob
  as
  begin
    return uc_ai_memory.execute_command(json_object_t.parse(p_json));
  end run;


  function run_txt(p_json in varchar2) return varchar2
  as
  begin
    return sys.dbms_lob.substr(run(p_json), 4000, 1);
  end run_txt;


  -- Drives the tool the way a provider does: the registered function_call of the
  -- MEMORY row, with the arguments bound as one CLOB by the tool layer.
  function run_tool(p_json in varchar2) return varchar2
  as
    l_args json_object_t;
  begin
    if p_json is not null then
      l_args := json_object_t.parse(p_json);
    end if;

    return sys.dbms_lob.substr(
      uc_ai_tools_api.execute_tool(
        p_tool_code => uc_ai_memory.c_tool_code
      , p_arguments => l_args
      )
    , 4000, 1);
  end run_tool;


  procedure set_ctx(
    p_agent       in varchar2,
    p_user        in varchar2 default 'TEST_MEM_USER',
    p_session     in varchar2 default 'TEST_MEM_SESSION_1',
    p_run_context in clob default null
  )
  as
    l_ctx uc_ai.t_exec_context;
  begin
    l_ctx.agent_id    := 1;
    l_ctx.agent_code  := p_agent;
    l_ctx.created_by  := p_user;
    l_ctx.session_id  := p_session;
    l_ctx.run_context := p_run_context;
    uc_ai.set_exec_context(l_ctx);
  end set_ctx;


  -- Binds the agent to a document, as a "talk to this document" run would.
  procedure set_doc_ctx(
    p_agent in varchar2,
    p_doc   in varchar2
  )
  as
  begin
    set_ctx(p_agent, p_run_context => '{"document_id": "' || p_doc || '"}');
  end set_doc_ctx;


  function doc_key(
    p_namespace in varchar2,
    p_doc       in varchar2
  ) return varchar2
  as
  begin
    return 'context:' || p_namespace || ':document_id:' || p_doc;
  end doc_key;


  procedure enable_a(
    p_scope           in varchar2 default uc_ai_memory.c_scope_agent,
    p_store_code      in varchar2 default null,
    p_max_file_chars  in number default null,
    p_max_files       in number default null,
    p_context_key     in varchar2 default null
  )
  as
  begin
    uc_ai_memory.enable_for_agent(
      p_agent_code     => gc_agent_a,
      p_scope          => p_scope,
      p_store_code     => p_store_code,
      p_context_key    => p_context_key,
      p_update_profile => false,
      p_max_file_chars => p_max_file_chars,
      p_max_files      => p_max_files
    );
  end enable_a;


  function store_count(p_key in varchar2) return pls_integer
  as
    l_count pls_integer;
  begin
    select count(*) into l_count from uc_ai_memory_stores where store_key = p_key;
    return l_count;
  end store_count;


  function file_count(p_key in varchar2) return pls_integer
  as
    l_count pls_integer;
  begin
    select count(*)
      into l_count
      from uc_ai_memory_files f
      join uc_ai_memory_stores s on s.id = f.store_id
     where s.store_key = p_key;
    return l_count;
  end file_count;


  function profile_config return json_object_t
  as
    l_json uc_ai_prompt_profiles.model_config_json%type;
  begin
    select model_config_json
      into l_json
      from uc_ai_prompt_profiles
     where code = gc_prof;
    return json_object_t.parse(coalesce(l_json, '{}'));
  end profile_config;


  function profile_has_memory_tag return boolean
  as
    l_config json_object_t := profile_config();
    l_tags   json_array_t;
  begin
    if not l_config.has('g_tool_tags') then
      return false;
    end if;
    l_tags := l_config.get_array('g_tool_tags');
    <<tag_loop>>
    for i in 0 .. l_tags.get_size - 1 loop
      if l_tags.get_string(i) = uc_ai_memory.c_tool_tag then
        return true;
      end if;
    end loop tag_loop;
    return false;
  end profile_has_memory_tag;


  procedure delete_test_rows
  as
  begin
    delete from uc_ai_memory_files
     where store_id in (select s.id from uc_ai_memory_stores s where s.store_key like '%TEST_MEM%');
    -- global-store leftovers of the global-scope test
    delete from uc_ai_memory_files where path like '/memories/test_mem_%';
    delete from uc_ai_memory_stores where store_key like '%TEST_MEM%';
    delete from uc_ai_memory_config where agent_code like 'TEST_MEM%';
    delete from uc_ai_agents where code like 'TEST_MEM%';
    delete from uc_ai_prompt_profiles where code = gc_prof;
    commit;
  end delete_test_rows;


  -- ==========================================================================
  -- Fixture
  -- ==========================================================================

  procedure setup
  as
    l_id number;
  begin
    delete_test_rows;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => gc_prof,
      p_description            => 'Memory feature test profile',
      p_system_prompt_template => 'You are a test assistant.',
      p_user_prompt_template   => 'Say hi.',
      p_provider               => uc_ai.c_provider_openai,
      p_model                  => 'gpt-test',
      p_status                 => uc_ai_prompt_profiles_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_agent_a,
      p_description         => 'Memory test agent A',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_prof,
      p_status              => uc_ai_agents_api.c_status_active
    );
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_agent_b,
      p_description         => 'Memory test agent B (shares the profile)',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_prof,
      p_status              => uc_ai_agents_api.c_status_active
    );

    commit;
  end setup;


  procedure teardown
  as
  begin
    uc_ai.clear_exec_context;
    uc_ai_memory.clear_store;
    delete_test_rows;
  end teardown;


  procedure before_each
  as
  begin
    uc_ai.clear_exec_context;
    uc_ai_memory.clear_store;

    delete from uc_ai_memory_files
     where store_id in (select s.id from uc_ai_memory_stores s where s.store_key like '%TEST_MEM%');
    delete from uc_ai_memory_files where path like '/memories/test_mem_%';
    delete from uc_ai_memory_stores where store_key like '%TEST_MEM%';
    delete from uc_ai_memory_config where agent_code like 'TEST_MEM%';
    commit;
  end before_each;


  procedure after_each
  as
  begin
    uc_ai.clear_exec_context;
    uc_ai_memory.clear_store;
    rollback;
  end after_each;


  -- ==========================================================================
  -- Path security
  -- ==========================================================================

  procedure rejects_path_outside_memories
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/etc/passwd"}')).to_be_like('Error: Invalid path%');
  end rejects_path_outside_memories;


  procedure rejects_dotdot_traversal
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories/../secrets.env"}')).to_be_like('Error: Invalid path%');
    ut.expect(run_txt('{"command":"create","path":"/memories/notes/../../x","file_text":"x"}')).to_be_like('Error: Invalid path%');
  end rejects_dotdot_traversal;


  procedure rejects_backslash_traversal
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories\\..\\x"}')).to_be_like('Error: Invalid path%');
  end rejects_backslash_traversal;


  procedure rejects_urlencoded_traversal
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories/%2e%2e/x"}')).to_be_like('Error: Invalid path%');
    ut.expect(run_txt('{"command":"view","path":"/memories/%2E%2E/x"}')).to_be_like('Error: Invalid path%');
  end rejects_urlencoded_traversal;


  procedure normalizes_duplicate_slashes
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories//a.txt","file_text":"x"}'))
      .to_equal('File created successfully at: /memories/a.txt');
    ut.expect(run_txt('{"command":"view","path":"/memories/a.txt"}')).to_be_like('Here''s the content%');
  end normalizes_duplicate_slashes;


  -- ==========================================================================
  -- Store resolution
  -- ==========================================================================

  procedure resolves_agent_scope
  as
  begin
    enable_a;
    set_ctx(gc_agent_a);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(store_count('agent:' || gc_agent_a)).to_equal(1);
    ut.expect(file_count('agent:' || gc_agent_a)).to_equal(1);
  end resolves_agent_scope;


  procedure resolves_user_scope_per_user
  as
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_user);

    set_ctx(gc_agent_a, p_user => 'TEST_MEM_ALICE');
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"alice"}')).to_be_like('File created%');

    set_ctx(gc_agent_a, p_user => 'TEST_MEM_BOB');
    -- bob sees an empty root, not alice's file
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}')).to_be_like('The path%does not exist%');

    ut.expect(store_count('user:' || gc_agent_a || ':TEST_MEM_ALICE')).to_equal(1);
    ut.expect(store_count('user:' || gc_agent_a || ':TEST_MEM_BOB')).to_equal(1);
  end resolves_user_scope_per_user;


  procedure resolves_session_scope
  as
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_session);

    set_ctx(gc_agent_a, p_session => 'TEST_MEM_SESSION_1');
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"s1"}')).to_be_like('File created%');

    set_ctx(gc_agent_a, p_session => 'TEST_MEM_SESSION_2');
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}')).to_be_like('The path%does not exist%');

    ut.expect(store_count('session:TEST_MEM_SESSION_1')).to_equal(1);
  end resolves_session_scope;


  procedure resolves_shared_store_across_agents
  as
  begin
    uc_ai_memory.enable_for_agent(
      p_agent_code => gc_agent_a, p_scope => uc_ai_memory.c_scope_shared,
      p_store_code => gc_shared, p_update_profile => false);
    uc_ai_memory.enable_for_agent(
      p_agent_code => gc_agent_b, p_scope => uc_ai_memory.c_scope_shared,
      p_store_code => gc_shared, p_update_profile => false);

    set_ctx(gc_agent_a);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"from A"}')).to_be_like('File created%');

    set_ctx(gc_agent_b);
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}')).to_be_like('%from A%');

    ut.expect(store_count('shared:' || gc_shared)).to_equal(1);
  end resolves_shared_store_across_agents;


  procedure resolves_global_scope
  as
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_global);
    set_ctx(gc_agent_a);
    ut.expect(run_txt('{"command":"create","path":"/memories/test_mem_global.txt","file_text":"g"}')).to_be_like('File created%');
    ut.expect(store_count('global')).to_equal(1);
  end resolves_global_scope;


  procedure standalone_without_context_returns_error
  as
  begin
    ut.expect(run_txt('{"command":"view","path":"/memories"}'))
      .to_be_like('Error: the memory tool is not available here%');
  end standalone_without_context_returns_error;


  procedure set_store_override_resolves_shared
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(file_count('shared:' || gc_shared)).to_equal(1);
  end set_store_override_resolves_shared;


  procedure disabled_config_returns_error
  as
  begin
    enable_a;
    uc_ai_memory.disable_for_agent(gc_agent_a, p_remove_tool_tag => false);
    set_ctx(gc_agent_a);
    ut.expect(run_txt('{"command":"view","path":"/memories"}'))
      .to_be_like('Error: memory is disabled for agent%');
  end disabled_config_returns_error;


  procedure store_autoprovision_is_idempotent
  as
    l_res clob;
  begin
    enable_a;
    set_ctx(gc_agent_a);
    l_res := run('{"command":"view","path":"/memories"}');
    l_res := run('{"command":"create","path":"/memories/f.txt","file_text":"x"}');
    l_res := run('{"command":"view","path":"/memories"}');
    ut.expect(store_count('agent:' || gc_agent_a)).to_equal(1);
  end store_autoprovision_is_idempotent;


  -- ==========================================================================
  -- view
  -- ==========================================================================

  procedure view_empty_root_not_error
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories"}'))
      .to_equal('Here''re the files and directories up to 2 levels deep in /memories:'
        || chr(10) || '0' || chr(9) || '/memories');
  end view_empty_root_not_error;


  procedure view_directory_two_levels_sizes
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/a.txt","file_text":"12345"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/b.txt","file_text":"1234567890"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/sub/c.txt","file_text":"123"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/sub/deep/d.txt","file_text":"1"}')).to_be_like('File created%');

    l_res := run_txt('{"command":"view","path":"/memories"}');

    -- root aggregates everything (5 + 10 + 3 + 1 = 19)
    ut.expect(l_res).to_be_like('%19' || chr(9) || '/memories%');
    -- level 1: file + aggregated dir (10 + 3 + 1 = 14)
    ut.expect(l_res).to_be_like('%5' || chr(9) || '/memories/a.txt%');
    ut.expect(l_res).to_be_like('%14' || chr(9) || '/memories/dir%');
    -- level 2: file + aggregated sub-dir
    ut.expect(l_res).to_be_like('%10' || chr(9) || '/memories/dir/b.txt%');
    ut.expect(l_res).to_be_like('%4' || chr(9) || '/memories/dir/sub%');
    -- level 3 must NOT appear as an own entry
    ut.expect(instr(l_res, '/memories/dir/sub/deep') > 0).to_be_false();
  end view_directory_two_levels_sizes;


  procedure view_file_line_numbers_format
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"alpha\nbeta"}')).to_be_like('File created%');

    l_res := run_txt('{"command":"view","path":"/memories/f.txt"}');
    ut.expect(l_res).to_equal('Here''s the content of /memories/f.txt with line numbers:'
      || chr(10) || '     1' || chr(9) || 'alpha'
      || chr(10) || '     2' || chr(9) || 'beta');
  end view_file_line_numbers_format;


  procedure view_range_slice
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"l1\nl2\nl3\nl4"}')).to_be_like('File created%');

    l_res := run_txt('{"command":"view","path":"/memories/f.txt","view_range":[2,3]}');
    ut.expect(l_res).to_be_like('%     2' || chr(9) || 'l2' || chr(10) || '     3' || chr(9) || 'l3');
    ut.expect(instr(l_res, 'l1') > 0).to_be_false();
    ut.expect(instr(l_res, 'l4') > 0).to_be_false();
  end view_range_slice;


  procedure view_range_minus_one_to_eof
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"l1\nl2\nl3"}')).to_be_like('File created%');

    l_res := run_txt('{"command":"view","path":"/memories/f.txt","view_range":[2,-1]}');
    ut.expect(l_res).to_be_like('%l2%l3');
    ut.expect(instr(l_res, 'l1') > 0).to_be_false();
  end view_range_minus_one_to_eof;


  -- A listing has no lines, so no range can mean anything against one. A model
  -- in strict mode has to send the argument and invents a value: [1,200],
  -- [0,0], [-1,-1] and [-1,0] were all seen from one model in one run. Refusing
  -- any of them makes the listing succeed or fail by luck, so all are ignored.
  procedure view_directory_ignores_any_range
  as
    l_ranges apex_t_varchar2 := apex_t_varchar2('[1,2]', '[1,200]', '[0,0]', '[-1,-1]', '[-1,0]', '[5,3]');
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/f.txt","file_text":"x"}')).to_be_like('File created%');

    <<range_loop>>
    for i in 1 .. l_ranges.count loop
      ut.expect(run_txt('{"command":"view","path":"/memories/dir","view_range":' || l_ranges(i) || '}'))
        .to_be_like('Here''re the files and directories%');
    end loop range_loop;
  end view_directory_ignores_any_range;


  -- A provider in strict mode (OpenAI) requires every declared property of the
  -- tool schema to be present, so the model sends view_range on every call. The
  -- value it sends is its whole-file default. Reading that as "the caller asked
  -- for a range" made `view /memories` fail on every call, which left an agent
  -- unable to find what it wrote in an earlier conversation.
  procedure view_directory_with_default_range
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/test_mem_pref.txt","file_text":"x"}'))
      .to_be_like('File created%');

    l_res := run_txt('{"command":"view","path":"/memories","view_range":[1,-1]}');

    ut.expect(l_res).to_be_like('Here''re the files and directories%');
    ut.expect(l_res).to_be_like('%/memories/test_mem_pref.txt%');
  end view_directory_with_default_range;


  procedure view_directory_with_empty_range
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/test_mem_pref.txt","file_text":"x"}'))
      .to_be_like('File created%');

    ut.expect(run_txt('{"command":"view","path":"/memories","view_range":[]}'))
      .to_be_like('Here''re the files and directories%');
    ut.expect(run_txt('{"command":"view","path":"/memories","view_range":null}'))
      .to_be_like('Here''re the files and directories%');
  end view_directory_with_empty_range;


  -- The exact argument set captured from an OpenAI strict-mode run.
  procedure view_root_with_strict_mode_arguments
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/test_mem_pref.txt","file_text":"x"}'))
      .to_be_like('File created%');

    l_res := run_txt('{"command":"view","file_text":"","insert_line":0,"insert_text":"",'
      || '"new_path":"","new_str":"","old_path":"","old_str":"","path":"/memories",'
      || '"view_range":[1,-1]}');

    ut.expect(l_res).to_be_like('Here''re the files and directories%');
    ut.expect(l_res).to_be_like('%/memories/test_mem_pref.txt%');
  end view_root_with_strict_mode_arguments;


  procedure view_truncates_over_16k
  as
    l_text clob;
    l_res  clob;
  begin
    uc_ai_memory.set_store(gc_shared);
    -- @dblinter ignore(g-4395): the fixed line count is the point of this test; 800
    -- lines of 30 characters put the view output well over the 16000-character cap
    <<build_loop>>
    for i in 1 .. 800 loop
      if i > 1 then
        l_text := l_text || '\n';
      end if;
      l_text := l_text || rpad('x', 30, 'x');
    end loop build_loop;

    l_res := uc_ai_memory.execute_command(json_object_t.parse(
      '{"command":"create","path":"/memories/big.txt","file_text":"' || l_text || '"}'));
    ut.expect(sys.dbms_lob.substr(l_res, 100, 1)).to_be_like('File created%');

    l_res := run('{"command":"view","path":"/memories/big.txt"}');
    ut.expect(instr(l_res, 'output truncated') > 0).to_be_true();
    ut.expect(instr(l_res, 'view_range') > 0).to_be_true();
  end view_truncates_over_16k;


  procedure view_missing_path_error_string
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories/nope.txt"}'))
      .to_equal('The path /memories/nope.txt does not exist. Please provide a valid path.');
  end view_missing_path_error_string;


  procedure view_touches_last_accessed
  as
    l_res  clob;
    l_seen timestamp;
  begin
    uc_ai_memory.set_store(gc_shared);
    l_res := run('{"command":"create","path":"/memories/f.txt","file_text":"x"}');
    commit;  -- the touch is autonomous and can only see committed rows

    update uc_ai_memory_files
       set last_accessed_at = systimestamp - interval '10' day
     where path = '/memories/f.txt'
       and store_id = (select s.id from uc_ai_memory_stores s where s.store_key = 'shared:' || gc_shared);
    commit;

    l_res := run('{"command":"view","path":"/memories/f.txt"}');

    select last_accessed_at
      into l_seen
      from uc_ai_memory_files
     where path = '/memories/f.txt'
       and store_id = (select s.id from uc_ai_memory_stores s where s.store_key = 'shared:' || gc_shared);

    -- generous window: systimestamp lands in a tz-less timestamp column, so
    -- the stored value can trail the session's systimestamp by the utc offset
    ut.expect(l_seen > systimestamp - interval '1' day).to_be_true();
  end view_touches_last_accessed;


  -- ==========================================================================
  -- create
  -- ==========================================================================

  procedure create_new_file_message
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"x"}'))
      .to_equal('File created successfully at: /memories/f.txt');
  end create_new_file_message;


  procedure create_overwrites_existing
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"first"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"second"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}')).to_be_like('%second');
    ut.expect(file_count('shared:' || gc_shared)).to_equal(1);
  end create_overwrites_existing;


  procedure create_enforces_file_cap
  as
  begin
    enable_a(p_max_file_chars => 10);
    set_ctx(gc_agent_a);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"this is far too long for the cap"}'))
      .to_be_like('Error: file too large%');
  end create_enforces_file_cap;


  procedure create_enforces_max_files
  as
  begin
    enable_a(p_max_files => 1);
    set_ctx(gc_agent_a);
    ut.expect(run_txt('{"command":"create","path":"/memories/one.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/two.txt","file_text":"x"}'))
      .to_be_like('Error: the memory store already holds%');
  end create_enforces_max_files;


  -- ==========================================================================
  -- str_replace
  -- ==========================================================================

  procedure str_replace_unique_success_snippet
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"Favorite color: blue\nSecond line"}')).to_be_like('File created%');

    l_res := run_txt('{"command":"str_replace","path":"/memories/f.txt","old_str":"blue","new_str":"green"}');
    ut.expect(l_res).to_be_like('The memory file has been edited.%');
    -- snippet with line numbers around the edit
    ut.expect(l_res).to_be_like('%     1' || chr(9) || 'Favorite color: green%');
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}')).to_be_like('%green%');
  end str_replace_unique_success_snippet;


  procedure str_replace_not_found_exact_message
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"hello"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"str_replace","path":"/memories/f.txt","old_str":"absent","new_str":"x"}'))
      .to_equal('No replacement was performed, old_str `absent` did not appear verbatim in /memories/f.txt.');
  end str_replace_not_found_exact_message;


  procedure str_replace_multiple_reports_line_numbers
  as
    l_res varchar2(4000 char);
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"dup here\nclean\ndup here"}')).to_be_like('File created%');

    l_res := run_txt('{"command":"str_replace","path":"/memories/f.txt","old_str":"dup here","new_str":"x"}');
    ut.expect(l_res).to_be_like('No replacement was performed. Multiple occurrences%');
    ut.expect(l_res).to_be_like('%lines: 1, 3%');
  end str_replace_multiple_reports_line_numbers;


  procedure str_replace_omitted_new_str_deletes
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"keep REMOVE keep"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"str_replace","path":"/memories/f.txt","old_str":"REMOVE "}'))
      .to_be_like('The memory file has been edited.%');
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}')).to_be_like('%keep keep');
  end str_replace_omitted_new_str_deletes;


  -- ==========================================================================
  -- insert
  -- ==========================================================================

  procedure insert_line_zero_prepends
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"body"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"insert","path":"/memories/f.txt","insert_line":0,"insert_text":"HEADER"}'))
      .to_equal('The file /memories/f.txt has been edited.');
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}'))
      .to_be_like('%     1' || chr(9) || 'HEADER' || chr(10) || '     2' || chr(9) || 'body');
  end insert_line_zero_prepends;


  procedure insert_middle
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"l1\nl3"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"insert","path":"/memories/f.txt","insert_line":1,"insert_text":"l2"}'))
      .to_be_like('The file%has been edited.');
    ut.expect(run_txt('{"command":"view","path":"/memories/f.txt"}'))
      .to_be_like('%l1' || chr(10) || '     2' || chr(9) || 'l2' || chr(10) || '     3' || chr(9) || 'l3');
  end insert_middle;


  procedure insert_out_of_range_exact_message
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"l1\nl2"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"insert","path":"/memories/f.txt","insert_line":5,"insert_text":"x"}'))
      .to_equal('Error: Invalid `insert_line` parameter: 5. It should be within the range of lines of the file: [0, 2]');
  end insert_out_of_range_exact_message;


  procedure insert_missing_file_error
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"insert","path":"/memories/nope.txt","insert_line":0,"insert_text":"x"}'))
      .to_equal('Error: The path /memories/nope.txt does not exist');
  end insert_missing_file_error;


  -- ==========================================================================
  -- delete
  -- ==========================================================================

  procedure delete_file_message
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/f.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"delete","path":"/memories/f.txt"}'))
      .to_equal('Successfully deleted /memories/f.txt');
    ut.expect(file_count('shared:' || gc_shared)).to_equal(0);
  end delete_file_message;


  procedure delete_directory_recursive
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/a.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/sub/b.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/keep.txt","file_text":"x"}')).to_be_like('File created%');

    ut.expect(run_txt('{"command":"delete","path":"/memories/dir"}'))
      .to_equal('Successfully deleted /memories/dir');
    ut.expect(file_count('shared:' || gc_shared)).to_equal(1);
  end delete_directory_recursive;


  procedure delete_root_rejected
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"delete","path":"/memories"}'))
      .to_be_like('Error: cannot delete the /memories root%');
  end delete_root_rejected;


  procedure delete_missing_path_error
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"delete","path":"/memories/nope"}'))
      .to_equal('Error: The path /memories/nope does not exist');
  end delete_missing_path_error;


  -- ==========================================================================
  -- rename
  -- ==========================================================================

  procedure rename_file_message
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/draft.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"rename","old_path":"/memories/draft.txt","new_path":"/memories/final.txt"}'))
      .to_equal('Successfully renamed /memories/draft.txt to /memories/final.txt');
    ut.expect(run_txt('{"command":"view","path":"/memories/final.txt"}')).to_be_like('Here''s the content%');
  end rename_file_message;


  procedure rename_directory_moves_prefix
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/old/a.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/old/sub/b.txt","file_text":"x"}')).to_be_like('File created%');

    ut.expect(run_txt('{"command":"rename","old_path":"/memories/old","new_path":"/memories/new"}'))
      .to_equal('Successfully renamed /memories/old to /memories/new');

    ut.expect(run_txt('{"command":"view","path":"/memories/new/sub/b.txt"}')).to_be_like('Here''s the content%');
    ut.expect(run_txt('{"command":"view","path":"/memories/old"}')).to_be_like('The path%does not exist%');
  end rename_directory_moves_prefix;


  procedure rename_destination_exists_error
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/a.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/b.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"rename","old_path":"/memories/a.txt","new_path":"/memories/b.txt"}'))
      .to_equal('Error: The destination /memories/b.txt already exists');
  end rename_destination_exists_error;


  procedure rename_root_rejected
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"rename","old_path":"/memories","new_path":"/memories/x"}'))
      .to_be_like('Error: cannot rename the /memories root%');
  end rename_root_rejected;


  procedure rename_into_itself_rejected
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/dir/a.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"rename","old_path":"/memories/dir","new_path":"/memories/dir/inner"}'))
      .to_be_like('Error: cannot move%inside itself.');
  end rename_into_itself_rejected;


  -- ==========================================================================
  -- config API
  -- ==========================================================================

  procedure enable_for_agent_creates_config
  as
    l_row uc_ai_memory_config%rowtype;
  begin
    enable_a(p_max_file_chars => 5000);

    select * into l_row from uc_ai_memory_config where agent_code = gc_agent_a;
    ut.expect(l_row.enabled).to_equal('Y');
    ut.expect(l_row.scope).to_equal('agent');
    ut.expect(l_row.max_file_chars).to_equal(5000);
  end enable_for_agent_creates_config;


  procedure enable_adds_memory_tag_to_profile
  as
    l_config json_object_t;
  begin
    uc_ai_memory.enable_for_agent(p_agent_code => gc_agent_a);

    ut.expect(profile_has_memory_tag()).to_be_true();
    l_config := profile_config();
    ut.expect(l_config.get_boolean('g_enable_tools')).to_be_true();

    -- idempotent: enabling again must not duplicate the tag
    uc_ai_memory.enable_for_agent(p_agent_code => gc_agent_a);
    l_config := profile_config();
    ut.expect(l_config.get_array('g_tool_tags').get_size).to_equal(1);
  end enable_adds_memory_tag_to_profile;


  procedure enable_shared_requires_store_code
  as
  begin
    begin
      uc_ai_memory.enable_for_agent(
        p_agent_code => gc_agent_a,
        p_scope      => uc_ai_memory.c_scope_shared,
        p_update_profile => false);
      ut.fail('Expected -20424 for shared scope without store code');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_config_invalid);
    end;
  end enable_shared_requires_store_code;


  procedure enable_invalid_scope_raises
  as
  begin
    begin
      uc_ai_memory.enable_for_agent(
        p_agent_code => gc_agent_a,
        p_scope      => 'galaxy',
        p_update_profile => false);
      ut.fail('Expected -20421 for an invalid scope');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_invalid_scope);
    end;
  end enable_invalid_scope_raises;


  procedure enable_unknown_agent_raises
  as
  begin
    begin
      uc_ai_memory.enable_for_agent(
        p_agent_code => 'TEST_MEM_NO_SUCH_AGENT',
        p_update_profile => false);
      ut.fail('Expected -20422 for an unknown agent');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_agent_not_found);
    end;
  end enable_unknown_agent_raises;


  procedure disable_for_agent_disables
  as
    l_enabled uc_ai_memory_config.enabled%type;
  begin
    uc_ai_memory.enable_for_agent(p_agent_code => gc_agent_a);
    ut.expect(profile_has_memory_tag()).to_be_true();

    uc_ai_memory.disable_for_agent(gc_agent_a);

    select enabled into l_enabled from uc_ai_memory_config where agent_code = gc_agent_a;
    ut.expect(l_enabled).to_equal('N');
    ut.expect(profile_has_memory_tag()).to_be_false();
  end disable_for_agent_disables;


  procedure disable_keeps_tag_when_shared
  as
  begin
    -- both agents reference gc_prof and are memory-enabled
    uc_ai_memory.enable_for_agent(p_agent_code => gc_agent_a);
    uc_ai_memory.enable_for_agent(p_agent_code => gc_agent_b);

    uc_ai_memory.disable_for_agent(gc_agent_a);

    -- B still needs the tool: the tag must survive
    ut.expect(profile_has_memory_tag()).to_be_true();
  end disable_keeps_tag_when_shared;


  -- ==========================================================================
  -- admin helpers
  -- ==========================================================================

  procedure expire_files_deletes_stale_only
  as
    l_store_id number;
    l_count    pls_integer;
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/stale.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/fresh.txt","file_text":"x"}')).to_be_like('File created%');
    commit;

    l_store_id := uc_ai_memory.resolve_store_id(
      p_scope => uc_ai_memory.c_scope_shared, p_store_code => gc_shared);

    update uc_ai_memory_files
       set last_accessed_at = systimestamp - interval '100' day(3),
           updated_at       = systimestamp - interval '100' day(3)
     where store_id = l_store_id
       and path = '/memories/stale.txt';
    commit;

    uc_ai_memory.expire_files(p_days => 30, p_store_id => l_store_id);

    select count(*) into l_count from uc_ai_memory_files where store_id = l_store_id;
    ut.expect(l_count).to_equal(1);
    ut.expect(run_txt('{"command":"view","path":"/memories/fresh.txt"}')).to_be_like('Here''s the content%');
  end expire_files_deletes_stale_only;


  procedure clear_store_files_empties
  as
    l_store_id number;
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"create","path":"/memories/a.txt","file_text":"x"}')).to_be_like('File created%');
    ut.expect(run_txt('{"command":"create","path":"/memories/b.txt","file_text":"x"}')).to_be_like('File created%');

    l_store_id := uc_ai_memory.resolve_store_id(
      p_scope => uc_ai_memory.c_scope_shared, p_store_code => gc_shared);
    uc_ai_memory.clear_store_files(l_store_id);

    ut.expect(file_count('shared:' || gc_shared)).to_equal(0);
  end clear_store_files_empties;


  procedure put_get_file_roundtrip
  as
    l_store_id number;
    l_content  clob;
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories"}')).to_be_like('Here''re%');

    l_store_id := uc_ai_memory.resolve_store_id(
      p_scope => uc_ai_memory.c_scope_shared, p_store_code => gc_shared);

    uc_ai_memory.put_file(l_store_id, '/memories/seeded.md', 'seeded content');
    l_content := uc_ai_memory.get_file(l_store_id, '/memories/seeded.md');
    ut.expect(sys.dbms_lob.substr(l_content, 100, 1)).to_equal('seeded content');

    -- overwrite via put_file
    uc_ai_memory.put_file(l_store_id, '/memories/seeded.md', 'v2');
    ut.expect(sys.dbms_lob.substr(uc_ai_memory.get_file(l_store_id, '/memories/seeded.md'), 100, 1)).to_equal('v2');

    uc_ai_memory.delete_file(l_store_id, '/memories/seeded.md');
    begin
      l_content := uc_ai_memory.get_file(l_store_id, '/memories/seeded.md');
      ut.fail('Expected -20425 for a deleted file');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_file_not_found);
    end;
  end put_get_file_roundtrip;


  procedure resolve_store_id_behavior
  as
    l_id number;
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_txt('{"command":"view","path":"/memories"}')).to_be_like('Here''re%');

    l_id := uc_ai_memory.resolve_store_id(
      p_scope => uc_ai_memory.c_scope_shared, p_store_code => gc_shared);
    ut.expect(l_id).to_be_not_null();

    begin
      l_id := uc_ai_memory.resolve_store_id(
        p_scope => uc_ai_memory.c_scope_shared, p_store_code => 'TEST_MEM_NO_SUCH_STORE');
      ut.fail('Expected -20423 for a missing store');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_store_not_found);
    end;
  end resolve_store_id_behavior;


  -- ==========================================================================
  -- context scope
  -- ==========================================================================

  procedure context_scope_separates_values
  as
    l_out clob;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_note.md","file_text":"about doc 7"}');
    ut.expect(sys.dbms_lob.substr(l_out, 4000, 1)).to_be_like('%test_mem_note.md%');

    set_doc_ctx(gc_agent_a, '8');
    l_out := run('{"command":"create","path":"/memories/test_mem_note.md","file_text":"about doc 8"}');

    -- one store per document, and neither sees the other's file
    ut.expect(store_count(doc_key(gc_agent_a, '7'))).to_equal(1);
    ut.expect(store_count(doc_key(gc_agent_a, '8'))).to_equal(1);
    ut.expect(file_count(doc_key(gc_agent_a, '7'))).to_equal(1);
    ut.expect(file_count(doc_key(gc_agent_a, '8'))).to_equal(1);

    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"view","path":"/memories/test_mem_note.md"}');
    ut.expect(sys.dbms_lob.substr(l_out, 4000, 1)).to_be_like('%about doc 7%');
  end context_scope_separates_values;


  procedure context_scope_requires_key
  as
    l_out varchar2(4000 char);
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    -- the run carries no context at all
    set_ctx(gc_agent_a);
    l_out := run_txt('{"command":"view","path":"/memories"}');

    -- an instructive message, not an exception: the model has to read it
    ut.expect(l_out).to_be_like('Error:%document_id%');
    -- and nothing was provisioned
    ut.expect(store_count(doc_key(gc_agent_a, '7'))).to_equal(0);
  end context_scope_requires_key;


  procedure context_scope_shared_namespace
  as
    l_out clob;
  begin
    uc_ai_memory.enable_for_agent(
      p_agent_code     => gc_agent_a,
      p_scope          => uc_ai_memory.c_scope_context,
      p_store_code     => 'TEST_MEM_DOCS',
      p_context_key    => 'document_id',
      p_update_profile => false
    );
    uc_ai_memory.enable_for_agent(
      p_agent_code     => gc_agent_b,
      p_scope          => uc_ai_memory.c_scope_context,
      p_store_code     => 'TEST_MEM_DOCS',
      p_context_key    => 'document_id',
      p_update_profile => false
    );

    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_shared.md","file_text":"agent A learned this"}');

    -- the second agent works on the same document and sees what the first learned
    set_doc_ctx(gc_agent_b, '7');
    l_out := run('{"command":"view","path":"/memories/test_mem_shared.md"}');
    ut.expect(sys.dbms_lob.substr(l_out, 4000, 1)).to_be_like('%agent A learned this%');

    ut.expect(store_count(doc_key('TEST_MEM_DOCS', '7'))).to_equal(1);
    ut.expect(store_count(doc_key(gc_agent_a, '7'))).to_equal(0);
  end context_scope_shared_namespace;


  procedure context_scope_private_by_default
  as
    l_out clob;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');
    uc_ai_memory.enable_for_agent(
      p_agent_code     => gc_agent_b,
      p_scope          => uc_ai_memory.c_scope_context,
      p_context_key    => 'document_id',
      p_update_profile => false
    );

    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_private.md","file_text":"only agent A"}');

    -- same document, other agent: without a shared namespace the stores are separate
    set_doc_ctx(gc_agent_b, '7');
    ut.expect(run_txt('{"command":"view","path":"/memories/test_mem_private.md"}'))
      .to_be_like('%does not exist%');

    ut.expect(store_count(doc_key(gc_agent_a, '7'))).to_equal(1);
    ut.expect(store_count(doc_key(gc_agent_b, '7'))).to_equal(1);
  end context_scope_private_by_default;


  procedure context_scope_needs_context_key
  as
  begin
    begin
      enable_a(p_scope => uc_ai_memory.c_scope_context);
      ut.fail('Expected -20424: scope context needs p_context_key');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_config_invalid);
    end;
  end context_scope_needs_context_key;


  procedure context_scope_rejects_bad_value
  as
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    -- a colon would let the value address a store of another namespace or key
    set_doc_ctx(gc_agent_a, 'x:context:OTHER_AGENT:document_id');
    ut.expect(run_txt('{"command":"view","path":"/memories"}')).to_be_like('Error:%document_id%');

    -- and a plain space is refused as well
    set_doc_ctx(gc_agent_a, 'doc 7');
    ut.expect(run_txt('{"command":"view","path":"/memories"}')).to_be_like('Error:%');
  end context_scope_rejects_bad_value;


  procedure context_scope_resolve_store_id
  as
    l_out clob;
    l_id  number;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');
    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_admin.md","file_text":"x"}');

    l_id := uc_ai_memory.resolve_store_id(
      p_scope         => uc_ai_memory.c_scope_context,
      p_agent_code    => gc_agent_a,
      p_context_key   => 'document_id',
      p_context_value => '7'
    );
    ut.expect(l_id).to_be_not_null();
    ut.expect(uc_ai_memory.get_file(l_id, '/memories/test_mem_admin.md')).to_be_not_null();
  end context_scope_resolve_store_id;


  procedure context_scope_drop_store
  as
    l_out clob;
  begin
    -- agent A keeps its own per-document stores
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');
    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_own.md","file_text":"x"}');

    -- agent B puts its per-document store in a shared namespace
    uc_ai_memory.enable_for_agent(
      p_agent_code     => gc_agent_b,
      p_scope          => uc_ai_memory.c_scope_context,
      p_store_code     => 'TEST_MEM_DOCS',
      p_context_key    => 'document_id',
      p_update_profile => false
    );
    set_doc_ctx(gc_agent_b, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_shared.md","file_text":"y"}');

    uc_ai_memory.disable_for_agent(
      p_agent_code      => gc_agent_a,
      p_remove_tool_tag => false,
      p_drop_store      => true
    );

    ut.expect(store_count(doc_key(gc_agent_a, '7'))).to_equal(0);
    -- a shared namespace is nobody's own store, so it survives
    ut.expect(store_count(doc_key('TEST_MEM_DOCS', '7'))).to_equal(1);
  end context_scope_drop_store;


  procedure context_scope_value_length_limit
  as
    l_at   varchar2(300 char) := rpad('a', 200, 'a');
    l_over varchar2(300 char) := rpad('a', 201, 'a');
    l_out  clob;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    -- exactly the width of uc_ai_memory_stores.context_value: still a store
    set_doc_ctx(gc_agent_a, l_at);
    l_out := run('{"command":"create","path":"/memories/test_mem_limit.md","file_text":"x"}');
    ut.expect(sys.dbms_lob.substr(l_out, 4000, 1)).to_be_like('%test_mem_limit.md%');
    ut.expect(store_count(doc_key(gc_agent_a, l_at))).to_equal(1);

    -- one character more: refused with a message, and nothing is provisioned
    set_doc_ctx(gc_agent_a, l_over);
    ut.expect(run_txt('{"command":"view","path":"/memories"}')).to_be_like('Error:%200 characters%');
    ut.expect(store_count(doc_key(gc_agent_a, l_over))).to_equal(0);
  end context_scope_value_length_limit;


  procedure context_scope_reuses_existing_store
  as
    l_key varchar2(1000 char) := doc_key(gc_agent_a, '7');
    l_pre number;
    l_now number;
    l_out clob;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    -- another session for the same document got there first and committed
    insert into uc_ai_memory_stores (store_key, scope, agent_code, context_key, context_value)
    values (l_key, uc_ai_memory.c_scope_context, gc_agent_a, 'document_id', '7')
    returning id into l_pre;
    commit;

    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_race.md","file_text":"x"}');
    ut.expect(sys.dbms_lob.substr(l_out, 4000, 1)).to_be_like('%test_mem_race.md%');

    -- the run joined that store instead of provisioning a second one
    ut.expect(store_count(l_key)).to_equal(1);
    l_now := uc_ai_memory.resolve_store_id(
      p_scope         => uc_ai_memory.c_scope_context,
      p_agent_code    => gc_agent_a,
      p_context_key   => 'document_id',
      p_context_value => '7'
    );
    ut.expect(l_now).to_equal(l_pre);
    ut.expect(file_count(l_key)).to_equal(1);
  end context_scope_reuses_existing_store;


  procedure context_scope_housekeeping
  as
    l_store_id number;
    l_count    pls_integer;
    l_out      clob;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    set_doc_ctx(gc_agent_a, '7');
    l_out := run('{"command":"create","path":"/memories/test_mem_stale.md","file_text":"x"}');
    l_out := run('{"command":"create","path":"/memories/test_mem_fresh.md","file_text":"x"}');

    -- a second document, so the housekeeping can be shown to stay inside one store
    set_doc_ctx(gc_agent_a, '8');
    l_out := run('{"command":"create","path":"/memories/test_mem_other.md","file_text":"y"}');
    commit;

    l_store_id := uc_ai_memory.resolve_store_id(
      p_scope         => uc_ai_memory.c_scope_context,
      p_agent_code    => gc_agent_a,
      p_context_key   => 'document_id',
      p_context_value => '7'
    );

    update uc_ai_memory_files
       set last_accessed_at = systimestamp - interval '100' day(3),
           updated_at       = systimestamp - interval '100' day(3)
     where store_id = l_store_id
       and path = '/memories/test_mem_stale.md';
    commit;

    uc_ai_memory.expire_files(p_days => 30, p_store_id => l_store_id);

    select count(*) into l_count from uc_ai_memory_files where store_id = l_store_id;
    ut.expect(l_count).to_equal(1);

    uc_ai_memory.clear_store_files(l_store_id);
    ut.expect(file_count(doc_key(gc_agent_a, '7'))).to_equal(0);
    -- the other document kept its memory
    ut.expect(file_count(doc_key(gc_agent_a, '8'))).to_equal(1);
  end context_scope_housekeeping;


  -- ==========================================================================
  -- run readiness
  -- ==========================================================================

  procedure run_ready_raises_without_key
  as
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    begin
      uc_ai_memory.check_run_ready(gc_agent_a, null);
      ut.fail('Expected -20426 for a run without the context key');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_context_missing);
        ut.expect(sqlerrm).to_be_like('%document_id%');
    end;

    -- a bag that has other keys but not this one is the same failure
    begin
      uc_ai_memory.check_run_ready(gc_agent_a, '{"tenant_id":"ACME"}');
      ut.fail('Expected -20426 for a bag without the context key');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_context_missing);
    end;
  end run_ready_raises_without_key;


  procedure run_ready_raises_on_bad_value
  as
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');

    begin
      uc_ai_memory.check_run_ready(gc_agent_a, '{"document_id":"x:forged"}');
      ut.fail('Expected -20426 for a value that cannot identify a store');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_memory.c_err_context_missing);
    end;
  end run_ready_raises_on_bad_value;


  procedure run_ready_silent_when_fine
  as
  begin
    -- the key is supplied
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');
    uc_ai_memory.check_run_ready(gc_agent_a, '{"document_id":"7"}');

    -- another scope needs no run context at all
    enable_a(p_scope => uc_ai_memory.c_scope_agent);
    uc_ai_memory.check_run_ready(gc_agent_a, null);

    -- an agent without memory is none of its business
    uc_ai_memory.check_run_ready('TEST_MEM_NO_SUCH_AGENT', null);

    -- a disabled agent likewise
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');
    uc_ai_memory.disable_for_agent(gc_agent_a, p_remove_tool_tag => false);
    uc_ai_memory.check_run_ready(gc_agent_a, null);

    ut.expect(1).to_equal(1); -- reached without raising
  end run_ready_silent_when_fine;


  -- The failure this guards against: the store holds content, the run omits the
  -- key, the tool can only answer in text, and the model reports "nothing
  -- recorded" while the run reports success. Failing at run start puts the error
  -- in front of the developer instead.
  procedure run_without_key_fails_the_run
  as
    l_res json_object_t;
  begin
    enable_a(p_scope => uc_ai_memory.c_scope_context, p_context_key => 'document_id');
    commit;

    begin
      l_res := uc_ai_agents_api.execute_agent(
        p_agent_code => gc_agent_a,
        p_session_id => uc_ai_agents_api.generate_session_id
      );
      ut.fail('Expected the run to fail, got status ' || l_res.get_string('status'));
    exception
      when others then
        ut.expect(sqlerrm).to_be_like('%document_id%');
    end;
  end run_without_key_fails_the_run;


  procedure protocol_separates_failure_from_empty
  as
    l_protocol clob := uc_ai_memory.get_memory_protocol;
  begin
    ut.expect(instr(l_protocol, 'could not determine') > 0).to_be_true();
    ut.expect(instr(l_protocol, 'NOT an empty memory') > 0).to_be_true();
    ut.expect(instr(l_protocol, 'could not be read') > 0).to_be_true();
  end protocol_separates_failure_from_empty;


  -- ==========================================================================
  -- prompt hook
  -- ==========================================================================

  procedure augment_appends_protocol
  as
    l_prompt clob := 'You are a helpful assistant.';
  begin
    enable_a;
    set_ctx(gc_agent_a);

    uc_ai_memory.augment_system_prompt(l_prompt);

    ut.expect(instr(l_prompt, 'MEMORY PROTOCOL') > 0).to_be_true();
    ut.expect(sys.dbms_lob.substr(l_prompt, 28, 1)).to_equal('You are a helpful assistant.');
  end augment_appends_protocol;


  procedure augment_noop_when_not_enabled
  as
    l_prompt clob := 'You are a helpful assistant.';
  begin
    set_ctx(gc_agent_b);  -- no config row for B in this test

    uc_ai_memory.augment_system_prompt(l_prompt);

    ut.expect(instr(l_prompt, 'MEMORY PROTOCOL') > 0).to_be_false();
  end augment_noop_when_not_enabled;


  -- ==========================================================================
  -- Tool layer
  -- ==========================================================================
  -- The tests above call uc_ai_memory.execute_command directly. These go through
  -- uc_ai_tools_api.execute_tool, which reads the function_call of the registered
  -- MEMORY row and binds the arguments as one CLOB - the path a provider uses.

  procedure tool_layer_view_works
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_tool('{"command":"view","path":"/memories"}'))
      .to_equal('Here''re the files and directories up to 2 levels deep in /memories:'
        || chr(10) || '0' || chr(9) || '/memories');
  end tool_layer_view_works;


  procedure tool_layer_create_and_view_file
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_tool('{"command":"create","path":"/memories/tool.txt","file_text":"from the tool layer"}'))
      .to_equal('File created successfully at: /memories/tool.txt');
    ut.expect(run_tool('{"command":"view","path":"/memories/tool.txt"}'))
      .to_be_like('%from the tool layer%');
    ut.expect(file_count('shared:' || gc_shared)).to_equal(1);
  end tool_layer_create_and_view_file;


  procedure tool_layer_malformed_json_error
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    -- the tool layer binds a CLOB, and a model can send anything: the handler
    -- must answer with an error string and must not raise
    ut.expect(sys.dbms_lob.substr(uc_ai_memory.execute_command(to_clob('{"command":')), 4000, 1))
      .to_be_like('Error: the memory arguments are not a JSON object%');
    ut.expect(sys.dbms_lob.substr(uc_ai_memory.execute_command(to_clob('view /memories')), 4000, 1))
      .to_be_like('Error: the memory arguments are not a JSON object%');
    ut.expect(sys.dbms_lob.substr(uc_ai_memory.execute_command(to_clob('["view"]')), 4000, 1))
      .to_be_like('Error: the memory arguments are not a JSON object%');
  end tool_layer_malformed_json_error;


  procedure tool_layer_empty_arguments_error
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    ut.expect(run_tool(null)).to_be_like('Error: parameter `command` is required%');
    ut.expect(run_tool('{}')).to_be_like('Error: parameter `command` is required%');
  end tool_layer_empty_arguments_error;


  procedure tool_layer_wrapped_arguments
  as
  begin
    uc_ai_memory.set_store(gc_shared);
    -- the tool layer adds the run context to the arguments, which must not count
    -- as the parent object of a provider that wraps the arguments
    ut.expect(run_tool('{"input":{"command":"create","path":"/memories/w.txt","file_text":"x"}}'))
      .to_equal('File created successfully at: /memories/w.txt');
  end tool_layer_wrapped_arguments;

end test_uc_ai_memory;
/
