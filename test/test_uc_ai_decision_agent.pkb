create or replace package body test_uc_ai_decision_agent as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): the tests assert THAT an error is raised; sqlcode/sqlerrm are the assertion
  -- @dblinter ignore(g-5080): the tests assert on sqlerrm itself; a backtrace would only add noise to the test log

  gc_prefix       constant varchar2(20 char) := 'TEST_DECA_';
  gc_profile_code constant varchar2(50 char) := 'TEST_DECA_PROFILE';
  gc_profile_ag   constant varchar2(50 char) := 'TEST_DECA_PROFILE_AG';
  gc_dec          constant varchar2(50 char) := 'TEST_DECA_DECISION';
  gc_dec_active   constant varchar2(50 char) := 'TEST_DECA_ACTIVE';
  gc_route        constant varchar2(50 char) := 'TEST_DECA_ROUTE';

  -- the message and the questions of the recorded triage samples
  gc_ticket constant varchar2(100 char) :=
    'I was charged twice for my order. Please refund the extra charge.';

  -- answers for the department question of a hand written triage response
  gc_billing_answer constant varchar2(300 char) :=
    '{"type":"choice","name":"department","choice":"billing","probabilities":[{"value":"billing","probability":1.0},{"value":"support","probability":0.0},{"value":"sales","probability":0.0}]}';

  gc_refusal_answer constant varchar2(100 char) :=
    '{"type":"refusal","name":"department"}';

  gc_support_answer constant varchar2(300 char) :=
    '{"type":"choice","name":"department","choice":"support","probabilities":[{"value":"billing","probability":0.0},{"value":"support","probability":1.0},{"value":"sales","probability":0.0}]}';

  gc_triage_questions constant varchar2(2000 char) :=
    '{"department":{"type":"choice","instructions":"Which team should handle this message?","criteria":{'
    || '"billing":"Payments, invoices, and refunds.","support":"Product usage and technical problems.","sales":"New purchases and pricing questions."}}'
    || ',"severity":{"type":"score","instructions":"How severe is the problem described?","criteria":['
    || '"Appearance only; no lost functionality.","Something is broken but the customer can continue.","The customer cannot continue or lost money."]}'
    || ',"wants_refund":{"type":"boolean","instructions":"The customer asks for money back."}}';

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


  -- A decision_config with the triage questions of the recorded samples
  function triage_config(
    p_provider        in varchar2,
    p_model           in varchar2 default null,
    p_state_template  in varchar2 default '{message}',
    p_model_config    in varchar2 default null
  ) return clob
  as
    l_cfg json_object_t := json_object_t();
  begin
    l_cfg.put('provider', p_provider);
    if p_model is not null then
      l_cfg.put('model', p_model);
    end if;
    l_cfg.put('state_template', p_state_template);
    l_cfg.put('questions', json_object_t.parse(gc_triage_questions));
    -- Every config names a web credential: without one the call would look up
    -- the API key of the provider, and the tests never read a key
    l_cfg.put(
      'model_config'
    , json_object_t.parse(
        coalesce(p_model_config, '{"' || p_provider || '":{"g_apex_web_credential":"TEST_DECA_CREDENTIAL"}}')
      )
    );
    return l_cfg.to_clob;
  end triage_config;


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

    -- the triage agent of the workflow and tool tests (OpenAI, the recorded samples)
    l_id := uc_ai_agents_api.create_agent(
      p_code            => gc_route,
      p_description     => 'Triage decision agent',
      p_agent_type      => uc_ai_agents_api.c_type_decision,
      p_decision_config => triage_config(uc_ai.c_provider_openai, 'gpt-6-luna'),
      p_status          => uc_ai_agents_api.c_status_active
    );

    commit;

    -- the executor tests answer from the recorded samples
    uc_ai_http.set_transport('uc_ai_test_http_mock');
  end setup;


  procedure teardown
  as
  begin
    uc_ai_http.set_transport(null);
    delete_test_rows;
    uc_ai.reset_globals;
  end teardown;


  procedure reset_mock
  as
  begin
    uc_ai_test_http_mock.reset;
  end reset_mock;


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

  -- executor helpers ---------------------------------------------------------

  -- Creates an active triage decision agent (the questions of the samples)
  procedure make_triage_agent(
    p_code           in varchar2,
    p_provider       in varchar2 default uc_ai.c_provider_openai,
    p_model          in varchar2 default null,
    p_state_template in varchar2 default '{message}',
    p_model_config   in varchar2 default null
  )
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code            => p_code,
      p_description     => 'Triage decision agent under test',
      p_agent_type      => uc_ai_agents_api.c_type_decision,
      p_decision_config => triage_config(p_provider, p_model, p_state_template, p_model_config),
      p_status          => uc_ai_agents_api.c_status_active
    );
    commit;
  end make_triage_agent;


  -- Runs a decision agent on the message
  function run_agent(
    p_code    in varchar2,
    p_message in varchar2 default gc_ticket
  ) return json_object_t
  as
    l_input json_object_t := json_object_t();
  begin
    l_input.put('message', p_message);
    return uc_ai_agents_api.execute_agent(
             p_agent_code       => p_code
           , p_input_parameters => l_input
           );
  end run_agent;


  -- The error of a run that is expected to fail: its code and its text
  procedure run_expect_error(
    p_code    in  varchar2,
    p_input   in  json_object_t,
    po_code   out number,
    po_msg    out varchar2,
    p_files   in  uc_ai_message_api.t_files default null
  )
  as
    l_result json_object_t;
  begin
    po_code := 0;
    l_result := uc_ai_agents_api.execute_agent(
                  p_agent_code       => p_code
                , p_input_parameters => p_input
                , p_files            => p_files
                );
  exception
    when others then
      po_code := sqlcode;
      po_msg  := sqlerrm;
  end run_expect_error;


  -- The latest execution of an agent: status, own tokens, error and stored result
  procedure latest_execution(
    p_agent_code in  varchar2,
    po_exec_id   out number,
    po_status    out varchar2,
    po_in        out number,
    po_out       out number,
    po_error     out varchar2,
    po_output    out clob
  )
  as
  begin
    select e.id, e.status, e.total_input_tokens, e.total_output_tokens, e.error_message, e.output_result
      into po_exec_id, po_status, po_in, po_out, po_error, po_output
      from uc_ai_agent_executions e
     where e.id = (select max(x.id)
                     from uc_ai_agent_executions x
                     join uc_ai_agents a on a.id = x.agent_id
                    where a.code = p_agent_code);
  end latest_execution;


  procedure execution_row(
    p_exec_id in  number,
    po_status out varchar2,
    po_in     out number,
    po_out    out number,
    po_output out clob
  )
  as
  begin
    select status, total_input_tokens, total_output_tokens, output_result
      into po_status, po_in, po_out, po_output
      from uc_ai_agent_executions
     where id = p_exec_id;
  end execution_row;


  procedure session_totals(
    p_session_id in  varchar2,
    po_in        out number,
    po_out       out number
  )
  as
  begin
    select total_input_tokens, total_output_tokens
      into po_in, po_out
      from uc_ai_agent_sessions
     where session_id = p_session_id;
  end session_totals;


  -- A triage response with the given answer for the department question
  function triage_response(p_department in varchar2) return clob
  as
  begin
    return '{"model":"gpt-6-luna","answers":[' || p_department
        || ',{"type":"score","name":"severity","score":1,"probabilities":[{"value":0,"label":"0","probability":0.0},{"value":1,"label":"1","probability":1.0},{"value":2,"label":"2","probability":0.0}]}'
        || ',{"type":"predicate","name":"wants_refund","probability":0.5}]'
        || ',"usage":{"input_tokens":100,"output_tokens":0,"total_tokens":100}}';
  end triage_response;


  -- executor: result, tokens, answers ---------------------------------------

  procedure exec_tokens_openai
  as
    l_result  json_object_t;
    l_status  varchar2(50 char);
    l_in      number;
    l_out     number;
    l_output  clob;
    l_sess_in number;
    l_sess_out number;
    l_stored  json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_result := run_agent(gc_route);

    -- the request is the recorded one: the state, the questions, the model
    test_uc_ai_wire.expect_url(1, 'https://api.openai.com/v1/decisions');
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('input'), 'state').to_equal(gc_ticket);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model'), 'model').to_equal('gpt-6-luna');
    ut.expect(uc_ai_test_http_mock.request_json(1).get_array('questions').get_size, 'questions').to_equal(3);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_number('tool_calls_count')).to_equal(0);
    ut.expect(l_result.get_string('provider')).to_equal(uc_ai.c_provider_openai);
    ut.expect(l_result.get_string('model')).to_equal('gpt-6-luna');
    ut.expect(l_result.get_object('usage').get_number('prompt_tokens'), 'prompt_tokens').to_equal(429);
    ut.expect(l_result.get_object('usage').get_number('completion_tokens'), 'completion_tokens').to_equal(0);
    ut.expect(l_result.has('raw'), 'no raw in the result').to_be_false();
    ut.expect(l_result.get_object('final_message').has('raw'), 'no raw in final_message').to_be_false();

    -- the execution row holds the tokens of the call
    execution_row(l_result.get_number('execution_id'), l_status, l_in, l_out, l_output);
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_in, 'execution input tokens').to_equal(429);
    ut.expect(l_out, 'execution output tokens').to_equal(0);

    -- the stored result has the answers and no raw response
    l_stored := json_object_t.parse(l_output);
    ut.expect(l_stored.get_object('final_message').get_object('answers').get_object('department').get_string('choice')).to_equal('billing');
    ut.expect(l_stored.has('raw'), 'no raw in the stored result').to_be_false();
    ut.expect(l_output, 'no provider response in the stored result').not_to_be_like('%"predicate"%');

    -- the session total is the total of the execution
    session_totals(l_result.get_string('session_id'), l_sess_in, l_sess_out);
    ut.expect(l_sess_in, 'session input tokens').to_equal(l_in);
    ut.expect(l_sess_out, 'session output tokens').to_equal(l_out);
    test_uc_ai_wire.expect_all_consumed(1);
  end exec_tokens_openai;


  procedure exec_tokens_typesafe
  as
    l_result   json_object_t;
    l_status   varchar2(50 char);
    l_in       number;
    l_out      number;
    l_output   clob;
    l_sess_in  number;
    l_sess_out number;
  begin
    make_triage_agent(gc_prefix || 'TS_TOK', uc_ai.c_provider_typesafe);
    test_uc_ai_wire.enqueue_sample('typesafe/decisions/triage_response');

    l_result := run_agent(gc_prefix || 'TS_TOK');

    test_uc_ai_wire.expect_url(1, 'https://api.typesafe.ai/v1/systemone');
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('state'), 'state').to_equal(gc_ticket);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model'), 'default model').to_equal('jev-latest');
    ut.expect(uc_ai_test_http_mock.request_json(1).get_object('questions').get_size, 'questions').to_equal(3);

    ut.expect(l_result.get_string('provider')).to_equal(uc_ai.c_provider_typesafe);
    ut.expect(l_result.get_string('model')).to_equal('jev-1.13.0');
    ut.expect(l_result.get_object('usage').get_number('prompt_tokens')).to_equal(458);
    ut.expect(l_result.get_object('usage').get_number('completion_tokens')).to_equal(71);

    execution_row(l_result.get_number('execution_id'), l_status, l_in, l_out, l_output);
    ut.expect(l_in, 'execution input tokens').to_equal(458);
    ut.expect(l_out, 'execution output tokens').to_equal(71);

    session_totals(l_result.get_string('session_id'), l_sess_in, l_sess_out);
    ut.expect(l_sess_in, 'session input tokens').to_equal(458);
    ut.expect(l_sess_out, 'session output tokens').to_equal(71);
    test_uc_ai_wire.expect_all_consumed(1);
  end exec_tokens_typesafe;


  procedure exec_answers_openai
  as
    l_final   json_object_t;
    l_answers json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_final := run_agent(gc_route).get_object('final_message');
    l_answers := l_final.get_object('answers');

    ut.expect(l_answers.get_object('department').get_string('type')).to_equal('choice');
    ut.expect(l_answers.get_object('department').get_string('choice')).to_equal('billing');
    ut.expect(l_answers.get_object('department').get_object('probabilities').get_number('billing')).to_equal(1);
    ut.expect(l_answers.get_object('severity').get_string('type')).to_equal('score');
    ut.expect(l_answers.get_object('severity').get_number('score')).to_equal(1.97);
    ut.expect(l_answers.get_object('wants_refund').get_string('type')).to_equal('boolean');
    ut.expect(l_answers.get_object('wants_refund').get_number('probability')).to_equal(1);
    ut.expect(l_final.get_string('model')).to_equal('gpt-6-luna');
    ut.expect(l_final.get_array('warnings').get_size).to_equal(0);
    ut.expect(l_final.has('provider_metadata'), 'provider_metadata is part of final_message').to_be_true();
  end exec_answers_openai;


  procedure exec_answers_typesafe
  as
    l_final   json_object_t;
    l_answers json_object_t;
  begin
    make_triage_agent(gc_prefix || 'TS_ANS', uc_ai.c_provider_typesafe);
    test_uc_ai_wire.enqueue_sample('typesafe/decisions/triage_response');

    l_final := run_agent(gc_prefix || 'TS_ANS').get_object('final_message');
    l_answers := l_final.get_object('answers');

    ut.expect(l_answers.get_object('department').get_string('type')).to_equal('choice');
    ut.expect(l_answers.get_object('department').get_string('choice')).to_equal('billing');
    ut.expect(l_answers.get_object('severity').get_string('type')).to_equal('score');
    ut.expect(l_answers.get_object('severity').get_number('score')).to_equal(1.96);
    ut.expect(l_answers.get_object('wants_refund').get_string('type')).to_equal('boolean');
    ut.expect(l_answers.get_object('wants_refund').get_number('probability')).to_equal(0.99);
    ut.expect(l_final.get_string('model')).to_equal('jev-1.13.0');
    ut.expect(l_final.get_object('provider_metadata').get_object('confidence').get_number('department')).to_equal(1);
  end exec_answers_typesafe;


  procedure exec_refusal
  as
    l_code      varchar2(50 char) := gc_prefix || 'REFUSAL';
    l_id        number;
    l_result    json_object_t;
    l_answers   json_object_t;
    l_status    varchar2(50 char);
    l_in        number;
    l_out       number;
    l_output    clob;
  begin
    -- the questions of the recorded refusal request
    l_id := uc_ai_agents_api.create_agent(
      p_code            => l_code,
      p_description     => 'Refusal sample',
      p_agent_type      => uc_ai_agents_api.c_type_decision,
      p_decision_config => '{"provider":"openai","model":"gpt-6-luna","state_template":"{message}","questions":{'
        || '"gay":{"type":"boolean","instructions":"The author is gay."},'
        || '"religion":{"type":"choice","instructions":"What is the author''s religion?","criteria":{"christian":null,"muslim":null,"jewish":null,"none":null}}},'
        || '"model_config":{"openai":{"g_apex_web_credential":"TEST_DECA_CREDENTIAL"}}}',
      p_status          => uc_ai_agents_api.c_status_active
    );
    commit;
    test_uc_ai_wire.enqueue_sample('openai/decisions/refusal_response');

    l_result := run_agent(l_code, 'I love cooking pasta with my partner on Sundays and we just adopted a dog.');
    l_answers := l_result.get_object('final_message').get_object('answers');

    ut.expect(l_answers.get_object('gay').get_string('type')).to_equal('refused');
    ut.expect(l_answers.get_object('gay').has('choice'), 'no choice').to_be_false();
    ut.expect(l_answers.get_object('gay').has('probability'), 'no probability').to_be_false();
    ut.expect(l_answers.get_object('religion').get_string('choice'), 'the other question is answered').to_equal('none');

    -- a refusal does not fail the run and the tokens count
    execution_row(l_result.get_number('execution_id'), l_status, l_in, l_out, l_output);
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_in).to_equal(280);
  end exec_refusal;


  procedure exec_top_level_persists_message
  as
    l_result  json_object_t;
    l_exec_id number;
    l_content clob;
  begin
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_result := run_agent(gc_route);
    l_exec_id := l_result.get_number('execution_id');

    -- final_message is an object: the stored message must not be empty
    select content
      into l_content
      from uc_ai_agent_messages
     where execution_id = l_exec_id
       and role = 'assistant';

    ut.expect(l_content).to_be_like('%"department"%"choice":"billing"%');
  end exec_top_level_persists_message;


  -- executor: state_template ------------------------------------------------

  procedure exec_state_template
  as
    l_code  varchar2(50 char) := gc_prefix || 'TEMPLATE';
    l_input json_object_t := json_object_t();
    l_result json_object_t;
  begin
    make_triage_agent(l_code, p_state_template => 'Ticket {Ticket_ID} (urgent: {urgent}) from {customer}: {message}');
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    -- the key case differs from the placeholder, a number and a boolean become text
    l_input.put('ticket_id', 42);
    l_input.put('urgent', true);
    l_input.put('customer', 'ACME');
    l_input.put('message', gc_ticket);
    l_result := uc_ai_agents_api.execute_agent(p_agent_code => l_code, p_input_parameters => l_input);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('input'))
      .to_equal('Ticket 42 (urgent: true) from ACME: ' || gc_ticket);
  end exec_state_template;


  procedure exec_missing_variable
  as
    l_code   varchar2(50 char) := gc_prefix || 'MISSING';
    l_err    number;
    l_msg    varchar2(4000 char);
    l_exec   number;
    l_status varchar2(50 char);
    l_in     number;
    l_out    number;
    l_error  varchar2(4000 char);
    l_output clob;
  begin
    make_triage_agent(l_code, p_state_template => '{message} / {order_id}');

    -- a prompt profile raises -20506 for a placeholder without a value; so does the agent
    run_expect_error(l_code, json_object_t('{"message":"hello"}'), l_err, l_msg);

    ut.expect(l_err).to_equal(uc_ai_error.c_err_missing_placeholder);
    ut.expect(l_msg).to_be_like('%{order_id}%');
    ut.expect(uc_ai_test_http_mock.request_count, 'no request').to_equal(0);

    latest_execution(l_code, l_exec, l_status, l_in, l_out, l_error, l_output);
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_failed);
    ut.expect(l_error).to_be_like('%{order_id}%');
    ut.expect(l_in).to_equal(0);

    -- no input at all fails the same way
    run_expect_error(l_code, null, l_err, l_msg);
    ut.expect(l_err, 'without any input').to_equal(uc_ai_error.c_err_missing_placeholder);
  end exec_missing_variable;


  procedure exec_run_context_placeholder
  as
    l_code   varchar2(50 char) := gc_prefix || 'RUNCTX';
    l_result json_object_t;
  begin
    make_triage_agent(l_code);
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_result := uc_ai_agents_api.execute_agent(
                  p_agent_code  => l_code
                , p_run_context => json_object_t('{"message":"from the run context"}')
                );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('input')).to_equal('from the run context');
  end exec_run_context_placeholder;


  -- executor: settings ------------------------------------------------------

  procedure exec_model_config_beats_globals
  as
    l_code   varchar2(50 char) := gc_prefix || 'CFG';
    l_result json_object_t;
  begin
    make_triage_agent(
      l_code
    , p_model_config => '{"g_base_url":"https://decide.example.test/v1","g_apex_web_credential":"AGENT_CREDENTIAL"}'
    );
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    -- globals an earlier profile step or the session could have set
    uc_ai.g_base_url := 'https://bogus-global.example.test/v9';
    uc_ai.g_apex_web_credential := 'BOGUS_GLOBAL_CREDENTIAL';
    uc_ai_openai.g_apex_web_credential := 'BOGUS_OPENAI_CREDENTIAL';

    l_result := run_agent(l_code);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai_test_http_mock.request(1).url, 'url from model_config').to_equal('https://decide.example.test/v1/decisions');
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential from model_config').to_equal('AGENT_CREDENTIAL');

    -- the run did not change the globals
    ut.expect(uc_ai.g_base_url, 'g_base_url').to_equal('https://bogus-global.example.test/v9');
    ut.expect(uc_ai.g_apex_web_credential, 'g_apex_web_credential').to_equal('BOGUS_GLOBAL_CREDENTIAL');
    ut.expect(uc_ai_openai.g_apex_web_credential, 'openai credential').to_equal('BOGUS_OPENAI_CREDENTIAL');
  end exec_model_config_beats_globals;


  procedure exec_provider_credential
  as
    l_code   varchar2(50 char) := gc_prefix || 'CFG_PROV';
    l_result json_object_t;
  begin
    -- no base URL in model_config: the provider default applies, not the global
    make_triage_agent(l_code, p_model_config => '{"openai":{"g_apex_web_credential":"AGENT_OPENAI_CREDENTIAL"}}');
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    uc_ai.g_base_url := 'https://bogus-global.example.test/v9';
    uc_ai.g_apex_web_credential := 'BOGUS_GLOBAL_CREDENTIAL';

    l_result := run_agent(l_code);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai_test_http_mock.request(1).url, 'provider default url').to_equal('https://api.openai.com/v1/decisions');
    ut.expect(uc_ai_test_http_mock.request(1).credential).to_equal('AGENT_OPENAI_CREDENTIAL');
  end exec_provider_credential;


  -- executor: files, errors -------------------------------------------------

  procedure exec_image_file
  as
    l_code    varchar2(50 char) := gc_prefix || 'IMAGE';
    l_files   uc_ai_message_api.t_files := uc_ai_message_api.t_files();
    l_input   json_object_t := json_object_t();
    l_result  json_object_t;
    l_content json_array_t;
    l_part    json_object_t;
  begin
    make_triage_agent(l_code, p_state_template => 'Review: {message}');
    l_files.extend;
    l_files(1).media_type := 'image/png';
    l_files(1).data_blob  := sys.utl_raw.cast_to_raw('image bytes');
    l_files(1).filename   := 'scan.png';

    uc_ai_test_http_mock.enqueue(triage_response(gc_billing_answer));

    l_input.put('message', 'the scan');
    l_result := uc_ai_agents_api.execute_agent(
                  p_agent_code       => l_code
                , p_input_parameters => l_input
                , p_files            => l_files
                );

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_content := treat(uc_ai_test_http_mock.request_json(1).get_array('input').get(0) as json_object_t).get_array('content');
    ut.expect(l_content.get_size, 'text and image').to_equal(2);
    ut.expect(treat(l_content.get(0) as json_object_t).get_string('text')).to_equal('Review: the scan');
    l_part := treat(l_content.get(1) as json_object_t);
    ut.expect(l_part.get_string('type')).to_equal('input_image');
    ut.expect(l_part.get_string('image_url')).to_be_like('data:image/png;base64,%');
  end exec_image_file;


  procedure exec_typesafe_rejects_file
  as
    l_code   varchar2(50 char) := gc_prefix || 'TS_FILE';
    l_files  uc_ai_message_api.t_files := uc_ai_message_api.t_files();
    l_err    number;
    l_msg    varchar2(4000 char);
    l_exec   number;
    l_status varchar2(50 char);
    l_in     number;
    l_out    number;
    l_error  varchar2(4000 char);
    l_output clob;
  begin
    make_triage_agent(l_code, uc_ai.c_provider_typesafe);
    l_files.extend;
    l_files(1).media_type := 'image/png';
    l_files(1).data_blob  := sys.utl_raw.cast_to_raw('image bytes');

    run_expect_error(l_code, json_object_t('{"message":"hello"}'), l_err, l_msg, l_files);

    ut.expect(l_err).to_equal(uc_ai_error.c_err_unsupported_content);
    ut.expect(uc_ai_test_http_mock.request_count, 'no request').to_equal(0);

    latest_execution(l_code, l_exec, l_status, l_in, l_out, l_error, l_output);
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_failed);
    ut.expect(l_error).to_be_like('%text only%');
  end exec_typesafe_rejects_file;


  procedure exec_provider_error
  as
    l_code   varchar2(50 char) := gc_prefix || 'ERROR';
    l_err    number;
    l_msg    varchar2(4000 char);
    l_exec   number;
    l_status varchar2(50 char);
    l_in     number;
    l_out    number;
    l_error  varchar2(4000 char);
    l_output clob;
  begin
    make_triage_agent(l_code, p_model => 'gpt-6-nope');
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get('openai/decisions/error_unknown_model_response'), 404);

    run_expect_error(l_code, json_object_t('{"message":"hello"}'), l_err, l_msg);

    ut.expect(l_err).to_equal(uc_ai_error.c_err_provider_response);
    ut.expect(l_msg).to_be_like('%gpt-6-nope%');

    latest_execution(l_code, l_exec, l_status, l_in, l_out, l_error, l_output);
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_failed);
    ut.expect(l_error).to_be_like('%gpt-6-nope%');
    ut.expect(l_in, 'input tokens').to_equal(0);
    ut.expect(l_out, 'output tokens').to_equal(0);
  end exec_provider_error;


  procedure exec_garbage_config
  as
    l_code   varchar2(50 char) := gc_prefix || 'GARBAGE';
    l_err    number;
    l_msg    varchar2(4000 char);
    l_exec   number;
    l_status varchar2(50 char);
    l_in     number;
    l_out    number;
    l_error  varchar2(4000 char);
    l_output clob;
  begin
    make_triage_agent(l_code);

    -- edited by hand after the checks of create_agent
    update uc_ai_agents set decision_config = '{"provider":"openai"}' where code = l_code;
    commit;
    run_expect_error(l_code, json_object_t('{"message":"hello"}'), l_err, l_msg);
    ut.expect(l_err, 'missing questions').to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%not a valid decision config%');

    update uc_ai_agents set decision_config = 'this is not json' where code = l_code;
    commit;
    run_expect_error(l_code, json_object_t('{"message":"hello"}'), l_err, l_msg);
    ut.expect(l_err, 'not json').to_equal(uc_ai_error.c_err_invalid_config);
    ut.expect(l_msg).to_be_like('%not a valid decision config%');

    ut.expect(uc_ai_test_http_mock.request_count, 'no request').to_equal(0);
    latest_execution(l_code, l_exec, l_status, l_in, l_out, l_error, l_output);
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_failed);
  end exec_garbage_config;


  -- executor: workflow and tools --------------------------------------------

  -- A workflow: the triage decision, then one step per department
  procedure make_route_workflow(
    p_code in varchar2
  )
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Route by department',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => q'#{
        "workflow_type": "sequential",
        "steps": [
          {
            "agent_code": "#' || gc_route || q'#",
            "input_mapping": { "message": "{$.input.message}" },
            "output_key": "route"
          },
          {
            "step_type": "plsql",
            "condition": "'{$.steps.route.answers.department.choice}' = 'billing'",
            "plsql_function_call": "return 'billing handled';",
            "output_key": "billing_branch"
          },
          {
            "step_type": "plsql",
            "condition": "'{$.steps.route.answers.department.choice}' = 'support'",
            "plsql_function_call": "return 'support handled';",
            "output_key": "support_branch"
          }
        ]
      }#',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
  end make_route_workflow;


  procedure wf_route_taken_branch
  as
    l_code   varchar2(50 char) := gc_prefix || 'WF_ROUTE';
    l_result json_object_t;
    l_steps  json_object_t;
  begin
    make_route_workflow(l_code);

    -- billing: the billing step runs, the support step is skipped
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');
    l_result := run_agent(l_code);
    l_steps := l_result.get_object('steps');

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_steps.get_object('route').get_object('answers').get_object('department').get_string('choice')).to_equal('billing');
    ut.expect(l_steps.has('billing_branch'), 'billing step ran').to_be_true();
    ut.expect(l_steps.has('support_branch'), 'support step skipped').to_be_false();

    -- support: the other way round
    uc_ai_test_http_mock.enqueue(triage_response(gc_support_answer));
    l_result := run_agent(l_code);
    l_steps := l_result.get_object('steps');

    ut.expect(l_steps.has('billing_branch'), 'billing step skipped').to_be_false();
    ut.expect(l_steps.has('support_branch'), 'support step ran').to_be_true();
  end wf_route_taken_branch;


  procedure wf_token_attribution
  as
    l_code     varchar2(50 char) := gc_prefix || 'WF_TOKENS';
    l_result   json_object_t;
    l_status   varchar2(50 char);
    l_wf_in    number;
    l_wf_out   number;
    l_child_in number;
    l_child_out number;
    l_output   clob;
    l_child_id number;
    l_exec_id  number;
    l_session  varchar2(255 char);
    l_sess_in  number;
    l_sess_out number;
    l_count    number;
  begin
    make_route_workflow(l_code);
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_result := run_agent(l_code);
    l_exec_id := l_result.get_number('execution_id');
    l_session := l_result.get_string('session_id');

    -- the workflow made no model call: its own tokens are 0
    execution_row(l_exec_id, l_status, l_wf_in, l_wf_out, l_output);
    ut.expect(l_wf_in, 'workflow input tokens').to_equal(0);
    ut.expect(l_wf_out, 'workflow output tokens').to_equal(0);

    -- the child execution of the decision agent holds them
    select e.id, e.total_input_tokens, e.total_output_tokens
      into l_child_id, l_child_in, l_child_out
      from uc_ai_agent_executions e
     where e.parent_execution_id = l_exec_id;
    ut.expect(l_child_in, 'decision input tokens').to_equal(429);
    ut.expect(l_child_out, 'decision output tokens').to_equal(0);

    -- the session is the sum of its executions, so it equals the child
    session_totals(l_session, l_sess_in, l_sess_out);
    ut.expect(l_sess_in, 'session input tokens').to_equal(l_child_in);
    ut.expect(l_sess_out, 'session output tokens').to_equal(l_child_out);

    select count(*)
      into l_count
      from uc_ai_agent_executions
     where session_id = l_session;
    ut.expect(l_count, 'executions in the session').to_equal(2);
  end wf_token_attribution;


  -- A workflow with a step for a refusal, for billing and for "not billing"
  procedure make_refusal_workflow(
    p_code in varchar2
  )
  as
    l_id number;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => p_code,
      p_description         => 'Conditions on a refused question',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => q'#{
        "workflow_type": "sequential",
        "steps": [
          {
            "agent_code": "#' || gc_route || q'#",
            "input_mapping": { "message": "{$.input.message}" },
            "output_key": "route"
          },
          {
            "step_type": "plsql",
            "condition": "'{$.steps.route.answers.department.type}' = 'refused'",
            "plsql_function_call": "return 'refused handled';",
            "output_key": "refused_branch"
          },
          {
            "step_type": "plsql",
            "condition": "'{$.steps.route.answers.department.choice}' = 'billing'",
            "plsql_function_call": "return 'billing handled';",
            "output_key": "billing_branch"
          },
          {
            "step_type": "plsql",
            "condition": "'{$.steps.route.answers.department.choice}' != 'billing'",
            "plsql_function_call": "return 'not billing handled';",
            "output_key": "not_billing_branch"
          }
        ]
      }#',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
  end make_refusal_workflow;


  procedure wf_refusal_trap
  as
    l_code   varchar2(50 char) := gc_prefix || 'WF_TRAP';
    l_result json_object_t;
    l_steps  json_object_t;
  begin
    make_refusal_workflow(l_code);
    uc_ai_test_http_mock.enqueue(triage_response(gc_refusal_answer));

    l_result := run_agent(l_code);
    l_steps := l_result.get_object('steps');

    -- the refused answer has no choice: the path does not resolve and every
    -- condition on it is false, "!=" too. "!= 'billing'" does NOT catch a refusal.
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_steps.get_object('route').get_object('answers').get_object('department').has('choice'), 'no choice key').to_be_false();
    ut.expect(l_steps.has('billing_branch'), '= billing is false').to_be_false();
    ut.expect(l_steps.has('not_billing_branch'), '!= billing is false too').to_be_false();
  end wf_refusal_trap;


  procedure wf_refusal_type_condition
  as
    l_code   varchar2(50 char) := gc_prefix || 'WF_REFUSED';
    l_result json_object_t;
    l_steps  json_object_t;
  begin
    make_refusal_workflow(l_code);

    -- refused: the condition on type runs its branch
    uc_ai_test_http_mock.enqueue(triage_response(gc_refusal_answer));
    l_steps := run_agent(l_code).get_object('steps');
    ut.expect(l_steps.has('refused_branch'), 'refused branch ran').to_be_true();

    -- answered: the same condition is false
    uc_ai_test_http_mock.enqueue(triage_response(gc_billing_answer));
    l_result := run_agent(l_code);
    l_steps := l_result.get_object('steps');
    ut.expect(l_steps.has('refused_branch'), 'refused branch skipped').to_be_false();
    ut.expect(l_steps.has('billing_branch'), 'billing branch ran').to_be_true();
    ut.expect(l_steps.has('not_billing_branch'), '!= billing is false for billing').to_be_false();
  end wf_refusal_type_condition;


  procedure wf_final_message_is_object
  as
    l_code   varchar2(50 char) := gc_prefix || 'WF_FINAL';
    l_id     number;
    l_result json_object_t;
  begin
    l_id := uc_ai_agents_api.create_agent(
      p_code                => l_code,
      p_description         => 'Workflow that ends with a decision step',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => '{"workflow_type":"sequential","steps":[{"agent_code":"' || gc_route
                               || '","input_mapping":{"message":"{$.input.message}"},"output_key":"route"}]}',
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_result := run_agent(l_code);

    ut.expect(l_result.get('final_message').is_object, 'final_message is the decision object').to_be_true();
    ut.expect(l_result.get_object('final_message').get_object('answers').get_object('department').get_string('choice')).to_equal('billing');
  end wf_final_message_is_object;


  procedure as_tool_returns_json
  as
    l_answer clob;
    l_json   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    l_answer := uc_ai_agents_api.run_agent_as_tool(
                  p_agent_code => gc_route
                , p_arguments  => '{"message":"' || gc_ticket || '"}'
                );

    ut.expect(l_answer).not_to_be_like('%gave no answer%');
    ut.expect(l_answer).not_to_be_like('Error executing agent%');
    l_json := json_object_t.parse(l_answer);
    ut.expect(l_json.get_object('answers').get_object('department').get_string('choice')).to_equal('billing');
    ut.expect(l_json.get_object('answers').get_object('severity').get_number('score')).to_equal(1.97);
  end as_tool_returns_json;

  -- render_template ----------------------------------------------------------

  -- The rendered text of a short template as varchar2, which ut.expect can compare
  function render(
    p_template in clob,
    p_json     in varchar2
  ) return varchar2
  as
  begin
    return sys.dbms_lob.substr(
             uc_ai_prompt_profiles_api.render_template(p_template, json_object_t.parse(p_json))
           , 4000, 1);
  end render;


  procedure tpl_value_is_not_rescanned
  as
  begin
    -- x comes first in the key order: a rescan would turn its value into Z
    ut.expect(render('a {x} b {y}', '{"x":"{y}","y":"Z"}')).to_equal('a {y} b Z');
    -- the same when the value is the placeholder of its own key
    ut.expect(render('{x}', '{"x":"{x}"}')).to_equal('{x}');
    -- and for the other key order
    ut.expect(render('{y} {x}', '{"y":"Z","x":"{y}"}')).to_equal('Z {y}');
  end tpl_value_is_not_rescanned;


  procedure tpl_value_is_literal
  as
  begin
    -- JSON strings below: the PL/SQL text has no escapes, the JSON parser decodes \\ to one backslash
    ut.expect(render('v={p}', '{"p":"C:\\temp \\1 end"}'), 'path with a backreference').to_equal('v=C:\temp \1 end');
    ut.expect(render('v={p}', '{"p":"a\\\\b"}'), 'double backslash').to_equal('v=a\\b');
    ut.expect(render('v={p}', '{"p":"\\0 \\9 & $1 \\n"}'), 'other escapes').to_equal('v=\0 \9 & $1 \n');
  end tpl_value_is_literal;


  procedure tpl_large_value
  as
    c_chunks constant pls_integer := 10;
    l_big    clob;
    l_values json_object_t := json_object_t();
    l_result clob;
  begin
    sys.dbms_lob.createtemporary(l_big, true);
    <<fill_loop>>
    for i in 1 .. c_chunks loop
      sys.dbms_lob.writeappend(l_big, 10000, rpad(to_char(i - 1), 10000, to_char(i - 1)));
    end loop fill_loop;
    l_values.put('p', l_big);

    l_result := uc_ai_prompt_profiles_api.render_template('A {p} B {P} C', l_values);

    -- 7 characters of template text and the value twice
    ut.expect(sys.dbms_lob.getlength(l_result), 'length').to_equal(200007);
    ut.expect(sys.dbms_lob.substr(l_result, 5, 1), 'start').to_equal('A 000');
    ut.expect(sys.dbms_lob.substr(l_result, 3, 100003), 'between the values').to_equal(' B ');
    ut.expect(sys.dbms_lob.substr(l_result, 3, 100006), 'second value start').to_equal('000');
    ut.expect(sys.dbms_lob.substr(l_result, 5, 200003), 'end').to_equal('999 C');
  end tpl_large_value;


  procedure tpl_special_character_key
  as
  begin
    -- the dot of a.b is not "any character", the plus is not a quantifier
    ut.expect(render('{a.b}|{axb}', '{"a.b":"DOT","axb":"X"}')).to_equal('DOT|X');
    ut.expect(render('v={a+b}', '{"a+b":"PLUS"}')).to_equal('v=PLUS');
    ut.expect(render('{a b}', '{"a b":"SPACE"}')).to_equal('SPACE');
  end tpl_special_character_key;


  procedure tpl_unchanged_behaviour
  as
  begin
    ut.expect(render('{Name} {NAME}', '{"name":"v"}'), 'case-insensitive').to_equal('v v');
    ut.expect(render('{n}', '{"n":42}'), 'number').to_equal('42');
    ut.expect(render('{n}', '{"n":1.5}'), 'decimal number').to_equal(to_char(1.5));
    ut.expect(render('{t} {f}', '{"t":true,"f":false}'), 'boolean').to_equal('true false');
    ut.expect(render('{o}', '{"o":{"k":[1,2]}}'), 'object').to_equal('{"k":[1,2]}');
    ut.expect(render('{a}', '{"a":[1,"x"]}'), 'array').to_equal('[1,"x"]');
    ut.expect(render('{z}', '{"z":null}'), 'null').to_equal('null');
    ut.expect(render('{x}{x}-{X}', '{"x":"v"}'), 'repeated placeholder').to_equal('vv-v');
    ut.expect(render('{{x}}', '{"x":"v"}'), 'braces around a placeholder').to_equal('{v}');
    ut.expect(render('no placeholder', '{"x":"v"}'), 'no placeholder').to_equal('no placeholder');
    ut.expect(render('{x}', '{"x":""}'), 'empty value').to_be_null();
    -- two keys that differ in case: the first key in key order wins
    ut.expect(render('{x}/{X}', '{"x":"first","X":"second"}'), 'duplicate keys').to_equal('first/first');
  end tpl_unchanged_behaviour;


  procedure tpl_missing_and_extra
  as
    l_code number := 0;
  begin
    begin
      ut.expect(render('{x} {nope}', '{"x":"v"}')).to_be_null();
    exception
      when others then
        l_code := sqlcode;
    end;
    ut.expect(l_code, 'missing placeholder').to_equal(uc_ai_error.c_err_missing_placeholder);

    -- no values at all fails the same way
    l_code := 0;
    begin
      ut.expect(uc_ai_prompt_profiles_api.render_template('{x}', null)).to_be_null();
    exception
      when others then
        l_code := sqlcode;
    end;
    ut.expect(l_code, 'null parameters').to_equal(uc_ai_error.c_err_missing_placeholder);

    ut.expect(render('{x}', '{"x":"v","unused":"w"}'), 'extra key').to_equal('v');
    ut.expect(sys.dbms_lob.substr(uc_ai_prompt_profiles_api.render_template('no placeholder', null), 100, 1), 'no placeholder, no values').to_equal('no placeholder');
  end tpl_missing_and_extra;


  procedure exec_value_with_placeholder_is_literal
  as
    l_code  varchar2(50 char) := gc_prefix || 'LITERAL';
    l_input json_object_t := json_object_t();
    l_result json_object_t;
  begin
    make_triage_agent(l_code);
    test_uc_ai_wire.enqueue_sample('openai/decisions/triage_response');

    -- message comes first: a rescan would put the value of secret into the state
    l_input.put('message', 'refund {secret} to C:\temp\1 please');
    l_input.put('secret', 'TOP-SECRET');
    l_result := uc_ai_agents_api.execute_agent(p_agent_code => l_code, p_input_parameters => l_input);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('input')).to_equal('refund {secret} to C:\temp\1 please');
  end exec_value_with_placeholder_is_literal;


end test_uc_ai_decision_agent;
/
