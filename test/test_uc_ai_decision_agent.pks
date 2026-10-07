create or replace package test_uc_ai_decision_agent as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Decision agent storage, validation and guards (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- LLM-free tests for agent_type = 'decision': CRUD, versioning, the checks of
  -- decision_config, the guards of execute_agent and the places that must not
  -- accept a decision agent (handoff, conversation). The executor is a later
  -- work package: execute_agent raises "not implemented yet" for now.

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%aftereach
  procedure reset_globals;

  -- CRUD, versioning, status -------------------------------------------------

  --%test(create_agent stores a decision agent and get_agent reads it back)
  procedure create_and_read;

  --%test(create_new_version copies decision_config and the type)
  procedure new_version_copies_config;

  --%test(update_agent changes decision_config and description)
  procedure update_changes_config;

  --%test(A decision agent can be activated and archived)
  procedure activate_and_archive;

  --%test(A workflow can reference an active decision agent as a step)
  procedure workflow_references_decision_agent;

  --%test(purge_agent deletes a decision agent)
  procedure purge_deletes_agent;

  -- validate_decision_config -------------------------------------------------

  --%test(Valid openai config passes)
  procedure val_valid_openai;

  --%test(Valid typesafe config with model_config and options passes)
  procedure val_valid_typesafe_full;

  --%test(A config without model passes: the provider default applies)
  procedure val_model_optional;

  --%test(Null config is invalid)
  procedure val_null;

  --%test(Config that is not JSON is invalid)
  procedure val_not_json;

  --%test(Config that is a JSON array is invalid)
  procedure val_not_object;

  --%test(Unknown top-level key is invalid)
  procedure val_unknown_key;

  --%test(Missing provider is invalid)
  procedure val_missing_provider;

  --%test(Provider that is not a string is invalid)
  procedure val_provider_not_string;

  --%test(Provider without decision support is invalid)
  procedure val_unsupported_provider;

  --%test(Model that is not a string is invalid)
  procedure val_model_not_string;

  --%test(Missing state_template is invalid)
  procedure val_missing_state_template;

  --%test(Blank state_template is invalid)
  procedure val_blank_state_template;

  --%test(state_template that is not a string is invalid)
  procedure val_state_template_not_string;

  --%test(Missing questions is invalid)
  procedure val_missing_questions;

  --%test(questions that is not an object is invalid)
  procedure val_questions_not_object;

  --%test(Empty questions object is invalid)
  procedure val_empty_questions;

  --%test(options that is not an object is invalid)
  procedure val_options_not_object;

  --%test(model_config that is not an object is invalid)
  procedure val_model_config_not_object;

  --%test(Unknown key in model_config is invalid)
  procedure val_model_config_unknown_key;

  -- create_agent / update_agent ----------------------------------------------

  --%test(create_agent rejects a decision agent without decision_config)
  --%throws(-20502)
  procedure create_missing_config;

  --%test(create_agent rejects an invalid decision_config)
  --%throws(-20503)
  procedure create_invalid_config;

  --%test(create_agent rejects decision_config on a profile agent)
  --%throws(-20503)
  procedure create_config_on_profile;

  --%test(create_agent rejects decision_config on a workflow agent)
  --%throws(-20503)
  procedure create_config_on_workflow;

  --%test(create_agent rejects prompt_profile_code on a decision agent)
  --%throws(-20503)
  procedure create_decision_with_profile;

  --%test(create_agent rejects workflow_definition on a decision agent)
  --%throws(-20503)
  procedure create_decision_with_workflow;

  --%test(create_agent rejects orchestration_config on a decision agent)
  --%throws(-20503)
  procedure create_decision_with_orch;

  --%test(update_agent rejects an invalid decision_config)
  --%throws(-20503)
  procedure update_invalid_config;

  --%test(update_agent rejects decision_config on a profile agent)
  --%throws(-20503)
  procedure update_config_on_profile;

  --%test(update_agent rejects prompt_profile_code on a decision agent)
  --%throws(-20503)
  procedure update_decision_with_profile;

  --%test(The table rejects a decision agent without decision_config)
  procedure table_check_decision_config;

  --%test(The table accepts the type decision and rejects an unknown type)
  procedure table_check_type;

  -- handoff and conversation -------------------------------------------------

  --%test(A decision agent cannot be a handoff target)
  --%throws(-20503)
  procedure handoff_target_rejected;

  --%test(A decision agent cannot be a conversation participant)
  --%throws(-20503)
  procedure conversation_participant_rejected;

  --%test(update_agent rejects a decision agent as conversation participant)
  --%throws(-20503)
  procedure conversation_update_rejected;

  -- execute_agent ------------------------------------------------------------

  --%test(execute_agent on a decision agent raises not implemented yet)
  procedure exec_not_implemented;

  --%test(execute_agent accepts p_files for a decision agent)
  procedure exec_accepts_files;

  --%test(execute_agent rejects p_response_schema for a decision agent)
  procedure exec_rejects_response_schema;

  --%test(execute_agent rejects p_extra_tool_tag for a decision agent)
  procedure exec_rejects_extra_tool_tag;

  --%test(execute_agent rejects p_prompt_addendum for a decision agent)
  procedure exec_rejects_prompt_addendum;

  --%test(execute_agent rejects p_follow_up_message for a decision agent)
  procedure exec_rejects_follow_up;

end test_uc_ai_decision_agent;
/
