-- UC AI - Programmatic Tool Calling ("code mode") sandbox installer
--
-- Run this AS SYS (or a DBA with CREATE USER, CREATE ANY SYNONYM, CREATE ANY
-- PROCEDURE and GRANT ANY OBJECT PRIVILEGE), connected to the SAME PDB where UC AI
-- core is installed. Requires Oracle 23ai with MLE JavaScript.
--
-- It enables code mode by creating a dedicated, low-privilege, schema-only account
-- that runs the model-authored JavaScript in isolation:
--   * the JS runs in a PURE MLE execution context, which removes every
--     database-facing JavaScript API (mle-js-oracledb cannot be required or
--     imported; the oracledb/session/soda/plsffi globals do not exist). The
--     generated program can therefore run no SQL at all - it cannot read data and
--     it cannot COMMIT or ROLLBACK the caller's transaction;
--   * tool calls are serviced from PL/SQL by the runner, whose ONLY reachable
--     object is the UC AI gateway uc_ai_ptc_api (via a private synonym);
--   * as defense in depth the runner is a definer's-rights package OWNED BY this
--     account, so any SQL it did run would use the account's (near-zero)
--     privileges with roles disabled.
--
-- Both schema names are asked for below - nothing is hardcoded in UC AI. The UC AI
-- schema finds its runner through a private synonym this script creates there, so
-- run the script once per UC AI installation and each one gets its own sandbox.
--
-- Enable per call afterwards with:  uc_ai.g_enable_programmatic_tools := true;
-- Undo with scripts/uninstall_ptc_sandbox.sql.
--
-- For an unattended install, replace the two ACCEPT commands below with
--   define core_schema = MY_UC_AI_SCHEMA
--   define sbx_schema  = MY_SANDBOX_SCHEMA
-- everything after that is non-interactive.

set define on
set verify off
whenever sqlerror exit failure

prompt
prompt UC AI code-mode sandbox installer
prompt =================================
prompt Press ENTER to accept the default shown in brackets.
prompt

accept core_schema char default 'UC_AI' -
  prompt 'Schema UC AI is installed in     [UC_AI]: '
accept sbx_schema char default 'UC_AI_MLE_SBX' -
  prompt 'Sandbox schema to create  [UC_AI_MLE_SBX]: '

prompt
prompt Installing code-mode sandbox &sbx_schema for UC AI schema &core_schema ...
prompt

-- 0) Fail before changing anything if the target is not a UC AI schema. One sandbox
--    per UC AI installation: sharing one would point its gateway synonym at a single
--    schema, so another installation's programs would run tools in the wrong schema.
declare
  l_cnt pls_integer;
begin
  if upper('&core_schema') = upper('&sbx_schema') then
    raise_application_error(-20001, 'The sandbox must be a separate schema from the UC AI schema.');
  end if;

  select count(*)
    into l_cnt
    from dba_objects
   where owner = upper('&core_schema')
     and object_name = 'UC_AI_TOOLS_API'
     and object_type = 'PACKAGE BODY'
     and status = 'VALID';
  if l_cnt = 0 then
    raise_application_error(-20001, 'UC AI does not seem to be installed in schema &core_schema (no valid UC_AI_TOOLS_API package body).');
  end if;

  -- a sandbox schema that already exists and is NOT one of ours would be adopted
  -- silently, so make the caller pick a different name
  -- @dblinter ignore(G-8110): a one-off install-time check; the count reads clearer than a cursor here
  select count(*)
    into l_cnt
    from dba_users u
   where u.username = upper('&sbx_schema')
     and exists (select 1
                   from dba_objects o
                  where o.owner = u.username
                    and o.object_name not in ('UC_AI_PTC_RUNNER', 'UC_AI_PTC_API', 'UC_AI_PTC_PURE_ENV'));
  if l_cnt > 0 then
    raise_application_error(-20001, 'Schema &sbx_schema already exists and owns other objects. Choose a dedicated schema name for the sandbox.');
  end if;
end;
/

-- 1) Dedicated schema-only account that cannot log in.
declare
  l_cnt pls_integer;
begin
  -- @dblinter ignore(G-8110): a one-off install-time check; the count reads clearer than a cursor here
  select count(*) into l_cnt from dba_users where username = upper('&sbx_schema');
  if l_cnt = 0 then
    -- @dblinter ignore(G-6010): DDL cannot use bind variables; the schema name is supplied by the DBA running this script
    execute immediate 'create user &sbx_schema no authentication';
  end if;
end;
/

-- 2) Just enough privilege to run JavaScript via MLE - nothing that grants data
--    access. (CREATE MLE suffices on 23.9+; the others are harmless on newer RUs.)
grant create mle to &sbx_schema;
grant execute dynamic mle to &sbx_schema;
grant execute on sys.dbms_mle to &sbx_schema;

-- 3) Install / refresh the UC AI-side gateway (the single entry point the sandbox
--    is allowed to call).
alter session set current_schema = &core_schema;
set define off
@@../src/packages/uc_ai_ptc_api.pks
@@../src/packages/uc_ai_ptc_api.pkb
set define on

-- 4) Grant the sandbox EXECUTE on exactly that gateway, reachable unqualified via
--    a private synonym in the sandbox schema.
grant execute on &core_schema..uc_ai_ptc_api to &sbx_schema;
create or replace synonym &sbx_schema..uc_ai_ptc_api for &core_schema..uc_ai_ptc_api;

-- 5) The PURE MLE environment the runner evaluates the model's code in. This is
--    what strips SQL access from the generated JavaScript, so it is required -
--    if this fails your database does not support PURE contexts and code mode
--    cannot be installed.
alter session set current_schema = &sbx_schema;
create or replace mle env uc_ai_ptc_pure_env pure;

-- 6) Install the MLE runner INTO the sandbox schema (definer's rights => any SQL it
--    ran would use the sandbox's privileges; it services callTool from PL/SQL).
--    Substitution must be OFF here: the runner embeds JavaScript containing "&&",
--    which SQLcl/SQL*Plus would otherwise treat as a substitution variable and
--    silently skip the package body.
set define off
@@../src/packages/uc_ai_ptc_runner.pks
@@../src/packages/uc_ai_ptc_runner.pkb
set define on

-- 7) Let the UC AI schema invoke the runner, and give it a private synonym so it can
--    find the sandbox at runtime with no schema name compiled into UC AI. This
--    synonym is what uc_ai_tools_api.c_ptc_runner_synonym resolves.
alter session set current_schema = &core_schema;
grant execute on &sbx_schema..uc_ai_ptc_runner to &core_schema;
create or replace synonym &core_schema..uc_ai_ptc_runner for &sbx_schema..uc_ai_ptc_runner;

-- 8) Verify: a silently skipped package body or a missing synonym must not look
--    like success.
declare
  l_cnt pls_integer;
begin
  select count(*)
    into l_cnt
    from dba_objects
   where owner = upper('&sbx_schema')
     and object_name = 'UC_AI_PTC_RUNNER'
     and object_type in ('PACKAGE', 'PACKAGE BODY')
     and status = 'VALID';
  if l_cnt != 2 then
    raise_application_error(-20001, 'Install failed: &sbx_schema..UC_AI_PTC_RUNNER is not valid (expected spec + body, found ' || l_cnt || ' valid).');
  end if;

  select count(*)
    into l_cnt
    from dba_synonyms
   where owner = upper('&core_schema')
     and synonym_name = 'UC_AI_PTC_RUNNER'
     and table_owner = upper('&sbx_schema');
  if l_cnt != 1 then
    raise_application_error(-20001, 'Install failed: synonym &core_schema..UC_AI_PTC_RUNNER does not point at &sbx_schema.');
  end if;
end;
/

prompt
prompt Code-mode sandbox &sbx_schema installed for &core_schema.
prompt Enable per call with: uc_ai.g_enable_programmatic_tools := true;
prompt
