create or replace package body test_uc_ai_decision_agent as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): the tests assert THAT an error is raised; sqlcode/sqlerrm are the assertion
  -- @dblinter ignore(g-5080): the tests assert on sqlerrm itself; a backtrace would only add noise to the test log

  gc_prefix       constant varchar2(20 char) := 'TEST_DECA_';
  gc_profile_code constant varchar2(50 char) := 'TEST_DECA_PROFILE';
  gc_profile_ag   constant varchar2(50 char) := 'TEST_DECA_PROFILE_AG';
  gc_dec          constant varchar2(50 char) := 'TEST_DECA_DECISION';
  gc_dec_active   constant varchar2(50 char) := 'TEST_DECA_ACTIVE';

  gc_cfg_ok constant varchar2(1000 char) :=
    '{"provider":"openai","model":"gpt-6-luna","state_template":"Review: {text}",'
    || '"questions":{"is_ok":{"type":"boolean","instructions":"Is the review fine?"}}}';

  gc_questions constant varchar2(200 char) :=
    '{"is_ok":{"type":"boolean","instructions":"Is the review fine?"}}';


  -- Removes every agent the suite made, with its executions. Referencing agents
  -- (workflow, handoff, conversation) go before the agents they reference.
  procedure delete_test_rows
  as
  begin
    <<purge_loop>>
    for r in (
      select code
        from uc_ai_agents
       where code like gc_prefix || '%'
       group by code
       order by max(case agent_type
                      when uc_ai_agents_api.c_type_decision then 2
                      when uc_ai_agents_api.c_type_profile then 3
                      else 1
                    end)
    ) loop
      uc_ai_agents_api.purge_agent(r.code);
    end loop purge_loop;

    delete from uc_ai_prompt_profiles where code = gc_profile_code;
    commit;
  end delete_test_rows;


  procedure setup
  as
    l_id number;
  begin
    delete_test_rows;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => gc_profile_code,
      p_description            => 'Decision agent test profile',
      p_system_prompt_template => 'You are a test assistant.',
      p_user_prompt_template   => 'Say hi.',
      p_provider               => uc_ai.c_provider_openai,
      p_model                  => 'gpt-4o-mini',
      p_status                 => 'active'
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_profile_ag,
      p_description         => 'Profile agent of the decision agent tests',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_profile_code,
      p_status              => uc_ai_agents_api.c_status_active
    );

    -- an active decision agent for the tests that need one to exist
    l_id := uc_ai_agents_api.create_agent(
      p_code            => gc_dec_active,
      p_description     => 'Active decision agent',
      p_agent_type      => uc_ai_agents_api.c_type_decision,
      p_decision_config => gc_cfg_ok,
      p_status          => uc_ai_agents_api.c_status_active
    );

    commit;
  end setup;


  procedure teardown
  as
  begin
    delete_test_rows;
    uc_ai.reset_globals;
  end teardown;


  procedure reset_globals
  as
  begin
    uc_ai.reset_globals;
  end reset_globals;


  -- Creates a draft decision agent under p_code and returns its id
  function make_decision_agent(
    p_code in varchar2
  ) return number
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code            => p_code,
      p_description     => 'Decision agent under test',
      p_agent_type      => uc_ai_agents_api.c_type_decision,
      p_decision_config => gc_cfg_ok
    );
    commit;
    return l_id;
  end make_decision_agent;


  -- Validation helper: one invalid config, the reason must contain p_text
  procedure expect_invalid(
    p_config in clob,
    p_text   in varchar2
  )
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_decision_config(p_config);

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_be_like('%' || p_text || '%');
  end expect_invalid;


  -- CRUD, versioning, status -------------------------------------------------

  procedure create_and_read
  as
    l_id    number;
    l_agent uc_ai_agents%rowtype;
  begin
    l_id := make_decision_agent(gc_dec);
    l_agent := uc_ai_agents_api.get_agent(l_id);

    ut.expect(l_agent.code).to_equal(gc_dec);
    ut.expect(l_agent.agent_type).to_equal(uc_ai_agents_api.c_type_decision);
    ut.expect(l_agent.status).to_equal(uc_ai_agents_api.c_status_draft);
    ut.expect(l_agent.version).to_equal(1);
    ut.expect(l_agent.decision_config).to_equal(to_clob(gc_cfg_ok));
    ut.expect(l_agent.prompt_profile_code).to_be_null();
    ut.expect(l_agent.workflow_definition).to_be_null();
    ut.expect(l_agent.orchestration_config).to_be_null();

    -- by code and version too
    l_agent := uc_ai_agents_api.get_agent(gc_dec, 1);
    ut.expect(l_agent.id).to_equal(l_id);
  end create_and_read;


  procedure new_version_copies_config
  as
    l_id    number;
    l_new   number;
    l_agent uc_ai_agents%rowtype;
  begin
    l_id := make_decision_agent(gc_dec || '_V');
    l_new := uc_ai_agents_api.create_new_version(gc_dec || '_V', 1);
    commit;

    l_agent := uc_ai_agents_api.get_agent(l_new);
    ut.expect(l_new).not_to_equal(l_id);
    ut.expect(l_agent.version).to_equal(2);
    ut.expect(l_agent.agent_type).to_equal(uc_ai_agents_api.c_type_decision);
    ut.expect(l_agent.status).to_equal(uc_ai_agents_api.c_status_draft);
    ut.expect(l_agent.decision_config).to_equal(to_clob(gc_cfg_ok));
  end new_version_copies_config;


  procedure update_changes_config
  as
    l_id      number;
    l_agent   uc_ai_agents%rowtype;
    c_new_cfg constant varchar2(1000 char) :=
      '{"provider":"typesafe","state_template":"Ticket: {ticket}",'
      || '"questions":{"urgent":{"type":"boolean","instructions":"Is it urgent?"}}}';
  begin
    l_id := make_decision_agent(gc_dec || '_U');

    uc_ai_agents_api.update_agent(
      p_id              => l_id,
      p_description     => 'Changed description',
      p_decision_config => c_new_cfg
    );
    commit;

    l_agent := uc_ai_agents_api.get_agent(l_id);
    ut.expect(l_agent.description).to_equal('Changed description');
    ut.expect(l_agent.decision_config).to_equal(to_clob(c_new_cfg));
    ut.expect(l_agent.agent_type).to_equal(uc_ai_agents_api.c_type_decision);

    -- an update without decision_config keeps it
    uc_ai_agents_api.update_agent(p_id => l_id, p_description => 'Again');
    commit;
    l_agent := uc_ai_agents_api.get_agent(l_id);
    ut.expect(l_agent.decision_config).to_equal(to_clob(c_new_cfg));
  end update_changes_config;


  procedure activate_and_archive
  as
    l_id number;
  begin
    l_id := make_decision_agent(gc_dec || '_S');

    uc_ai_agents_api.change_status(l_id, uc_ai_agents_api.c_status_active);
    ut.expect(uc_ai_agents_api.get_agent(l_id).status).to_equal(uc_ai_agents_api.c_status_active);
    ut.expect(uc_ai_agents_api.get_agent(gc_dec || '_S').id).to_equal(l_id);

    uc_ai_agents_api.change_status(gc_dec || '_S', 1, uc_ai_agents_api.c_status_archived);
    ut.expect(uc_ai_agents_api.get_agent(l_id).status).to_equal(uc_ai_agents_api.c_status_archived);
    commit;
  end activate_and_archive;


  procedure workflow_references_decision_agent
  as
    l_id    number;
    l_agent uc_ai_agents%rowtype;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_prefix || 'WF',
      p_description         => 'Workflow with a decision step',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => '{"workflow_type":"sequential","steps":[{"agent_code":"'
                               || gc_dec_active || '","output_key":"verdict"}]}'
    );
    commit;

    l_agent := uc_ai_agents_api.get_agent(l_id);
    ut.expect(l_agent.agent_type).to_equal(uc_ai_agents_api.c_type_workflow);
  end workflow_references_decision_agent;


  procedure purge_deletes_agent
  as
    l_id    number;
    l_count number;
  begin
    l_id := make_decision_agent(gc_dec || '_P');
    uc_ai_agents_api.purge_agent(gc_dec || '_P');
    commit;

    select count(*) into l_count from uc_ai_agents where id = l_id;
    ut.expect(l_count).to_equal(0);
  end purge_deletes_agent;


  -- validate_decision_config -------------------------------------------------

  procedure val_valid_openai
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_decision_config(gc_cfg_ok);

    ut.expect(l_result.is_valid).to_be_true();
    ut.expect(l_result.error_reason).to_be_null();
  end val_valid_openai;


  procedure val_valid_typesafe_full
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_decision_config(
      '{"provider":"typesafe","model":"jev-latest","state_template":"Text: {text}",'
      || '"questions":' || gc_questions || ','
      || '"options":{"extra_body":{"a":1}},'
      || '"model_config":{"g_base_url":"https://example.invalid","typesafe":{"g_apex_web_credential":"NO_SUCH_CREDENTIAL"}}}'
    );

    ut.expect(l_result.is_valid).to_be_true();
    ut.expect(l_result.error_reason).to_be_null();
  end val_valid_typesafe_full;


  procedure val_model_optional
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_decision_config(
      '{"provider":"openai","state_template":"x","questions":' || gc_questions || '}'
    );

    ut.expect(l_result.is_valid).to_be_true();
  end val_model_optional;


  procedure val_null
  as
  begin
    expect_invalid(null, 'is null');
  end val_null;


  procedure val_not_json
  as
  begin
    expect_invalid('not json', 'is not valid JSON');
  end val_not_json;


  procedure val_not_object
  as
  begin
    expect_invalid('[1,2]', 'must be a JSON object');
  end val_not_object;


  procedure val_unknown_key
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":"x","questions":' || gc_questions || ',"question":{}}'
    , 'unknown key: question');
  end val_unknown_key;


  procedure val_missing_provider
  as
  begin
    expect_invalid('{"state_template":"x","questions":' || gc_questions || '}', 'requires provider');
  end val_missing_provider;


  procedure val_provider_not_string
  as
  begin
    expect_invalid(
      '{"provider":5,"state_template":"x","questions":' || gc_questions || '}'
    , 'requires provider');
  end val_provider_not_string;


  procedure val_unsupported_provider
  as
  begin
    expect_invalid(
      '{"provider":"anthropic","state_template":"x","questions":' || gc_questions || '}'
    , 'provider without decision support: anthropic');
  end val_unsupported_provider;


  procedure val_model_not_string
  as
  begin
    expect_invalid(
      '{"provider":"openai","model":7,"state_template":"x","questions":' || gc_questions || '}'
    , 'model must be a string');
  end val_model_not_string;


  procedure val_missing_state_template
  as
  begin
    expect_invalid('{"provider":"openai","questions":' || gc_questions || '}', 'requires state_template');
  end val_missing_state_template;


  procedure val_blank_state_template
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":"   ","questions":' || gc_questions || '}'
    , 'requires state_template');
  end val_blank_state_template;


  procedure val_state_template_not_string
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":{"a":1},"questions":' || gc_questions || '}'
    , 'requires state_template');
  end val_state_template_not_string;


  procedure val_missing_questions
  as
  begin
    expect_invalid('{"provider":"openai","state_template":"x"}', 'requires questions');
  end val_missing_questions;


  procedure val_questions_not_object
  as
  begin
    expect_invalid('{"provider":"openai","state_template":"x","questions":[]}', 'requires questions');
  end val_questions_not_object;


  procedure val_empty_questions
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":"x","questions":{}}'
    , 'questions must have at least one question');
  end val_empty_questions;


  procedure val_options_not_object
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":"x","questions":' || gc_questions || ',"options":"a"}'
    , 'options must be an object');
  end val_options_not_object;


  procedure val_model_config_not_object
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":"x","questions":' || gc_questions || ',"model_config":[]}'
    , 'model_config must be an object');
  end val_model_config_not_object;


  procedure val_model_config_unknown_key
  as
  begin
    expect_invalid(
      '{"provider":"openai","state_template":"x","questions":' || gc_questions
      || ',"model_config":{"g_no_such_setting":true}}'
    , 'invalid model_config');
  end val_model_config_unknown_key;


  -- create_agent / update_agent ----------------------------------------------

  procedure create_missing_config
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code        => gc_prefix || 'NOCFG',
      p_description => 'No config',
      p_agent_type  => uc_ai_agents_api.c_type_decision
    );
  end create_missing_config;


  procedure create_invalid_config
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code            => gc_prefix || 'BADCFG',
      p_description     => 'Bad config',
      p_agent_type      => uc_ai_agents_api.c_type_decision,
      p_decision_config => '{"provider":"openai"}'
    );
  end create_invalid_config;


  procedure create_config_on_profile
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_prefix || 'PROF_CFG',
      p_description         => 'Profile agent with a decision config',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_profile_code,
      p_decision_config     => gc_cfg_ok
    );
  end create_config_on_profile;


  procedure create_config_on_workflow
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_prefix || 'WF_CFG',
      p_description         => 'Workflow agent with a decision config',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => '{"workflow_type":"sequential","steps":[{"agent_code":"'
                               || gc_profile_ag || '","output_key":"a"}]}',
      p_decision_config     => gc_cfg_ok
    );
  end create_config_on_workflow;


  procedure create_decision_with_profile
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_prefix || 'DEC_PROF',
      p_description         => 'Decision agent with a prompt profile',
      p_agent_type          => uc_ai_agents_api.c_type_decision,
      p_prompt_profile_code => gc_profile_code,
      p_decision_config     => gc_cfg_ok
    );
  end create_decision_with_profile;


  procedure create_decision_with_workflow
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_prefix || 'DEC_WF',
      p_description         => 'Decision agent with a workflow definition',
      p_agent_type          => uc_ai_agents_api.c_type_decision,
      p_workflow_definition => '{"workflow_type":"sequential","steps":[{"agent_code":"'
                               || gc_profile_ag || '","output_key":"a"}]}',
      p_decision_config     => gc_cfg_ok
    );
  end create_decision_with_workflow;


  procedure create_decision_with_orch
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_prefix || 'DEC_ORCH',
      p_description          => 'Decision agent with an orchestration config',
      p_agent_type           => uc_ai_agents_api.c_type_decision,
      p_orchestration_config => '{"pattern_type":"orchestrator"}',
      p_decision_config      => gc_cfg_ok
    );
  end create_decision_with_orch;


  procedure update_invalid_config
  as
    l_id number;
  begin
    l_id := make_decision_agent(gc_dec || '_UI');
    uc_ai_agents_api.update_agent(
      p_id              => l_id,
      p_decision_config => '{"provider":"anthropic","state_template":"x","questions":' || gc_questions || '}'
    );
  end update_invalid_config;


  procedure update_config_on_profile
  as
  begin
    uc_ai_agents_api.update_agent(
      p_id              => uc_ai_agents_api.get_agent(gc_profile_ag).id,
      p_decision_config => gc_cfg_ok
    );
  end update_config_on_profile;


  procedure update_decision_with_profile
  as
    l_id number;
  begin
    l_id := make_decision_agent(gc_dec || '_UP');
    uc_ai_agents_api.update_agent(
      p_id                  => l_id,
      p_prompt_profile_code => gc_profile_code
    );
  end update_decision_with_profile;


  procedure table_check_decision_config
  as
    l_code number := 0;
  begin
    begin
      insert into uc_ai_agents (code, description, agent_type)
      values (gc_prefix || 'TBL_NOCFG', 'No config', 'decision');
    exception
      when others then
        l_code := sqlcode;
    end;
    rollback;

    -- ORA-02290: check constraint violated
    ut.expect(l_code).to_equal(-2290);
  end table_check_decision_config;


  procedure table_check_type
  as
    l_code_ok  number := 0;
    l_code_bad number := 0;
  begin
    begin
      insert into uc_ai_agents (code, description, agent_type, decision_config)
      values (gc_prefix || 'TBL_OK', 'Decision agent', 'decision', '{}');
    exception
      when others then
        l_code_ok := sqlcode;
    end;
    rollback;

    begin
      insert into uc_ai_agents (code, description, agent_type, decision_config)
      values (gc_prefix || 'TBL_BAD', 'Unknown type', 'banana', '{}');
    exception
      when others then
        l_code_bad := sqlcode;
    end;
    rollback;

    ut.expect(l_code_ok).to_equal(0);
    ut.expect(l_code_bad).to_equal(-2290);
  end table_check_type;


  -- handoff and conversation -------------------------------------------------

  procedure handoff_target_rejected
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_prefix || 'HANDOFF',
      p_description          => 'Handoff to a decision agent',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => '{"pattern_type":"handoff","initial_agent_code":"' || gc_profile_ag || '",'
        || '"handoff_agents":[{"agent_code":"' || gc_profile_ag || '","description":"p"},'
        || '{"agent_code":"' || gc_dec_active || '","description":"d"}]}'
    );
  end handoff_target_rejected;


  procedure conversation_participant_rejected
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_prefix || 'CONV',
      p_description          => 'Conversation with a decision agent',
      p_agent_type           => uc_ai_agents_api.c_type_conversation,
      p_orchestration_config => '{"pattern_type":"conversation","conversation_mode":"round_robin",'
        || '"agents":[{"agent_code":"' || gc_profile_ag || '","role":"a"},'
        || '{"agent_code":"' || gc_dec_active || '","role":"b"}]}'
    );
  end conversation_participant_rejected;


  procedure conversation_update_rejected
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_prefix || 'CONV_U',
      p_description          => 'Conversation of profile agents',
      p_agent_type           => uc_ai_agents_api.c_type_conversation,
      p_orchestration_config => '{"pattern_type":"conversation","conversation_mode":"round_robin",'
        || '"agents":[{"agent_code":"' || gc_profile_ag || '","role":"a"}]}'
    );
    commit;

    uc_ai_agents_api.update_agent(
      p_id                   => l_id,
      p_orchestration_config => '{"pattern_type":"conversation","conversation_mode":"round_robin",'
        || '"agents":[{"agent_code":"' || gc_profile_ag || '","role":"a"},'
        || '{"agent_code":"' || gc_dec_active || '","role":"b"}]}'
    );
  end conversation_update_rejected;


  -- execute_agent ------------------------------------------------------------

  procedure exec_not_implemented
  as
    l_result json_object_t;
    l_code   number := 0;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := uc_ai_agents_api.execute_agent(p_agent_code => gc_dec_active);
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code).to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%not implemented yet%');
  end exec_not_implemented;


  procedure exec_accepts_files
  as
    l_files uc_ai_message_api.t_files := uc_ai_message_api.t_files();
    l_code  number := 0;
    l_msg   varchar2(4000 char);
  begin
    l_files.extend;
    l_files(1).media_type := 'image/png';
    l_files(1).data_blob  := sys.utl_raw.cast_to_raw('not a real image');
    l_files(1).filename   := 'a.png';

    begin
      l_msg := uc_ai_agents_api.execute_agent(
                 p_agent_code => gc_dec_active
               , p_files      => l_files
               ).to_string;
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    -- past the file guard: the run stops at the missing executor
    ut.expect(l_code).to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%not implemented yet%');
  end exec_accepts_files;


  procedure exec_rejects_response_schema
  as
    l_result json_object_t;
    l_code   number := 0;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := uc_ai_agents_api.execute_agent(
                    p_agent_code      => gc_dec_active
                  , p_response_schema => json_object_t('{"type":"object"}')
                  );
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code).to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%response_schema%only be used with profile agents, not decision%');
  end exec_rejects_response_schema;


  procedure exec_rejects_extra_tool_tag
  as
    l_result json_object_t;
    l_code   number := 0;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := uc_ai_agents_api.execute_agent(
                    p_agent_code     => gc_dec_active
                  , p_extra_tool_tag => 'some_tag'
                  );
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code).to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%extra_tool_tag%only be used with profile agents, not decision%');
  end exec_rejects_extra_tool_tag;


  procedure exec_rejects_prompt_addendum
  as
    l_result json_object_t;
    l_code   number := 0;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := uc_ai_agents_api.execute_agent(
                    p_agent_code      => gc_dec_active
                  , p_prompt_addendum => 'Be brief.'
                  );
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code).to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%prompt_addendum%not decision%');
  end exec_rejects_prompt_addendum;


  procedure exec_rejects_follow_up
  as
    l_result json_object_t;
    l_code   number := 0;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := uc_ai_agents_api.execute_agent(
                    p_agent_code        => gc_dec_active
                  , p_follow_up_message => 'And now?'
                  , p_session_id        => 'test-deca-session'
                  );
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code).to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%follow_up_message%not decision%');
  end exec_rejects_follow_up;

end test_uc_ai_decision_agent;
/
