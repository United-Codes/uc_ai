-- ============================================================================
-- UC AI tutorial — "Give an Agent a Memory" — Lesson 4
-- A note the desk should not have believed
-- ============================================================================
-- Run 03_shape.sql first. The AS-14 store holds handover.txt, history.txt and
-- site_rules.txt, and the desk files under the plant's rules.
--
-- Five blocks:
--   1  Put a note in the history that WAS true and is not true any more.
--   2  Ask the question it answers wrongly.
--   3  Rank the tools above the memory, in the prompt.
--   4  Ask again.
--   5  Housekeeping, and the trace of the closing run.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200

variable sess_before varchar2(255)
variable sess_after  varchar2(255)

-- ---------------------------------------------------------------------------
-- 1. A note that was true in February
-- ---------------------------------------------------------------------------
-- This is seeded rather than earned, because earning it takes six months. It is
-- exactly what the desk would have written after WO-31240 in November 2025:
-- three failures on this pump, the same cause every time.
--
-- What the note does not say is what happened afterwards. In June 2026,
-- WO-31388 replaced that strainer with a self-cleaning unit and took the manual
-- cleaning off the plan. The two failures since then were the shaft coupling.
-- Every one of those facts is in mx_work_orders, and none of them is in the note.
prompt
prompt === 1. THE NOTE GOES IN ============================================
prompt

declare
  l_store_id number;
  c_history constant varchar2(1200 char) :=
'2026-02-10 - Flow drops on this pump are almost always the suction strainer
  clogging with label pulp. Check and clean the strainer FIRST, before anything
  else. Three occurrences in the last twelve months, the same cause every time.
2026-08-25 - Recurring drive-end vibration after coupling-elastomer replacements
  (2026-07-21 and 2026-08-14). Reliability requires the alignment measured cold
  before start-up, never after a run.';
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-14'
  );

  uc_ai_memory.put_file(
    p_store_id => l_store_id
  , p_path     => '/memories/history.txt'
  , p_content  => c_history
  );
  commit;
  sys.dbms_output.put_line('history.txt now carries the February note.');
end;
/

-- What the work orders say, so you can compare the two sources yourself.
prompt
prompt --- What mx_work_orders says about AS-14
select w.wo_no
     , to_char(w.opened_on, 'YYYY-MM-DD') as opened_on
     , w.cause
  from mx_work_orders w
 where w.asset_no = 'AS-14'
 order by w.opened_on;

-- ---------------------------------------------------------------------------
-- 2. The question the note answers wrongly
-- ---------------------------------------------------------------------------
prompt
prompt === 2. ASK BEFORE THE FIX ==========================================
prompt

declare
  l_result json_object_t;
begin
  :sess_before := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Sam"
    , "today": "2026-08-25"
    , "question": "Flow is dropping on this pump again and I can hear cavitation. Where do I start?"
    }')
  , p_session_id       => :sess_before
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"sam.o"}')
  );
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

prompt
prompt --- What that run read
select m.seq
     , json_value(m.tool_input, '$.command') as command
     , coalesce(json_value(m.tool_input, '$.path'), m.tool_name) as target
  from uc_ai_agent_messages m
 where m.role = 'tool_call'
   and m.session_id = :sess_before
 order by m.seq;

-- ---------------------------------------------------------------------------
-- 3. Rank the tools above the memory
-- ---------------------------------------------------------------------------
-- Memory is not a source of truth. It is what one conversation told another,
-- and nothing revisits it when the machine changes. The tables are the record.
-- Say so, in the prompt, and say what to do when the two disagree.
prompt
prompt === 3. ADD THE PRECEDENCE RULE =====================================
prompt

declare
  l_profile uc_ai_prompt_profiles%rowtype;

  c_system_prompt constant varchar2(4000 char) :=
'You are the maintenance desk of the Aldenbruck bottling plant, line LINE-2.
You help the technician {technician_name}, who is standing at one machine. Today is {today}.

Read the asset and its maintenance history before you answer. Be short and
practical: a technician is reading this on a tablet next to a running line.

WHAT TO TRUST
The tools are the record of this machine. Your memory is not: it holds what one
conversation told another, and nobody goes back to correct it when the machine
changes. So:
  - Always read the work orders before you act on anything your memory says
    about a cause, a part, or a procedure.
  - If your memory disagrees with a work order, the WORK ORDER wins.
  - When you find such a disagreement, say so in your answer, and correct the
    memory in the same run.
  - A note with no date, or a note older than the newest work order that
    contradicts it, is a suspect note.

MEMORY LAYOUT
Your memory holds one machine only, so never put an asset number in a file name.
Use these three files and no others:

  /memories/handover.txt    what the next shift must know NOW. Short. Current only.
  /memories/history.txt     what we have learned about this machine over time.
  /memories/site_rules.txt  written by the maintenance planner. READ IT, never write to it.

Start every line you add with the date as YYYY-MM-DD, then a space, then a dash.
Never record a phone number, a home address, or any other personal data. The
name of a technician on shift is fine.
When a line stops being true, replace or delete it. Do not append a correction
underneath it and leave both.';
begin
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('MX_DESK_PROFILE', 1);

  l_profile.system_prompt_template := c_system_prompt;
  uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_profile);
  commit;
  sys.dbms_output.put_line('Precedence rule added to MX_DESK_PROFILE version 1.');
end;
/

-- Put the stale note back, unchanged, so the two runs differ in ONE thing:
-- the prompt. If the run above already corrected the file, leaving it corrected
-- would make the comparison meaningless.
declare
  l_store_id number;
  c_history constant varchar2(1200 char) :=
'2026-02-10 - Flow drops on this pump are almost always the suction strainer
  clogging with label pulp. Check and clean the strainer FIRST, before anything
  else. Three occurrences in the last twelve months, the same cause every time.
2026-08-25 - Recurring drive-end vibration after coupling-elastomer replacements
  (2026-07-21 and 2026-08-14). Reliability requires the alignment measured cold
  before start-up, never after a run.';
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-14'
  );
  uc_ai_memory.put_file(
    p_store_id => l_store_id
  , p_path     => '/memories/history.txt'
  , p_content  => c_history
  );
  commit;
  sys.dbms_output.put_line('history.txt reset to the February note.');
end;
/

-- ---------------------------------------------------------------------------
-- 4. The same question, the same note, a new conversation
-- ---------------------------------------------------------------------------
prompt
prompt === 4. ASK AFTER THE FIX ===========================================
prompt

declare
  l_result json_object_t;
begin
  :sess_after := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Sam"
    , "today": "2026-08-25"
    , "question": "Flow is dropping on this pump again and I can hear cavitation. Where do I start?"
    }')
  , p_session_id       => :sess_after
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"sam.o"}')
  );
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

prompt
prompt --- history.txt after the run
declare
  l_store_id number;
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-14'
  );
  sys.dbms_output.put_line(uc_ai_memory.get_file(l_store_id, '/memories/history.txt'));
end;
/

-- ---------------------------------------------------------------------------
-- 5. Housekeeping, and the trace of the closing run
-- ---------------------------------------------------------------------------
-- expire_files deletes what nobody has touched. It is hygiene, not a control:
-- reading a file counts as touching it, so a stale note that the desk keeps
-- reading never expires. Only the precedence rule and a person deal with that.
prompt
prompt === 5. HOUSEKEEPING ===============================================
prompt

begin
  uc_ai_memory.expire_files(p_days => 180);
  commit;
  sys.dbms_output.put_line('Files untouched for 180 days are gone.');
end;
/

prompt
prompt --- Every store this desk holds
select f.store_key
     , f.path
     , f.char_count
     , to_char(f.last_accessed_at, 'YYYY-MM-DD HH24:MI') as last_read
  from uc_ai_v_memory_files f
 where f.agent_code = 'MX_DESK'
 order by f.store_key, f.path;

prompt
prompt --- What the closing run did
select m.seq
     , m.role
     , coalesce(m.tool_name, '-') as tool_name
     , coalesce(json_value(m.tool_input, '$.command'), '-') as memory_command
     , coalesce(json_value(m.tool_input, '$.path'), '-')    as memory_path
  from uc_ai_agent_messages m
 where m.session_id = :sess_after
 order by m.seq;

prompt
prompt --- And its execution row
select e.status
     , e.tool_calls_count    as calls
     , e.total_input_tokens  as in_tok
     , e.total_output_tokens as out_tok
     , e.created_by
     , e.run_context
  from uc_ai_agent_executions e
 where e.session_id = :sess_after;
