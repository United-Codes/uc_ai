create or replace package test_uc_ai_decision_agent as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Decision agent storage, validation, guards and execution (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- LLM-free tests for agent_type = 'decision': CRUD, versioning, the checks of
  -- decision_config, the guards of execute_agent, the places that must not
  -- accept a decision agent (handoff, conversation) and the executor. The
  -- executor tests answer from the recorded samples through the mock transport
  -- (uc_ai_test_http_mock), so no provider is reached. The mock needs a build
  -- compiled with UC_AI_DEBUG:TRUE (scripts/enable_test_transport.sql).

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%beforeeach
  procedure reset_mock;

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

  --%test(execute_agent rejects p_response_schema for a decision agent)
  procedure exec_rejects_response_schema;

  --%test(execute_agent rejects p_extra_tool_tag for a decision agent)
  procedure exec_rejects_extra_tool_tag;

  --%test(execute_agent rejects p_prompt_addendum for a decision agent)
  procedure exec_rejects_prompt_addendum;

  --%test(execute_agent rejects p_follow_up_message for a decision agent)
  procedure exec_rejects_follow_up;

  -- executor: result, tokens, answers ---------------------------------------

  --%test(OpenAI: the execution holds the tokens of the call and the result has no raw)
  procedure exec_tokens_openai;

  --%test(TypeSafe: the execution holds input and output tokens)
  procedure exec_tokens_typesafe;

  --%test(OpenAI: a boolean, a choice and a score come back in final_message)
  procedure exec_answers_openai;

  --%test(TypeSafe: a boolean, a choice and a score come back in final_message)
  procedure exec_answers_typesafe;

  --%test(A refused question is {type: refused} without choice, the others are answered)
  procedure exec_refusal;

  --%test(A top-level run stores the answers as the assistant message)
  procedure exec_top_level_persists_message;

  -- executor: state_template ------------------------------------------------

  --%test(state_template placeholders are replaced like in a prompt profile)
  procedure exec_state_template;

  --%test(A placeholder without a value fails the run before any request)
  procedure exec_missing_variable;

  --%test(The run context fills a placeholder the input does not supply)
  procedure exec_run_context_placeholder;

  -- executor: settings ------------------------------------------------------

  --%test(model_config is used and the session globals are ignored and unchanged)
  procedure exec_model_config_beats_globals;

  --%test(A credential of the provider block in model_config is used)
  procedure exec_provider_credential;

  -- executor: files, errors -------------------------------------------------

  --%test(OpenAI: an image reaches the request as input_image)
  procedure exec_image_file;

  --%test(TypeSafe: a file fails before any request and the execution fails)
  procedure exec_typesafe_rejects_file;

  --%test(A provider error fails the execution with the error and zero tokens)
  procedure exec_provider_error;

  --%test(A decision_config that was edited to garbage fails with a clear error)
  procedure exec_garbage_config;

  -- executor: workflow and tools --------------------------------------------

  --%test(Workflow: the branch of the chosen department runs, the other is skipped)
  procedure wf_route_taken_branch;

  --%test(Workflow: the child execution holds the tokens, the session total equals it)
  procedure wf_token_attribution;

  --%test(Workflow: a refused question makes every condition on its choice false)
  procedure wf_refusal_trap;

  --%test(Workflow: a condition on type = refused works)
  procedure wf_refusal_type_condition;

  --%test(Workflow: a decision step as the last step gives the workflow the answers)
  procedure wf_final_message_is_object;

  --%test(run_agent_as_tool returns the decision JSON)
  procedure as_tool_returns_json;

  -- uc_ai_prompt_profiles_api.render_template (placeholder rendering) --------

  --%test(render_template: a value that contains a placeholder is not expanded)
  procedure tpl_value_is_not_rescanned;

  --%test(render_template: a backslash or a backreference in a value stays as it is)
  procedure tpl_value_is_literal;

  --%test(render_template: a value of 100000 characters renders)
  procedure tpl_large_value;

  --%test(render_template: a key with regex characters matches literally)
  procedure tpl_special_character_key;

  --%test(render_template: case, number, boolean, object, array and repeated placeholders)
  procedure tpl_unchanged_behaviour;

  --%test(render_template: a placeholder without a value raises, an extra key is ignored)
  procedure tpl_missing_and_extra;

  --%test(A decision agent sends an input value that contains a placeholder as it is)
  procedure exec_value_with_placeholder_is_literal;

end test_uc_ai_decision_agent;
/
