create sequence uc_ai_tools_seq;

create table uc_ai_tools(
  id                   number default on null uc_ai_tools_seq.nextval not null,
  code                 varchar2(255 char)  not null,
  description          varchar2(4000 char) not null,
  active               number(1) default on null 1 not null,
  response_schema      clob,
  version              varchar2(50 char) default on null '1.0' not null,
  function_call        clob not null,
  authorization_schema varchar2(255 char),
  code_mode_access     varchar2(10 char) default on null 'both' not null,
  created_by           varchar2(255 char) not null,
  created_at           timestamp not null,
  updated_by           varchar2(255 char) not null,
  updated_at           timestamp not null,
  constraint uc_ai_tools_pk primary key (id),
  constraint uc_ai_tools_uk unique (code),
  constraint uc_ai_tools_active_ck check (active in (0,1)),
  -- Programmatic tool calling ("code mode") availability:
  --   direct = normal tool only, code = only via callTool() in a program, both = either
  constraint uc_ai_tools_cma_ck check (code_mode_access in ('direct','code','both'))
);

create sequence uc_ai_tool_parameters_seq;

create table uc_ai_tool_parameters(
  id                  number default on null uc_ai_tool_parameters_seq.nextval not null,
  tool_id             number not null,
  name                varchar2(255 char)  not null,
  description         varchar2(4000 char) not null,
  required            number(1) default on null 1 not null,
  data_type           varchar2(255 char) not null,
  min_num_val         number,
  max_num_val         number,
  enum_values         varchar2(4000 char),                -- For parameters with enumerated values, : seperated
  default_value       varchar2(4000 char),                -- Default value for the parameter
  is_array            number(1) default on null 0 not null,  -- Specify if the data_type is expected as an array (e. g. number -> number[])
  array_min_items     number,                        -- Minimum number of items in array
  array_max_items     number,                        -- Maximum number of items in array
  pattern             varchar2(4000 char),                -- Regex pattern for string validation
  format              varchar2(255 char),                 -- Format specifier (e.g., date-time, email)
  min_length          number,                        -- For string parameters
  max_length          number,                        -- For string parameters
  parent_param_id     number,                        -- For nested parameters
  created_by          varchar2(255 char) not null,
  created_at          timestamp not null,
  updated_by          varchar2(255 char) not null,
  updated_at          timestamp not null,
  constraint uc_ai_tool_parameters_pk primary key (id),
  constraint uc_ai_tool_parameters_uk unique (tool_id, name)
);

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_required_ck check (required in (0,1));

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_tool_id_fk foreign key (tool_id) references uc_ai_tools(id) on delete cascade;

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_data_type_ck check (
    data_type in ('string', 'number', 'integer', 'boolean', 'object')
  );

  -- For number/integer type: only min_num_val and max_num_val should be filled
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_number_cols_ck check (
      (data_type in ('number', 'integer') and 
      (min_length is null and max_length is null and pattern is null)) 
      or 
      (data_type not in ('number', 'integer'))
  );

  -- For string type: only min_length, max_length, pattern, and format should be filled
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_string_cols_ck check (
      (data_type = 'string' and 
      (min_num_val is null and max_num_val is null)) 
      or 
      (data_type != 'string')
  );

  -- For boolean type: most validation fields should be null
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_boolean_cols_ck check (
      (data_type = 'boolean' and 
      (min_num_val is null and max_num_val is null and 
        min_length is null and max_length is null and 
        pattern is null and format is null)) 
      or 
      (data_type != 'boolean')
  );

  -- For array type: ensure array flags are properly set
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_array_cols_ck check (
      (data_type = 'array' and is_array = 1) 
      or 
      (data_type != 'array')
  );

  -- Ensure array properties are only set when is_array = 1
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_array_props_ck check (
      (is_array = 1) 
      or 
      (is_array = 0 and array_min_items is null and array_max_items is null)
  );

  -- For enum values: ensure they're only used with appropriate types
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_enum_ck check (
      (enum_values is not null and data_type in ('string', 'number', 'integer')) 
      or 
      (enum_values is null)
  );

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_parent_param_id_fk foreign key (parent_param_id) references uc_ai_tool_parameters(id) on delete cascade
;  


create sequence uc_ai_tool_tags_seq;

create table uc_ai_tool_tags(
  id                   number default on null uc_ai_tool_tags_seq.nextval not null,
  tool_id              number not null,
  tag_name             varchar2(255 char) not null,
  created_by           varchar2(255 char) not null,
  created_at           timestamp not null,
  updated_by           varchar2(255 char) not null,
  updated_at           timestamp not null,
  constraint uc_ai_tool_tags_pk primary key (id),
  constraint uc_ai_tool_tags_uk unique (tool_id, tag_name),
  constraint uc_ai_tool_tags_tool_id_fk foreign key (tool_id) references uc_ai_tools(id) on delete cascade,
  constraint uc_ai_tool_tags_tag_lower_ck check (tag_name = lower(tag_name))
);  


create sequence uc_ai_prompt_profiles_seq;

create table uc_ai_prompt_profiles (
  id                     number default on null uc_ai_prompt_profiles_seq.nextval not null,
  code                   varchar2(255 char)  not null,
  version                number default on null 1 not null,
  status                 varchar2(50 char) default on null 'draft' not null,
  description            varchar2(4000 char) not null,

  system_prompt_template clob not null,
  user_prompt_template   clob not null,
  provider               varchar2(512 char) not null,
  model                  varchar2(512 char) not null,
  model_config_json      clob,
  response_schema        clob,
  parameters_schema      clob,

  created_by             varchar2(255 char) not null,
  created_at             timestamp not null,
  updated_by             varchar2(255 char) not null,
  updated_at             timestamp not null,
  constraint uc_ai_prompt_profiles_pk primary key (id),
  constraint uc_ai_prompt_profiles_uk unique (code, version),
  constraint uc_ai_prompt_profiles_status_ck check (status in ('draft', 'active', 'archived'))
);


-- ============================================================================
-- AGENTS TABLE (Multi-Agent Systems)
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
    ('profile', 'workflow', 'orchestrator', 'handoff', 'conversation')),
  -- Each agent type requires its own configuration column to be populated
  constraint uc_ai_agents_profile_ck check (
    agent_type <> 'profile' or prompt_profile_code is not null),
  constraint uc_ai_agents_workflow_ck check (
    agent_type <> 'workflow' or workflow_definition is not null),
  constraint uc_ai_agents_orch_ck check (
    agent_type not in ('orchestrator', 'handoff', 'conversation')
    or orchestration_config is not null)
);

-- Ensure only one active version per code
create unique index uc_ai_agents_active_uk on uc_ai_agents(
  case when status = 'active' then code else null end
);

create index uc_ai_agents_code_idx on uc_ai_agents(code, version, status);


-- ============================================================================
-- AGENT EXECUTIONS TABLE
-- ============================================================================

create sequence uc_ai_agent_executions_seq;

create table uc_ai_agent_executions (
  id                     number default on null uc_ai_agent_executions_seq.nextval not null,
  agent_id               number not null,
  parent_execution_id    number,
  session_id             varchar2(255 char),
  -- Sequential turn number within the session; only set for top-level
  -- executions (parent_execution_id is null). Nested sub-agent runs leave it null.
  turn_index             number,

  input_parameters       clob,
  current_state          clob,
  output_result          clob,
  
  status                 varchar2(50 char) not null,
  iteration_count        number default on null 0 not null,
  tool_calls_count       number default on null 0 not null,
  
  -- Token and cost tracking
  total_input_tokens     number default on null 0 not null,
  total_output_tokens    number default on null 0 not null,
  
  started_at             timestamp not null,
  completed_at           timestamp,
  updated_at             timestamp,
  error_message          varchar2(4000 char),

  -- Environment/session context (captured at top-level execution start)
  created_by             varchar2(255 char),
  db_user                varchar2(255 char),
  apex_user              varchar2(255 char),
  audience               varchar2(20 char),
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

  -- Run context in force for this run (JSON name/value pairs)
  run_context            clob,

  constraint uc_ai_agent_executions_pk primary key (id),
  constraint uc_ai_agent_exec_agent_fk foreign key (agent_id) 
    references uc_ai_agents(id),
  constraint uc_ai_agent_exec_parent_fk foreign key (parent_execution_id) 
    references uc_ai_agent_executions(id),
  constraint uc_ai_agent_exec_status_ck check (status in
    ('pending', 'running', 'completed', 'failed', 'timeout')),
  -- A finished execution must record when it finished
  constraint uc_ai_agent_exec_done_ck check (
    status not in ('completed', 'failed', 'timeout') or completed_at is not null)
);

create index uc_ai_agent_exec_session_idx on uc_ai_agent_executions(session_id);
create index uc_ai_agent_exec_status_idx on uc_ai_agent_executions(status, started_at);
create index uc_ai_agent_exec_agent_idx on uc_ai_agent_executions(agent_id);
create index uc_ai_agent_exec_parent_idx on uc_ai_agent_executions(parent_execution_id);
-- Per-APEX-session usage lookups (an extension governing anonymous traffic pairs
-- the session equality with a started_at window, so keep them in one index).
create index uc_ai_agent_exec_apex_sess_idx on uc_ai_agent_executions(apex_session_id, started_at);

comment on column uc_ai_agent_executions.created_by is 'coalesce(real APEX user, DB user) at top-level execution start';
comment on column uc_ai_agent_executions.db_user is 'SYS_CONTEXT USERENV SESSION_USER';
comment on column uc_ai_agent_executions.apex_user is 'APEX APP_USER (null for uc_ai''s own synthetic session)';
comment on column uc_ai_agent_executions.audience is 'Caller class at execution start: public (anonymous APEX visitor) | authenticated (logged-in APEX user) | db (database/job session, or uc_ai''s own synthetic session)';
comment on column uc_ai_agent_executions.apex_session_id is 'APEX APP_SESSION';
comment on column uc_ai_agent_executions.apex_app_id is 'APEX application ID';
comment on column uc_ai_agent_executions.apex_page_id is 'APEX page ID';
comment on column uc_ai_agent_executions.env_context is 'JSON dump of SYS_CONTEXT USERENV + APEX session values';
comment on column uc_ai_agent_executions.run_context is 'Run-context bag (JSON name/value pairs) in force for this run; inherited by nested sub-agent runs';
comment on column uc_ai_agent_executions.turn_index is 'Sequential turn number within the session (top-level executions only; null for nested sub-agent runs)';


-- ============================================================================
-- AGENT SESSIONS: conversation header, one row per session_id
-- ============================================================================
-- A session groups all executions (turns + their nested sub-agent runs) of a
-- single conversation. Aggregates (token totals, turn/message counts, status)
-- are maintained by the API in the top-level completion path.
create table uc_ai_agent_sessions (
  session_id             varchar2(255 char) not null,
  root_agent_id          number,
  title                  varchar2(200 char),

  -- End-user verdict on the conversation, set by the front end. Null means "not
  -- rated" — never "rated neutral", so an unanswered ask stays distinguishable
  -- from a deliberate one.
  feedback_rating        varchar2(10 char),
  feedback_comment       varchar2(2000 char),
  feedback_at            timestamp,

  status                 varchar2(50 char),
  turn_count             number default on null 0 not null,
  message_count          number default on null 0 not null,

  -- Sum of the OWN tokens of every execution in the session (no double count:
  -- each execution records only the tokens of the LLM calls it made itself).
  total_input_tokens     number default on null 0 not null,
  total_output_tokens    number default on null 0 not null,

  started_at             timestamp,
  last_activity_at       timestamp,
  updated_at             timestamp,

  -- Environment/session context, snapshotted from the first (opening) turn
  created_by             varchar2(255 char),
  db_user                varchar2(255 char),
  apex_user              varchar2(255 char),
  audience               varchar2(20 char),
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

  -- Run context bound to this conversation on its first turn
  run_context            clob,

  constraint uc_ai_agent_sessions_pk primary key (session_id),
  constraint uc_ai_agent_sess_agent_fk foreign key (root_agent_id)
    references uc_ai_agents(id),
  constraint uc_ai_agent_sess_status_ck check (status in
    ('pending', 'running', 'completed', 'failed', 'timeout')),
  constraint uc_ai_agent_sess_fb_ck check (feedback_rating in ('up', 'down'))
);

create index uc_ai_agent_sess_activity_idx on uc_ai_agent_sessions(last_activity_at);
create index uc_ai_agent_sess_agent_idx on uc_ai_agent_sessions(root_agent_id);
-- "My conversations, newest first": a chat front end runs this on every page
-- load, so keep the created_by equality and the last_activity_at ordering in one
-- index. Ascending is enough — the descending scan reads it backwards.
create index uc_ai_agent_sess_user_idx on uc_ai_agent_sessions(created_by, last_activity_at);

comment on table uc_ai_agent_sessions is 'Conversation header: one row per session_id grouping all executions (turns + nested sub-agent runs)';
comment on column uc_ai_agent_sessions.audience is 'Caller class of the opening turn: public | authenticated | db';
comment on column uc_ai_agent_sessions.root_agent_id is 'Agent that opened the session (first top-level turn)';
comment on column uc_ai_agent_sessions.title is 'Optional human-readable conversation title, set by the front end via set_session_title';
comment on column uc_ai_agent_sessions.feedback_rating is 'Optional end-user verdict on the conversation: up | down. Null = not rated, set by the front end via set_session_feedback';
comment on column uc_ai_agent_sessions.feedback_comment is 'Optional free-text comment the end user left alongside feedback_rating';
comment on column uc_ai_agent_sessions.feedback_at is 'When feedback_rating was last set; nulled together with the rating when feedback is withdrawn';
comment on column uc_ai_agent_sessions.run_context is 'Run-context bag bound to this conversation on its first turn. Keys already present are immutable: a later turn can add a key but cannot change one.';
comment on column uc_ai_agent_sessions.status is 'Status of the most recent top-level turn';
comment on column uc_ai_agent_sessions.total_input_tokens is 'SUM of own input tokens across all executions in the session';
comment on column uc_ai_agent_sessions.total_output_tokens is 'SUM of own output tokens across all executions in the session';


-- ============================================================================
-- AGENT MESSAGES: normalized, untrimmed per-message conversation log
-- ============================================================================
-- One row per message content item, in conversation order (seq). Written per
-- turn as the delta of new messages, so history-window trimming (which only
-- governs what is sent to the LLM) never erodes the persisted record.
create sequence uc_ai_agent_messages_seq;

create table uc_ai_agent_messages (
  id                     number default on null uc_ai_agent_messages_seq.nextval not null,
  session_id             varchar2(255 char) not null,
  execution_id           number not null,

  -- Global, gap-tolerant ordering within the session
  seq                    number not null,

  -- user | assistant | tool_call | tool_result | reasoning | system
  role                   varchar2(50 char) not null,
  content                clob,

  -- Agent that produced this message: the sub-agent for wrapper turns
  -- (conversation participant, handoff specialist), the turn's own agent
  -- otherwise. Null for the caller's user/system input. No FK - kept as a
  -- plain string (like tool_name) so history survives agent deletion.
  agent_code             varchar2(255 char),

  tool_name              varchar2(255 char),
  tool_input             clob,
  tool_output            clob,
  tool_status            varchar2(50 char),

  created_at             timestamp not null,

  constraint uc_ai_agent_messages_pk primary key (id),
  constraint uc_ai_agent_msg_session_fk foreign key (session_id)
    references uc_ai_agent_sessions(session_id),
  constraint uc_ai_agent_msg_exec_fk foreign key (execution_id)
    references uc_ai_agent_executions(id),
  constraint uc_ai_agent_msg_role_ck check (role in
    ('user', 'assistant', 'tool_call', 'tool_result', 'reasoning', 'system'))
);

create index uc_ai_agent_msg_session_idx on uc_ai_agent_messages(session_id, seq);
create index uc_ai_agent_msg_exec_idx on uc_ai_agent_messages(execution_id);

comment on table uc_ai_agent_messages is 'Normalized, untrimmed per-message conversation log (one row per content item)';
comment on column uc_ai_agent_messages.seq is 'Ordering within the session; assigned as running max(seq)+1 per persisted message';
comment on column uc_ai_agent_messages.agent_code is 'Agent that produced this message (sub-agent for wrapper turns; the turn''s own agent otherwise); null for caller user/system input';


-- ============================================================================
-- AGENT MEMORY
-- ============================================================================
-- Persistent agent memory: a virtual filesystem of CLOB files rooted at
-- /memories, exposed to agents through the generic MEMORY function tool
-- (Anthropic memory-tool contract, working on every provider). A store is one
-- virtual filesystem; which store a run resolves to is driven by
-- uc_ai_memory_config + the ambient execution context (uc_ai.get_exec_context).
-- Directories are implicit from path prefixes (S3-key style) — no directory rows.

create sequence uc_ai_memory_stores_seq;

create table uc_ai_memory_stores (
  id          number default on null uc_ai_memory_stores_seq.nextval not null,
  store_key   varchar2(1000 char) not null,
  scope       varchar2(50 char)   not null,
  agent_code  varchar2(255 char),
  username    varchar2(255 char),
  session_id  varchar2(255 char),
  store_code  varchar2(255 char),
  context_key   varchar2(255 char),
  context_value varchar2(200 char),
  created_by  varchar2(255 char) default on null coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  created_at  timestamp          default on null systimestamp not null,
  updated_by  varchar2(255 char) default on null coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  updated_at  timestamp          default on null systimestamp not null,
  constraint uc_ai_memory_stores_pk primary key (id),
  constraint uc_ai_memory_stores_uk unique (store_key),
  constraint uc_ai_memory_stores_scope_ck check (scope in ('agent', 'user', 'session', 'shared', 'global', 'context'))
);

comment on table  uc_ai_memory_stores is 'One row = one virtual memory filesystem. Auto-provisioned on first use.';
comment on column uc_ai_memory_stores.store_key is 'Canonical resolution key: agent:CODE | user:CODE:USER | session:ID | shared:NAME | global | context:NAMESPACE:KEY:VALUE';
comment on column uc_ai_memory_stores.scope is 'agent | user | session | shared | global | context';
comment on column uc_ai_memory_stores.agent_code is 'Descriptive only (agent/user scopes); resolution goes through store_key';
comment on column uc_ai_memory_stores.username is 'Descriptive only (user scope: the created_by of the run)';
comment on column uc_ai_memory_stores.session_id is 'Descriptive only (session scope)';
comment on column uc_ai_memory_stores.store_code is 'Descriptive only (shared scope: the explicit store name; context scope: the namespace, when the agents share one)';
comment on column uc_ai_memory_stores.context_key is 'Descriptive only (context scope: the run-context key the store is scoped by, e.g. document_id)';
comment on column uc_ai_memory_stores.context_value is 'Descriptive only (context scope: the value of that key for this store, e.g. 7)';


create sequence uc_ai_memory_files_seq;

create table uc_ai_memory_files (
  id               number default on null uc_ai_memory_files_seq.nextval not null,
  store_id         number              not null,
  path             varchar2(1000 char) not null,
  content          clob                not null,
  last_accessed_at timestamp           default on null systimestamp not null,
  created_by  varchar2(255 char) default on null coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  created_at  timestamp          default on null systimestamp not null,
  updated_by  varchar2(255 char) default on null coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  updated_at  timestamp          default on null systimestamp not null,
  constraint uc_ai_memory_files_pk primary key (id),
  constraint uc_ai_memory_files_uk unique (store_id, path),
  constraint uc_ai_memory_files_store_fk foreign key (store_id)
    references uc_ai_memory_stores(id) on delete cascade,
  constraint uc_ai_memory_files_path_ck check (path like '/memories/%' and instr(path, '..') = 0)
);

comment on table  uc_ai_memory_files is 'Virtual memory files. Directories are implicit from path prefixes; there are no directory rows.';
comment on column uc_ai_memory_files.path is 'Normalized absolute path, always starting with /memories/';
comment on column uc_ai_memory_files.last_accessed_at is 'Touched (best-effort) on view; expire_files uses greatest(last_accessed_at, updated_at)';


create sequence uc_ai_memory_config_seq;

create table uc_ai_memory_config (
  id              number default on null uc_ai_memory_config_seq.nextval not null,
  agent_code      varchar2(255 char) not null,
  scope           varchar2(50 char)  default on null 'agent' not null,
  store_code      varchar2(255 char),
  context_key     varchar2(255 char),
  enabled         varchar2(1 char)   default on null 'Y' not null,
  max_file_chars  number             default on null 100000 not null,
  max_store_chars number,
  max_files       number             default on null 1000 not null,
  created_by  varchar2(255 char) default on null coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  created_at  timestamp          default on null systimestamp not null,
  updated_by  varchar2(255 char) default on null coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  updated_at  timestamp          default on null systimestamp not null,
  constraint uc_ai_memory_config_pk primary key (id),
  constraint uc_ai_memory_config_uk unique (agent_code),
  constraint uc_ai_memory_config_scope_ck  check (scope in ('agent', 'user', 'session', 'shared', 'global', 'context')),
  constraint uc_ai_memory_config_en_ck     check (enabled in ('Y', 'N')),
  constraint uc_ai_memory_config_shared_ck check (scope != 'shared' or store_code is not null),
  constraint uc_ai_memory_config_ctx_ck    check (scope != 'context' or context_key is not null)
);

comment on table  uc_ai_memory_config is 'Per-agent memory enablement + store scoping and size caps';
comment on column uc_ai_memory_config.scope is 'Which store the agent resolves to: agent (own store, default) | user (per agent+user) | session (per session) | shared (named store, see store_code) | global | context (per run-context value, see context_key)';
comment on column uc_ai_memory_config.store_code is 'Required for scope = shared: the named store several agents can share. Optional for scope = context: the namespace, so several agents share one store per context value (defaults to the agent code, which keeps the store private to the agent)';
comment on column uc_ai_memory_config.context_key is 'Required for scope = context: the run-context key that identifies the store, e.g. document_id';
comment on column uc_ai_memory_config.max_file_chars is 'Cap for a single file''s content length (enforced on create/insert/str_replace)';
comment on column uc_ai_memory_config.max_store_chars is 'Optional cap for the summed content length of the resolved store (null = unlimited)';
comment on column uc_ai_memory_config.max_files is 'Cap for the number of files in the resolved store';
