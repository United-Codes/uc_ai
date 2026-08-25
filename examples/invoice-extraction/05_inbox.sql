-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 5
-- Run the whole inbox
-- ============================================================================
-- Five blocks:
--   1  the prompt and the schema become a row: a prompt profile
--   2  the agent over that profile
--   3  one agent run, and the type it gives back
--   4  the whole inbox, through the agent, one commit for each document
--   5  the trace and the cost of every run
--
-- Run lesson 4 first.
-- ============================================================================
-- Repeatable: block 1 creates the profile when it is absent and updates it when
-- it is already there. Block 3 puts every document back to NEW, so the whole
-- inbox runs again. That costs about 12000 tokens each time.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- 1. The prompt profile
-- ---------------------------------------------------------------------------
-- The system prompt and the response schema were constants inside a package
-- body. A better prompt was a compile and a deployment.
--
-- On a profile they are a row. A new version is an insert, the running version
-- is one status column, and you can see which version read which invoice.
prompt
prompt === 1. Register INV_EXTRACT ===
declare
  l_profile_id number;
  l_exists     pls_integer;

  c_description constant varchar2(400 char) :=
    'Reads one supplier document (PDF) and returns its header and line items.';

  c_system_prompt constant varchar2(4000 char) :=
'You read one supplier document and return its data.
Rules:
- Read every page. A total on page 1 is not the total when a later page adds charges.
- Copy what is printed. Never invent a value the document does not show.
- Every charge and every adjustment is a line item, wherever it is printed: goods,
  a service, delivery, freight, a discount, an early-payment discount.
- Tax is NOT a line item. Put the total tax in tax_amount and nowhere else.
- A discount or a credit line has a NEGATIVE line_total.
- net_amount is everything except tax. It is total_amount minus tax_amount, and it
  is the sum of the line items. When the document prints a subtotal that leaves out
  delivery or a discount, that subtotal is NOT net_amount.
- When the document does not show a field, return an empty string for a text field
  and 0 for an amount. Never invent a value.
- Decimal separators differ by country. 1.234,56 and 1,234.56 are the same amount.
- Return the date twice: exactly as printed, and as YYYY-MM-DD.
- When the document is not an invoice, say so in document_type and fill only what
  it really shows.';

  c_schema constant varchar2(4000 char) := '{
  "title": "Supplier Invoice",
  "type": "object",
  "properties": {
    "document_type":    { "type": "string",
                          "enum": ["INVOICE", "CREDIT_NOTE", "DELIVERY_NOTE", "OTHER"] },
    "supplier_name":    { "type": "string" },
    "invoice_number":   { "type": "string" },
    "invoice_date_raw": { "type": "string" },
    "invoice_date_iso": { "type": "string" },
    "po_number":        { "type": "string" },
    "currency":         { "type": "string",
                          "enum": ["EUR", "GBP", "USD", "CHF", "OTHER"] },
    "net_amount":       { "type": "number" },
    "tax_amount":       { "type": "number" },
    "total_amount":     { "type": "number" },
    "line_items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "position":    { "type": "integer" },
          "description": { "type": "string" },
          "kind":        { "type": "string",
                           "enum": ["GOODS", "SERVICE", "FREIGHT", "DISCOUNT", "OTHER"] },
          "quantity":    { "type": "number" },
          "unit_price":  { "type": "number" },
          "line_total":  { "type": "number" }
        },
        "required": ["position", "description", "kind", "quantity", "unit_price",
                     "line_total"],
        "additionalProperties": false
      }
    },
    "extraction_note":  { "type": "string" }
  },
  "required": ["document_type", "supplier_name", "invoice_number", "invoice_date_raw",
               "invoice_date_iso", "po_number", "currency", "net_amount", "tax_amount",
               "total_amount", "line_items", "extraction_note"],
  "additionalProperties": false
}';
begin
  -- rownum stops at the first hit: this asks "is there one?", not "how many?"
  select count(*)
    into l_exists
    from uc_ai_prompt_profiles
   where code = 'INV_EXTRACT'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'INV_EXTRACT'
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => 'Extract this document.'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_response_schema        => c_schema
    );
    sys.dbms_output.put_line('Profile INV_EXTRACT created, version 1.');
  else
    select id
      into l_profile_id
      from uc_ai_prompt_profiles
     where code = 'INV_EXTRACT'
       and version = 1;

    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_id                     => l_profile_id
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => 'Extract this document.'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_response_schema        => c_schema
    );
    sys.dbms_output.put_line('Profile INV_EXTRACT updated, version 1.');
  end if;

  -- create_prompt_profile makes a DRAFT, and a call that does not name a
  -- version resolves the latest ACTIVE one. Without this the profile cannot be
  -- found at all.
  uc_ai_prompt_profiles_api.change_status(
    p_id     => l_profile_id
  , p_status => uc_ai_prompt_profiles_api.c_status_active
  );

  commit;
  sys.dbms_output.put_line('Profile INV_EXTRACT is active.');
end;
/

-- ---------------------------------------------------------------------------
-- 2. The agent
-- ---------------------------------------------------------------------------
-- An agent of type 'profile' is a name in front of a prompt profile. It adds
-- three things the profile alone does not have:
--   * a row in uc_ai_agent_executions for every run
--   * the messages of every run in uc_ai_agent_messages
--   * the tokens of every run counted and stored for you
prompt
prompt === 2. Register INV_EXTRACT_AGENT ===
declare
  l_agent_id number;
  l_exists   pls_integer;
begin
  -- rownum stops at the first hit: this asks "is there one?", not "how many?"
  select count(*)
    into l_exists
    from uc_ai_agents
   where code = 'INV_EXTRACT_AGENT'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    -- @dblinter ignore(g-2135): the id is not needed again; change_status below works
    -- from the code and the version, the same way the profile block does
    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'INV_EXTRACT_AGENT'
    , p_description         => 'Reads one supplier document and returns its data.'
    , p_agent_type          => uc_ai_agents_api.c_type_profile
    , p_prompt_profile_code => 'INV_EXTRACT'
    , p_timeout_seconds     => 120
    );
    sys.dbms_output.put_line('Agent INV_EXTRACT_AGENT created, version 1.');
  else
    sys.dbms_output.put_line('Agent INV_EXTRACT_AGENT is already there.');
  end if;

  -- Same trap as the profile: create_agent makes a DRAFT, and a call that does
  -- not name a version resolves the latest ACTIVE one.
  uc_ai_agents_api.change_status(
    p_code    => 'INV_EXTRACT_AGENT'
  , p_version => 1
  , p_status  => uc_ai_agents_api.c_status_active
  );

  -- Not optional. UC AI writes the execution row in its own transaction, so an
  -- uncommitted agent row makes that insert wait for a lock it will never get.
  commit;
  sys.dbms_output.put_line('Agent INV_EXTRACT_AGENT is active.');
end;
/

-- ---------------------------------------------------------------------------
-- 3. One agent run
-- ---------------------------------------------------------------------------
-- The same PDF, the same schema, the same answer. One thing changes in your own
-- code, and it is the line that reads the answer.
prompt
prompt === 3. Run the agent over one PDF ===
declare
  l_blob    blob;
  l_files   uc_ai_message_api.t_files;
  l_result  json_object_t;
  l_invoice json_object_t;
  l_session varchar2(255 char) := uc_ai_agents_api.generate_session_id;
begin
  select content into l_blob from inv_documents where filename = 'halvorsen.pdf';

  l_files := uc_ai_message_api.t_files();
  l_files.extend;
  l_files(1).media_type := 'application/pdf';
  l_files(1).data_blob  := l_blob;
  l_files(1).filename   := 'halvorsen.pdf';

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code => 'INV_EXTRACT_AGENT'
  , p_files      => l_files
  , p_session_id => l_session
  );

  -- get_object, not get_clob. The profile carries the schema, so execute_agent
  -- already parsed the answer for you. This is the opposite of lesson 2.
  l_invoice := l_result.get_object('final_message');

  sys.dbms_output.put_line('get_object   -> '
    || case when l_invoice is null then '(null)' else 'an object' end);
  sys.dbms_output.put_line('get_clob len -> '
    || nvl(length(l_result.get_clob('final_message')), -1));
  sys.dbms_output.put_line('---');
  sys.dbms_output.put_line('invoice_no:   ' || l_invoice.get_string('invoice_number'));
  sys.dbms_output.put_line('total:        ' || l_invoice.get_number('total_amount'));
  sys.dbms_output.put_line('lines:        ' || l_invoice.get_array('line_items').get_size);
  sys.dbms_output.put_line('---');
  sys.dbms_output.put_line('execution_id: ' || l_result.get_number('execution_id'));
  sys.dbms_output.put_line('session_id:   ' || l_result.get_string('session_id'));
  sys.dbms_output.put_line('status:       ' || l_result.get_string('status'));
end;
/

-- ---------------------------------------------------------------------------
-- 4. The inbox
-- ---------------------------------------------------------------------------
-- Everything back to NEW, so the loop has work to do. In production a document
-- reaches NEW once and never goes back.
prompt
prompt === 4. Run the inbox ===
delete from inv_invoice_lines;
delete from inv_invoices;
delete from inv_extractions;
update inv_documents set status = 'NEW';
commit;

declare
  l_handled pls_integer;
begin
  l_handled := inv_extract_pkg.run_inbox;
  sys.dbms_output.put_line('Documents handled: ' || l_handled || '.');
end;
/

-- ---------------------------------------------------------------------------
-- 5. The trace and the cost
-- ---------------------------------------------------------------------------
column filename format a30
column status format a10
column reasons format a32
column invoice_no format a16

prompt
prompt -- what one invoice costs
select d.filename, x.seconds, x.prompt_tokens, x.completion_tokens
     , x.total_tokens
  from inv_extractions x
  join inv_documents d on d.id = x.document_id
 order by x.id;

prompt
prompt -- the whole inbox
select count(*) as documents
     , sum(x.total_tokens) as total_tokens
     , round(sum(x.seconds), 1) as seconds
  from inv_extractions x;

prompt
prompt -- the review queue
select d.filename, d.status, i.invoice_no
     , i.review_reasons as reasons, i.total_amount
  from inv_documents d
  left join inv_invoices i on i.document_id = d.id
 where d.status != 'POSTED'
 order by d.id;

prompt
prompt -- what went through with nobody looking at it
select d.filename, i.invoice_no, i.currency, i.total_amount
  from inv_invoices i
  join inv_documents d on d.id = i.document_id
 where i.needs_review = 'N'
 order by d.id;

-- ---------------------------------------------------------------------------
-- The trace UC AI kept for you
-- ---------------------------------------------------------------------------
-- Every row below was written by UC AI. Nothing in inv_extract_pkg fills these
-- tables, and they survive a rollback, because UC AI writes them in their own
-- transaction.

column role format a12
column detail format a52
prompt
prompt -- every run of the agent, newest first
select e.id as execution_id
     , e.status
     , e.total_input_tokens as in_tokens
     , e.total_output_tokens as out_tokens
     , round(extract(second from (e.completed_at - e.started_at))
             + extract(minute from (e.completed_at - e.started_at)) * 60, 1) as seconds
  from uc_ai_agent_executions e
 where e.agent_id = ( select a.id from uc_ai_agents a
                       where a.code = 'INV_EXTRACT_AGENT' )
 order by e.started_at desc
 fetch first 6 rows only;

prompt
prompt -- what the newest run actually did
-- Do not select m.content itself here. On the assistant row it is the whole
-- extraction JSON, and it is a CLOB, so it does not mix with a varchar2 column
-- in the same coalesce. Its length says enough.
select m.seq
     , m.role
     , m.tool_name
     , length(coalesce(m.tool_input, m.tool_output, m.content)) as chars
  from uc_ai_agent_messages m
 where m.session_id = ( select e.session_id
                          from uc_ai_agent_executions e
                         where e.agent_id = ( select a.id from uc_ai_agents a
                                               where a.code = 'INV_EXTRACT_AGENT' )
                         order by e.started_at desc
                         fetch first 1 row only )
 order by m.seq;

prompt
prompt -- from an invoice row back to the run that produced it
select i.invoice_no
     , x.execution_id
     , e.status
     , e.total_input_tokens + e.total_output_tokens as tokens
  from inv_invoices i
  join inv_extractions x on x.id = i.extraction_id
  join uc_ai_agent_executions e on e.id = x.execution_id
 order by i.invoice_no;
