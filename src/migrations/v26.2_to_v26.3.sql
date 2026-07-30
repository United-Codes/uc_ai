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
  updated_at             timestamp
);

comment on column uc_ai_agent_executions.created_by is 'coalesce(real APEX user, DB user) at top-level execution start';
comment on column uc_ai_agent_executions.db_user is 'SYS_CONTEXT USERENV SESSION_USER';
comment on column uc_ai_agent_executions.apex_user is 'APEX APP_USER (null for uc_ai''s own synthetic session)';
comment on column uc_ai_agent_executions.audience is 'Caller class at execution start: public (anonymous APEX visitor) | authenticated (logged-in APEX user) | db (database/job session, or uc_ai''s own synthetic session)';
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

-- Per-APEX-session usage lookups pair an apex_session_id equality with a
-- started_at range, so both columns belong in one index. Without it, a governance
-- extension capping anonymous usage per browser session would full-scan this
-- table on every run — the worst place for it, since anonymous traffic is exactly
-- what is unbounded.
create index uc_ai_agent_exec_apex_sess_idx on uc_ai_agent_executions(apex_session_id, started_at);


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


-- ============================================================================
-- CONVERSATION SESSIONS: header table + normalized message log
-- ============================================================================
-- Turns of a conversation used to be readable only as separate execution rows
-- sharing a session_id. This adds a conversation header (one row per session)
-- with maintained aggregates, and a normalized, untrimmed per-message log.
-- Each execution now records only the OWN tokens of the LLM calls it made; the
-- session total is the SUM across the session (no parent/child double count).

alter table uc_ai_agent_executions add (turn_index number);
comment on column uc_ai_agent_executions.turn_index is 'Sequential turn number within the session (top-level executions only; null for nested sub-agent runs)';


create table uc_ai_agent_sessions (
  session_id             varchar2(255 char) not null,
  root_agent_id          number,

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

  constraint uc_ai_agent_sessions_pk primary key (session_id),
  constraint uc_ai_agent_sess_agent_fk foreign key (root_agent_id)
    references uc_ai_agents(id),
  constraint uc_ai_agent_sess_status_ck check (status in
    ('pending', 'running', 'completed', 'failed', 'timeout'))
);

create index uc_ai_agent_sess_activity_idx on uc_ai_agent_sessions(last_activity_at);
create index uc_ai_agent_sess_agent_idx on uc_ai_agent_sessions(root_agent_id);

comment on table uc_ai_agent_sessions is 'Conversation header: one row per session_id grouping all executions (turns + nested sub-agent runs)';
comment on column uc_ai_agent_sessions.audience is 'Caller class of the opening turn: public | authenticated | db';


create sequence uc_ai_agent_messages_seq;

create table uc_ai_agent_messages (
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
comment on column uc_ai_agent_messages.agent_code is 'Agent that produced this message (sub-agent for wrapper turns; the turn''s own agent otherwise); null for caller user/system input';


create or replace trigger uc_ai_agent_sessions_biu
    before insert or update on uc_ai_agent_sessions
    for each row
begin
    if inserting
    then
        if :new.started_at is null
        then
            :new.started_at := systimestamp;
        end if;

        if :new.created_by is null
        then
            :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
        end if;
    end if;

    :new.updated_at := systimestamp;
end uc_ai_agent_sessions_biu;
/

create or replace trigger uc_ai_agent_messages_bi
    before insert on uc_ai_agent_messages
    for each row
begin
    if :new.created_at is null
    then
        :new.created_at := systimestamp;
    end if;
end uc_ai_agent_messages_bi;
/


-- ============================================================================
-- BACKFILL (best-effort; existing data is not critical)
-- ============================================================================

-- 1) Own-token normalization. Workflow/handoff/conversation parents historically
--    stored SUM(children); zero them so the new session SUM does not double count.
--    (Profile/orchestrator rows already held only their own generate_text tokens.)
update uc_ai_agent_executions e
   set e.total_input_tokens = 0,
       e.total_output_tokens = 0
 where e.agent_id in (
   select id from uc_ai_agents
    where agent_type in ('workflow', 'handoff', 'conversation')
 );

-- 2) Number the historical turns (top-level executions) within each session.
merge into uc_ai_agent_executions tgt
using (
  select id,
         row_number() over (partition by session_id order by started_at, id) as rn
    from uc_ai_agent_executions
   where parent_execution_id is null
     and session_id is not null
) src
on (tgt.id = src.id)
when matched then update set tgt.turn_index = src.rn;

-- 3) Build the conversation headers from the existing executions.
insert into uc_ai_agent_sessions (
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
  left join last_turn lt on lt.session_id = ag.session_id;

-- 4) Reconstruct the message log. Per session we take the latest completed
--    top-level execution, whose output_result already holds the full
--    (accumulated) conversation, and store its messages once.
declare
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
    insert into uc_ai_agent_messages (
      session_id, execution_id, seq, role, content,
      tool_name, tool_input, tool_output, tool_status
    ) values (
      p_session_id, p_exec_id, p_seq, p_role, p_content,
      p_tool_name, p_tool_input, p_tool_output, p_tool_status
    );
  end ins;
begin
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
          end loop;
        end loop;
      elsif l_result.has('final_message') then
        l_seq := l_seq + 1;
        ins(s.session_id, s.exec_id, l_seq, 'assistant', l_result.get_clob('final_message'));
      end if;
    exception
      when others then
        -- best-effort: skip sessions whose output_result cannot be parsed
        null;
    end;
  end loop;

  -- refresh the maintained message_count on the headers
  update uc_ai_agent_sessions ss
     set ss.message_count = (
       select count(*) from uc_ai_agent_messages m where m.session_id = ss.session_id
     );

  commit;
end;
/


-- ============================================================================
-- TOOLS: programmatic tool calling ("code mode") per-tool availability
-- ============================================================================
-- Controls whether a tool is offered as a normal (direct) tool, only inside a
-- code-mode program (callTool), or both. Existing tools default to 'both' so
-- behaviour is unchanged.

alter table uc_ai_tools add (
  code_mode_access varchar2(10 char) default on null 'both' not null
);

alter table uc_ai_tools add constraint uc_ai_tools_cma_ck
  check (code_mode_access in ('direct','code','both'));
