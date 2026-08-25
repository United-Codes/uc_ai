-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 1
-- Three ordinary tools, and the question that needs twenty-six calls
-- ============================================================================
-- Registers the three read tools of the cold-chain analyst and asks the batch
-- question with NORMAL tool calling, two times:
--
--   Run A  the default tool-call budget. It runs out, and the run raises
--          ORA-20301. There is no answer and no result object.
--   Run B  a budget of 40. It finishes. Look at what it costs.
--
-- Run B is the most expensive run of the whole course. It sends every reading of
-- every shipment through the context window, and the transcript is re-sent on
-- each round. If you do not want to pay for it, read the recorded numbers on the
-- lesson page instead and go to lesson 2.
--
-- Safe to run more than one time. merge_tool_from_schema replaces the tools.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- The three tools
-- ---------------------------------------------------------------------------
-- Nothing here is special. These are ordinary UC AI function tools, and lesson 2
-- changes none of them.
--
-- The tag is 'coldchain'. Tags are stored in LOWER CASE and the filter that
-- selects them is case sensitive, so always write the tag in lower case.
--
-- p_code_mode_access says where a tool can be called from. 'both' is the value a
-- new tool gets anyway, and this script states it because lesson 4 changes two of
-- these tools to 'code'. merge_tool_from_schema KEEPS the value a tool already
-- has when you leave the parameter out, so without this line a second run of this
-- script would not put the tools back.
declare
  l_tool_id number;
begin
  -- --- CC_LIST_SHIPMENTS ---------------------------------------------------
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'CC_LIST_SHIPMENTS'
  , p_description   => 'List every cold-chain shipment with its numeric id, its shipment '
                    || 'number, its carrier, its lane and its product class.'
  , p_function_call => 'return cc_analyst_pkg.list_shipments(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "product_class": { "type": "string", "description": "Optional filter: FROZEN or CHILLED." }
      },
      "required": []
    }')
  , p_tags          => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'both'
  );
  sys.dbms_output.put_line('CC_LIST_SHIPMENTS  id=' || l_tool_id);

  -- --- CC_GET_READINGS -----------------------------------------------------
  -- The bulk tool. 49 readings for each shipment, which is about 2 KB of JSON
  -- and about 500 tokens.
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'CC_GET_READINGS'
  , p_description   => 'Return the temperature readings of ONE shipment, in time order.'
  , p_function_call => 'return cc_analyst_pkg.get_readings(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "shipment_id": { "type": "integer", "description": "The numeric shipment_id from CC_LIST_SHIPMENTS. This is not the shipment number." }
      },
      "required": ["shipment_id"]
    }')
  , p_tags          => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'both'
  );
  sys.dbms_output.put_line('CC_GET_READINGS    id=' || l_tool_id);

  -- --- CC_GET_LIMITS -------------------------------------------------------
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'CC_GET_LIMITS'
  , p_description   => 'Return the temperature limit and the claim rule of each product class.'
  , p_function_call => 'return cc_analyst_pkg.get_limits(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {},
      "required": []
    }')
  , p_tags          => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'both'
  );
  sys.dbms_output.put_line('CC_GET_LIMITS      id=' || l_tool_id);

  commit;
end;
/

-- ---------------------------------------------------------------------------
-- The question
-- ---------------------------------------------------------------------------
-- The rule is in the system prompt and in CC_GET_LIMITS. The last line of the
-- answer is a RESULT line, so that grading the answer is a string comparison and
-- not an opinion.
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

  e_max_calls exception;
  pragma exception_init(e_max_calls, -20301);
begin
  -- Start from the framework defaults. The globals below live for the whole
  -- session, so a session that already ran lesson 2 would still have code mode on,
  -- and Run A would no longer show what it is here to show.
  uc_ai.reset_globals;

  uc_ai.g_enable_tools := true;
  uc_ai.g_tool_tags    := apex_t_varchar2('coldchain');

  -- --- Run A: the default budget -------------------------------------------
  -- Nothing sets max_tool_calls, so UC AI uses its default of 10. The question
  -- needs 26. Watch what that means: not a shorter answer, and not a warning.
  begin
    l_start := sys.dbms_utility.get_time;

    l_result := uc_ai.generate_text(
      p_user_prompt   => c_question
    , p_system_prompt => c_system
    , p_provider      => uc_ai.c_provider_anthropic
    , p_model         => uc_ai_anthropic.c_model_claude_4_6_sonnet
    );

    sys.dbms_output.put_line('Run A finished. That is not what this lesson expects.');
    sys.dbms_output.put_line(l_result.get_clob('final_message'));
  exception
    when e_max_calls then
      -- @dblinter ignore(g-5080): the message IS the lesson; a backtrace of the
      -- framework internals would not add anything for the reader
      l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);
      sys.dbms_output.put_line('Run A, default budget, after ' || l_seconds || ' seconds:');
      sys.dbms_output.put_line('  ' || substr(sqlerrm, 1, 200));
      sys.dbms_output.put_line(' ');
      sys.dbms_output.put_line('  There is no answer, no token count and no result object.');
      sys.dbms_output.put_line('  The run raised, so everything it already paid for is gone.');
  end;

  sys.dbms_output.put_line(' ');

  -- --- Run B: a budget large enough ----------------------------------------
  cc_analyst_pkg.print_header;

  l_start := sys.dbms_utility.get_time;

  l_result := uc_ai.generate_text(
    p_user_prompt    => c_question
  , p_system_prompt  => c_system
  , p_provider       => uc_ai.c_provider_anthropic
  , p_model          => uc_ai_anthropic.c_model_claude_4_6_sonnet
  , p_max_tool_calls => 40
  );

  l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);
  cc_analyst_pkg.print_metrics('classic, 40 calls', l_result, l_seconds);
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('--- answer of run B ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
-- Whatever the two runs above said, this is the answer. The rule is in SQL, and
-- the database is the only thing here that cannot be talked out of it.
set feedback off

prompt
prompt  The shipments that really broke the cold chain:
prompt

select s.shipment_no
     , cc_analyst_pkg.minutes_over(s.id) as minutes_over
     , ceil(cc_analyst_pkg.minutes_over(s.id) / 60) * l.claim_per_hour_eur as claim_eur
  from cc_shipments s
  join cc_limits l on l.product_class = s.product_class
 where cc_analyst_pkg.minutes_over(s.id) > 0
 order by s.shipment_no;

set feedback on
