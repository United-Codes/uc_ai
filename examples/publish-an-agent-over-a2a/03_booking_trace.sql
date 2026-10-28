-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A" — Lesson 3
-- Read the trace of the two booking requests
-- ============================================================================
-- Run it after you sent the two booking messages of lesson 3. It reads, for
-- the last two tasks of the client apikey:ferrolux:
--
--   * the text of the request,
--   * the tool_result row of the run: what the handler returned to the model,
--   * the text of the artifact: what the client received.
--
-- Then it lists the rows of partner_visits. It only reads.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on size unlimited
set linesize 200
set long 4000

declare
  l_number pls_integer := 0;
begin
  <<ordered>>
  for t in ( select y.execution_id
                  , json_value(y.request_message, '$.parts[0].text') as asked
                  , json_value(y.result, '$.parts[0].text')          as answered
               from ( select k.execution_id
                           , k.request_message
                           , k.result
                           , k.created_at
                        from uc_ai_a2a_tasks k
                        join uc_ai_a2a_endpoints e on e.id = k.endpoint_id
                       where e.code = 'service-desk'
                         and k.client_id = 'apikey:ferrolux'
                       order by k.created_at desc
                       fetch first 2 rows only ) y
              order by y.created_at ) loop
    l_number := l_number + 1;
    sys.dbms_output.put_line('Task ' || l_number);
    sys.dbms_output.put_line('  asked:        ' || t.asked);

    <<results>>
    for m in ( select g.tool_name
                    , g.tool_output
                 from uc_ai_agent_messages g
                where g.execution_id = t.execution_id
                  and g.role = 'tool_result'
                order by g.seq ) loop
      sys.dbms_output.put_line('  tool_result:  ' || m.tool_name || ' ' || m.tool_output);
    end loop results;

    sys.dbms_output.put_line('  artifact:     ' || t.answered);
  end loop ordered;
end;
/

prompt
prompt The rows of partner_visits:
prompt

select v.id
     , a.asset_tag
     , to_char(v.requested_for, 'YYYY-MM-DD') as requested_for
     , v.status
     , v.client_id
  from partner_visits v
  join sc_assets a on a.id = v.asset_id
 order by v.id;
