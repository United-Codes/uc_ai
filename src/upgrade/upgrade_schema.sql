-- ============================================================================
-- UC AI schema upgrade (v25.7 and later)
-- ============================================================================
-- Brings the tables, sequences, constraints and indexes of an existing UC AI
-- schema to the shape of src/tables/install.sql. Every step checks the data
-- dictionary first, so the script is safe to run more than once, on any version
-- from v25.7 on, and on a schema that holds a half-applied older migration.
--
-- Rules for this file:
--  * A DDL change goes into src/tables/install.sql AND into a guarded step here.
--  * Add one column per call. One "alter table ... add (a, b)" fails as a whole
--    when only one of the columns is missing.
--  * Every statement that touches an object this script can create or change
--    (backfills too) runs through execute immediate. The block is compiled
--    before the first step runs, so a static reference to a table or column
--    that does not exist yet fails the whole script.
--  * A one-time data change must run only when its structural change ran in the
--    same run: guard it with "if g_changed then".
--  * Comments, triggers, views and packages are not handled here. The generated
--    upgrade script appends them.

-- @dblinter ignore(G-5010): an installer script runs before uc_ai_logger exists and reports to the person running it
-- @dblinter ignore(G-6010): the dynamic statements are literals on purpose; the block is compiled before the first step runs, so a static reference to a table that is not there yet would fail it
-- @dblinter ignore(G-7130): the helpers share the step name, the change counter and the changed flag of this one-off block
-- @dblinter ignore(G-9501): every DDL string comes from a literal in this file, never from input
declare
  g_step    varchar2(200 char);
  g_changes pls_integer := 0;
  -- true when the latest ensure_* call changed the schema
  g_changed boolean := false;

  procedure say(p_text in varchar2) is
  begin
    sys.dbms_output.put_line(p_text);
  end say;

  procedure step(p_name in varchar2) is
  begin
    g_step := p_name;
    say(p_name);
  end step;

  procedure run_ddl(p_ddl in varchar2, p_message in varchar2) is
  begin
    execute immediate p_ddl;
    g_changes := g_changes + 1;
    g_changed := true;
    say('  ' || p_message);
  end run_ddl;

  function object_exists(p_type in varchar2, p_name in varchar2) return boolean is
    l_found pls_integer;
  begin
    select case when exists (
             select 1
               from user_objects
              where object_type = p_type
                and object_name = upper(p_name)
           ) then 1 else 0 end
      into l_found
      from dual;

    return l_found = 1;
  end object_exists;

  function column_exists(p_table in varchar2, p_column in varchar2) return boolean is
    l_found pls_integer;
  begin
    select case when exists (
             select 1
               from user_tab_columns
              where table_name  = upper(p_table)
                and column_name = upper(p_column)
           ) then 1 else 0 end
      into l_found
      from dual;

    return l_found = 1;
  end column_exists;

  function constraint_exists(p_name in varchar2) return boolean is
    l_found pls_integer;
  begin
    select case when exists (
             select 1
               from user_constraints
              where constraint_name = upper(p_name)
           ) then 1 else 0 end
      into l_found
      from dual;

    return l_found = 1;
  end constraint_exists;

  procedure ensure_sequence(p_name in varchar2) is
  begin
    g_changed := false;
    if not object_exists('SEQUENCE', p_name) then
      run_ddl('create sequence ' || p_name, 'created sequence ' || p_name);
    end if;
  end ensure_sequence;

  procedure ensure_table(p_name in varchar2, p_ddl in varchar2) is
  begin
    g_changed := false;
    if not object_exists('TABLE', p_name) then
      run_ddl(p_ddl, 'created table ' || p_name);
    end if;
  end ensure_table;

  procedure ensure_column(p_table in varchar2, p_column in varchar2, p_definition in varchar2) is
  begin
    g_changed := false;
    if not column_exists(p_table, p_column) then
      run_ddl(
        'alter table ' || p_table || ' add (' || p_column || ' ' || p_definition || ')',
        'added column ' || p_table || '.' || p_column
      );
    end if;
  end ensure_column;

  -- p_definition is everything after the constraint name, e.g. "check (...)"
  procedure ensure_constraint(p_table in varchar2, p_name in varchar2, p_definition in varchar2) is
  begin
    g_changed := false;
    if not constraint_exists(p_name) then
      run_ddl(
        'alter table ' || p_table || ' add constraint ' || p_name || ' ' || p_definition,
        'added constraint ' || p_name
      );
    end if;
  end ensure_constraint;

  -- A check constraint whose condition changed between releases. The existing
  -- constraint is replaced unless its condition already contains p_marker.
  procedure ensure_check(
    p_table      in varchar2,
    p_name       in varchar2,
    p_marker     in varchar2,
    p_definition in varchar2
  ) is
    l_found pls_integer;
  begin
    g_changed := false;

    select case when exists (
             select 1
               from user_constraints
              where constraint_name = upper(p_name)
                and instr(lower(search_condition_vc), lower(p_marker)) > 0
           ) then 1 else 0 end
      into l_found
      from dual;

    if l_found = 0 then
      if constraint_exists(p_name) then
        run_ddl(
          'alter table ' || p_table || ' drop constraint ' || p_name,
          'dropped outdated constraint ' || p_name
        );
      end if;

      run_ddl(
        'alter table ' || p_table || ' add constraint ' || p_name || ' ' || p_definition,
        'added constraint ' || p_name
      );
    end if;
  end ensure_check;

  procedure ensure_index(p_name in varchar2, p_ddl in varchar2) is
  begin
    g_changed := false;
    if not object_exists('INDEX', p_name) then
      run_ddl(p_ddl, 'created index ' || p_name);
    end if;
  end ensure_index;

  procedure drop_trigger_if_exists(p_name in varchar2) is
  begin
    g_changed := false;
    if object_exists('TRIGGER', p_name) then
      run_ddl('drop trigger ' || p_name, 'dropped trigger ' || p_name);
    end if;
  end drop_trigger_if_exists;

  procedure assert_installed is
  begin
    if not object_exists('TABLE', 'UC_AI_TOOLS') then
      raise_application_error(
        -20000,
        'UC AI is not installed in this schema. Run install_uc_ai_complete.sql instead.'
      );
    end if;

    if not object_exists('TABLE', 'UC_AI_TOOL_TAGS') then
      raise_application_error(
        -20000,
        'This schema is older than UC AI v25.7. Upgrade it to v25.7 first.'
      );
    end if;
  end assert_installed;

  -- ==========================================================================
  -- v26.1: prompt profiles, agents and agent executions
  -- ==========================================================================
  -- Tables that did not exist in v25.7 are created in their current shape, so
  -- the column and constraint steps of later releases find nothing to do.

  procedure release_v26_1 is
  begin
    step('v26.1: prompt profiles and agents');

    ensure_sequence('uc_ai_prompt_profiles_seq');
    ensure_table('uc_ai_prompt_profiles', q'[create table uc_ai_prompt_profiles (
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
)]');

    ensure_sequence('uc_ai_agents_seq');
    ensure_table('uc_ai_agents', q'[create table uc_ai_agents (
  id                     number default on null uc_ai_agents_seq.nextval not null,
  code                   varchar2(255 char) not null,
  version                number default on null 1 not null,
  status                 varchar2(50 char) default on null 'draft' not null,
  description            varchar2(4000 char) not null,
  agent_type             varchar2(50 char) not null,

  prompt_profile_code    varchar2(255 char),
  prompt_profile_version number,

  workflow_definition    clob,

  orchestration_config   clob,

  decision_config        clob,

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
    ('profile', 'workflow', 'orchestrator', 'handoff', 'conversation', 'decision')),
  constraint uc_ai_agents_profile_ck check (
    agent_type <> 'profile' or prompt_profile_code is not null),
  constraint uc_ai_agents_workflow_ck check (
    agent_type <> 'workflow' or workflow_definition is not null),
  constraint uc_ai_agents_orch_ck check (
    agent_type not in ('orchestrator', 'handoff', 'conversation')
    or orchestration_config is not null),
  constraint uc_ai_agents_decision_ck check (
    agent_type <> 'decision' or decision_config is not null)
)]');

    ensure_index('uc_ai_agents_active_uk', q'[create unique index uc_ai_agents_active_uk on uc_ai_agents(
  case when status = 'active' then code else null end
)]');
    ensure_index('uc_ai_agents_code_idx', 'create index uc_ai_agents_code_idx on uc_ai_agents(code, version, status)');

    ensure_sequence('uc_ai_agent_executions_seq');
    ensure_table('uc_ai_agent_executions', q'[create table uc_ai_agent_executions (
  id                     number default on null uc_ai_agent_executions_seq.nextval not null,
  agent_id               number not null,
  parent_execution_id    number,
  session_id             varchar2(255 char),
  turn_index             number,

  input_parameters       clob,
  current_state          clob,
  output_result          clob,

  status                 varchar2(50 char) not null,
  iteration_count        number default on null 0 not null,
  tool_calls_count       number default on null 0 not null,

  total_input_tokens     number default on null 0 not null,
  total_output_tokens    number default on null 0 not null,

  started_at             timestamp not null,
  completed_at           timestamp,
  updated_at             timestamp,
  error_message          varchar2(4000 char),

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

  run_context            clob,

  constraint uc_ai_agent_executions_pk primary key (id),
  constraint uc_ai_agent_exec_agent_fk foreign key (agent_id)
    references uc_ai_agents(id),
  constraint uc_ai_agent_exec_parent_fk foreign key (parent_execution_id)
    references uc_ai_agent_executions(id),
  constraint uc_ai_agent_exec_status_ck check (status in
    ('pending', 'running', 'completed', 'failed', 'timeout')),
  constraint uc_ai_agent_exec_done_ck check (
    status not in ('completed', 'failed', 'timeout') or completed_at is not null)
)]');

    ensure_index('uc_ai_agent_exec_session_idx', 'create index uc_ai_agent_exec_session_idx on uc_ai_agent_executions(session_id)');
    ensure_index('uc_ai_agent_exec_status_idx', 'create index uc_ai_agent_exec_status_idx on uc_ai_agent_executions(status, started_at)');
    ensure_index('uc_ai_agent_exec_agent_idx', 'create index uc_ai_agent_exec_agent_idx on uc_ai_agent_executions(agent_id)');
  end release_v26_1;

  -- ==========================================================================
  -- v26.3: execution context, sessions, message log, code mode, agent memory
  -- ==========================================================================

  procedure release_v26_3 is
    l_sessions_created boolean;
  begin
    step('v26.3: agent execution columns');

    ensure_column('uc_ai_agent_executions', 'turn_index', 'number');
    ensure_column('uc_ai_agent_executions', 'created_by', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'db_user', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'apex_user', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'audience', 'varchar2(20 char)');
    ensure_column('uc_ai_agent_executions', 'apex_session_id', 'number');
    ensure_column('uc_ai_agent_executions', 'apex_app_id', 'number');
    ensure_column('uc_ai_agent_executions', 'apex_page_id', 'number');
    ensure_column('uc_ai_agent_executions', 'os_user', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'host', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'ip_address', 'varchar2(64 char)');
    ensure_column('uc_ai_agent_executions', 'module', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'action', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'client_identifier', 'varchar2(255 char)');
    ensure_column('uc_ai_agent_executions', 'sid', 'number');
    ensure_column('uc_ai_agent_executions', 'env_context', 'clob');
    ensure_column('uc_ai_agent_executions', 'run_context', 'clob');

    ensure_column('uc_ai_agent_executions', 'updated_at', 'timestamp');
    if g_changed then
      -- existing rows get a sensible last-modified value
      execute immediate q'[update uc_ai_agent_executions
   set updated_at = coalesce(completed_at, started_at)
 where updated_at is null]';
      commit;
    end if;

    -- The insert-only trigger of v26.1 is replaced by uc_ai_agent_executions_biu
    -- (created by the trigger script that follows this block).
    drop_trigger_if_exists('uc_ai_agent_executions_bi');

    step('v26.3: agent type checks');

    -- Pre-existing rows were written through the API, which already enforces
    -- these checks, so they are created ENABLE NOVALIDATE.
    ensure_constraint('uc_ai_agents', 'uc_ai_agents_profile_ck', q'[check (
  agent_type <> 'profile' or prompt_profile_code is not null) enable novalidate]');
    ensure_constraint('uc_ai_agents', 'uc_ai_agents_workflow_ck', q'[check (
  agent_type <> 'workflow' or workflow_definition is not null) enable novalidate]');
    ensure_constraint('uc_ai_agents', 'uc_ai_agents_orch_ck', q'[check (
  agent_type not in ('orchestrator', 'handoff', 'conversation')
  or orchestration_config is not null) enable novalidate]');
    ensure_constraint('uc_ai_agent_executions', 'uc_ai_agent_exec_done_ck', q'[check (
  status not in ('completed', 'failed', 'timeout') or completed_at is not null)
  enable novalidate]');

    ensure_index('uc_ai_agent_exec_parent_idx', 'create index uc_ai_agent_exec_parent_idx on uc_ai_agent_executions(parent_execution_id)');
    ensure_index('uc_ai_agent_exec_apex_sess_idx', 'create index uc_ai_agent_exec_apex_sess_idx on uc_ai_agent_executions(apex_session_id, started_at)');

    step('v26.3: conversation sessions and message log');

    ensure_table('uc_ai_agent_sessions', q'[create table uc_ai_agent_sessions (
  session_id             varchar2(255 char) not null,
  root_agent_id          number,
  title                  varchar2(200 char),

  feedback_rating        varchar2(10 char),
  feedback_comment       varchar2(2000 char),
  feedback_at            timestamp,

  status                 varchar2(50 char),
  turn_count             number default on null 0 not null,
  message_count          number default on null 0 not null,

  total_input_tokens     number default on null 0 not null,
  total_output_tokens    number default on null 0 not null,

  started_at             timestamp,
  last_activity_at       timestamp,
  updated_at             timestamp,

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

  run_context            clob,

  constraint uc_ai_agent_sessions_pk primary key (session_id),
  constraint uc_ai_agent_sess_agent_fk foreign key (root_agent_id)
    references uc_ai_agents(id),
  constraint uc_ai_agent_sess_status_ck check (status in
    ('pending', 'running', 'completed', 'failed', 'timeout')),
  constraint uc_ai_agent_sess_fb_ck check (feedback_rating in ('up', 'down'))
)]');
    l_sessions_created := g_changed;

    -- An early v26.3 schema has the table without the feedback and run context
    -- columns.
    ensure_column('uc_ai_agent_sessions', 'feedback_rating', 'varchar2(10 char)');
    ensure_column('uc_ai_agent_sessions', 'feedback_comment', 'varchar2(2000 char)');
    ensure_column('uc_ai_agent_sessions', 'feedback_at', 'timestamp');
    ensure_column('uc_ai_agent_sessions', 'run_context', 'clob');
    ensure_column('uc_ai_agent_sessions', 'audience', 'varchar2(20 char)');
    ensure_constraint('uc_ai_agent_sessions', 'uc_ai_agent_sess_fb_ck', q'[check (feedback_rating in ('up', 'down'))]');

    ensure_index('uc_ai_agent_sess_activity_idx', 'create index uc_ai_agent_sess_activity_idx on uc_ai_agent_sessions(last_activity_at)');
    ensure_index('uc_ai_agent_sess_agent_idx', 'create index uc_ai_agent_sess_agent_idx on uc_ai_agent_sessions(root_agent_id)');
    ensure_index('uc_ai_agent_sess_user_idx', 'create index uc_ai_agent_sess_user_idx on uc_ai_agent_sessions(created_by, last_activity_at)');

    ensure_sequence('uc_ai_agent_messages_seq');
    ensure_table('uc_ai_agent_messages', q'[create table uc_ai_agent_messages (
  id                     number default on null uc_ai_agent_messages_seq.nextval not null,
  session_id             varchar2(255 char) not null,
  execution_id           number not null,

  seq                    number not null,

  role                   varchar2(50 char) not null,
  content                clob,

  agent_code             varchar2(255 char),

  tool_name              varchar2(255 char),
  tool_input             clob,
  tool_output            clob,
  tool_status            varchar2(50 char),

  tool_call_id           varchar2(255 char),

  created_at             timestamp not null,

  constraint uc_ai_agent_messages_pk primary key (id),
  constraint uc_ai_agent_msg_session_fk foreign key (session_id)
    references uc_ai_agent_sessions(session_id),
  constraint uc_ai_agent_msg_exec_fk foreign key (execution_id)
    references uc_ai_agent_executions(id),
  constraint uc_ai_agent_msg_role_ck check (role in
    ('user', 'assistant', 'tool_call', 'tool_result', 'reasoning', 'system'))
)]');

    ensure_index('uc_ai_agent_msg_session_idx', 'create index uc_ai_agent_msg_session_idx on uc_ai_agent_messages(session_id, seq)');
    ensure_index('uc_ai_agent_msg_exec_idx', 'create index uc_ai_agent_msg_exec_idx on uc_ai_agent_messages(execution_id)');

    -- Backfill (best effort, the history is not critical). It runs only when
    -- this run created the sessions table: it zeroes token totals, so a second
    -- run must never repeat it.
    if l_sessions_created then
      step('v26.3: backfill sessions from existing executions');

      -- 1) Own-token normalization. Workflow, handoff and conversation parents
      --    stored the sum of their children; zero them so the session sum does
      --    not count the same tokens twice.
      execute immediate q'[update uc_ai_agent_executions e
   set e.total_input_tokens = 0,
       e.total_output_tokens = 0
 where e.agent_id in (
   select a.id from uc_ai_agents a
    where a.agent_type in ('workflow', 'handoff', 'conversation')
 )]';

      -- 2) Number the historical turns (top-level executions) of each session.
      execute immediate q'[merge into uc_ai_agent_executions tgt
using (
  select id,
         row_number() over (partition by session_id order by started_at, id) as rn
    from uc_ai_agent_executions
   where parent_execution_id is null
     and session_id is not null
) src
on (tgt.id = src.id)
when matched then update set tgt.turn_index = src.rn]';

      -- 3) Build the conversation headers from the existing executions.
      execute immediate q'[insert into uc_ai_agent_sessions (
  session_id, root_agent_id, status, turn_count, message_count,
  total_input_tokens, total_output_tokens, started_at, last_activity_at,
  created_by, db_user, apex_user, apex_session_id, apex_app_id, apex_page_id,
  os_user, host, ip_address, module, action, client_identifier, sid, env_context
)
with agg as (
  select session_id,
         min(started_at) as started_at,
         max(coalesce(completed_at, updated_at, started_at)) as last_activity_at,
         sum(total_input_tokens) as tin,
         sum(total_output_tokens) as tout,
         count(case when turn_index is not null then 1 end) as turn_count
    from uc_ai_agent_executions
   where session_id is not null
   group by session_id
),
first_turn as (
  select * from (
    select e.session_id, e.agent_id, e.status, e.created_by, e.db_user, e.apex_user,
           e.apex_session_id, e.apex_app_id, e.apex_page_id, e.os_user, e.host,
           e.ip_address, e.module, e.action, e.client_identifier, e.sid, e.env_context,
           row_number() over (partition by e.session_id
                              order by e.turn_index nulls last, e.started_at, e.id) as rn
      from uc_ai_agent_executions e
     where e.session_id is not null
  ) where rn = 1
),
last_turn as (
  select session_id, status from (
    select session_id, status,
           row_number() over (partition by session_id
                              order by turn_index desc nulls last, started_at desc, id desc) as rn
      from uc_ai_agent_executions
     where session_id is not null
       and turn_index is not null
  ) where rn = 1
)
select ag.session_id, ft.agent_id, coalesce(lt.status, ft.status), ag.turn_count, 0,
       ag.tin, ag.tout, ag.started_at, ag.last_activity_at,
       ft.created_by, ft.db_user, ft.apex_user, ft.apex_session_id, ft.apex_app_id,
       ft.apex_page_id, ft.os_user, ft.host, ft.ip_address, ft.module, ft.action,
       ft.client_identifier, ft.sid, ft.env_context
  from agg ag
  join first_turn ft on ft.session_id = ag.session_id
  left join last_turn lt on lt.session_id = ag.session_id]';

      -- 4) Reconstruct the message log. Per session the latest completed
      --    top-level execution holds the full conversation in output_result.
      execute immediate q'[declare
  l_seq      number;
  l_result   json_object_t;
  l_messages json_array_t;
  l_msg      json_object_t;
  l_content  json_element_t;
  l_arr      json_array_t;
  l_item     json_object_t;
  l_role     varchar2(50 char);
  l_type     varchar2(50 char);
  l_output   clob;

  procedure ins(
    p_session_id in varchar2, p_exec_id in number, p_seq in number,
    p_role in varchar2, p_content in clob default null,
    p_tool_name in varchar2 default null, p_tool_input in clob default null,
    p_tool_output in clob default null, p_tool_status in varchar2 default null
  ) is
  begin
    -- created_at is set here: the trigger that normally sets it does not exist
    -- yet, because the trigger script runs after this block.
    insert into uc_ai_agent_messages (
      session_id, execution_id, seq, role, content,
      tool_name, tool_input, tool_output, tool_status, created_at
    ) values (
      p_session_id, p_exec_id, p_seq, p_role, p_content,
      p_tool_name, p_tool_input, p_tool_output, p_tool_status, systimestamp
    );
  end ins;
begin
  <<sessions_loop>>
  for s in (
    select session_id, id as exec_id, output_result from (
      select session_id, id, output_result,
             row_number() over (partition by session_id
                                order by completed_at desc nulls last, id desc) as rn
        from uc_ai_agent_executions
       where session_id is not null
         and parent_execution_id is null
         and output_result is not null
    ) where rn = 1
  ) loop
    begin
      l_seq := 0;
      l_output := s.output_result;
      l_result := json_object_t.parse(l_output);

      if l_result.has('messages') then
        l_messages := l_result.get_array('messages');
        <<messages_loop>>
        for i in 0 .. l_messages.get_size - 1 loop
          l_msg := treat(l_messages.get(i) as json_object_t);
          l_role := l_msg.get_string('role');
          if not l_msg.has('content') then
            continue;
          end if;
          l_content := l_msg.get('content');
          if not l_content.is_array then
            l_seq := l_seq + 1;
            ins(s.session_id, s.exec_id, l_seq, l_role, l_msg.get_clob('content'));
            continue;
          end if;
          l_arr := treat(l_content as json_array_t);
          <<content_items_loop>>
          for j in 0 .. l_arr.get_size - 1 loop
            l_item := treat(l_arr.get(j) as json_object_t);
            l_type := l_item.get_string('type');
            case l_type
              when 'text' then
                l_seq := l_seq + 1;
                ins(s.session_id, s.exec_id, l_seq, l_role, l_item.get_clob('text'));
              when 'reasoning' then
                l_seq := l_seq + 1;
                ins(s.session_id, s.exec_id, l_seq, 'reasoning', l_item.get_clob('text'));
              when 'tool_call' then
                l_seq := l_seq + 1;
                ins(s.session_id, s.exec_id, l_seq, 'tool_call',
                    p_tool_name => l_item.get_string('toolName'),
                    p_tool_input => l_item.get_clob('args'));
              when 'tool_result' then
                l_seq := l_seq + 1;
                ins(s.session_id, s.exec_id, l_seq, 'tool_result',
                    p_tool_name => l_item.get_string('toolName'),
                    p_tool_output => l_item.get_clob('result'),
                    p_tool_status => 'success');
              else
                null;
            end case;
          end loop content_items_loop;
        end loop messages_loop;
      elsif l_result.has('final_message') then
        l_seq := l_seq + 1;
        ins(s.session_id, s.exec_id, l_seq, 'assistant', l_result.get_clob('final_message'));
      end if;
    exception
      when others then
        null;
    end;
  end loop sessions_loop;
end;]';

      -- refresh the maintained message_count on the headers
      execute immediate q'[update uc_ai_agent_sessions ss
   set ss.message_count = (
     select count(*) from uc_ai_agent_messages m where m.session_id = ss.session_id
   )]';

      commit;
    end if;

    step('v26.3: code mode access on tools');

    ensure_column('uc_ai_tools', 'code_mode_access', q'[varchar2(10 char) default on null 'both' not null]');
    ensure_constraint('uc_ai_tools', 'uc_ai_tools_cma_ck', q'[check (code_mode_access in ('direct','code','both'))]');

    step('v26.3: agent memory');

    ensure_sequence('uc_ai_memory_stores_seq');
    ensure_table('uc_ai_memory_stores', q'[create table uc_ai_memory_stores (
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
)]');
    ensure_column('uc_ai_memory_stores', 'context_key', 'varchar2(255 char)');
    ensure_column('uc_ai_memory_stores', 'context_value', 'varchar2(200 char)');
    ensure_check('uc_ai_memory_stores', 'uc_ai_memory_stores_scope_ck', '''context''',
      q'[check (scope in ('agent', 'user', 'session', 'shared', 'global', 'context'))]');

    ensure_sequence('uc_ai_memory_files_seq');
    ensure_table('uc_ai_memory_files', q'[create table uc_ai_memory_files (
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
)]');

    ensure_sequence('uc_ai_memory_config_seq');
    ensure_table('uc_ai_memory_config', q'[create table uc_ai_memory_config (
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
)]');
    ensure_column('uc_ai_memory_config', 'context_key', 'varchar2(255 char)');
    ensure_check('uc_ai_memory_config', 'uc_ai_memory_config_scope_ck', '''context''',
      q'[check (scope in ('agent', 'user', 'session', 'shared', 'global', 'context'))]');
    ensure_constraint('uc_ai_memory_config', 'uc_ai_memory_config_ctx_ck',
      q'[check (scope != 'context' or context_key is not null)]');
  end release_v26_3;

  -- ==========================================================================
  -- v26.5: tool call ids on messages, the decision agent type
  -- ==========================================================================

  procedure release_v26_5 is
  begin
    step('v26.5: tool call id on agent messages');

    ensure_column('uc_ai_agent_messages', 'tool_call_id', 'varchar2(255 char)');

    step('v26.5: decision agents');

    ensure_column('uc_ai_agents', 'decision_config', 'clob');
    ensure_check('uc_ai_agents', 'uc_ai_agents_type_ck', '''decision''', q'[check (agent_type in
      ('profile', 'workflow', 'orchestrator', 'handoff', 'conversation', 'decision'))]');
    -- No existing row can have the type 'decision'.
    ensure_constraint('uc_ai_agents', 'uc_ai_agents_decision_ck', q'[check (
      agent_type <> 'decision' or decision_config is not null) enable novalidate]');
  end release_v26_5;
begin
  say('Upgrading the UC AI schema objects...');
  execute immediate 'alter session set ddl_lock_timeout = 30';

  step('Checking the installed version');
  assert_installed;

  release_v26_1;
  release_v26_3;
  release_v26_5;

  if g_changes = 0 then
    say('The schema is up to date. Nothing to change.');
  else
    say(g_changes || ' schema change(s) applied.');
  end if;
exception
  when others then
    say('UPGRADE STOPPED at step: ' || g_step);
    say(sqlerrm);
    say(sys.dbms_utility.format_error_backtrace);
    raise;
end;
/
