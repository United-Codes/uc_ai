-- ============================================================================
-- UC AI tutorial — "Give an Agent a Memory"
-- Remove everything this course created
-- ============================================================================
-- Deletes the memory of MX_DESK with its files, the agent and its execution
-- history, the prompt profile, the two tools, the handler package, and the four
-- demo tables.
--
-- Leaves UC AI itself, your API keys, and everything outside this course alone.
-- Safe to run at any point, including before the course is finished.
--
-- The ORDER matters. disable_for_agent needs the agent to still exist, so the
-- memory goes before the agent.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

prompt
prompt === Teardown: Give an Agent a Memory ===============================
prompt

-- ---------------------------------------------------------------------------
-- 1. The memory, with its files
-- ---------------------------------------------------------------------------
-- p_drop_store also removes the per-asset stores, because this agent owns their
-- namespace: no p_store_code was ever named, so every store key starts with
-- "context:MX_DESK:". ORA-20424 means memory was never enabled here.
declare
  e_no_config exception;
  pragma exception_init(e_no_config, -20424);
  l_files pls_integer;
begin
  select count(*) into l_files
    from uc_ai_v_memory_files
   where agent_code = 'MX_DESK';

  uc_ai_memory.disable_for_agent(
    p_agent_code => 'MX_DESK'
  , p_drop_store => true
  );
  commit;
  sys.dbms_output.put_line('1. Memory removed, with ' || l_files || ' file(s).');
exception
  when e_no_config then
    sys.dbms_output.put_line('1. MX_DESK had no memory. Nothing to remove.');
end;
/

-- ---------------------------------------------------------------------------
-- 2. The agent, with its execution history
-- ---------------------------------------------------------------------------
-- An agent that has run cannot be deleted, because its execution history points
-- at it. purge_agent removes the history with it.
declare
  l_exists pls_integer;
begin
  select count(*) into l_exists
    from uc_ai_agents
   where code = 'MX_DESK' and rownum = 1;

  if l_exists = 1 then
    uc_ai_agents_api.purge_agent(p_code => 'MX_DESK');
    commit;
    sys.dbms_output.put_line('2. Agent MX_DESK purged, with its runs.');
  else
    sys.dbms_output.put_line('2. No agent MX_DESK.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 3. The prompt profile
-- ---------------------------------------------------------------------------
declare
  l_count pls_integer := 0;
begin
  <<profile_versions>>
  for r in (
    select version
      from uc_ai_prompt_profiles
     where code = 'MX_DESK_PROFILE'
     order by version
  )
  loop
    uc_ai_prompt_profiles_api.delete_prompt_profile(
      p_code => 'MX_DESK_PROFILE', p_version => r.version);
    l_count := l_count + 1;
  end loop profile_versions;
  commit;
  sys.dbms_output.put_line('3. Prompt profile versions deleted: ' || l_count || '.');
end;
/

-- ---------------------------------------------------------------------------
-- 4. The two tools
-- ---------------------------------------------------------------------------
-- The MEMORY tool row belongs to UC AI, not to this course. It stays.
declare
  l_count pls_integer;
begin
  delete from uc_ai_tools
   where code in ('MX_GET_ASSET', 'MX_LIST_WORK_ORDERS');
  l_count := sql%rowcount;
  commit;
  sys.dbms_output.put_line('4. Tools deleted: ' || l_count || '.');
end;
/

-- ---------------------------------------------------------------------------
-- 5. The handler package and the tables
-- ---------------------------------------------------------------------------
declare
  procedure drop_object(p_name in varchar2, p_type in varchar2)
  as
    l_exists pls_integer;
    l_sql    varchar2(200 char);
  begin
    select count(*) into l_exists
      from user_objects
     where object_name = p_name
       and object_type = p_type
       and rownum = 1;

    if l_exists = 1 then
      if p_type = 'PACKAGE' then
        l_sql := 'drop package ' || sys.dbms_assert.simple_sql_name(p_name);
      else
        l_sql := 'drop table ' || sys.dbms_assert.simple_sql_name(p_name)
              || ' cascade constraints purge';
      end if;
      execute immediate l_sql;
      sys.dbms_output.put_line('   dropped ' || p_type || ' ' || p_name);
    end if;
  end drop_object;
begin
  sys.dbms_output.put_line('5. Package and tables:');
  drop_object('MX_DESK_PKG', 'PACKAGE');
  drop_object('MX_WORK_ORDERS', 'TABLE');
  drop_object('MX_ALARMS', 'TABLE');
  drop_object('MX_TECHNICIANS', 'TABLE');
  drop_object('MX_ASSETS', 'TABLE');
end;
/

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
declare
  l_tables pls_integer;
  l_tools  pls_integer;
  l_agents pls_integer;
  l_files  pls_integer;
begin
  select count(*) into l_tables
    from user_tables
   where table_name in ('MX_ASSETS', 'MX_WORK_ORDERS', 'MX_ALARMS', 'MX_TECHNICIANS');

  select count(*) into l_tools
    from uc_ai_tools
   where code in ('MX_GET_ASSET', 'MX_LIST_WORK_ORDERS');

  select count(*) into l_agents
    from uc_ai_agents
   where code = 'MX_DESK';

  select count(*) into l_files
    from uc_ai_v_memory_files
   where agent_code = 'MX_DESK';

  sys.dbms_output.put_line('-------------------------------------------------------');
  if l_tables = 0 and l_tools = 0 and l_agents = 0 and l_files = 0 then
    sys.dbms_output.put_line('Teardown OK. Nothing of this course is left.');
  else
    sys.dbms_output.put_line('Left behind: ' || l_tables || ' tables, ' || l_tools
      || ' tools, ' || l_agents || ' agents, ' || l_files || ' memory files.');
  end if;
  sys.dbms_output.put_line('-------------------------------------------------------');
end;
/
