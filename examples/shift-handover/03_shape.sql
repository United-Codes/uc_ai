-- ============================================================================
-- UC AI tutorial — "Give an Agent a Memory" — Lesson 3
-- Decide what the desk writes down
-- ============================================================================
-- Run 02_stores.sql first. Memory is scoped to one store per asset.
--
-- Five blocks:
--   1  The file names the desk has chosen for itself so far.
--   2  The MEMORY PROTOCOL it is working from, in full.
--   3  Filing rules of your own, in the prompt profile.
--   4  A reference note the planner writes, with put_file.
--   5  Two conversations under the rules, and what the store looks like after.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200

variable sess_night varchar2(255)

-- ---------------------------------------------------------------------------
-- 1. What the desk called things
-- ---------------------------------------------------------------------------
prompt
prompt === 1. THE FILE NAMES THE DESK CHOSE ===============================
prompt

select f.store_key
     , f.path
     , f.char_count
     , to_char(f.created_at, 'YYYY-MM-DD HH24:MI') as created_at
  from uc_ai_v_memory_files f
 where f.agent_code = 'MX_DESK'
 order by f.store_key, f.path;

-- ---------------------------------------------------------------------------
-- 2. The instructions it is working from
-- ---------------------------------------------------------------------------
-- This block is appended to the rendered system prompt of every memory-enabled
-- agent. It is the same text for every agent in every installation, and there
-- is no parameter that changes it.
prompt
prompt === 2. THE MEMORY PROTOCOL =========================================
prompt

declare
  l_protocol clob := uc_ai_memory.get_memory_protocol;
begin
  sys.dbms_output.put_line('Length: ' || sys.dbms_lob.getlength(l_protocol) || ' characters.');
  sys.dbms_output.put_line(l_protocol);
end;
/

-- ---------------------------------------------------------------------------
-- 3. Filing rules of your own
-- ---------------------------------------------------------------------------
-- The protocol says "keep memory organized". It cannot say what organized means
-- at your plant, because it does not know your plant. That part is yours, and
-- it belongs in the system prompt of the profile.
prompt
prompt === 3. ADD THE FILING RULES ========================================
prompt

-- Read the profile, set the new system prompt, and put the row back. The other
-- columns, including the memory tool tag that lesson 1 put there, stay as they are.
declare
  l_profile uc_ai_prompt_profiles%rowtype;

  c_system_prompt constant varchar2(4000 char) :=
'You are the maintenance desk of the Aldenbruck bottling plant, line LINE-2.
You help the technician {technician_name}, who is standing at one machine. Today is {today}.

Read the asset and its maintenance history before you answer. Be short and
practical: a technician is reading this on a tablet next to a running line.

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
  sys.dbms_output.put_line('Filing rules added to MX_DESK_PROFILE version 1.');

  -- Read it back: the memory tool tag from lesson 1 is still there.
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('MX_DESK_PROFILE', 1);
  sys.dbms_output.put_line('Tool tags kept: ' || l_profile.model_config_json);
end;
/

-- The store keeps the names the desk chose before the rules existed. Nothing
-- migrates them, and asking a model to tidy its own filing is not something you
-- can verify. Adopt a layout on a store you have emptied.
declare
  l_store_id number;
  e_no_store exception;
  pragma exception_init(e_no_store, -20423);
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-14'
  );
  uc_ai_memory.clear_store_files(l_store_id);
  commit;
  sys.dbms_output.put_line('Emptied the AS-14 store, id=' || l_store_id || '.');
exception
  when e_no_store then
    sys.dbms_output.put_line('AS-14 has no store yet.');
end;
/

-- ---------------------------------------------------------------------------
-- 4. A reference note the planner writes
-- ---------------------------------------------------------------------------
-- Nothing says the agent has to be the only author. put_file writes into the
-- same filesystem, so the planner can put standing site rules where the desk
-- will read them.
--
-- One constraint: a store exists from its FIRST use. resolve_store_id raises
-- ORA-20423 for a machine the desk has never run on, so there is nothing to
-- seed yet for such a machine. The AS-14 store exists, because lesson 2 used it.
prompt
prompt === 4. THE PLANNER SEEDS A REFERENCE FILE ==========================
prompt

declare
  l_store_id number;
  c_rules constant varchar2(1000 char) :=
'Site rules for LINE-2. Maintained by the maintenance planner. Read only.

2026-01-15 - Work that opens the syrup circuit needs a CIP rinse booked with
  production before it starts.
2026-03-02 - Coupling and alignment work on a pump is a TWO-PERSON job. Do not
  start it alone on a night shift. Call the shift leader instead.
2026-05-20 - LINE-2 spares are drawn from store 4B. Store 2A no longer holds
  them.';
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-14'
  );

  uc_ai_memory.put_file(
    p_store_id => l_store_id
  , p_path     => '/memories/site_rules.txt'
  , p_content  => c_rules
  );
  commit;
  sys.dbms_output.put_line('Seeded /memories/site_rules.txt into the AS-14 store.');
end;
/

-- ---------------------------------------------------------------------------
-- 5. Two conversations under the rules
-- ---------------------------------------------------------------------------
-- The second one is the test of the seeded file. A lone technician on a night
-- shift asks whether to start the coupling job. Nothing in mx_work_orders or
-- mx_alarms answers that. Only site_rules.txt does.
prompt
prompt === 5. TWO CONVERSATIONS UNDER THE RULES ===========================
prompt

declare
  l_result json_object_t;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Petra"
    , "today": "2026-08-25"
    , "question": "The drive-end vibration is back again. Reliability wants the alignment measured cold, before start-up, never after a run. Record that for the next shift."
    }')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"petra.k"}')
  );
  sys.dbms_output.put_line('--- Conversation 1 (Petra, night shift) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line(' ');

  :sess_night := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Tomas"
    , "today": "2026-08-25"
    , "question": "I am on nights on my own. Can I start the coupling job on this pump now?"
    }')
  , p_session_id       => :sess_night
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"tomas.b"}')
  );
  sys.dbms_output.put_line('--- Conversation 2 (Tomas, alone on nights) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

prompt
prompt --- What the store holds now
select f.path
     , f.char_count
  from uc_ai_v_memory_files f
 where f.store_key = 'context:MX_DESK:asset_no:AS-14'
 order by f.path;

prompt
prompt --- Which files the night-shift run opened
select m.seq
     , json_value(m.tool_input, '$.command') as command
     , json_value(m.tool_input, '$.path')    as path
  from uc_ai_agent_messages m
 where m.tool_name = 'MEMORY'
   and m.role = 'tool_call'
   and m.session_id = :sess_night
 order by m.seq;

prompt
prompt --- The two files the desk wrote, in full
declare
  l_store_id number;
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-14'
  );

  <<written_files>>
  for r in (
    select f.path
      from uc_ai_v_memory_files f
     where f.store_id = l_store_id
       and f.path != '/memories/site_rules.txt'
     order by f.path
  )
  loop
    sys.dbms_output.put_line('=== ' || r.path || ' ===');
    sys.dbms_output.put_line(uc_ai_memory.get_file(l_store_id, r.path));
    sys.dbms_output.put_line(' ');
  end loop written_files;

  -- And the planner's file, byte for byte as it was seeded.
  sys.dbms_output.put_line('=== /memories/site_rules.txt, after both runs ===');
  sys.dbms_output.put_line(uc_ai_memory.get_file(l_store_id, '/memories/site_rules.txt'));
end;
/
