-- ============================================================================
-- UC AI Migration: v26.4 to v26.5
-- ============================================================================
-- Safe to run more than once: every step checks the data dictionary first.
-- Run upgrade_packages.sql after this script.

-- ============================================================================
-- AGENT MESSAGES: provider tool call id
-- ============================================================================
-- Pairs a tool_call row with its tool_result row. Rows written before this
-- release keep a null id.

declare
  l_column user_tab_columns.column_name%type;
  c_stmt   constant varchar2(200 char) := 'alter table uc_ai_agent_messages add (tool_call_id varchar2(255 char))';
begin
  select max(column_name)
    into l_column
    from user_tab_columns
   where table_name  = 'UC_AI_AGENT_MESSAGES'
     and column_name = 'TOOL_CALL_ID';

  if l_column is null then
    execute immediate c_stmt;
  end if;
end;
/

comment on column uc_ai_agent_messages.tool_call_id is 'Provider tool call id, set on tool_call and tool_result rows (null on all other roles and on rows written before v26.5). Pairs a tool_call row with its tool_result row. Google and Ollama synthesize ids such as tool_call_1 from a per-run counter, so an id is unique only within one execution_id. Pair rows on (execution_id, tool_call_id), never on tool_call_id alone';


-- ============================================================================
-- AGENTS: agent type 'decision' and its decision_config column
-- ============================================================================
-- Existing rows keep their values. The type check is dropped and created again
-- only when it does not list 'decision' yet. The new decision check is created
-- with ENABLE NOVALIDATE like the other per-type checks: no existing row can
-- have the type 'decision'.

declare
  l_count      pls_integer;
  c_add_column constant varchar2(200 char) := 'alter table uc_ai_agents add (decision_config clob)';
  c_drop_type  constant varchar2(200 char) := 'alter table uc_ai_agents drop constraint uc_ai_agents_type_ck';
  c_add_type   constant varchar2(500 char) := q'[alter table uc_ai_agents add constraint uc_ai_agents_type_ck check (agent_type in
      ('profile', 'workflow', 'orchestrator', 'handoff', 'conversation', 'decision'))]';
  c_add_check  constant varchar2(500 char) := q'[alter table uc_ai_agents add constraint uc_ai_agents_decision_ck check (
      agent_type <> 'decision' or decision_config is not null) enable novalidate]';
begin
  select count(*)
    into l_count
    from user_tab_columns
   where table_name  = 'UC_AI_AGENTS'
     and column_name = 'DECISION_CONFIG';

  if l_count = 0 then
    execute immediate c_add_column;
  end if;

  select count(*)
    into l_count
    from user_constraints
   where table_name      = 'UC_AI_AGENTS'
     and constraint_name = 'UC_AI_AGENTS_TYPE_CK'
     and search_condition_vc like '%''decision''%';

  if l_count = 0 then
    select count(*)
      into l_count
      from user_constraints
     where table_name      = 'UC_AI_AGENTS'
       and constraint_name = 'UC_AI_AGENTS_TYPE_CK';

    if l_count > 0 then
      execute immediate c_drop_type;
    end if;

    execute immediate c_add_type;
  end if;

  select count(*)
    into l_count
    from user_constraints
   where table_name      = 'UC_AI_AGENTS'
     and constraint_name = 'UC_AI_AGENTS_DECISION_CK';

  if l_count = 0 then
    execute immediate c_add_check;
  end if;
end;
/

comment on column uc_ai_agents.decision_config is 'For agent_type = ''decision'': JSON object with provider, model, state_template, questions and optional options and model_config. Run through uc_ai.decide';
