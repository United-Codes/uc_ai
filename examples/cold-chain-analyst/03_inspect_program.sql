-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 3
-- Read the program, and see what every kind of mistake in it does
-- ============================================================================
-- Part 1 makes ONE code-mode call and prints the JavaScript the model wrote.
-- Part 2 runs seven programs of your own straight through the sandbox, with NO
-- model and NO cost. Five of them fail on purpose, one for each mistake a model
-- makes.
--
-- Safe to run more than one time.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- Part 1: the program the model wrote
-- ---------------------------------------------------------------------------
-- The program is an ordinary tool call. It sits in the messages array of the
-- result, in a content item of type 'tool_call' whose toolName is
-- uc_ai__run_code, and the source is the 'code' key of its arguments.
--
-- cc_analyst_pkg.program_source does that walk. Read its body: it is 30 lines,
-- and it is the same walk you need for any tool call you want to audit.
declare
  c_system constant clob :=
    'You are the cold-chain analyst of a pharmaceutical logistics operator.' || chr(10)
    || 'A shipment BREAKS THE COLD CHAIN when its temperature stays above the limit of' || chr(10)
    || 'its product class for LONGER than max_minutes_above, without interruption.' || chr(10)
    || 'One reading stands for sample_minutes minutes. Add up the minutes of the runs' || chr(10)
    || 'that are too long. The claim is ceil(total_minutes / 60) * claim_per_hour_eur.' || chr(10)
    || 'A single reading above the limit, or a run that is short enough, is not a break' || chr(10)
    || 'and is worth nothing.' || chr(10)
    || 'Examine EVERY shipment. End your answer with one line in exactly this form:' || chr(10)
    || 'RESULT: <shipment numbers, comma separated, or NONE> | <total claim in EUR>';

  l_result  json_object_t;
  l_program clob;
begin
  uc_ai.g_enable_tools              := true;
  uc_ai.g_tool_tags                 := apex_t_varchar2('coldchain');
  uc_ai.g_enable_programmatic_tools := true;

  l_result := uc_ai.generate_text(
    p_user_prompt   => 'Which shipments broke the cold chain, and what is the total claim in EUR?'
  , p_system_prompt => c_system
  , p_provider      => uc_ai.c_provider_anthropic
  , p_model         => uc_ai_anthropic.c_model_claude_4_6_sonnet
  );

  l_program := cc_analyst_pkg.program_source(l_result);

  if l_program is null then
    sys.dbms_output.put_line('The model wrote no program on this run. It called the tools '
      || 'one at a time. That is allowed: code mode is an offer, not an order.');
  else
    sys.dbms_output.put_line('--- the program the model wrote ---');
    sys.dbms_output.put_line(l_program);
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- Part 2: seven programs, no model
-- ---------------------------------------------------------------------------
-- execute_agent_tool is the same entry point a provider uses when the model asks
-- for uc_ai__run_code. Calling it yourself is the cheapest way to learn what the
-- sandbox does, because it needs no provider and costs nothing.
--
-- Read every line of output below. Five of the seven come back as errors, and
-- NONE of them raises. A code-mode failure is DATA that goes back to the model, so the model
-- can correct itself on the next turn. That also means your PL/SQL call succeeds
-- when the program failed: never read "no exception" as "it worked".
declare
  l_settings uc_ai_settings.t_settings;

  -- @dblinter ignore(g-7130): l_settings is the allow-list of this one run, and every
  -- program below is meant to run under exactly it
  procedure run_program(p_label in varchar2, p_code in clob)
  is
    l_args json_object_t := json_object_t();
    l_out  clob;
  begin
    l_args.put('code', p_code);
    l_out := uc_ai_tools_api.execute_agent_tool(
               uc_ai_tools_api.c_code_mode_tool_code, l_args, l_settings);
    sys.dbms_output.put_line(rpad(p_label, 22) || ' -> ' || substr(l_out, 1, 400));
    sys.dbms_output.put_line(' ');
  end run_program;
begin
  uc_ai.g_enable_tools              := true;
  uc_ai.g_tool_tags                 := apex_t_varchar2('coldchain');
  uc_ai.g_enable_programmatic_tools := true;

  -- The settings record carries the allow-list of this run. Build it from the
  -- globals you just set, exactly as generate_text does.
  l_settings := uc_ai_settings.build_from_globals;

  -- 1. A correct program. `result` is a top-level variable, and only its value
  --    goes back to the model.
  run_program('1 correct',
    'const limits = await callTool("CC_GET_LIMITS", {});' || chr(10)
    || 'const result = { classes: limits.length'
    || ', frozen: limits.find(l => l.product_class === "FROZEN").max_temp_c };');

  -- 2. The await is missing. UC AI inserts it, so this still works. The rewrite
  --    leaves strings, comments and member calls of the same name alone.
  run_program('2 forgotten await',
    'const limits = callTool("CC_GET_LIMITS", {});' || chr(10)
    || 'const result = { classes: limits.length };');

  -- 3. The same mistake behind an alias. No rewrite can find this one, so a
  --    Proxy on the promise raises instead of letting the model treat a promise
  --    as data. A wrong answer is worse than an error.
  run_program('3 aliased call',
    'const fetchIt = callTool;' || chr(10)
    || 'const limits = fetchIt("CC_GET_LIMITS", {});' || chr(10)
    || 'const result = { classes: limits.length };');

  -- 4. The program computed something and assigned nothing to `result`.
  run_program('4 no result',
    'const limits = await callTool("CC_GET_LIMITS", {});');

  -- 5. A program that logs and then throws. console.log is the only debugging
  --    channel a program has, and UC AI returns the captured lines with the
  --    error. A program that DOES assign `result` drops its log.
  run_program('5 log then throw',
    'console.log("fetched the limits");' || chr(10)
    || 'const limits = await callTool("CC_GET_LIMITS", {});' || chr(10)
    || 'const result = limits.map(l => l.product_class.toUpperCase().nope());');

  -- 6. A tool that does not exist. The allow-list answers, not the database.
  run_program('6 unknown tool',
    'const result = await callTool("CC_DELETE_EVERYTHING", {});');

  -- 7. The program does not parse at all.
  run_program('7 syntax error',
    'const result = { a: 1');
end;
/

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
-- Programs 3 to 7 all failed, and this script raised nothing. Prove that the
-- session is healthy and that no program left anything behind.
set feedback off

prompt
prompt  Claims filed by the seven programs above. It must be 0.
prompt

select count(*) as claims_filed from cc_claims;

set feedback on
