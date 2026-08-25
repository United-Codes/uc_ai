-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 5
-- What the program cannot do
-- ============================================================================
-- Five proofs. NONE of them calls a model, so all five cost nothing:
--
--   1. A program cannot call a 'direct' tool, whatever it writes.
--   2. A program has no SQL, and therefore no COMMIT and no ROLLBACK.
--   3. The before_tool_call hook fires for EVERY callTool inside a program.
--   4. A veto from the hook stops the whole request, and the program cannot
--      catch its way past it.
--   5. The inner call budget stops a runaway loop at 100 calls.
--
-- Run cc_hook_pkg.sql first: this script needs that package.
--
-- This whole script calls no model, so it costs nothing.
--
-- Safe to run more than one time. It clears the hook at the end and rolls back
-- the one row it writes.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- The one tool that writes
-- ---------------------------------------------------------------------------
-- CC_FILE_CLAIM is registered as 'direct'. The model can call it. A program
-- cannot, whatever the program writes and whether or not the model knows the
-- tool code.
--
-- This is the division of labour code mode wants: the PROGRAM computes over
-- large data, the MODEL decides what to do with the small result, and the
-- DATABASE decides whether the decision is allowed.
declare
  l_tool_id number;
begin
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code        => 'CC_FILE_CLAIM'
  , p_description      => 'File one claim against one shipment that broke the cold chain. '
                       || 'Arguments: shipment_id (numeric id), minutes_over (total minutes '
                       || 'of the runs that were too long), amount_eur, and an optional note. '
                       || 'The database checks the readings and refuses a claim that does not '
                       || 'match them.'
  , p_function_call    => 'return cc_analyst_pkg.file_claim(:ARGUMENTS);'
  , p_json_schema      => json_object_t('{
      "type": "object",
      "properties": {
        "shipment_id":  { "type": "integer", "description": "Numeric shipment id." },
        "minutes_over": { "type": "integer", "description": "Total minutes in runs longer than max_minutes_above." },
        "amount_eur":   { "type": "number",  "description": "ceil(minutes_over / 60) * claim_per_hour_eur." },
        "note":         { "type": "string",  "description": "Optional free text." }
      },
      "required": ["shipment_id", "minutes_over", "amount_eur"]
    }')
  , p_tags             => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'direct'
  );
  commit;
  sys.dbms_output.put_line('CC_FILE_CLAIM      id=' || l_tool_id || '  access=direct');
end;
/

-- ---------------------------------------------------------------------------
-- The five checks, none of which calls a model
-- ---------------------------------------------------------------------------
declare
  l_settings uc_ai_settings.t_settings;
  l_pending  pls_integer;

  -- ORA-20503 is the code UC AI raises for a vetoed code-mode tool call.
  e_veto exception;
  pragma exception_init(e_veto, -20503);

  -- @dblinter ignore(g-7130): l_settings is the allow-list of this one run, and every
  -- program below is meant to run under exactly it
  function run_program(p_code in clob) return clob
  is
    l_args json_object_t := json_object_t();
  begin
    l_args.put('code', p_code);
    return uc_ai_tools_api.execute_agent_tool(
             uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);
  end run_program;
begin
  uc_ai.g_enable_tools              := true;
  uc_ai.g_tool_tags                 := apex_t_varchar2('coldchain');
  uc_ai.g_enable_programmatic_tools := true;
  l_settings := uc_ai_settings.build_from_globals;

  -- --- 1. The allow-list -------------------------------------------------
  -- Shipment id 7 is SHP-2047, the first shipment that broke the cold chain.
  sys.dbms_output.put_line('1. A program calls the write tool by its exact code:');
  sys.dbms_output.put_line('   ' || substr(
    run_program('const result = await callTool("CC_FILE_CLAIM", '
      || '{ shipment_id: 7, minutes_over: 150, amount_eur: 720 });'), 1, 260));
  sys.dbms_output.put_line(' ');

  -- --- 2. No SQL, and therefore no transaction control --------------------
  -- Write a row first and do NOT commit it. If the program could reach SQL, it
  -- could also roll this back, and no privilege would stop it: transaction
  -- control needs none.
  insert into cc_claims (shipment_id, minutes_over, amount_eur, note)
  values (7, 150, 720, 'uncommitted marker of lesson 5');

  sys.dbms_output.put_line('2. A program tries to reach the database:');
  sys.dbms_output.put_line('   ' || substr(
    run_program(q'~
      const probe = {};
      try { probe.require = typeof require("mle-js-oracledb"); } catch (e) { probe.require = "blocked"; }
      try { await import("mle-js-oracledb"); probe.import = "reached"; } catch (e) { probe.import = "blocked"; }
      probe.globals = [typeof oracledb, typeof session, typeof soda, typeof plsffi].join(",");
      const result = probe;
    ~'), 1, 260));

  -- @dblinter ignore(g-8110): a presence check; a scalar count is the clearest form here
  select count(*) into l_pending from cc_claims where note = 'uncommitted marker of lesson 5';
  sys.dbms_output.put_line('   the uncommitted row of the caller is still pending: '
    || case when l_pending = 1 then 'yes' else 'NO' end);
  rollback;
  sys.dbms_output.put_line('   rolled back again, so the claims table is empty.');
  sys.dbms_output.put_line(' ');

  -- --- 3. The hook fires for every inner call -----------------------------
  uc_ai_agents_api.set_execution_hook('CC_HOOK_PKG');
  cc_hook_pkg.reset;

  sys.dbms_output.put_line('3. A program reads every shipment in one call:');
  sys.dbms_output.put_line('   ' || substr(
    run_program(q'~
      const shipments = await callTool("CC_LIST_SHIPMENTS", {});
      let readings = 0;
      for (const s of shipments) {
        const r = await callTool("CC_GET_READINGS", { shipment_id: s.shipment_id });
        readings += r.readings.length;
      }
      const result = { shipments: shipments.length, readings };
    ~'), 1, 200));
  sys.dbms_output.put_line('   before_tool_call fired ' || cc_hook_pkg.g_calls || ' times.');
  sys.dbms_output.put_line('   That is one for CC_LIST_SHIPMENTS and one for each of the 24');
  sys.dbms_output.put_line('   CC_GET_READINGS calls. The call to the program itself is not in');
  sys.dbms_output.put_line('   this count, because this block calls the sandbox directly. In a');
  sys.dbms_output.put_line('   model run the provider fires the hook for uc_ai__run_code as well,');
  sys.dbms_output.put_line('   so the number there is 26.');
  sys.dbms_output.put_line(' ');

  -- --- 4. A veto stops the request ----------------------------------------
  cc_hook_pkg.reset;
  cc_hook_pkg.g_block_tool := 'CC_GET_READINGS';

  sys.dbms_output.put_line('4. The hook now refuses CC_GET_READINGS, and the program '
    || 'catches the error:');
  begin
    sys.dbms_output.put_line('   ' || substr(
      run_program(q'~
        let caught = "no";
        try {
          await callTool("CC_GET_READINGS", { shipment_id: 7 });
        } catch (e) {
          caught = "yes";
        }
        const result = { the_program_carried_on: caught };
      ~'), 1, 200));
  exception
    when e_veto then
      -- @dblinter ignore(g-5080): the message IS the proof; a backtrace of the
      -- framework internals adds nothing for the reader
      sys.dbms_output.put_line('   ' || substr(sqlerrm, 1, 220));
      sys.dbms_output.put_line('   The program finished. The request did not.');
    when others then
      -- @dblinter ignore(g-5040): anything other than the veto means this check did
      -- not prove what it claims, so say so instead of presenting it as the veto
      -- @dblinter ignore(g-5080): the reader needs the message, not a backtrace
      sys.dbms_output.put_line('   This is NOT the veto. Check 4 did not prove anything:');
      sys.dbms_output.put_line('   ' || substr(sqlerrm, 1, 220));
  end;

  cc_hook_pkg.reset;
  uc_ai_agents_api.set_execution_hook(null);
  sys.dbms_output.put_line(' ');

  -- --- 5. The call budget --------------------------------------------------
  -- 100 inner calls for one program. It is a constant, not a setting. A program
  -- may catch the error and go on calling, so the runner has a second, hard
  -- ceiling of 1000 serviced calls behind it.
  sys.dbms_output.put_line('5. A program that asks for 150 tool calls:');
  sys.dbms_output.put_line('   ' || substr(
    run_program(q'~
      let ok = 0;
      let stoppedAt = null;
      for (let i = 0; i < 150; i++) {
        try {
          await callTool("CC_GET_LIMITS", {});
          ok++;
        } catch (e) {
          stoppedAt = i;
          break;
        }
      }
      const result = { calls_that_worked: ok, stopped_at_call: stoppedAt };
    ~'), 1, 260));
end;
/

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
-- Nothing above called a model, and nothing above wrote a row. The five checks
-- ran 8 programs between them, and the claims table is still empty.
--
-- Lesson 6 gives CC_FILE_CLAIM to the agent, and the claims arrive there.
set feedback off

prompt
prompt  Claims written by the five checks. It must be 0.
prompt

select count(*) as claims_filed from cc_claims;

prompt
prompt  Where each tool can be called from. CC_FILE_CLAIM must say 'direct'.
prompt

select code, code_mode_access
  from uc_ai_tools
 where code like 'CC\_%' escape '\'
 order by code;

set feedback on
