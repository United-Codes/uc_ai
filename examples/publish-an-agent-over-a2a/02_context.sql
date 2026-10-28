-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A" — Lesson 2
-- Read which tools each question of Ferrolux called
-- ============================================================================
-- Run it after the clients of lesson 2. For every task of the client
-- apikey:ferrolux it prints the context (the first 8 characters of the
-- contextId), the question, and the tools that the agent called. It only reads.
-- ============================================================================

set define off
set linesize 200
column context format a10
column asked format a44
column tools format a40
select substr(t.context_id, 1, 8) as context
     , t.asked
     , listagg(m.tool_name, ', ') within group (order by m.seq) as tools
  from ( select k.task_id
              , k.context_id
              , k.execution_id
              , k.created_at
              , json_value(k.request_message, '$.parts[0].text') as asked
           from uc_ai_a2a_tasks k
          where k.client_id = 'apikey:ferrolux' ) t
  left join uc_ai_agent_messages m
    on m.execution_id = t.execution_id
   and m.role = 'tool_call'
 group by t.task_id, t.context_id, t.created_at, t.asked
 order by t.created_at;
