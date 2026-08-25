-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF"
-- Remove everything this course created
-- ============================================================================
-- Deletes the five demo tables, the extraction package, and every version of
-- the prompt profile lesson 5 registers.
--
-- Leaves UC AI itself, your API keys, and everything outside this course alone.
-- Safe to run at any point, including before the course is finished.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- The agent of lesson 5
-- ---------------------------------------------------------------------------
-- The agent goes first. An agent that has run cannot be deleted, because its
-- execution history points at it, so purge_agent removes the history with it.
declare
  l_exists pls_integer;
begin
  begin
    -- rownum stops at the first hit: this asks "is there one?", not "how many?"
    select count(*)
      into l_exists
      from uc_ai_agents
     where code = 'INV_EXTRACT_AGENT'
       and rownum = 1;

    if l_exists > 0 then
      -- One call removes every version of the agent and its whole history.
      uc_ai_agents_api.purge_agent(p_code => 'INV_EXTRACT_AGENT');
      commit;
      sys.dbms_output.put_line('Agent INV_EXTRACT_AGENT purged.');
    else
      sys.dbms_output.put_line('Agent INV_EXTRACT_AGENT was not there.');
    end if;
  exception
    when others then
      -- @dblinter ignore(g-5040): the agent may not exist, or UC AI may already be gone;
      -- neither must stop the teardown of everything below
      -- @dblinter ignore(g-5080): a teardown that skips an absent object has nothing to
      -- trace, and a backtrace here would read as a failure
      sys.dbms_output.put_line('Agent: nothing to purge ('
        || substr(sqlerrm, 1, 120) || ').');
  end;
end;
/

-- ---------------------------------------------------------------------------
-- The prompt profile of lesson 5
-- ---------------------------------------------------------------------------
declare
  l_deleted pls_integer := 0;
begin
  begin
    <<profile_loop>>
    for p in ( select id from uc_ai_prompt_profiles where code = 'INV_EXTRACT' ) loop
      uc_ai_prompt_profiles_api.delete_prompt_profile(p_id => p.id);
      l_deleted := l_deleted + 1;
    end loop profile_loop;

    sys.dbms_output.put_line('Prompt profile versions deleted: ' || l_deleted || '.');
  exception
    when others then
      -- @dblinter ignore(g-5040): the profile may not exist, or UC AI may already be gone;
      -- neither must stop the teardown of the tables below
      -- @dblinter ignore(g-5080): a teardown that skips an absent object has nothing to
      -- trace, and a backtrace here would read as a failure
      sys.dbms_output.put_line('Prompt profile: nothing to delete ('
        || substr(sqlerrm, 1, 120) || ').');
  end;
end;
/

-- ---------------------------------------------------------------------------
-- The package
-- ---------------------------------------------------------------------------
declare
  e_object_missing exception;
  pragma exception_init(e_object_missing, -4043);
begin
  -- @dblinter ignore(g-6010): a fixed statement; dynamic only so an absent package is
  -- not an error on a second run
  execute immediate 'drop package inv_extract_pkg';
  sys.dbms_output.put_line('Package inv_extract_pkg dropped.');
exception
  when e_object_missing then
    sys.dbms_output.put_line('Package inv_extract_pkg was not there.');
end;
/

-- ---------------------------------------------------------------------------
-- The tables
-- ---------------------------------------------------------------------------
declare
  -- Child tables first, so no foreign key blocks a drop.
  c_tables constant sys.odcivarchar2list := sys.odcivarchar2list(
    'INV_INVOICE_LINES'
  , 'INV_INVOICES'
  , 'INV_EXTRACTIONS'
  , 'INV_DOCUMENTS'
  , 'INV_PURCHASE_ORDERS'
  );
  e_table_missing exception;
  pragma exception_init(e_table_missing, -942);
  l_dropped pls_integer := 0;
begin
  <<table_loop>>
  for i in 1 .. c_tables.count loop
    begin
      -- @dblinter ignore(g-6010): the name comes from the constant list above, not from user input
      execute immediate 'drop table ' || c_tables(i) || ' cascade constraints purge';
      l_dropped := l_dropped + 1;
    exception
      when e_table_missing then
        -- @dblinter ignore(g-5080): an absent table is the normal case on a second run
        null;
    end;
  end loop table_loop;

  sys.dbms_output.put_line('Tables dropped: ' || l_dropped || ' of 5.');
  sys.dbms_output.put_line('The course is removed. UC AI is untouched.');
end;
/
