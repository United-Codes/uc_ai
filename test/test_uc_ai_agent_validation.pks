create or replace package test_uc_ai_agent_validation as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent validation and profile context tests (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- LLM-free unit tests for uc_ai_agents_api validation functions and
  -- uc_ai_prompt_profiles_api.prepare_profile_context

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%aftereach
  procedure reset_globals;

  -- validate_workflow_definition ---------------------------------------------

  --%test(Valid sequential workflow definition passes)
  procedure wf_valid_sequential;

  --%test(Null workflow definition is invalid)
  procedure wf_null_invalid;

  --%test(Missing workflow_type is invalid)
  procedure wf_missing_type;

  --%test(Unknown workflow_type is invalid)
  procedure wf_bad_type;

  --%test(Missing steps is invalid)
  procedure wf_missing_steps;

  --%test(Empty steps array is invalid)
  procedure wf_empty_steps;

  --%test(Step without agent_code is invalid)
  procedure wf_step_missing_agent_code;

  --%test(Non-string step condition is invalid)
  procedure wf_non_string_condition;

  --%test(Invalid workflow JSON re-raises the parse error - characterization)
  procedure wf_invalid_json_raises;

  -- validate_orchestration_config --------------------------------------------

  --%test(Valid orchestrator config passes)
  procedure orch_valid_orchestrator;

  --%test(Null orchestration config is invalid)
  procedure orch_null;

  --%test(Missing pattern_type is invalid)
  procedure orch_missing_pattern;

  --%test(Orchestrator config without profile code or delegates is invalid)
  procedure orch_orchestrator_missing_fields;

  --%test(Handoff config without initial_agent_code is invalid)
  procedure orch_handoff_missing_initial;

  --%test(Conversation config without mode or participants is invalid)
  procedure orch_conversation_missing_fields;

  --%test(Unknown pattern_type is invalid)
  procedure orch_bad_pattern_type;

  --%test(Invalid orchestration JSON returns invalid instead of raising)
  procedure orch_invalid_json_returns_invalid;

  -- validate_agent_references / check_agent_not_referenced -------------------

  --%test(Reference to an existing active agent is valid)
  procedure refs_existing_agent_valid;

  --%test(Reference to an active prompt profile also counts as existing)
  procedure refs_profile_code_valid;

  --%test(Reference to a missing agent is invalid)
  procedure refs_missing_agent_invalid;

  --%test(Invalid orchestration JSON makes references invalid)
  procedure refs_invalid_orch_json;

  --%test(check_agent_not_referenced raises for a referenced agent)
  procedure check_referenced_raises;

  --%test(check_agent_not_referenced passes for an unreferenced agent)
  procedure check_unreferenced_passes;

  -- prepare_profile_context ---------------------------------------------------

  --%test(prepare_profile_context returns the profile provider and model)
  procedure ctx_returns_provider_model;

  --%test(prepare_profile_context applies the profile model config to globals)
  procedure ctx_applies_profile_config;

  --%test(Config override replaces the profile config and resets stale globals)
  procedure ctx_resets_stale_globals;

  --%test(Response schema is resolved from the profile column)
  procedure ctx_schema_from_profile_column;

  --%test(A response_schema in the config override wins over the profile column)
  procedure ctx_schema_override_wins;

  --%test(Unknown profile code raises not found)
  --%throws(-20500)
  procedure ctx_unknown_code;

  --%test(Unknown key in the config override raises invalid config)
  --%throws(-20503)
  procedure ctx_invalid_override_key;

end test_uc_ai_agent_validation;
/
