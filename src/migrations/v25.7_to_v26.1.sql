-- ============================================================================
-- UC AI Migration: v25.7 to v26.1
-- Multi-Agent Systems Support
-- ============================================================================

-- ============================================================================
-- AGENTS TABLE
-- ============================================================================

create sequence uc_ai_agents_seq;

create table uc_ai_agents (
  id                     number default on null uc_ai_agents_seq.nextval not null,
  code                   varchar2(255 char) not null,
  version                number default on null 1 not null,
  status                 varchar2(50 char) default on null 'draft' not null,
  description            varchar2(4000 char) not null,
  agent_type             varchar2(50 char) not null,
  
  -- For agent_type = 'profile'
  prompt_profile_code    varchar2(255 char),
  prompt_profile_version number,
  
  -- For agent_type = 'workflow'
  workflow_definition    clob,
  
  -- For agent_type = 'orchestrator'/'handoff'/'conversation'
  orchestration_config   clob,
  
  -- Shared configuration
  input_schema           clob,
  output_schema          clob,
  timeout_seconds        number,
  max_iterations         number,
  max_history_messages   number,
  
  created_by             varchar2(255 char) not null,
  created_at             timestamp not null,
  updated_by             varchar2(255 char) not null,
  updated_at             timestamp not null,
  
  constraint uc_ai_agents_pk primary key (id),
  constraint uc_ai_agents_uk unique (code, version),
  constraint uc_ai_agents_status_ck check (status in ('draft', 'active', 'archived')),
  constraint uc_ai_agents_type_ck check (agent_type in 
    ('profile', 'workflow', 'orchestrator', 'handoff', 'conversation'))
);

-- Ensure only one active version per code
create unique index uc_ai_agents_active_uk on uc_ai_agents(
  case when status = 'active' then code else null end
);

create index uc_ai_agents_code_idx on uc_ai_agents(code, version, status);

comment on table uc_ai_agents is 'Agent definitions for multi-agent systems';
comment on column uc_ai_agents.code is 'Unique code identifier for the agent';
comment on column uc_ai_agents.version is 'Version number of the agent';
comment on column uc_ai_agents.status is 'Status: draft, active, or archived';
comment on column uc_ai_agents.agent_type is 'Type: profile, workflow, orchestrator, handoff, or conversation';
comment on column uc_ai_agents.prompt_profile_code is 'For profile agents: code of the referenced prompt profile';
comment on column uc_ai_agents.prompt_profile_version is 'For profile agents: version of the referenced prompt profile (null = latest active)';
comment on column uc_ai_agents.workflow_definition is 'JSON workflow definition for workflow agents';
comment on column uc_ai_agents.orchestration_config is 'JSON orchestration config for orchestrator/handoff/conversation agents';
comment on column uc_ai_agents.max_history_messages is 'Maximum conversation history messages (for sliding window)';

create or replace trigger uc_ai_agents_biu
  before insert or update on uc_ai_agents
  for each row
begin
  if inserting then
    :new.created_at := systimestamp;
    :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
  end if;

  :new.updated_at := systimestamp;
  :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_agents_biu;
/

-- ============================================================================
-- AGENT EXECUTIONS TABLE
-- ============================================================================

create sequence uc_ai_agent_executions_seq;

create table uc_ai_agent_executions (
  id                     number default on null uc_ai_agent_executions_seq.nextval not null,
  agent_id               number not null,
  parent_execution_id    number,
  session_id             varchar2(255 char),
  
  input_parameters       clob,
  current_state          clob,
  output_result          clob,
  
  status                 varchar2(50 char) not null,
  iteration_count        number default on null 0 not null,
  tool_calls_count       number default on null 0 not null,
  
  -- Token and cost tracking
  total_input_tokens     number default on null 0 not null,
  total_output_tokens    number default on null 0 not null,
  total_cost_usd         number(10,6) default on null 0 not null,
  
  started_at             timestamp not null,
  completed_at           timestamp,
  error_message          varchar2(4000 char),
  
  constraint uc_ai_agent_executions_pk primary key (id),
  constraint uc_ai_agent_exec_agent_fk foreign key (agent_id) 
    references uc_ai_agents(id),
  constraint uc_ai_agent_exec_parent_fk foreign key (parent_execution_id) 
    references uc_ai_agent_executions(id),
  constraint uc_ai_agent_exec_status_ck check (status in 
    ('pending', 'running', 'completed', 'failed', 'timeout'))
);

create index uc_ai_agent_exec_session_idx on uc_ai_agent_executions(session_id);
create index uc_ai_agent_exec_status_idx on uc_ai_agent_executions(status, started_at);
create index uc_ai_agent_exec_agent_idx on uc_ai_agent_executions(agent_id);

comment on table uc_ai_agent_executions is 'Execution history and state for agent runs';
comment on column uc_ai_agent_executions.session_id is 'Groups related executions (use SYS_GUID)';
comment on column uc_ai_agent_executions.total_input_tokens is 'Total input tokens across all AI calls';
comment on column uc_ai_agent_executions.total_output_tokens is 'Total output tokens across all AI calls';
comment on column uc_ai_agent_executions.total_cost_usd is 'Accumulated cost in USD across all AI calls';

create or replace trigger uc_ai_agent_executions_bi
  before insert on uc_ai_agent_executions
  for each row
begin
  :new.started_at := systimestamp;
end uc_ai_agent_executions_bi;
/

-- ============================================================================
-- TEMPORARY TOOLS TABLE (for orchestrator pattern)
-- ============================================================================

create sequence uc_ai_temp_tools_seq;

create table uc_ai_temp_tools (
  id                     number default on null uc_ai_temp_tools_seq.nextval not null,
  execution_id           number not null,
  tool_id                number not null,
  created_at             timestamp default on null systimestamp not null,
  
  constraint uc_ai_temp_tools_pk primary key (id),
  constraint uc_ai_temp_tools_exec_fk foreign key (execution_id)
    references uc_ai_agent_executions(id) on delete cascade,
  constraint uc_ai_temp_tools_tool_fk foreign key (tool_id)
    references uc_ai_tools(id) on delete cascade
);

create index uc_ai_temp_tools_exec_idx on uc_ai_temp_tools(execution_id);

comment on table uc_ai_temp_tools is 'Tracks temporary tools created for orchestrator agent executions';

