-- UC AI - Programmatic Tool Calling ("code mode") sandbox uninstaller
--
-- Run AS SYS (or a DBA with DROP USER). Removes the code-mode sandbox schema
-- (and with it the runner package, the PURE MLE environment and the private
-- synonym), the locating synonym in the UC AI schema, and the UC AI-side gateway
-- package. UC AI core is left untouched; code mode simply becomes unavailable
-- (generate_text with g_enable_programmatic_tools => true will then raise a clear
-- "sandbox not installed" error).

set define on
set verify off
whenever sqlerror continue

prompt
prompt UC AI code-mode sandbox uninstaller
prompt ===================================
prompt Press ENTER to accept the default shown in brackets.
prompt

accept core_schema char default 'UC_AI' -
  prompt 'Schema UC AI is installed in     [UC_AI]: '
accept sbx_schema char default 'UC_AI_MLE_SBX' -
  prompt 'Sandbox schema to remove  [UC_AI_MLE_SBX]: '

prompt
prompt Removing code-mode sandbox &sbx_schema from &core_schema ...
prompt

-- Drop the locating synonym in the UC AI schema first: without it UC AI reports code
-- mode as unavailable, which is exactly what we want from here on.
begin
  -- @dblinter ignore(G-6010): DDL cannot use bind variables; the schema name is supplied by the DBA running this script
  execute immediate 'drop synonym &core_schema..uc_ai_ptc_runner';
exception
  -- @dblinter ignore(G-5040): best-effort cleanup, a missing object must not stop the uninstall
  when others then null;
end;
/

-- Drop the sandbox account; cascade removes the runner package, the PURE MLE
-- environment and the synonym it owns.
declare
  l_cnt pls_integer;
begin
  -- @dblinter ignore(G-8110): a one-off uninstall-time check; the count reads clearer than a cursor here
  select count(*) into l_cnt from dba_users where username = upper('&sbx_schema');
  if l_cnt > 0 then
    -- @dblinter ignore(G-6010): DDL cannot use bind variables; the schema name is supplied by the DBA running this script
    execute immediate 'drop user &sbx_schema cascade';
  end if;
end;
/

-- Drop the core-side gateway.
alter session set current_schema = &core_schema;
begin
  -- @dblinter ignore(G-6010): DDL cannot use bind variables
  execute immediate 'drop package uc_ai_ptc_api';
exception
  -- @dblinter ignore(G-5040): best-effort cleanup, a missing package must not stop the uninstall
  when others then null;
end;
/

prompt
prompt Code-mode sandbox &sbx_schema removed from &core_schema.
prompt
