-- ============================================================================
-- UC AI tutorial — "Build an Agent"
-- Removes everything the tutorial created
-- ============================================================================
-- Run this when you are finished, or before you hand the schema back. It removes
-- the demo tables, the UC AI rows the lessons registered (tools, prompt profile,
-- agent, memory configuration), and the hook package of the last lesson.
--
-- It leaves UC AI itself and every other agent in the schema untouched.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- The agent, and everything that belongs only to it
-- ---------------------------------------------------------------------------
-- Most people who want an agent gone want it to stop answering. For that, do not
-- delete anything:
--
--   uc_ai_agents_api.change_status('SC_DESK', 1, uc_ai_agents_api.c_status_archived);
--
-- An archived agent no longer resolves, and its history stays.
--
-- purge_agent is the other choice: it removes every version of the agent, its
-- executions, its sessions, their messages, and the memory stores that belong to
-- it alone. It keeps what other things also use, so the prompt profile stays and
-- the tool rows stay. Those are deleted below.
declare
  e_agent_missing exception;
  pragma exception_init(e_agent_missing, -20500);
begin
  uc_ai_agents_api.purge_agent(p_code => 'SC_DESK');
  commit;
  sys.dbms_output.put_line('Agent SC_DESK purged, with its history and its own memory.');
exception
  when e_agent_missing then
    sys.dbms_output.put_line('Agent SC_DESK is not there, so there is nothing to purge.');
end;
/

-- ---------------------------------------------------------------------------
-- UC AI rows the lessons created
-- ---------------------------------------------------------------------------
declare
  procedure log_line(p_text in varchar2) is
  begin
    sys.dbms_output.put_line(p_text);
  end log_line;
begin
  -- Memory needs no separate step: purge_agent above already removed the
  -- per-contract stores of this agent, because they belong to it alone.
  begin
    uc_ai_prompt_profiles_api.delete_prompt_profile(p_code => 'SC_DESK_PROFILE', p_version => 1);
    log_line('Prompt profile SC_DESK_PROFILE removed.');
  exception
    when others then
      -- @dblinter ignore(g-5040): several different errors all mean "nothing to remove", and
      -- teardown must continue to the next object whichever one it is
      -- @dblinter ignore(g-5080): sqlerrm is reported to the reader; a teardown that skips an
      -- absent object has nothing to trace, and a backtrace here would read as a failure
      log_line('Prompt profile: nothing to remove (' || sqlerrm || ').');
  end;
end;
/

-- The tools are plain rows. Deleting the parameters first keeps the foreign keys happy.
delete from uc_ai_tool_parameters
 where tool_id in (select t.id from uc_ai_tools t where t.code like 'SC\_%' escape '\');

delete from uc_ai_tool_tags
 where tool_id in (select t.id from uc_ai_tools t where t.code like 'SC\_%' escape '\');

delete from uc_ai_tools where code like 'SC\_%' escape '\';

commit;

-- ---------------------------------------------------------------------------
-- The hook of the last lesson
-- ---------------------------------------------------------------------------
-- The tutorial uses SC_DESK_HOOK and registers it for the session only, so it
-- never activates itself. This removes it together with the tool handler package.
--
-- It does NOT touch a package named UC_AI_HOOK. That name activates itself for
-- every agent in the schema, so if one exists it may be yours or another
-- product's. The tutorial never creates it and must never delete it. The
-- verification below warns you when one is present.
declare
  c_packages constant sys.odcivarchar2list := sys.odcivarchar2list(
    'SC_DESK_HOOK'      -- lesson 9, the execution hook
  , 'SC_DESK_JOB_PKG'   -- lesson 8, queue_request and run_request
  , 'SC_DESK_PKG'       -- lessons 3 and 5, the tool handlers
  );
  e_object_missing exception;
  pragma exception_init(e_object_missing, -4043);
begin
  <<package_loop>>
  for i in 1 .. c_packages.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above, not from user input
      execute immediate 'drop package ' || c_packages(i);
    exception
      when e_object_missing then
        -- @dblinter ignore(g-5080): an absent package is the normal case, so there is nothing to report
        null;
    end;
  end loop package_loop;
end;
/

-- ---------------------------------------------------------------------------
-- The scheduler jobs of lesson 8
-- ---------------------------------------------------------------------------
-- queue_request creates one job for each question. A one-time job drops itself
-- when it finishes, because auto_drop defaults to true, so usually there is
-- nothing here to remove. This loop catches the exception: a job that never ran,
-- or one that is still running when you tear the tutorial down.
declare
  l_dropped pls_integer := 0;
begin
  <<job_rows>>
  for r in ( select j.job_name
               from user_scheduler_jobs j
              where j.job_name like 'SC\_AI\_JOB\_%' escape '\' ) loop
    -- @dblinter ignore(g-6010): the name comes from the data dictionary, not from user input
    sys.dbms_scheduler.drop_job(job_name => r.job_name, force => true);
    l_dropped := l_dropped + 1;
  end loop job_rows;

  sys.dbms_output.put_line('Scheduler jobs dropped: ' || l_dropped);
end;
/

-- ---------------------------------------------------------------------------
-- Demo tables
-- ---------------------------------------------------------------------------
declare
  c_tables constant sys.odcivarchar2list := sys.odcivarchar2list(
    'SC_DESK_AUDIT'     -- lesson 9, what our own hook recorded
  , 'SC_AI_REQUESTS'    -- lesson 8, the request queue
  , 'SC_CREDIT_NOTES'
  , 'SC_INVOICES'
  , 'SC_SERVICE_CALLS'
  , 'SC_ASSETS'
  , 'SC_CONTRACTS'
  , 'SC_CUSTOMERS'
  );
  e_table_missing exception;
  pragma exception_init(e_table_missing, -942);
  e_sequence_missing exception;
  pragma exception_init(e_sequence_missing, -2289);
begin
  <<table_loop>>
  for i in 1 .. c_tables.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above, not from user input
      execute immediate 'drop table ' || c_tables(i) || ' cascade constraints purge';
    exception
      when e_table_missing then
        -- @dblinter ignore(g-5080): an absent table is the normal case, so there is nothing to report
        null;
    end;
  end loop table_loop;

  begin
    -- @dblinter ignore(g-6010): a compile-time constant statement with no user input
    execute immediate 'drop sequence sc_credit_notes_no_seq';
  exception
    when e_sequence_missing then
      -- @dblinter ignore(g-5080): an absent sequence is the normal case
      null;
  end;
end;
/

-- ---------------------------------------------------------------------------
-- Verification — every count below must be 0
-- ---------------------------------------------------------------------------
set feedback off
prompt
prompt Teardown finished. Every number below must be 0.
prompt

select (select count(*) from user_tables where table_name like 'SC\_%' escape '\')     as demo_tables
     , (select count(*) from user_scheduler_jobs
         where job_name like 'SC\_AI\_JOB\_%' escape '\')                             as demo_jobs
     , (select count(*) from uc_ai_tools where code like 'SC\_%' escape '\')           as demo_tools
     , (select count(*) from uc_ai_agents where code = 'SC_DESK')                      as demo_agents
     , (select count(*) from uc_ai_prompt_profiles where code = 'SC_DESK_PROFILE')      as demo_profiles
     , (select count(*) from user_objects
         where object_name in ('SC_DESK_HOOK', 'SC_DESK_JOB_PKG', 'SC_DESK_PKG')
           and object_type = 'PACKAGE')                                                as demo_packages
  from dual;

prompt
prompt A package named UC_AI_HOOK runs before every agent in this schema. The
prompt tutorial never creates one, so if the next query returns a row, it is not
prompt from the tutorial and this script left it alone on purpose.
prompt

select object_name, status
  from user_objects
 where object_name = 'UC_AI_HOOK'
   and object_type = 'PACKAGE';

set feedback on
