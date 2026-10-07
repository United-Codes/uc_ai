create or replace package body test_uc_ai_agent_prompt_addendum as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its code; a backtrace adds nothing

  gc_prof_code    constant varchar2(50 char) := 'TEST_PADD_PROF';
  gc_tool_prof    constant varchar2(50 char) := 'TEST_PADD_TOOL_PROF';
  gc_orch_prof    constant varchar2(50 char) := 'TEST_PADD_ORCH_PROF';
  gc_agent        constant varchar2(50 char) := 'TEST_PADD_AGENT';
  gc_tool_agent   constant varchar2(50 char) := 'TEST_PADD_TOOL_AGENT';
  gc_orch_agent   constant varchar2(50 char) := 'TEST_PADD_ORCH_AGENT';
  gc_flow_agent   constant varchar2(50 char) := 'TEST_PADD_FLOW_AGENT';
  gc_mem_agent    constant varchar2(50 char) := 'TEST_PADD_MEM_AGENT';
  gc_echo_tool    constant varchar2(50 char) := 'TEST_PADD_ECHO';
  gc_tool_tag     constant varchar2(50 char) := 'test_padd';

  -- Named on every profile so no provider asks uc_ai_get_key for a key. The mock
  -- records the name; nothing resolves it.
  gc_credential   constant varchar2(50 char) := 'PADD_TEST_CREDENTIAL';

  gc_system       constant varchar2(100 char) := 'You are a test assistant.';
  gc_addendum     constant varchar2(200 char) := 'WIDGET PROTOCOL: answer with one word.';

  -- ==========================================================================
  -- Helpers
  -- ==========================================================================

  -- Chat Completions, not the Responses API: the request shape is simpler to read
  function profile_config(p_with_tools in boolean) return clob
  as
    l_config json_object_t := json_object_t();
  begin
    l_config.put('g_apex_web_credential', gc_credential);
    l_config.put('openai', json_object_t('{"g_use_responses_api":false}'));
    if p_with_tools then
      l_config.put('g_enable_tools', true);
      l_config.put('g_tool_tags', json_array_t('["' || gc_tool_tag || '"]'));
    end if;
    return l_config.to_clob;
  end profile_config;


  procedure create_profile(
    p_code       in varchar2,
    p_with_tools in boolean default false
  )
  as
    l_id number;
  begin
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => p_code,
      p_description            => 'Prompt addendum test profile',
      p_system_prompt_template => gc_system,
      p_user_prompt_template   => 'hello',
      p_provider               => uc_ai.c_provider_openai,
      p_model                  => 'gpt-4o-mini',
      p_model_config_json      => profile_config(p_with_tools),
      p_status                 => uc_ai_prompt_profiles_api.c_status_active
    );
    ut.expect(l_id, p_code || ' created').to_be_not_null();
  end create_profile;


  procedure create_profile_agent(
    p_code    in varchar2,
    p_profile in varchar2
  )
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Prompt addendum test agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => p_profile,
      p_status              => uc_ai_agents_api.c_status_active
    );
    ut.expect(l_id, p_code || ' created').to_be_not_null();
  end create_profile_agent;


  procedure delete_echo_tool
  as
  begin
    -- the tag and parameter rows go with the tool: both foreign keys cascade
    delete from uc_ai_tools where code = gc_echo_tool;
  end delete_echo_tool;


  procedure delete_fixtures
  as
  begin
    -- executions commit autonomously and survive a rollback, so delete by pattern
    delete from uc_ai_memory_config where agent_code like 'TEST_PADD%';
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_PADD%');
    delete from uc_ai_prompt_profiles where code like 'TEST_PADD%';
    delete_echo_tool;
    commit;
  end delete_fixtures;


  /*
   * An OpenAI Chat Completions answer with plain text.
   */
  function text_response(p_text in varchar2) return clob
  as
    l_body json_object_t := json_object_t();
  begin
    l_body.put('id', 'chatcmpl-padd');
    l_body.put('object', 'chat.completion');
    l_body.put('model', 'gpt-4o-mini');
    l_body.put('choices', json_array_t(
      '[{"index":0,"message":{"role":"assistant","content":"' || p_text || '"},"finish_reason":"stop"}]'));
    l_body.put('usage', json_object_t('{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}'));
    return l_body.to_clob;
  end text_response;


  /*
   * One assistant turn that calls the echo tool once per id. The argument is the
   * id itself, so the echoed result says which call it answers.
   */
  function tool_call_response(p_ids in apex_t_varchar2) return clob
  as
    l_body  json_object_t := json_object_t();
    l_calls json_array_t := json_array_t();
    l_call  json_object_t;
    l_msg   json_object_t := json_object_t();
    l_choice json_object_t := json_object_t();
  begin
    <<call_loop>>
    for i in 1 .. p_ids.count loop
      l_call := json_object_t();
      l_call.put('id', p_ids(i));
      l_call.put('type', 'function');
      l_call.put('function', json_object_t(
        '{"name":"' || gc_echo_tool || '","arguments":"{\"query\":\"' || p_ids(i) || '\"}"}'));
      l_calls.append(l_call);
    end loop call_loop;

    l_msg.put('role', 'assistant');
    l_msg.put_null('content');
    l_msg.put('tool_calls', l_calls);

    l_choice.put('index', 0);
    l_choice.put('message', l_msg);
    l_choice.put('finish_reason', 'tool_calls');

    l_body.put('id', 'chatcmpl-padd-tools');
    l_body.put('object', 'chat.completion');
    l_body.put('model', 'gpt-4o-mini');
    l_body.put('choices', json_array_t('[' || l_choice.to_clob || ']'));
    l_body.put('usage', json_object_t('{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}'));
    return l_body.to_clob;
  end tool_call_response;


  /*
   * The content of the system message in the p_index-th recorded request.
   */
  function system_message_of(p_index in pls_integer) return clob
  as
    l_messages json_array_t := uc_ai_test_http_mock.request_json(p_index).get_array('messages');
    l_message  json_object_t;
  begin
    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_message := treat(l_messages.get(i) as json_object_t);
      if l_message.get_string('role') = 'system' then
        return l_message.get_clob('content');
      end if;
    end loop message_loop;

    return null;
  end system_message_of;


  function count_of(
    p_text   in clob,
    p_needle in varchar2
  ) return pls_integer
  as
    l_count pls_integer := 0;
    l_pos   pls_integer := 1;
  begin
    <<find_loop>>
    loop
      l_pos := sys.dbms_lob.instr(p_text, p_needle, l_pos);
      exit find_loop when l_pos = 0;
      l_count := l_count + 1;
      l_pos := l_pos + length(p_needle);
    end loop find_loop;

    return l_count;
  end count_of;


  function run_agent(
    p_agent_code in varchar2,
    p_addendum   in clob     default null,
    p_session_id in varchar2 default null,
    p_follow_up  in clob     default null
  ) return json_object_t
  as
  begin
    return uc_ai_agents_api.execute_agent(
      p_agent_code        => p_agent_code,
      p_session_id        => p_session_id,
      p_follow_up_message => p_follow_up,
      p_prompt_addendum   => p_addendum
    );
  end run_agent;


  -- ==========================================================================
  -- Fixture
  -- ==========================================================================

  procedure setup
  as
    l_id number;
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
    uc_ai.reset_globals;
    uc_ai.clear_exec_context;
    uc_ai_agents_api.set_execution_hook(null);

    delete_fixtures;

    l_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => gc_echo_tool,
      p_description   => 'Returns its arguments unchanged',
      p_function_call => 'return :parameters;',
      p_json_schema   => json_object_t('{
        "type": "object",
        "properties": { "query": { "type": "string", "description": "Anything" } },
        "required": ["query"]
      }'),
      p_tags          => apex_t_varchar2(gc_tool_tag)
    );
    ut.expect(l_id, 'echo tool created').to_be_not_null();

    create_profile(gc_prof_code);
    create_profile(gc_tool_prof, p_with_tools => true);
    create_profile(gc_orch_prof);
    create_profile_agent(gc_agent, gc_prof_code);
    create_profile_agent(gc_tool_agent, gc_tool_prof);
    create_profile_agent(gc_mem_agent, gc_prof_code);

    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_orch_agent,
      p_description          => 'Prompt addendum test orchestrator',
      p_agent_type           => uc_ai_agents_api.c_type_orchestrator,
      p_orchestration_config => json_object_t('{
        "pattern_type": "orchestrator",
        "orchestrator_profile_code": "' || gc_orch_prof || '",
        "delegate_agents": ["' || gc_agent || '"],
        "max_delegations": 2
      }').to_clob,
      p_status               => uc_ai_agents_api.c_status_active
    );
    ut.expect(l_id, 'orchestrator created').to_be_not_null();

    -- one PL/SQL step: a run happens with no provider call anywhere
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_flow_agent,
      p_description         => 'Prompt addendum test workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => json_object_t('{
        "workflow_type": "sequential",
        "steps": [
          { "step_type": "plsql", "plsql_function_call": "return ''ok'';", "output_key": "done" }
        ]
      }').to_clob,
      p_status              => uc_ai_agents_api.c_status_active
    );
    ut.expect(l_id, 'workflow created').to_be_not_null();

    -- agents must be committed before execution (autonomous telemetry)
    commit;
  end setup;


  procedure teardown
  as
  begin
    uc_ai_http.set_transport(null);
    delete_fixtures;
    uc_ai.reset_globals;
  end teardown;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai.clear_exec_context;
    uc_ai_test_http_mock.reset;
  end reset_state;


  -- ==========================================================================
  -- tool_call_id
  -- ==========================================================================

  procedure tool_call_id_persisted_and_paired
  as
    l_result  json_object_t;
    l_exec_id number;
    l_calls   pls_integer;
    l_pairs   pls_integer;
    l_matched pls_integer;
    l_ids     pls_integer;
  begin
    -- round 1: one call; round 2: two parallel calls; round 3: the answer
    uc_ai_test_http_mock.enqueue(tool_call_response(apex_t_varchar2('call_a1')));
    uc_ai_test_http_mock.enqueue(tool_call_response(apex_t_varchar2('call_b1', 'call_b2')));
    uc_ai_test_http_mock.enqueue(text_response('done'));

    l_result := run_agent(gc_tool_agent);
    l_exec_id := l_result.get_number('execution_id');

    ut.expect(l_result.get_string('final_message'), 'final message').to_equal('done');
    ut.expect(uc_ai_test_http_mock.request_count, 'requests made').to_equal(3);
    ut.expect(uc_ai_test_http_mock.pending_count, 'responses nobody asked for').to_equal(0);

    select count(*), count(distinct tool_call_id)
      into l_calls, l_ids
      from uc_ai_agent_messages
     where execution_id = l_exec_id
       and role = 'tool_call';
    ut.expect(l_calls, 'tool_call rows').to_equal(3);
    ut.expect(l_ids, 'distinct tool_call_id on tool_call rows').to_equal(3);

    select count(*)
      into l_pairs
      from uc_ai_agent_messages c
      join uc_ai_agent_messages r
        on r.execution_id = c.execution_id
       and r.tool_call_id = c.tool_call_id
       and r.role = 'tool_result'
     where c.execution_id = l_exec_id
       and c.role = 'tool_call';
    ut.expect(l_pairs, 'tool_call rows paired with a tool_result row').to_equal(3);

    -- the echo tool returns the id it was called with, so a pair is correct when
    -- the result row names the id of its call row
    select count(*)
      into l_matched
      from uc_ai_agent_messages c
      join uc_ai_agent_messages r
        on r.execution_id = c.execution_id
       and r.tool_call_id = c.tool_call_id
       and r.role = 'tool_result'
     where c.execution_id = l_exec_id
       and c.role = 'tool_call'
       and sys.dbms_lob.instr(r.tool_output, c.tool_call_id) > 0;
    ut.expect(l_matched, 'results that answer their own call').to_equal(3);

    -- user, system and assistant text rows carry no id
    select count(*)
      into l_calls
      from uc_ai_agent_messages
     where execution_id = l_exec_id
       and role not in ('tool_call', 'tool_result')
       and tool_call_id is not null;
    ut.expect(l_calls, 'text rows with a tool_call_id').to_equal(0);
  end tool_call_id_persisted_and_paired;


  procedure tool_call_id_in_session_messages
  as
    l_result  json_object_t;
    l_messages_cur  sys_refcursor;
    l_col_cnt pls_integer;
    l_desc    sys.dbms_sql.desc_tab;
    l_cur_id  pls_integer;
    l_last    varchar2(255 char);
  begin
    uc_ai_test_http_mock.enqueue(tool_call_response(apex_t_varchar2('call_s1')));
    uc_ai_test_http_mock.enqueue(text_response('done'));

    l_result := run_agent(gc_tool_agent);

    l_messages_cur := uc_ai_agents_api.get_session_messages(l_result.get_string('session_id'));
    l_cur_id := sys.dbms_sql.to_cursor_number(l_messages_cur);
    sys.dbms_sql.describe_columns(l_cur_id, l_col_cnt, l_desc);
    l_last := l_desc(l_col_cnt).col_name;
    sys.dbms_sql.close_cursor(l_cur_id);

    -- the new column comes last, so a caller that fetches by position keeps working
    ut.expect(l_last, 'last column of get_session_messages').to_equal('TOOL_CALL_ID');
  end tool_call_id_in_session_messages;


  -- ==========================================================================
  -- p_prompt_addendum
  -- ==========================================================================

  procedure addendum_ends_system_message
  as
    l_result json_object_t;
    l_system clob;
  begin
    uc_ai_test_http_mock.enqueue(text_response('ok'));

    l_result := run_agent(gc_agent, p_addendum => gc_addendum);
    l_system := system_message_of(1);

    ut.expect(l_result.get_string('status')).to_equal('completed');
    ut.expect(l_system, 'system message').to_equal(to_clob(gc_system || chr(10) || chr(10) || gc_addendum));
  end addendum_ends_system_message;


  procedure addendum_follows_memory_protocol
  as
    l_system   clob;
    l_result   json_object_t;
    l_protocol clob := uc_ai_memory.get_memory_protocol;
  begin
    uc_ai_memory.enable_for_agent(p_agent_code => gc_mem_agent, p_update_profile => false);
    uc_ai_test_http_mock.enqueue(text_response('ok'));

    l_result := run_agent(gc_mem_agent, p_addendum => gc_addendum);
    l_system := system_message_of(1);

    ut.expect(l_result.get_string('status')).to_equal('completed');
    ut.expect(l_system, 'system message').to_equal(
      to_clob(gc_system || chr(10) || chr(10)) || l_protocol || to_clob(chr(10) || chr(10) || gc_addendum));
  end addendum_follows_memory_protocol;


  procedure follow_up_keeps_addendum_once
  as
    l_first  json_object_t;
    l_system clob;
  begin
    uc_ai_test_http_mock.enqueue(text_response('first'));
    uc_ai_test_http_mock.enqueue(text_response('second'));

    l_first := run_agent(gc_agent, p_addendum => gc_addendum);

    -- the caller passes the addendum on every turn, as a chat region would
    l_first := run_agent(
      p_agent_code => gc_agent,
      p_addendum   => gc_addendum,
      p_session_id => l_first.get_string('session_id'),
      p_follow_up  => 'and again'
    );

    ut.expect(uc_ai_test_http_mock.request_count, 'requests made').to_equal(2);
    ut.expect(l_first.get_string('final_message')).to_equal('second');

    l_system := system_message_of(2);
    ut.expect(count_of(l_system, gc_addendum), 'addendum in the system message of turn 2').to_equal(1);
    ut.expect(l_system, 'system message of turn 2').to_equal(system_message_of(1));
  end follow_up_keeps_addendum_once;


  procedure null_addendum_is_unchanged
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(text_response('one'));
    uc_ai_test_http_mock.enqueue(text_response('two'));

    l_result := uc_ai_agents_api.execute_agent(p_agent_code => gc_agent);
    l_result := run_agent(gc_agent, p_addendum => null);

    ut.expect(system_message_of(1), 'without the parameter').to_equal(to_clob(gc_system));
    ut.expect(system_message_of(2), 'with a null addendum').to_equal(system_message_of(1));
    ut.expect(uc_ai_test_http_mock.request_json(2), 'whole request').to_equal(uc_ai_test_http_mock.request_json(1));
  end null_addendum_is_unchanged;


  procedure orchestrator_honours_addendum
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(text_response('ok'));

    l_result := run_agent(gc_orch_agent, p_addendum => gc_addendum);

    ut.expect(l_result.get_string('status')).to_equal('completed');
    ut.expect(system_message_of(1), 'system message').to_equal(to_clob(gc_system || chr(10) || chr(10) || gc_addendum));
  end orchestrator_honours_addendum;


  procedure workflow_rejects_addendum
  as
    l_before number;
    l_after  number;
    l_result json_object_t;
  begin
    select count(*) into l_before from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id where a.code = gc_flow_agent;

    begin
      l_result := run_agent(gc_flow_agent, p_addendum => gc_addendum);
      ut.fail('expected ORA-20503');
    exception
      when others then
        ut.expect(sqlcode, 'error code').to_equal(uc_ai_error.c_err_invalid_config);
        ut.expect(sqlerrm, 'error message').to_be_like('%prompt_addendum%profile or orchestrator agents%workflow%');
    end;

    select count(*) into l_after from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id where a.code = gc_flow_agent;
    ut.expect(l_after, 'executions created by the rejected call').to_equal(l_before);
  end workflow_rejects_addendum;


  procedure workflow_without_addendum_runs
  as
    l_result json_object_t;
  begin
    l_result := run_agent(gc_flow_agent, p_addendum => null);

    ut.expect(l_result.get_string('status')).to_equal('completed');
    ut.expect(uc_ai_test_http_mock.request_count, 'requests made').to_equal(0);
  end workflow_without_addendum_runs;


  -- ==========================================================================
  -- Schema
  -- ==========================================================================

  procedure tool_call_id_column_contract
  as
    l_type     user_tab_columns.data_type%type;
    l_length   user_tab_columns.char_length%type;
    l_nullable user_tab_columns.nullable%type;
    l_comment  user_col_comments.comments%type;
  begin
    select c.data_type, c.char_length, c.nullable
      into l_type, l_length, l_nullable
      from user_tab_columns c
     where c.table_name = 'UC_AI_AGENT_MESSAGES'
       and c.column_name = 'TOOL_CALL_ID';

    select m.comments
      into l_comment
      from user_col_comments m
     where m.table_name = 'UC_AI_AGENT_MESSAGES'
       and m.column_name = 'TOOL_CALL_ID';

    ut.expect(l_type, 'data type').to_equal('VARCHAR2');
    ut.expect(l_length, 'length').to_equal(255);
    ut.expect(l_nullable, 'nullable').to_equal('Y');
    ut.expect(l_comment, 'comment').to_be_like('%unique only within one execution_id%');
  end tool_call_id_column_contract;

end test_uc_ai_agent_prompt_addendum;
/
