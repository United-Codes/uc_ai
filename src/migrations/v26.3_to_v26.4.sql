-- ============================================================================
-- UC AI Migration: v26.3 to v26.4
-- ============================================================================

-- ============================================================================
-- AGENT EXECUTIONS / SESSIONS: run context
-- ============================================================================

alter table uc_ai_agent_executions add (
  run_context clob
);

alter table uc_ai_agent_sessions add (
  run_context clob
);

comment on column uc_ai_agent_executions.run_context is 'Run-context bag (JSON name/value pairs) in force for this run; inherited by nested sub-agent runs';
comment on column uc_ai_agent_sessions.run_context is 'Run-context bag bound to this conversation on its first turn. Keys already present are immutable: a later turn can add a key but cannot change one.';
