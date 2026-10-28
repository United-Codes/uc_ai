-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - lesson 3
-- Send one message to the desk the way the chat region does, and read what the
-- chat stores.
-- ============================================================================
-- The region of the plug-in writes one row for the message of the user and then
-- starts the job UC_AI_CHAT.EXECUTE_AGENT_JOB. This script does the same two
-- steps from SQL, so you can try the widget without an APEX page.
--
-- It calls the model of the agent SC_DESK, so it needs the network access and
-- the API key that the earlier courses set up. Run 02_invoice_widget.sql first.
--
-- Change C_QUESTION to try other questions. Each run starts a new conversation
-- with a session ID that starts with SCW_. 00_teardown.sql deletes these rows.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

declare
  c_agent    constant varchar2(30 char) := 'SC_DESK';
  c_question constant varchar2(400 char) :=
    'List the invoices of this contract and tell me which of them still have an uncredited amount.';

  l_session  varchar2(255 char) := 'SCW_' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
  l_params   json_object_t := json_object_t();
  l_context  json_object_t := json_object_t();
  l_params_c clob;
  l_context_c clob;
  l_user_id  number;
  l_status   varchar2(20 char);
  l_answer   clob;
  l_parts    clob;
  l_t0       timestamp := systimestamp;
  l_secs     number;
begin
  -- What the region sends: the three values of Agent Input Mapping (lesson 1 of
  -- Put an Agent in APEX), and the Agent Run Context that binds the conversation
  -- to contract 88.
  l_params.put('engineer_name', 'petra.k');
  l_params.put('today', to_char(sysdate, 'YYYY-MM-DD'));
  l_params.put('question', c_question);
  l_context.put('contract_id', '88');
  l_context.put('engineer', 'petra.k');
  -- the JSON objects go into the insert as text: a PL/SQL JSON object cannot be used in SQL
  l_params_c := l_params.to_clob();
  l_context_c := l_context.to_clob();

  insert into uc_ai_chat_messages (
    session_id, role, content, agent_code, agent_request_params, run_context, widgets, turn_status, created_by
  ) values (
    l_session, 'user', c_question, c_agent, l_params_c, l_context_c
  , uc_ai_chat_widgets.normalize_types('sc_invoices')   -- the attribute Custom Widgets
  , 'pending', 'PETRA.K'
  ) returning id into l_user_id;
  commit;

  uc_ai_chat.execute_agent_job(p_user_msg_id => l_user_id);

  l_secs := extract(second from (systimestamp - l_t0)) + 60 * extract(minute from (systimestamp - l_t0));

  select turn_status into l_status from uc_ai_chat_messages where id = l_user_id;
  sys.dbms_output.put_line('Session  : ' || l_session);
  sys.dbms_output.put_line('Turn     : ' || l_status || ' in ' || round(l_secs) || ' seconds');

  sys.dbms_output.put_line('Tool calls:');
  <<call_loop>>
  for c in (select tool_name from uc_ai_chat_messages
             where session_id = l_session and role = 'tool_call' order by id) loop
    sys.dbms_output.put_line('  ' || c.tool_name);
  end loop call_loop;

  select content, parts
    into l_answer, l_parts
    from uc_ai_chat_messages
   where session_id = l_session and role = 'assistant'
   order by id desc
   fetch first 1 row only;

  sys.dbms_output.put_line('Answer   :');
  sys.dbms_output.put_line(l_answer);

  sys.dbms_output.put_line('Parts    :');
  <<part_loop>>
  for p in (
    select jt.rn, jt.kind, jt.type, jt.titles, jt.rejected
      from json_table(l_parts, '$[*]' columns (
             rn for ordinality
           , kind     varchar2(10 char)  path '$.kind'
           , type     varchar2(20 char)  path '$.type'
           , titles   varchar2(200 char) format json with wrapper path '$.spec.items[*].title'
           , rejected varchar2(300 char) path '$.rejected'
           )) jt
     order by jt.rn
  ) loop
    sys.dbms_output.put_line('  ' || p.rn || ' ' || p.kind || ' ' || p.type
      || case when p.titles is not null then ' ' || p.titles end
      || case when p.rejected is not null then ' REJECTED: ' || p.rejected end);
  end loop part_loop;
end;
/
