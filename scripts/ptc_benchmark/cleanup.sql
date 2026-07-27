-- UC AI - Programmatic Tool Calling ("code mode") benchmark: remove
--
-- Drops the benchmark tools and package again. Run as the UC AI owner.

set define off
whenever sqlerror continue

begin
  delete from uc_ai_tools where code like 'BENCH_%';
  commit;
end;
/

drop package uc_ai_ptc_bench;

prompt UC AI code-mode benchmark removed.
