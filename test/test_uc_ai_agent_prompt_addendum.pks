create or replace package test_uc_ai_agent_prompt_addendum as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent prompt addendum and persisted tool call id (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- Every test runs an agent end to end against uc_ai_test_http_mock, so no
  -- provider is reached and no key is read: the profiles name a web credential
  -- that nothing resolves. The suite asserts on the request UC AI sent (the
  -- system message) and on the rows UC AI persisted (uc_ai_agent_messages).

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%beforeeach
  procedure reset_state;

  -- ---- tool_call_id ----------------------------------------------------------

  --%test(Tool call and tool result rows carry the provider tool call id, paired one to one)
  procedure tool_call_id_persisted_and_paired;

  --%test(get_session_messages returns the tool_call_id column)
  procedure tool_call_id_in_session_messages;

  -- ---- p_prompt_addendum -----------------------------------------------------

  --%test(The addendum ends the system message of the first turn, after a blank line)
  procedure addendum_ends_system_message;

  --%test(The addendum follows the MEMORY PROTOCOL block)
  procedure addendum_follows_memory_protocol;

  --%test(A follow-up turn does not add the addendum a second time)
  procedure follow_up_keeps_addendum_once;

  --%test(A null addendum leaves the system message unchanged)
  procedure null_addendum_is_unchanged;

  --%test(An orchestrator agent honours the addendum)
  procedure orchestrator_honours_addendum;

  --%test(An agent without a pinned profile version runs the latest active of two versions)
  procedure unpinned_agent_uses_latest_profile;

  --%test(A workflow agent with an addendum raises ORA-20503 before it creates a run)
  procedure workflow_rejects_addendum;

  --%test(A workflow agent without an addendum still runs)
  procedure workflow_without_addendum_runs;

  -- ---- schema ----------------------------------------------------------------

  --%test(uc_ai_agent_messages.tool_call_id is a nullable varchar2(255 char) with a comment)
  procedure tool_call_id_column_contract;

end test_uc_ai_agent_prompt_addendum;
/
