-- Run one utPLSQL suite, package or single test.
--
-- Usage: @scripts/run_tests.sql <target>
--   test_uc_ai_toon                     a whole package
--   test_uc_ai_anthropic.basic_recipe   a single test
--   uc_ai.agents                        a suitepath (needs the schema prefix)
--
-- Careful: anything matching a provider suite calls a real LLM and costs money.
-- Use `make test-free` for the fast, free set.

set serveroutput on size unlimited
set feedback off
-- Otherwise SQLcl echoes the block twice as "old:" / "new:" for the &1 variable.
set verify off

-- Keep number formatting locale-independent; see run_tests_free.sql.
alter session set nls_numeric_characters = '.,';

whenever sqlerror exit failure
whenever oserror exit failure

begin
  ut.run('&1');
end;
/

exit
