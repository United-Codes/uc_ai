create or replace package body inv_extract_pkg as

  -- ==========================================================================
  -- The prompt
  -- ==========================================================================
  -- Every rule here exists because a run without it gave a worse answer. Three
  -- of them are worth knowing about before you change any of it:
  --
  --   "Read every page"      halvorsen.pdf prints its totals on page 2, under a
  --                          line that says not to pay from page 1.
  --   "Tax is NOT a line"    with tax allowed as a line kind, two of three runs
  --                          over the same PDF added a tax line and one did not,
  --                          so the sum check compared a different thing each time.
  --   "net_amount is ..."    ferrotek.pdf prints a subtotal that leaves out the
  --                          delivery charge. "As printed" is not a definition.
  --
  -- The rules live here and not in the schema on purpose. On OpenAI and on
  -- Anthropic, UC AI removes every "description" from the schema before it is
  -- sent, so a rule written there never reaches the model.

  c_system_prompt constant varchar2(4000 char) :=
    'You read one supplier document and return its data.' || chr(10)
    || 'Rules:' || chr(10)
    || '- Read every page. A total on page 1 is not the total when a later page '
    || 'adds charges.' || chr(10)
    || '- Copy what is printed. Never invent a value the document does not show.' || chr(10)
    || '- Every charge and every adjustment is a line item, wherever it is printed: '
    || 'goods, a service, delivery, freight, a discount, an early-payment discount.' || chr(10)
    || '- Tax is NOT a line item. Put the total tax in tax_amount and nowhere else.' || chr(10)
    || '- A discount or a credit line has a NEGATIVE line_total.' || chr(10)
    || '- net_amount is everything except tax. It is total_amount minus tax_amount, '
    || 'and it is the sum of the line items. When the document prints a subtotal '
    || 'that leaves out delivery or a discount, that subtotal is NOT net_amount.' || chr(10)
    || '- When the document does not show a field, return an empty string for a text '
    || 'field and 0 for an amount. Never invent a value.' || chr(10)
    || '- Decimal separators differ by country. 1.234,56 and 1,234.56 are the same '
    || 'amount.' || chr(10)
    || '- Return the date twice: exactly as printed, and as YYYY-MM-DD.' || chr(10)
    || '- When the document is not an invoice, say so in document_type and fill only '
    || 'what it really shows.';

  -- ==========================================================================
  -- The schema
  -- ==========================================================================
  -- Two things in here are not decoration:
  --
  --   document_type   an enum survives the conversion to the OpenAI format,
  --                   while a description does not. It is the only field your
  --                   PL/SQL can branch on to keep a delivery note out.
  --   invoice_date_*  the printed string AND the parsed date. Without the raw
  --                   string you cannot tell afterwards how 08/11/2026 was read.
  --
  -- An absent value is an empty string or 0, never null. On OpenAI every field
  -- is required whatever this list says, so absence has to BE a value.

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

  -- Two amounts agree when they are within a cent of each other. Comparing
  -- money with = is how a rounding difference becomes a support ticket.
  c_cent constant number := 0.005;

  e_already_posted exception;
  pragma exception_init(e_already_posted, -20901);


  -- ==========================================================================
  -- extract_document
  -- ==========================================================================
  function extract_document (
    p_document_id in inv_documents.id%type
  ) return inv_extractions.id%type
  as
    l_doc           inv_documents%rowtype;
    l_messages      json_array_t := json_array_t();
    l_content       json_array_t := json_array_t();
    l_result        json_object_t;
    l_usage         json_object_t;
    l_json          clob;
    l_start         number;
    l_seconds       number;
    l_extraction_id inv_extractions.id%type;
    l_error         varchar2(4000 char);
    l_prompt_tokens     number;
    l_completion_tokens number;
    l_total_tokens      number;
  begin
    select * into l_doc from inv_documents where id = p_document_id;

    -- A file is legal only inside a USER message. Put it in the system message
    -- and it is dropped without an error: the model answers from the text alone
    -- and tells you it never saw a document.
    l_messages.append(uc_ai_message_api.create_system_message(c_system_prompt));

    -- The filename is not decoration. UC AI leaves the key out when it is null,
    -- and OpenAI then answers HTTP 500.
    l_content.append(uc_ai_message_api.create_file_content(
      p_media_type => l_doc.media_type
    , p_data_blob  => l_doc.content
    , p_filename   => l_doc.filename
    ));
    l_content.append(uc_ai_message_api.create_text_content(
      'Extract this document.'));

    l_messages.append(uc_ai_message_api.create_user_message(l_content));

    l_start := sys.dbms_utility.get_time;

    l_result := uc_ai.generate_text(
      p_messages             => l_messages
    , p_provider             => uc_ai.c_provider_openai
    , p_model                => c_model
    , p_response_json_schema => json_object_t(c_schema)
    );

    l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);

    -- generate_text leaves final_message as TEXT that holds JSON, even with a
    -- response schema. Only an agent run parses it for you. get_object here
    -- returns null and raises nothing at all.
    l_json  := l_result.get_clob('final_message');
    l_usage := l_result.get_object('usage');

    -- Read every value OUT of the JSON object before the insert. A get_ call
    -- inside a SQL statement raises ORA-40573, because a PL/SQL JSON object
    -- cannot cross into SQL.
    l_prompt_tokens     := l_usage.get_number('prompt_tokens');
    l_completion_tokens := l_usage.get_number('completion_tokens');
    l_total_tokens      := l_usage.get_number('total_tokens');

    insert into inv_extractions (
      document_id, model, seconds, prompt_tokens, completion_tokens
    , total_tokens, raw_json
    ) values (
      p_document_id, c_model, l_seconds
    , l_prompt_tokens, l_completion_tokens, l_total_tokens, l_json
    ) returning id into l_extraction_id;

    update inv_documents set status = 'EXTRACTED' where id = p_document_id;

    return l_extraction_id;
  exception
    when others then
      -- The run is evidence either way. A failed extraction that leaves no row
      -- behind is a failure you cannot look at afterwards.
      -- @dblinter ignore(g-5040): every provider and parsing error is recorded on the
      -- extraction row and re-raised below, so one handler is correct here
      -- @dblinter ignore(g-5080): the handler records the message and then re-raises with
      -- a bare `raise`, which keeps the original error and its backtrace for the caller
      -- sqlerrm is a PL/SQL function, so it cannot go straight into an insert.
      l_error := substr(sqlerrm, 1, 4000);

      insert into inv_extractions (document_id, model, error_message)
      values (p_document_id, c_model, l_error)
      returning id into l_extraction_id;

      update inv_documents set status = 'FAILED' where id = p_document_id;

      raise;
  end extract_document;


  -- ==========================================================================
  -- extract_with_agent
  -- ==========================================================================
  -- Same document, same schema, same answer. One different call.
  --
  -- Two things change, and both are the reason lesson 5 exists:
  --   * final_message arrives as a JSON OBJECT, because execute_agent parses it
  --     when the profile carries a response schema. get_clob returns nothing.
  --   * the run leaves a trace: one row in uc_ai_agent_executions, and the
  --     messages of the turn in uc_ai_agent_messages.
  function extract_with_agent (
    p_document_id in inv_documents.id%type
  ) return inv_extractions.id%type
  as
    l_doc           inv_documents%rowtype;
    l_files         uc_ai_message_api.t_files;
    l_result        json_object_t;
    l_answer        json_object_t;
    l_usage         json_object_t;
    l_json          clob;
    l_session       varchar2(255 char) := uc_ai_agents_api.generate_session_id;
    l_start         number;
    l_seconds       number;
    l_extraction_id inv_extractions.id%type;
    l_error         varchar2(4000 char);
    l_execution_id  number;
    l_prompt_tokens     number;
    l_completion_tokens number;
    l_total_tokens      number;
  begin
    select * into l_doc from inv_documents where id = p_document_id;

    -- t_files is a collection. Every entry needs the same three values you gave
    -- create_file_content in lesson 1, and the filename has no default here
    -- either.
    l_files := uc_ai_message_api.t_files();
    l_files.extend;
    l_files(1).media_type := l_doc.media_type;
    l_files(1).data_blob  := l_doc.content;
    l_files(1).filename   := l_doc.filename;

    l_start := sys.dbms_utility.get_time;

    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code => c_agent_code
    , p_files      => l_files
    , p_session_id => l_session
    );

    l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);

    -- get_object, not get_clob. This is the opposite of lesson 2, and it is the
    -- one thing that changes in your own code when you move to an agent.
    l_answer := l_result.get_object('final_message');
    l_json   := l_answer.to_clob;

    l_usage             := l_result.get_object('usage');
    l_prompt_tokens     := l_usage.get_number('prompt_tokens');
    l_completion_tokens := l_usage.get_number('completion_tokens');
    l_total_tokens      := l_usage.get_number('total_tokens');
    l_execution_id      := l_result.get_number('execution_id');

    insert into inv_extractions (
      document_id, model, seconds, prompt_tokens, completion_tokens
    , total_tokens, execution_id, session_id, raw_json
    ) values (
      p_document_id, c_model, l_seconds
    , l_prompt_tokens, l_completion_tokens, l_total_tokens
    , l_execution_id, l_session, l_json
    ) returning id into l_extraction_id;

    update inv_documents set status = 'EXTRACTED' where id = p_document_id;

    return l_extraction_id;
  exception
    when others then
      -- @dblinter ignore(g-5040): every provider and parsing error is recorded on the
      -- extraction row and re-raised below, so one handler is correct here
      -- @dblinter ignore(g-5080): the handler records the message and then re-raises with
      -- a bare `raise`, which keeps the original error and its backtrace for the caller
      l_error := substr(sqlerrm, 1, 4000);

      insert into inv_extractions (document_id, model, session_id, error_message)
      values (p_document_id, c_model, l_session, l_error)
      returning id into l_extraction_id;

      update inv_documents set status = 'FAILED' where id = p_document_id;

      raise;
  end extract_with_agent;


  -- ==========================================================================
  -- validate_extraction
  -- ==========================================================================
  function validate_extraction (
    p_extraction_id in inv_extractions.id%type
  ) return varchar2
  as
    l_raw       clob;
    l_inv       json_object_t;
    l_lines     json_array_t;
    l_line      json_object_t;
    l_reasons   varchar2(400 char);
    l_line_sum  number := 0;
    l_net       number;
    l_tax       number;
    l_total     number;
    l_date_raw  varchar2(60 char);
    l_first     number;
    l_second    number;
    l_po_number varchar2(40 char);
    l_po        inv_purchase_orders%rowtype;

    -- @dblinter ignore(g-7130): add_reason exists to append to l_reasons of the block
    -- around it. Passing the list in and out of every call would hide what the five
    -- checks below do, which is the one thing this function has to make obvious.
    procedure add_reason (p_reason in varchar2)
    as
    begin
      l_reasons := case when l_reasons is null then p_reason
                        else l_reasons || ', ' || p_reason
                   end;
    end add_reason;
  begin
    select raw_json into l_raw from inv_extractions where id = p_extraction_id;

    if l_raw is null then
      return 'NO_ANSWER';
    end if;

    l_inv := json_object_t(l_raw);

    -- ---------------------------------------------------------------------
    -- 1. Is it an invoice at all?
    -- ---------------------------------------------------------------------
    -- The model reads a delivery note correctly and says so. What it cannot do
    -- is stop your code from posting the row. Only this check does that.
    -- nvl matters. An absent key gives NULL, NULL != 'INVOICE' is NULL, and the
    -- document would pass the one check that exists to stop it.
    if nvl(l_inv.get_string('document_type'), 'MISSING') != 'INVOICE' then
      add_reason('NOT_AN_INVOICE');
    end if;

    -- ---------------------------------------------------------------------
    -- 2. Does the document agree with itself?
    -- ---------------------------------------------------------------------
    -- get_number, not to_number on a string. A JSON number always has a dot,
    -- and to_number reads it with the decimal separator of YOUR session.
    l_net   := l_inv.get_number('net_amount');
    l_tax   := l_inv.get_number('tax_amount');
    l_total := l_inv.get_number('total_amount');
    l_lines := l_inv.get_array('line_items');

    <<line_loop>>
    for i in 0 .. l_lines.get_size - 1 loop
      l_line := treat(l_lines.get(i) as json_object_t);
      l_line_sum := l_line_sum + l_line.get_number('line_total');
    end loop line_loop;

    -- Only for a document that says it is an invoice. A delivery note is all
    -- zeros, and zeros add up perfectly.
    --
    -- Guard on the TYPE, not on the amount. "Skip the check when the total is 0"
    -- reads the same and is a hole: an invoice that the model read so badly that
    -- it returned 0 is exactly the case SUM_MISMATCH exists for.
    if nvl(l_inv.get_string('document_type'), 'MISSING') = 'INVOICE'
       and ( abs(l_line_sum - l_net) > c_cent
             or abs(l_net + l_tax - l_total) > c_cent )
    then
      add_reason('SUM_MISMATCH');
    end if;

    -- ---------------------------------------------------------------------
    -- 3. Can the printed date be read two ways?
    -- ---------------------------------------------------------------------
    -- 08/11/2026 is 11 August in Cleveland and 8 November in Leeds. The model
    -- picks one and never says which. The honest answer is that the day is not
    -- on the document, so a person decides.
    l_date_raw := l_inv.get_string('invoice_date_raw');

    if regexp_like(l_date_raw, '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$') then
      l_first  := to_number(regexp_substr(l_date_raw, '^[0-9]{1,2}'));
      l_second := to_number(regexp_substr(l_date_raw, '[0-9]{1,2}', 1, 2));

      if l_first <= 12 and l_second <= 12 then
        add_reason('DATE_AMBIGUOUS');
      end if;
    end if;

    -- ---------------------------------------------------------------------
    -- 4 and 5. Is there an order, and does the invoice stay inside it?
    -- ---------------------------------------------------------------------
    -- This is the part no prompt can reach. The purchase order is not printed
    -- on the invoice in any form the model could check.
    l_po_number := l_inv.get_string('po_number');

    begin
      select * into l_po
        from inv_purchase_orders
       where po_number = l_po_number;

      if l_po.status != 'OPEN' then
        add_reason('PO_NOT_FOUND');
      elsif l_net > l_po.amount_limit then
        add_reason('OVER_PO');
      end if;
    exception
      when no_data_found then
        -- An empty po_number lands here as well, which is the right answer:
        -- an invoice with no order is an invoice nobody agreed to.
        add_reason('PO_NOT_FOUND');
    end;

    return l_reasons;
  end validate_extraction;


  -- ==========================================================================
  -- post_extraction
  -- ==========================================================================
  function post_extraction (
    p_extraction_id in inv_extractions.id%type
  ) return inv_invoices.id%type
  as
    l_extraction  inv_extractions%rowtype;
    l_inv         json_object_t;
    l_lines       json_array_t;
    l_line        json_object_t;
    l_reasons     varchar2(400 char);
    l_invoice_id  inv_invoices.id%type;
    l_iso         varchar2(60 char);
    l_date        date;

    -- Locals for every value that goes into a SQL statement. See ORA-40573 in
    -- extract_document: a json_object_t method cannot be called inside SQL.
    l_supplier    varchar2(200 char);
    l_invoice_no  varchar2(60 char);
    l_date_raw    varchar2(60 char);
    l_po_number   varchar2(40 char);
    l_currency    varchar2(5 char);
    l_net         number;
    l_tax         number;
    l_total       number;
    l_description varchar2(400 char);
    l_kind        varchar2(10 char);
    l_position    number;
    l_quantity    number;
    l_unit_price  number;
    l_line_total  number;
    l_already     pls_integer;
  begin
    select * into l_extraction from inv_extractions where id = p_extraction_id;

    if l_extraction.raw_json is null then
      return null;
    end if;

    l_inv     := json_object_t(l_extraction.raw_json);
    l_reasons := validate_extraction(p_extraction_id);

    -- An empty string is what the schema returns for an absent date, and
    -- to_date on it would raise. Absence is a value here, so test for it.
    l_iso := l_inv.get_string('invoice_date_iso');
    l_date := case when l_iso is not null and length(l_iso) = 10
                   then to_date(l_iso, 'YYYY-MM-DD')
              end;

    -- substr on every one of them. The schema puts no maximum length on a string,
    -- and Anthropic removes maxLength even when you write one. A value that is one
    -- character too long raises ORA-06502 in the middle of a transaction.
    l_supplier   := substr(l_inv.get_string('supplier_name'), 1, 200);
    l_invoice_no := substr(l_inv.get_string('invoice_number'), 1, 60);
    l_date_raw   := substr(l_inv.get_string('invoice_date_raw'), 1, 60);
    l_po_number  := substr(l_inv.get_string('po_number'), 1, 40);
    l_currency   := substr(l_inv.get_string('currency'), 1, 5);
    l_net        := l_inv.get_number('net_amount');
    l_tax        := l_inv.get_number('tax_amount');
    l_total      := l_inv.get_number('total_amount');

    -- Two things make a document impossible to post, rather than only doubtful:
    -- it is not an invoice, and it has no number to key it by. An empty string in
    -- JSON arrives here as NULL, and inv_invoices.invoice_no is NOT NULL.
    -- Every other reason IS posted and flagged, because somebody has to see it.
    if instr(l_reasons, 'NOT_AN_INVOICE') > 0 or l_invoice_no is null then
      update inv_documents
         set status = 'REVIEW'
       where id = l_extraction.document_id;
      return null;
    end if;

    -- The same DOCUMENT twice and the same INVOICE twice are different facts, and
    -- a clerk looks in a different place for each. dup_val_on_index cannot tell
    -- them apart, so ask about the document before the insert.
    -- rownum stops at the first hit: this asks "is there one?", not "how many?"
    select count(*)
      into l_already
      from inv_invoices
     where document_id = l_extraction.document_id
       and rownum = 1;

    if l_already > 0 then
      raise_application_error(-20902
      , 'This document is already posted: document ' || l_extraction.document_id);
    end if;

    -- What is left can only be the key on the supplier and the invoice number.
    begin
      insert into inv_invoices (
        document_id, extraction_id, supplier_name, invoice_no, invoice_date
      , invoice_date_raw, po_number, currency, net_amount, tax_amount
      , total_amount, needs_review, review_reasons
      ) values (
        l_extraction.document_id
      , p_extraction_id
      , l_supplier
      , l_invoice_no
      , l_date
      , l_date_raw
      , l_po_number
      , l_currency
      , l_net
      , l_tax
      , l_total
      , case when l_reasons is null then 'N' else 'Y' end
      , l_reasons
      ) returning id into l_invoice_id;
    exception
      when dup_val_on_index then
        raise_application_error(-20901
        , 'This invoice is already posted: ' || l_supplier || ' ' || l_invoice_no);
    end;

    l_lines := l_inv.get_array('line_items');

    <<line_loop>>
    for i in 0 .. l_lines.get_size - 1 loop
      l_line := treat(l_lines.get(i) as json_object_t);

      -- A description can arrive with a line break in it, because that is how
      -- the part number sits under the text on the page.
      l_description := substr(
        regexp_replace(l_line.get_string('description'), '\s+', ' '), 1, 400);
      l_position    := l_line.get_number('position');
      l_kind        := l_line.get_string('kind');
      l_quantity    := l_line.get_number('quantity');
      l_unit_price  := l_line.get_number('unit_price');
      l_line_total  := l_line.get_number('line_total');

      -- @dblinter ignore(g-3210): an invoice has a handful of lines, and the loop reads
      -- one JSON object at a time. A forall would need six collections built first and
      -- would say less about what is happening.
      insert into inv_invoice_lines (
        invoice_id, seq, position, description, kind, quantity, unit_price
      , line_total
      ) values (
        l_invoice_id, i + 1, l_position, l_description, l_kind, l_quantity
      , l_unit_price, l_line_total
      );
    end loop line_loop;

    update inv_documents
       set status = case when l_reasons is null then 'POSTED' else 'REVIEW' end
     where id = l_extraction.document_id;

    return l_invoice_id;
  end post_extraction;


  -- ==========================================================================
  -- run_inbox
  -- ==========================================================================
  function run_inbox return pls_integer
  as
    l_extraction_id inv_extractions.id%type;
    l_handled       pls_integer := 0;
    l_error         varchar2(4000 char);
  begin
    <<document_loop>>
    for doc in ( select id, filename
                   from inv_documents
                  where status = 'NEW'
                  order by id )
    loop
      begin
        -- Through the agent, so every document in the inbox leaves a trace.
        l_extraction_id := extract_with_agent(doc.id);
        l_extraction_id := post_extraction(l_extraction_id);

        -- One document, one transaction. A bad PDF at the end of the inbox must
        -- not roll back the nine good ones before it.
        -- @dblinter ignore(g-3310): the commit inside the loop is the design. Each
        -- document is its own unit of work, and a run of a hundred must not lose the
        -- ninety-nine that worked because the last one failed.
        commit;
        l_handled := l_handled + 1;
      exception
        when others then
          -- @dblinter ignore(g-5040): a document that cannot be handled must not stop
          -- the inbox, whichever of the two steps raised
          -- @dblinter ignore(g-5080): the message is recorded on the extraction row
          -- below; a backtrace of the framework would not help whoever reads the queue
          l_error := substr(sqlerrm, 1, 4000);
          rollback;

          -- extract_document records its own failures. A failure in the POSTING
          -- step does not go through it, and without this the document stays at
          -- EXTRACTED: not NEW, so a second run skips it, and not FAILED, so it
          -- appears nowhere. It falls out of the pipeline in silence.
          -- @dblinter ignore(g-3210): one document is one unit of work, so this marks
          -- the one document the loop is on. There is no set to update.
          update inv_documents set status = 'FAILED' where id = doc.id;

          -- @dblinter ignore(g-3210): the same, for the extraction row of that one
          -- document
          update inv_extractions
             set error_message = l_error
           where id = ( select max(x.id) from inv_extractions x
                         where x.document_id = doc.id );

          -- @dblinter ignore(g-3310): the commit keeps the FAILED status of this
          -- document and lets the loop go on to the next one
          commit;
          -- @dblinter ignore(g-5010): a tutorial prints its progress so the reader sees
          -- it in SQLcl; inv_extractions.error_message is the durable record
          sys.dbms_output.put_line('FAILED ' || doc.filename || ': '
            || substr(l_error, 1, 300));
      end;
    end loop document_loop;

    return l_handled;
  end run_inbox;

end inv_extract_pkg;
/
