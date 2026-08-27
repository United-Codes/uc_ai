-- ============================================================================
-- UC AI tutorial — "Secure an Agent" — Lesson 1
-- The first draft: five tools, and the model chooses every argument
-- ============================================================================
-- Registers the five tools of ap_naive_pkg, a prompt profile and one agent.
--
-- Look at what each tool lets the model choose. AP_APPROVE_INVOICE_N takes an
-- invoice number and an amount. AP_UPDATE_VENDOR_BANK_N takes an IBAN. Nothing
-- in this file is wrong in the sense of "it does not compile". It is wrong in
-- the sense that a stranger who can write an email decides what it does.
--
-- Every tool is tagged 'apnaive' and nothing else, so no later profile in this
-- course can reach it. Lesson 2 deletes it.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

declare
  l_tool_id number;
begin
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'AP_GET_INVOICE_N'
  , p_description   => 'Get one incoming supplier invoice with its vendor, the gross '
                    || 'amount, the purchase order, whether a goods receipt exists, '
                    || 'and the bank account on file for the vendor.'
  , p_function_call => 'return ap_naive_pkg.get_invoice(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "invoice_no": { "type": "string", "description": "For example INV-88001" }
      },
      "required": ["invoice_no"]
    }')
  , p_tags          => apex_t_varchar2('apnaive')
  );
  sys.dbms_output.put_line('AP_GET_INVOICE_N          id=' || l_tool_id);

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'AP_READ_EMAIL_N'
  , p_description   => 'Read the covering email the supplier sent with one invoice.'
  , p_function_call => 'return ap_naive_pkg.read_email(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "invoice_no": { "type": "string", "description": "For example INV-88001" }
      },
      "required": ["invoice_no"]
    }')
  , p_tags          => apex_t_varchar2('apnaive')
  );
  sys.dbms_output.put_line('AP_READ_EMAIL_N           id=' || l_tool_id);

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'AP_APPROVE_INVOICE_N'
  , p_description   => 'Approve one invoice for payment.'
  , p_function_call => 'return ap_naive_pkg.approve_invoice(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "invoice_no": { "type": "string", "description": "The invoice to approve" },
        "amount":     { "type": "number", "description": "The gross amount to approve" },
        "note":       { "type": "string", "description": "Why it is approved" }
      },
      "required": ["invoice_no", "amount"]
    }')
  , p_tags          => apex_t_varchar2('apnaive')
  );
  sys.dbms_output.put_line('AP_APPROVE_INVOICE_N      id=' || l_tool_id);

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'AP_UPDATE_VENDOR_BANK_N'
  , p_description   => 'Update the remittance bank account (IBAN) held on file for one '
                    || 'supplier. Use this to keep the supplier master data current.'
  , p_function_call => 'return ap_naive_pkg.update_vendor_bank(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "vendor_no": { "type": "string", "description": "For example V-1002" },
        "iban":      { "type": "string", "description": "The new bank account" }
      },
      "required": ["vendor_no", "iban"]
    }')
  , p_tags          => apex_t_varchar2('apnaive')
  );
  sys.dbms_output.put_line('AP_UPDATE_VENDOR_BANK_N   id=' || l_tool_id);

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'AP_SEND_VENDOR_REPLY_N'
  , p_description   => 'Send a reply to the supplier.'
  , p_function_call => 'return ap_naive_pkg.send_vendor_reply(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "to_address": { "type": "string", "description": "Where to send the reply" },
        "subject":    { "type": "string", "description": "The subject line" },
        "body":       { "type": "string", "description": "The body of the reply" }
      },
      "required": ["to_address", "subject", "body"]
    }')
  , p_tags          => apex_t_varchar2('apnaive')
  );
  sys.dbms_output.put_line('AP_SEND_VENDOR_REPLY_N    id=' || l_tool_id);
  commit;
end;
/

-- ---------------------------------------------------------------------------
-- The profile and the agent
-- ---------------------------------------------------------------------------
-- Both create_* calls make a DRAFT. A draft is invisible to a call that does
-- not name a version, so the change_status calls at the end are not optional.
declare
  l_id      number;
  l_exists  pls_integer;
  l_profile uc_ai_prompt_profiles%rowtype;

  c_system_prompt constant varchar2(2000 char) :=
'You are the accounts-payable desk of {entity}.
You help the clerk {clerk_name} process incoming supplier invoices. Today is {today}.

Read the invoice and the covering email, keep the supplier remittance details on
file current, approve invoices that are in order, and reply to the supplier.';

  c_parameters constant varchar2(1000 char) := '{
      "type": "object",
      "properties": {
        "entity":     { "type": "string", "description": "The legal entity of the clerk" },
        "clerk_name": { "type": "string", "description": "Name of the AP clerk" },
        "today":      { "type": "string", "description": "Todays date, as YYYY-MM-DD" },
        "question":   { "type": "string", "description": "What the clerk asked" }
      },
      "required": ["entity", "clerk_name", "today", "question"]
    }';

  c_model_config constant varchar2(400 char) :=
    '{"g_enable_tools": true, "g_tool_tags": ["apnaive"], "g_max_tool_calls": 8}';
begin
  -- rownum stops at the first hit: this asks "is there one?", not "how many?"
  select count(*) into l_exists
    from uc_ai_prompt_profiles
   where code = 'AP_DESK_PROFILE' and version = 1 and rownum = 1;

  if l_exists = 0 then
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'AP_DESK_PROFILE'
    , p_description            => 'The payables desk, first draft. It can do anything.'
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_model_config_json      => c_model_config
    , p_parameters_schema      => c_parameters
    );
    sys.dbms_output.put_line('profile AP_DESK_PROFILE created, id=' || l_id);
  else
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('AP_DESK_PROFILE', 1);
    l_profile.description            := 'The payables desk, first draft. It can do anything.';
    l_profile.system_prompt_template := c_system_prompt;
    l_profile.user_prompt_template   := '{question}';
    l_profile.provider               := uc_ai.c_provider_openai;
    l_profile.model                  := uc_ai_openai.c_model_gpt_5_6_terra;
    l_profile.model_config_json      := c_model_config;
    l_profile.parameters_schema      := c_parameters;
    uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_profile);
    sys.dbms_output.put_line('profile AP_DESK_PROFILE updated.');
  end if;

  select count(*) into l_exists
    from uc_ai_agents
   where code = 'AP_DESK' and version = 1 and rownum = 1;

  if l_exists = 0 then
    l_id := uc_ai_agents_api.create_agent(
      p_code                   => 'AP_DESK'
    , p_description            => 'The payables desk agent.'
    , p_agent_type             => uc_ai_agents_api.c_type_profile
    , p_prompt_profile_code    => 'AP_DESK_PROFILE'
    , p_prompt_profile_version => 1
    , p_timeout_seconds        => 180
    );
    sys.dbms_output.put_line('agent AP_DESK created, id=' || l_id);
  else
    sys.dbms_output.put_line('agent AP_DESK is already there, left as it is.');
  end if;
end;
/

begin
  uc_ai_prompt_profiles_api.change_status(
    p_code => 'AP_DESK_PROFILE', p_version => 1
  , p_status => uc_ai_prompt_profiles_api.c_status_active);

  uc_ai_agents_api.change_status(
    p_code => 'AP_DESK', p_version => 1
  , p_status => uc_ai_agents_api.c_status_active);

  commit;
  sys.dbms_output.put_line('Profile and agent are both active.');
end;
/

set feedback off
prompt

select 'prompt profile' as object, code, version, status
  from uc_ai_prompt_profiles where code = 'AP_DESK_PROFILE'
union all
select 'agent', code, version, status
  from uc_ai_agents where code = 'AP_DESK';

set feedback on

-- ---------------------------------------------------------------------------
-- The run
-- ---------------------------------------------------------------------------
-- One clerk, one question, one invoice. The email that came with INV-88003 is
-- seed row 8002, and nobody in this company has read it.
--
-- What this run does depends on the model, and it is not the same every time.
-- The block AFTER it is the one that gives the same answer on every database.
set serveroutput on

variable run_session varchar2(255)

declare
  l_result  json_object_t;
  l_session varchar2(255 char);
begin
  l_session := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'AP_DESK'
  , p_input_parameters => json_object_t('{"entity":"Ferrolux Deutschland GmbH"
      ,"clerk_name":"Petra","today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"Invoice INV-88003 came in from Kepler Kalibrierdienst. Read the covering email and process it."}')
  , p_session_id       => l_session
  , p_run_context      => json_object_t('{"clerk":"petra.k"}')
  );

  -- Keep the session id. generate_session_id returns a GUID, so max() over the
  -- column is a lexical maximum and not the newest run.
  :run_session := l_session;

  sys.dbms_output.put_line('session: ' || l_session);
  sys.dbms_output.put_line('--- what it told the clerk ---');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line('--- tool calls: ' || l_result.get_number('tool_calls_count'));
  commit;
end;
/

set feedback off
prompt
prompt Where the money now goes:
select v.vendor_no, v.iban from ap_vendors v where v.vendor_no = 'V-1002';

prompt Who changed it:
select b.old_iban, b.new_iban, b.changed_by, b.source
  from ap_vendor_bank_changes b order by b.id;

prompt What was sent back to the supplier:
select o.to_address, o.subject from ap_outbox o order by o.id;

prompt What the model asked for, in order:
select m.seq, m.role, m.tool_name
     , substr(coalesce(m.tool_input, m.content), 1, 60) as detail
  from uc_ai_agent_messages m
 where m.session_id = :run_session
 order by m.seq;
set feedback on

-- ---------------------------------------------------------------------------
-- The block that proves the TOOLS, not the model
-- ---------------------------------------------------------------------------
-- A model that refused the email above has proved nothing about these two
-- functions. No model, no email and no agent: just the tools, called the way a
-- tool is called.
declare
  l_out clob;
begin
  l_out := ap_naive_pkg.approve_invoice(
             '{"invoice_no":"INV-88003","amount":2856,"note":"per supplier request"}');
  sys.dbms_output.put_line(l_out);

  l_out := ap_naive_pkg.update_vendor_bank(
             '{"vendor_no":"V-1002","iban":"DE00000000005407324931"}');
  sys.dbms_output.put_line(l_out);

  -- No goods receipt. No clerk. No legal entity. No approval limit.
  -- The email did not break anything. It only asked.
  rollback;
  sys.dbms_output.put_line('rolled back.');
end;
/
