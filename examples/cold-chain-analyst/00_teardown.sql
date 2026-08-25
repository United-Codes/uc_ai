-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale"
-- Removes everything the tutorial created
-- ============================================================================
-- Run this when you are finished, or before you hand the schema back. It removes
-- the demo tables, the UC AI rows the lessons registered (tools, prompt profile,
-- agent), and the two packages.
--
-- It LEAVES THE SANDBOX SCHEMA ALONE. UC_AI_MLE_SBX belongs to the DBA and to
-- every other code-mode user of this database. To remove it, a DBA runs
-- scripts/uninstall_ptc_sandbox.sql with the same two answers as the install.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- The execution hook, in case lesson 5 stopped early
-- ---------------------------------------------------------------------------
begin
  uc_ai_agents_api.set_execution_hook(null);
  -- Every lesson sets g_enable_tools, g_tool_tags and g_enable_programmatic_tools
  -- on the package globals, and none of them resets it. Those values live for the
  -- whole session, so clear them here as well.
  uc_ai.reset_globals;
  sys.dbms_output.put_line('Execution hook and UC AI globals cleared for this session.');
end;
/

-- ---------------------------------------------------------------------------
-- The agent
-- ---------------------------------------------------------------------------
-- Most people who want an agent gone want it to stop answering. For that, do not
-- delete anything:
--
--   uc_ai_agents_api.change_status('CC_ANALYST', 1, uc_ai_agents_api.c_status_archived);
--
-- An archived agent no longer resolves, and its history stays. purge_agent is
-- the other choice: every version, its executions, its sessions and their
-- messages. It keeps what other things also use, so the prompt profile and the
-- tool rows stay. Those are deleted below.
declare
  e_agent_missing exception;
  pragma exception_init(e_agent_missing, -20500);
begin
  uc_ai_agents_api.purge_agent(p_code => 'CC_ANALYST');
  commit;
  sys.dbms_output.put_line('Agent CC_ANALYST purged, with its executions and messages.');
exception
  when e_agent_missing then
    sys.dbms_output.put_line('Agent CC_ANALYST is not there, so there is nothing to purge.');
end;
/

-- ---------------------------------------------------------------------------
-- The prompt profile and the tools
-- ---------------------------------------------------------------------------
-- There is no delete_tool API. A tool is a row, and its parameters and tags are
-- rows that point at it. The foreign keys cascade, and the two deletes below are
-- written out so that the shape is visible.
--
-- CAUTION: the filter is `code like 'CC\_%'`. If your schema holds other tools
-- whose code starts with CC_, change the filter before you run this.
declare
  l_rows pls_integer;
begin
  begin
    uc_ai_prompt_profiles_api.delete_prompt_profile(p_code => 'CC_ANALYST_PROFILE', p_version => 1);
    sys.dbms_output.put_line('Prompt profile CC_ANALYST_PROFILE removed.');
  exception
    when others then
      -- @dblinter ignore(g-5040): an absent profile is the normal case on a second run
      -- @dblinter ignore(g-5080): the message says what happened, and the script continues
      sys.dbms_output.put_line('Prompt profile CC_ANALYST_PROFILE was not removed: '
        || substr(sqlerrm, 1, 120));
  end;

  delete from uc_ai_tool_parameters
   where tool_id in ( select t.id from uc_ai_tools t where t.code like 'CC\_%' escape '\' );

  delete from uc_ai_tool_tags
   where tool_id in ( select t.id from uc_ai_tools t where t.code like 'CC\_%' escape '\' );

  delete from uc_ai_tools where code like 'CC\_%' escape '\';
  l_rows := sql%rowcount;

  commit;
  sys.dbms_output.put_line('Tools removed: ' || l_rows || '.');
end;
/

-- ---------------------------------------------------------------------------
-- The packages
-- ---------------------------------------------------------------------------
declare
  c_packages constant sys.odcivarchar2list := sys.odcivarchar2list(
    'CC_ANALYST_PKG'
  , 'CC_HOOK_PKG'
  );
  e_object_missing exception;
  pragma exception_init(e_object_missing, -4043);
begin
  <<package_loop>>
  for i in 1 .. c_packages.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above, not from user input
      execute immediate 'drop package ' || c_packages(i);
      sys.dbms_output.put_line('Package ' || c_packages(i) || ' dropped.');
    exception
      when e_object_missing then
        -- @dblinter ignore(g-5080): an absent package is the normal case on a second run
        null;
    end;
  end loop package_loop;
end;
/

-- ---------------------------------------------------------------------------
-- The demo tables
-- ---------------------------------------------------------------------------
declare
  -- Child tables first, so no foreign key blocks a drop.
  c_tables constant sys.odcivarchar2list := sys.odcivarchar2list(
    'CC_CLAIMS'
  , 'CC_READINGS'
  , 'CC_SHIPMENTS'
  , 'CC_LIMITS'
  );
  e_table_missing exception;
  pragma exception_init(e_table_missing, -942);
begin
  <<table_loop>>
  for i in 1 .. c_tables.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above, not from user input
      execute immediate 'drop table ' || c_tables(i) || ' cascade constraints purge';
      sys.dbms_output.put_line('Table ' || c_tables(i) || ' dropped.');
    exception
      when e_table_missing then
        -- @dblinter ignore(g-5080): an absent table is the normal case on a second run
        null;
    end;
  end loop table_loop;
end;
/

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
set feedback off

prompt
prompt  Every number below must be 0.
prompt

select ( select count(*) from uc_ai_tools where code like 'CC\_%' escape '\' )   as tools_left
     , ( select count(*) from uc_ai_agents where code = 'CC_ANALYST' )           as agents_left
     , ( select count(*) from uc_ai_prompt_profiles
          where code = 'CC_ANALYST_PROFILE' )                                    as profiles_left
     , ( select count(*) from user_tables
          where table_name like 'CC\_%' escape '\' )                             as tables_left
     , ( select count(*) from user_objects
          where object_name in ('CC_ANALYST_PKG', 'CC_HOOK_PKG') )               as packages_left
  from dual;

prompt
prompt  The sandbox schema is NOT removed. It belongs to the DBA, and other
prompt  UC AI installations in this database may use their own one.
prompt  To remove it: scripts/uninstall_ptc_sandbox.sql, as a DBA.
prompt

set feedback on
