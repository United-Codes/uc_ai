-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 2
-- The same question, the same tools, one more line
-- ============================================================================
-- Asks exactly the question of lesson 1, against exactly the tools of lesson 1.
-- The only difference is one flag:
--
--   uc_ai.g_enable_programmatic_tools := true;
--
-- That flag adds one synthesized tool, uc_ai__run_code. The model can write a
-- small JavaScript program that calls your tools in a loop inside the database
-- and returns only its final result.
--
-- This script needs Oracle 23ai and the code-mode sandbox. Run 00_precheck.sql
-- first if you have not.
--
-- Safe to run more than one time. It registers nothing and changes nothing.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

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

  c_question constant clob :=
    'Which shipments broke the cold chain, and what is the total claim in EUR?';

  l_result  json_object_t;
  l_start   number;
  l_seconds number;
begin
  uc_ai.g_enable_tools              := true;
  uc_ai.g_tool_tags                 := apex_t_varchar2('coldchain');
  -- The one line that this whole lesson is about.
  uc_ai.g_enable_programmatic_tools := true;

  cc_analyst_pkg.print_header;

  l_start := sys.dbms_utility.get_time;

  l_result := uc_ai.generate_text(
    p_user_prompt   => c_question
  , p_system_prompt => c_system
  , p_provider      => uc_ai.c_provider_anthropic
  , p_model         => uc_ai_anthropic.c_model_claude_4_6_sonnet
  );

  l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);
  cc_analyst_pkg.print_metrics('code mode', l_result, l_seconds);

  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('--- answer ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- What the model was offered
-- ---------------------------------------------------------------------------
-- The meta-tool is not a setting on a tool. UC AI builds it while it assembles
-- the tool list, and it appends it ONLY when at least one of your tools is
-- callable from a program. Print the names to see it.
declare
  l_tools json_array_t;
  l_tool  json_object_t;
begin
  l_tools := uc_ai_tools_api.get_tools_array(
    p_provider           => uc_ai.c_provider_anthropic
  , p_tool_tags          => apex_t_varchar2('coldchain')
  , p_enable_tools       => true
  , p_programmatic_tools => true
  );

  sys.dbms_output.put_line('Tools the model sees with code mode on:');

  <<tool_loop>>
  for i in 0 .. l_tools.get_size - 1 loop
    l_tool := treat(l_tools.get(i) as json_object_t);
    sys.dbms_output.put_line('  ' || l_tool.get_string('name'));
  end loop tool_loop;
end;
/

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
set feedback off

prompt
prompt  The answer the database gives. Compare it with the RESULT line above.
prompt

select s.shipment_no
     , cc_analyst_pkg.minutes_over(s.id) as minutes_over
     , ceil(cc_analyst_pkg.minutes_over(s.id) / 60) * l.claim_per_hour_eur as claim_eur
  from cc_shipments s
  join cc_limits l on l.product_class = s.product_class
 where cc_analyst_pkg.minutes_over(s.id) > 0
 order by s.shipment_no;

set feedback on
