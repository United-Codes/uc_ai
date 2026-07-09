-- ============================================================================
-- UC AI Migration: v26.2 to v26.3
-- ============================================================================

-- ============================================================================
-- AGENT EXECUTIONS: environment/session context columns
-- ============================================================================

alter table uc_ai_agent_executions add (
  created_by             varchar2(255 char),
  db_user                varchar2(255 char),
  apex_user              varchar2(255 char),
  apex_session_id        number,
  apex_app_id            number,
  apex_page_id           number,
  os_user                varchar2(255 char),
  host                   varchar2(255 char),
  ip_address             varchar2(64 char),
  module                 varchar2(255 char),
  action                 varchar2(255 char),
  client_identifier      varchar2(255 char),
  sid                    number,
  env_context            clob,
  updated_at             timestamp
);

comment on column uc_ai_agent_executions.created_by is 'coalesce(real APEX user, DB user) at top-level execution start';
comment on column uc_ai_agent_executions.db_user is 'SYS_CONTEXT USERENV SESSION_USER';
comment on column uc_ai_agent_executions.apex_user is 'APEX APP_USER (null for uc_ai''s own synthetic session)';
comment on column uc_ai_agent_executions.apex_session_id is 'APEX APP_SESSION';
comment on column uc_ai_agent_executions.apex_app_id is 'APEX application ID';
comment on column uc_ai_agent_executions.apex_page_id is 'APEX page ID';
comment on column uc_ai_agent_executions.env_context is 'JSON dump of SYS_CONTEXT USERENV + APEX session values';

-- backfill so existing rows have a sensible last-modified value
update uc_ai_agent_executions
   set updated_at = coalesce(completed_at, started_at)
 where updated_at is null;


-- ============================================================================
-- AGENTS: each agent type requires its own configuration column populated
-- ============================================================================
-- Added ENABLE NOVALIDATE so pre-existing rows (only ever written through the
-- API, which already enforces these invariants) are not re-validated; the
-- constraints are enforced for all new and changed rows.

alter table uc_ai_agents add constraint uc_ai_agents_profile_ck check (
  agent_type <> 'profile' or prompt_profile_code is not null) enable novalidate;

alter table uc_ai_agents add constraint uc_ai_agents_workflow_ck check (
  agent_type <> 'workflow' or workflow_definition is not null) enable novalidate;

alter table uc_ai_agents add constraint uc_ai_agents_orch_ck check (
  agent_type not in ('orchestrator', 'handoff', 'conversation')
  or orchestration_config is not null) enable novalidate;


-- ============================================================================
-- AGENT EXECUTIONS: data-integrity constraint and parent index
-- ============================================================================

alter table uc_ai_agent_executions add constraint uc_ai_agent_exec_done_ck check (
  status not in ('completed', 'failed', 'timeout') or completed_at is not null)
  enable novalidate;

create index uc_ai_agent_exec_parent_idx on uc_ai_agent_executions(parent_execution_id);


-- ============================================================================
-- AGENT EXECUTIONS: trigger fires on insert OR update to maintain updated_at
-- ============================================================================

-- replaces the insert-only uc_ai_agent_executions_bi from v26.1
drop trigger uc_ai_agent_executions_bi;

create or replace trigger uc_ai_agent_executions_biu
    before insert or update on uc_ai_agent_executions
    for each row
begin
    if inserting
    then
        :new.started_at := systimestamp;

        -- fallbacks for inserts outside the API; API-captured values win
        if :new.created_by is null
        then
            :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
        end if;

        if :new.db_user is null
        then
            :new.db_user := user;
        end if;
    end if;

    -- audit every state change (checkpoint, completion, failure)
    :new.updated_at := systimestamp;
end uc_ai_agent_executions_biu;
/
