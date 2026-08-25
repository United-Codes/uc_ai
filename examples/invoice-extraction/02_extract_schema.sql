-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 2
-- A schema the model must fill
-- ============================================================================
-- Three blocks:
--   1  what OpenAI really receives, with no model call and no cost
--   2  the extraction, and the type final_message has here
--   3  the same schema on a German invoice
--
-- Run lesson 1 first.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- 1. What OpenAI receives
-- ---------------------------------------------------------------------------
-- A small schema, on purpose. It has a description on every property, and it
-- names exactly ONE required field. Watch what comes out the other side.
prompt
prompt === 1. The schema after UC AI converts it ===
declare
  c_small constant varchar2(2000 char) := '{
  "title": "Invoice Header",
  "type": "object",
  "properties": {
    "invoice_number": { "type": "string",
                        "description": "The number the supplier gave this invoice" },
    "po_number":      { "type": "string",
                        "description": "Purchase order number, empty when there is none" },
    "currency":       { "type": "string", "enum": ["EUR", "GBP", "USD"],
                        "description": "Currency of the amounts" }
  },
  "required": ["invoice_number"],
  "additionalProperties": false
}';
  l_converted json_object_t;
  l_schema    json_object_t;
begin
  l_converted := uc_ai_structured_output.to_responses_api_format(json_object_t(c_small));
  l_schema    := l_converted.get_object('schema');

  sys.dbms_output.put_line('Schema name:  ' || l_converted.get_string('name'));
  sys.dbms_output.put_line('Required:     ' || l_schema.get_array('required').to_string);
  sys.dbms_output.put_line('po_number:    '
    || l_schema.get_object('properties').get_object('po_number').to_string);
  sys.dbms_output.put_line('currency:     '
    || l_schema.get_object('properties').get_object('currency').to_string);
end;
/

-- ---------------------------------------------------------------------------
-- 2. The extraction
-- ---------------------------------------------------------------------------
prompt
prompt === 2. Extract the FerroTek invoice ===
declare
  -- The schema the course uses from here on. inv_extract_pkg holds the same one.
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

  -- Every rule that a description would have carried has to live here, because
  -- the conversion in block 1 deleted all of them.
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

  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
  l_wrong    json_object_t;
  l_invoice  json_object_t;
  l_lines    json_array_t;
  l_line     json_object_t;
  l_sum      number := 0;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_messages.append(uc_ai_message_api.create_system_message(c_system_prompt));

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => 'ferrotek.pdf'
  ));
  l_content.append(uc_ai_message_api.create_text_content('Extract this document.'));
  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages             => l_messages
  , p_provider             => uc_ai.c_provider_openai
  , p_model                => uc_ai_openai.c_model_gpt_5_6_terra
  , p_response_json_schema => json_object_t(c_schema)
  );

  -- The way that does not work. No error, no warning, just null.
  l_wrong := l_result.get_object('final_message');
  sys.dbms_output.put_line('get_object  -> '
    || case when l_wrong is null then '(null)' else 'an object' end);
  sys.dbms_output.put_line('has structured_output -> '
    || case when l_result.has('structured_output') then 'yes' else 'no' end);

  -- The way that does.
  l_invoice := json_object_t(l_result.get_clob('final_message'));

  sys.dbms_output.put_line('---');
  sys.dbms_output.put_line('document_type: ' || l_invoice.get_string('document_type'));
  sys.dbms_output.put_line('supplier:      ' || l_invoice.get_string('supplier_name'));
  sys.dbms_output.put_line('invoice_no:    ' || l_invoice.get_string('invoice_number'));
  sys.dbms_output.put_line('date printed:  ' || l_invoice.get_string('invoice_date_raw'));
  sys.dbms_output.put_line('date parsed:   ' || l_invoice.get_string('invoice_date_iso'));
  sys.dbms_output.put_line('po_number:     ' || l_invoice.get_string('po_number'));
  sys.dbms_output.put_line('currency:      ' || l_invoice.get_string('currency'));
  sys.dbms_output.put_line('net / tax / total: '
    || l_invoice.get_number('net_amount') || ' / '
    || l_invoice.get_number('tax_amount') || ' / '
    || l_invoice.get_number('total_amount'));

  l_lines := l_invoice.get_array('line_items');
  sys.dbms_output.put_line('lines:         ' || l_lines.get_size);

  <<line_loop>>
  for i in 0 .. l_lines.get_size - 1 loop
    l_line := treat(l_lines.get(i) as json_object_t);
    l_sum := l_sum + l_line.get_number('line_total');
    sys.dbms_output.put_line('  ' || rpad(l_line.get_string('kind'), 9)
      || lpad(l_line.get_number('line_total'), 10) || '  '
      || substr(replace(l_line.get_string('description'), chr(10), ' '), 1, 44));
  end loop line_loop;

  sys.dbms_output.put_line('  sum of lines: ' || l_sum);
  sys.dbms_output.put_line('Tokens: ' || l_result.get_object('usage').to_clob);
end;
/

-- ---------------------------------------------------------------------------
-- 3. The same schema on a German invoice
-- ---------------------------------------------------------------------------
-- Different language, different layout, comma decimals, a date as DD.MM.YYYY,
-- and an early-payment discount printed below the totals. The schema does not
-- change, and neither does the prompt.
prompt
prompt === 3. The same schema on nordwind.pdf ===
-- inv_extract_pkg holds the same schema and the same prompt, so from here on
-- the course calls the package instead of repeating sixty lines of JSON.
declare
  l_document_id   inv_documents.id%type;
  l_extraction_id inv_extractions.id%type;
  l_raw           clob;
  l_invoice       json_object_t;
  l_lines         json_array_t;
  l_line          json_object_t;
  l_sum           number := 0;
  l_tokens        varchar2(200 char);
begin
  select id into l_document_id from inv_documents where filename = 'nordwind.pdf';

  update inv_documents set status = 'NEW' where id = l_document_id;

  l_extraction_id := inv_extract_pkg.extract_document(l_document_id);
  commit;

  select raw_json into l_raw from inv_extractions where id = l_extraction_id;
  l_invoice := json_object_t(l_raw);

  sys.dbms_output.put_line('supplier:      ' || l_invoice.get_string('supplier_name'));
  sys.dbms_output.put_line('invoice_no:    ' || l_invoice.get_string('invoice_number'));
  sys.dbms_output.put_line('date printed:  ' || l_invoice.get_string('invoice_date_raw'));
  sys.dbms_output.put_line('date parsed:   ' || l_invoice.get_string('invoice_date_iso'));
  sys.dbms_output.put_line('currency:      ' || l_invoice.get_string('currency'));
  sys.dbms_output.put_line('net / tax / total: '
    || l_invoice.get_number('net_amount') || ' / '
    || l_invoice.get_number('tax_amount') || ' / '
    || l_invoice.get_number('total_amount'));

  l_lines := l_invoice.get_array('line_items');

  <<line_loop>>
  for i in 0 .. l_lines.get_size - 1 loop
    l_line := treat(l_lines.get(i) as json_object_t);
    l_sum := l_sum + l_line.get_number('line_total');
    sys.dbms_output.put_line('  ' || rpad(l_line.get_string('kind'), 9)
      || lpad(l_line.get_number('line_total'), 10) || '  '
      || substr(replace(l_line.get_string('description'), chr(10), ' '), 1, 44));
  end loop line_loop;

  sys.dbms_output.put_line('  sum of lines: ' || l_sum);

  -- extract_document already stored the usage of this run, so read it back
  -- instead of asking the provider a second time.
  select 'Tokens: prompt_tokens ' || x.prompt_tokens
         || ', completion_tokens ' || x.completion_tokens
         || ', total_tokens ' || x.total_tokens
    into l_tokens
    from inv_extractions x
   where x.id = l_extraction_id;

  sys.dbms_output.put_line(l_tokens);
end;
/
