-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 4
-- The catalog is the only documentation the program gets
-- ============================================================================
-- Prints the tool catalog that UC AI puts inside the uc_ai__run_code
-- description, then corrects the three tool descriptions and narrows the two
-- bulk tools to 'code'. Ends with the size limit of the catalog.
--
-- Safe to run more than one time. Every registration is a merge, and the
-- oversized test tool at the end is deleted again.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- What the program is told
-- ---------------------------------------------------------------------------
-- The catalog is not a schema. It is one line for each tool: the tool code, the
-- names of the arguments, and the full description. There are no types, no
-- required flags, and NOTHING about the shape of the result.
-- @dblinter ignore(g-2160): a local function keeps the provider difference below in one place
declare
  l_tools json_array_t;
  l_tool  json_object_t;

  -- The schema key is not the same for all providers. Anthropic and OpenAI use
  -- 'input_schema'; Google, Ollama, xAI, OpenRouter and Mistral use 'parameters'.
  function code_parameter_description(p_tool in json_object_t) return clob
  is
    l_schema json_object_t := p_tool.get_object('input_schema');
  begin
    if l_schema is null then
      l_schema := p_tool.get_object('parameters');
    end if;

    return l_schema.get_object('properties').get_object('code').get_clob('description');
  end code_parameter_description;
begin
  l_tools := uc_ai_tools_api.get_tools_array(
    p_provider           => uc_ai.c_provider_anthropic
  , p_tool_tags          => apex_t_varchar2('coldchain')
  , p_enable_tools       => true
  , p_programmatic_tools => true
  );

  <<tool_loop>>
  for i in 0 .. l_tools.get_size - 1 loop
    l_tool := treat(l_tools.get(i) as json_object_t);

    if l_tool.get_string('name') = uc_ai_tools_api.c_code_mode_tool_code then
      sys.dbms_output.put_line('--- the description of ' || l_tool.get_string('name') || ' ---');
      sys.dbms_output.put_line(code_parameter_description(l_tool));
    end if;
  end loop tool_loop;
end;
/

-- ---------------------------------------------------------------------------
-- Correct the descriptions
-- ---------------------------------------------------------------------------
-- Every description below now names the fields the tool RETURNS. That is the
-- part a program cannot guess and cannot discover, because it never sees an
-- example result before it writes the code that reads one.
--
-- The two bulk tools also become 'code'. They leave the tool list of the model,
-- so their output can no longer reach the context window at all. Only a program
-- can call them.
declare
  l_tool_id number;
begin
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code        => 'CC_LIST_SHIPMENTS'
  , p_description      => 'List every cold-chain shipment. Returns an array of '
                       || '{ shipment_id, shipment_no, carrier, lane, product_class, departed_at }. '
                       || 'shipment_id is the number you pass to CC_GET_READINGS. shipment_no is the '
                       || 'label a person reads, for example SHP-2047. product_class is FROZEN or '
                       || 'CHILLED. Optional argument product_class filters the list.'
  , p_function_call    => 'return cc_analyst_pkg.list_shipments(:ARGUMENTS);'
  , p_json_schema      => json_object_t('{
      "type": "object",
      "properties": {
        "product_class": { "type": "string", "description": "Optional filter: FROZEN or CHILLED." }
      },
      "required": []
    }')
  , p_tags             => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'code'
  );
  sys.dbms_output.put_line('CC_LIST_SHIPMENTS  id=' || l_tool_id || '  access=code');

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code        => 'CC_GET_READINGS'
  , p_description      => 'Return the temperature readings of ONE shipment, in time order. '
                       || 'Argument shipment_id is the numeric shipment_id from CC_LIST_SHIPMENTS, '
                       || 'not the shipment number. Returns { shipment_id, readings } where readings '
                       || 'is an array of { ts, temp_c }, about 49 rows. temp_c is degrees Celsius '
                       || 'and ts is the time of the reading.'
  , p_function_call    => 'return cc_analyst_pkg.get_readings(:ARGUMENTS);'
  , p_json_schema      => json_object_t('{
      "type": "object",
      "properties": {
        "shipment_id": { "type": "integer", "description": "The numeric shipment_id from CC_LIST_SHIPMENTS." }
      },
      "required": ["shipment_id"]
    }')
  , p_tags             => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'code'
  );
  sys.dbms_output.put_line('CC_GET_READINGS    id=' || l_tool_id || '  access=code');

  -- This one stays available both ways. It returns two small rows, so it costs
  -- almost nothing in the context, and a person may want to ask about it.
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code        => 'CC_GET_LIMITS'
  , p_description      => 'Return the limit and the claim rule of each product class. Returns an '
                       || 'array of { product_class, max_temp_c, sample_minutes, max_minutes_above, '
                       || 'claim_per_hour_eur }. max_temp_c is the highest allowed temperature in '
                       || 'Celsius. One reading stands for sample_minutes minutes. A run of readings '
                       || 'above max_temp_c that lasts longer than max_minutes_above breaks the cold '
                       || 'chain. Compare with the temp_c of CC_GET_READINGS.'
  , p_function_call    => 'return cc_analyst_pkg.get_limits(:ARGUMENTS);'
  , p_json_schema      => json_object_t('{
      "type": "object",
      "properties": {},
      "required": []
    }')
  , p_tags             => apex_t_varchar2('coldchain')
  , p_code_mode_access => 'both'
  );
  sys.dbms_output.put_line('CC_GET_LIMITS      id=' || l_tool_id || '  access=both');

  commit;
end;
/

-- ---------------------------------------------------------------------------
-- What the model sees now
-- ---------------------------------------------------------------------------
-- Two tools left the direct list. They are still in the catalog, so a program
-- can call them, and nothing else can.
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

  sys.dbms_output.put_line('Tools the model can call directly:');

  <<tool_loop>>
  for i in 0 .. l_tools.get_size - 1 loop
    l_tool := treat(l_tools.get(i) as json_object_t);
    sys.dbms_output.put_line('  ' || l_tool.get_string('name'));
  end loop tool_loop;
end;
/

-- ---------------------------------------------------------------------------
-- The same question again
-- ---------------------------------------------------------------------------
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
  l_start   number;
  l_seconds number;
begin
  uc_ai.g_enable_tools              := true;
  uc_ai.g_tool_tags                 := apex_t_varchar2('coldchain');
  uc_ai.g_enable_programmatic_tools := true;

  l_start := sys.dbms_utility.get_time;

  l_result := uc_ai.generate_text(
    p_user_prompt   => 'Which shipments broke the cold chain, and what is the total claim in EUR?'
  , p_system_prompt => c_system
  , p_provider      => uc_ai.c_provider_anthropic
  , p_model         => uc_ai_anthropic.c_model_claude_4_6_sonnet
  );

  l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);

  cc_analyst_pkg.print_header;
  cc_analyst_pkg.print_metrics('code, bulk hidden', l_result, l_seconds);

  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('--- the program ---');
  sys.dbms_output.put_line(cc_analyst_pkg.program_source(l_result));
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('--- last line of the answer ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- The catalog has a size limit
-- ---------------------------------------------------------------------------
-- The whole catalog has to fit in the description of ONE tool, so UC AI gives it
-- about 31 KB. One description cannot fill that alone: uc_ai_tools.description
-- holds 4000 characters. About eight of that size can.
--
-- A tool that no longer fits is LEFT OUT. It is not in the catalog, a program
-- cannot call it, nothing fails, and the only sign is a warning in the log.
--
-- Register nine filler tools with 3900 characters of padding each, then
-- count what survived. This costs nothing: no model is called.
--
-- The COUNT that is left out follows from the sizes. WHICH tools are left out
-- does not: the query that reads the tools has no order by, so the answer depends
-- on where the rows sit. A second database with the same tools drops a different
-- pair. That is the finding.
declare
  c_fillers constant pls_integer := 9;
  l_tools    json_array_t;
  l_tool     json_object_t;
  l_catalog  clob;
  -- @dblinter ignore(g-2135): merge_tool_from_schema is a function, and the tool row is
  -- what this loop wants, not the id it returns
  l_ignore   number;
  l_expected pls_integer := 0;
  l_in_cat   pls_integer := 0;
  l_missing  varchar2(4000 char);

  -- @dblinter ignore(g-7130): account_for is an accumulator over the three counters
  -- and the catalog of this one block. Parameters would only repeat them twelve times.
  procedure account_for(p_code in varchar2)
  is
  begin
    l_expected := l_expected + 1;

    -- Match the callTool line, not the bare code: one description names another
    -- tool, so a bare instr would report a dropped tool as present.
    if instr(l_catalog, 'callTool("' || p_code || '"') > 0 then
      l_in_cat := l_in_cat + 1;
    else
      l_missing := l_missing || case when l_missing is null then null else ', ' end || p_code;
    end if;
  end account_for;
begin
  <<filler_loop>>
  for i in 1 .. c_fillers loop
    l_ignore := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code        => 'CC_FILLER_' || i
    , p_description      => 'Filler tool number ' || i || '. ' || rpad('x', 3900, 'x')
    , p_function_call    => 'return cc_analyst_pkg.get_limits(:ARGUMENTS);'
    , p_json_schema      => json_object_t('{"type":"object","properties":{},"required":[]}')
    , p_tags             => apex_t_varchar2('coldchain')
    , p_code_mode_access => 'code'
    );
  end loop filler_loop;

  l_tools := uc_ai_tools_api.get_tools_array(
    p_provider           => uc_ai.c_provider_anthropic
  , p_tool_tags          => apex_t_varchar2('coldchain')
  , p_enable_tools       => true
  , p_programmatic_tools => true
  );

  <<tool_loop>>
  for i in 0 .. l_tools.get_size - 1 loop
    l_tool := treat(l_tools.get(i) as json_object_t);

    if l_tool.get_string('name') = uc_ai_tools_api.c_code_mode_tool_code then
      l_catalog := l_tool.get_object('input_schema').get_object('properties')
                     .get_object('code').get_clob('description');
    end if;
  end loop tool_loop;

  account_for('CC_LIST_SHIPMENTS');
  account_for('CC_GET_READINGS');
  account_for('CC_GET_LIMITS');

  <<report_loop>>
  for i in 1 .. c_fillers loop
    account_for('CC_FILLER_' || i);
  end loop report_loop;

  -- This is the WHOLE description of the code parameter: the fixed preamble of
  -- about 900 characters, and then the catalog. The budget applies to the catalog.
  sys.dbms_output.put_line('preamble + catalog:  ' || sys.dbms_lob.getlength(l_catalog)
    || ' characters');
  sys.dbms_output.put_line('code-callable tools: ' || l_expected);
  sys.dbms_output.put_line('in the catalog:      ' || l_in_cat);
  sys.dbms_output.put_line('LEFT OUT:            ' || (l_expected - l_in_cat)
    || '  (' || l_missing || ')');
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('Nothing failed, and no tool in that last line is callable');
  sys.dbms_output.put_line('from a program. The log holds the only warning.');
  sys.dbms_output.put_line('The NAMES on that line are not predictable. Another database');
  sys.dbms_output.put_line('with the same tools leaves out a different pair.');

  -- Take them away again. There is no delete_tool API: a tool is a row.
  delete from uc_ai_tool_parameters
   where tool_id in (select t.id from uc_ai_tools t where t.code like 'CC\_FILLER\_%' escape '\');
  delete from uc_ai_tool_tags
   where tool_id in (select t.id from uc_ai_tools t where t.code like 'CC\_FILLER\_%' escape '\');
  delete from uc_ai_tools where code like 'CC\_FILLER\_%' escape '\';
  commit;

  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('The nine filler tools are removed again.');
end;
/

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
set feedback off

prompt
prompt  Where each tool can be called from:
prompt

select code, code_mode_access, active
  from uc_ai_tools
 where code like 'CC\_%' escape '\'
 order by code;

set feedback on
