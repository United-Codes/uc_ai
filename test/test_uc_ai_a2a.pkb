create or replace package body test_uc_ai_a2a as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages
  -- @dblinter ignore(g-7210): one suite for the A2A server; the helpers are shared by every section

  -- Every object this suite creates carries the TEST_A2A / test-a2a prefix, and only
  -- those are deleted. The smoke assets (a2a_smoke_*, a2a_live_assistant, the
  -- endpoints smoke, smoke_slow and live) and the ORDS module are never touched.
  --
  -- The tests call uc_ai_a2a.process_request, which needs no HTTP and no ORDS. The
  -- agents are workflow agents with PL/SQL steps only, so no request reaches an LLM.
  --
  -- The A2A server writes task rows in autonomous transactions. A task row has a
  -- foreign key to its endpoint, so the endpoint must be committed before the first
  -- message: setup and the tests that create an endpoint commit it.
  --
  -- The push delivery tests replace the HTTP transport with uc_ai_test_http_mock.
  -- That needs a uc_ai_http built with UC_AI_DEBUG:TRUE, like the wire suites;
  -- scripts/run_tests_free.sql runs scripts/enable_test_transport.sql first.

  gc_echo_agent constant varchar2(50 char) := 'TEST_A2A_ECHO';
  gc_json_agent constant varchar2(50 char) := 'TEST_A2A_JSON';
  gc_fail_agent constant varchar2(50 char) := 'TEST_A2A_FAIL';
  gc_txw_agent  constant varchar2(50 char) := 'TEST_A2A_TXW';   -- writes a row, then fails
  gc_txok_agent constant varchar2(50 char) := 'TEST_A2A_TXOK';  -- writes a row, then succeeds
  gc_tx_table   constant varchar2(30 char) := 'TEST_UC_AI_A2A_WRITES';

  gc_ep_echo    constant varchar2(50 char) := 'test-a2a-echo';
  gc_ep_open    constant varchar2(50 char) := 'test-a2a-open';
  gc_ep_json    constant varchar2(50 char) := 'test-a2a-json';
  gc_ep_fail    constant varchar2(50 char) := 'test-a2a-fail';
  gc_ep_noasync constant varchar2(50 char) := 'test-a2a-noasync';
  gc_ep_oauth   constant varchar2(50 char) := 'test-a2a-oauth';
  gc_ep_sign    constant varchar2(50 char) := 'test-a2a-sign';
  gc_ep_base    constant varchar2(50 char) := 'test-a2a-base';
  gc_ep_extras  constant varchar2(50 char) := 'test-a2a-extras';
  gc_ep_keys    constant varchar2(50 char) := 'test-a2a-keys';
  gc_ep_txw     constant varchar2(50 char) := 'test-a2a-txw';
  gc_ep_txok    constant varchar2(50 char) := 'test-a2a-txok';

  gc_card_url   constant varchar2(200 char) := 'https://h.example/ords/s/a2a/';
  gc_push_url   constant varchar2(200 char) := 'https://push.example/hook';

  -- A key made only for this suite: it protects nothing.
  gc_test_pem constant varchar2(4000 char) := q'[-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCe45l3FIN+rF7P
+z/AlVs6MAvGXfce7b8/4LuUU4pnhKwAePZIz0xQwzrZgTdKK21XshTwLO66jOoN
88JMPnRUbsDsZ9cz8/9JFztx295k4hx6cLKKmqQaoOyYFTE8JV3MEpn9nju85McO
zXapv9jSPviakRciQgJTgHxfCzFgW7reaHJ9Y4plz+Il5Hup7Cl+fA43XgcHywub
oDdanBD1qJXNTRd6VWiSiNscG+LimmpIj7NJNQqVhHLTy6C9pQ7+9LMl2P418/Wy
+3LrNxQJqdCZX6TQiyoXMzjabk9ofzFmLg+WMH+BCSxtnPASy8OunUpjoK8WZQ9f
3d7kQil/AgMBAAECggEAC16K4S/5FsvbvvMiBTRKwlekyA16PN7TRA1fLsZpjW27
Zw9AxEX9FnxZzi2GWMrRuKg4AlWcwYGKz/PEz/LaHR6NtHzbs85+UmsUqFmMyNg7
JHHC/NMC8hrYwyslCkI8O3mLRlAXwzT1n3QJTS06pRS3ckv2hU+G3hXAEIb7AgOB
aqWK3G4OfG+Fh1igHENc2dNc5vIPTgsfCLctJCKmb3hyUZoZCv2dSk/Gt+fsugmY
RRiIKbkmwNR1yiRVNmWUa5iT6NP5Q1DJxMcx5nhRfU5FXFknB0OMKqkAeE3v+qoR
5F4Guk/NZdOBx2v2RaNaFrGfECJtL/mFrr2FD5J3GQKBgQDVxBWX9WuSpLyfYHPo
WjWOkiX9oZoo8SP5k0e4KR1JyEvCWbjikb8hO53vvaEvuuHWScLCu6pZjxM8eI4J
RlXQdwZSsZKUFp0Lr+bOcnMhGoLnM66VCgJMIiU+t5HTCcrsTKMOjcDrUyHDz3rx
Wq+VeUZbJTeMcUILcSPnhfAaGQKBgQC+R++Uyzphk9HWK+yUPtiwv7l1+Bx0GKYx
WVGLYJAwOqlmZ7zJVYNLFT4A+g2YKZY5ZIo3bJRa8Ax1utkuZR1310cjz09xuNEO
ArNTc3xNPyO1h7pSRVDchs0CAfnP/w9LtWbqMiQYvoSmR/MCev1hHG9gehQDCvaL
Dku0i5MDVwKBgQCZGOOCPsH5d8SjvLemrJz47BELcqbvNa1XPLU73y5bvnkLy6iP
lGS3z3PQ1RZREd5W0+MKBs/9bmwPfiPz3oztTaGYrhbVutBlI2kBaJSuG8evAKPD
mDSHBFl6boyhAb10uXp6nOmTYKmpDLr3isSAIChUdPYwvpjXiwN0+Mc6WQKBgBxN
buFe6SwiZI/KsMHMJ0cC/X8CjJjoIbAtbOeiUVAbKZ9FxtrbkU/VtQdIKkV7yhB3
V+euitKL6g6I4Ez6VUvCBZ7Z8yMjLlU7KZk8ED0dKx6RNbGPBdwHYO7vhEzfz1Kf
hNNI6f2UOP7SrN6tlIqhRB/BiMB7HPjKA5CzQga5AoGAcAUF1mzglwV3h468im3L
fgYf8sSsflN59yh2BT4SqXMiwAXEzpkanGbU8+KaM0/VBb4XWtA0jcFNBR6hxRyf
EM776G0Q+8pBbLdgy60SQgJ7t3uFqMLJS0KK/s4k9zbbj4II0eQsI3DS2oJrnWZG
dnMpQo4Q+8D6VN6swnKkB64=
-----END PRIVATE KEY-----]';

  g_key_a   varchar2(100 char);
  g_key_b   varchar2(100 char);
  g_key_json varchar2(100 char);
  g_key_sign varchar2(100 char);
  g_counter pls_integer := 0;


  -- ==========================================================================
  -- Setup and cleanup
  -- ==========================================================================

  procedure purge
  as
  begin
    -- scheduler jobs of async tasks
    <<job_loop>>
    for r in (
      select t.job_name
        from uc_ai_a2a_tasks t
        join uc_ai_a2a_endpoints e on e.id = t.endpoint_id
       where e.code like 'test-a2a%'
         and t.job_name is not null
    ) loop
      begin
        sys.dbms_scheduler.drop_job(job_name => r.job_name, force => true);
      exception
        when others then
          null;
      end;
    end loop job_loop;

    <<endpoint_loop>>
    for r in (select code from uc_ai_a2a_endpoints where code like 'test-a2a%') loop
      uc_ai_a2a.remove_endpoint(r.code);
    end loop endpoint_loop;
    commit;

    -- executions commit autonomously and survive rollback, so purge by pattern
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_A2A%');
    commit;
  end purge;


  procedure create_workflow(
    p_code          in varchar2,
    p_step          in varchar2,
    p_input_schema  in clob default null,
    p_output_schema in clob default null
  )
  as
    l_def json_object_t := json_object_t('{"workflow_type":"sequential","steps":[]}');
    l_step json_object_t := json_object_t();
    l_list json_array_t := json_array_t();
    l_id   number;
  begin
    l_step.put('step_type', 'plsql');
    l_step.put('plsql_function_call', p_step);
    l_step.put('output_key', 'r');
    l_list.append(l_step);
    l_def.put('steps', l_list);

    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'A2A test agent ' || p_code,
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_def.to_clob,
      p_input_schema        => p_input_schema,
      p_output_schema       => p_output_schema,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_workflow;


  -- A workflow whose first step writes a marker row and whose second step runs p_second
  procedure create_writing_workflow(
    p_code   in varchar2,
    p_second in varchar2
  )
  as
    l_def json_object_t := json_object_t('{"workflow_type":"sequential","steps":[]}');
    l_list json_array_t := json_array_t();
    l_step json_object_t;
    l_id   number;
  begin
    l_step := json_object_t();
    l_step.put('step_type', 'plsql');
    l_step.put('plsql_function_call',
      -- one bind only (:parameters) is allowed in a step, so the marker goes in as a quoted literal
      'begin execute immediate ''insert into ' || gc_tx_table || ' (marker) values ('' || sys.dbms_assert.enquote_literal(json_object_t(:parameters).get_object(''input'').get_string(''text'')) || '')''; return ''written''; end;');
    l_step.put('output_key', 'w');
    l_list.append(l_step);
    l_step := json_object_t();
    l_step.put('step_type', 'plsql');
    l_step.put('plsql_function_call', p_second);
    l_step.put('output_key', 'r');
    l_list.append(l_step);
    l_def.put('steps', l_list);

    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'A2A transaction test agent ' || p_code,
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_def.to_clob,
      p_input_schema        => '{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_writing_workflow;


  -- Rows of the scratch table with this marker (dynamic: the table is created by setup)
  function tx_rows(p_marker in varchar2) return number
  as
    l_sql   varchar2(200 char) := 'select count(*) from ' || gc_tx_table || ' where marker = :m';
    l_count number;
  begin
    execute immediate l_sql into l_count using p_marker;
    return l_count;
  end tx_rows;


  -- Whether the scratch table of the transaction tests exists
  function tx_table_exists return boolean
  as
    l_found pls_integer;
  begin
    select case when exists (select 1 from user_tables where table_name = gc_tx_table) then 1 else 0 end
      into l_found
      from dual;
    return l_found = 1;
  end tx_table_exists;


  procedure setup
  as
    l_ddl varchar2(200 char);
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    purge;

    create_workflow(
      gc_echo_agent
    , q'#return 'echo: ' || json_object_t(:parameters).get_object('input').get_string('text');#'
    , '{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}'
    );
    create_workflow(
      gc_json_agent
    , q'#declare i json_object_t := json_object_t(:parameters).get_object('input'); o json_object_t := json_object_t(); begin o.put('sum', i.get_number('a') + i.get_number('b')); return o.to_clob; end;#'
    , '{"type":"object","properties":{"a":{"type":"number"},"b":{"type":"number"}},"required":["a","b"]}'
    , '{"type":"object","properties":{"sum":{"type":"number"}},"required":["sum"]}'
    );
    create_workflow(
      gc_fail_agent
    , q'#declare l_x varchar2(10); begin raise_application_error(-20999, 'boom secret ORA-01017 detail'); return l_x; end;#'
    );

    if not tx_table_exists then
      l_ddl := 'create table ' || gc_tx_table || ' (marker varchar2(200 char))';
      execute immediate l_ddl;
    end if;
    create_writing_workflow(gc_txw_agent, q'#declare l_x varchar2(10); begin raise_application_error(-20998, 'second step fails'); return l_x; end;#');
    create_writing_workflow(gc_txok_agent, q'#return 'ok';#');
    uc_ai_a2a.expose_agent(gc_ep_txw, gc_txw_agent, p_auth_mode => uc_ai_a2a.c_auth_none);
    uc_ai_a2a.expose_agent(gc_ep_txok, gc_txok_agent, p_auth_mode => uc_ai_a2a.c_auth_none);

    uc_ai_a2a.expose_agent(gc_ep_echo, gc_echo_agent, p_name => 'Test Echo', p_card_version => '2.1.0');
    uc_ai_a2a.expose_agent(gc_ep_open, gc_echo_agent, p_auth_mode => uc_ai_a2a.c_auth_none);
    uc_ai_a2a.expose_agent(gc_ep_json, gc_json_agent);
    uc_ai_a2a.expose_agent(gc_ep_fail, gc_fail_agent, p_auth_mode => uc_ai_a2a.c_auth_none);
    uc_ai_a2a.expose_agent(gc_ep_noasync, gc_echo_agent, p_auth_mode => uc_ai_a2a.c_auth_none, p_allow_async => false);
    uc_ai_a2a.expose_agent(gc_ep_oauth, gc_echo_agent, p_auth_mode => uc_ai_a2a.c_auth_oauth2);
    uc_ai_a2a.expose_agent(gc_ep_sign, gc_echo_agent);
    uc_ai_a2a.expose_agent(gc_ep_base, gc_echo_agent, p_auth_mode => uc_ai_a2a.c_auth_none, p_base_url => 'https://api.example.com/x/y/');
    uc_ai_a2a.expose_agent(
      gc_ep_extras, gc_echo_agent
    , p_card_extras => q'#{"provider":{"organization":"United Codes","url":"https://uc.example"},"documentationUrl":"https://docs.example/a2a","iconUrl":"https://docs.example/icon.png","tags":["t1","t2"],"examples":["Say hello"]}#'
    );
    commit;

    g_key_a      := uc_ai_a2a.create_api_key(gc_ep_echo, 'alpha');
    g_key_b      := uc_ai_a2a.create_api_key(gc_ep_echo, 'beta');
    g_key_json   := uc_ai_a2a.create_api_key(gc_ep_json, 'alpha');
    g_key_sign   := uc_ai_a2a.create_api_key(gc_ep_sign, 'alpha');
    commit;
  end setup;


  procedure teardown
  as
    l_ddl varchar2(200 char) := 'drop table ' || gc_tx_table || ' purge';
  begin
    purge;
    if tx_table_exists then
      execute immediate l_ddl;
    end if;
  end teardown;


  procedure reset_transport
  as
  begin
    uc_ai_http.set_transport(null);
    uc_ai_test_http_mock.reset;
  exception
    when others then
      null;
  end reset_transport;


  -- ==========================================================================
  -- Helpers
  -- ==========================================================================

  function next_id return varchar2
  as
  begin
    g_counter := g_counter + 1;
    return 'msg-' || g_counter;
  end next_id;


  function hdrs(
    p_key     in varchar2 default null,
    p_version in varchar2 default null
  ) return json_object_t
  as
    l_h json_object_t := json_object_t();
  begin
    if p_key is not null then
      l_h.put('x-api-key', p_key);
    end if;
    if p_version is not null then
      l_h.put('a2a-version', p_version);
    end if;
    return l_h;
  end hdrs;


  function jbody(p_resp in uc_ai_a2a.t_http_response) return json_object_t
  as
  begin
    return json_object_t.parse(p_resp.body);
  end jbody;


  function obj_at(p_arr in json_array_t, p_idx in pls_integer) return json_object_t
  as
  begin
    return treat(p_arr.get(p_idx) as json_object_t);
  end obj_at;


  -- JSON of the params of a SendMessage request
  function params_of(
    p_parts      in varchar2,
    p_message_id in varchar2 default null,
    p_context_id in varchar2 default null,
    p_task_id    in varchar2 default null,
    p_role       in varchar2 default 'ROLE_USER',
    p_config     in varchar2 default null
  ) return varchar2
  as
    l_msg    json_object_t := json_object_t();
    l_params json_object_t := json_object_t();
  begin
    l_msg.put('messageId', coalesce(p_message_id, next_id));
    l_msg.put('role', p_role);
    if p_parts is not null then
      l_msg.put('parts', json_array_t(p_parts));
    end if;
    if p_context_id is not null then
      l_msg.put('contextId', p_context_id);
    end if;
    if p_task_id is not null then
      l_msg.put('taskId', p_task_id);
    end if;
    l_params.put('message', l_msg);
    if p_config is not null then
      l_params.put('configuration', json_object_t(p_config));
    end if;
    return l_params.to_string;
  end params_of;


  -- Params of a text message (the text must not need JSON escapes)
  function text_params(
    p_text       in varchar2,
    p_message_id in varchar2 default null,
    p_context_id in varchar2 default null,
    p_config     in varchar2 default null
  ) return varchar2
  as
  begin
    return params_of(
      '[{"text":"' || p_text || '"}]'
    , p_message_id => p_message_id
    , p_context_id => p_context_id
    , p_config     => p_config
    );
  end text_params;


  function rpc(
    p_endpoint in varchar2,
    p_method   in varchar2,
    p_params   in varchar2 default '{}',
    p_key      in varchar2 default g_key_a,
    p_version  in varchar2 default null
  ) return uc_ai_a2a.t_http_response
  as
  begin
    return uc_ai_a2a.process_request(
      p_endpoint_code => p_endpoint
    , p_route         => uc_ai_a2a.c_route_jsonrpc
    , p_method        => 'POST'
    , p_body          => '{"jsonrpc":"2.0","id":7,"method":"' || p_method || '","params":' || p_params || '}'
    , p_headers       => hdrs(p_key, p_version)
    , p_request_url   => gc_card_url || p_endpoint || '/jsonrpc'
    );
  end rpc;


  function rest(
    p_endpoint in varchar2,
    p_method   in varchar2,
    p_path     in varchar2,
    p_query    in varchar2 default null,
    p_body     in varchar2 default null,
    p_key      in varchar2 default g_key_a
  ) return uc_ai_a2a.t_http_response
  as
  begin
    return uc_ai_a2a.process_request(
      p_endpoint_code => p_endpoint
    , p_route         => uc_ai_a2a.c_route_rest
    , p_method        => p_method
    , p_path          => p_path
    , p_query_string  => p_query
    , p_body          => p_body
    , p_headers       => hdrs(p_key)
    , p_request_url   => gc_card_url || p_endpoint || '/rest/' || p_path
    );
  end rest;


  function card_of(
    p_endpoint in varchar2,
    p_url      in varchar2 default null
  ) return uc_ai_a2a.t_http_response
  as
  begin
    return uc_ai_a2a.process_request(
      p_endpoint_code => p_endpoint
    , p_route         => uc_ai_a2a.c_route_card
    , p_method        => 'GET'
    , p_request_url   => coalesce(p_url, gc_card_url || p_endpoint || '/.well-known/agent-card.json')
    );
  end card_of;


  -- The task of a JSON-RPC SendMessage-like answer
  function rpc_task(p_resp in uc_ai_a2a.t_http_response) return json_object_t
  as
  begin
    return jbody(p_resp).get_object('result').get_object('task');
  end rpc_task;


  function rpc_error_code(p_resp in uc_ai_a2a.t_http_response) return number
  as
  begin
    return jbody(p_resp).get_object('error').get_number('code');
  end rpc_error_code;


  -- Sends a text message through JSON-RPC and returns the task
  function send_text(
    p_endpoint   in varchar2,
    p_text       in varchar2,
    p_key        in varchar2 default g_key_a,
    p_context_id in varchar2 default null,
    p_message_id in varchar2 default null,
    p_config     in varchar2 default null
  ) return json_object_t
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(
      p_endpoint, 'SendMessage'
    , text_params(p_text, p_message_id, p_context_id, p_config)
    , p_key
    );
    return rpc_task(l_resp);
  end send_text;


  function hist_size(p_task in json_object_t) return pls_integer
  as
  begin
    if p_task.has('history') then
      return p_task.get_array('history').get_size;
    end if;
    return 0;
  end hist_size;


  function state_of(p_task in json_object_t) return varchar2
  as
  begin
    return p_task.get_object('status').get_string('state');
  end state_of;


  function artifact_text(p_task in json_object_t) return varchar2
  as
  begin
    return obj_at(obj_at(p_task.get_array('artifacts'), 0).get_array('parts'), 0).get_string('text');
  end artifact_text;


  function db_state(p_task_id in varchar2) return varchar2
  as
    l_state uc_ai_a2a_tasks.state%type;
  begin
    select state into l_state from uc_ai_a2a_tasks where task_id = p_task_id;
    return l_state;
  end db_state;


  -- The events of an SSE body
  function sse_events(p_body in clob) return json_array_t
  as
    l_events json_array_t := json_array_t();
    l_line   varchar2(32000 char);
    l_pos    pls_integer := 1;
    l_end    pls_integer;
    l_text   varchar2(32000 char);
  begin
    -- the test bodies are small: one varchar2 holds them
    l_text := sys.dbms_lob.substr(p_body, 32000, 1);
    <<line_loop>>
    loop
      l_end := instr(l_text, chr(10), l_pos);
      exit line_loop when l_end = 0;
      l_line := substr(l_text, l_pos, l_end - l_pos);
      l_pos  := l_end + 1;
      if l_line like 'data: %' then
        l_events.append(json_object_t.parse(substr(l_line, 7)));
      end if;
    end loop line_loop;
    return l_events;
  end sse_events;


  function b64url_decode(p_text in varchar2) return varchar2
  as
    l_text varchar2(4000 char) := translate(p_text, '-_', '+/');
  begin
    l_text := l_text || case mod(length(l_text), 4) when 2 then '==' when 3 then '=' else null end;
    return sys.utl_raw.cast_to_varchar2(sys.utl_encode.base64_decode(sys.utl_raw.cast_to_raw(l_text)));
  end b64url_decode;


  function can_sign return boolean
  as
    l_sig raw(4000);
  begin
    l_sig := uc_ai_a2a_core.sign_rs256(gc_test_pem, sys.utl_raw.cast_to_raw('x'));
    return true;
  exception
    when others then
      return false;
  end can_sign;


  -- Expects a call that raises the application error p_code
  procedure expect_ora(
    p_code  in number,
    p_block in varchar2
  )
  as
    l_code number := 0;
  begin
    begin
      -- @dblinter ignore(G-9501): p_block is a literal block from this package, never user input
      execute immediate p_block;
    exception
      when others then
        l_code := sqlcode;
    end;
    ut.expect(l_code, p_block).to_equal(p_code);
  end expect_ora;


  -- GetTask result: the task itself
  function rpc_task_get(
    p_id          in varchar2,
    p_history     in number,
    p_key         in varchar2 default g_key_a
  ) return json_object_t
  as
    l_params json_object_t := json_object_t();
  begin
    l_params.put('id', p_id);
    if p_history is not null then
      l_params.put('historyLength', p_history);
    end if;
    return jbody(rpc(gc_ep_echo, 'GetTask', l_params.to_string, p_key)).get_object('result');
  end rpc_task_get;


  -- ==========================================================================
  -- Endpoint management
  -- ==========================================================================

  procedure expose_creates_and_upserts
  as
    l_id1   number;
    l_id2   number;
    l_count number;
    l_name  uc_ai_a2a_endpoints.name%type;
    l_auth  uc_ai_a2a_endpoints.auth_mode%type;
  begin
    l_id1 := uc_ai_a2a.expose_agent('test-a2a-upsert', gc_echo_agent, p_name => 'one');
    l_id2 := uc_ai_a2a.expose_agent('test-a2a-upsert', gc_echo_agent, p_name => 'two', p_auth_mode => uc_ai_a2a.c_auth_none);
    commit;

    ut.expect(l_id1).to_be_not_null();
    ut.expect(l_id2).to_equal(l_id1);

    select count(*), max(name), max(auth_mode)
      into l_count, l_name, l_auth
      from uc_ai_a2a_endpoints
     where code = 'test-a2a-upsert';
    ut.expect(l_count).to_equal(1);
    ut.expect(l_name).to_equal('two');
    ut.expect(l_auth).to_equal('none');

    uc_ai_a2a.remove_endpoint('test-a2a-upsert');
    commit;
  end expose_creates_and_upserts;


  procedure expose_rejects_invalid_code
  as
  begin
    expect_ora(uc_ai_a2a.c_err_invalid_endpoint, q'#begin uc_ai_a2a.expose_agent('Test-A2A-Upper', 'TEST_A2A_ECHO'); end;#');
    expect_ora(uc_ai_a2a.c_err_invalid_endpoint, q'#begin uc_ai_a2a.expose_agent('test a2a space', 'TEST_A2A_ECHO'); end;#');
    expect_ora(uc_ai_a2a.c_err_invalid_endpoint, q'#begin uc_ai_a2a.expose_agent('-test-a2a-dash', 'TEST_A2A_ECHO'); end;#');
    expect_ora(uc_ai_a2a.c_err_invalid_endpoint, q'#begin uc_ai_a2a.expose_agent(null, 'TEST_A2A_ECHO'); end;#');
  end expose_rejects_invalid_code;


  procedure expose_rejects_unknown_auth_mode
  as
    l_count number;
  begin
    expect_ora(
      uc_ai_a2a.c_err_invalid_endpoint
    , q'#begin uc_ai_a2a.expose_agent('test-a2a-badauth', 'TEST_A2A_ECHO', p_auth_mode => 'basic'); end;#'
    );
    select count(*) into l_count from uc_ai_a2a_endpoints where code = 'test-a2a-badauth';
    ut.expect(l_count).to_equal(0);
  end expose_rejects_unknown_auth_mode;


  procedure expose_rejects_unknown_agent
  as
  begin
    expect_ora(
      uc_ai_a2a.c_err_invalid_endpoint
    , q'#begin uc_ai_a2a.expose_agent('test-a2a-noagent', 'TEST_A2A_DOES_NOT_EXIST'); end;#'
    );
  end expose_rejects_unknown_agent;


  procedure expose_derives_text_input_param
  as
    l_param uc_ai_a2a_endpoints.text_input_param%type;
  begin
    select text_input_param into l_param from uc_ai_a2a_endpoints where code = gc_ep_echo;
    ut.expect(l_param).to_equal('text');

    -- an explicit parameter wins
    uc_ai_a2a.expose_agent('test-a2a-upsert', gc_echo_agent, p_text_input_param => 'prompt');
    commit;
    select text_input_param into l_param from uc_ai_a2a_endpoints where code = 'test-a2a-upsert';
    ut.expect(l_param).to_equal('prompt');
    uc_ai_a2a.remove_endpoint('test-a2a-upsert');
    commit;
  end expose_derives_text_input_param;


  procedure expose_no_text_param_for_two_inputs
  as
    l_param uc_ai_a2a_endpoints.text_input_param%type;
  begin
    select text_input_param into l_param from uc_ai_a2a_endpoints where code = gc_ep_json;
    ut.expect(l_param).to_be_null();
  end expose_no_text_param_for_two_inputs;


  procedure oauth2_requires_client_id
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := uc_ai_a2a.process_request(
      gc_ep_oauth, uc_ai_a2a.c_route_jsonrpc, 'POST'
    , p_body => '{"jsonrpc":"2.0","id":1,"method":"ListTasks","params":{}}'
    );
    ut.expect(l_resp.status).to_equal(401);

    l_resp := uc_ai_a2a.process_request(
      gc_ep_oauth, uc_ai_a2a.c_route_jsonrpc, 'POST'
    , p_body => '{"jsonrpc":"2.0","id":1,"method":"ListTasks","params":{}}'
    , p_client_id => 'test-a2a-client-1'
    );
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(jbody(l_resp).get_object('result').get_number('totalSize')).to_equal(0);
  end oauth2_requires_client_id;


  procedure disabled_endpoint_answers_404
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    uc_ai_a2a.set_enabled(gc_ep_open, false);
    commit;
    begin
      l_resp := card_of(gc_ep_open);
      ut.expect(l_resp.status, 'card').to_equal(404);
      l_resp := rpc(gc_ep_open, 'ListTasks', p_key => null);
      ut.expect(l_resp.status, 'jsonrpc').to_equal(404);
      l_resp := rest(gc_ep_open, 'GET', 'tasks', p_key => null);
      ut.expect(l_resp.status, 'rest').to_equal(404);
    exception
      when others then
        uc_ai_a2a.set_enabled(gc_ep_open, true);
        commit;
        raise;
    end;

    uc_ai_a2a.set_enabled(gc_ep_open, true);
    commit;
    l_resp := card_of(gc_ep_open);
    ut.expect(l_resp.status, 'enabled again').to_equal(200);

    -- an endpoint that does not exist answers 404 as well
    l_resp := card_of('test-a2a-nope');
    ut.expect(l_resp.status, 'unknown').to_equal(404);
  end disabled_endpoint_answers_404;


  procedure remove_endpoint_deletes_children
  as
    l_key    varchar2(100 char);
    l_task   json_object_t;
    l_resp   uc_ai_a2a.t_http_response;
    l_keys   number;
    l_tasks  number;
    l_pushes number;
    l_tid    varchar2(36 char);
  begin
    uc_ai_a2a.expose_agent('test-a2a-rm', gc_echo_agent);
    commit;
    l_key := uc_ai_a2a.create_api_key('test-a2a-rm', 'gamma');
    commit;

    l_task := send_text('test-a2a-rm', 'hello', l_key);
    ut.expect(state_of(l_task)).to_equal(uc_ai_a2a_core.c_state_completed);
    l_tid := l_task.get_string('id');
    l_resp := rpc(
      'test-a2a-rm', 'CreateTaskPushNotificationConfig'
    , '{"taskId":"' || l_task.get_string('id') || '","id":"c1","url":"' || gc_push_url || '"}'
    , l_key
    );
    ut.expect(l_resp.body).not_to_be_like('%"error"%');
    commit;

    uc_ai_a2a.remove_endpoint('test-a2a-rm');
    commit;

    select count(*) into l_keys   from uc_ai_a2a_api_keys where client_name = 'gamma';
    select count(*) into l_tasks  from uc_ai_a2a_tasks where task_id = l_tid;
    select count(*) into l_pushes from uc_ai_a2a_push_configs where task_id = l_tid;
    ut.expect(l_keys, 'keys').to_equal(0);
    ut.expect(l_tasks, 'tasks').to_equal(0);
    ut.expect(l_pushes, 'push configs').to_equal(0);
    ut.expect(card_of('test-a2a-rm').status).to_equal(404);
  end remove_endpoint_deletes_children;


  -- ==========================================================================
  -- API keys
  -- ==========================================================================

  procedure api_key_stores_hash_only
  as
    l_key    varchar2(100 char);
    l_hash   uc_ai_a2a_api_keys.key_hash%type;
    l_prefix uc_ai_a2a_api_keys.key_prefix%type;
    l_leaks  number;
    l_expected varchar2(64 char);
  begin
    uc_ai_a2a.expose_agent(gc_ep_keys, gc_echo_agent);
    commit;
    l_key := uc_ai_a2a.create_api_key(gc_ep_keys, 'hashed');
    commit;

    ut.expect(regexp_like(l_key, '^a2a_[0-9a-f]{48}$')).to_be_true();

    select k.key_hash, k.key_prefix
      into l_hash, l_prefix
      from uc_ai_a2a_api_keys k
      join uc_ai_a2a_endpoints e on e.id = k.endpoint_id
     where e.code = gc_ep_keys
       and k.client_name = 'hashed';

    select lower(rawtohex(standard_hash(l_key, 'SHA256'))) into l_expected from dual;
    ut.expect(l_hash).to_equal(l_expected);
    ut.expect(l_prefix).not_to_equal(l_key);
    ut.expect(length(l_prefix) < length(l_key)).to_be_true();

    select count(*)
      into l_leaks
      from uc_ai_a2a_api_keys
     where instr(key_hash, l_key) > 0
        or key_prefix = l_key;
    ut.expect(l_leaks).to_equal(0);
  end api_key_stores_hash_only;


  procedure api_key_missing_or_wrong_is_401
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_echo, 'ListTasks', p_key => null);
    ut.expect(l_resp.status, 'no key').to_equal(401);

    l_resp := rpc(gc_ep_echo, 'ListTasks', p_key => 'a2a_not_a_real_key');
    ut.expect(l_resp.status, 'wrong key').to_equal(401);

    l_resp := rest(gc_ep_echo, 'GET', 'tasks', p_key => 'a2a_not_a_real_key');
    ut.expect(l_resp.status, 'rest wrong key').to_equal(401);
    ut.expect(jbody(l_resp).get_object('error').get_string('status')).to_equal('UNAUTHENTICATED');

    -- a key of another endpoint does not open this one
    l_resp := rpc(gc_ep_json, 'ListTasks', p_key => g_key_a);
    ut.expect(l_resp.status, 'key of another endpoint').to_equal(401);
  end api_key_missing_or_wrong_is_401;


  procedure api_key_revoked_is_401
  as
    l_key  varchar2(100 char);
    l_resp uc_ai_a2a.t_http_response;
    l_used uc_ai_a2a_api_keys.last_used_at%type;
  begin
    uc_ai_a2a.expose_agent(gc_ep_keys, gc_echo_agent);
    commit;
    l_key := uc_ai_a2a.create_api_key(gc_ep_keys, 'revoked');
    commit;

    l_resp := rpc(gc_ep_keys, 'ListTasks', p_key => l_key);
    ut.expect(l_resp.status, 'before revoke').to_equal(200);

    select k.last_used_at into l_used
      from uc_ai_a2a_api_keys k join uc_ai_a2a_endpoints e on e.id = k.endpoint_id
     where e.code = gc_ep_keys and k.client_name = 'revoked';
    ut.expect(l_used, 'last_used_at').to_be_not_null();

    uc_ai_a2a.revoke_api_key(gc_ep_keys, 'revoked');
    commit;
    l_resp := rpc(gc_ep_keys, 'ListTasks', p_key => l_key);
    ut.expect(l_resp.status, 'after revoke').to_equal(401);
    l_resp := rest(gc_ep_keys, 'GET', 'tasks', p_key => l_key);
    ut.expect(l_resp.status, 'rest after revoke').to_equal(401);
  end api_key_revoked_is_401;


  procedure api_key_expired_is_401
  as
    l_key  varchar2(100 char);
    l_resp uc_ai_a2a.t_http_response;
  begin
    uc_ai_a2a.expose_agent(gc_ep_keys, gc_echo_agent);
    commit;
    l_key := uc_ai_a2a.create_api_key(gc_ep_keys, 'expired', localtimestamp - interval '1' hour);
    commit;
    l_resp := rpc(gc_ep_keys, 'ListTasks', p_key => l_key);
    ut.expect(l_resp.status, 'expired').to_equal(401);

    l_key := uc_ai_a2a.create_api_key(gc_ep_keys, 'future', localtimestamp + interval '1' hour);
    commit;
    l_resp := rpc(gc_ep_keys, 'ListTasks', p_key => l_key);
    ut.expect(l_resp.status, 'not yet expired').to_equal(200);
  end api_key_expired_is_401;


  procedure api_key_duplicate_client_rejected
  as
    l_key varchar2(100 char);
  begin
    uc_ai_a2a.expose_agent(gc_ep_keys, gc_echo_agent);
    commit;
    l_key := uc_ai_a2a.create_api_key(gc_ep_keys, 'twice');
    commit;
    expect_ora(
      uc_ai_a2a.c_err_api_key
    , q'#declare l_k varchar2(100); begin l_k := uc_ai_a2a.create_api_key('test-a2a-keys', 'twice'); end;#'
    );
  end api_key_duplicate_client_rejected;


  -- ==========================================================================
  -- Agent card
  -- ==========================================================================

  procedure card_required_fields
  as
    l_resp uc_ai_a2a.t_http_response;
    l_card json_object_t;
    l_cap  json_object_t;
    l_skill json_object_t;
  begin
    l_resp := card_of(gc_ep_echo);
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(l_resp.content_type).to_equal('application/json');
    l_card := jbody(l_resp);

    ut.expect(l_card.get_string('name')).to_equal('Test Echo');
    ut.expect(l_card.get_string('description')).to_equal('A2A test agent ' || gc_echo_agent);
    ut.expect(l_card.get_string('version')).to_equal('2.1.0');
    ut.expect(l_card.has('supportedInterfaces')).to_be_true();
    ut.expect(l_card.has('defaultInputModes')).to_be_true();
    ut.expect(l_card.has('defaultOutputModes')).to_be_true();

    l_cap := l_card.get_object('capabilities');
    ut.expect(l_cap.get_boolean('streaming')).to_be_true();
    ut.expect(l_cap.get_boolean('pushNotifications')).to_be_true();

    ut.expect(l_card.get_array('skills').get_size).to_equal(1);
    l_skill := obj_at(l_card.get_array('skills'), 0);
    ut.expect(l_skill.get_string('id')).to_equal(gc_echo_agent);
    ut.expect(l_skill.get_string('name')).to_be_not_null();
    ut.expect(l_skill.get_string('description')).to_be_not_null();
    ut.expect(l_skill.get_array('tags').get_size).to_be_greater_than(0);

    -- no signature without a key
    ut.expect(l_card.has('signatures')).to_be_false();
    -- a file-accepting agent lists the file types
    ut.expect(l_card.get_array('defaultInputModes').to_string).to_be_like('%application/pdf%');

    -- the push capability follows allow_async
    l_card := jbody(card_of(gc_ep_noasync));
    ut.expect(l_card.get_object('capabilities').get_boolean('pushNotifications')).to_be_false();
  end card_required_fields;


  procedure card_interfaces_from_request_url
  as
    l_card  json_object_t := jbody(card_of(gc_ep_echo));
    l_ifs   json_array_t := l_card.get_array('supportedInterfaces');
    l_rpc   json_object_t;
    l_rest  json_object_t;
  begin
    ut.expect(l_ifs.get_size).to_equal(2);
    l_rpc  := obj_at(l_ifs, 0);
    l_rest := obj_at(l_ifs, 1);

    ut.expect(l_rpc.get_string('url')).to_equal(gc_card_url || gc_ep_echo || '/jsonrpc');
    ut.expect(l_rpc.get_string('protocolBinding')).to_equal('JSONRPC');
    ut.expect(l_rpc.get_string('protocolVersion')).to_equal('1.0');
    ut.expect(l_rest.get_string('url')).to_equal(gc_card_url || gc_ep_echo || '/rest');
    ut.expect(l_rest.get_string('protocolBinding')).to_equal('HTTP+JSON');
    ut.expect(l_rest.get_string('protocolVersion')).to_equal('1.0');
    ut.expect(l_rpc.get_string('url')).to_be_like('https://%');
  end card_interfaces_from_request_url;


  procedure card_interfaces_from_base_url
  as
    -- the request URL is ignored when the endpoint has a base_url
    l_card json_object_t := jbody(card_of(gc_ep_base, 'http://internal.example/other/test-a2a-base/.well-known/agent-card.json'));
    l_ifs  json_array_t := l_card.get_array('supportedInterfaces');
  begin
    ut.expect(obj_at(l_ifs, 0).get_string('url')).to_equal('https://api.example.com/x/y/jsonrpc');
    ut.expect(obj_at(l_ifs, 1).get_string('url')).to_equal('https://api.example.com/x/y/rest');
  end card_interfaces_from_base_url;


  procedure card_security_schemes_per_auth_mode
  as
    l_card   json_object_t;
    l_scheme json_object_t;
    l_flow   json_object_t;
    l_url    varchar2(1000 char);
  begin
    -- api_key
    l_card   := jbody(card_of(gc_ep_echo));
    l_scheme := l_card.get_object('securitySchemes').get_object('apiKey').get_object('apiKeySecurityScheme');
    ut.expect(l_scheme.get_string('location')).to_equal('header');
    ut.expect(l_scheme.get_string('name')).to_equal('X-API-Key');
    ut.expect(l_card.get_array('securityRequirements').get_size).to_equal(1);

    -- none
    l_card := jbody(card_of(gc_ep_open));
    ut.expect(l_card.has('securitySchemes'), 'none: schemes').to_be_false();
    ut.expect(l_card.has('securityRequirements'), 'none: requirements').to_be_false();

    -- oauth2: the token URL is derived from the request URL
    l_card   := jbody(card_of(gc_ep_oauth));
    l_flow   := l_card.get_object('securitySchemes').get_object('oauth2').get_object('oauth2SecurityScheme')
                      .get_object('flows').get_object('clientCredentials');
    l_url    := l_flow.get_string('tokenUrl');
    ut.expect(l_url).to_equal('https://h.example/ords/s/oauth/token');
    ut.expect(l_card.get_array('securityRequirements').to_string).to_be_like('%oauth2%');

    -- oauth2: oauthTokenUrl of card_extras wins
    uc_ai_a2a.expose_agent(
      gc_ep_oauth, gc_echo_agent, p_auth_mode => uc_ai_a2a.c_auth_oauth2
    , p_card_extras => '{"oauthTokenUrl":"https://auth.example/token"}'
    );
    commit;
    l_card := jbody(card_of(gc_ep_oauth));
    l_flow := l_card.get_object('securitySchemes').get_object('oauth2').get_object('oauth2SecurityScheme')
                    .get_object('flows').get_object('clientCredentials');
    ut.expect(l_flow.get_string('tokenUrl')).to_equal('https://auth.example/token');

    uc_ai_a2a.expose_agent(gc_ep_oauth, gc_echo_agent, p_auth_mode => uc_ai_a2a.c_auth_oauth2);
    commit;
  end card_security_schemes_per_auth_mode;


  procedure card_needs_no_auth
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    -- api_key endpoint, no key
    l_resp := card_of(gc_ep_echo);
    ut.expect(l_resp.status).to_equal(200);
    -- oauth2 endpoint, no client
    l_resp := card_of(gc_ep_oauth);
    ut.expect(l_resp.status).to_equal(200);
  end card_needs_no_auth;


  procedure card_extended_capability
  as
  begin
    ut.expect(jbody(card_of(gc_ep_echo)).get_object('capabilities').get_boolean('extendedAgentCard'), 'api_key').to_be_true();
    ut.expect(jbody(card_of(gc_ep_oauth)).get_object('capabilities').get_boolean('extendedAgentCard'), 'oauth2').to_be_true();
    ut.expect(jbody(card_of(gc_ep_open)).get_object('capabilities').get_boolean('extendedAgentCard'), 'none').to_be_false();
  end card_extended_capability;


  procedure card_output_modes
  as
    l_card json_object_t;
  begin
    l_card := jbody(card_of(gc_ep_echo));
    ut.expect(l_card.get_array('defaultOutputModes').to_string).to_equal('["text/plain"]');

    l_card := jbody(card_of(gc_ep_json));
    ut.expect(l_card.get_array('defaultOutputModes').to_string).to_equal('["application/json","text/plain"]');
  end card_output_modes;


  procedure card_extras_merge
  as
    l_card  json_object_t := jbody(card_of(gc_ep_extras));
    l_skill json_object_t := obj_at(l_card.get_array('skills'), 0);
  begin
    ut.expect(l_card.get_object('provider').get_string('organization')).to_equal('United Codes');
    ut.expect(l_card.get_object('provider').get_string('url')).to_equal('https://uc.example');
    ut.expect(l_card.get_string('documentationUrl')).to_equal('https://docs.example/a2a');
    ut.expect(l_card.get_string('iconUrl')).to_equal('https://docs.example/icon.png');
    ut.expect(l_skill.get_array('tags').to_string).to_equal('["t1","t2"]');
    ut.expect(l_skill.get_array('examples').to_string).to_equal('["Say hello"]');
    -- the plain endpoint has none of it
    ut.expect(jbody(card_of(gc_ep_echo)).has('provider')).to_be_false();
  end card_extras_merge;


  -- ==========================================================================
  -- JSON-RPC
  -- ==========================================================================

  procedure rpc_send_text_completed
  as
    l_resp uc_ai_a2a.t_http_response;
    l_task json_object_t;
    l_msg  json_object_t;
  begin
    l_resp := rpc(gc_ep_echo, 'SendMessage', text_params('hi', 'm-text'));
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(l_resp.content_type).to_equal('application/json');
    ut.expect(jbody(l_resp).get_string('jsonrpc')).to_equal('2.0');
    ut.expect(jbody(l_resp).get_number('id')).to_equal(7);

    l_task := rpc_task(l_resp);
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_COMPLETED');
    ut.expect(l_task.get_string('id')).to_be_not_null();
    ut.expect(l_task.get_string('contextId')).to_be_not_null();
    ut.expect(l_task.get_object('status').get_string('timestamp')).to_match('^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$');
    ut.expect(artifact_text(l_task)).to_equal('echo: hi');
    ut.expect(obj_at(l_task.get_array('artifacts'), 0).get_string('artifactId')).to_equal(l_task.get_string('id') || '-result');

    -- history: the client message and the agent reply
    ut.expect(hist_size(l_task)).to_equal(2);
    l_msg := obj_at(l_task.get_array('history'), 0);
    ut.expect(l_msg.get_string('messageId')).to_equal('m-text');
    ut.expect(l_msg.get_string('role')).to_equal('ROLE_USER');
    ut.expect(l_msg.get_string('taskId')).to_equal(l_task.get_string('id'));
    ut.expect(l_msg.get_string('contextId')).to_equal(l_task.get_string('contextId'));
    l_msg := obj_at(l_task.get_array('history'), 1);
    ut.expect(l_msg.get_string('role')).to_equal('ROLE_AGENT');
    ut.expect(l_msg.get_string('messageId')).to_be_not_null();

    ut.expect(db_state(l_task.get_string('id'))).to_equal(uc_ai_a2a_core.c_state_completed);
  end rpc_send_text_completed;


  procedure rpc_send_data_part
  as
    l_resp uc_ai_a2a.t_http_response;
    l_task json_object_t;
    l_part json_object_t;
  begin
    l_resp := rpc(
      gc_ep_json, 'SendMessage'
    , params_of('[{"data":{"a":2,"b":5}}]')
    , g_key_json
    );
    l_task := rpc_task(l_resp);
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_COMPLETED');

    l_part := obj_at(obj_at(l_task.get_array('artifacts'), 0).get_array('parts'), 0);
    ut.expect(l_part.get_string('mediaType')).to_equal('application/json');
    ut.expect(l_part.get_object('data').get_number('sum')).to_equal(7);
  end rpc_send_data_part;


  procedure rpc_missing_required_input
  as
    l_resp   uc_ai_a2a.t_http_response;
    l_before number;
  begin
    l_resp   := rpc(gc_ep_json, 'ListTasks', '{}', g_key_json);
    l_before := jbody(l_resp).get_object('result').get_number('totalSize');
    -- a required input is missing from the data part
    l_resp := rpc(gc_ep_json, 'SendMessage', params_of('[{"data":{"a":2}}]'), g_key_json);
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(rpc_error_code(l_resp)).to_equal(-32602);
    ut.expect(jbody(l_resp).get_object('error').get_string('message')).to_be_like('%"b"%');

    -- text for an agent that takes no text
    l_resp := rpc(gc_ep_json, 'SendMessage', text_params('hello'), g_key_json);
    ut.expect(rpc_error_code(l_resp)).to_equal(-32602);
    ut.expect(jbody(l_resp).get_object('error').get_string('message')).to_be_like('%a, b%');

    -- an input that is not the text parameter
    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"data":{"other":1}}]'));
    ut.expect(rpc_error_code(l_resp)).to_equal(-32602);

    -- nothing ran: the failed requests made no task
    l_resp := rpc(gc_ep_json, 'ListTasks', '{}', g_key_json);
    ut.expect(jbody(l_resp).get_object('result').get_number('totalSize')).to_equal(l_before);
  end rpc_missing_required_input;


  procedure rpc_url_part_unsupported
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"url":"https://files.example/a.pdf","mediaType":"application/pdf"}]'));
    ut.expect(rpc_error_code(l_resp)).to_equal(-32005);
    ut.expect(jbody(l_resp).get_object('error').get_array('data').to_string).to_be_like('%CONTENT_TYPE_NOT_SUPPORTED%');
  end rpc_url_part_unsupported;


  procedure rpc_invalid_message
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[]'));
    ut.expect(rpc_error_code(l_resp), 'empty parts').to_equal(-32602);

    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of(null));
    ut.expect(rpc_error_code(l_resp), 'no parts').to_equal(-32602);

    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"text":"x"}]', p_role => 'ROLE_AGENT'));
    ut.expect(rpc_error_code(l_resp), 'agent role').to_equal(-32602);

    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"text":"x"}]', p_role => 'user'));
    ut.expect(rpc_error_code(l_resp), 'bad role').to_equal(-32602);

    l_resp := rpc(gc_ep_echo, 'SendMessage', '{"message":{"role":"ROLE_USER","parts":[{"text":"x"}]}}');
    ut.expect(rpc_error_code(l_resp), 'no messageId').to_equal(-32602);

    l_resp := rpc(gc_ep_echo, 'SendMessage', '{}');
    ut.expect(rpc_error_code(l_resp), 'no message').to_equal(-32602);

    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"text":"x","data":{"a":1}}]'));
    ut.expect(rpc_error_code(l_resp), 'two kinds in one part').to_equal(-32602);
  end rpc_invalid_message;


  procedure rpc_protocol_errors
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    -- parse error: the id is unknown, so it is null
    l_resp := uc_ai_a2a.process_request(
      gc_ep_echo, uc_ai_a2a.c_route_jsonrpc, 'POST', p_body => '{not json', p_headers => hdrs(g_key_a)
    );
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(rpc_error_code(l_resp), 'parse').to_equal(-32700);
    ut.expect(jbody(l_resp).get('id').is_null).to_be_true();

    -- invalid request: no method
    l_resp := uc_ai_a2a.process_request(
      gc_ep_echo, uc_ai_a2a.c_route_jsonrpc, 'POST', p_body => '{"jsonrpc":"2.0","id":3}', p_headers => hdrs(g_key_a)
    );
    ut.expect(rpc_error_code(l_resp), 'invalid request').to_equal(-32600);
    ut.expect(jbody(l_resp).get_number('id')).to_equal(3);

    -- method not found
    l_resp := rpc(gc_ep_echo, 'NoSuchMethod');
    ut.expect(rpc_error_code(l_resp), 'method').to_equal(-32601);
    ut.expect(jbody(l_resp).get_number('id')).to_equal(7);

    -- params that are not an object
    l_resp := uc_ai_a2a.process_request(
      gc_ep_echo, uc_ai_a2a.c_route_jsonrpc, 'POST'
    , p_body => '{"jsonrpc":"2.0","id":4,"method":"GetTask","params":[1]}', p_headers => hdrs(g_key_a)
    );
    ut.expect(rpc_error_code(l_resp), 'params').to_equal(-32602);

    -- GET is not allowed
    l_resp := uc_ai_a2a.process_request(gc_ep_echo, uc_ai_a2a.c_route_jsonrpc, 'GET', p_headers => hdrs(g_key_a));
    ut.expect(rpc_error_code(l_resp), 'GET').to_equal(-32600);
  end rpc_protocol_errors;


  procedure rpc_legacy_and_version
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    <<legacy_loop>>
    for m in (
      select column_value as method_name
        from table(sys.odcivarchar2list(
          'message/send', 'message/stream', 'tasks/get', 'tasks/cancel', 'tasks/resubscribe'
        , 'tasks/pushNotificationConfig/set', 'agent/getAuthenticatedExtendedCard'))
    ) loop
      l_resp := rpc(gc_ep_echo, m.method_name);
      ut.expect(rpc_error_code(l_resp), m.method_name).to_equal(-32009);
      ut.expect(jbody(l_resp).get_object('error').get_string('message'), m.method_name).to_be_like('%1.0%');
    end loop legacy_loop;

    -- an A2A-Version other than 1.0 / 1
    l_resp := rpc(gc_ep_echo, 'ListTasks', p_version => '0.3');
    ut.expect(rpc_error_code(l_resp), 'version 0.3').to_equal(-32009);
    l_resp := rpc(gc_ep_echo, 'ListTasks', p_version => '2.0');
    ut.expect(rpc_error_code(l_resp), 'version 2.0').to_equal(-32009);

    -- the supported values, and no header, work
    l_resp := rpc(gc_ep_echo, 'ListTasks', p_version => '1.0');
    ut.expect(jbody(l_resp).has('result'), 'version 1.0').to_be_true();
    l_resp := rpc(gc_ep_echo, 'ListTasks', p_version => '1');
    ut.expect(jbody(l_resp).has('result'), 'version 1').to_be_true();
    l_resp := rpc(gc_ep_echo, 'ListTasks');
    ut.expect(jbody(l_resp).has('result'), 'no header').to_be_true();

    -- REST: 400 VERSION_NOT_SUPPORTED
    l_resp := uc_ai_a2a.process_request(
      gc_ep_echo, uc_ai_a2a.c_route_rest, 'GET', p_path => 'tasks', p_headers => hdrs(g_key_a, '0.3')
    );
    ut.expect(l_resp.status).to_equal(400);
    ut.expect(jbody(l_resp).get_object('error').get_array('details').to_string).to_be_like('%VERSION_NOT_SUPPORTED%');
  end rpc_legacy_and_version;


  procedure rpc_get_task_history_length
  as
    l_task  json_object_t := send_text(gc_ep_echo, 'history');
    l_id    varchar2(36 char) := l_task.get_string('id');
    l_got   json_object_t;
  begin
    l_got := rpc_task_get(l_id, null);
    ut.expect(l_got.get_string('id'), 'unset').to_equal(l_id);
    ut.expect(hist_size(l_got), 'unset').to_equal(2);

    l_got := rpc_task_get(l_id, 0);
    ut.expect(hist_size(l_got), 'zero').to_equal(0);
    -- the artifact stays
    ut.expect(artifact_text(l_got), 'zero artifact').to_equal('echo: history');

    l_got := rpc_task_get(l_id, 1);
    ut.expect(hist_size(l_got), 'one').to_equal(1);
  end rpc_get_task_history_length;


  procedure rpc_list_tasks_paging
  as
    c_ctx   constant varchar2(50 char) := 'test-a2a-ctx-page';
    l_t1    json_object_t := send_text(gc_ep_echo, 'one', p_context_id => c_ctx);
    l_t2    json_object_t := send_text(gc_ep_echo, 'two', p_context_id => c_ctx);
    l_t3    json_object_t := send_text(gc_ep_echo, 'three', p_context_id => c_ctx);
    l_res   json_object_t;
    l_token varchar2(200 char);
    l_seen  varchar2(4000 char);
    l_id    varchar2(36 char);
  begin
    ut.expect(l_t3.get_string('contextId')).to_equal(c_ctx);

    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"' || c_ctx || '","pageSize":1}')).get_object('result');
    ut.expect(l_res.get_array('tasks').get_size, 'page 1 size').to_equal(1);
    ut.expect(l_res.get_number('totalSize'), 'total').to_equal(3);
    ut.expect(l_res.get_number('pageSize'), 'pageSize').to_equal(1);
    l_token := l_res.get_string('nextPageToken');
    ut.expect(l_token, 'token 1').to_be_not_null();
    l_id    := obj_at(l_res.get_array('tasks'), 0).get_string('id');
    l_seen  := l_id;

    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"' || c_ctx || '","pageSize":1,"pageToken":"' || l_token || '"}')).get_object('result');
    ut.expect(l_res.get_array('tasks').get_size, 'page 2 size').to_equal(1);
    ut.expect(l_res.get_number('totalSize'), 'total 2').to_equal(3);
    l_token := l_res.get_string('nextPageToken');
    ut.expect(l_token, 'token 2').to_be_not_null();
    l_id    := obj_at(l_res.get_array('tasks'), 0).get_string('id');
    ut.expect(l_seen, 'page 2 is new').not_to_be_like('%' || l_id || '%');
    l_seen  := l_seen || l_id;

    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"' || c_ctx || '","pageSize":1,"pageToken":"' || l_token || '"}')).get_object('result');
    ut.expect(l_res.get_array('tasks').get_size, 'page 3 size').to_equal(1);
    l_id := obj_at(l_res.get_array('tasks'), 0).get_string('id');
    ut.expect(l_seen, 'page 3 is new').not_to_be_like('%' || l_id || '%');
    -- the last page: the token is present and empty
    ut.expect(l_res.has('nextPageToken'), 'last token present').to_be_true();
    ut.expect(l_res.get_string('nextPageToken')).to_be_null();

    -- a listed task has no artifacts unless asked for
    ut.expect(obj_at(l_res.get_array('tasks'), 0).has('artifacts'), 'no artifacts').to_be_false();
    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"' || c_ctx || '","includeArtifacts":true,"pageSize":3}')).get_object('result');
    ut.expect(l_res.get_array('tasks').get_size, 'all on one page').to_equal(3);
    ut.expect(obj_at(l_res.get_array('tasks'), 0).has('artifacts'), 'artifacts').to_be_true();

    -- a bad page size and a bad token are -32602
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'ListTasks', '{"pageSize":0}')), 'pageSize 0').to_equal(-32602);
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'ListTasks', '{"pageSize":101}')), 'pageSize 101').to_equal(-32602);
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'ListTasks', '{"pageToken":"garbage"}')), 'token').to_equal(-32602);
    ut.expect(l_t1.get_string('id') is not null and l_t2.get_string('id') is not null).to_be_true();
  end rpc_list_tasks_paging;


  procedure rpc_list_tasks_context_filter
  as
    l_a   json_object_t := send_text(gc_ep_echo, 'ctx a', p_context_id => 'test-a2a-ctx-filter-a');
    l_b   json_object_t := send_text(gc_ep_echo, 'ctx b', p_context_id => 'test-a2a-ctx-filter-b');
    l_res json_object_t;
  begin
    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"test-a2a-ctx-filter-a"}')).get_object('result');
    ut.expect(l_res.get_number('totalSize')).to_equal(1);
    ut.expect(obj_at(l_res.get_array('tasks'), 0).get_string('id')).to_equal(l_a.get_string('id'));

    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"test-a2a-ctx-filter-b"}')).get_object('result');
    ut.expect(l_res.get_number('totalSize')).to_equal(1);
    ut.expect(obj_at(l_res.get_array('tasks'), 0).get_string('id')).to_equal(l_b.get_string('id'));

    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"test-a2a-ctx-filter-none"}')).get_object('result');
    ut.expect(l_res.get_number('totalSize')).to_equal(0);
    ut.expect(l_res.get_array('tasks').get_size).to_equal(0);

    -- the status filter
    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"test-a2a-ctx-filter-a","status":"TASK_STATE_FAILED"}')).get_object('result');
    ut.expect(l_res.get_number('totalSize'), 'failed').to_equal(0);
    l_res := jbody(rpc(gc_ep_echo, 'ListTasks', '{"contextId":"test-a2a-ctx-filter-a","status":"TASK_STATE_COMPLETED"}')).get_object('result');
    ut.expect(l_res.get_number('totalSize'), 'completed').to_equal(1);
  end rpc_list_tasks_context_filter;


  procedure rpc_cancel_completed_task
  as
    l_task json_object_t := send_text(gc_ep_echo, 'cancel me');
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_echo, 'CancelTask', '{"id":"' || l_task.get_string('id') || '"}');
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(rpc_error_code(l_resp)).to_equal(-32002);
    ut.expect(jbody(l_resp).get_object('error').get_array('data').to_string).to_be_like('%TASK_NOT_CANCELABLE%');
    ut.expect(db_state(l_task.get_string('id'))).to_equal(uc_ai_a2a_core.c_state_completed);
  end rpc_cancel_completed_task;


  procedure rpc_duplicate_message_id
  as
    l_first  json_object_t := send_text(gc_ep_echo, 'dup', p_message_id => 'm-dup');
    l_second json_object_t := send_text(gc_ep_echo, 'dup again', p_message_id => 'm-dup');
    l_count  number;
  begin
    ut.expect(l_second.get_string('id')).to_equal(l_first.get_string('id'));
    -- the second request did not run the agent
    ut.expect(artifact_text(l_second)).to_equal('echo: dup');

    select count(*) into l_count from uc_ai_a2a_tasks where message_id = 'm-dup';
    ut.expect(l_count).to_equal(1);

    -- another client may use the same messageId
    ut.expect(send_text(gc_ep_echo, 'dup', g_key_b, p_message_id => 'm-dup').get_string('id')).not_to_equal(l_first.get_string('id'));
  end rpc_duplicate_message_id;


  procedure rpc_follow_up_same_context
  as
    l_first  json_object_t := send_text(gc_ep_echo, 'turn one');
    l_second json_object_t;
  begin
    l_second := send_text(gc_ep_echo, 'turn two', p_context_id => l_first.get_string('contextId'));
    ut.expect(l_second.get_string('id')).not_to_equal(l_first.get_string('id'));
    ut.expect(l_second.get_string('contextId')).to_equal(l_first.get_string('contextId'));
    ut.expect(state_of(l_second)).to_equal('TASK_STATE_COMPLETED');
    ut.expect(artifact_text(l_second)).to_equal('echo: turn two');
  end rpc_follow_up_same_context;


  procedure rpc_foreign_context_rejected
  as
    l_task json_object_t := send_text(gc_ep_echo, 'mine');
    l_resp uc_ai_a2a.t_http_response;
    l_text varchar2(4000 char);
  begin
    -- client B reuses the context of client A
    l_resp := rpc(gc_ep_echo, 'SendMessage', text_params('steal', p_context_id => l_task.get_string('contextId')), g_key_b);
    ut.expect(rpc_error_code(l_resp), 'foreign').to_equal(-32602);
    l_text := jbody(l_resp).get_object('error').get_string('message');

    -- a malformed context gives the same answer
    l_resp := rpc(gc_ep_echo, 'SendMessage', text_params('x', p_context_id => 'has space/and slash'));
    ut.expect(rpc_error_code(l_resp), 'malformed').to_equal(-32602);
    ut.expect(jbody(l_resp).get_object('error').get_string('message'), 'same text').to_equal(l_text);
  end rpc_foreign_context_rejected;


  procedure rpc_task_of_other_client
  as
    l_task json_object_t := send_text(gc_ep_echo, 'private');
    l_id   varchar2(36 char) := l_task.get_string('id');
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_echo, 'GetTask', '{"id":"' || l_id || '"}', g_key_b);
    ut.expect(rpc_error_code(l_resp), 'GetTask').to_equal(-32001);

    l_resp := rpc(gc_ep_echo, 'CancelTask', '{"id":"' || l_id || '"}', g_key_b);
    ut.expect(rpc_error_code(l_resp), 'CancelTask').to_equal(-32001);

    l_resp := rpc(gc_ep_echo, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_id || '","url":"' || gc_push_url || '"}', g_key_b);
    ut.expect(rpc_error_code(l_resp), 'push').to_equal(-32001);

    -- the same answer as for a task that does not exist
    l_resp := rpc(gc_ep_echo, 'GetTask', '{"id":"00000000-0000-4000-8000-000000000000"}', g_key_b);
    ut.expect(rpc_error_code(l_resp), 'missing').to_equal(-32001);

    -- B does not see the task in its list
    l_resp := rpc(gc_ep_echo, 'ListTasks', '{"contextId":"' || l_task.get_string('contextId') || '"}', g_key_b);
    ut.expect(jbody(l_resp).get_object('result').get_number('totalSize')).to_equal(0);

    -- A still does
    l_resp := rpc(gc_ep_echo, 'GetTask', '{"id":"' || l_id || '"}', g_key_a);
    ut.expect(jbody(l_resp).get_object('result').get_string('id')).to_equal(l_id);
  end rpc_task_of_other_client;


  procedure rpc_task_id_in_message_unsupported
  as
    l_task json_object_t := send_text(gc_ep_echo, 'finished');
    l_resp uc_ai_a2a.t_http_response;
  begin
    -- a task in a final state cannot take more messages
    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"text":"more"}]', p_task_id => l_task.get_string('id')));
    ut.expect(rpc_error_code(l_resp), 'terminal').to_equal(-32004);

    -- a task that is not the caller's
    l_resp := rpc(gc_ep_echo, 'SendMessage', params_of('[{"text":"more"}]', p_task_id => l_task.get_string('id')), g_key_b);
    ut.expect(rpc_error_code(l_resp), 'foreign').to_equal(-32001);
  end rpc_task_id_in_message_unsupported;


  procedure rpc_extended_card
  as
    l_resp uc_ai_a2a.t_http_response;
    l_card json_object_t;
  begin
    l_resp := rpc(gc_ep_echo, 'GetExtendedAgentCard', '{}', null);
    ut.expect(l_resp.status, 'no key').to_equal(401);

    l_resp := rpc(gc_ep_echo, 'GetExtendedAgentCard');
    ut.expect(l_resp.status).to_equal(200);
    l_card := jbody(l_resp).get_object('result');
    ut.expect(l_card.get_string('name')).to_equal('Test Echo');
    -- the extended skill description holds the input schema
    ut.expect(obj_at(l_card.get_array('skills'), 0).get_string('description')).to_be_like('%text%');
    ut.expect(length(obj_at(l_card.get_array('skills'), 0).get_string('description'))
            > length(obj_at(jbody(card_of(gc_ep_echo)).get_array('skills'), 0).get_string('description'))).to_be_true();

    -- an endpoint without auth has no extended card
    l_resp := rpc(gc_ep_open, 'GetExtendedAgentCard', '{}', null);
    ut.expect(rpc_error_code(l_resp), 'none').to_equal(-32007);
  end rpc_extended_card;


  -- ==========================================================================
  -- REST
  -- ==========================================================================

  function rest_send(
    p_text in varchar2,
    p_key  in varchar2 default g_key_a
  ) return json_object_t
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rest(gc_ep_echo, 'POST', 'message:send', p_body => text_params(p_text), p_key => p_key);
    return jbody(l_resp).get_object('task');
  end rest_send;


  procedure rest_message_send
  as
    l_resp uc_ai_a2a.t_http_response;
    l_task json_object_t;
  begin
    l_resp := rest(gc_ep_echo, 'POST', 'message:send', p_body => text_params('rest hi'));
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(l_resp.content_type).to_equal('application/a2a+json');
    l_task := jbody(l_resp).get_object('task');
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_COMPLETED');
    ut.expect(artifact_text(l_task)).to_equal('echo: rest hi');

    -- errors: an empty and a broken body
    l_resp := rest(gc_ep_echo, 'POST', 'message:send', p_body => null);
    ut.expect(l_resp.status, 'no body').to_equal(400);
    l_resp := rest(gc_ep_echo, 'POST', 'message:send', p_body => '{broken');
    ut.expect(l_resp.status, 'broken body').to_equal(400);
    l_resp := rest(gc_ep_echo, 'POST', 'message:send', p_body => params_of('[]'));
    ut.expect(l_resp.status, 'no parts').to_equal(400);
    ut.expect(jbody(l_resp).get_object('error').get_string('status'), 'no parts').to_equal('INVALID_ARGUMENT');
    -- no key
    l_resp := rest(gc_ep_echo, 'POST', 'message:send', p_body => text_params('x'), p_key => null);
    ut.expect(l_resp.status, 'no key').to_equal(401);
    -- unknown path
    l_resp := rest(gc_ep_echo, 'GET', 'nothing/here');
    ut.expect(l_resp.status, 'unknown path').to_equal(404);
  end rest_message_send;


  procedure rest_get_task
  as
    l_task json_object_t := rest_send('rest get');
    l_id   varchar2(36 char) := l_task.get_string('id');
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rest(gc_ep_echo, 'GET', 'tasks/' || l_id);
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(l_resp.content_type).to_equal('application/a2a+json');
    ut.expect(jbody(l_resp).get_string('id')).to_equal(l_id);
    ut.expect(hist_size(jbody(l_resp)), 'history').to_equal(2);

    l_resp := rest(gc_ep_echo, 'GET', 'tasks/' || l_id, p_query => 'historyLength=0');
    ut.expect(hist_size(jbody(l_resp)), 'history 0').to_equal(0);

    -- another client
    l_resp := rest(gc_ep_echo, 'GET', 'tasks/' || l_id, p_key => g_key_b);
    ut.expect(l_resp.status, 'other client').to_equal(404);
  end rest_get_task;


  procedure rest_list_tasks
  as
    c_ctx constant varchar2(50 char) := 'test-a2a-ctx-rest';
    l_t1  json_object_t := send_text(gc_ep_echo, 'r1', p_context_id => c_ctx);
    l_t2  json_object_t := send_text(gc_ep_echo, 'r2', p_context_id => c_ctx);
    l_t3  json_object_t := send_text(gc_ep_echo, 'other', p_context_id => 'test-a2a-ctx-rest-2');
    l_resp uc_ai_a2a.t_http_response;
    l_res  json_object_t;
  begin
    l_resp := rest(gc_ep_echo, 'GET', 'tasks', p_query => 'contextId=' || c_ctx || '&pageSize=1');
    ut.expect(l_resp.status).to_equal(200);
    l_res := jbody(l_resp);
    ut.expect(l_res.get_array('tasks').get_size).to_equal(1);
    ut.expect(l_res.get_number('totalSize')).to_equal(2);
    ut.expect(l_res.get_string('nextPageToken')).to_be_not_null();

    l_resp := rest(gc_ep_echo, 'GET', 'tasks', p_query => 'contextId=' || c_ctx || '&pageSize=1&pageToken=' || l_res.get_string('nextPageToken'));
    l_res := jbody(l_resp);
    ut.expect(l_res.get_array('tasks').get_size, 'page 2').to_equal(1);
    ut.expect(l_res.get_string('nextPageToken'), 'last page').to_be_null();

    l_resp := rest(gc_ep_echo, 'GET', 'tasks', p_query => 'contextId=test-a2a-ctx-rest-2&includeArtifacts=true');
    l_res := jbody(l_resp);
    ut.expect(l_res.get_number('totalSize'), 'other context').to_equal(1);
    ut.expect(obj_at(l_res.get_array('tasks'), 0).has('artifacts'), 'artifacts').to_be_true();
    ut.expect(l_t1.has('id') and l_t2.has('id') and l_t3.has('id')).to_be_true();
  end rest_list_tasks;


  procedure rest_cancel_completed_task
  as
    l_task json_object_t := rest_send('rest cancel');
    l_resp uc_ai_a2a.t_http_response;
    l_err  json_object_t;
  begin
    l_resp := rest(gc_ep_echo, 'POST', 'tasks/' || l_task.get_string('id') || ':cancel', p_body => '{}');
    ut.expect(l_resp.status).to_equal(400);
    l_err := jbody(l_resp).get_object('error');
    ut.expect(l_err.get_number('code')).to_equal(400);
    ut.expect(l_err.get_string('status')).to_equal('FAILED_PRECONDITION');
    ut.expect(obj_at(l_err.get_array('details'), 0).get_string('reason')).to_equal('TASK_NOT_CANCELABLE');
  end rest_cancel_completed_task;


  procedure rest_unknown_task_and_error_shape
  as
    l_resp   uc_ai_a2a.t_http_response;
    l_err    json_object_t;
    l_detail json_object_t;
  begin
    l_resp := rest(gc_ep_echo, 'GET', 'tasks/00000000-0000-4000-8000-000000000000');
    ut.expect(l_resp.status).to_equal(404);
    ut.expect(l_resp.content_type).to_equal('application/a2a+json');

    l_err := jbody(l_resp).get_object('error');
    ut.expect(l_err.get_number('code')).to_equal(404);
    ut.expect(l_err.get_string('status')).to_equal('NOT_FOUND');
    ut.expect(l_err.get_string('message')).to_be_not_null();
    l_detail := obj_at(l_err.get_array('details'), 0);
    ut.expect(l_detail.get_string('@type')).to_equal('type.googleapis.com/google.rpc.ErrorInfo');
    ut.expect(l_detail.get_string('reason')).to_equal('TASK_NOT_FOUND');
    ut.expect(l_detail.get_string('domain')).to_equal('a2a-protocol.org');
    ut.expect(l_resp.body).not_to_be_like('%ORA-%');

    -- a JSON-RPC error carries the same ErrorInfo
    l_resp := rpc(gc_ep_echo, 'GetTask', '{"id":"00000000-0000-4000-8000-000000000000"}');
    l_detail := obj_at(jbody(l_resp).get_object('error').get_array('data'), 0);
    ut.expect(l_detail.get_string('reason'), 'jsonrpc reason').to_equal('TASK_NOT_FOUND');
    ut.expect(l_detail.get_string('domain'), 'jsonrpc domain').to_equal('a2a-protocol.org');
  end rest_unknown_task_and_error_shape;


  procedure rest_extended_card
  as
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rest(gc_ep_echo, 'GET', 'extendedAgentCard');
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(jbody(l_resp).get_string('name')).to_equal('Test Echo');

    l_resp := rest(gc_ep_echo, 'GET', 'extendedAgentCard', p_key => null);
    ut.expect(l_resp.status, 'no key').to_equal(401);

    l_resp := rest(gc_ep_open, 'GET', 'extendedAgentCard', p_key => null);
    ut.expect(l_resp.status, 'none').to_equal(400);
    ut.expect(jbody(l_resp).get_object('error').get_array('details').to_string).to_be_like('%EXTENDED_AGENT_CARD_NOT_CONFIGURED%');
  end rest_extended_card;


  -- ==========================================================================
  -- Streaming
  -- ==========================================================================

  procedure stream_jsonrpc_events
  as
    l_resp   uc_ai_a2a.t_http_response;
    l_events json_array_t;
    l_first  json_object_t;
    l_last   json_object_t;
  begin
    l_resp := rpc(gc_ep_echo, 'SendStreamingMessage', text_params('stream me'));
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(l_resp.content_type).to_equal('text/event-stream');
    ut.expect(l_resp.body).to_be_like('data: %');

    l_events := sse_events(l_resp.body);
    ut.expect(l_events.get_size).to_be_greater_than(1);

    -- every event is a JSON-RPC response
    <<wrap_loop>>
    for i in 0 .. l_events.get_size - 1 loop
      ut.expect(obj_at(l_events, i).get_string('jsonrpc'), 'jsonrpc ' || i).to_equal('2.0');
      ut.expect(obj_at(l_events, i).get_number('id'), 'id ' || i).to_equal(7);
      ut.expect(obj_at(l_events, i).has('result'), 'result ' || i).to_be_true();
    end loop wrap_loop;

    l_first := obj_at(l_events, 0).get_object('result');
    ut.expect(l_first.has('task'), 'first is a task').to_be_true();
    ut.expect(state_of(l_first.get_object('task'))).to_equal('TASK_STATE_WORKING');

    l_last := obj_at(l_events, l_events.get_size - 1).get_object('result');
    ut.expect(l_last.has('statusUpdate'), 'last is a status update').to_be_true();
    ut.expect(l_last.get_object('statusUpdate').get_object('status').get_string('state')).to_equal('TASK_STATE_COMPLETED');
    ut.expect(l_last.get_object('statusUpdate').get_string('taskId')).to_equal(l_first.get_object('task').get_string('id'));

    ut.expect(l_resp.body).to_be_like('%artifactUpdate%');
    ut.expect(l_resp.body).to_be_like('%echo: stream me%');

    -- an error before the first event is a plain error response
    l_resp := rpc(gc_ep_echo, 'SendStreamingMessage', params_of('[]'));
    ut.expect(l_resp.content_type).to_equal('application/json');
    ut.expect(rpc_error_code(l_resp)).to_equal(-32602);
  end stream_jsonrpc_events;


  procedure stream_rest_events
  as
    l_resp   uc_ai_a2a.t_http_response;
    l_events json_array_t;
    l_last   json_object_t;
  begin
    l_resp := rest(gc_ep_echo, 'POST', 'message:stream', p_body => text_params('rest stream'));
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(l_resp.content_type).to_equal('text/event-stream');

    l_events := sse_events(l_resp.body);
    ut.expect(obj_at(l_events, 0).has('task'), 'first is a task').to_be_true();
    -- no JSON-RPC wrapper
    ut.expect(obj_at(l_events, 0).has('jsonrpc'), 'no wrapper').to_be_false();
    l_last := obj_at(l_events, l_events.get_size - 1);
    ut.expect(l_last.get_object('statusUpdate').get_object('status').get_string('state')).to_equal('TASK_STATE_COMPLETED');
  end stream_rest_events;


  -- ==========================================================================
  -- Failure
  -- ==========================================================================

  procedure failure_hides_internals
  as
    l_resp uc_ai_a2a.t_http_response;
    l_task json_object_t;
    l_msg  json_object_t;
    l_got  uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_fail, 'SendMessage', params_of('[{"data":{"x":1}}]'), null);
    ut.expect(l_resp.status).to_equal(200);
    l_task := rpc_task(l_resp);
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_FAILED');

    l_msg := l_task.get_object('status').get_object('message');
    ut.expect(l_msg.get_string('role')).to_equal('ROLE_AGENT');
    ut.expect(obj_at(l_msg.get_array('parts'), 0).get_string('text')).to_equal('The agent run failed.');

    -- nothing of the error text in the answer
    ut.expect(l_resp.body).not_to_be_like('%ORA-%');
    ut.expect(l_resp.body).not_to_be_like('%boom%');
    ut.expect(l_resp.body).not_to_be_like('%secret%');
    ut.expect(l_resp.body).not_to_be_like('%01017%');

    -- GetTask and the REST binding say the same
    l_got := rpc(gc_ep_fail, 'GetTask', '{"id":"' || l_task.get_string('id') || '"}', null);
    ut.expect(l_got.body).not_to_be_like('%ORA-%');
    ut.expect(l_got.body).not_to_be_like('%boom%');
    ut.expect(l_got.body).to_be_like('%The agent run failed.%');

    l_got := rest(gc_ep_fail, 'POST', 'message:send', p_body => params_of('[{"data":{"x":1}}]'), p_key => null);
    ut.expect(l_got.status).to_equal(200);
    ut.expect(l_got.body).to_be_like('%TASK_STATE_FAILED%');
    ut.expect(l_got.body).not_to_be_like('%ORA-%');
    ut.expect(l_got.body).not_to_be_like('%boom%');

    -- and in a stream
    l_got := rpc(gc_ep_fail, 'SendStreamingMessage', params_of('[{"data":{"x":1}}]'), null);
    ut.expect(l_got.body).to_be_like('%TASK_STATE_FAILED%');
    ut.expect(l_got.body).not_to_be_like('%ORA-%');
    ut.expect(l_got.body).not_to_be_like('%boom%');

    -- the status message is stored for the task
    ut.expect(db_state(l_task.get_string('id'))).to_equal(uc_ai_a2a_core.c_state_failed);
  end failure_hides_internals;


  procedure failed_run_rolls_back_writes
  as
    l_marker varchar2(100 char) := 'txw-' || next_id;
    l_task   json_object_t;
  begin
    l_task := rpc_task(rpc(gc_ep_txw, 'SendMessage', params_of('[{"text":"' || l_marker || '"}]'), null));
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_FAILED');
    -- the first step wrote the row in the same session; the failed run took it back
    ut.expect(tx_rows(l_marker)).to_equal(0);
  end failed_run_rolls_back_writes;


  procedure completed_run_commits_writes
  as
    l_marker varchar2(100 char) := 'txok-' || next_id;
    l_task   json_object_t;
  begin
    l_task := rpc_task(rpc(gc_ep_txok, 'SendMessage', params_of('[{"text":"' || l_marker || '"}]'), null));
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_COMPLETED');
    -- committed by the server, so a rollback of the caller cannot take it back
    rollback;
    ut.expect(tx_rows(l_marker)).to_equal(1);
  end completed_run_commits_writes;


  -- ==========================================================================
  -- Push notifications
  -- ==========================================================================

  procedure push_config_crud
  as
    l_task  json_object_t := send_text(gc_ep_echo, 'push crud');
    l_id    varchar2(36 char) := l_task.get_string('id');
    l_resp  uc_ai_a2a.t_http_response;
    l_cfg   json_object_t;
    l_list  json_object_t;
    l_first_cfg varchar2(255 char);
  begin
    -- create with a client id, a token and authentication
    l_resp := rpc(
      gc_ep_echo, 'CreateTaskPushNotificationConfig'
    , '{"taskId":"' || l_id || '","id":"cfg-1","url":"' || gc_push_url || '","token":"tok-1","authentication":{"scheme":"Bearer","credentials":"abc"}}'
    );
    ut.expect(l_resp.status).to_equal(200);
    l_cfg := jbody(l_resp).get_object('result');
    ut.expect(l_cfg.get_string('id')).to_equal('cfg-1');
    ut.expect(l_cfg.get_string('taskId')).to_equal(l_id);
    ut.expect(l_cfg.get_string('url')).to_equal(gc_push_url);
    ut.expect(l_cfg.get_string('token')).to_equal('tok-1');
    ut.expect(l_cfg.get_object('authentication').get_string('scheme')).to_equal('Bearer');

    -- create without an id: the server picks one
    l_resp := rpc(gc_ep_echo, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_id || '","url":"' || gc_push_url || '/2"}');
    l_cfg := jbody(l_resp).get_object('result');
    l_first_cfg := l_cfg.get_string('id');
    ut.expect(l_first_cfg, 'generated id').to_be_not_null();

    -- get
    l_resp := rpc(gc_ep_echo, 'GetTaskPushNotificationConfig', '{"taskId":"' || l_id || '","id":"cfg-1"}');
    ut.expect(jbody(l_resp).get_object('result').get_string('url')).to_equal(gc_push_url);

    -- list
    l_resp := rpc(gc_ep_echo, 'ListTaskPushNotificationConfigs', '{"taskId":"' || l_id || '"}');
    l_list := jbody(l_resp).get_object('result');
    ut.expect(l_list.get_array('configs').get_size).to_equal(2);

    -- delete, twice: the second delete is not an error
    l_resp := rpc(gc_ep_echo, 'DeleteTaskPushNotificationConfig', '{"taskId":"' || l_id || '","id":"cfg-1"}');
    ut.expect(l_resp.status, 'delete').to_equal(200);
    ut.expect(jbody(l_resp).has('error'), 'delete error').to_be_false();
    ut.expect(jbody(l_resp).get_object('result').get_size, 'delete result').to_equal(0);
    l_resp := rpc(gc_ep_echo, 'DeleteTaskPushNotificationConfig', '{"taskId":"' || l_id || '","id":"cfg-1"}');
    ut.expect(jbody(l_resp).has('error'), 'second delete error').to_be_false();

    -- it is gone
    l_resp := rpc(gc_ep_echo, 'GetTaskPushNotificationConfig', '{"taskId":"' || l_id || '","id":"cfg-1"}');
    ut.expect(jbody(l_resp).has('error'), 'get after delete').to_be_true();
    l_resp := rpc(gc_ep_echo, 'ListTaskPushNotificationConfigs', '{"taskId":"' || l_id || '"}');
    ut.expect(jbody(l_resp).get_object('result').get_array('configs').get_size).to_equal(1);

    -- the task of another client
    l_resp := rpc(gc_ep_echo, 'ListTaskPushNotificationConfigs', '{"taskId":"' || l_id || '"}', g_key_b);
    ut.expect(rpc_error_code(l_resp), 'other client').to_equal(-32001);
  end push_config_crud;


  procedure push_config_rejects_bad_url
  as
    l_task json_object_t := send_text(gc_ep_echo, 'push bad');
    l_id   varchar2(36 char) := l_task.get_string('id');
  begin
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_id || '","url":"ftp://x.example/hook"}')), 'ftp').to_equal(-32602);
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_id || '","url":"not a url"}')), 'text').to_equal(-32602);
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_id || '"}')), 'no url').to_equal(-32602);
    ut.expect(rpc_error_code(rpc(gc_ep_echo, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_id || '","id":"bad id!","url":"' || gc_push_url || '"}')), 'bad id').to_equal(-32602);

    -- a configuration on SendMessage is checked before the agent runs
    ut.expect(rpc_error_code(rpc(
      gc_ep_echo, 'SendMessage'
    , text_params('x', p_config => '{"taskPushNotificationConfig":{"url":"ftp://x.example"}}')
    )), 'send').to_equal(-32602);
  end push_config_rejects_bad_url;


  procedure push_not_supported_without_async
  as
    l_task json_object_t := send_text(gc_ep_noasync, 'no push', null);
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rpc(gc_ep_noasync, 'CreateTaskPushNotificationConfig', '{"taskId":"' || l_task.get_string('id') || '","url":"' || gc_push_url || '"}', null);
    ut.expect(rpc_error_code(l_resp)).to_equal(-32003);
    ut.expect(jbody(l_resp).get_object('error').get_array('data').to_string).to_be_like('%PUSH_NOTIFICATION_NOT_SUPPORTED%');

    l_resp := rest(
      gc_ep_noasync, 'POST', 'tasks/' || l_task.get_string('id') || '/pushNotificationConfigs'
    , p_body => '{"url":"' || gc_push_url || '"}', p_key => null
    );
    ut.expect(l_resp.status, 'rest').to_equal(400);

    -- the same on SendMessage
    l_resp := rpc(
      gc_ep_noasync, 'SendMessage'
    , text_params('x', p_config => '{"taskPushNotificationConfig":{"url":"' || gc_push_url || '"}}'), null
    );
    ut.expect(rpc_error_code(l_resp), 'send').to_equal(-32003);
  end push_not_supported_without_async;


  procedure push_delivery_on_completion
  as
    l_task json_object_t;
    l_req  uc_ai_test_http_mock.t_request;
    l_body json_object_t;
    l_status number;
    l_tid    varchar2(36 char);
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
    uc_ai_test_http_mock.reset;
    uc_ai_test_http_mock.enqueue('{}', 200);

    l_task := send_text(
      gc_ep_echo, 'push me'
    , p_config => '{"taskPushNotificationConfig":{"url":"' || gc_push_url || '","token":"tok-123","authentication":{"scheme":"Bearer","credentials":"s3cret"}}}'
    );
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_COMPLETED');
    l_tid := l_task.get_string('id');

    ut.expect(uc_ai_test_http_mock.request_count, 'one POST').to_equal(1);
    l_req := uc_ai_test_http_mock.request(1);
    ut.expect(l_req.url).to_equal(gc_push_url);

    l_body := json_object_t.parse(l_req.body);
    ut.expect(l_body.get_object('task').get_string('id')).to_equal(l_task.get_string('id'));
    ut.expect(l_body.get_object('task').get_object('status').get_string('state')).to_equal('TASK_STATE_COMPLETED');
    ut.expect(artifact_text(l_body.get_object('task'))).to_equal('echo: push me');

    ut.expect(uc_ai_test_http_mock.request_header(1, 'X-A2A-Notification-Token')).to_equal('tok-123');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization')).to_equal('Bearer s3cret');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type')).to_be_like('application/%json');

    -- the outcome is recorded on the configuration
    select max(last_status)
      into l_status
      from uc_ai_a2a_push_configs
     where task_id = l_tid;
    ut.expect(l_status).to_equal(200);

    -- a task without a configuration sends nothing
    uc_ai_test_http_mock.reset;
    l_task := send_text(gc_ep_echo, 'no push');
    ut.expect(uc_ai_test_http_mock.request_count, 'no config').to_equal(0);

    uc_ai_http.set_transport(null);
  end push_delivery_on_completion;


  procedure push_delivery_failure_is_recorded
  as
    l_task  json_object_t;
    l_error uc_ai_a2a_push_configs.last_error%type;
    l_status uc_ai_a2a_push_configs.last_status%type;
    l_tid    varchar2(36 char);
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
    uc_ai_test_http_mock.reset;
    -- the receiver answers 500
    uc_ai_test_http_mock.enqueue('{"error":"down"}', 500);

    l_task := send_text(
      gc_ep_echo, 'push fails'
    , p_config => '{"taskPushNotificationConfig":{"url":"' || gc_push_url || '"}}'
    );
    ut.expect(state_of(l_task), 'the task is not affected').to_equal('TASK_STATE_COMPLETED');
    l_tid := l_task.get_string('id');
    ut.expect(uc_ai_test_http_mock.request_count).to_equal(1);

    select max(last_status), max(last_error)
      into l_status, l_error
      from uc_ai_a2a_push_configs
     where task_id = l_tid;
    ut.expect(l_status is not null and l_status <> 200 or l_error is not null, 'failure recorded').to_be_true();

    -- a transport that raises does not fail the task either (no response queued)
    uc_ai_test_http_mock.reset;
    l_task := send_text(
      gc_ep_echo, 'push raises'
    , p_config => '{"taskPushNotificationConfig":{"url":"' || gc_push_url || '"}}'
    );
    ut.expect(state_of(l_task), 'raise').to_equal('TASK_STATE_COMPLETED');
    l_tid := l_task.get_string('id');
    select max(last_error)
      into l_error
      from uc_ai_a2a_push_configs
     where task_id = l_tid;
    ut.expect(l_error, 'error recorded').to_be_not_null();

    uc_ai_http.set_transport(null);
  end push_delivery_failure_is_recorded;


  procedure push_rest_config_crud
  as
    l_task json_object_t := rest_send('rest push');
    l_id   varchar2(36 char) := l_task.get_string('id');
    c_path constant varchar2(100 char) := '/pushNotificationConfigs';
    l_resp uc_ai_a2a.t_http_response;
  begin
    l_resp := rest(gc_ep_echo, 'POST', 'tasks/' || l_id || c_path, p_body => '{"id":"rc1","url":"' || gc_push_url || '","token":"t"}');
    ut.expect(l_resp.status, 'create').to_equal(200);
    ut.expect(jbody(l_resp).get_string('id')).to_equal('rc1');

    l_resp := rest(gc_ep_echo, 'GET', 'tasks/' || l_id || c_path || '/rc1');
    ut.expect(l_resp.status, 'get').to_equal(200);
    ut.expect(jbody(l_resp).get_string('url')).to_equal(gc_push_url);

    l_resp := rest(gc_ep_echo, 'GET', 'tasks/' || l_id || c_path);
    ut.expect(l_resp.status, 'list').to_equal(200);
    ut.expect(jbody(l_resp).get_array('configs').get_size).to_equal(1);

    l_resp := rest(gc_ep_echo, 'DELETE', 'tasks/' || l_id || c_path || '/rc1');
    ut.expect(l_resp.status, 'delete').to_equal(200);
    l_resp := rest(gc_ep_echo, 'DELETE', 'tasks/' || l_id || c_path || '/rc1');
    ut.expect(l_resp.status, 'delete again').to_equal(200);

    l_resp := rest(gc_ep_echo, 'GET', 'tasks/' || l_id || c_path || '/rc1');
    ut.expect(l_resp.status, 'get after delete').to_equal(404);
  end push_rest_config_crud;


  -- ==========================================================================
  -- Async runs
  -- ==========================================================================

  -- Drops the job of a task so that the scheduler does not race the test
  procedure drop_task_job(p_task_id in varchar2)
  as
    l_job uc_ai_a2a_tasks.job_name%type;
  begin
    select job_name into l_job from uc_ai_a2a_tasks where task_id = p_task_id;
    begin
      sys.dbms_scheduler.drop_job(job_name => l_job, force => true);
    exception
      when others then
        null; -- already gone: the job ran or was dropped
    end;
  end drop_task_job;


  function job_count(p_task_id in varchar2) return number
  as
    l_count number;
  begin
    select count(*)
      into l_count
      from user_scheduler_jobs j
      join uc_ai_a2a_tasks t on t.job_name = j.job_name
     where t.task_id = p_task_id;
    return l_count;
  end job_count;


  procedure async_submitted_then_run
  as
    c_wait_loops constant pls_integer := 20;
    c_async constant varchar2(400 char) := '{"returnImmediately":true,"taskPushNotificationConfig":{"url":"https://push.example/async","token":"async-token"}}';
    l_task   json_object_t;
    l_id     varchar2(36 char);
    l_job    uc_ai_a2a_tasks.job_name%type;
    l_pending number;
    l_state  varchar2(30 char);
    l_req    uc_ai_test_http_mock.t_request;
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
    uc_ai_test_http_mock.reset;
    uc_ai_test_http_mock.enqueue('{}', 200);

    l_task := send_text(gc_ep_echo, 'run later', p_config => c_async);
    l_id   := l_task.get_string('id');
    ut.expect(state_of(l_task), 'answer').to_equal('TASK_STATE_SUBMITTED');
    ut.expect(l_task.has('artifacts'), 'no artifacts yet').to_be_false();

    select job_name, case when pending_request is null then 0 else 1 end
      into l_job, l_pending
      from uc_ai_a2a_tasks where task_id = l_id;
    ut.expect(l_job, 'job name').to_equal('UC_AI_A2A_' || upper(replace(l_id, '-')));
    ut.expect(l_pending, 'pending request stored').to_equal(1);

    -- the scheduler job exists unless it has run already
    ut.expect(job_count(l_id) = 1 or db_state(l_id) <> uc_ai_a2a_core.c_state_submitted, 'job exists').to_be_true();

    -- the job of this session must not race the test
    drop_task_job(l_id);
    ut.expect(job_count(l_id), 'job dropped').to_equal(0);

    if db_state(l_id) = uc_ai_a2a_core.c_state_submitted then
      uc_ai_a2a.run_task(l_id);
    end if;

    -- a job that started before the drop finishes on its own: wait for it
    <<wait_loop>>
    for i in 1 .. c_wait_loops loop
      l_state := db_state(l_id);
      exit wait_loop when l_state = uc_ai_a2a_core.c_state_completed;
      sys.dbms_session.sleep(0.5);
    end loop wait_loop;
    ut.expect(l_state, 'after run_task').to_equal(uc_ai_a2a_core.c_state_completed);

    l_task := jbody(rpc(gc_ep_echo, 'GetTask', '{"id":"' || l_id || '"}')).get_object('result');
    ut.expect(artifact_text(l_task)).to_equal('echo: run later');

    select case when pending_request is null then 0 else 1 end into l_pending from uc_ai_a2a_tasks where task_id = l_id;
    ut.expect(l_pending, 'pending request cleared').to_equal(0);

    -- the push notification went out when the run ended (a job in another
    -- session would not use this session's transport, so only check a run of ours)
    if uc_ai_test_http_mock.request_count > 0 then
      l_req := uc_ai_test_http_mock.request(1);
      ut.expect(l_req.url).to_equal('https://push.example/async');
      ut.expect(json_object_t.parse(l_req.body).get_object('task').get_object('status').get_string('state')).to_equal('TASK_STATE_COMPLETED');
    end if;

    uc_ai_http.set_transport(null);
  end async_submitted_then_run;


  procedure async_cancel_submitted
  as
    l_task  json_object_t;
    l_id    varchar2(36 char);
    l_resp  uc_ai_a2a.t_http_response;
    l_exec  uc_ai_a2a_tasks.execution_id%type;
  begin
    l_task := send_text(gc_ep_echo, 'cancel before run', p_config => '{"returnImmediately":true}');
    l_id   := l_task.get_string('id');
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_SUBMITTED');

    l_resp := rpc(gc_ep_echo, 'CancelTask', '{"id":"' || l_id || '"}');
    ut.expect(l_resp.status).to_equal(200);
    ut.expect(state_of(jbody(l_resp).get_object('result')), 'cancel answer').to_equal('TASK_STATE_CANCELED');
    ut.expect(db_state(l_id), 'stored').to_equal(uc_ai_a2a_core.c_state_canceled);
    ut.expect(job_count(l_id), 'job gone').to_equal(0);

    -- a run_task that arrives later leaves the task alone
    uc_ai_a2a.run_task(l_id);
    ut.expect(db_state(l_id), 'after run_task').to_equal(uc_ai_a2a_core.c_state_canceled);
    select execution_id into l_exec from uc_ai_a2a_tasks where task_id = l_id;
    ut.expect(l_exec, 'the agent did not run').to_be_null();

    -- a canceled task cannot be canceled again
    l_resp := rpc(gc_ep_echo, 'CancelTask', '{"id":"' || l_id || '"}');
    ut.expect(rpc_error_code(l_resp), 'second cancel').to_equal(-32002);
  end async_cancel_submitted;


  procedure async_ignored_without_allow_async
  as
    l_task json_object_t;
  begin
    l_task := send_text(gc_ep_noasync, 'blocking anyway', null, p_config => '{"returnImmediately":true}');
    ut.expect(state_of(l_task)).to_equal('TASK_STATE_COMPLETED');
    ut.expect(artifact_text(l_task)).to_equal('echo: blocking anyway');
  end async_ignored_without_allow_async;


  -- ==========================================================================
  -- Card signing
  -- ==========================================================================

  procedure signing_adds_signature
  as
    l_card   json_object_t;
    l_sig    json_object_t;
    l_header json_object_t;
    l_ext    json_object_t;
  begin
    if not can_sign then
      sys.dbms_output.put_line('signing_adds_signature skipped: dbms_crypto.sign is not available');
      return;
    end if;

    uc_ai_a2a.set_card_signing_key(gc_ep_sign, 'test-kid-1', gc_test_pem, 'https://keys.example/jwks.json');
    commit;
    l_card := jbody(card_of(gc_ep_sign));

    ut.expect(l_card.get_array('signatures').get_size).to_equal(1);
    l_sig := obj_at(l_card.get_array('signatures'), 0);
    ut.expect(l_sig.get_string('protected')).to_match('^[A-Za-z0-9_-]+$');
    ut.expect(l_sig.get_string('signature')).to_match('^[A-Za-z0-9_-]+$');
    -- RS256 over a 2048 bit key: 256 bytes, 342 base64url characters
    ut.expect(length(l_sig.get_string('signature'))).to_equal(342);

    l_header := json_object_t.parse(b64url_decode(l_sig.get_string('protected')));
    ut.expect(l_header.get_string('alg')).to_equal('RS256');
    ut.expect(l_header.get_string('kid')).to_equal('test-kid-1');
    ut.expect(l_header.get_string('typ')).to_equal('JOSE');
    ut.expect(l_header.get_string('jku')).to_equal('https://keys.example/jwks.json');

    -- the card is signed, so the same card gives the same signature
    ut.expect(obj_at(jbody(card_of(gc_ep_sign)).get_array('signatures'), 0).get_string('signature')).to_equal(l_sig.get_string('signature'));

    -- the extended card carries a signature too
    l_ext := jbody(rpc(gc_ep_sign, 'GetExtendedAgentCard', '{}', g_key_sign)).get_object('result');
    ut.expect(l_ext.has('signatures'), 'extended').to_be_true();

    -- another endpoint is not affected
    ut.expect(jbody(card_of(gc_ep_echo)).has('signatures'), 'other endpoint').to_be_false();

    uc_ai_a2a.set_card_signing_key(gc_ep_sign, null, null);
    commit;
  end signing_adds_signature;


  procedure signing_rejects_bad_key
  as
  begin
    if not can_sign then
      sys.dbms_output.put_line('signing_rejects_bad_key skipped: dbms_crypto.sign is not available');
      return;
    end if;

    expect_ora(
      uc_ai_a2a.c_err_signing
    , q'#begin uc_ai_a2a.set_card_signing_key('test-a2a-sign', 'k', to_clob('-----BEGIN PRIVATE KEY-----' || chr(10) || 'bm90IGEga2V5' || chr(10) || '-----END PRIVATE KEY-----')); end;#'
    );
    -- the endpoint stays unsigned
    ut.expect(jbody(card_of(gc_ep_sign)).has('signatures')).to_be_false();
  end signing_rejects_bad_key;


  procedure signing_can_be_cleared
  as
    l_key uc_ai_a2a_endpoints.signing_key%type;
  begin
    if not can_sign then
      sys.dbms_output.put_line('signing_can_be_cleared skipped: dbms_crypto.sign is not available');
      return;
    end if;

    uc_ai_a2a.set_card_signing_key(gc_ep_sign, 'test-kid-2', gc_test_pem);
    commit;
    ut.expect(jbody(card_of(gc_ep_sign)).has('signatures'), 'signed').to_be_true();

    uc_ai_a2a.set_card_signing_key(gc_ep_sign, null, null);
    commit;
    ut.expect(jbody(card_of(gc_ep_sign)).has('signatures'), 'cleared').to_be_false();
    select signing_key into l_key from uc_ai_a2a_endpoints where code = gc_ep_sign;
    ut.expect(l_key).to_be_null();
  end signing_can_be_cleared;

end test_uc_ai_a2a;
/
