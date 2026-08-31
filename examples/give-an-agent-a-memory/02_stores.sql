-- ============================================================================
-- UC AI tutorial — "Give an Agent a Memory" — Lesson 2
-- One store for the desk, or one for each machine
-- ============================================================================
-- Run 01_recall.sql first. Memory is on, with the DEFAULT scope: one store for
-- the whole agent.
--
-- Six blocks:
--   1  A conversation about the pump AS-14 records a note about its alarm.
--   2  A conversation about the compressor AS-31 reads the same store.
--   3  The proof that needs no model: one store key, reachable from both runs.
--   4  Re-scope the memory to one store per asset.
--   5  The files that stayed behind in the old store.
--   6  Two conversations again, two store keys.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200

-- The AS-31 conversation of block 2. The trace query below reports on THIS run
-- and not on whatever else has happened in this schema.
variable sess_31 varchar2(255)

-- ---------------------------------------------------------------------------
-- 1. A note about the alarm on AS-14
-- ---------------------------------------------------------------------------
-- AS-14 really does have a nuisance alarm: PRS-LOW trips on every clean-in-place
-- cycle and clears itself. A technician says so, and the desk writes it down.
prompt
prompt === 1. AS-14: the alarm that IS a nuisance ==========================
prompt

declare
  l_result json_object_t;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Nadia"
    , "today": "2026-08-25"
    , "question": "About the low pressure alarm on this one: it is a nuisance. It trips on every clean-in-place cycle and clears itself, and nobody should be chasing it. Write that down so the next shift does not waste an hour on it."
    }')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"nadia.r"}')
  );
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- 2. A different machine, whose low-pressure alarm is real
-- ---------------------------------------------------------------------------
-- AS-31 is the plant air compressor. Its DIS-PRS-LOW alarm is HIGH severity,
-- open since 2026-08-23, and it is starving the whole line of air. Nothing in
-- the data connects it to AS-14.
prompt
prompt === 2. AS-31: the alarm that is REAL ================================
prompt

declare
  l_result json_object_t;
begin
  :sess_31 := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Tomas"
    , "today": "2026-08-25"
    , "question": "I have a low pressure alarm on this machine. Do I need to act on it, or is it one we ignore?"
    }')
  , p_session_id       => :sess_31
  , p_run_context      => json_object_t('{"asset_no":"AS-31","technician":"tomas.b"}')
  );
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('session: ' || :sess_31);
end;
/

-- Which files did the AS-31 run actually read? This is the question that
-- decides whether the answer above was influenced or not.
prompt
prompt --- Every MEMORY call of the AS-31 run
-- Read the command and the path out of the arguments. That is the whole
-- question: which files did a run bound to AS-31 open?
select m.seq
     , json_value(m.tool_input, '$.command') as command
     , json_value(m.tool_input, '$.path')    as path
  from uc_ai_agent_messages m
 where m.tool_name = 'MEMORY'
   and m.role = 'tool_call'
   and m.session_id = :sess_31
 order by m.seq;

-- ---------------------------------------------------------------------------
-- 3. The proof that needs no model
-- ---------------------------------------------------------------------------
-- A recorded answer tells you what the model DID. It cannot tell you what it
-- COULD have done. The store key does.
prompt
prompt === 3. ONE STORE, BOTH MACHINES ====================================
prompt

select f.store_key
     , f.scope
     , f.path
     , f.char_count
  from uc_ai_v_memory_files f
 where f.agent_code = 'MX_DESK'
 order by f.path;

-- resolve_store_id for the default scope takes NO asset. There is nowhere to
-- put one, because the run context is not part of the key.
declare
  l_store_id number;
  l_files_cur sys_refcursor;
  l_path     varchar2(1000 char);
  l_chars    number;
  l_created  timestamp;
  l_updated  timestamp;
  l_accessed timestamp;
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope      => uc_ai_memory.c_scope_agent
  , p_agent_code => 'MX_DESK'
  );

  sys.dbms_output.put_line('The store every run of MX_DESK resolves to: id=' || l_store_id);
  sys.dbms_output.put_line('Every file in it, whatever machine it is about:');

  l_files_cur := uc_ai_memory.list_files(l_store_id);
  -- @dblinter ignore(g-3140): list_files returns a weakly typed ref cursor, so
  -- there is no record to anchor to
  <<file_row>>
  loop
    fetch l_files_cur into l_path, l_chars, l_created, l_updated, l_accessed;
    exit file_row when l_files_cur%notfound;
    sys.dbms_output.put_line('  ' || l_path);
  end loop file_row;
  close l_files_cur;
end;
/

-- ---------------------------------------------------------------------------
-- 4. One store per machine
-- ---------------------------------------------------------------------------
-- The same call as lesson 1, with a scope and a key. It OVERWRITES the
-- configuration row; it does not add a second one.
prompt
prompt === 4. RE-SCOPE TO ONE STORE PER MACHINE ===========================
prompt

begin
  uc_ai_memory.enable_for_agent(
    p_agent_code  => 'MX_DESK'
  , p_scope       => uc_ai_memory.c_scope_context
  , p_context_key => 'asset_no'
  );
  commit;
end;
/

select c.agent_code
     , c.scope
     , c.context_key
     , c.enabled
  from uc_ai_memory_config c
 where c.agent_code = 'MX_DESK';

-- ---------------------------------------------------------------------------
-- 5. What the re-scope did NOT do
-- ---------------------------------------------------------------------------
-- It changed one configuration row. A store is a row of its own, and the files
-- hang off it, so the old shared store is still there with everything in it.
prompt
prompt === 5. THE OLD STORE IS STILL THERE ================================
prompt

select f.store_key
     , f.scope
     , f.path
     , f.char_count
  from uc_ai_v_memory_files f
 where f.agent_code = 'MX_DESK'
 order by f.store_key, f.path;

-- Clear it. The store row stays, and nothing resolves to it any more.
declare
  l_store_id number;
  e_no_store exception;
  pragma exception_init(e_no_store, -20423);
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope      => uc_ai_memory.c_scope_agent
  , p_agent_code => 'MX_DESK'
  );
  uc_ai_memory.clear_store_files(l_store_id);
  commit;
  sys.dbms_output.put_line('Cleared the old shared store, id=' || l_store_id || '.');
exception
  when e_no_store then
    sys.dbms_output.put_line('There is no shared store, so there is nothing to clear.');
end;
/

-- ---------------------------------------------------------------------------
-- 6. The same two conversations, on two stores
-- ---------------------------------------------------------------------------
prompt
prompt === 6. THE SAME TWO CONVERSATIONS, RE-SCOPED =======================
prompt

declare
  l_result json_object_t;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Nadia"
    , "today": "2026-08-25"
    , "question": "About the low pressure alarm on this one: it is a nuisance. It trips on every clean-in-place cycle and clears itself, and nobody should be chasing it. Write that down so the next shift does not waste an hour on it."
    }')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"nadia.r"}')
  );
  sys.dbms_output.put_line('--- AS-14 (Nadia) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line(' ');

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Tomas"
    , "today": "2026-08-25"
    , "question": "I have a low pressure alarm on this machine. Do I need to act on it, or is it one we ignore?"
    }')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  , p_run_context      => json_object_t('{"asset_no":"AS-31","technician":"tomas.b"}')
  );
  sys.dbms_output.put_line('--- AS-31 (Tomas) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

prompt
prompt --- Two machines, two store keys
select f.store_key
     , f.path
     , f.char_count
  from uc_ai_v_memory_files f
 where f.agent_code = 'MX_DESK'
 order by f.store_key, f.path;

-- And the isolation itself, without a model: the AS-31 store cannot be asked
-- for a file that lives in the AS-14 store.
prompt
prompt --- Ask the AS-31 store for the AS-14 note
declare
  l_store_31 number;
  l_path     varchar2(1000 char);
  -- @dblinter ignore(g-2135): the point of the call is whether get_file RAISES,
  -- so the returned content is deliberately thrown away
  l_dummy    varchar2(32767 char);
  e_no_file  exception;
  pragma exception_init(e_no_file, -20425);
begin
  -- The first file in the AS-14 store, whatever the model called it.
  select min(f.path)
    into l_path
    from uc_ai_v_memory_files f
   where f.store_key = 'context:MX_DESK:asset_no:AS-14';

  l_store_31 := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'MX_DESK'
  , p_context_key   => 'asset_no'
  , p_context_value => 'AS-31'
  );

  sys.dbms_output.put_line('AS-14 wrote: ' || l_path);
  sys.dbms_output.put_line('Reading it from the AS-31 store (id=' || l_store_31 || ') ...');

  l_dummy := uc_ai_memory.get_file(l_store_31, l_path);
  sys.dbms_output.put_line('LEAK: the AS-31 store returned it.');
exception
  when e_no_file then
    sys.dbms_output.put_line('ORA-20425: not in this store. The machines are separated.');
end;
/
