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
  env_context            clob
);

comment on column uc_ai_agent_executions.created_by is 'coalesce(real APEX user, DB user) at top-level execution start';
comment on column uc_ai_agent_executions.db_user is 'SYS_CONTEXT USERENV SESSION_USER';
comment on column uc_ai_agent_executions.apex_user is 'APEX APP_USER (null for uc_ai''s own synthetic session)';
comment on column uc_ai_agent_executions.apex_session_id is 'APEX APP_SESSION';
comment on column uc_ai_agent_executions.apex_app_id is 'APEX application ID';
comment on column uc_ai_agent_executions.apex_page_id is 'APEX page ID';
comment on column uc_ai_agent_executions.env_context is 'JSON dump of SYS_CONTEXT USERENV + APEX session values';

create or replace trigger uc_ai_agent_executions_bi
    before insert on uc_ai_agent_executions
    for each row
begin
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
end uc_ai_agent_executions_bi;
/
