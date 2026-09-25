-- ============================================================================
-- UC AI tutorial — "Answer from Your Documents"
-- Remove everything this course created
-- ============================================================================
-- Drops the three functions and the two demo tables.
--
-- Leaves UC AI itself, your API keys, and everything outside this course alone.
-- Safe to run at any point, including before the course is finished.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on
set feedback off

prompt
prompt === Teardown: Answer from Your Documents ===========================
prompt

drop function if exists hb_answer;
drop function if exists hb_retrieve;
drop function if exists hb_embed;

-- Dropping the table also drops its DOC_ID index.
drop table if exists hb_chunks purge;
drop table if exists hb_documents purge;

declare
  l_left pls_integer;
begin
  select count(*) into l_left
    from user_objects
   where object_name like 'HB\_%' escape '\';

  sys.dbms_output.put_line('Teardown OK: ' || l_left || ' HB_ objects left.');
end;
/
