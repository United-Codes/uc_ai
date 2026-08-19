create or replace package body test_uc_ai_ptc as
  -- @dblinter ignore(g-5010): allow logger-free simple test helpers in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-4395): fixture loops are deliberately fixed-size so the expected aggregates stay literal

  gc_prefix constant varchar2(50 char) := 'TEST_PTC_';
  gc_user   constant varchar2(255 char) := 'TEST_USER';
  gc_tag    constant varchar2(50 char) := 'ptc_test';  -- tags are stored lowercase
  gc_hook   constant varchar2(255 char) := 'TEST_UC_AI_HOOK_STUB';

  -- Deterministic per-employee approved travel spend so the aggregate is known:
  -- employee N spends N * 100 approved travel. Employees 1..3 => 100+200+300 = 600.
  function f_get_employees(p_args in clob) return clob
  as
    l_arr json_array_t := json_array_t();
    l_obj json_object_t;
  begin
    <<employee_loop>>
    for i in 1 .. 3 loop
      l_obj := json_object_t();
      l_obj.put('id', i);
      l_obj.put('name', 'Employee ' || i);
      l_arr.append(l_obj);
    end loop employee_loop;
    return l_arr.to_clob;
  end f_get_employees;

  function f_get_expenses(p_args in clob) return clob
  as
    l_id  number := json_object_t(p_args).get_number('employee_id');
    l_arr json_array_t := json_array_t();
    l_obj json_object_t;
  begin
    l_obj := json_object_t();
    l_obj.put('category', 'travel'); l_obj.put('amount', l_id * 100); l_obj.put('status', 'approved');
    l_arr.append(l_obj);
    l_obj := json_object_t();
    l_obj.put('category', 'travel'); l_obj.put('amount', 50); l_obj.put('status', 'pending');
    l_arr.append(l_obj);
    l_obj := json_object_t();
    l_obj.put('category', 'meals'); l_obj.put('amount', 25); l_obj.put('status', 'approved');
    l_arr.append(l_obj);
    return l_arr.to_clob;
  end f_get_expenses;

  -- Returns ~55 KB of JSON (100 rows x 500 chars) to exercise large tool results.
  function f_big_payload(p_args in clob) return clob
  as
    l_arr json_array_t := json_array_t();
    l_obj json_object_t;
  begin
    <<payload_loop>>
    for i in 1 .. 100 loop
      l_obj := json_object_t();
      l_obj.put('id', i);
      l_obj.put('text', rpad('x', 500, 'x'));
      l_arr.append(l_obj);
    end loop payload_loop;
    return l_arr.to_clob;
  end f_big_payload;

  -- A tool that itself starts a code-mode run, like an agent-as-tool whose agent
  -- uses code mode. Exercises save/restore of the outer run context.
  function f_nested_program(p_args in clob) return clob
  as
    l_args     json_object_t := json_object_t();
    l_settings uc_ai_settings.t_settings := uc_ai_settings.build_from_globals;
  begin
    l_args.put('code', 'const result = await callTool("' || gc_prefix || 'GET_EMPLOYEES", {});');
    return uc_ai_tools_api.execute_agent_tool(
             uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);
  end f_nested_program;


  procedure reset_state as
  begin
    uc_ai_agents_api.set_execution_hook(null);
    test_uc_ai_hook_stub.reset;
    -- run_program leaves enable_tools/tool_tags set on the globals; another suite
    -- in the same session would then see this suite's tag filter
    uc_ai.reset_globals;
  end reset_state;

  procedure cleanup_tools as
  begin
    reset_state;
    delete from uc_ai_tools where code like gc_prefix || '%';
  end cleanup_tools;

  procedure setup_tools as
    l_id uc_ai_tools.id%type;
  begin
    cleanup_tools;

    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_prefix || 'GET_EMPLOYEES'
    , p_description   => 'List all employees'
    , p_function_call => 'return test_uc_ai_ptc.f_get_employees(:parameters);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by    => gc_user
    , p_tags          => apex_t_varchar2(gc_tag)
    );

    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_prefix || 'GET_EXPENSES'
    , p_description   => 'Get expenses for one employee'
    , p_function_call => 'return test_uc_ai_ptc.f_get_expenses(:parameters);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{"employee_id":{"type":"integer","description":"Employee id"}},"required":["employee_id"]}')
    , p_created_by    => gc_user
    , p_tags          => apex_t_varchar2(gc_tag)
    );

    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_prefix || 'BIG'
    , p_description   => 'Return a large (>32 KB) payload'
    , p_function_call => 'return test_uc_ai_ptc.f_big_payload(:parameters);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by    => gc_user
    , p_tags          => apex_t_varchar2(gc_tag)
    );

    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_prefix || 'NESTED'
    , p_description   => 'Runs its own code-mode program'
    , p_function_call => 'return test_uc_ai_ptc.f_nested_program(:parameters);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by    => gc_user
    , p_tags          => apex_t_varchar2(gc_tag)
    );

    -- direct-only: normal tool, must NOT be callable from a program
    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code        => gc_prefix || 'DIRECT_ONLY'
    , p_description      => 'Direct-only tool'
    , p_function_call    => 'return test_uc_ai_ptc.f_get_employees(:parameters);'
    , p_json_schema      => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by       => gc_user
    , p_tags             => apex_t_varchar2(gc_tag)
    , p_code_mode_access => 'direct'
    );

    -- long, multi-line description: the catalog must carry it in full, on one line
    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code        => gc_prefix || 'LONG_DESC'
    , p_description      => 'First sentence of a deliberately long description.' || chr(10)
                            || rpad('more detail ', 1000, 'more detail ') || chr(9)
                            || 'END_OF_LONG_DESC'
    , p_function_call    => 'return test_uc_ai_ptc.f_get_employees(:parameters);'
    , p_json_schema      => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by       => gc_user
    , p_tags             => apex_t_varchar2(gc_tag)
    , p_code_mode_access => 'code'
    );

    -- code-only: must NOT appear as a normal tool, but IS callable from a program
    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code        => gc_prefix || 'CODE_ONLY'
    , p_description      => 'Code-only tool'
    , p_function_call    => 'return test_uc_ai_ptc.f_get_employees(:parameters);'
    , p_json_schema      => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by       => gc_user
    , p_tags             => apex_t_varchar2(gc_tag)
    , p_code_mode_access => 'code'
    );
  end setup_tools;


  -- Run a model-style JS program through the real code-mode path (which executes
  -- inside the low-privilege sandbox schema), scoped to our tagged tools.
  function run_program(p_js in clob) return clob as
    l_settings uc_ai_settings.t_settings;
    l_args     json_object_t := json_object_t();
  begin
    uc_ai.reset_globals;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags    := apex_t_varchar2(gc_tag);
    l_settings := uc_ai_settings.build_from_globals;
    l_args.put('code', p_js);
    return uc_ai_tools_api.execute_agent_tool(
             uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);
  end run_program;

  function get_meta_tool(
    p_programmatic_tools in boolean
  , p_provider  in varchar2 default uc_ai.c_provider_anthropic
  , p_add_info  in varchar2 default null
  ) return json_object_t as
    l_tools json_array_t;
    l_obj   json_object_t;
  begin
    l_tools := uc_ai_tools_api.get_tools_array(
      p_provider        => p_provider
    , p_additional_info => p_add_info
    , p_tool_tags       => apex_t_varchar2(gc_tag)
    , p_enable_tools    => true
    , p_programmatic_tools       => p_programmatic_tools
    );
    <<meta_lookup_loop>>
    for i in 0 .. l_tools.get_size - 1 loop
      l_obj := treat(l_tools.get(i) as json_object_t);
      -- openai/ollama wrap the definition in {type, function:{...}}
      if l_obj.has('function') then
        l_obj := l_obj.get_object('function');
      end if;
      if l_obj.get_string('name') = uc_ai_tools_api.c_code_mode_tool_code then
        return l_obj;
      end if;
    end loop meta_lookup_loop;
    return null;
  end get_meta_tool;

  -- The provider-specific key the tool's JSON schema must sit under.
  function meta_schema_key(
    p_provider in varchar2
  , p_add_info in varchar2 default null
  ) return varchar2 as
    l_meta json_object_t := get_meta_tool(true, p_provider, p_add_info);
  begin
    if l_meta is null then
      return null;
    elsif l_meta.has('parameters') then
      return 'parameters';
    elsif l_meta.has('input_schema') then
      return 'input_schema';
    end if;
    return 'none';
  end meta_schema_key;

  function meta_catalog(
    p_provider in varchar2
  , p_add_info in varchar2 default null
  ) return clob as
    l_meta json_object_t := get_meta_tool(true, p_provider, p_add_info);
    l_key  varchar2(30 char) := meta_schema_key(p_provider, p_add_info);
  begin
    return l_meta.get_object(l_key).get_object('properties').get_object('code').get_string('description');
  end meta_catalog;


  procedure test_code_mode_orchestration as
    l_out clob;
    l_obj json_object_t;
  begin
    l_out := run_program(q'~
      const employees = await callTool("TEST_PTC_GET_EMPLOYEES", {});
      let total = 0;
      for (const e of employees) {
        const expenses = await callTool("TEST_PTC_GET_EXPENSES", { employee_id: e.id });
        for (const x of expenses) {
          if (x.category === "travel" && x.status === "approved") total += x.amount;
        }
      }
      const result = { approved_travel_total: total, employee_count: employees.length };
    ~');
    l_obj := json_object_t(l_out);
    ut.expect(l_obj.get_number('approved_travel_total')).to_equal(600);
    ut.expect(l_obj.get_number('employee_count')).to_equal(3);
  end test_code_mode_orchestration;

  -- A tool result becomes the content of a tool message, and OpenAI-compatible
  -- providers reject a null content with HTTP 422 - so a program that sets no
  -- `result` must still come back as readable data.
  procedure test_code_mode_no_result as
    l_out clob;
  begin
    l_out := run_program('const x = await callTool("TEST_PTC_GET_EMPLOYEES", {}); const y = x.length;');
    ut.expect(l_out).to_be_not_null();
    ut.expect(json_object_t(l_out).get_string('error')).to_be_like('%without assigning a value to `result`%');
  end test_code_mode_no_result;

  procedure test_meta_tool_exposure as
    l_code_desc clob;
  begin
    ut.expect(get_meta_tool(p_programmatic_tools => true)).to_be_not_null();
    ut.expect(get_meta_tool(p_programmatic_tools => false)).to_be_null();

    l_code_desc := meta_catalog(uc_ai.c_provider_anthropic);
    ut.expect(l_code_desc).to_be_like('%' || gc_prefix || 'GET_EMPLOYEES%');
    ut.expect(l_code_desc).to_be_like('%' || gc_prefix || 'GET_EXPENSES%');
  end test_meta_tool_exposure;

  -- Regression: the meta-tool used to hard-code "input_schema", so on providers
  -- that expect "parameters" the `code` argument was never declared.
  procedure test_meta_tool_schema_key as
  begin
    ut.expect(meta_schema_key(uc_ai.c_provider_anthropic)).to_equal('input_schema');
    ut.expect(meta_schema_key(uc_ai.c_provider_responses_api)).to_equal('parameters');
    ut.expect(meta_schema_key(uc_ai.c_provider_google)).to_equal('parameters');
    ut.expect(meta_schema_key(uc_ai.c_provider_ollama)).to_equal('parameters');
    ut.expect(meta_schema_key(uc_ai.c_provider_openai)).to_equal('input_schema');
    ut.expect(meta_schema_key(uc_ai.c_provider_openai, uc_ai.c_provider_xai)).to_equal('parameters');
    ut.expect(meta_schema_key(uc_ai.c_provider_openai, uc_ai.c_provider_openrouter)).to_equal('parameters');
    ut.expect(meta_schema_key(uc_ai.c_provider_openai, uc_ai.c_provider_mistral)).to_equal('parameters');
  end test_meta_tool_schema_key;

  -- Regression: the meta-tool carried additionalProperties, which makes Gemini
  -- reject the whole request ("Unknown name \"additionalProperties\"").
  procedure test_meta_tool_google_schema as
    l_meta json_object_t;
  begin
    l_meta := get_meta_tool(true, uc_ai.c_provider_google);
    ut.expect(l_meta.get_object('parameters').has('additionalProperties')).to_be_false();
    ut.expect(l_meta.get_object('parameters').has('$schema')).to_be_false();
    -- every other provider keeps the strict schema
    ut.expect(get_meta_tool(true, uc_ai.c_provider_anthropic)
                .get_object('input_schema').has('additionalProperties')).to_be_true();
  end test_meta_tool_google_schema;

  -- Regression: parameter names were read from a hard-coded "input_schema", so the
  -- catalog showed "{  }" for every tool on providers that use "parameters".
  procedure test_catalog_param_names as
  begin
    ut.expect(meta_catalog(uc_ai.c_provider_anthropic)).to_be_like('%GET_EXPENSES", { employee_id }%');
    ut.expect(meta_catalog(uc_ai.c_provider_google)).to_be_like('%GET_EXPENSES", { employee_id }%');
    ut.expect(meta_catalog(uc_ai.c_provider_ollama)).to_be_like('%GET_EXPENSES", { employee_id }%');
    ut.expect(meta_catalog(uc_ai.c_provider_openai, uc_ai.c_provider_xai)).to_be_like('%GET_EXPENSES", { employee_id }%');
  end test_catalog_param_names;

  -- Regression: the catalog cut every description at 200 chars. For a code-only tool
  -- that description is the only documentation the model gets (the catalog lists
  -- parameter names, not the JSON schema), so it was silently losing semantics.
  procedure test_catalog_keeps_full_description as
    l_catalog varchar2(32767 char);
    l_line    varchar2(32767 char);
  begin
    l_catalog := meta_catalog(uc_ai.c_provider_anthropic);

    -- the tail sits ~1000 chars past the old cut, so it only shows up if nothing was cut
    ut.expect(instr(l_catalog, 'END_OF_LONG_DESC')).to_be_greater_than(0);

    -- ... and the whole entry must still be ONE line: newlines and tabs inside a
    -- description are folded to spaces, otherwise the '//' comment would break and
    -- swallow the following catalog entries as code.
    l_line := regexp_substr(l_catalog, '^  await callTool\("' || gc_prefix || 'LONG_DESC".*$', 1, 1, 'm');
    ut.expect(instr(l_line, 'END_OF_LONG_DESC')).to_be_greater_than(0);
    ut.expect(length(l_line)).to_be_greater_than(1000);
  end test_catalog_keeps_full_description;

  -- Regression: the code argument was read with get_string, which raises above 32 KB.
  procedure test_large_program as
    l_out  clob;
    l_code clob;
  begin
    l_code := 'const employees = await callTool("' || gc_prefix || 'GET_EMPLOYEES", {});' || chr(10)
              || '// ' || rpad('x', 32000, 'x') || chr(10)
              || '// ' || rpad('y', 9000, 'y') || chr(10)
              || 'const result = { n: employees.length };';
    ut.expect(sys.dbms_lob.getlength(l_code)).to_be_greater_than(32767);

    l_out := run_program(l_code);
    ut.expect(json_object_t(l_out).get_number('n')).to_equal(3);
  end test_large_program;

  -- The program runs in a PURE MLE context: no SQL at all. That is what stops it
  -- from reading tables AND from committing/rolling back the caller's transaction
  -- (transaction control needs no privilege, so the privilege wall alone would not).
  procedure test_no_sql_access as
    l_out clob;
    l_obj json_object_t;
    l_cnt pls_integer;
  begin
    -- an uncommitted change of the caller that the program must not be able to undo
    update uc_ai_tools set description = 'MARKER_UNCOMMITTED' where code = gc_prefix || 'BIG';

    l_out := run_program(q'~
      const attempts = {};
      try { attempts.req = typeof require("mle-js-oracledb"); } catch (e) { attempts.req = "blocked"; }
      try { const m = await import("mle-js-oracledb"); attempts.imp = "reached"; } catch (e) { attempts.imp = "blocked"; }
      attempts.globals = [typeof oracledb, typeof session, typeof soda, typeof plsffi].join(",");
      const result = attempts;
    ~');
    l_obj := json_object_t(l_out);
    ut.expect(l_obj.get_string('req')).to_equal('blocked');
    ut.expect(l_obj.get_string('imp')).to_equal('blocked');
    ut.expect(l_obj.get_string('globals')).to_equal('undefined,undefined,undefined,undefined');

    -- the caller's uncommitted change is still pending
    select count(*) into l_cnt from uc_ai_tools where description = 'MARKER_UNCOMMITTED';
    ut.expect(l_cnt).to_equal(1);
  end test_no_sql_access;

  procedure test_allowlist_rejection as
    l_out clob;
    l_obj json_object_t;
  begin
    -- A tool that is not part of this run's tagged set must be rejected.
    l_out := run_program('const result = await callTool("TEST_PTC_NOT_EXPOSED", {});');
    l_obj := json_object_t(l_out);
    ut.expect(l_obj.has('error')).to_be_true();
  end test_allowlist_rejection;

  procedure test_large_tool_result as
    l_out clob;
    l_obj json_object_t;
  begin
    -- The tool returns ~55 KB; the program must receive all of it (no 32 KB cap).
    l_out := run_program(q'~
      const rows = await callTool("TEST_PTC_BIG", {});
      let chars = 0;
      for (const r of rows) chars += r.text.length;
      const result = { count: rows.length, chars };
    ~');
    l_obj := json_object_t(l_out);
    ut.expect(l_obj.get_number('count')).to_equal(100);
    ut.expect(l_obj.get_number('chars')).to_equal(50000);
  end test_large_tool_result;

  procedure test_code_mode_access as
    l_tools     json_array_t;
    l_obj_i     json_object_t;
    l_direct    varchar2(4000 char);
    l_catalog   clob;
    l_out       clob;
  begin
    -- Build the tool array (code mode on), scoped to our tag.
    l_tools := uc_ai_tools_api.get_tools_array(
      p_provider     => uc_ai.c_provider_anthropic
    , p_tool_tags    => apex_t_varchar2(gc_tag)
    , p_enable_tools => true
    , p_programmatic_tools    => true
    );
    <<split_loop>>
    for i in 0 .. l_tools.get_size - 1 loop
      l_obj_i := treat(l_tools.get(i) as json_object_t);
      if l_obj_i.get_string('name') = uc_ai_tools_api.c_code_mode_tool_code then
        l_catalog := l_obj_i.get_object('input_schema').get_object('properties').get_object('code').get_string('description');
      else
        l_direct := l_direct || l_obj_i.get_string('name') || ',';
      end if;
    end loop split_loop;

    -- direct-only shows up as a normal tool, NOT in the code catalog
    ut.expect(instr(l_direct, gc_prefix || 'DIRECT_ONLY')).to_be_greater_than(0);
    ut.expect(instr(l_catalog, gc_prefix || 'DIRECT_ONLY')).to_equal(0);
    -- code-only shows up in the catalog, NOT as a normal tool
    ut.expect(instr(l_catalog, gc_prefix || 'CODE_ONLY')).to_be_greater_than(0);
    ut.expect(instr(l_direct, gc_prefix || 'CODE_ONLY')).to_equal(0);

    -- runtime: code-only is callable from a program...
    l_out := run_program('const result = await callTool("' || gc_prefix || 'CODE_ONLY", {});');
    ut.expect(json_array_t(l_out).get_size).to_equal(3);
    -- ...direct-only is rejected by the allow-list even though its code is known
    l_out := run_program('const result = await callTool("' || gc_prefix || 'DIRECT_ONLY", {});');
    ut.expect(json_object_t(l_out).has('error')).to_be_true();
  end test_code_mode_access;

  -- Regression: merge used to overwrite code_mode_access with its 'both' default,
  -- silently widening a tool that had been narrowed.
  procedure test_merge_keeps_access as
    l_id     uc_ai_tools.id%type;
    l_access uc_ai_tools.code_mode_access%type;
  begin
    -- re-merging without the parameter keeps 'code' (set in setup_tools)
    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_prefix || 'CODE_ONLY'
    , p_description   => 'Code-only tool (re-merged)'
    , p_function_call => 'return test_uc_ai_ptc.f_get_employees(:parameters);'
    , p_json_schema   => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by    => gc_user
    , p_tags          => apex_t_varchar2(gc_tag)
    );
    select code_mode_access into l_access from uc_ai_tools where code = gc_prefix || 'CODE_ONLY';
    ut.expect(l_access).to_equal('code');

    -- passing it explicitly still changes it
    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code        => gc_prefix || 'CODE_ONLY'
    , p_description      => 'Code-only tool (widened)'
    , p_function_call    => 'return test_uc_ai_ptc.f_get_employees(:parameters);'
    , p_json_schema      => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_created_by       => gc_user
    , p_tags             => apex_t_varchar2(gc_tag)
    , p_code_mode_access => 'both'
    );
    select code_mode_access into l_access from uc_ai_tools where code = gc_prefix || 'CODE_ONLY';
    ut.expect(l_access).to_equal('both');
  end test_merge_keeps_access;

  -- Regression: a nested run used to clear the run context, so the outer program's
  -- next callTool failed with "used outside an active code-mode run".
  procedure test_nested_run as
    l_out clob;
    l_obj json_object_t;
  begin
    l_out := run_program(q'~
      const inner = await callTool("TEST_PTC_NESTED", {});
      const after = await callTool("TEST_PTC_GET_EMPLOYEES", {});
      const result = { inner_len: inner.length, after_len: after.length };
    ~');
    l_obj := json_object_t(l_out);
    ut.expect(l_obj.get_number('inner_len')).to_equal(3);
    ut.expect(l_obj.get_number('after_len')).to_equal(3);
  end test_nested_run;

  -- callTool is asynchronous because the tool runs in PL/SQL, not in the sandbox.
  -- A model that forgets `await` would otherwise get a promise where it expects
  -- data, so the runner inserts the missing await.
  procedure test_missing_await_repaired as
    l_out clob;
  begin
    l_out := run_program('const e = callTool("' || gc_prefix || 'GET_EMPLOYEES", {}); const result = { n: e.length };');
    ut.expect(json_object_t(l_out).get_number('n')).to_equal(3);

    -- a promise is not iterable, so this only works if the await was inserted
    l_out := run_program('let n = 0; for (const e of callTool("' || gc_prefix || 'GET_EMPLOYEES", {})) { n++; } const result = { n };');
    ut.expect(json_object_t(l_out).get_number('n')).to_equal(3);
  end test_missing_await_repaired;

  procedure test_await_rewrite_is_safe as
    l_out clob;
  begin
    -- string literals must not be rewritten
    l_out := run_program('const s = "callTool(1)"; const result = { s };');
    ut.expect(json_object_t(l_out).get_string('s')).to_equal('callTool(1)');

    -- a member call of the same name is not our callTool
    l_out := run_program('const o = { callTool: function (x) { return x * 2; } }; const result = { v: o.callTool(21) };');
    ut.expect(json_object_t(l_out).get_number('v')).to_equal(42);

    -- injecting await into a non-async arrow would not parse, so the original
    -- source runs instead and the program's own Promise.all still works
    l_out := run_program('const ps = [1,2].map(i => callTool("' || gc_prefix || 'GET_EXPENSES", { employee_id: i }));'
                         || ' const rs = await Promise.all(ps); const result = { a: rs[0][0].amount, b: rs[1][0].amount };');
    ut.expect(json_object_t(l_out).get_number('a')).to_equal(100);
    ut.expect(json_object_t(l_out).get_number('b')).to_equal(200);

    -- what a rewrite cannot reach (an alias) fails with a precise message instead
    -- of silently treating the promise as data
    l_out := run_program('const f = callTool; const p = f("' || gc_prefix || 'GET_EMPLOYEES", {}); const result = { n: p.length };');
    ut.expect(json_object_t(l_out).get_string('error')).to_be_like('%asynchronous%await callTool%');
  end test_await_rewrite_is_safe;

  -- MLE throws console output away in a dynamic context. Models are told to assign
  -- `result`, but "print the answer" is a common habit from other code-interpreter
  -- setups, so a program that only logs still gets its output back.
  procedure test_console_output_returned as
    l_out clob;
  begin
    l_out := run_program('const e = await callTool("' || gc_prefix || 'GET_EMPLOYEES", {});'
                         || ' console.log("found " + e.length + " employees");');
    ut.expect(l_out).to_be_like('%found 3 employees%');

    -- an assigned result still wins: logging must not change what comes back
    l_out := run_program('console.log("noise"); const result = { n: 1 };');
    ut.expect(json_object_t(l_out).get_number('n')).to_equal(1);
    ut.expect(instr(l_out, 'noise')).to_equal(0);
  end test_console_output_returned;

  procedure test_console_output_on_error as
    l_out clob;
    l_obj json_object_t;
  begin
    l_out := run_program('console.log("step 1 ok"); throw new Error("boom");');
    l_obj := json_object_t(l_out);
    ut.expect(l_obj.get_string('error')).to_be_like('%boom%');
    ut.expect(l_obj.get_string('console')).to_be_like('%step 1 ok%');
  end test_console_output_on_error;

  -- Regression: inner callTool()s bypassed the per-tool-call hook entirely, so
  -- hook-based authorization and auditing did not cover code mode.
  procedure test_hook_fires_for_inner_calls as
    l_out clob;
  begin
    test_uc_ai_hook_stub.reset;
    uc_ai_agents_api.set_execution_hook(gc_hook);

    l_out := run_program(q'~
      await callTool("TEST_PTC_GET_EMPLOYEES", {});
      await callTool("TEST_PTC_GET_EXPENSES", { employee_id: 1 });
      const result = { done: true };
    ~');

    ut.expect(json_object_t(l_out).get_boolean('done')).to_be_true();
    ut.expect(test_uc_ai_hook_stub.g_tool_count).to_equal(2);
    ut.expect(test_uc_ai_hook_stub.g_last_tool_code).to_equal(gc_prefix || 'GET_EXPENSES');

    uc_ai_agents_api.set_execution_hook(null);
  end test_hook_fires_for_inner_calls;

  procedure test_hook_veto_aborts_run as
    l_out clob;
  begin
    test_uc_ai_hook_stub.reset;
    test_uc_ai_hook_stub.g_tool_raise := true;
    uc_ai_agents_api.set_execution_hook(gc_hook);

    begin
      -- the program swallows the rejected callTool, but the veto must still abort
      l_out := run_program(q'~
        let r = "none";
        try { await callTool("TEST_PTC_GET_EMPLOYEES", {}); } catch (e) { r = "swallowed"; }
        const result = { r };
      ~');
      uc_ai_agents_api.set_execution_hook(null);
      ut.fail('Expected the hook veto to abort the code-mode run');
    exception
      -- @dblinter ignore(g-5040): asserting on the raised error is the point of the test
      -- @dblinter ignore(g-5080): the assertion is on sqlcode/sqlerrm; a backtrace would add nothing
      when others then
        uc_ai_agents_api.set_execution_hook(null);
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_invalid_config);
        ut.expect(sqlerrm).to_be_like('%veto%');
    end;

    ut.expect(test_uc_ai_hook_stub.g_tool_count).to_equal(1);
  end test_hook_veto_aborts_run;

end test_uc_ai_ptc;
/
