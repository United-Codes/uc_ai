create or replace package body test_uc_ai_agent_as_tool as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initializing variables in declare in test packages

  gc_sub_code    constant varchar2(50 char) := 'TEST_AAT_SUB';
  gc_parent_code constant varchar2(50 char) := 'TEST_AAT_PARENT';
  gc_split_code  constant varchar2(50 char) := 'TEST_AAT_SPLIT';
  gc_ctx_code    constant varchar2(50 char) := 'TEST_AAT_CTX';
  gc_loop_code   constant varchar2(50 char) := 'TEST_AAT_LOOP';
  gc_nosch_code  constant varchar2(50 char) := 'TEST_AAT_NOSCHEMA';
  gc_null_code   constant varchar2(50 char) := 'TEST_AAT_NULLMSG';
  gc_ver_code    constant varchar2(50 char) := 'TEST_AAT_VER';
  -- an agent code that would break out of the single-quoted literal the
  -- generated handler bakes it into, if the generator did not double the quote
  gc_quote_code  constant varchar2(50 char) := q'#TEST_AAT_Q'UOTE#';

  gc_sub_tool     constant varchar2(50 char) := 'TEST_AAT_SUB_TOOL';
  gc_missing_tool constant varchar2(50 char) := 'TEST_AAT_MISSING_TOOL';
  gc_loop_tool    constant varchar2(50 char) := 'TEST_AAT_LOOP_TOOL';

  gc_tool_tag constant varchar2(50 char) := 'test_aat';

  -- The input schema every sub-agent of this suite takes
  gc_city_schema constant varchar2(500 char) := '{
    "type": "object",
    "properties": {
      "city": { "type": "string", "description": "City to report the weather for" }
    },
    "required": ["city"]
  }';

  -- The whole handler of an agent-as-tool: one call, the same line the docs
  -- show. run_agent_as_tool strips the run context key, joins the session of
  -- the caller, and returns a failure as text.
  function agent_tool_handler(
    p_agent_code in varchar2
  ) return clob
  as
  begin
    return 'return uc_ai_agents_api.run_agent_as_tool(''' || p_agent_code || ''', :parameters);';
  end agent_tool_handler;


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


  -- Every tool of this suite carries the suite tag, also the ones the
  -- orchestrator generates under a name of its own (agent code + GUID). Purging
  -- by tag therefore clears leftovers of a run that stopped halfway.
  procedure delete_suite_tools
  as
  begin
    -- the tag rows and the parameter rows go with the tool: both foreign keys
    -- are "on delete cascade"
    delete from uc_ai_tools t
     where exists (
             select 1
               from uc_ai_tool_tags g
              where g.tool_id = t.id
                and g.tag_name = gc_tool_tag
           );
    commit;
  end delete_suite_tools;


  procedure create_workflow(
    p_code         in varchar2,
    p_def          in clob,
    p_input_schema in clob default null,
    p_version      in number default 1,
    p_status       in varchar2 default uc_ai_agents_api.c_status_active
  )
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Agent-as-tool test agent ' || p_code,
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => p_def,
      p_input_schema        => p_input_schema,
      p_version             => p_version,
      p_status              => p_status
    );
    commit; -- agents must be committed before execution (autonomous telemetry)
    ut.expect(l_id).to_be_not_null();
  end create_workflow;


  procedure create_agent_tool(
    p_tool_code  in varchar2,
    p_agent_code in varchar2,
    p_schema     in json_object_t
  )
  as
    l_id number;
  begin
    delete_tool(p_tool_code);
    l_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code     => p_tool_code,
      p_description   => 'Runs the ' || p_agent_code || ' agent',
      p_function_call => agent_tool_handler(p_agent_code),
      p_json_schema   => p_schema,
      p_tags          => apex_t_varchar2(gc_tool_tag)
    );
    commit;
    ut.expect(l_id).to_be_not_null();
  end create_agent_tool;


  -- The highest execution id that exists right now. A test takes this marker
  -- before it runs something, so it can tell its own rows from the rows an
  -- earlier test (or an earlier run of the suite) left behind.
  function exec_marker return number
  as
    l_id number;
  begin
    select coalesce(max(id), 0) into l_id from uc_ai_agent_executions;
    return l_id;
  end exec_marker;


  -- The one run of p_agent_code that happened after p_after_exec_id, optionally
  -- narrowed to a session. Reading exactly one row is part of the assertion:
  -- more than one run, or none, is a failure of the test that called this.
  procedure agent_run(
    p_after_exec_id in  number,
    p_agent_code    in  varchar2 default gc_sub_code,
    p_session_id    in  varchar2 default null,
    po_exec_id      out number,
    po_session_id   out varchar2,
    po_parent_id    out number,
    po_turn_index   out number,
    po_run_context  out clob
  )
  as
  begin
    select e.id, e.session_id, e.parent_execution_id, e.turn_index, e.run_context
      into po_exec_id, po_session_id, po_parent_id, po_turn_index, po_run_context
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
     where a.code = p_agent_code
       and e.id > p_after_exec_id
       and (p_session_id is null or e.session_id = p_session_id);
  end agent_run;


  procedure setup
  as
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- executions commit autonomously and survive rollback, so purge by pattern
    delete_suite_tools;
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_AAT%');
    commit;

    -- Sub-agent: answers a weather question from its input, no model call
    create_workflow(gc_sub_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return 'Weather in ' || json_object_t(:parameters).get_object('input').get_string('city') || ' is sunny';",
          "output_key": "answer"
        }
      ]
    }#', gc_city_schema);

    -- Caller agent: its step calls the tool the way a model would
    create_workflow(gc_parent_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return uc_ai_tools_api.execute_tool('TEST_AAT_SUB_TOOL', json_object_t(:parameters).get_object('input'));",
          "output_key": "weather"
        }
      ]
    }#');

    -- Caller agent whose step hands the handler a session id of its own
    create_workflow(gc_split_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "declare l_state json_object_t := json_object_t(:parameters); l_args json_object_t := json_object_t(); begin l_args.put('city', 'Rome'); return uc_ai_agents_api.run_agent_as_tool(p_agent_code => 'TEST_AAT_SUB', p_arguments => l_args.to_clob, p_session_id => l_state.get_object('input').get_string('sub_session')); end;",
          "output_key": "weather"
        }
      ]
    }#');

    -- Caller agent whose step hands the tool a run context with a session id of
    -- its own. The tool must not follow it: the run belongs to the conversation
    -- of this caller.
    create_workflow(gc_ctx_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "declare l_state json_object_t := json_object_t(:parameters); l_args json_object_t := json_object_t(); begin l_args.put('city', 'Turin'); return uc_ai_tools_api.execute_tool(p_tool_code => 'TEST_AAT_SUB_TOOL', p_arguments => l_args, p_run_context => l_state.get_object('input').to_clob); end;",
          "output_key": "weather"
        }
      ]
    }#');

    -- Sub-agent without an input schema: the generated tool must still work
    create_workflow(gc_nosch_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return 'no parameters needed';",
          "output_key": "answer"
        }
      ]
    }#');

    -- Sub-agent that finishes without an answer: its final_message is JSON null.
    -- A profile agent whose last turn carries no text block ends the same way.
    -- a loop workflow honours the final_message template of its definition; a
    -- template that resolves to nothing leaves final_message as a JSON null
    create_workflow(gc_null_code, q'#{
      "workflow_type": "loop",
      "steps": [
        {
          "step_type": "plsql",
          "output_key": "x",
          "plsql_function_call": "declare o json_object_t := json_object_t(); begin o.put('__control__', 'stop'); return o.to_clob; end;"
        }
      ],
      "loop_config": { "max_iterations": 2 },
      "final_message": { "expression": "null", "is_plsql_expression": true }
    }#');

    -- Circular reference: the agent calls the tool that runs the agent again
    create_workflow(gc_loop_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        {
          "step_type": "plsql",
          "plsql_function_call": "return uc_ai_tools_api.execute_tool('TEST_AAT_LOOP_TOOL', json_object_t('{}'));",
          "output_key": "again"
        }
      ]
    }#');

    -- Two versions of one agent, each with an answer of its own. Only one
    -- version of an agent can be active, so v1 is archived when v2 goes live.
    create_workflow(gc_ver_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return 'answer from v1';", "output_key": "answer" }
      ]
    }#', gc_city_schema, 1, uc_ai_agents_api.c_status_active);

    create_workflow(gc_ver_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return 'answer from v2';", "output_key": "answer" }
      ]
    }#', gc_city_schema, 2, uc_ai_agents_api.c_status_draft);

    uc_ai_agents_api.change_status(gc_ver_code, 1, uc_ai_agents_api.c_status_archived);
    uc_ai_agents_api.change_status(gc_ver_code, 2, uc_ai_agents_api.c_status_active);
    commit;

    -- An agent whose code holds a single quote
    create_workflow(gc_quote_code, q'#{
      "workflow_type": "sequential",
      "steps": [
        { "step_type": "plsql", "plsql_function_call": "return 'the quoted agent answered';", "output_key": "answer" }
      ]
    }#', gc_city_schema);

    create_agent_tool(gc_sub_tool, gc_sub_code, json_object_t(gc_city_schema));
    create_agent_tool(gc_missing_tool, 'TEST_AAT_NOT_THERE', json_object_t(gc_city_schema));

    create_agent_tool(gc_loop_tool, gc_loop_code, json_object_t('{
      "type": "object",
      "properties": {
        "note": { "type": "string", "description": "Ignored" }
      }
    }'));
  end setup;


  procedure teardown
  as
  begin
    delete_suite_tools;
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_AAT%');
    commit;
  end teardown;


  procedure tool_returns_sub_agent_answer
  as
    l_result clob;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => gc_sub_tool,
      p_arguments => json_object_t('{"city": "Berlin"}')
    );

    sys.dbms_output.put_line('tool_returns_sub_agent_answer: ' || l_result);

    ut.expect(l_result).to_equal(to_clob('Weather in Berlin is sunny'));
  end tool_returns_sub_agent_answer;


  procedure arguments_reach_sub_agent
  as
    l_result     clob;
    l_input      clob;
    l_session_id varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_sub_tool,
      p_arguments   => json_object_t('{"city": "Lisbon"}'),
      p_run_context => '{"session_id": "' || l_session_id || '"}'
    );

    ut.expect(l_result).to_equal(to_clob('Weather in Lisbon is sunny'));

    -- the stored input parameters hold the tool arguments, without the run
    -- context key the handler removed
    select e.input_parameters
      into l_input
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
     where a.code = gc_sub_code
       and e.session_id = l_session_id;

    sys.dbms_output.put_line('arguments_reach_sub_agent: ' || l_input);

    ut.expect(json_object_t(l_input).get_string('city')).to_equal('Lisbon');
    ut.expect(json_object_t(l_input).has(uc_ai.c_run_context_key)).to_be_false();
  end arguments_reach_sub_agent;


  procedure handler_tolerates_no_arguments
  as
    l_null_args clob;
    l_result    clob;
  begin
    -- a tool without parameters: the handler is called with no arguments at
    -- all, and still has to answer
    l_result := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_sub_code,
      p_arguments  => l_null_args
    );

    sys.dbms_output.put_line('handler_tolerates_no_arguments (null): ' || l_result);
    ut.expect(l_result).to_be_like('Weather in%');

    l_result := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_sub_code,
      p_arguments  => to_clob('{}')
    );

    sys.dbms_output.put_line('handler_tolerates_no_arguments (empty): ' || l_result);
    ut.expect(l_result).to_be_like('Weather in%');
  end handler_tolerates_no_arguments;


  procedure empty_context_is_stored_as_null
  as
    l_result      clob;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
  begin
    -- The tool layer always hands the handler a run context bag, an empty one
    -- when the run carries no context. Nothing must reach the execution row.
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_sub_tool,
      p_arguments   => json_object_t('{"city": "Bruges"}'),
      p_run_context => '{}'
    );

    ut.expect(l_result).to_equal(to_clob('Weather in Bruges is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    sys.dbms_output.put_line('empty_context_is_stored_as_null: exec ' || l_exec_id
      || ' context ' || coalesce(l_run_context, 'NULL'));

    ut.expect(l_run_context).to_be_null();
  end empty_context_is_stored_as_null;


  procedure bogus_context_is_ignored
  as
    l_result      clob;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_input       clob;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    -- A handler can be called with anything under the reserved key. A value
    -- that is not an object is no context: it is dropped, and it must not end
    -- up in the input parameters of the agent either.
    l_result := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_sub_code,
      p_arguments  => to_clob('{"city": "Ghent", "' || uc_ai.c_run_context_key || '": "not an object"}'),
      p_session_id => l_given_id
    );

    sys.dbms_output.put_line('bogus_context_is_ignored: ' || l_result);

    ut.expect(l_result).to_equal(to_clob('Weather in Ghent is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      p_session_id    => l_given_id,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_run_context).to_be_null();

    select input_parameters into l_input
      from uc_ai_agent_executions
     where id = l_exec_id;

    ut.expect(json_object_t(l_input).has(uc_ai.c_run_context_key)).to_be_false();
  end bogus_context_is_ignored;


  procedure outside_run_is_own_turn
  as
    l_result      clob;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_status      uc_ai_agent_executions.status%type;
    l_header      number;
  begin
    -- No agent run around this call, so there is no session to join and no
    -- parent to link to: the "session_id" key of the run context groups it.
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_sub_tool,
      p_arguments   => json_object_t('{"city": "Porto"}'),
      p_run_context => '{"session_id": "' || l_given_id || '"}'
    );

    ut.expect(l_result).to_equal(to_clob('Weather in Porto is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_session_id).to_equal(l_given_id);
    ut.expect(l_parent_id).to_be_null();
    ut.expect(l_turn_index).to_be_not_null();

    select status into l_status
      from uc_ai_agent_executions
     where id = l_exec_id;

    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    -- a top-level run always gets a session header
    select count(*) into l_header
      from uc_ai_agent_sessions
     where session_id = l_given_id;

    ut.expect(l_header).to_equal(1);
  end outside_run_is_own_turn;


  procedure session_param_beats_context
  as
    l_result      clob;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_ctx_id      varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_stray       number;
  begin
    -- Both the parameter and the run context name a session. The parameter is
    -- the choice of whoever wrote the handler, so it wins.
    l_result := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_sub_code,
      p_arguments  => to_clob('{"city": "Nice", "' || uc_ai.c_run_context_key
                              || '": {"session_id": "' || l_ctx_id || '"}}'),
      p_session_id => l_given_id
    );

    sys.dbms_output.put_line('session_param_beats_context: ' || l_result);

    ut.expect(l_result).to_equal(to_clob('Weather in Nice is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_session_id).to_equal(l_given_id);

    -- and the session the run context named stayed empty
    select count(*) into l_stray
      from uc_ai_agent_executions
     where session_id = l_ctx_id;

    ut.expect(l_stray).to_equal(0);
  end session_param_beats_context;


  procedure sub_run_links_to_parent
  as
    l_result      json_object_t;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_caller_id   number;
    l_turn_count  number;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    -- The caller passes neither a session id nor a parent id to the tool
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_parent_code,
      p_input_parameters => json_object_t('{"city": "Oslo"}'),
      p_session_id       => l_given_id
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Weather in Oslo is sunny'));

    l_caller_id := l_result.get_number('execution_id');

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    -- the run of the sub-agent joins the session and hangs under the caller
    ut.expect(l_session_id).to_equal(l_given_id);
    ut.expect(l_parent_id).to_equal(l_caller_id);
    ut.expect(l_turn_index).to_be_null();

    -- and it does not count as a turn of the conversation
    select turn_count into l_turn_count
      from uc_ai_agent_sessions
     where session_id = l_given_id;

    sys.dbms_output.put_line('sub_run_links_to_parent: turn_count = ' || l_turn_count);
    ut.expect(l_turn_count).to_equal(1);
  end sub_run_links_to_parent;


  procedure nested_run_inherits_context
  as
    l_result      json_object_t;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    -- The caller binds a run context. The tool passes none, so the sub-agent
    -- must inherit the context of the run it was started from.
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_parent_code,
      p_input_parameters => json_object_t('{"city": "Madrid"}'),
      p_session_id       => l_given_id,
      p_run_context      => json_object_t('{"tenant_id": "ACME"}')
    );

    sys.dbms_output.put_line('nested_run_inherits_context: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Weather in Madrid is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      p_session_id    => l_given_id,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(uc_ai.run_context_value(l_run_context, 'tenant_id')).to_equal('ACME');
  end nested_run_inherits_context;


  procedure explicit_session_skips_link
  as
    l_result      json_object_t;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_header      number;
    l_caller_id   varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_sub_id      varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    -- The step calls the handler with a session id of its own, which beats the
    -- session of the run around it. A run that leaves the conversation of its
    -- caller must not hang under it.
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_split_code,
      p_input_parameters => json_object_t('{"sub_session": "' || l_sub_id || '"}'),
      p_session_id       => l_caller_id
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Weather in Rome is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_session_id).to_equal(l_sub_id);
    ut.expect(l_parent_id).to_be_null();
    ut.expect(l_turn_index).to_be_not_null();

    -- an unlinked run still gets a header of its own, so reporting finds it
    select count(*) into l_header
      from uc_ai_agent_sessions
     where session_id = l_sub_id;

    ut.expect(l_header).to_equal(1);
  end explicit_session_skips_link;


  procedure ctx_session_cannot_move_run
  as
    l_result      json_object_t;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_caller_id   number;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
    l_other_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    -- The run context is user data. A "session_id" in it must not pull the run
    -- of the sub-agent out of the conversation it runs inside.
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_ctx_code,
      p_input_parameters => json_object_t('{"session_id": "' || l_other_id || '"}'),
      p_session_id       => l_given_id
    );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Weather in Turin is sunny'));
    l_caller_id := l_result.get_number('execution_id');

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_session_id).to_equal(l_given_id);
    ut.expect(l_parent_id).to_equal(l_caller_id);
    ut.expect(l_turn_index).to_be_null();
  end ctx_session_cannot_move_run;


  procedure settings_context_reaches_agent
  as
    l_settings    uc_ai_settings.t_settings;
    l_result      clob;
    l_marker      number := exec_marker;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    -- The way a provider calls a tool: the run context travels in the per-call
    -- settings record, and execute_agent_tool hands it to the handler.
    l_settings.ctx_run_context := '{"tenant_id": "ACME", "session_id": "' || l_given_id || '"}';

    l_result := uc_ai_tools_api.execute_agent_tool(
      p_tool_code => gc_sub_tool,
      p_arguments => json_object_t('{"city": "Nantes"}'),
      p_settings  => l_settings
    );

    sys.dbms_output.put_line('settings_context_reaches_agent: ' || l_result);

    ut.expect(l_result).to_equal(to_clob('Weather in Nantes is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_session_id).to_equal(l_given_id);
    ut.expect(uc_ai.run_context_value(l_run_context, 'tenant_id')).to_equal('ACME');
  end settings_context_reaches_agent;


  procedure version_param_pins_the_agent
  as
    l_latest clob;
    l_pinned clob;
  begin
    -- Without a version the handler runs the active version
    l_latest := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_ver_code,
      p_arguments  => to_clob('{"city": "Turku"}')
    );

    -- With one it runs that version, also when it is archived by now
    l_pinned := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code    => gc_ver_code,
      p_arguments     => to_clob('{"city": "Turku"}'),
      p_agent_version => 1
    );

    sys.dbms_output.put_line('version_param_pins_the_agent: latest=' || l_latest || ' pinned=' || l_pinned);

    ut.expect(l_latest).to_equal(to_clob('answer from v2'));
    ut.expect(l_pinned).to_equal(to_clob('answer from v1'));
  end version_param_pins_the_agent;


  procedure generated_handler_is_the_helper
  as
    l_tool_id       number;
    l_tool_code     uc_ai_tools.code%type;
    l_function_call clob;
    l_result        clob;
  begin
    -- The orchestrator registers its delegates with the same shared handler
    l_tool_id := uc_ai_agent_exec_api.register_agent_as_tool(
      p_agent_code => gc_sub_code,
      p_tool_tag   => gc_tool_tag
    );
    commit;

    select code, function_call
      into l_tool_code, l_function_call
      from uc_ai_tools
     where id = l_tool_id;

    sys.dbms_output.put_line('generated_handler_is_the_helper: ' || l_function_call);

    -- nothing is baked into the handler any more but the agent code
    ut.expect(l_function_call).to_equal(
      to_clob('return uc_ai_agents_api.run_agent_as_tool(''' || gc_sub_code || ''', :parameters);')
    );

    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => l_tool_code,
      p_arguments => json_object_t('{"city": "Genoa"}')
    );

    ut.expect(l_result).to_equal(to_clob('Weather in Genoa is sunny'));

    delete_tool(l_tool_code);
  end generated_handler_is_the_helper;


  procedure delegate_without_schema_works
  as
    l_tool_id       number;
    l_tool_code     uc_ai_tools.code%type;
    l_result        clob;
    l_marker        number;
    l_exec_id       number;
    l_session_id    varchar2(255 char);
    l_parent_id     number;
    l_turn_index    number;
    l_run_context   clob;
  begin
    -- An agent takes no input schema: the tool then takes no parameters.
    -- json_object_t of a null CLOB raises ORA-40834, so the generator has to
    -- give the tool an empty object schema of its own.
    l_tool_id := uc_ai_agent_exec_api.register_agent_as_tool(
      p_agent_code => gc_nosch_code,
      p_tool_tag   => gc_tool_tag
    );
    commit;

    ut.expect(l_tool_id).to_be_not_null();

    select code into l_tool_code from uc_ai_tools where id = l_tool_id;

    l_marker := exec_marker;

    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => l_tool_code,
      p_arguments => json_object_t('{}')
    );

    ut.expect(l_result).to_equal(to_clob('no parameters needed'));

    agent_run(
      p_after_exec_id => l_marker,
      p_agent_code    => gc_nosch_code,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    ut.expect(l_exec_id).to_be_not_null();

    delete_tool(l_tool_code);
  end delegate_without_schema_works;


  procedure quoted_agent_code_is_safe
  as
    l_tool_id       number;
    l_tool_code     uc_ai_tools.code%type;
    l_function_call clob;
    l_result        clob;
  begin
    -- The agent code is baked into a single-quoted literal of the generated
    -- handler. A quote in the code has to come out doubled, or the handler is
    -- either broken or a way to inject PL/SQL.
    l_tool_id := uc_ai_agent_exec_api.register_agent_as_tool(
      p_agent_code => gc_quote_code,
      p_tool_tag   => gc_tool_tag
    );
    commit;

    select code, function_call
      into l_tool_code, l_function_call
      from uc_ai_tools
     where id = l_tool_id;

    sys.dbms_output.put_line('quoted_agent_code_is_safe: ' || l_function_call);

    ut.expect(l_function_call).to_equal(
      to_clob('return uc_ai_agents_api.run_agent_as_tool(''' || replace(gc_quote_code, '''', '''''')
              || ''', :parameters);')
    );

    -- and the handler still compiles and finds the agent
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => l_tool_code,
      p_arguments => json_object_t('{"city": "Cork"}')
    );

    ut.expect(l_result).to_equal(to_clob('the quoted agent answered'));

    delete_tool(l_tool_code);
  end quoted_agent_code_is_safe;


  procedure null_answer_is_not_the_word_null
  as
    l_result clob;
  begin
    -- has('final_message') is true for a JSON null, and to_clob of a JSON null
    -- is the four letters "null". The model must not read that as the answer.
    l_result := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_null_code,
      p_arguments  => to_clob('{}')
    );

    sys.dbms_output.put_line('null_answer_is_not_the_word_null: ' || l_result);

    ut.expect(l_result).to_be_not_null();
    ut.expect(lower(l_result)).not_to_equal(to_clob('null'));
  end null_answer_is_not_the_word_null;


  procedure session_key_is_not_a_binding
  as
    l_result      clob;
    l_marker      number;
    l_exec_id     number;
    l_session_id  varchar2(255 char);
    l_parent_id   number;
    l_turn_index  number;
    l_run_context clob;
    l_given_id    varchar2(100 char) := uc_ai_agents_api.generate_session_id;
  begin
    l_marker := exec_marker;

    -- session_id names the session; it is not a value of the run. It must not
    -- end up bound to the session, where it would fill prompt placeholders and
    -- collide with a later turn.
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code   => gc_sub_tool,
      p_arguments   => json_object_t('{"city": "Nantes"}'),
      p_run_context => '{"session_id": "' || l_given_id || '", "tenant_id": "ACME"}'
    );

    ut.expect(l_result).to_equal(to_clob('Weather in Nantes is sunny'));

    agent_run(
      p_after_exec_id => l_marker,
      p_session_id    => l_given_id,
      po_exec_id      => l_exec_id,
      po_session_id   => l_session_id,
      po_parent_id    => l_parent_id,
      po_turn_index   => l_turn_index,
      po_run_context  => l_run_context
    );

    sys.dbms_output.put_line('session_key_is_not_a_binding: ' || l_run_context);

    -- the run joined the session, and the key itself was not bound
    ut.expect(l_session_id).to_equal(l_given_id);
    ut.expect(uc_ai.run_context_value(l_run_context, 'tenant_id')).to_equal('ACME');
    ut.expect(uc_ai.run_context_value(l_run_context, 'session_id')).to_be_null();
  end session_key_is_not_a_binding;


  procedure failure_comes_back_as_text
  as
    l_result clob;
  begin
    -- The agent the tool names does not exist
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => gc_missing_tool,
      p_arguments => json_object_t('{"city": "Berlin"}')
    );

    sys.dbms_output.put_line('failure_comes_back_as_text (no agent): ' || l_result);

    ut.expect(l_result).to_be_like('Error executing agent:%');

    -- and the arguments are not JSON at all, so the handler fails before it
    -- reaches the agent - the same answer goes back to the model
    l_result := uc_ai_agents_api.run_agent_as_tool(
      p_agent_code => gc_sub_code,
      p_arguments  => to_clob('{"city": "Berlin"')
    );

    sys.dbms_output.put_line('failure_comes_back_as_text (bad json): ' || l_result);

    ut.expect(l_result).to_be_like('Error executing agent:%');
  end failure_comes_back_as_text;


  procedure recursion_hits_depth_limit
  as
    l_result clob;
    l_marker number := exec_marker;
    l_count  number;
  begin
    l_result := uc_ai_tools_api.execute_tool(
      p_tool_code => gc_loop_tool,
      p_arguments => json_object_t('{}')
    );

    sys.dbms_output.put_line('recursion_hits_depth_limit: ' || substr(l_result, 1, 500));

    -- The recursion stops and the innermost error travels back out as text.
    -- Which guard trips first is not fixed: the UC AI nesting limit (ORA-20405)
    -- or the Oracle recursive SQL level limit (ORA-00036), because each level
    -- runs the handler through dynamic SQL.
    ut.expect(l_result).to_be_like('%ORA-%');

    -- the agent really did nest before it stopped
    select count(*)
      into l_count
      from uc_ai_agent_executions e
      join uc_ai_agents a on a.id = e.agent_id
     where a.code = gc_loop_code
       and e.id > l_marker;

    sys.dbms_output.put_line('recursion depth reached: ' || l_count);
    ut.expect(l_count).to_be_greater_than(1);
  end recursion_hits_depth_limit;

end test_uc_ai_agent_as_tool;
/
