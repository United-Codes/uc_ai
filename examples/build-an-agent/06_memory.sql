-- ============================================================================
-- UC AI tutorial — "Build an Agent" — Lesson 6
-- Sessions, and memory that survives a conversation
-- ============================================================================
-- Two separate ideas, in this order:
--
--   A session keeps the turns of ONE conversation together.
--   Memory keeps what the desk learned BETWEEN conversations.
--
-- The memory of this agent is scoped to the run-context key contract_id, so each
-- contract gets its own memory. Nothing crosses from one contract to another.
--
-- CAUTION: from the moment memory is enabled, every run of SC_DESK must pass
-- p_run_context with contract_id, or the run stops with ORA-20426. Lesson 6
-- shows that error on purpose.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- Enable memory, one store for each contract
-- ---------------------------------------------------------------------------
-- This adds the memory tool tag to the model configuration of the prompt
-- profile, and it keeps the tags that are already there. It is safe to run again.
begin
  uc_ai_memory.enable_for_agent(
    p_agent_code  => 'SC_DESK'
  , p_scope       => uc_ai_memory.c_scope_context
  , p_context_key => 'contract_id'
  );
  commit;
  sys.dbms_output.put_line('Memory enabled for SC_DESK, one store for each contract_id.');
end;
/

-- The tag list now holds both tags. Lesson 3 put 'scdesk' there.
select model_config_json
  from uc_ai_prompt_profiles
 where code = 'SC_DESK_PROFILE'
   and version = 1;

-- ---------------------------------------------------------------------------
-- Start with an empty memory, so this script gives the same result every time
-- ---------------------------------------------------------------------------
-- A store is created at its first use, so on a first run there is nothing to
-- clear and resolve_store_id reports that with ORA-20423.
declare
  l_store_id number;
  e_no_store exception;
  pragma exception_init(e_no_store, -20423);
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'SC_DESK'
  , p_context_key   => 'contract_id'
  , p_context_value => '88'
  );

  uc_ai_memory.clear_store_files(l_store_id);
  commit;
  sys.dbms_output.put_line('Store ' || l_store_id || ' is empty again.');
exception
  when e_no_store then
    sys.dbms_output.put_line('No store yet for contract 88, so it is already empty.');
end;
/

-- ---------------------------------------------------------------------------
-- 1. Two turns in ONE conversation (the session)
-- ---------------------------------------------------------------------------
declare
  l_result  json_object_t;
  l_session varchar2(255 char) := uc_ai_agents_api.generate_session_id;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'SC_DESK'
  , p_input_parameters => json_object_t('{"engineer_name":"Petra"
      ,"today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"Which invoice on this contract still has an uncredited amount?"}')
  , p_session_id       => l_session
  , p_run_context      => json_object_t('{"contract_id":"88","engineer":"petra.k"}')
  );
  sys.dbms_output.put_line('TURN 1: ' || l_result.get_clob('final_message'));

  -- The follow-up names no invoice. The session carries the first answer.
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code        => 'SC_DESK'
  , p_follow_up_message => 'And is that one inside the coverage window?'
  , p_session_id        => l_session
  , p_run_context       => json_object_t('{"contract_id":"88","engineer":"petra.k"}')
  );
  sys.dbms_output.put_line('TURN 2: ' || l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- 2. Two SEPARATE conversations (the memory)
-- ---------------------------------------------------------------------------
declare
  function ask(
    p_question in varchar2
  ) return clob
  as
    l_res json_object_t;
  begin
    l_res := uc_ai_agents_api.execute_agent(
      p_agent_code       => 'SC_DESK'
    , p_input_parameters => json_object_t('{"engineer_name":"Petra"
        ,"today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
        ,"question":"' || p_question || '"}')
      -- A NEW session each time: nothing carries over except the memory.
    , p_session_id       => uc_ai_agents_api.generate_session_id
    , p_run_context      => json_object_t('{"contract_id":"88","engineer":"petra.k"}')
    );
    return l_res.get_clob('final_message');
  end ask;
begin
  sys.dbms_output.put_line('CONVERSATION 1: ' || ask(
    'Remember for next time: this customer always wants the plant manager '
    || 'Anna Ruiz copied on any credit note, and they prefer email over phone.'));

  sys.dbms_output.put_line('CONVERSATION 2: ' || ask(
    'I am about to raise another credit note for this customer. Anything I '
    || 'should know about how they want to be contacted?'));
end;
/

-- ---------------------------------------------------------------------------
-- Verification — the file the desk wrote, and what is in it
-- ---------------------------------------------------------------------------
set feedback off
prompt
prompt The store, the path, and the size:
prompt

select store_key
     , path
     , char_count
  from uc_ai_v_memory_files
 where agent_code = 'SC_DESK'
 order by path;

prompt
prompt The content. The view carries no content column, so read the file itself:
prompt

set serveroutput on
declare
  l_store_id number;
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'SC_DESK'
  , p_context_key   => 'contract_id'
  , p_context_value => '88'
  );

  <<file_rows>>
  for r in ( select f.path
               from uc_ai_memory_files f
              where f.store_id = l_store_id
              order by f.path ) loop
    sys.dbms_output.put_line('--- ' || r.path || ' ---');
    sys.dbms_output.put_line(uc_ai_memory.get_file(l_store_id, r.path));
  end loop file_rows;
end;
/

-- ---------------------------------------------------------------------------
-- The mistake you will make once
-- ---------------------------------------------------------------------------
-- Memory is scoped to contract_id. A run that does not supply it cannot be
-- matched to a store, so UC AI stops the run before it starts.
declare
  l_ignored json_object_t;
begin
  l_ignored := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'SC_DESK'
  , p_input_parameters => json_object_t('{"engineer_name":"Petra"
      ,"today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"What do you remember about this customer?"}')
  , p_session_id       => uc_ai_agents_api.generate_session_id
    -- p_run_context is missing on purpose
  );
  -- @dblinter ignore(g-2135): the call raises, so the result is never read. That is the
  -- point of this block: it shows the error a missing run context gives.
  sys.dbms_output.put_line('This line is never reached. ' || l_ignored.to_clob);
exception
  when others then
    -- @dblinter ignore(g-5040): the lesson shows the error text itself, and any other
    -- error here is equally worth printing for the reader
    -- @dblinter ignore(g-5080): the message IS the teaching point; a backtrace of the
    -- framework internals would not help the reader
    sys.dbms_output.put_line('Stopped, as it must: ' || sqlerrm);
end;
/

set feedback on
