-- UC AI - Programmatic Tool Calling ("code mode") benchmark: fixture + runner
--
-- Installs into the UC AI schema:
--   * package UC_AI_PTC_BENCH - deterministic fixture data + the benchmark driver
--   * three tools tagged 'ptc_bench' that expose that data to a model
--
-- Run as the UC AI owner:   @scripts/ptc_benchmark/setup.sql
-- Then:                     @scripts/ptc_benchmark/run.sql
-- Remove again:             @scripts/ptc_benchmark/cleanup.sql
--
-- See README.md in this directory. The run makes real, paid LLM calls.

set define off

create or replace package uc_ai_ptc_bench as

  /**
  * UC AI - code mode benchmark
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  *
  * Reproduces the expense-analysis scenario from Anthropic's Programmatic Tool
  * Calling cookbook as UC AI tools, then answers the same question once with
  * classic tool calling and once with code mode, per provider, and reports tool
  * calls, token usage, wall-clock time and whether the answer was right.
  *
  * The data is deterministic, so the expected answer is known up front:
  * employee 10X has X approved travel expenses of X * 450 (plus pending travel
  * and non-travel noise rows), against a 5000 standard budget - except employee
  * 103 (custom 2000) and 107 (custom 25000).
  */

  -- tag the benchmark tools are registered under
  c_tag constant varchar2(30 char) := 'ptc_bench';

  -- Tool implementations (called through the registered tools' function_call)
  function get_team_members(p_args in clob) return clob;
  function get_expenses(p_args in clob) return clob;
  function get_custom_budget(p_args in clob) return clob;

  -- Employee ids that are over budget, comma separated and ascending.
  function expected_answer return varchar2;

  /*
   * Runs the scenario once and prints a single result line.
   *
   * @param p_label      label for the output line (e.g. 'anthropic sonnet-4-6')
   * @param p_provider   uc_ai.c_provider_*
   * @param p_model      model id
   * @param p_code_mode  true = offer the code-mode meta-tool, false = classic
   */
  procedure run_case(
    p_label     in varchar2
  , p_provider  in uc_ai.provider_type
  , p_model     in uc_ai.model_type
  , p_code_mode in boolean
  );

  /*
   * Runs every configured provider, classic and code mode.
   *
   * @param p_passes    how often to repeat the whole set (LLMs vary between runs)
   * @param p_provider  restrict to one uc_ai.c_provider_* value, null = all
   */
  procedure run_all(
    p_passes   in pls_integer default 1
  , p_provider in uc_ai.provider_type default null
  );

end uc_ai_ptc_bench;
/

create or replace package body uc_ai_ptc_bench as
  -- @dblinter ignore(g-5010): benchmark harness, prints to dbms_output instead of logging
  -- @dblinter ignore(g-4395): the fixture sizes are fixed on purpose so the expected answer stays literal

  gc_employees constant pls_integer := 8;
  gc_rows      constant pls_integer := 15;   -- expense rows per employee
  gc_standard  constant pls_integer := 5000; -- standard travel budget

  gc_question constant varchar2(1000 char) :=
    'Which members of the engineering team exceeded their Q3 travel budget? '
    || 'The standard travel budget is 5000 USD, but some employees have a custom budget that '
    || 'can be higher OR lower than the standard one, so look up the custom budget for every team member. '
    || 'Only count expenses with category "travel" and status "approved". '
    || 'End your answer with a final line in exactly this format: '
    || 'RESULT: <comma-separated employee ids, ascending>';

  gc_system constant varchar2(200 char) :=
    'You are a precise data analyst. Use the available tools to get the data you need.';

  function employee_name(p_idx in pls_integer) return varchar2;


  function employee_name(p_idx in pls_integer) return varchar2
  as
  begin
    return case p_idx
             when 1 then 'Ada Lovelace'
             when 2 then 'Grace Hopper'
             when 3 then 'Alan Turing'
             when 4 then 'Ken Thompson'
             when 5 then 'Barbara Liskov'
             when 6 then 'Linus Torvalds'
             when 7 then 'Margaret Hamilton'
             else        'Dennis Ritchie'
           end;
  end employee_name;

  function get_team_members(p_args in clob) return clob
  as
    l_arr json_array_t := json_array_t();
    l_obj json_object_t;
  begin
    <<member_loop>>
    for i in 1 .. gc_employees loop
      l_obj := json_object_t();
      l_obj.put('id', 100 + i);
      l_obj.put('name', employee_name(i));
      l_obj.put('department', 'engineering');
      l_obj.put('role', case when i <= 2 then 'staff engineer' else 'engineer' end);
      l_arr.append(l_obj);
    end loop member_loop;
    return l_arr.to_clob;
  end get_team_members;

  function get_expenses(p_args in clob) return clob
  as
    l_id  number;
    l_x   pls_integer;
    l_arr json_array_t := json_array_t();
    l_obj json_object_t;
  begin
    l_id := json_object_t(p_args).get_number('employee_id');
    l_x  := l_id - 100;

    <<expense_loop>>
    for i in 1 .. gc_rows loop
      l_obj := json_object_t();
      l_obj.put('expense_id', l_id * 1000 + i);
      l_obj.put('employee_id', l_id);
      l_obj.put('quarter', 'Q3');
      l_obj.put('date', to_char(date '2026-07-01' + i * 4, 'yyyy-mm-dd'));

      if i <= l_x then
        -- the rows that count
        l_obj.put('category', 'travel');
        l_obj.put('amount', l_x * 450);
        l_obj.put('status', 'approved');
      elsif i <= l_x + 3 then
        -- travel, but not approved
        l_obj.put('category', 'travel');
        l_obj.put('amount', 900);
        l_obj.put('status', 'pending');
      else
        -- approved, but not travel
        l_obj.put('category', case when mod(i, 2) = 0 then 'meals' else 'equipment' end);
        l_obj.put('amount', 120 + i * 7);
        l_obj.put('status', 'approved');
      end if;

      -- The metadata that makes a raw dump expensive: none of it is needed to
      -- answer the question, but in classic tool calling all of it reaches the
      -- model - and stays in the context for every following turn.
      l_obj.put('currency', 'USD');
      l_obj.put('merchant', 'Vendor ' || chr(64 + mod(i, 26) + 1) || ' International Travel & Logistics GmbH');
      l_obj.put('receipt_url', 'https://receipts.example.com/q3/' || l_id || '/' || i
                               || '/scan-' || lpad(to_char(l_id * 1000 + i), 12, '0') || '.pdf');
      l_obj.put('cost_center', 'CC-' || (4000 + mod(i, 7)));
      l_obj.put('project_code', 'PRJ-ENG-' || (mod(i, 5) + 1) || '-2026-Q3');
      l_obj.put('submitted_at', to_char(date '2026-07-01' + i * 4, 'yyyy-mm-dd')
                                || 'T09:' || lpad(mod(i * 7, 60), 2, '0') || ':00Z');
      l_obj.put('approval_chain', 'submitted by employee; reviewed by team lead (CC-' || (4000 + mod(i, 7))
                                  || '); finance check by accounts payable; policy version 2026.2 applied');
      l_obj.put('notes', 'Trip report attached. Booking made through the corporate travel portal, '
                         || 'fare class economy, cancellation policy flexible, VAT reclaim pending for invoice '
                         || (l_id * 1000 + i) || '.');
      l_arr.append(l_obj);
    end loop expense_loop;
    return l_arr.to_clob;
  end get_expenses;

  function get_custom_budget(p_args in clob) return clob
  as
    l_id  number;
    l_obj json_object_t := json_object_t();
  begin
    l_id := json_object_t(p_args).get_number('employee_id');
    l_obj.put('employee_id', l_id);
    case l_id
      when 107 then
        -- high enough that this employee is NOT over budget
        l_obj.put('travel_budget', 25000);
        l_obj.put('reason', 'conference speaker circuit');
      when 103 then
        -- low enough that this employee IS over budget, although below standard
        l_obj.put('travel_budget', 2000);
        l_obj.put('reason', 'part time');
      else
        l_obj.put_null('travel_budget');
        l_obj.put('reason', 'standard budget applies');
    end case;
    return l_obj.to_clob;
  end get_custom_budget;

  function expected_answer return varchar2
  as
    l_out varchar2(200 char);
    l_travel pls_integer;
    l_budget pls_integer;
  begin
    <<expected_loop>>
    for i in 1 .. gc_employees loop
      l_travel := i * i * 450;
      l_budget := case 100 + i when 103 then 2000 when 107 then 25000 else gc_standard end;
      if l_travel > l_budget then
        l_out := l_out || case when l_out is not null then ',' end || (100 + i);
      end if;
    end loop expected_loop;
    return l_out;
  end expected_answer;


  procedure run_case(
    p_label     in varchar2
  , p_provider  in uc_ai.provider_type
  , p_model     in uc_ai.model_type
  , p_code_mode in boolean
  )
  as
    l_res      json_object_t;
    l_msg      clob;
    l_answer   varchar2(200 char);
    l_start    number;
    l_secs     number;
    l_used     boolean := false;
    l_mode     varchar2(10 char) := case when p_code_mode then 'code' else 'classic' end;
  begin
    uc_ai.reset_globals;
    uc_ai.g_enable_tools     := true;
    uc_ai.g_tool_tags        := apex_t_varchar2(c_tag);
    uc_ai.g_enable_programmatic_tools := p_code_mode;

    l_start := sys.dbms_utility.get_time;
    l_res := uc_ai.generate_text(
      p_user_prompt    => gc_question
    , p_system_prompt  => gc_system
    , p_provider       => p_provider
    , p_model          => p_model
    , p_max_tool_calls => 30
    );
    l_secs := round((sys.dbms_utility.get_time - l_start) / 100, 1);

    l_msg := l_res.get_clob('final_message');
    -- the model states its verdict on a RESULT: line
    l_answer := regexp_replace(regexp_substr(l_msg, 'RESULT:[^' || chr(10) || ']*'), '[^0-9,]');
    l_answer := trim(both ',' from regexp_replace(l_answer, ',+', ','));

    -- did it actually write a program, or just call tools one by one?
    if instr(l_res.get_array('messages').to_clob, uc_ai_tools_api.c_code_mode_tool_code) > 0 then
      l_used := true;
    end if;

    sys.dbms_output.put_line(
      rpad(p_label, 30) || ' | ' || rpad(l_mode, 7)
      || ' | program: ' || rpad(case when l_used then 'yes' else 'no' end, 3)
      || ' | calls: ' || lpad(l_res.get_number('tool_calls_count'), 2)
      || ' | tokens: ' || lpad(l_res.get_object('usage').get_number('total_tokens'), 7)
      || ' | ' || lpad(l_secs, 5) || 's'
      || ' | ' || rpad(nvl(l_answer, '?'), 25)
      || ' | ' || case when l_answer = expected_answer then 'correct' else 'WRONG' end
    );
  exception
    -- @dblinter ignore(g-5040): one provider failing must not stop the benchmark
    -- @dblinter ignore(g-5080): the provider's own message is what matters here
    when others then
      sys.dbms_output.put_line(
        rpad(p_label, 30) || ' | ' || rpad(l_mode, 7) || ' | FAILED: '
        || replace(substr(sqlerrm, 1, 300), chr(10), ' '));
  end run_case;


  procedure run_all(
    p_passes   in pls_integer default 1
  , p_provider in uc_ai.provider_type default null
  )
  as
    procedure maybe(
      p_label    in varchar2
    , p_provider in uc_ai.provider_type
    , p_model    in uc_ai.model_type
    )
    as
    begin
      if p_provider is null or run_all.p_provider = maybe.p_provider then
        run_case(p_label, maybe.p_provider, p_model, false);
        run_case(p_label, maybe.p_provider, p_model, true);
      end if;
    end maybe;
  begin
    sys.dbms_output.put_line('expected answer: ' || expected_answer);

    <<pass_loop>>
    for l_pass in 1 .. nvl(p_passes, 1) loop
      sys.dbms_output.put_line('--- pass ' || l_pass || ' of ' || nvl(p_passes, 1) || ' ---');

      maybe('anthropic claude-sonnet-4-6', uc_ai.c_provider_anthropic, uc_ai_anthropic.c_model_claude_4_6_sonnet);
      maybe('openai gpt-5-mini',           uc_ai.c_provider_openai,    uc_ai_openai.c_model_gpt_5_mini);
      maybe('google gemini-3-flash',       uc_ai.c_provider_google,    uc_ai_google.c_model_gemini_3_flash);
      maybe('xai grok-4-fast',             uc_ai.c_provider_xai,       uc_ai_xai.c_model_grok_4_fast);
      maybe('mistral mistral-medium',      uc_ai.c_provider_mistral,   uc_ai_mistral.c_model_mistral_medium);
    end loop pass_loop;

    uc_ai.reset_globals;
  end run_all;

end uc_ai_ptc_bench;
/


-- Register the three tools the scenario needs. Note the documented return shapes:
-- the code catalog only lists parameter names, so telling the model what a tool
-- gives back saves it a round-trip of guessing (or an empty aggregate).
declare
  l_id uc_ai_tools.id%type;
begin
  delete from uc_ai_tools where code like 'BENCH_%';

  l_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'BENCH_GET_TEAM_MEMBERS'
  , p_description   => 'List all members of a department. Returns [{ id, name, department, role }].'
  , p_function_call => 'return uc_ai_ptc_bench.get_team_members(:parameters);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{"department":{"type":"string","description":"Department name, e.g. engineering"}},"required":["department"]}')
  , p_created_by    => 'UC_AI_PTC_BENCH'
  , p_tags          => apex_t_varchar2(uc_ai_ptc_bench.c_tag)
  );

  l_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'BENCH_GET_EXPENSES'
  , p_description   => 'All expense line items of one employee for a quarter. '
                       || 'Returns [{ expense_id, employee_id, category, amount, status, ... }].'
  , p_function_call => 'return uc_ai_ptc_bench.get_expenses(:parameters);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{"employee_id":{"type":"integer","description":"Employee id"},"quarter":{"type":"string","description":"Quarter, e.g. Q3"}},"required":["employee_id","quarter"]}')
  , p_created_by    => 'UC_AI_PTC_BENCH'
  , p_tags          => apex_t_varchar2(uc_ai_ptc_bench.c_tag)
  );

  l_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'BENCH_GET_CUSTOM_BUDGET'
  , p_description   => 'Custom travel budget of one employee. '
                       || 'Returns { employee_id, travel_budget, reason } - travel_budget is null when the standard budget applies.'
  , p_function_call => 'return uc_ai_ptc_bench.get_custom_budget(:parameters);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{"employee_id":{"type":"integer","description":"Employee id"}},"required":["employee_id"]}')
  , p_created_by    => 'UC_AI_PTC_BENCH'
  , p_tags          => apex_t_varchar2(uc_ai_ptc_bench.c_tag)
  );

  commit;
end;
/

prompt UC AI code-mode benchmark installed. Run it with @scripts/ptc_benchmark/run.sql
