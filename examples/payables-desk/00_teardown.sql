-- ============================================================================
-- UC AI tutorial — "Secure an Agent" — remove everything
-- ============================================================================
-- Deletes the eleven demo tables, the packages, and every row this course
-- registered in UC AI. It touches nothing that belongs to another course or to
-- your own work.
--
-- The attack text of this course lives in AP_MESSAGES and in one AP_VENDORS
-- row. Dropping those tables is what removes it.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl

set define off
set serveroutput on

-- 1. Memory first. disable_for_agent needs the agent to still exist, and it
--    removes the memory tag from the prompt profile as well as the config row.
--    The stores themselves belong to AP_DESK alone, so purge_agent below
--    removes them.
begin
  uc_ai_memory.disable_for_agent(p_agent_code => 'AP_DESK', p_drop_store => true);
  sys.dbms_output.put_line('memory disabled for AP_DESK');
  commit;
exception
  when others then
    -- @dblinter ignore(g-5040): several different errors all mean "no memory to remove",
    -- and teardown must continue to the next object whichever one it is
    -- @dblinter ignore(g-5080): sqlerrm is reported to the reader, and a teardown that
    -- stopped on the first absent object would be useless on a partial run
    sys.dbms_output.put_line('memory for AP_DESK: ' || sqlerrm);
end;
/

-- 2. The agents, the profiles and their history.
declare
  procedure purge(p_code in varchar2)
  as
  begin
    uc_ai_agents_api.purge_agent(p_code => p_code);
    sys.dbms_output.put_line('agent ' || p_code || ' purged');
  exception
    when others then
      -- @dblinter ignore(g-5040): an absent agent is the normal case on a partial run
      -- @dblinter ignore(g-5080): the message below is all the reader needs
      sys.dbms_output.put_line('agent ' || p_code || ': ' || sqlerrm);
  end purge;
begin
  purge('AP_DESK');
  purge('AP_TRIAGE');
  commit;
end;
/

declare
  procedure drop_profile(p_code in varchar2)
  as
  begin
    uc_ai_prompt_profiles_api.delete_prompt_profile(p_code => p_code, p_version => 1);
    sys.dbms_output.put_line('prompt profile ' || p_code || ' deleted');
  exception
    when others then
      -- @dblinter ignore(g-5040): several different errors all mean "nothing to remove",
      -- and teardown must continue to the next object whichever one it is
      -- @dblinter ignore(g-5080): sqlerrm is reported to the reader
      sys.dbms_output.put_line('prompt profile ' || p_code || ': ' || sqlerrm);
  end drop_profile;
begin
  drop_profile('AP_DESK_PROFILE');
  drop_profile('AP_TRIAGE_PROFILE');
  commit;
end;
/

-- 3. The tools. A tool is a row, so removing one is DML. The parameters and
--    the tags cascade.
declare
  l_rows pls_integer;
begin
  delete from uc_ai_tools where code like 'AP\_%' escape '\';
  l_rows := sql%rowcount;
  commit;
  sys.dbms_output.put_line('tools removed: ' || l_rows);
end;
/

-- 4. The packages, including the two deliberately unsafe ones.
declare
  c_packages constant sys.odcivarchar2list := sys.odcivarchar2list(
    'AP_NAIVE_PKG', 'AP_LEAK_PKG', 'AP_DESK_HOOK', 'AP_DESK_PKG'
  );
  e_not_there exception;
  pragma exception_init(e_not_there, -4043);
begin
  <<package_loop>>
  for i in 1 .. c_packages.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above
      execute immediate 'drop package ' || c_packages(i);
      sys.dbms_output.put_line('dropped ' || c_packages(i));
    exception
      when e_not_there then
        -- @dblinter ignore(g-5080): already gone is the outcome this wants
        null;
    end;
  end loop package_loop;
end;
/

-- 5. The tables, child first, and the sequence.
declare
  c_tables constant sys.odcivarchar2list := sys.odcivarchar2list(
    'AP_DESK_ERRORS'
  , 'AP_VENDOR_BANK_CHANGES'
  , 'AP_OUTBOX'
  , 'AP_APPROVALS'
  , 'AP_MESSAGES'
  , 'AP_INVOICES'
  , 'AP_CLERKS'
  , 'AP_VENDORS'
  , 'AP_ENTITIES'
  , 'AP_REPLY_TEMPLATES'
  , 'AP_CONTROLS'
  );
  e_table_missing exception;
  pragma exception_init(e_table_missing, -942);
  e_sequence_missing exception;
  pragma exception_init(e_sequence_missing, -2289);
begin
  <<table_loop>>
  for i in 1 .. c_tables.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above
      execute immediate 'drop table ' || c_tables(i) || ' cascade constraints purge';
    exception
      when e_table_missing then
        -- @dblinter ignore(g-5080): an absent table is the normal case on a partial run
        null;
    end;
  end loop table_loop;

  begin
    execute immediate 'drop sequence ap_approvals_no_seq';
  exception
    when e_sequence_missing then
      -- @dblinter ignore(g-5080): an absent sequence is the normal case on a partial run
      null;
  end;

  sys.dbms_output.put_line('demo tables removed.');
end;
/

-- 6. Clear the session hook, in case lesson 6 left it set.
begin
  uc_ai_agents_api.set_execution_hook(null);
  sys.dbms_output.put_line('session execution hook cleared.');
end;
/
