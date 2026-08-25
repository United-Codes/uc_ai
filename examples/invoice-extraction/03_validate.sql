-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 3
-- Do not trust what you extracted
-- ============================================================================
-- Four blocks:
--   1  a document that is not an invoice, through a schema that cannot say so
--   2  the same document through the schema of this course
--   3  the five checks over all four documents
--   4  the same checks with no model call at all
--
-- Run lessons 1 and 2 first. Block 3 reuses an answer whenever one is already
-- stored, so it only pays for the documents no earlier lesson has read. After
-- lesson 2 and block 2 above, that is ferrotek.pdf and halvorsen.pdf, about
-- 7600 tokens. A second run of this script costs nothing at all.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- 1. The delivery note, through a schema with no document_type
-- ---------------------------------------------------------------------------
-- The model behaves well here. It does not invent an invoice. It gives you
-- zeros and it writes a warning, in English, in extraction_note.
--
-- Look at what that leaves in your hands: a supplier, a real purchase order and
-- a total of 0. Nothing in any FIELD says this must not be paid. The one thing
-- that does say it is a sentence no `case` statement can read.
prompt
prompt === 1. A delivery note, through a schema that cannot describe one ===
declare
  c_schema constant varchar2(2000 char) := '{
  "title": "Invoice Without Type",
  "type": "object",
  "properties": {
    "supplier_name":  { "type": "string" },
    "invoice_number": { "type": "string" },
    "po_number":      { "type": "string" },
    "currency":       { "type": "string", "enum": ["EUR", "GBP", "USD", "OTHER"] },
    "net_amount":     { "type": "number" },
    "tax_amount":     { "type": "number" },
    "total_amount":   { "type": "number" },
    "extraction_note":{ "type": "string" }
  },
  "required": ["supplier_name", "invoice_number", "po_number", "currency",
               "net_amount", "tax_amount", "total_amount", "extraction_note"],
  "additionalProperties": false
}';
  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
  l_out      json_object_t;
begin
  select content
    into l_blob
    from inv_documents
   where filename = 'ferrotek-delivery-note.pdf';

  l_messages.append(uc_ai_message_api.create_system_message(
    'You read supplier invoices and return the fields of the schema. '
    || 'Copy every value from the document.'));

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => 'ferrotek-delivery-note.pdf'
  ));
  l_content.append(uc_ai_message_api.create_text_content('Extract this document.'));
  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages             => l_messages
  , p_provider             => uc_ai.c_provider_openai
  , p_model                => uc_ai_openai.c_model_gpt_5_6_terra
  , p_response_json_schema => json_object_t(c_schema)
  );

  l_out := json_object_t(l_result.get_clob('final_message'));

  sys.dbms_output.put_line('supplier:      ' || l_out.get_string('supplier_name'));
  sys.dbms_output.put_line('invoice_no:   [' || l_out.get_string('invoice_number') || ']');
  sys.dbms_output.put_line('po_number:     ' || l_out.get_string('po_number'));
  sys.dbms_output.put_line('total_amount:  ' || l_out.get_number('total_amount'));
  sys.dbms_output.put_line('note:          ' || l_out.get_string('extraction_note'));
end;
/

-- ---------------------------------------------------------------------------
-- 2. The same document, with document_type in the schema
-- ---------------------------------------------------------------------------
-- One enum field, and now the answer carries a value your code can branch on.
-- Note the invoice_number: the model fills it with the delivery-note number,
-- because the field asked for a number and the document has one.
prompt
prompt === 2. The same document, through the schema of this course ===
declare
  l_document_id   inv_documents.id%type;
  l_extraction_id inv_extractions.id%type;
  l_raw           clob;
  l_out           json_object_t;
begin
  select id
    into l_document_id
    from inv_documents
   where filename = 'ferrotek-delivery-note.pdf';

  update inv_documents set status = 'NEW' where id = l_document_id;

  l_extraction_id := inv_extract_pkg.extract_document(l_document_id);
  commit;

  select raw_json into l_raw from inv_extractions where id = l_extraction_id;
  l_out := json_object_t(l_raw);

  sys.dbms_output.put_line('document_type: ' || l_out.get_string('document_type'));
  sys.dbms_output.put_line('invoice_no:   [' || l_out.get_string('invoice_number') || ']');
  sys.dbms_output.put_line('total_amount:  ' || l_out.get_number('total_amount'));
  sys.dbms_output.put_line('checks:       ['
    || inv_extract_pkg.validate_extraction(l_extraction_id) || ']');
end;
/

-- ---------------------------------------------------------------------------
-- 3. The five checks over the whole inbox
-- ---------------------------------------------------------------------------
prompt
prompt === 3. Every document, checked ===
declare
  l_extraction_id inv_extractions.id%type;
begin
  <<document_loop>>
  for doc in ( select id, filename, status from inv_documents order by id ) loop
    -- Reuse an answer that is already here. A second run of the model would
    -- cost tokens and could give a slightly different wording.
    -- max() over no rows returns one row holding NULL, so there is no
    -- no_data_found to handle here.
    select max(id)
      into l_extraction_id
      from inv_extractions
     where document_id = doc.id
       and raw_json is not null;

    if l_extraction_id is null then
      l_extraction_id := inv_extract_pkg.extract_document(doc.id);
      -- @dblinter ignore(g-3310): each document is its own unit of work here, exactly
      -- as it is in inv_extract_pkg.run_inbox
      commit;
    end if;

    sys.dbms_output.put_line(rpad(doc.filename, 30)
      || '[' || inv_extract_pkg.validate_extraction(l_extraction_id) || ']');
  end loop document_loop;
end;
/

-- ---------------------------------------------------------------------------
-- 4. The same checks, with no model call
-- ---------------------------------------------------------------------------
-- This is the block worth keeping. Every branch of validate_extraction is
-- proved here from hand-written JSON, in under a second and for no tokens.
--
-- SUM_MISMATCH is the reason none of the four real documents produced. Here is
-- the day it does: a model that read only page 1 of a two-page invoice.
prompt
prompt === 4. The checks, proved without a model ===
declare
  l_document_id inv_documents.id%type;

  -- @dblinter ignore(g-7130): check_json reads l_document_id of the block around it. It
  -- is the same document for every one of the eight payloads, and threading it through
  -- a second parameter would only make the eight calls harder to compare.
  function check_json (p_json in clob) return varchar2
  as
    l_id      inv_extractions.id%type;
    l_reasons varchar2(400 char);
  begin
    insert into inv_extractions (document_id, model, raw_json)
    values (l_document_id, 'none', p_json)
    returning id into l_id;

    l_reasons := inv_extract_pkg.validate_extraction(l_id);

    delete from inv_extractions where id = l_id;

    return l_reasons;
  end check_json;
begin
  select id into l_document_id from inv_documents where filename = 'ferrotek.pdf';

  -- A clean invoice against a purchase order that is open and big enough.
  sys.dbms_output.put_line('clean            -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-1","invoice_date_raw":"14 July 2026",
    "invoice_date_iso":"2026-07-14","po_number":"PO-4500198231","currency":"GBP",
    "net_amount":1000,"tax_amount":200,"total_amount":1200,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":1000,"line_total":1000}],"extraction_note":""}') || ']');

  -- Only page 1 was read: the lines and the totals no longer agree.
  sys.dbms_output.put_line('page 1 only      -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-2","invoice_date_raw":"14 July 2026",
    "invoice_date_iso":"2026-07-14","po_number":"PO-4500198231","currency":"GBP",
    "net_amount":1000,"tax_amount":200,"total_amount":1200,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":600,"line_total":600}],"extraction_note":""}') || ']');

  -- 08/11/2026: two numbers under 13, either side of the slash.
  sys.dbms_output.put_line('ambiguous date   -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-3","invoice_date_raw":"08/11/2026",
    "invoice_date_iso":"2026-08-11","po_number":"PO-4500198231","currency":"GBP",
    "net_amount":1000,"tax_amount":200,"total_amount":1200,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":1000,"line_total":1000}],"extraction_note":""}') || ']');

  -- 25/11/2026 is not ambiguous: only one of the two numbers can be a month.
  sys.dbms_output.put_line('unambiguous date -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-4","invoice_date_raw":"25/11/2026",
    "invoice_date_iso":"2026-11-25","po_number":"PO-4500198231","currency":"GBP",
    "net_amount":1000,"tax_amount":200,"total_amount":1200,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":1000,"line_total":1000}],"extraction_note":""}') || ']');

  -- A purchase order nobody raised.
  sys.dbms_output.put_line('unknown PO       -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-5","invoice_date_raw":"14 July 2026",
    "invoice_date_iso":"2026-07-14","po_number":"PO-9999999999","currency":"GBP",
    "net_amount":1000,"tax_amount":200,"total_amount":1200,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":1000,"line_total":1000}],"extraction_note":""}') || ']');

  -- A purchase order that is closed.
  sys.dbms_output.put_line('closed PO        -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-6","invoice_date_raw":"14 July 2026",
    "invoice_date_iso":"2026-07-14","po_number":"PO-4500197004","currency":"GBP",
    "net_amount":100,"tax_amount":20,"total_amount":120,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":100,"line_total":100}],"extraction_note":""}') || ']');

  -- More than the purchase order allows.
  sys.dbms_output.put_line('over the PO      -> [' || check_json('{
    "document_type":"INVOICE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"FT-7","invoice_date_raw":"14 July 2026",
    "invoice_date_iso":"2026-07-14","po_number":"PO-4500198231","currency":"GBP",
    "net_amount":9000,"tax_amount":1800,"total_amount":10800,
    "line_items":[{"position":1,"description":"x","kind":"GOODS","quantity":1,
    "unit_price":9000,"line_total":9000}],"extraction_note":""}') || ']');

  -- Not an invoice at all, and no purchase order either.
  sys.dbms_output.put_line('two failures     -> [' || check_json('{
    "document_type":"DELIVERY_NOTE","supplier_name":"FerroTek Components Ltd",
    "invoice_number":"DN-1","invoice_date_raw":"11 July 2026",
    "invoice_date_iso":"2026-07-11","po_number":"","currency":"OTHER",
    "net_amount":0,"tax_amount":0,"total_amount":0,
    "line_items":[],"extraction_note":""}') || ']');

  rollback;
end;
/
