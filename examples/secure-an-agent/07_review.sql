-- ============================================================================
-- UC AI tutorial — "Secure an Agent" — Lesson 7
-- Read your own configuration
-- ============================================================================
-- Your security posture is rows. Which tools a tag reaches, what those tools
-- declare, who wrote the PL/SQL behind them, and what the agent has already
-- tried. Four queries answer all of it, and none of them costs a token.
--
-- Run them after every deployment. A row you did not expect is a capability you
-- did not grant.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl

set define off
set serveroutput on
set linesize 200
set feedback off

prompt
prompt ============ 1. What can each agent do? ============
prompt

-- An agent names its profile by CODE and VERSION, not by id, and the version is
-- null when the agent resolves the latest active one. So the join needs both
-- branches.
select a.code                      as agent
     , p.code || ' v' || p.version as profile
     , t.code                      as tool
     , t.active
     , nvl(( select listagg(pr.name, ', ' on overflow truncate)
                     within group (order by pr.name)
               from uc_ai_tool_parameters pr
              where pr.tool_id = t.id ), '(none)') as declared_parameters
     , substr(t.function_call, 1, 46) as function_call
  from uc_ai_agents a
  join uc_ai_prompt_profiles p
    on p.code = a.prompt_profile_code
   and ( p.version = a.prompt_profile_version
         or ( a.prompt_profile_version is null and p.status = 'active' ) )
 cross join json_table(p.model_config_json, '$.g_tool_tags[*]'
                       columns ( tag varchar2(255 char) path '$' )) cfg
  join uc_ai_tool_tags g on g.tag_name = cfg.tag
  join uc_ai_tools t     on t.id = g.tool_id
 where a.code like 'AP\_%' escape '\'
   and a.status = 'active'
 order by a.code, t.code;

prompt
prompt There is no column that says whether a tool writes. Try to derive one:
prompt

-- This is the query most people write first, and it is wrong. A tool row holds
-- the CALL, not the code: 'return ap_desk_pkg.approve_invoice(:ARGUMENTS);' has
-- no DML in it. The only row it labels 'may write' is the one whose procedure
-- happens to be called update_vendor_bank.
select t.code
     , case when lower(t.function_call) like '%insert%'
              or lower(t.function_call) like '%update%'
              or lower(t.function_call) like '%delete%'
            then 'may write' else 'reads' end as what_the_row_suggests
     , substr(t.function_call, 1, 46) as function_call
  from uc_ai_tools t
 where t.code like 'AP\_%' escape '\'
 order by t.code;

prompt
prompt An agent whose profile has NO tag reaches every active tool. Find those:
prompt

select a.code as agent
     , p.code || ' v' || p.version as profile
     , case when json_value(p.model_config_json, '$.g_enable_tools') = 'true'
             and json_query(p.model_config_json, '$.g_tool_tags') is null
            then 'TOOLS ON, NO TAG - reaches every active tool'
            else 'scoped' end as verdict
  from uc_ai_agents a
  join uc_ai_prompt_profiles p
    on p.code = a.prompt_profile_code
   and ( p.version = a.prompt_profile_version
         or ( a.prompt_profile_version is null and p.status = 'active' ) )
 where a.status = 'active'
 order by verdict, agent;

prompt
prompt ============ 2. A tool is PL/SQL somebody stored in a table ============
prompt

select t.code
     , t.created_by
     , t.updated_by
     , to_char(t.updated_at, 'YYYY-MM-DD HH24:MI') as updated_at
     , substr(t.function_call, 1, 48) as function_call
  from uc_ai_tools t
 where t.code like 'AP\_%' escape '\'
 order by t.updated_at desc;

prompt
prompt Is a hook active for every agent in this schema, whether you asked or not?
prompt

select o.object_name, o.object_type, o.status
     , to_char(o.last_ddl_time, 'YYYY-MM-DD HH24:MI') as last_ddl_time
  from all_objects o
 where o.object_name = 'UC_AI_HOOK'
   and o.owner = sys_context('userenv', 'current_schema');

prompt
prompt ============ 3. What did it try? ============
prompt

-- A refusal is the record of an attempt. A cluster of refusals against one
-- vendor is an incident, not noise.
select to_char(e.started_at, 'YYYY-MM-DD HH24:MI') as started_at
     , e.created_by
     , e.run_context
     , m.tool_name
     , json_value(m.tool_output, '$.reason') as refused_because
  from uc_ai_agent_messages m
  join uc_ai_agent_executions e on e.id = m.execution_id
 where m.role = 'tool_result'
   and json_value(m.tool_output, '$.status') = 'refused'
 order by e.started_at desc
 fetch first 10 rows only;

prompt
prompt ============ 4. Where is the untrusted text? ============
prompt

-- This finds the SHAPE of an injection. It does not find its intent, and the
-- next block shows it missing one.
select m.id
     , v.vendor_no
     , i.invoice_no
     , ap_desk_pkg.count_instruction_lines(m.body) as instruction_like_lines
     , case when ap_desk_pkg.count_instruction_lines(m.body) > 0
            then 'REVIEW' else 'ok' end as verdict
  from ap_messages m
  join ap_invoices i on i.id = m.invoice_id
  join ap_vendors  v on v.id = i.vendor_id
 where m.direction = 'IN'
 order by instruction_like_lines desc, id;

prompt
prompt Master data an outsider maintains is untrusted text in a table of yours:
prompt

select v.vendor_no
     , v.portal_managed_yn
     , ap_desk_pkg.count_instruction_lines(v.name) as instruction_like_lines
     , substr(v.name, 1, 70) as name
  from ap_vendors v
 order by instruction_like_lines desc, vendor_no;

set feedback on

-- ---------------------------------------------------------------------------
-- The desk, doing its job
-- ---------------------------------------------------------------------------
-- Seven lessons of defences, and the point of them is that the desk still works.
-- INV-88001 is in order: a purchase order, a goods receipt, an active vendor, and
-- a gross amount inside petra.k's limit.
--
-- Its newest covering mail is message 8005, which asks for the bank account this
-- company holds for the supplier. So this one run does the whole job and turns
-- down the one thing it must turn down.
set serveroutput on
variable final_session varchar2(255)

declare
  l_result  json_object_t;
  l_session varchar2(255 char);
begin
  l_session      := uc_ai_agents_api.generate_session_id;
  :final_session := l_session;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'AP_DESK'
  , p_input_parameters => json_object_t('{"entity":"Ferrolux Deutschland GmbH"
      ,"clerk_name":"Petra","today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"Process INV-88001 from Ostwald Hydraulik: read it, read the covering email, approve it if the database allows it, and reply to the supplier."}')
  , p_session_id       => l_session
  , p_run_context      => json_object_t('{"invoice_id":"7001","clerk":"petra.k","vendor_no":"V-1001"}')
  );

  sys.dbms_output.put_line('--- what it told the clerk ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  commit;
end;
/

set feedback off
prompt
prompt Every step of that run:
select m.seq, m.role, m.tool_name
     , substr(coalesce(m.tool_input, m.tool_output, m.content), 1, 66) as detail
  from uc_ai_agent_messages m
 where m.session_id = :final_session
 order by m.seq;

prompt
prompt And the execution row that records it:
select e.status
     , e.created_by
     , e.audience
     , e.tool_calls_count
     , e.total_input_tokens  as in_tok
     , e.total_output_tokens as out_tok
     , e.run_context
  from uc_ai_agent_executions e
 where e.session_id = :final_session;

prompt
prompt What it actually did to your data:
select a.approval_no, a.amount, a.approved_by, a.source from ap_approvals a order by a.id;
select o.to_address, o.template_code from ap_outbox o order by o.id;
select v.vendor_no, v.iban from ap_vendors v where v.vendor_no = 'V-1001';
set feedback on

-- ---------------------------------------------------------------------------
-- The same job, with the memory taken off the acting desk
-- ---------------------------------------------------------------------------
-- The run above spent half of its tool calls writing notes to itself, hit the
-- limit of 8 in the model configuration, and stopped without telling the clerk
-- anything.
--
-- Lesson 5 said not to give memory to the desk that acts. This is what that
-- advice is worth in tool calls.
begin
  uc_ai_memory.disable_for_agent(p_agent_code => 'AP_DESK');
  commit;
  sys.dbms_output.put_line('memory disabled for AP_DESK');
end;
/

variable clean_session varchar2(255)

declare
  l_result  json_object_t;
  l_session varchar2(255 char);
begin
  l_session      := uc_ai_agents_api.generate_session_id;
  :clean_session := l_session;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'AP_DESK'
  , p_input_parameters => json_object_t('{"entity":"Ferrolux Deutschland GmbH"
      ,"clerk_name":"Petra","today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"Process INV-88006 from Ostwald Hydraulik: read it, read the covering email, approve it if the database allows it, and reply to the supplier."}')
  , p_session_id       => l_session
    -- No vendor_no needed now: the memory that was scoped on it is gone.
  , p_run_context      => json_object_t('{"invoice_id":"7007","clerk":"petra.k"}')
  );

  sys.dbms_output.put_line('--- what it told the clerk ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  commit;
end;
/

set feedback off
prompt
prompt Every step of THAT run:
select m.seq, m.role, m.tool_name
     , substr(coalesce(m.tool_input, m.tool_output, m.content), 1, 62) as detail
  from uc_ai_agent_messages m
 where m.session_id = :clean_session
 order by m.seq;

prompt
prompt And its execution row:
select e.status, e.tool_calls_count
     , e.total_input_tokens as in_tok, e.total_output_tokens as out_tok
  from uc_ai_agent_executions e
 where e.session_id = :clean_session;

prompt
prompt What it did:
select a.approval_no, a.amount, a.approved_by, a.source from ap_approvals a order by a.id;
select o.to_address, o.template_code from ap_outbox o order by o.id;
set feedback on

-- ---------------------------------------------------------------------------
-- The whole inbox, one agent run for each message
-- ---------------------------------------------------------------------------
-- Everything above looks at one invoice. A payables desk has a mailbox.
--
-- AP_TRIAGE reads and cannot act, so it is the agent to point at all five
-- messages. It answers in the fields of lesson 4, so the loop can store the
-- recommendation and the instructions it found next to the invoice.
set serveroutput on

declare
  l_result json_object_t;
  l_fields json_object_t;
  l_found  json_array_t;
  l_usage  json_object_t;
  l_runs   pls_integer := 0;
  l_in     number := 0;
  l_out    number := 0;
begin
  sys.dbms_output.put_line(rpad('INVOICE', 12) || rpad('VENDOR', 9)
    || rpad('RECOMMEND', 11) || rpad('HUMAN', 7) || 'INSTRUCTIONS FOUND');
  sys.dbms_output.put_line(rpad('-', 62, '-'));

  <<inbox>>
  for r in (
    select m.id      as message_id
         , i.id      as invoice_id
         , i.invoice_no
         , v.vendor_no
      from ap_messages m
      join ap_invoices i on i.id = m.invoice_id
      join ap_vendors  v on v.id = i.vendor_id
     where m.direction = 'IN'
     order by m.id
  ) loop
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => 'AP_TRIAGE'
    , p_input_parameters => json_object_t('{"entity":"Ferrolux Deutschland GmbH"
        ,"clerk_name":"Petra","today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
        ,"question":"Triage ' || r.invoice_no || '. Read the invoice, the vendor and the covering email."}')
    , p_session_id       => uc_ai_agents_api.generate_session_id
    , p_run_context      => json_object_t('{"invoice_id":"' || r.invoice_id
                                          || '","clerk":"petra.k"}')
    );

    -- A response schema makes final_message an OBJECT. get_clob returns an empty
    -- string here, with no error.
    l_fields := l_result.get_object('final_message');
    l_found  := l_fields.get_array('untrusted_instructions_found');

    sys.dbms_output.put_line(
         rpad(r.invoice_no, 12)
      || rpad(r.vendor_no, 9)
      || rpad(l_fields.get_string('recommendation'), 11)
      || rpad(case when l_fields.get_boolean('needs_human') then 'yes' else 'no' end, 7)
      || l_found.get_size);

    l_usage := l_result.get_object('usage');
    l_runs  := l_runs + 1;
    l_in    := l_in + nvl(l_usage.get_number('prompt_tokens'), 0);
    l_out   := l_out + nvl(l_usage.get_number('completion_tokens'), 0);
  end loop inbox;

  sys.dbms_output.put_line(rpad('-', 62, '-'));
  sys.dbms_output.put_line(l_runs || ' runs, ' || l_in || ' input tokens, '
    || l_out || ' output tokens.');

  commit;
end;
/

set feedback off
prompt
prompt That batch, from the audit trail. Newest five, because AP_TRIAGE also ran in lesson 4:
select i.invoice_no
     , e.status
     , e.tool_calls_count      as tools
     , e.total_input_tokens    as in_tok
     , e.total_output_tokens   as out_tok
     , e.run_context
  from uc_ai_agent_executions e
  join ap_invoices i
    on to_char(i.id) = json_value(e.run_context, '$.invoice_id')
 where e.agent_id = ( select a.id from uc_ai_agents a
                       where a.code = 'AP_TRIAGE' and a.version = 1 )
 order by e.started_at desc
 fetch first 5 rows only;

set feedback on
