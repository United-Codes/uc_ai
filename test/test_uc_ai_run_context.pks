create or replace package test_uc_ai_run_context as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-7230): allow global variables in a test package that doubles as an execution hook

  --%suite(Run Context Tests)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%aftereach
  procedure cleanup_context;

  -- ==========================================================================
  -- Execution-hook contract
  --
  -- This package doubles as the run's execution hook. augment_system_prompt is
  -- the one place UC AI hands control back to PL/SQL in the middle of a profile
  -- run: after the prompt is rendered and after an orchestrator registered its
  -- delegate tools, but before the provider is called. A test can therefore
  -- observe the run from the inside - the rendered prompt, the ambient
  -- execution context, and a delegate tool called at exactly the stack position
  -- the provider's tool loop would call it from - with no LLM involved.
  -- before_execution / after_execution are part of the contract and must exist.
  -- ==========================================================================

  -- what the hook saw on its last call
  g_seen_prompt      clob;
  g_seen_agent_code  varchar2(255 char);
  g_seen_run_context clob;
  g_hook_count       pls_integer := 0;

  -- when set, the hook runs the first tool whose code matches this LIKE pattern
  g_probe_tool_like  varchar2(255 char);
  g_probe_tool_args  clob;
  g_probe_result     clob;
  g_probe_error      varchar2(4000 char);

  procedure before_execution(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_created_by  in varchar2,
    p_apex_app_id in number,
    p_session_id  in varchar2
  );

  procedure after_execution(
    p_exec_id       in number,
    p_status        in varchar2,
    p_input_tokens  in number,
    p_output_tokens in number
  );

  procedure augment_system_prompt(
    pio_system_prompt in out nocopy clob
  );

  -- Body of a PL/SQL workflow step: starts a sub-agent that is meant to fail,
  -- swallows the failure, then records the execution context it is left with.
  g_ctx_after_failed_child clob;

  function spawn_failing_then_read return clob;

  -- ---- The bag as a value ---------------------------------------------------

  --%test(run_context_value reads a string, a number and a boolean out of the bag)
  procedure reads_scalar_values;

  --%test(run_context_value returns null for an absent key, a null bag and a malformed bag)
  procedure reads_missing_values;

  --%test(run_context_value serializes an object, an array and a nested bag)
  procedure reads_structured_values;

  --%test(run_context_value ignores a bag that is not a JSON object)
  procedure reads_non_object_bags;

  --%test(run_context_value caps a long value instead of raising)
  procedure caps_a_long_value;

  -- ---- What a tool receives -------------------------------------------------

  --%test(A tool receives the run context under _ctx)
  procedure tool_receives_context;

  --%test(_ctx is present but empty when the run carries no context)
  procedure tool_receives_empty_context;

  --%test(A _ctx the model put in the arguments is overwritten)
  procedure tool_context_is_not_forgeable;

  --%test(_ctx lands at the top level of a single object parameter that the provider unwrapped)
  procedure tool_context_on_unwrapped_object;

  --%test(The model-supplied arguments reach the tool unchanged next to _ctx)
  procedure tool_arguments_survive;

  --%test(Registering a tool with a parameter named _ctx is rejected)
  procedure reserved_parameter_name_rejected;

  --%test(Objects and arrays in the bag reach the tool verbatim)
  procedure tool_receives_structured_context;

  --%test(An empty bag reaches the tool as an empty _ctx)
  procedure tool_receives_empty_bag;

  --%test(A bag that is not a JSON object reaches the tool as an empty _ctx)
  procedure tool_receives_broken_bag;

  --%test(A large bag reaches the tool whole)
  procedure tool_receives_large_context;

  --%test(Quotes, backslashes, newlines and non-ASCII characters survive)
  procedure tool_receives_special_characters;

  --%test(A bag key of the same name as a tool parameter leaves the parameter alone)
  procedure tool_context_key_collides_with_parameter;

  --%test(A tool called with no arguments at all still runs and still gets _ctx)
  procedure tool_called_without_arguments;

  --%test(execute_agent_tool hands the settings run context to the tool)
  procedure agent_tool_threads_settings_context;

  -- ---- Binding a run and a conversation -------------------------------------

  --%test(The run context is recorded on the execution and on the session)
  procedure persists_on_execution_and_session;

  --%test(A later turn of the same session inherits the bound context)
  procedure later_turn_inherits_session_context;

  --%test(A later turn may repeat the same value)
  procedure later_turn_may_repeat_value;

  --%test(A later turn may add a new key)
  procedure later_turn_may_add_key;

  --%test(A later turn may not change a bound key)
  procedure later_turn_may_not_change_key;

  --%test(A key bound to JSON null is not bound: a later turn can still set it)
  procedure null_binding_can_be_set_later;

  --%test(A JSON null from a later turn leaves a bound key alone)
  procedure null_from_a_later_turn_is_ignored;

  --%test(Conflicts are detected across more than two turns)
  procedure conflict_across_three_turns;

  --%test(A nested sub-agent run inherits the parent run context)
  procedure nested_run_inherits;

  --%test(A nested run that opens its own session still inherits)
  procedure nested_run_with_own_session_inherits;

  --%test(A nested run may add a key)
  procedure nested_run_may_add_key;

  --%test(A nested run may not override an inherited key)
  procedure nested_run_may_not_override_key;

  --%test(A nested run that fails restores the caller's run context)
  procedure failed_nested_run_restores_context;

  -- ---- Prompt placeholders --------------------------------------------------

  --%test(The run context fills a prompt placeholder the input parameters do not supply)
  procedure context_fills_placeholder;

  --%test(An input parameter wins over the run context for the same placeholder)
  procedure input_parameter_wins;

  --%test(A placeholder that neither side supplies still raises)
  procedure unsupplied_placeholder_raises;

  --%test(An orchestrator prompt is filled from the run context too)
  procedure orchestrator_prompt_uses_context;

  --%test(A workflow step input is not widened by the run context)
  procedure workflow_step_input_unchanged;

  -- ---- Generated tools ------------------------------------------------------

  --%test(The run context is ambient while a run is in flight)
  procedure context_is_ambient_during_a_run;

  --%test(An orchestrator delegate tool passes the run context to its sub-agent)
  procedure orchestrator_delegate_inherits;

  --%test(A handoff sub-agent run inherits the run context)
  procedure handoff_child_inherits;

  -- ---- Code mode ------------------------------------------------------------

  --%test(A tool called from a code-mode program receives _ctx)
  procedure code_mode_tool_receives_context;

  --%test(A code-mode program cannot forge _ctx)
  procedure code_mode_cannot_forge_context;

  -- ---- Threading through the settings record --------------------------------

  --%test(build_from_globals carries the caller run context outside an agent run)
  procedure settings_carry_standalone_context;

  --%test(An agent run context wins over a run context passed to generate_text)
  procedure agent_context_wins_over_caller;

  --%test(build_from_config snapshots the execution context instead of dropping it)
  procedure config_settings_carry_context;

  --%test(build_from_config carries the caller run context outside an agent run)
  procedure config_settings_carry_standalone_context;

end test_uc_ai_run_context;
/
