create or replace package body test_uc_ai_agent_validation as

  gc_profile_code  constant varchar2(50 char) := 'TEST_VALIDATION_PROFILE';
  gc_agent_a       constant varchar2(50 char) := 'TEST_VAL_AGENT_A';
  gc_agent_wf      constant varchar2(50 char) := 'TEST_VAL_AGENT_WF';

  procedure delete_test_rows
  as
  begin
    delete from uc_ai_agents where code like 'TEST_VAL_%';
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
      p_description            => 'Validation test profile',
      p_system_prompt_template => 'You are a test assistant.',
      p_user_prompt_template   => 'Say hi.',
      p_provider               => uc_ai.c_provider_openai,
      p_model                  => 'gpt-4o-mini',
      p_model_config_json      => '{"g_enable_tools": true, "g_max_tool_calls": 7}',
      p_response_schema        => '{"type":"object","properties":{"confidence":{"type":"number"}}}',
      p_status                 => 'active'
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_agent_a,
      p_description         => 'Validation test profile agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_profile_code,
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_agent_wf,
      p_description         => 'Validation test workflow agent',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => '{"workflow_type":"sequential","steps":[{"agent_code":"'
                               || gc_agent_a || '","output_key":"a"}]}',
      p_status              => uc_ai_agents_api.c_status_draft
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


  -- validate_workflow_definition ---------------------------------------------

  procedure wf_valid_sequential
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"workflow_type":"sequential","steps":[{"agent_code":"' || gc_agent_a || '"}]}'
    );

    ut.expect(l_result.is_valid).to_be_true();
    ut.expect(l_result.error_reason).to_be_null();
  end wf_valid_sequential;


  procedure wf_null_invalid
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(null);

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('workflow_definition is null');
  end wf_null_invalid;


  procedure wf_missing_type
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"steps":[{"agent_code":"X"}]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('Missing required field: workflow_type');
  end wf_missing_type;


  procedure wf_bad_type
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"workflow_type":"banana","steps":[{"agent_code":"X"}]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_be_like('Invalid workflow_type: banana%');
  end wf_bad_type;


  procedure wf_missing_steps
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"workflow_type":"sequential"}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('Missing required field: steps');
  end wf_missing_steps;


  procedure wf_empty_steps
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"workflow_type":"sequential","steps":[]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('steps array is empty');
  end wf_empty_steps;


  procedure wf_step_missing_agent_code
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"workflow_type":"sequential","steps":[{"output_key":"a"}]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('Step 0 missing required field: agent_code');
  end wf_step_missing_agent_code;


  procedure wf_non_string_condition
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_workflow_definition(
      '{"workflow_type":"conditional","steps":['
      || '{"agent_code":"A"},'
      || '{"agent_code":"B","condition":{"x":1}}'
      || ']}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Step 1 condition must be a string containing a PL/SQL boolean expression'
    );
  end wf_non_string_condition;


  procedure wf_invalid_json_raises
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    -- characterization: unlike validate_orchestration_config, invalid JSON
    -- re-raises the parse error instead of returning an invalid result
    begin
      l_result := uc_ai_agents_api.validate_workflow_definition('not json');
      ut.fail('Expected validate_workflow_definition to raise for invalid JSON');
    exception
      when others then
        -- generic JSON parse error, not a uc_ai custom error code
        ut.expect(sqlcode between -20999 and -20000).to_be_false();
    end;
  end wf_invalid_json_raises;


  -- validate_orchestration_config --------------------------------------------

  procedure orch_valid_orchestrator
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"orchestrator","orchestrator_profile_code":"X","delegate_agents":[]}'
    );

    ut.expect(l_result.is_valid).to_be_true();
    ut.expect(l_result.error_reason).to_be_null();
  end orch_valid_orchestrator;


  procedure orch_null
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(null);

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('orchestration_config is null');
  end orch_null;


  procedure orch_missing_pattern
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config('{"foo":1}');

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal('Missing required field: pattern_type');
  end orch_missing_pattern;


  procedure orch_orchestrator_missing_fields
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"orchestrator","delegate_agents":[]}'
    );
    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Orchestrator config missing required field: orchestrator_profile_code'
    );

    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"orchestrator","orchestrator_profile_code":"X"}'
    );
    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Orchestrator config missing required field: delegate_agents'
    );
  end orch_orchestrator_missing_fields;


  procedure orch_handoff_missing_initial
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"handoff"}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Handoff config missing required field: initial_agent_code'
    );
  end orch_handoff_missing_initial;


  procedure orch_handoff_missing_agents
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"handoff","initial_agent_code":"A"}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Handoff config missing required field: handoff_agents (array)'
    );
  end orch_handoff_missing_agents;


  procedure orch_handoff_empty_agents
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"handoff","initial_agent_code":"A","handoff_agents":[]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Handoff config handoff_agents must not be empty'
    );
  end orch_handoff_empty_agents;


  procedure orch_handoff_target_no_code
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"handoff","initial_agent_code":"A","handoff_agents":[{"description":"no code"}]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Handoff config handoff_agents entry 0 missing required field: agent_code'
    );
  end orch_handoff_target_no_code;


  procedure orch_handoff_bad_max
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"handoff","initial_agent_code":"A","handoff_agents":[{"agent_code":"B"}],"max_handoffs":0}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Handoff config max_handoffs must be a number >= 1'
    );
  end orch_handoff_bad_max;


  procedure orch_handoff_valid
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"handoff","initial_agent_code":"A","handoff_agents":[{"agent_code":"B","description":"specialist"}],"max_handoffs":3}'
    );

    ut.expect(l_result.is_valid).to_be_true();
    ut.expect(l_result.error_reason).to_be_null();
  end orch_handoff_valid;


  procedure create_handoff_bad_target
  as
    l_id number;
  begin
    -- Targets do not exist as active profile agents -> c_err_invalid_config
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => 'TEST_VAL_HANDOFF_BAD',
      p_description          => 'Handoff agent with invalid targets',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => '{"pattern_type":"handoff","initial_agent_code":"TEST_VAL_NO_SUCH_AGENT",'
        || '"handoff_agents":[{"agent_code":"TEST_VAL_NO_SUCH_AGENT_2","description":"missing"}]}',
      p_status               => uc_ai_agents_api.c_status_active
    );
  end create_handoff_bad_target;


  procedure orch_conversation_missing_fields
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"conversation","participant_agents":[]}'
    );
    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Conversation config missing required field: conversation_mode'
    );

    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"conversation","conversation_mode":"round_robin"}'
    );
    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Conversation config missing required field: participant_agents'
    );
  end orch_conversation_missing_fields;


  procedure orch_bad_pattern_type
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config(
      '{"pattern_type":"xyz"}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Invalid pattern_type: xyz. Must be one of: orchestrator, handoff, conversation'
    );
  end orch_bad_pattern_type;


  procedure orch_invalid_json_returns_invalid
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_orchestration_config('not json');

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_be_like('Error parsing orchestration config:%');
  end orch_invalid_json_returns_invalid;


  -- validate_agent_references / check_agent_not_referenced -------------------

  procedure refs_existing_agent_valid
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_agent_references(
      p_workflow_definition =>
        '{"workflow_type":"sequential","steps":[{"agent_code":"' || gc_agent_a || '"}]}'
    );

    ut.expect(l_result.is_valid).to_be_true();
    ut.expect(l_result.error_reason).to_be_null();
  end refs_existing_agent_valid;


  procedure refs_profile_code_valid
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    -- active prompt profile codes also satisfy agent_code references
    l_result := uc_ai_agents_api.validate_agent_references(
      p_workflow_definition =>
        '{"workflow_type":"sequential","steps":[{"agent_code":"' || gc_profile_code || '"}]}'
    );

    ut.expect(l_result.is_valid).to_be_true();
  end refs_profile_code_valid;


  procedure refs_missing_agent_invalid
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_agent_references(
      p_workflow_definition =>
        '{"workflow_type":"sequential","steps":[{"agent_code":"TEST_VAL_NOPE"}]}'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_equal(
      'Referenced agent or profile does not exist: TEST_VAL_NOPE'
    );
  end refs_missing_agent_invalid;


  procedure refs_invalid_orch_json
  as
    l_result uc_ai_agents_api.t_validation_result;
  begin
    l_result := uc_ai_agents_api.validate_agent_references(
      p_orchestration_config => 'not json'
    );

    ut.expect(l_result.is_valid).to_be_false();
    ut.expect(l_result.error_reason).to_be_like('Invalid JSON in orchestration_config:%');
  end refs_invalid_orch_json;


  procedure check_referenced_raises
  as
  begin
    -- gc_agent_a is referenced by gc_agent_wf's workflow definition
    begin
      uc_ai_agents_api.check_agent_not_referenced(gc_agent_a);
      ut.fail('Expected check_agent_not_referenced to raise for a referenced agent');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_has_references);
        ut.expect(sqlerrm).to_be_like('%Cannot delete "' || gc_agent_a || '": referenced by 1 record(s)%');
    end;
  end check_referenced_raises;


  procedure check_unreferenced_passes
  as
  begin
    uc_ai_agents_api.check_agent_not_referenced(gc_agent_wf);
    -- reaching this point means no exception was raised
    ut.expect(true).to_be_true();
  end check_unreferenced_passes;


  -- prepare_profile_context ---------------------------------------------------

  procedure ctx_returns_provider_model
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => gc_profile_code,
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );

    ut.expect(l_provider).to_equal(uc_ai.c_provider_openai);
    ut.expect(l_model).to_equal('gpt-4o-mini');
  end ctx_returns_provider_model;


  procedure ctx_applies_profile_config
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => gc_profile_code,
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );

    -- from model_config_json of the profile
    ut.expect(uc_ai.g_enable_tools).to_be_true();
    ut.expect(uc_ai.g_max_tool_calls).to_equal(7);
  end ctx_applies_profile_config;


  procedure ctx_resets_stale_globals
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai.g_max_tool_calls := 99;

    -- an override replaces the profile config entirely; an empty override
    -- means the globals end up at framework defaults
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => gc_profile_code,
      p_config_override  => json_object_t(),
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );

    ut.expect(uc_ai.g_max_tool_calls).to_be_null();
    ut.expect(uc_ai.g_enable_tools).to_be_false();
  end ctx_resets_stale_globals;


  procedure ctx_schema_from_profile_column
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => gc_profile_code,
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );

    ut.expect(l_schema is not null).to_be_true();
    ut.expect(l_schema.get_string('type')).to_equal('object');
    ut.expect(l_schema.get_object('properties').has('confidence')).to_be_true();
  end ctx_schema_from_profile_column;


  procedure ctx_schema_override_wins
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => gc_profile_code,
      p_config_override  => json_object_t(
        '{"response_schema":{"type":"object","properties":{"z":{"type":"string"}}}}'
      ),
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );

    ut.expect(l_schema.get_object('properties').has('z')).to_be_true();
    ut.expect(l_schema.get_object('properties').has('confidence')).to_be_false();
  end ctx_schema_override_wins;


  procedure ctx_unknown_code
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => 'TEST_VAL_DOES_NOT_EXIST',
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );
  end ctx_unknown_code;


  procedure ctx_invalid_override_key
  as
    l_provider uc_ai_prompt_profiles.provider%type;
    l_model    uc_ai_prompt_profiles.model%type;
    l_schema   json_object_t;
  begin
    uc_ai_prompt_profiles_api.prepare_profile_context(
      p_code             => gc_profile_code,
      p_config_override  => json_object_t('{"bogus_key":1}'),
      po_provider        => l_provider,
      po_model           => l_model,
      po_response_schema => l_schema
    );
  end ctx_invalid_override_key;


  -- execute_agent transaction visibility -------------------------------------

  procedure exec_uncommitted_agent_clear_err
  as
    l_id      number;
    l_result  json_object_t;
    l_sqlcode number;
    l_sqlerrm varchar2(4000 char);
  begin
    -- Create an agent but deliberately DO NOT commit it. Execution telemetry is
    -- written in an autonomous transaction whose agent_id FK cannot see this
    -- still-uncommitted row, so the autonomous insert self-deadlocks (ORA-00060)
    -- while the calling transaction is suspended waiting for it. create_execution
    -- must translate that into a clear config error telling the caller to commit.
    l_id := uc_ai_agents_api.create_agent(
      p_code                => 'TEST_VAL_UNCOMMITTED',
      p_description         => 'Uncommitted profile agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => gc_profile_code,
      p_status              => uc_ai_agents_api.c_status_active
    );

    begin
      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code       => 'TEST_VAL_UNCOMMITTED',
        p_input_parameters => json_object_t()
      );
      ut.fail('execute_agent should have raised for an uncommitted agent');
    exception
      when others then
        l_sqlcode := sqlcode;
        l_sqlerrm := sqlerrm;
    end;

    -- A clear config error (-20503), not a raw ORA-00060 deadlock
    ut.expect(l_sqlcode).to_equal(-20503);
    ut.expect(l_sqlerrm).to_be_like('%must be committed before execution%');

    rollback;  -- discard the uncommitted agent
  end exec_uncommitted_agent_clear_err;

end test_uc_ai_agent_validation;
/
