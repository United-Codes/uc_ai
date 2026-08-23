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


-- ============================================================================
-- AGENT MEMORY
-- ============================================================================
-- New feature, so these objects are created, not altered. The MEMORY function
-- tool row and the uc_ai_v_memory_files view are created by
-- upgrade_packages.sql, which you run after this script.

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


-- ---- triggers --------------------------------------------------------------
-- uc_ai_memory already sets updated_by/updated_at on its own write paths, using
-- the identical expression (see current_user_id); these triggers are the backstop
-- for a hand-edited row, the same as the triggers core keeps on the other tables
-- its API writes.
--
-- uc_ai_memory_files is DELIBERATELY EXCLUDED. It has a touch-only read path that
-- sets last_accessed_at WITHOUT updated_at, so that "last modified" and "last
-- read" stay distinct (expire_files relies on both via
-- greatest(last_accessed_at, updated_at)). A before-update trigger would bump
-- updated_at on every file read and collapse that distinction, turning
-- "last modified" into "last accessed". Its write paths already maintain the
-- audit columns themselves.

create or replace trigger uc_ai_memory_stores_biu
    before insert or update on uc_ai_memory_stores
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_memory_stores_biu;
/

create or replace trigger uc_ai_memory_config_biu
    before insert or update on uc_ai_memory_config
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_memory_config_biu;
/
