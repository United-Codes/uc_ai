create or replace package test_uc_ai_agent_as_tool as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent as Tool Tests)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- ==========================================================================
  -- The agent-as-tool pattern: a tool whose handler is
  -- uc_ai_agents_api.run_agent_as_tool. Every sub-agent here is a PL/SQL-only
  -- workflow agent, so the whole suite runs without a model call.
  --
  -- Execution telemetry commits autonomously, so rows of earlier runs survive
  -- the rollback of a test. Every test therefore reads its own rows only: it
  -- takes an execution-id marker before the call, or it generates the session
  -- id it looks for. No test depends on another test, or on an empty schema.
  -- ==========================================================================

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(The handler runs the sub-agent and returns its final message)
  procedure tool_returns_sub_agent_answer;

  --%test(The tool arguments become the input parameters of the sub-agent)
  procedure arguments_reach_sub_agent;

  --%test(The handler answers when the tool has no arguments at all)
  procedure handler_tolerates_no_arguments;

  --%test(An empty run context bag is stored as nothing, not as an empty object)
  procedure empty_context_is_stored_as_null;

  --%test(A run context key that is not an object is dropped, not passed on)
  procedure bogus_context_is_ignored;

  --%test(A tool called outside an agent run has no parent and is its own turn)
  procedure outside_run_is_own_turn;

  --%test(The session parameter of the handler beats the run context key)
  procedure session_param_beats_context;

  --%test(A sub-agent run started inside an agent run links to its caller)
  procedure sub_run_links_to_parent;

  --%test(A sub-agent started from a tool inherits the run context of the caller)
  procedure nested_run_inherits_context;

  --%test(A nested run sent to another session stays unlinked and keeps a header)
  procedure explicit_session_skips_link;

  --%test(A session id in the run context cannot move a run out of its caller)
  procedure ctx_session_cannot_move_run;

  --%test(The run context of the provider settings record reaches the sub-agent)
  procedure settings_context_reaches_agent;

  --%test(The version parameter of the handler runs that version of the agent)
  procedure version_param_pins_the_agent;

  --%test(The orchestrator registers the shared handler and it delegates)
  procedure generated_handler_is_the_helper;

  --%test(The orchestrator can register a delegate that has no input schema)
  procedure delegate_without_schema_works;

  --%test(The generated handler survives a single quote in the agent code)
  procedure quoted_agent_code_is_safe;

  --%test(A run that answers with JSON null does not give the model the word null)
  procedure null_answer_is_not_the_word_null;

  --%test(The reserved session id key is not bound to the run as a value)
  procedure session_key_is_not_a_binding;

  --%test(A failed sub-agent run comes back as text, not as an error)
  procedure failure_comes_back_as_text;

  --%test(A circular agent-as-tool reference stops at the nesting limit)
  procedure recursion_hits_depth_limit;

  --%test(A tool code of your own is the code of the tool)
  procedure explicit_tool_code_is_used;

  --%test(Without a tool code the name of the tool is generated)
  procedure generated_tool_code_is_used;

  --%test(The same tool code twice raises the unique constraint)
  procedure same_tool_code_twice_raises;

  --%test(Two generated codes leave two tools under one tag)
  procedure generated_code_duplicates_tool;

  --%test(The trigger sets created_by on the tool, its parameters and its tags)
  procedure the_trigger_sets_created_by;

end test_uc_ai_agent_as_tool;
/
