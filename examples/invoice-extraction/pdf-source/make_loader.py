#!/usr/bin/env python3
"""Generate ../00_load_pdfs.sql from the PDFs in ../pdf/.

The loader is a generated file. Never edit it by hand: run this after you
change build_pdfs.py, and check the result in.

    python3 make_loader.py

Why the PDF bytes are in the script at all: a tutorial has to be one command,
and the two portable alternatives both add work for the reader. A directory
object needs a DBA grant and the file has to reach the database server. An APEX
file upload needs an application. Hex chunks need nothing, and UC AI already
depends on APEX, so wwv_flow_api.varchar2_to_blob is always there.
"""

import binascii
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PDF_DIR = os.path.join(HERE, "..", "pdf")
OUT = os.path.join(HERE, "..", "00_load_pdfs.sql")
OUT_MATRIX = os.path.join(HERE, "..", "06_model_matrix.sql")

# A varchar2 in PL/SQL holds 32767 characters, so 2000 is far inside the limit
# and keeps a line short enough to read in a diff.
CHUNK = 2000

DOCUMENTS = [
    ("ferrotek.pdf", "A clean one-page invoice. Lessons 1, 2 and 4 use this one."),
    ("nordwind.pdf", "The same facts in a German layout, with comma decimals."),
    ("halvorsen.pdf", "Two pages. The amounts are all on page 2, and the date is ambiguous."),
    ("ferrotek-delivery-note.pdf", "Not an invoice at all. Lesson 3 needs this one."),
]

HEADER = """-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF"
-- Load the four sample documents into the inbox
-- ============================================================================
-- GENERATED FILE. Do not edit it by hand.
-- Run pdf-source/make_loader.py to build it again from pdf/*.pdf.
--
-- Each document goes in as hex chunks, so the script needs no directory object,
-- no DBA grant and no file on the database server. In production a row lands in
-- inv_documents from an APEX file upload or a mail interface instead.
--
-- Safe to run more than one time: it deletes the rows of an earlier run first.
-- Run 00_setup.sql before this.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on

delete from inv_invoice_lines;
delete from inv_invoices;
delete from inv_extractions;
delete from inv_documents;
commit;
"""

FOOTER = """
-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
declare
  l_docs pls_integer;
begin
  select count(*) into l_docs from inv_documents;
  sys.dbms_output.put_line('Documents in the inbox: ' || l_docs || '.');
  sys.dbms_output.put_line('Next: run 00_precheck.sql.');
end;
/
"""


MATRIX_TEMPLATE = r"""-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 5
-- Which model, and does it need reasoning?
-- ============================================================================
-- GENERATED FILE. Do not edit it by hand.
-- Run pdf-source/make_loader.py to build it again from pdf/*.pdf.
--
-- This is the measurement behind the model table in lesson 5. It is OPTIONAL:
-- the course works without it. Run it when you want the same numbers for your
-- own documents, which is the only way to know.
--
-- WHAT IT COSTS. About 30 calls to the provider and roughly 70000 tokens, which
-- is a few cents at current prices but far more than any other script here.
--
-- WHAT IT DOES. Three measurements, with the schema and the system prompt held
-- fixed, because those matter more than the model:
--   1  four model tiers over the four documents         16 calls
--   2  reasoning off, low and high on the CHEAPEST model 8 calls
--   3  the hardest case three times per tier             6 calls
--
-- Every run is scored in PL/SQL against values typed in by hand from the paper.
-- "OK" means the document type, the three amounts, the line count and the sum of
-- the lines are all right. Nothing here trusts the model to mark its own work.
--
-- Run 00_setup.sql, 00_load_pdfs.sql and the package first.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

declare
  -- The schema and the prompt of inv_extract_pkg, repeated here so that this
  -- script measures the model and nothing else.
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

  c_prompt constant varchar2(4000 char) :=
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

  c_cent constant number := 0.005;

  -- What the paper says. Typed in by hand, on purpose.
  type t_expect is record (
    doc_type varchar2(20 char)
  , net      number
  , tax      number
  , total    number
  , lines    pls_integer
  );
  type t_expects is table of t_expect index by varchar2(60 char);
  l_expect_map t_expects;

  c_runs constant pls_integer := 3;

  l_scan blob;

  -- One run, scored. The verdict is 'OK', or the first thing that is wrong.
  type t_outcome is record (verdict varchar2(200 char), tokens number);

  -- @dblinter ignore(g-7130): score reads l_expect_map of the block around it. The
  -- expectations are the same for every call, and passing them in would only make
  -- the six calls below harder to compare.
  function score (
    p_doc    in varchar2
  , p_blob   in blob
  , p_model  in uc_ai.model_type
  ) return t_outcome
  as
    l_m       json_array_t := json_array_t();
    l_c       json_array_t := json_array_t();
    l_r       json_object_t;
    l_out     json_object_t;
    l_li      json_array_t;
    l_line    json_object_t;
    l_sum     number := 0;
    l_e       t_expect;
    l_outcome t_outcome;
  begin
    l_e := l_expect_map(p_doc);
    l_m.append(uc_ai_message_api.create_system_message(c_prompt));
    l_c.append(uc_ai_message_api.create_file_content(
      p_media_type => 'application/pdf', p_data_blob => p_blob, p_filename => p_doc));
    l_c.append(uc_ai_message_api.create_text_content('Extract this document.'));
    l_m.append(uc_ai_message_api.create_user_message(l_c));

    l_r := uc_ai.generate_text(
      p_messages             => l_m
    , p_provider             => uc_ai.c_provider_openai
    , p_model                => p_model
    , p_response_json_schema => json_object_t(c_schema)
    );

    l_outcome.tokens := l_r.get_object('usage').get_number('total_tokens');
    l_out            := json_object_t(l_r.get_clob('final_message'));
    l_li             := l_out.get_array('line_items');

    <<line_loop>>
    for i in 0 .. l_li.get_size - 1 loop
      l_line := treat(l_li.get(i) as json_object_t);
      l_sum  := l_sum + l_line.get_number('line_total');
    end loop line_loop;

    l_outcome.verdict :=
      case
        when nvl(l_out.get_string('document_type'), 'MISSING') != l_e.doc_type
          then 'type=' || l_out.get_string('document_type')
        when abs(l_out.get_number('net_amount') - l_e.net) > c_cent
          then 'net=' || l_out.get_number('net_amount')
        when abs(l_out.get_number('tax_amount') - l_e.tax) > c_cent
          then 'tax=' || l_out.get_number('tax_amount')
        when abs(l_out.get_number('total_amount') - l_e.total) > c_cent
          then 'total=' || l_out.get_number('total_amount')
        when l_li.get_size != l_e.lines
          then 'lines=' || l_li.get_size
        when abs(l_sum - l_out.get_number('net_amount')) > c_cent
          then 'sum of lines=' || l_sum
        else 'OK'
      end;

    return l_outcome;
  exception
    when others then
      -- @dblinter ignore(g-5040): a failed run is a result here, not an error to raise
      -- @dblinter ignore(g-5080): the message goes in the table the script prints
      l_outcome.tokens  := 0;
      l_outcome.verdict := substr(sqlerrm, 1, 60);
      return l_outcome;
  end score;

  -- One row of the table: a model over the four documents of the inbox.
  procedure sweep (
    p_label in varchar2
  , p_model in uc_ai.model_type
  )
  as
    l_ok      pls_integer := 0;
    l_n       pls_integer := 0;
    l_tokens  number := 0;
    l_outcome t_outcome;
  begin
    <<document_loop>>
    for doc in ( select filename, content from inv_documents order by id ) loop
      l_outcome := score(doc.filename, doc.content, p_model);
      l_tokens  := l_tokens + l_outcome.tokens;
      l_n       := l_n + 1;
      l_ok      := l_ok + case when l_outcome.verdict = 'OK' then 1 else 0 end;

      if l_outcome.verdict != 'OK' then
        sys.dbms_output.put_line('    ' || rpad(doc.filename, 30) || l_outcome.verdict);
      end if;
    end loop document_loop;

    sys.dbms_output.put_line(rpad(p_label, 32) || l_ok || ' of ' || l_n
      || lpad(l_tokens, 12) || ' tokens');
  end sweep;
begin
  l_expect_map('ferrotek.pdf')               := t_expect('INVOICE', 2136.50, 427.30, 2563.80, 6);
  l_expect_map('nordwind.pdf')               := t_expect('INVOICE', 6450.85, 1225.66, 7676.51, 6);
  l_expect_map('halvorsen.pdf')              := t_expect('INVOICE', 4375.28, 350.02, 4725.30, 8);
  l_expect_map('ferrotek-delivery-note.pdf') := t_expect('DELIVERY_NOTE', 0, 0, 0, 4);
  -- The scan is the same invoice, so the same numbers must come back.
  l_expect_map('ferrotek-scan.pdf')          := t_expect('INVOICE', 2136.50, 427.30, 2563.80, 6);

  -- ------------------------------------------------------------------------
  -- 1. Four model tiers, one run for each of the four documents
  -- ------------------------------------------------------------------------
  sys.dbms_output.put_line('=== 1. Model tiers, one run per document ===');
  uc_ai.reset_globals;
  sweep('gpt-5.6-terra', uc_ai_openai.c_model_gpt_5_6_terra);
  sweep('gpt-5.6-sol',   uc_ai_openai.c_model_gpt_5_6_sol);
  sweep('gpt-5.6-luna',  uc_ai_openai.c_model_gpt_5_6_luna);
  sweep('gpt-5.4-nano',  uc_ai_openai.c_model_gpt_5_4_nano);

  -- ------------------------------------------------------------------------
  -- 2. Reasoning, on the cheapest model
  -- ------------------------------------------------------------------------
  -- On the cheapest one on purpose. Reasoning is meant to help a model that is
  -- struggling, so this is where it has the best chance of changing an answer.
  sys.dbms_output.put_line('=== 2. Reasoning, on the cheapest model ===');

  uc_ai.reset_globals;
  uc_ai.g_enable_reasoning := true;
  uc_ai.g_reasoning_level  := uc_ai.c_reasoning_level_low;
  sweep('gpt-5.4-nano, reasoning low', uc_ai_openai.c_model_gpt_5_4_nano);

  uc_ai.reset_globals;
  uc_ai.g_enable_reasoning := true;
  uc_ai.g_reasoning_level  := uc_ai.c_reasoning_level_high;
  sweep('gpt-5.4-nano, reasoning high', uc_ai_openai.c_model_gpt_5_4_nano);

  uc_ai.reset_globals;

  -- ------------------------------------------------------------------------
  -- 3. The hardest case, three times for each tier
  -- ------------------------------------------------------------------------
  -- A scan of the same FerroTek invoice: {{SCAN_BYTES}} bytes of pixels, and no
  -- text to extract. Three runs each, because one run of a model proves nothing.
  sys.dbms_output.put_line('=== 3. A scan, three runs per tier ===');

{{SCAN_HEX}}
  l_scan := wwv_flow_api.varchar2_to_blob(wwv_flow_api.g_varchar2_table);

  <<scan_loop>>
  for i in 1 .. c_runs loop
    sys.dbms_output.put_line('  nano  run ' || i || '  '
      || score('ferrotek-scan.pdf', l_scan, uc_ai_openai.c_model_gpt_5_4_nano).verdict);
    sys.dbms_output.put_line('  terra run ' || i || '  '
      || score('ferrotek-scan.pdf', l_scan, uc_ai_openai.c_model_gpt_5_6_terra).verdict);
  end loop scan_loop;
end;
/
"""


def block(filename, comment):
    path = os.path.join(PDF_DIR, filename)
    data = open(path, "rb").read()
    hexed = binascii.hexlify(data).decode().upper()
    chunks = [hexed[i : i + CHUNK] for i in range(0, len(hexed), CHUNK)]

    out = [
        "",
        "-- ---------------------------------------------------------------------------",
        f"-- {filename} — {len(data)} bytes",
        f"-- {comment}",
        "-- ---------------------------------------------------------------------------",
        "declare",
        "  l_blob blob;",
        "begin",
        "  wwv_flow_api.g_varchar2_table := wwv_flow_api.empty_varchar2_table;",
    ]
    for i, chunk in enumerate(chunks, 1):
        out.append(f"  wwv_flow_api.g_varchar2_table({i}) := '{chunk}';")
    out += [
        "  l_blob := wwv_flow_api.varchar2_to_blob(wwv_flow_api.g_varchar2_table);",
        "",
        "  insert into inv_documents (filename, media_type, file_bytes, content)",
        f"  values ('{filename}', 'application/pdf', sys.dbms_lob.getlength(l_blob), l_blob);",
        "",
        f"  sys.dbms_output.put_line('Loaded {filename}: '",
        "    || sys.dbms_lob.getlength(l_blob) || ' bytes.');",
        "end;",
        "/",
    ]
    return "\n".join(out)


def hex_chunks(filename):
    """The hex of one PDF, as PL/SQL assignments into wwv_flow_api."""
    data = open(os.path.join(PDF_DIR, filename), "rb").read()
    hexed = binascii.hexlify(data).decode().upper()
    chunks = [hexed[i : i + CHUNK] for i in range(0, len(hexed), CHUNK)]
    out = ["  wwv_flow_api.g_varchar2_table := wwv_flow_api.empty_varchar2_table;"]
    for i, chunk in enumerate(chunks, 1):
        out.append(f"  wwv_flow_api.g_varchar2_table({i}) := '{chunk}';")
    return "\n".join(out), len(data)


def matrix():
    """Generate 06_model_matrix.sql, the measurement behind lesson 5."""
    scan_hex, scan_bytes = hex_chunks("ferrotek-scan.pdf")
    body = MATRIX_TEMPLATE.replace("{{SCAN_HEX}}", scan_hex)
    body = body.replace("{{SCAN_BYTES}}", str(scan_bytes))

    with open(OUT_MATRIX, "w") as f:
        f.write(body)

    print(os.path.normpath(OUT_MATRIX), os.path.getsize(OUT_MATRIX), "bytes")


def main():
    parts = [HEADER]
    for filename, comment in DOCUMENTS:
        parts.append(block(filename, comment))
    parts.append("\ncommit;")
    parts.append(FOOTER)

    with open(OUT, "w") as f:
        f.write("\n".join(parts))

    print(os.path.normpath(OUT), os.path.getsize(OUT), "bytes")
    matrix()


if __name__ == "__main__":
    main()
