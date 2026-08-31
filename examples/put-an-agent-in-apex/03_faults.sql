-- ============================================================================
-- UC AI tutorial - "Put an Agent in APEX" - lesson 3
-- Reproduces the empty-answer fault, then removes its cause again.
-- ============================================================================
-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.
-- @dblinter ignore(g-2160): the local function is called in the report loop below,
-- which is the whole point of the script.

set serveroutput on
set feedback off
set define off
-- 1) put a response schema on the shared profile
declare
  l_p uc_ai_prompt_profiles%rowtype;
  c_schema constant varchar2(2000 char) := '{
    "type": "object",
    "properties": {
      "answer":        { "type": "string" },
      "actions_taken": { "type": "array", "items": { "type": "string" } },
      "needs_human":   { "type": "boolean" },
      "confidence":    { "type": "string", "enum": ["low","medium","high"] }
    },
    "required": ["answer","actions_taken","needs_human","confidence"],
    "additionalProperties": false
  }';
begin
  l_p := uc_ai_prompt_profiles_api.get_prompt_profile('SC_DESK_PROFILE', 1);
  l_p.response_schema := c_schema;
  uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_p);
  commit;
  sys.dbms_output.put_line('response schema applied');
end;
/
-- 2) run one chat turn exactly as the plug-in job does
declare
  l_sess varchar2(255 char) := 'SCHEMA_FAULT_' || to_char(systimestamp,'HH24MISSFF3');
  l_id   number;
begin
  insert into uc_ai_chat_messages (session_id, role, content, agent_code,
         agent_request_params, run_context, turn_status, created_by)
  values (l_sess, 'user', 'Which invoices still have an uncredited amount?', 'SC_DESK',
         '{"engineer_name":"ADMIN","today":"2026-08-25","question":"Which invoices still have an uncredited amount?"}',
         '{"contract_id":"88","engineer":"ADMIN"}', 'pending', 'ADMIN')
  returning id into l_id;
  commit;
  uc_ai_chat.execute_agent_job(p_user_msg_id => l_id);

  <<report_rows>>
  for r in (select id, role, turn_status, error_detail,
                   nvl(substr(to_char(content),1,60), '<<NULL>>') as c,
                   input_tokens, output_tokens
              from uc_ai_chat_messages where session_id = l_sess order by id) loop
    sys.dbms_output.put_line(rpad(r.role,11) || '| status=' || rpad(nvl(r.turn_status,'-'),8)
      || '| tokens=' || rpad(nvl(to_char(r.input_tokens),'-'),5) || '/' || rpad(nvl(to_char(r.output_tokens),'-'),5)
      || '| content=' || r.c
      || case when r.error_detail is not null
              then ' | err=' || substr(r.error_detail, 1, 40)
         end);
  end loop report_rows;
end;
/
-- 3) ALWAYS take the schema back off
declare
  l_p uc_ai_prompt_profiles%rowtype;
begin
  l_p := uc_ai_prompt_profiles_api.get_prompt_profile('SC_DESK_PROFILE', 1);
  l_p.response_schema := null;
  uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_p);
  commit;
  sys.dbms_output.put_line('response schema removed');
end;
/
select 'schema now: ' || nvl(substr(to_char(response_schema),1,20),'NULL') from uc_ai_prompt_profiles where code='SC_DESK_PROFILE';
exit
