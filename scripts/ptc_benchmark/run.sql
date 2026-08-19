-- UC AI - Programmatic Tool Calling ("code mode") benchmark: run
--
-- Requires @scripts/ptc_benchmark/setup.sql and, for the code-mode cases,
-- @scripts/install_ptc_sandbox.sql.
--
-- WARNING: this makes real, paid LLM calls - roughly 20 requests per pass across
-- five providers. Keys come from your uc_ai_get_key function.
--
-- To run a single provider or several passes, call the package directly:
--   begin uc_ai_ptc_bench.run_all(p_passes => 2); end;
--   begin uc_ai_ptc_bench.run_all(p_provider => uc_ai.c_provider_google); end;

set define off
set serveroutput on size unlimited
set feedback off
set linesize 200

begin
  uc_ai_ptc_bench.run_all(p_passes => 1);
end;
/
