create or replace package body test_uc_ai_run_context as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-5080): the handlers here record sqlcode/sqlerrm for an assertion; a backtrace would add nothing to the test output
  -- @dblinter ignore(g-7150): the execution-hook contract fixes these signatures, so a hook that only observes leaves parameters unused
  -- @dblinter ignore(g-7330): augment_system_prompt deliberately reads the rendered prompt without changing it

  gc_echo_tool   constant varchar2(50 char) := 'TEST_RCTX_ECHO';
  gc_obj_tool    constant varchar2(50 char) := 'TEST_RCTX_OBJ';
  gc_code_tool   constant varchar2(50 char) := 'TEST_RCTX_CODE_ECHO';
  gc_code_tag    constant varchar2(50 char) := 'test_rctx_code';
  gc_parent_code constant varchar2(50 char) := 'TEST_RCTX_PARENT';
  gc_child_code  constant varchar2(50 char) := 'TEST_RCTX_CHILD';
  gc_plain_code  constant varchar2(50 char) := 'TEST_RCTX_PLAIN';
  gc_prof_agent  constant varchar2(50 char) := 'TEST_RCTX_PROF_AGENT';
  gc_doc_agent   constant varchar2(50 char) := 'TEST_RCTX_DOC_AGENT';
  gc_orch_agent  constant varchar2(50 char) := 'TEST_RCTX_ORCH_AGENT';
  gc_hand_agent  constant varchar2(50 char) := 'TEST_RCTX_HAND_AGENT';
  gc_prof        constant varchar2(50 char) := 'TEST_RCTX_PROF';
  gc_doc_prof    constant varchar2(50 char) := 'TEST_RCTX_DOC_PROF';
  gc_orch_prof   constant varchar2(50 char) := 'TEST_RCTX_ORCH_PROF';
  gc_self_hook   constant varchar2(50 char) := 'TEST_UC_AI_RUN_CONTEXT';
  gc_fail_code   constant varchar2(50 char) := 'TEST_RCTX_FAIL';

  -- Every profile below runs on OCI with nothing configured, so generate_text
  -- raises before it opens a connection. The run still renders its prompt and
  -- still writes its execution rows, which is everything these tests assert on.
  gc_offline_model constant varchar2(100 char) := 'cohere.command-r-plus';

  -- ==========================================================================
  -- Execution-hook contract (see the spec)
  -- ==========================================================================

  procedure before_execution(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_created_by  in varchar2,
    p_apex_app_id in number,
    p_session_id  in varchar2
  )
  as
  begin
    null;
  end before_execution;


  procedure after_execution(
    p_exec_id       in number,
    p_status        in varchar2,
    p_input_tokens  in number,
    p_output_tokens in number
  )
  as
  begin
    null;
  end after_execution;


  procedure augment_system_prompt(
    pio_system_prompt in out nocopy clob
  )
  as
    l_ctx  uc_ai.t_exec_context := uc_ai.get_exec_context;
    l_code uc_ai_tools.code%type;
  begin
    g_hook_count       := nvl(g_hook_count, 0) + 1;
    g_seen_prompt      := pio_system_prompt;
    g_seen_agent_code  := l_ctx.agent_code;
    g_seen_run_context := l_ctx.run_context;

    if g_probe_tool_like is null then
      return;
    end if;

    -- Run a tool from inside the live run. An orchestrator has registered its
    -- delegate tools by now, so this reaches the generated tool at exactly the
    -- stack position the provider's tool loop would reach it from.
    begin
      select code
        into l_code
        from uc_ai_tools
       where code like g_probe_tool_like
         and rownum = 1;

      g_probe_result := uc_ai_tools_api.execute_tool(
        p_tool_code => l_code,
        p_arguments => case
                         when g_probe_tool_args is not null then json_object_t(g_probe_tool_args)
                         else json_object_t()
                       end
      );
    exception
      when others then
        g_probe_error := substr(sqlerrm, 1, 4000);
    end;
  end augment_system_prompt;


  function spawn_failing_then_read return clob
  as
    l_res json_object_t;
    l_ctx uc_ai.t_exec_context;
  begin
    begin
      -- the child adds a key of its own, so the caller's bag is recognizably
      -- different from the one the failing run was bound to
      l_res := uc_ai_agents_api.execute_agent(
        p_agent_code  => gc_fail_code,
        p_session_id  => 'TEST_RCTX_FAIL_SESSION',
        p_run_context => json_object_t('{"child_only": "yes"}')
      );
    exception
      when others then
        null;  -- the sub-agent was meant to fail
    end;

    -- What the caller is left with once the failed run unwound.
    l_ctx := uc_ai.get_exec_context;
    g_ctx_after_failed_child := l_ctx.run_context;
    return nvl(l_ctx.agent_code, 'NONE');
  end spawn_failing_then_read;


  -- ==========================================================================
  -- Helpers
  -- ==========================================================================

  procedure reset_hook_state
  as
  begin
    g_hook_count       := 0;
    g_seen_prompt      := null;
    g_seen_agent_code  := null;
    g_seen_run_context := null;
    g_probe_tool_like  := null;
    g_probe_tool_args  := null;
    g_probe_result     := null;
    g_probe_error      := null;
  end reset_hook_state;


  procedure delete_tool(p_code in varchar2)
  as
    l_id uc_ai_tools.id%type;
  begin
    select id into l_id from uc_ai_tools where code = p_code;

    delete from uc_ai_tool_tags where tool_id = l_id;
    delete from uc_ai_tool_parameters where tool_id = l_id;
    delete from uc_ai_tools where id = l_id;
    commit;
  exception
    when no_data_found then
      null;
  end delete_tool;


  -- An echo tool returns its arguments verbatim, so a test can assert on exactly
  -- what the handler was given.
  procedure create_echo_tool(
    p_code             in varchar2,
    p_tag              in varchar2,
    p_code_mode_access in varchar2 default 'direct'
  )
  as
    l_id number;
  begin
    delete_tool(p_code);
    l_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code        => p_code,
      p_description      => 'Returns its arguments unchanged',
      p_function_call    => 'return :parameters;',
      p_json_schema      => json_object_t('{
        "type": "object",
        "properties": { "query": { "type": "string", "description": "Anything" } },
        "required": ["query"]
      }'),
      p_tags             => apex_t_varchar2(p_tag),
      p_code_mode_access => p_code_mode_access
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_echo_tool;


  -- A tool whose only top-level parameter is an object: Anthropic and Google
  -- unwrap that object before dispatch, so the handler sees the inner object.
  procedure create_object_tool
  as
    l_id number;
  begin
    delete_tool(gc_obj_tool);
    l_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => gc_obj_tool,
      p_description   => 'Returns its arguments unchanged, single object parameter',
      p_function_call => 'return :parameters;',
      p_json_schema   => json_object_t('{
        "type": "object",
        "properties": {
          "payload": {
            "type": "object",
            "description": "Wrapper",
            "properties": { "query": { "type": "string", "description": "Anything" } }
          }
        }
      }'),
      p_tags          => apex_t_varchar2('test_rctx')
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_object_tool;


  procedure create_workflow(
    p_code in varchar2,
    p_def  in clob
  )
  as
    l_id number;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade(p_code);
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Run context test workflow ' || p_code,
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => p_def,
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => json_object_t('{
        "type": "object",
        "properties": { "prompt": { "type": "string", "description": "Anything" } }
      }').to_clob
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_workflow;


  -- A workflow whose single PL/SQL step does nothing: it exists only so a run
  -- happens, with no provider call anywhere.
  procedure create_plain_workflow(p_code in varchar2)
  as
  begin
    create_workflow(p_code, json_object_t('{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return ''ok'';", "output_key": "done" }
      ]
    }').to_clob);
  end create_plain_workflow;


  -- A workflow whose single PL/SQL step starts a sub-agent itself: no parent
  -- execution id and a session of its own, yet still nested inside the run.
  -- The literal quotes of the generated snippet are written as #Q# so the JSON
  -- around them stays readable.
  procedure create_spawning_workflow(
    p_code       in varchar2,
    p_child_code in varchar2,
    p_child_ses  in varchar2,
    p_child_ctx  in varchar2 default null
  )
  as
    l_call clob;
    l_def  clob;
  begin
    l_call := 'return uc_ai_agents_api.execute_agent(p_agent_code => #Q#' || p_child_code
              || '#Q#, p_session_id => #Q#' || p_child_ses || '#Q#'
              || case
                   when p_child_ctx is not null
                   then ', p_run_context => json_object_t(#Q#' || replace(p_child_ctx, '"', '\"') || '#Q#)'
                 end
              || ').get_string(#Q#session_id#Q#);';

    l_def := '{"workflow_type":"sequential","steps":[{"step_type":"plsql",'
             || '"plsql_function_call":"' || l_call || '","output_key":"spawned"}]}';

    create_workflow(p_code, replace(l_def, '#Q#', ''''));
  end create_spawning_workflow;


  procedure create_profile(
    p_code   in varchar2,
    p_system in varchar2,
    p_user   in varchar2
  )
  as
    l_id number;
  begin
    delete from uc_ai_prompt_profiles where code = p_code;
    commit;
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => p_code,
      p_description            => 'Run context test profile',
      p_system_prompt_template => p_system,
      p_user_prompt_template   => p_user,
      p_provider               => uc_ai.c_provider_oci,
      p_model                  => gc_offline_model,
      p_status                 => uc_ai_prompt_profiles_api.c_status_active
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_profile;


  procedure create_profile_agent(
    p_code    in varchar2,
    p_profile in varchar2
  )
  as
    l_id number;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade(p_code);
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Run context test profile agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => p_profile,
      p_status              => uc_ai_agents_api.c_status_active,
      p_input_schema        => json_object_t('{
        "type": "object",
        "properties": { "prompt": { "type": "string", "description": "Anything" } }
      }').to_clob
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_profile_agent;


  function exec_run_context(p_exec_id in number) return clob
  as
    l_ctx clob;
  begin
    select run_context into l_ctx from uc_ai_agent_executions where id = p_exec_id;
    return l_ctx;
  end exec_run_context;


  function session_run_context(p_session_id in varchar2) return clob
  as
    l_ctx clob;
  begin
    select run_context into l_ctx from uc_ai_agent_sessions where session_id = p_session_id;
    return l_ctx;
  end session_run_context;


  -- The newest execution of p_agent_code in p_session_id.
  function last_exec_id(
    p_session_id in varchar2,
    p_agent_code in varchar2
  ) return number
  as
    l_id number;
  begin
    select max(e.id)
      into l_id
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
     where e.session_id = p_session_id
       and a.code = p_agent_code;
    return l_id;
  end last_exec_id;


  function new_session return varchar2
  as
  begin
    return uc_ai_agents_api.generate_session_id;
  end new_session;


  -- Runs an agent whose provider is not configured: the run renders its prompt,
  -- writes its rows and then fails. Returns the session id it ran under.
  procedure run_offline(
    p_agent_code  in varchar2,
    p_session_id  in varchar2,
    p_input       in json_object_t default null,
    p_run_context in json_object_t default null,
    po_error      out varchar2
  )
  as
    l_result json_object_t;
  begin
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => p_agent_code,
      p_input_parameters => p_input,
      p_session_id       => p_session_id,
      p_run_context      => p_run_context
    );
    po_error := null;
  exception
    when others then
      po_error := substr(sqlerrm, 1, 4000);
  end run_offline;


  -- Is the code-mode MLE sandbox installed for this schema? The suite skips the
  -- code-mode tests where it is not, exactly as the runner check does at runtime.
  function sandbox_available return boolean
  as
    l_cnt pls_integer;
  begin
    -- @dblinter ignore(G-8110): presence check for the sandbox runner; a scalar count is the clearest form here
    select count(*)
      into l_cnt
      from all_synonyms syn
      join all_objects obj
        on obj.owner = syn.table_owner
       and obj.object_name = syn.table_name
     where syn.owner = user
       and syn.synonym_name = uc_ai_tools_api.c_ptc_runner_synonym
       and obj.object_type = 'PACKAGE'
       and obj.status = 'VALID';
    return l_cnt > 0;
  end sandbox_available;


  function big_text(p_chars in number) return clob
  as
    l_c clob;
  begin
    sys.dbms_lob.createtemporary(l_c, true);
    <<fill>>
    for i in 1 .. ceil(p_chars / 1000) loop
      sys.dbms_lob.writeappend(l_c, 1000, rpad('x', 1000, 'x'));
    end loop fill;
    return l_c;
  end big_text;


  -- ==========================================================================
  -- Fixture
  -- ==========================================================================

  procedure setup
  as
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    uc_ai.clear_exec_context;
    uc_ai_agents_api.set_execution_hook(null);

    -- executions commit autonomously and survive rollback, so purge by pattern
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_RCTX%');
    delete from uc_ai_prompt_profiles where code like 'TEST_RCTX%';
    commit;

    create_echo_tool(gc_echo_tool, 'test_rctx');
    create_object_tool;
    create_echo_tool(gc_code_tool, gc_code_tag, 'both');

    create_profile(gc_prof,      'doc={document_id} locale={locale}', 'q={question}');
    create_profile(gc_doc_prof,  'doc={document_id}',                 'hello');
    create_profile(gc_orch_prof, 'orchestrate doc={document_id}',     'go');
  end setup;


  procedure teardown
  as
  begin
    uc_ai.clear_exec_context;
    uc_ai_agents_api.set_execution_hook(null);
    delete_tool(gc_echo_tool);
    delete_tool(gc_obj_tool);
    delete_tool(gc_code_tool);
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_RCTX%');
    delete from uc_ai_prompt_profiles where code like 'TEST_RCTX%';
    commit;
    uc_ai.reset_globals;
  end teardown;


  procedure cleanup_context
  as
  begin
    uc_ai.clear_exec_context;
    uc_ai_agents_api.set_execution_hook(null);
    reset_hook_state;
    uc_ai.reset_globals;
  end cleanup_context;


  -- ==========================================================================
  -- The bag as a value
  -- ==========================================================================

  procedure reads_scalar_values
  as
    l_bag clob := '{"document_id": "7", "page": 12, "draft": true}';
  begin
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
    ut.expect(uc_ai.run_context_value(l_bag, 'page')).to_equal('12');
    ut.expect(uc_ai.run_context_value(l_bag, 'draft')).to_equal('true');
  end reads_scalar_values;


  procedure reads_missing_values
  as
  begin
    ut.expect(uc_ai.run_context_value('{"a": "1"}', 'b')).to_be_null();
    ut.expect(uc_ai.run_context_value(null, 'a')).to_be_null();
    ut.expect(uc_ai.run_context_value('{"a": "1"}', null)).to_be_null();
    -- a malformed bag must not raise: a tool call or a memory read would die with it
    ut.expect(uc_ai.run_context_value('not json at all', 'a')).to_be_null();
    ut.expect(uc_ai.run_context_value('{"a": null}', 'a')).to_be_null();
    ut.expect(uc_ai.run_context_value(empty_clob(), 'a')).to_be_null();
  end reads_missing_values;


  procedure reads_structured_values
  as
  begin
    -- an object or an array comes back serialized, so two turns can be compared
    ut.expect(uc_ai.run_context_value('{"a": {"x": 1, "y": "z"}}', 'a')).to_equal('{"x":1,"y":"z"}');
    ut.expect(uc_ai.run_context_value('{"a": [1, 2, 3]}', 'a')).to_equal('[1,2,3]');
    ut.expect(uc_ai.run_context_value('{"a": {"b": {"c": {"d": "deep"}}}}', 'a'))
      .to_equal('{"b":{"c":{"d":"deep"}}}');
    -- a string is NOT re-quoted
    ut.expect(uc_ai.run_context_value('{"a": "plain"}', 'a')).to_equal('plain');
  end reads_structured_values;


  procedure reads_non_object_bags
  as
  begin
    ut.expect(uc_ai.run_context_value('[1, 2, 3]', 'a')).to_be_null();
    ut.expect(uc_ai.run_context_value('"just a string"', 'a')).to_be_null();
    ut.expect(uc_ai.run_context_value('42', 'a')).to_be_null();
    ut.expect(uc_ai.run_context_value('{}', 'a')).to_be_null();
  end reads_non_object_bags;


  procedure caps_a_long_value
  as
    l_bag clob;
  begin
    -- A value far past the varchar2 limit must come back capped, not raise: it
    -- would otherwise take down every run that carries it.
    l_bag := '{"big": "' || big_text(40000) || '"}';
    ut.expect(length(uc_ai.run_context_value(l_bag, 'big'))).to_equal(4000);

    -- the same for an object value, which is serialized before it is capped
    l_bag := '{"big": {"inner": "' || big_text(40000) || '"}}';
    ut.expect(length(uc_ai.run_context_value(l_bag, 'big'))).to_equal(4000);
  end caps_a_long_value;


  -- ==========================================================================
  -- What a tool receives
  -- ==========================================================================

  procedure tool_receives_context
  as
    l_result clob;
    l_args   json_object_t;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "invoice terms"}'),
      p_run_context => '{"document_id": "7", "tenant_id": "ACME"}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_string('document_id')).to_equal('7');
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_string('tenant_id')).to_equal('ACME');
  end tool_receives_context;


  procedure tool_receives_empty_context
  as
    l_result clob;
    l_args   json_object_t;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => gc_echo_tool,
      p_arguments => json_object_t('{"query": "invoice terms"}')
    );

    l_args := json_object_t(l_result);
    -- always present, so a handler can read it without a null check
    ut.expect(l_args.has(uc_ai.c_run_context_key)).to_be_true();
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_size).to_equal(0);
  end tool_receives_empty_context;


  procedure tool_context_is_not_forgeable
  as
    l_result clob;
    l_args   json_object_t;
  begin
    -- the model tries to widen its own scope
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "x", "' || uc_ai.c_run_context_key || '": {"document_id": "42"}}'),
      p_run_context => '{"document_id": "7"}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_string('document_id')).to_equal('7');
  end tool_context_is_not_forgeable;


  procedure tool_context_on_unwrapped_object
  as
    l_result clob;
    l_args   json_object_t;
  begin
    -- Anthropic and Google hand the INNER object to execute_tool
    ut.expect(uc_ai_tools_api.get_tools_object_param_name(gc_obj_tool)).to_equal('payload');

    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_obj_tool,
      p_arguments   => json_object_t('{"query": "invoice terms"}'),
      p_run_context => '{"document_id": "7"}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.get_string('query')).to_equal('invoice terms');
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_string('document_id')).to_equal('7');
  end tool_context_on_unwrapped_object;


  procedure tool_arguments_survive
  as
    l_result clob;
    l_args   json_object_t;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "invoice terms"}'),
      p_run_context => '{"document_id": "7"}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.get_string('query')).to_equal('invoice terms');
    ut.expect(l_args.get_size).to_equal(2);
  end tool_arguments_survive;


  procedure reserved_parameter_name_rejected
  as
    l_id number;
  begin
    delete_tool('TEST_RCTX_RESERVED');
    begin
      l_id := uc_ai_tools_api.create_tool_from_schema(
        p_tool_code     => 'TEST_RCTX_RESERVED',
        p_description   => 'Declares the reserved key as a parameter',
        p_function_call => 'return :parameters;',
        p_json_schema   => json_object_t('{
          "type": "object",
          "properties": { "' || uc_ai.c_run_context_key || '": { "type": "string", "description": "mine" } }
        }')
      );
      ut.fail('Expected the reserved parameter name to be rejected, got tool id ' || l_id);
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_invalid_config);
        ut.expect(sqlerrm).to_be_like('%reserved%');
    end;
    rollback;
    delete_tool('TEST_RCTX_RESERVED');
  end reserved_parameter_name_rejected;


  procedure tool_receives_structured_context
  as
    l_result clob;
    l_ctx    json_object_t;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "x"}'),
      p_run_context => '{"doc": {"id": 7, "tags": ["a", "b"]}, "ids": [1, 2, 3]}'
    );

    l_ctx := json_object_t(l_result).get_object(uc_ai.c_run_context_key);
    ut.expect(l_ctx.get_object('doc').get_number('id')).to_equal(7);
    ut.expect(l_ctx.get_object('doc').get_array('tags').get_size).to_equal(2);
    ut.expect(l_ctx.get_array('ids').get_size).to_equal(3);
  end tool_receives_structured_context;


  procedure tool_receives_empty_bag
  as
    l_result clob;
    l_args   json_object_t;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "x"}'),
      p_run_context => '{}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.has(uc_ai.c_run_context_key)).to_be_true();
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_size).to_equal(0);
  end tool_receives_empty_bag;


  procedure tool_receives_broken_bag
  as
    procedure expect_empty(p_bag in clob)
    as
      l_res  clob;
      l_args json_object_t;
    begin
      l_res := uc_ai_tools_api.execute_tool(
        p_tool_code   => gc_echo_tool,
        p_arguments   => json_object_t('{"query": "x"}'),
        p_run_context => p_bag
      );
      l_args := json_object_t(l_res);
      ut.expect(l_args.has(uc_ai.c_run_context_key)).to_be_true();
      ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_size).to_equal(0);
    end expect_empty;
  begin
    -- none of these may break the tool call
    expect_empty('not json at all');
    expect_empty('[1, 2, 3]');
    expect_empty('"a string"');
    expect_empty(empty_clob());
  end tool_receives_broken_bag;


  procedure tool_receives_large_context
  as
    l_bag    clob;
    l_result clob;
    l_got    clob;
  begin
    -- 20 KB, not more: exec_function_call binds the whole arguments JSON through
    -- an apex_plugin_util.t_bind, whose value is a varchar2. Anything past 32767
    -- characters of arguments fails there, run context or not.
    l_bag := '{"document_id": "7", "big": "' || big_text(20000) || '"}';

    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "x"}'),
      p_run_context => l_bag
    );

    -- the tool gets the whole bag; only UC AI's own one-key reads are capped
    l_got := json_object_t(l_result).get_object(uc_ai.c_run_context_key).get_clob('big');
    ut.expect(sys.dbms_lob.getlength(l_got)).to_equal(20000);
    ut.expect(json_object_t(l_result).get_object(uc_ai.c_run_context_key).get_string('document_id'))
      .to_equal('7');
  end tool_receives_large_context;


  procedure tool_receives_special_characters
  as
    l_value varchar2(200 char);
    l_bag   json_object_t := json_object_t();
    l_result clob;
  begin
    l_value := 'say ' || chr(34) || 'hi' || chr(34) || ' \ ' || chr(39)
               || chr(10) || unistr('\00FC\20AC\4E2D');
    l_bag.put('label', l_value);

    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "x"}'),
      p_run_context => l_bag.to_clob
    );

    ut.expect(json_object_t(l_result).get_object(uc_ai.c_run_context_key).get_string('label'))
      .to_equal(l_value);
  end tool_receives_special_characters;


  procedure tool_context_key_collides_with_parameter
  as
    l_result clob;
    l_args   json_object_t;
  begin
    -- "query" is a declared tool parameter AND a run-context key: the two live
    -- in different places, so neither hides the other
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => json_object_t('{"query": "from the model"}'),
      p_run_context => '{"query": "from the run context", "document_id": "7"}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.get_string('query')).to_equal('from the model');
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_string('query'))
      .to_equal('from the run context');
  end tool_context_key_collides_with_parameter;


  procedure tool_called_without_arguments
  as
    l_result clob;
    l_args   json_object_t;
  begin
    -- a tool with no parameters is called with nothing at all
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_echo_tool,
      p_arguments   => null,
      p_run_context => '{"document_id": "7"}'
    );

    l_args := json_object_t(l_result);
    ut.expect(l_args.get_object(uc_ai.c_run_context_key).get_string('document_id')).to_equal('7');
    ut.expect(l_args.get_size).to_equal(1);
  end tool_called_without_arguments;


  procedure agent_tool_threads_settings_context
  as
    l_settings uc_ai_settings.t_settings;
    l_result   clob;
  begin
    uc_ai.clear_exec_context;
    l_settings := uc_ai_settings.build_from_globals(p_run_context => '{"document_id": "7"}');

    -- the route every provider takes for a normal tool call
    l_result := uc_ai_tools_api.execute_agent_tool(
      p_tool_code => gc_echo_tool,
      p_arguments => json_object_t('{"query": "x"}'),
      p_settings  => l_settings
    );

    ut.expect(json_object_t(l_result).get_object(uc_ai.c_run_context_key).get_string('document_id'))
      .to_equal('7');
  end agent_tool_threads_settings_context;


  -- ==========================================================================
  -- Binding a run and a conversation
  -- ==========================================================================

  procedure persists_on_execution_and_session
  as
    l_result  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai.run_context_value(exec_run_context(l_result.get_number('execution_id')), 'document_id'))
      .to_equal('7');
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'document_id')).to_equal('7');
  end persists_on_execution_and_session;


  procedure later_turn_inherits_session_context
  as
    l_first   json_object_t;
    l_second  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_first := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    -- the front end does not repeat the binding on the follow-up turn
    l_second := uc_ai_agents_api.execute_agent(
      p_agent_code => gc_plain_code,
      p_session_id => l_session
    );

    ut.expect(uc_ai.run_context_value(exec_run_context(l_second.get_number('execution_id')), 'document_id'))
      .to_equal('7');
  end later_turn_inherits_session_context;


  procedure later_turn_may_repeat_value
  as
    l_first   json_object_t;
    l_second  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_first := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    -- an APEX page naturally re-sends the same binding every turn
    l_second := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_second.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai.run_context_value(exec_run_context(l_second.get_number('execution_id')), 'document_id'))
      .to_equal('7');
  end later_turn_may_repeat_value;


  procedure later_turn_may_add_key
  as
    l_first   json_object_t;
    l_second  json_object_t;
    l_bag     clob;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_first := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    l_second := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"locale": "de"}')
    );

    l_bag := exec_run_context(l_second.get_number('execution_id'));
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
    ut.expect(uc_ai.run_context_value(l_bag, 'locale')).to_equal('de');

    -- the addition is bound to the session too
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'locale')).to_equal('de');
  end later_turn_may_add_key;


  procedure later_turn_may_not_change_key
  as
    l_first   json_object_t;
    l_second  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_first := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    begin
      l_second := uc_ai_agents_api.execute_agent(
        p_agent_code  => gc_plain_code,
        p_session_id  => l_session,
        p_run_context => json_object_t('{"document_id": "8"}')
      );
      ut.fail('Expected -20507: a bound session must not be re-targeted');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_run_context_conflict);
    end;

    -- the binding is unchanged
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'document_id')).to_equal('7');
  end later_turn_may_not_change_key;


  procedure null_binding_can_be_set_later
  as
    l_first   json_object_t;
    l_second  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    -- a front end that sends the key before it knows the value
    l_first := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": null}')
    );
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'document_id')).to_be_null();

    -- JSON null is not a binding, so the real value may still arrive
    l_second := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(uc_ai.run_context_value(exec_run_context(l_second.get_number('execution_id')), 'document_id'))
      .to_equal('7');
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'document_id')).to_equal('7');
  end null_binding_can_be_set_later;


  procedure null_from_a_later_turn_is_ignored
  as
    l_first   json_object_t;
    l_second  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_first := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    -- a null carries no value, so it neither clears nor conflicts with the binding
    l_second := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_plain_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": null}')
    );

    ut.expect(l_second.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai.run_context_value(exec_run_context(l_second.get_number('execution_id')), 'document_id'))
      .to_equal('7');
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'document_id')).to_equal('7');
  end null_from_a_later_turn_is_ignored;


  procedure conflict_across_three_turns
  as
    l_res     json_object_t;
    l_bag     clob;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_plain_code);

    l_res := uc_ai_agents_api.execute_agent(
      p_agent_code => gc_plain_code, p_session_id => l_session,
      p_run_context => json_object_t('{"document_id": "7"}'));

    l_res := uc_ai_agents_api.execute_agent(
      p_agent_code => gc_plain_code, p_session_id => l_session,
      p_run_context => json_object_t('{"locale": "de"}'));

    -- turn 3 re-targets the key bound on turn 1
    begin
      l_res := uc_ai_agents_api.execute_agent(
        p_agent_code => gc_plain_code, p_session_id => l_session,
        p_run_context => json_object_t('{"document_id": "8"}'));
      ut.fail('Expected -20507 for the key bound on turn 1');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_run_context_conflict);
    end;

    -- turn 4 re-targets the key added on turn 2
    begin
      l_res := uc_ai_agents_api.execute_agent(
        p_agent_code => gc_plain_code, p_session_id => l_session,
        p_run_context => json_object_t('{"locale": "fr"}'));
      ut.fail('Expected -20507 for the key added on turn 2');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_run_context_conflict);
    end;

    -- nothing moved
    l_bag := session_run_context(l_session);
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
    ut.expect(uc_ai.run_context_value(l_bag, 'locale')).to_equal('de');
  end conflict_across_three_turns;


  procedure nested_run_inherits
  as
    l_result   json_object_t;
    l_session  varchar2(255 char) := new_session;
    l_child_id number;
    l_bag      clob;
  begin
    create_plain_workflow(gc_child_code);

    -- a workflow step that runs the child agent, so a nested execution happens
    create_workflow(gc_parent_code, json_object_t('{
      "workflow_type": "sequential",
      "steps": [
        {
          "agent_code": "TEST_RCTX_CHILD",
          "input_mapping": { "passthrough": "$.input" },
          "output_key": "child"
        }
      ]
    }').to_clob);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_parent_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_child_id := last_exec_id(l_session, gc_child_code);
    l_bag := exec_run_context(l_child_id);
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
  end nested_run_inherits;


  procedure nested_run_with_own_session_inherits
  as
    l_result    json_object_t;
    l_session   varchar2(255 char) := new_session;
    l_child_ses varchar2(255 char) := new_session;
    l_bag       clob;
  begin
    create_plain_workflow(gc_child_code);

    create_spawning_workflow(gc_parent_code, gc_child_code, l_child_ses);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_parent_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_bag := exec_run_context(last_exec_id(l_child_ses, gc_child_code));
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
  end nested_run_with_own_session_inherits;


  procedure nested_run_may_add_key
  as
    l_result    json_object_t;
    l_session   varchar2(255 char) := new_session;
    l_child_ses varchar2(255 char) := new_session;
    l_bag       clob;
  begin
    create_plain_workflow(gc_child_code);

    create_spawning_workflow(gc_parent_code, gc_child_code, l_child_ses, '{"step": "one"}');

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_parent_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_bag := exec_run_context(last_exec_id(l_child_ses, gc_child_code));
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
    ut.expect(uc_ai.run_context_value(l_bag, 'step')).to_equal('one');

    -- the parent's own binding is untouched
    ut.expect(uc_ai.run_context_value(session_run_context(l_session), 'step')).to_be_null();
  end nested_run_may_add_key;


  procedure nested_run_may_not_override_key
  as
    l_result    json_object_t;
    l_session   varchar2(255 char) := new_session;
    l_child_ses varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_child_code);

    create_spawning_workflow(gc_parent_code, gc_child_code, l_child_ses, '{"document_id": "8"}');

    begin
      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code  => gc_parent_code,
        p_session_id  => l_session,
        p_run_context => json_object_t('{"document_id": "7"}')
      );
      ut.fail('Expected the nested run to be refused: it re-targets an inherited key');
    exception
      when others then
        -- the workflow wraps the step error, so match the message
        ut.expect(sqlerrm).to_be_like('%' || to_char(uc_ai_error.c_err_run_context_conflict) || '%');
    end;

    -- and the sub-agent never ran
    ut.expect(last_exec_id(l_child_ses, gc_child_code)).to_be_null();
  end nested_run_may_not_override_key;


  procedure failed_nested_run_restores_context
  as
    l_result  json_object_t;
    l_session varchar2(255 char) := new_session;
  begin
    -- a sub-agent that always fails
    create_workflow(gc_fail_code, json_object_t('{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql",
          "plsql_function_call": "raise_application_error(-20999, ''boom''); return ''x'';",
          "output_key": "never" }
      ]
    }').to_clob);

    -- a parent step that runs it, swallows the failure and then looks at the
    -- execution context it is left with
    create_workflow(gc_parent_code, json_object_t('{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql",
          "plsql_function_call": "return test_uc_ai_run_context.spawn_failing_then_read();",
          "output_key": "left_with" }
      ]
    }').to_clob);

    g_ctx_after_failed_child := null;

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code  => gc_parent_code,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    -- the failed sub-agent put its context back before unwinding, so the parent
    -- still runs bound to document 7 ...
    ut.expect(uc_ai.run_context_value(g_ctx_after_failed_child, 'document_id')).to_equal('7');
    -- ... and the key the failed run added did not survive it
    ut.expect(uc_ai.run_context_value(g_ctx_after_failed_child, 'child_only')).to_be_null();
  end failed_nested_run_restores_context;


  -- ==========================================================================
  -- Prompt placeholders
  -- ==========================================================================

  procedure context_fills_placeholder
  as
    l_err     varchar2(4000 char);
    l_session varchar2(255 char) := new_session;
  begin
    create_profile_agent(gc_prof_agent, gc_prof);
    reset_hook_state;
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    run_offline(
      p_agent_code  => gc_prof_agent,
      p_session_id  => l_session,
      p_input       => json_object_t('{"question": "what?"}'),
      p_run_context => json_object_t('{"document_id": "7", "locale": "de"}'),
      po_error      => l_err
    );

    -- the prompt was rendered before the provider was reached
    ut.expect(g_hook_count).to_equal(1);
    ut.expect(sys.dbms_lob.substr(g_seen_prompt, 4000, 1)).to_equal('doc=7 locale=de');
  end context_fills_placeholder;


  procedure input_parameter_wins
  as
    l_err     varchar2(4000 char);
    l_session varchar2(255 char) := new_session;
  begin
    create_profile_agent(gc_prof_agent, gc_prof);
    reset_hook_state;
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    run_offline(
      p_agent_code  => gc_prof_agent,
      p_session_id  => l_session,
      p_input       => json_object_t('{"question": "what?", "document_id": "99"}'),
      p_run_context => json_object_t('{"document_id": "7", "locale": "de"}'),
      po_error      => l_err
    );

    ut.expect(g_hook_count).to_equal(1);
    ut.expect(sys.dbms_lob.substr(g_seen_prompt, 4000, 1)).to_equal('doc=99 locale=de');
  end input_parameter_wins;


  procedure unsupplied_placeholder_raises
  as
    l_err     varchar2(4000 char);
    l_session varchar2(255 char) := new_session;
  begin
    create_profile_agent(gc_prof_agent, gc_prof);
    reset_hook_state;
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    -- neither the input parameters nor the run context supply document_id
    run_offline(
      p_agent_code  => gc_prof_agent,
      p_session_id  => l_session,
      p_input       => json_object_t('{"question": "what?", "locale": "de"}'),
      po_error      => l_err
    );

    ut.expect(l_err).to_be_like('%' || to_char(uc_ai_error.c_err_missing_placeholder) || '%');
    ut.expect(l_err).to_be_like('%document_id%');
    -- rendering never happened
    ut.expect(g_hook_count).to_equal(0);
  end unsupplied_placeholder_raises;


  procedure orchestrator_prompt_uses_context
  as
    l_err     varchar2(4000 char);
    l_id      number;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_child_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_orch_agent);
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_orch_agent,
      p_description          => 'Run context test orchestrator',
      p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
      p_orchestration_config => json_object_t('{
        "pattern_type": "orchestrator",
        "orchestrator_profile_code": "' || gc_orch_prof || '",
        "delegate_agents": ["' || gc_child_code || '"],
        "max_delegations": 2
      }').to_clob,
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

    reset_hook_state;
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    run_offline(
      p_agent_code  => gc_orch_agent,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}'),
      po_error      => l_err
    );

    ut.expect(g_hook_count).to_equal(1);
    ut.expect(sys.dbms_lob.substr(g_seen_prompt, 4000, 1)).to_equal('orchestrate doc=7');
  end orchestrator_prompt_uses_context;


  procedure workflow_step_input_unchanged
  as
    l_result  json_object_t;
    l_input   clob;
    l_exec_id number;
    l_session varchar2(255 char) := new_session;
  begin
    create_plain_workflow(gc_child_code);
    create_workflow(gc_parent_code, json_object_t('{
      "workflow_type": "sequential",
      "steps": [
        {
          "agent_code": "TEST_RCTX_CHILD",
          "input_mapping": { "topic": "{$.input.topic}" },
          "output_key": "child"
        }
      ]
    }').to_clob);

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_parent_code,
      p_session_id       => l_session,
      p_input_parameters => json_object_t('{"topic": "invoices"}'),
      p_run_context      => json_object_t('{"document_id": "7"}')
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    -- the step input is exactly what the mapping asked for: the run context is
    -- for prompts and tools, not for the workflow state
    l_exec_id := last_exec_id(l_session, gc_child_code);
    select input_parameters
      into l_input
      from uc_ai_agent_executions
     where id = l_exec_id;

    ut.expect(json_object_t(l_input).get_string('topic')).to_equal('invoices');
    ut.expect(json_object_t(l_input).has('document_id')).to_be_false();
  end workflow_step_input_unchanged;


  -- ==========================================================================
  -- Generated tools
  -- ==========================================================================

  procedure context_is_ambient_during_a_run
  as
    l_err     varchar2(4000 char);
    l_session varchar2(255 char) := new_session;
    l_after   uc_ai.t_exec_context;
  begin
    -- Everything the engine generates - the orchestrator's delegate tools, the
    -- handoff transfer tools - reads the run context from the ambient execution
    -- context rather than from an argument. This is that contract.
    create_profile_agent(gc_doc_agent, gc_doc_prof);
    reset_hook_state;
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    run_offline(
      p_agent_code  => gc_doc_agent,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}'),
      po_error      => l_err
    );

    ut.expect(g_seen_agent_code).to_equal(gc_doc_agent);
    ut.expect(uc_ai.run_context_value(g_seen_run_context, 'document_id')).to_equal('7');

    -- and it is gone again once the run unwound
    l_after := uc_ai.get_exec_context;
    ut.expect(l_after.run_context).to_be_null();
  end context_is_ambient_during_a_run;


  procedure orchestrator_delegate_inherits
  as
    l_err     varchar2(4000 char);
    l_id      number;
    l_session varchar2(255 char) := new_session;
    l_bag     clob;
  begin
    create_plain_workflow(gc_child_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_orch_agent);
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_orch_agent,
      p_description          => 'Run context test orchestrator',
      p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
      p_orchestration_config => json_object_t('{
        "pattern_type": "orchestrator",
        "orchestrator_profile_code": "' || gc_orch_prof || '",
        "delegate_agents": ["' || gc_child_code || '"],
        "max_delegations": 2
      }').to_clob,
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

    reset_hook_state;
    -- The delegate tools exist by the time the prompt hook fires, so the hook
    -- calls the generated tool from the same place the provider's tool loop
    -- would - no model needed to pick it.
    g_probe_tool_like := gc_child_code || '_TOOL_%';
    g_probe_tool_args := '{"prompt": "do the thing"}';
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    run_offline(
      p_agent_code  => gc_orch_agent,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}'),
      po_error      => l_err
    );

    ut.expect(g_probe_error).to_be_null();
    ut.expect(g_probe_result).to_be_not_null();

    -- the delegate ran as a nested execution and carried the binding
    l_bag := exec_run_context(last_exec_id(l_session, gc_child_code));
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
  end orchestrator_delegate_inherits;


  procedure handoff_child_inherits
  as
    l_err     varchar2(4000 char);
    l_id      number;
    l_session varchar2(255 char) := new_session;
    l_bag     clob;
  begin
    create_profile_agent(gc_doc_agent, gc_doc_prof);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_hand_agent);
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_hand_agent,
      p_description          => 'Run context test handoff',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => json_object_t('{
        "pattern_type": "handoff",
        "initial_agent_code": "' || gc_doc_agent || '",
        "handoff_agents": [
          {"agent_code": "' || gc_doc_agent || '", "description": "The only participant"}
        ],
        "max_handoffs": 1
      }').to_clob,
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

    reset_hook_state;
    uc_ai_agents_api.set_execution_hook(gc_self_hook);

    -- the wrapper hands its context down to the participant it starts
    run_offline(
      p_agent_code  => gc_hand_agent,
      p_session_id  => l_session,
      p_run_context => json_object_t('{"document_id": "7"}'),
      po_error      => l_err
    );

    l_bag := exec_run_context(last_exec_id(l_session, gc_doc_agent));
    ut.expect(uc_ai.run_context_value(l_bag, 'document_id')).to_equal('7');
    -- and the participant's own prompt was filled from it
    ut.expect(sys.dbms_lob.substr(g_seen_prompt, 4000, 1)).to_equal('doc=7');
  end handoff_child_inherits;


  -- ==========================================================================
  -- Code mode
  -- ==========================================================================

  procedure code_mode_tool_receives_context
  as
    l_settings uc_ai_settings.t_settings;
    l_args     json_object_t := json_object_t();
    l_result   clob;
  begin
    if not sandbox_available then
      -- no MLE sandbox in this database: code mode cannot run at all
      ut.expect(1).to_equal(1);
      return;
    end if;

    uc_ai.reset_globals;
    uc_ai.clear_exec_context;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags    := apex_t_varchar2(gc_code_tag);
    l_settings := uc_ai_settings.build_from_globals(p_run_context => '{"document_id": "7"}');

    l_args.put('code', 'const result = await callTool("' || gc_code_tool || '", { query: "x" });');
    l_result := uc_ai_tools_api.execute_agent_tool(
      uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);

    -- the program echoed the arguments the handler was given
    ut.expect(l_result).to_be_like('%' || uc_ai.c_run_context_key || '%');
    ut.expect(json_object_t(l_result).get_object(uc_ai.c_run_context_key).get_string('document_id'))
      .to_equal('7');
  end code_mode_tool_receives_context;


  procedure code_mode_cannot_forge_context
  as
    l_settings uc_ai_settings.t_settings;
    l_args     json_object_t := json_object_t();
    l_result   clob;
  begin
    if not sandbox_available then
      ut.expect(1).to_equal(1);
      return;
    end if;

    uc_ai.reset_globals;
    uc_ai.clear_exec_context;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags    := apex_t_varchar2(gc_code_tag);
    l_settings := uc_ai_settings.build_from_globals(p_run_context => '{"document_id": "7"}');

    -- the program writes its own _ctx into the arguments
    l_args.put('code', 'const result = await callTool("' || gc_code_tool
      || '", { query: "x", ' || uc_ai.c_run_context_key || ': { document_id: "42" } });');
    l_result := uc_ai_tools_api.execute_agent_tool(
      uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);

    ut.expect(json_object_t(l_result).get_object(uc_ai.c_run_context_key).get_string('document_id'))
      .to_equal('7');
  end code_mode_cannot_forge_context;


  -- ==========================================================================
  -- Threading through the settings record
  -- ==========================================================================

  procedure settings_carry_standalone_context
  as
    l_settings uc_ai_settings.t_settings;
  begin
    uc_ai.clear_exec_context;
    l_settings := uc_ai_settings.build_from_globals(p_run_context => '{"document_id": "7"}');
    ut.expect(uc_ai.run_context_value(l_settings.ctx_run_context, 'document_id')).to_equal('7');
  end settings_carry_standalone_context;


  procedure agent_context_wins_over_caller
  as
    l_settings uc_ai_settings.t_settings;
    l_ctx      uc_ai.t_exec_context;
  begin
    l_ctx.agent_id    := 1;
    l_ctx.agent_code  := 'TEST_RCTX_FAKE';
    l_ctx.run_context := '{"document_id": "7"}';
    uc_ai.set_exec_context(l_ctx);

    -- a nested generate_text must not be able to widen or re-target the run
    l_settings := uc_ai_settings.build_from_globals(p_run_context => '{"document_id": "8"}');
    ut.expect(uc_ai.run_context_value(l_settings.ctx_run_context, 'document_id')).to_equal('7');
  end agent_context_wins_over_caller;


  procedure config_settings_carry_context
  as
    l_settings uc_ai_settings.t_settings;
    l_ctx      uc_ai.t_exec_context;
  begin
    l_ctx.agent_id    := 1;
    l_ctx.agent_code  := 'TEST_RCTX_FAKE';
    l_ctx.run_context := '{"document_id": "7"}';
    uc_ai.set_exec_context(l_ctx);

    l_settings := uc_ai_settings.build_from_config(
      p_config   => json_object_t('{"g_enable_tools": true}'),
      p_provider => uc_ai.c_provider_openai
    );

    -- the execution context is not configuration, it describes who is running
    ut.expect(l_settings.ctx_agent_code).to_equal('TEST_RCTX_FAKE');
    ut.expect(uc_ai.run_context_value(l_settings.ctx_run_context, 'document_id')).to_equal('7');
  end config_settings_carry_context;


  procedure config_settings_carry_standalone_context
  as
    l_settings uc_ai_settings.t_settings;
  begin
    uc_ai.clear_exec_context;

    l_settings := uc_ai_settings.build_from_config(
      p_config      => json_object_t('{"g_enable_tools": true}'),
      p_provider    => uc_ai.c_provider_openai,
      p_run_context => '{"document_id": "7"}'
    );

    ut.expect(l_settings.ctx_agent_code).to_be_null();
    ut.expect(uc_ai.run_context_value(l_settings.ctx_run_context, 'document_id')).to_equal('7');
  end config_settings_carry_standalone_context;

end test_uc_ai_run_context;
/
