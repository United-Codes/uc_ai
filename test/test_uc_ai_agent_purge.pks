create or replace package test_uc_ai_agent_purge as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent Purge Tests)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- ==========================================================================
  -- uc_ai_agents_api.purge_agent removes an agent and everything that belongs
  -- only to it. Every agent here is a PL/SQL-only workflow agent, so the suite
  -- runs without a model call. The memory rows are written directly, because
  -- what matters is which rows the purge takes and which it leaves.
  -- ==========================================================================

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(delete_agent refuses an agent that has run, so nothing is lost by accident)
  procedure delete_agent_keeps_history;

  --%test(Purging removes the agent, its runs, its sessions and its messages)
  procedure purge_removes_history;

  --%test(Purging removes every version of the agent)
  procedure purge_removes_all_versions;

  --%test(Purging removes the runs of a sub-agent it started, whatever agent ran them)
  procedure purge_removes_nested_runs;

  --%test(Purging removes the memory of the agent and its configuration)
  procedure purge_removes_own_memory;

  --%test(Purging keeps a shared, a global and a foreign context memory store)
  procedure purge_keeps_shared_memory;

  --%test(Purging keeps the prompt profile, which lives without an agent)
  procedure purge_keeps_prompt_profile;

  --%test(Purging an agent another agent delegates to is refused)
  procedure purge_refuses_referenced_agent;

  --%test(Purging an agent that does not exist raises)
  procedure purge_unknown_agent_raises;

end test_uc_ai_agent_purge;
/
