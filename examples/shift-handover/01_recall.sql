-- ============================================================================
-- UC AI tutorial — "Give an Agent a Memory" — Lesson 1
-- The next shift starts from nothing
-- ============================================================================
-- Run 00_setup.sql and 00_precheck.sql first.
--
-- Four blocks:
--   1  Two conversations with NO memory. The second one knows nothing.
--   2  One call turns memory on.
--   3  The same two conversations. The second one remembers.
--   4  What the desk wrote, and what memory cost in tool calls.
--
-- Every conversation uses a NEW session id on purpose. A session carries the
-- turns of ONE conversation; it is not what carries knowledge between them.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200

-- The four conversations of this lesson. Block 5 reports on THESE runs and not
-- on whatever else has happened in this schema.
variable sess_a varchar2(255)
variable sess_b varchar2(255)
variable sess_c varchar2(255)
variable sess_d varchar2(255)

-- ---------------------------------------------------------------------------
-- 1. Two conversations, no memory
-- ---------------------------------------------------------------------------
prompt
prompt === 1. NO MEMORY ===================================================
prompt

declare
  l_result json_object_t;
begin
  :sess_a := uc_ai_agents_api.generate_session_id;
  :sess_b := uc_ai_agents_api.generate_session_id;

  -- Conversation 1: the night shift works something out and says it out loud.
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Petra"
    , "today": "2026-08-25"
    , "question": "The vibration at the drive end is back. I traced it to the coupling again. The reliability engineer wants the alignment measured COLD, before start-up, not after a run - the warm reading has been lying to us. Make sure the next shift knows that."
    }')
  , p_session_id       => :sess_a
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"petra.k"}')
  );
  sys.dbms_output.put_line('--- Conversation 1 (Petra, night shift) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line(' ');

  -- Conversation 2: a different technician, a NEW session, a week later.
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Sam"
    , "today": "2026-08-25"
    , "question": "I am about to work on the vibration at the drive end of this pump. Is there anything the last shift worked out that I should know before I start?"
    }')
  , p_session_id       => :sess_b
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"sam.o"}')
  );
  sys.dbms_output.put_line('--- Conversation 2 (Sam, early shift, new session) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- 2. Turn memory on
-- ---------------------------------------------------------------------------
-- No scope is named, so this takes the default: ONE store for the agent
-- MX_DESK, shared by every asset and every technician. That is deliberate.
-- Lesson 2 is about when it is the wrong choice.
prompt
prompt === 2. MEMORY ON ===================================================
prompt

begin
  uc_ai_memory.enable_for_agent(p_agent_code => 'MX_DESK');
  commit;
end;
/

-- What the call changed on the prompt profile.
select p.model_config_json
  from uc_ai_prompt_profiles p
 where p.code = 'MX_DESK_PROFILE'
   and p.version = 1;

-- And the configuration row it created.
select c.agent_code
     , c.scope
     , c.context_key
     , c.enabled
     , c.max_files
     , c.max_file_chars
  from uc_ai_memory_config c
 where c.agent_code = 'MX_DESK';

-- ---------------------------------------------------------------------------
-- 3. The same two conversations
-- ---------------------------------------------------------------------------
prompt
prompt === 3. THE SAME TWO CONVERSATIONS ==================================
prompt

declare
  l_result json_object_t;
begin
  :sess_c := uc_ai_agents_api.generate_session_id;
  :sess_d := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Petra"
    , "today": "2026-08-25"
    , "question": "The vibration at the drive end is back. I traced it to the coupling again. The reliability engineer wants the alignment measured COLD, before start-up, not after a run - the warm reading has been lying to us. Make sure the next shift knows that."
    }')
  , p_session_id       => :sess_c
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"petra.k"}')
  );
  sys.dbms_output.put_line('--- Conversation 1 (Petra) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('session 1: ' || :sess_c);

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'MX_DESK'
  , p_input_parameters => json_object_t('{
      "technician_name": "Sam"
    , "today": "2026-08-25"
    , "question": "I am about to work on the vibration at the drive end of this pump. Is there anything the last shift worked out that I should know before I start?"
    }')
  , p_session_id       => :sess_d
  , p_run_context      => json_object_t('{"asset_no":"AS-14","technician":"sam.o"}')
  );
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('--- Conversation 2 (Sam, a NEW session, told nothing) ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('session 2: ' || :sess_d);
end;
/

-- ---------------------------------------------------------------------------
-- 4. What the desk wrote, and what memory cost
-- ---------------------------------------------------------------------------
prompt
prompt === 4. WHAT IS IN THE STORE ========================================
prompt

select f.store_key
     , f.path
     , f.char_count
  from uc_ai_v_memory_files f
 where f.agent_code = 'MX_DESK'
 order by f.path;

-- Read one file. The view carries no content column.
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

  l_files_cur := uc_ai_memory.list_files(l_store_id);
  -- @dblinter ignore(g-3140): list_files returns a weakly typed ref cursor, so
  -- there is no record to anchor to
  <<file_row>>
  loop
    fetch l_files_cur into l_path, l_chars, l_created, l_updated, l_accessed;
    exit file_row when l_files_cur%notfound;
    sys.dbms_output.put_line('=== ' || l_path || ' (' || l_chars || ' chars) ===');
    sys.dbms_output.put_line(uc_ai_memory.get_file(l_store_id, l_path));
    sys.dbms_output.put_line(' ');
  end loop file_row;
  close l_files_cur;
end;
/

prompt
prompt === 5. WHAT MEMORY COST IN TOOL CALLS ==============================
prompt

-- Every run of this agent, and how many of its tool calls went on MEMORY.
-- g_max_tool_calls on this profile is 12.
select e.id
     , e.status
     , e.tool_calls_count            as calls
     , (select count(*)
          from uc_ai_agent_messages m
         where m.execution_id = e.id
           and m.role = 'tool_call'
           and m.tool_name = 'MEMORY') as memory_calls
     , e.total_input_tokens  as in_tok
     , e.total_output_tokens as out_tok
  from uc_ai_agent_executions e
  join uc_ai_agents a on a.id = e.agent_id
 where e.session_id in (:sess_a, :sess_b, :sess_c, :sess_d)
   and a.code = 'MX_DESK'
 order by e.id;
