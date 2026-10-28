-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A" — Lesson 4
-- Read how the clients use the endpoint
-- ============================================================================
-- Five queries over the tables of the A2A server and the agent runs. They only
-- read. Run the script at any time after lesson 2.
--
-- The token count of a task is the sum over its execution and every run that it
-- started below it, the same count that the task shows in metadata.usage.
-- ============================================================================

set define off
set linesize 200
set pagesize 100
column client_id format a20
column state format a24
column asked format a60
column tools format a50

-- ---------------------------------------------------------------------------
-- Read the tools of the last task of each client
-- ---------------------------------------------------------------------------
-- The tools of a run, in the order that the agent called them.
select x.client_id
     , x.asked
     , ( select listagg(m.tool_name, ' -> ') within group (order by m.seq)
           from uc_ai_agent_messages m
          where m.execution_id = x.execution_id
            and m.role = 'tool_call' ) as tools
  from ( select t.client_id
              , t.execution_id
              , json_value(t.request_message, '$.parts[0].text') as asked
              , row_number() over (partition by t.client_id order by t.created_at desc) as rn
           from uc_ai_a2a_tasks t
           join uc_ai_a2a_endpoints ep on ep.id = t.endpoint_id
          where ep.code = 'service-desk' ) x
 where x.rn = 1
 order by x.client_id;

-- The visit requests that the runs created.
select v.id
     , a.asset_tag
     , to_char(v.requested_for, 'YYYY-MM-DD') as requested_for
     , v.status
     , v.client_id
  from partner_visits v
  join sc_assets a on a.id = v.asset_id
 order by v.id;

-- ---------------------------------------------------------------------------
-- Tokens and tasks for each client
-- ---------------------------------------------------------------------------
select t.client_id
     , count(*) as tasks
     , sum(case when t.state = 'TASK_STATE_COMPLETED' then 1 else 0 end) as completed
     , sum(case when t.state = 'TASK_STATE_FAILED' then 1 else 0 end) as failed
     , sum(( select sum(e.total_input_tokens)
               from uc_ai_agent_executions e
              start with e.id = t.execution_id
            connect by prior e.id = e.parent_execution_id )) as input_tokens
     , sum(( select sum(e.total_output_tokens)
               from uc_ai_agent_executions e
              start with e.id = t.execution_id
            connect by prior e.id = e.parent_execution_id )) as output_tokens
  from uc_ai_a2a_tasks t
  join uc_ai_a2a_endpoints ep on ep.id = t.endpoint_id
 where ep.code = 'service-desk'
 group by t.client_id
 order by t.client_id;

-- ---------------------------------------------------------------------------
-- Check the tokens of the last 24 hours against a limit
-- ---------------------------------------------------------------------------
-- UC AI has no rate limit. This query is the check that you run from a job or
-- by hand. Change 50000 to the limit that you accept for one client in a day.
select u.client_id
     , u.tokens_24h
     , 50000 as daily_limit
     , case when u.tokens_24h > 50000 then 'OVER THE LIMIT' else 'ok' end as verdict
  from ( select t.client_id
              , sum(( select sum(e.total_input_tokens + e.total_output_tokens)
                        from uc_ai_agent_executions e
                       start with e.id = t.execution_id
                     connect by prior e.id = e.parent_execution_id )) as tokens_24h
           from uc_ai_a2a_tasks t
           join uc_ai_a2a_endpoints ep on ep.id = t.endpoint_id
          where ep.code = 'service-desk'
            and t.created_at > systimestamp - interval '1' day
          group by t.client_id ) u
 order by u.tokens_24h desc;

-- ---------------------------------------------------------------------------
-- Read the seconds of each task
-- ---------------------------------------------------------------------------
-- The seconds between the creation of the task row and its last update. For a
-- blocking call this is the time that the client waited for the answer.
select t.client_id
     , count(*) as tasks
     , to_char(min(t.seconds), 'FM990.0', 'nls_numeric_characters=''. ''') as min_seconds
     , to_char(avg(t.seconds), 'FM990.0', 'nls_numeric_characters=''. ''') as avg_seconds
     , to_char(max(t.seconds), 'FM990.0', 'nls_numeric_characters=''. ''') as max_seconds
  from ( select k.client_id
              , extract(second from (k.updated_at - k.created_at))
                + 60 * extract(minute from (k.updated_at - k.created_at)) as seconds
           from uc_ai_a2a_tasks k
           join uc_ai_a2a_endpoints ep on ep.id = k.endpoint_id
          where ep.code = 'service-desk'
            and k.state = 'TASK_STATE_COMPLETED' ) t
 group by t.client_id
 order by t.client_id;
