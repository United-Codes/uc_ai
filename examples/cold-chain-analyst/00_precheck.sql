-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 1
-- Run this FIRST
-- ============================================================================
-- Checks the six things this course depends on, and names the fix for each
-- failure. Two of them need somebody else:
--
--   * the code-mode SANDBOX. Code mode has no fallback without it, and only a
--     DBA can install it. Ask early.
--   * the network ACL for the provider, and on many systems the provider
--     certificate in a wallet.
--
-- Budget about 30 minutes for the two together.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on
set feedback off

prompt
prompt ==========================================================
prompt  UC AI tutorial - prerequisite check
prompt ==========================================================
prompt

-- ---------------------------------------------------------------------------
-- 1. Is UC AI installed, and which version?
-- ---------------------------------------------------------------------------
declare
  l_version varchar2(16 char);
begin
  -- @dblinter ignore(g-6010): a compile-time constant statement; dynamic only so the
  -- script still runs and reports when UC AI is not installed at all
  execute immediate 'begin :1 := uc_ai.c_version; end;' using out l_version;
  sys.dbms_output.put_line('1. UC AI is installed. Version ' || l_version || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): any error here has one meaning for the reader
    -- @dblinter ignore(g-5080): the message below is the diagnosis this check exists to give
    sys.dbms_output.put_line('1. FAILED: UC AI is not installed in this schema, or you '
      || 'cannot see it.');
    sys.dbms_output.put_line('   Fix: run install_uc_ai.sql, then come back.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
end;
/

-- ---------------------------------------------------------------------------
-- 2. Is this Oracle 23ai or newer?
-- ---------------------------------------------------------------------------
-- Code mode needs MLE JavaScript with PURE execution contexts. That is the only
-- part of UC AI with this requirement. Everything else runs on 12.2 and newer.
declare
  l_version number := sys.dbms_db_version.version;
begin
  if l_version >= 23 then
    sys.dbms_output.put_line('2. The database is version ' || l_version || '. Code mode is possible.');
  else
    sys.dbms_output.put_line('2. FAILED: the database is version ' || l_version || '.');
    sys.dbms_output.put_line('   Code mode needs Oracle 23ai. The rest of UC AI does not,');
    sys.dbms_output.put_line('   so the other courses and guides still work here.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 3. Is the code-mode sandbox installed?
-- ---------------------------------------------------------------------------
-- The JavaScript of the model is untrusted, so UC AI always runs it in a
-- separate, locked-down schema. There is no fallback. UC AI finds that schema
-- through a private synonym, so nothing is compiled into the packages.
declare
  l_owner   varchar2(128 char);
  l_count   pls_integer;
  l_sbx     varchar2(261 char);

  -- name_resolve answers the question the session itself answers when it runs
  -- `uc_ai.c_version`: WHICH schema owns the UC_AI you can see. A query on
  -- all_objects cannot: several schemas of one database may hold a UC_AI.
  l_part1     varchar2(128 char);
  l_part2     varchar2(128 char);
  l_dblink    varchar2(128 char);
  l_part1_typ number;
  l_objno     number;
begin
  sys.dbms_utility.name_resolve(
    name          => 'UC_AI'
  , context       => 1
  , schema        => l_owner
  , part1         => l_part1
  , part2         => l_part2
  , dblink        => l_dblink
  , part1_type    => l_part1_typ
  , object_number => l_objno
  );

  select count(*)
       , min(syn.table_owner || '.' || syn.table_name)
    into l_count, l_sbx
    from all_synonyms syn
    join all_objects obj
      on obj.owner = syn.table_owner
     and obj.object_name = syn.table_name
   where syn.owner = l_owner
     and syn.synonym_name = 'UC_AI_PTC_RUNNER'
     and obj.object_type = 'PACKAGE'
     and obj.status = 'VALID';

  if l_count > 0 then
    sys.dbms_output.put_line('3. The sandbox is installed. ' || l_owner
      || '.UC_AI_PTC_RUNNER points at ' || l_sbx || '.');
  else
    sys.dbms_output.put_line('3. FAILED: there is no valid UC_AI_PTC_RUNNER synonym in ' || l_owner || '.');
    sys.dbms_output.put_line('   Fix: a DBA runs scripts/install_ptc_sandbox.sql in this PDB.');
    sys.dbms_output.put_line('   From a release download, the file is install_ptc_sandbox_complete.sql.');
    sys.dbms_output.put_line('   Run it ONE TIME for each UC AI installation. Two installations');
    sys.dbms_output.put_line('   must not share one sandbox.');
    sys.dbms_output.put_line('   Without it, code mode raises ORA-20502 and names the script.');
    sys.dbms_output.put_line('   Note: the synonym is PRIVATE to the UC AI schema. If you are not');
    sys.dbms_output.put_line('   in that schema, you cannot see it, and check 4 below is the one');
    sys.dbms_output.put_line('   that answers the question.');
  end if;
exception
  when others then
    -- @dblinter ignore(g-5040): the one meaning of a failure here is "UC AI was not found"
    -- @dblinter ignore(g-5080): check 4 gives the reader the real answer anyway
    sys.dbms_output.put_line('3. SKIPPED: UC AI itself was not resolved, so check 1 failed first.');
    sys.dbms_output.put_line('   Error: ' || substr(sqlerrm, 1, 120));
end;
/

-- ---------------------------------------------------------------------------
-- 4. Does a program really run?
-- ---------------------------------------------------------------------------
-- Checks 1 to 3 read the data dictionary. This one runs a program end to end:
-- PL/SQL hands three lines of JavaScript to the sandbox and reads the answer
-- back. It calls no tool and no model, so it costs nothing.
declare
  l_args     json_object_t := json_object_t();
  l_settings uc_ai_settings.t_settings;
  l_out      clob;
begin
  uc_ai.g_enable_tools              := true;
  uc_ai.g_enable_programmatic_tools := true;
  -- Give the probe a tag, even though it calls no tool. An empty tag list is an
  -- allow-list over every active tool in the schema, and that is not a habit to
  -- start with.
  uc_ai.g_tool_tags                 := apex_t_varchar2('coldchain');
  l_settings := uc_ai_settings.build_from_globals;

  l_args.put('code', 'const result = { sandbox: "ready", two_plus_two: 2 + 2 };');

  l_out := uc_ai_tools_api.execute_agent_tool(
             uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);

  sys.dbms_output.put_line('4. A program ran in the sandbox and returned: ' || substr(l_out, 1, 80));
  uc_ai.reset_globals;
exception
  when others then
    -- @dblinter ignore(g-5040): every failure here has the same fix, and it is named below
    -- @dblinter ignore(g-5080): the reader needs the message, not a framework backtrace
    uc_ai.reset_globals;
    sys.dbms_output.put_line('4. FAILED: the sandbox did not run a program.');
    sys.dbms_output.put_line('   Error: ' || substr(sqlerrm, 1, 200));
    sys.dbms_output.put_line('   ORA-20502  the sandbox is not installed. See check 3.');
    sys.dbms_output.put_line('   ORA-04063  the runner package body is invalid. Ask the DBA to');
    sys.dbms_output.put_line('              run the installation script again.');
end;
/

-- ---------------------------------------------------------------------------
-- 5. Can this schema reach the provider?
-- ---------------------------------------------------------------------------
-- One real call, the smallest possible. It costs a few tokens.
declare
  l_result json_object_t;
begin
  l_result := uc_ai.generate_text(
    p_user_prompt => 'Reply with exactly: READY'
  , p_provider    => uc_ai.c_provider_anthropic
  , p_model       => uc_ai_anthropic.c_model_claude_4_5_haiku
  );

  sys.dbms_output.put_line('5. The provider answered: '
    || substr(l_result.get_clob('final_message'), 1, 40));
  sys.dbms_output.put_line('   Tokens used: '
    || l_result.get_object('usage').get_number('total_tokens') || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): every provider error is reported with its fix below
    -- @dblinter ignore(g-5080): sqlerrm is mapped to a fix; a backtrace would not help
    sys.dbms_output.put_line('5. FAILED: the call to the provider did not work.');
    sys.dbms_output.put_line('   Error: ' || substr(sqlerrm, 1, 200));
    sys.dbms_output.put_line('   ');
    sys.dbms_output.put_line('   Find your error below:');
    sys.dbms_output.put_line('   ORA-24247  no network ACL. A DBA must grant this schema access');
    sys.dbms_output.put_line('              to api.anthropic.com on port 443.');
    sys.dbms_output.put_line('   ORA-29024  certificate not trusted. The provider certificate');
    sys.dbms_output.put_line('              has to be in the wallet of the database.');
    sys.dbms_output.put_line('   ORA-20302  the provider refused. Check the API key.');
    sys.dbms_output.put_line('   See the network setup guide for the grants.');
end;
/

-- ---------------------------------------------------------------------------
-- 6. Is the demo schema there?
-- ---------------------------------------------------------------------------
declare
  l_tables   pls_integer;
  l_readings pls_integer := 0;
begin
  select count(*)
    into l_tables
    from user_tables
   where table_name in ('CC_LIMITS', 'CC_SHIPMENTS', 'CC_READINGS', 'CC_CLAIMS');

  if l_tables = 4 then
    -- @dblinter ignore(g-6010): a compile-time constant statement; dynamic only so this
    -- script still compiles and reports when the demo table is absent
    execute immediate 'select count(*) from cc_readings' into l_readings;
    sys.dbms_output.put_line('6. The demo schema is in place (4 tables, '
      || l_readings || ' readings).');
  else
    sys.dbms_output.put_line('6. FAILED: found ' || l_tables || ' of 4 demo tables.');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql.');
  end if;
end;
/

prompt
prompt ==========================================================
prompt  Every line above must start with a number and not FAILED.
prompt ==========================================================
prompt

set feedback on
