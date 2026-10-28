-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A"
-- Removes everything this course created
-- ============================================================================
-- It removes the endpoint service-desk with its API keys and tasks, its
-- scheduler jobs, the tools,
-- the prompt profile with all its versions, the agent, the tool-handler package
-- and the two partner_ tables.
--
-- It leaves these alone:
--   * the ORDS module uc_ai_a2a. Other endpoints in the schema use it. To
--     remove it, call uc_ai_a2a.uninstall_ords_module.
--   * the tables of the course "Build an Agent". Run the teardown of that course
--     to remove them.
--   * UC AI itself, and every other agent and endpoint of the schema.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- The scheduler jobs of a background run
-- ---------------------------------------------------------------------------
-- A background run creates a one-time job that drops itself when it ends. This
-- loop removes a job of this endpoint that never ran or is still queued. It
-- runs first, because remove_endpoint deletes the tasks that name the jobs.
declare
  l_dropped pls_integer := 0;
begin
  <<job_rows>>
  for r in ( select j.job_name
               from uc_ai_a2a_tasks t
               join uc_ai_a2a_endpoints e on e.id = t.endpoint_id
               join user_scheduler_jobs j on j.job_name = t.job_name
              where e.code = 'service-desk' ) loop
    -- @dblinter ignore(g-6010): the name comes from the data dictionary, not from user input
    sys.dbms_scheduler.drop_job(job_name => r.job_name, force => true);
    l_dropped := l_dropped + 1;
  end loop job_rows;

  sys.dbms_output.put_line('Scheduler jobs dropped: ' || l_dropped);
end;
/

-- ---------------------------------------------------------------------------
-- The endpoint
-- ---------------------------------------------------------------------------
declare
  e_endpoint_missing exception;
  pragma exception_init(e_endpoint_missing, -20430);
begin
  uc_ai_a2a.remove_endpoint('service-desk');
  commit;
  sys.dbms_output.put_line('Endpoint service-desk removed, with its API keys and tasks.');
exception
  when e_endpoint_missing then
    sys.dbms_output.put_line('Endpoint service-desk is not there, so there is nothing to remove.');
end;
/

-- ---------------------------------------------------------------------------
-- The agent, and the prompt profile with every version
-- ---------------------------------------------------------------------------
-- purge_agent removes every version of the agent, its executions, its sessions
-- and their messages.
declare
  e_agent_missing exception;
  pragma exception_init(e_agent_missing, -20500);
begin
  uc_ai_agents_api.purge_agent(p_code => 'partner_desk');
  commit;
  sys.dbms_output.put_line('Agent partner_desk purged, with its history.');
exception
  when e_agent_missing then
    sys.dbms_output.put_line('Agent partner_desk is not there, so there is nothing to purge.');
end;
/

declare
  procedure log_line(p_text in varchar2) is
  begin
    sys.dbms_output.put_line(p_text);
  end log_line;
begin
  <<profile_versions>>
  for r in ( select p.version
               from uc_ai_prompt_profiles p
              where p.code = 'PARTNER_DESK_PROFILE'
              order by p.version desc ) loop
    uc_ai_prompt_profiles_api.delete_prompt_profile(
      p_code    => 'PARTNER_DESK_PROFILE'
    , p_version => r.version
    );
    log_line('Prompt profile PARTNER_DESK_PROFILE version ' || r.version || ' removed.');
  end loop profile_versions;
  commit;
end;
/

-- ---------------------------------------------------------------------------
-- The tools
-- ---------------------------------------------------------------------------
-- The tools are plain rows. Deleting the parameters and tags first keeps the
-- foreign keys happy.
delete from uc_ai_tool_parameters
 where tool_id in (select t.id from uc_ai_tools t where t.code like 'PARTNER\_%' escape '\');

delete from uc_ai_tool_tags
 where tool_id in (select t.id from uc_ai_tools t where t.code like 'PARTNER\_%' escape '\');

delete from uc_ai_tools where code like 'PARTNER\_%' escape '\';

commit;

-- ---------------------------------------------------------------------------
-- Package and tables
-- ---------------------------------------------------------------------------
declare
  e_object_missing exception;
  pragma exception_init(e_object_missing, -4043);
  e_table_missing exception;
  pragma exception_init(e_table_missing, -942);
  c_tables constant sys.odcivarchar2list := sys.odcivarchar2list(
    'PARTNER_VISITS'
  , 'PARTNER_CLIENTS'
  );
begin
  begin
    -- @dblinter ignore(g-6010): a compile-time constant statement with no user input
    execute immediate 'drop package partner_desk_pkg';
  exception
    when e_object_missing then
      -- @dblinter ignore(g-5080): an absent package is the normal case, so there is nothing to report
      null;
  end;

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
end;
/

-- ---------------------------------------------------------------------------
-- Verification — every count below must be 0
-- ---------------------------------------------------------------------------
set feedback off
prompt
prompt Teardown finished. Every number below must be 0.
prompt

select (select count(*) from uc_ai_a2a_endpoints where code = 'service-desk')            as endpoints
     , (select count(*) from uc_ai_tools where code like 'PARTNER\_%' escape '\')        as tools
     , (select count(*) from uc_ai_agents where code = 'partner_desk')                   as agents
     , (select count(*) from uc_ai_prompt_profiles where code = 'PARTNER_DESK_PROFILE')  as profiles
     , (select count(*) from user_objects
         where object_name = 'PARTNER_DESK_PKG' and object_type = 'PACKAGE')             as packages
     , (select count(*) from user_tables where table_name like 'PARTNER\_%' escape '\')  as tables
  from dual;

set feedback on
