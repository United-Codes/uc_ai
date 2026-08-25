-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 4
-- From the answer into your tables
-- ============================================================================
-- Three blocks:
--   1  write one document into the tables, and read the rows back
--   2  read a number out of JSON safely, whatever session you are in
--   3  write all four, and see what a person has to look at
--
-- Run lesson 3 first. No block here calls a model. Every one of them works from
-- an answer that is already in inv_extractions, so the whole script is free.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- 1. One document into the tables
-- ---------------------------------------------------------------------------
prompt
prompt === 1. Write ferrotek.pdf into the tables ===
declare
  l_document_id   inv_documents.id%type;
  l_extraction_id inv_extractions.id%type;
  l_invoice_id    inv_invoices.id%type;
begin
  select id into l_document_id from inv_documents where filename = 'ferrotek.pdf';

  -- So you can run this script again.
  delete from inv_invoices where document_id = l_document_id;

  select max(id)
    into l_extraction_id
    from inv_extractions
   where document_id = l_document_id
     and raw_json is not null;

  l_invoice_id := inv_extract_pkg.post_extraction(l_extraction_id);
  commit;

  sys.dbms_output.put_line('Wrote invoice id ' || l_invoice_id || '.');
end;
/

column supplier_name format a32
column invoice_no format a16
column ccy format a4
column rev format a4
prompt
prompt -- the header row
select i.supplier_name, i.invoice_no, i.invoice_date, i.currency as ccy
     , i.net_amount, i.tax_amount, i.total_amount, i.needs_review as rev
  from inv_invoices i
  join inv_documents d on d.id = i.document_id
 where d.filename = 'ferrotek.pdf';

column description format a44
column kind format a9
prompt
prompt -- the line rows
select l.seq, l.position, l.kind, l.quantity, l.unit_price, l.line_total
     , l.description
  from inv_invoice_lines l
  join inv_invoices i on i.id = l.invoice_id
  join inv_documents d on d.id = i.document_id
 where d.filename = 'ferrotek.pdf'
 order by l.seq;

-- ---------------------------------------------------------------------------
-- 2. Reading a number out of JSON
-- ---------------------------------------------------------------------------
-- A JSON number always uses a dot: 7676.51, never 7676,51. Half the world writes
-- 7676,51 instead, and Oracle follows the session it runs in.
--
-- Nothing below changes your session. Each call is TOLD which separators to use,
-- which is what you want in code that other people run.
prompt
prompt === 2. Read the total four ways, and get three answers ===
declare
  l_raw    clob;
  l_inv    json_object_t;
  l_text   varchar2(40 char);
  l_number number;
  l_valid  pls_integer;
begin
  select x.raw_json
    into l_raw
    from inv_extractions x
    join inv_documents d on d.id = x.document_id
   where d.filename = 'nordwind.pdf'
     and x.id = ( select max(x2.id)
                    from inv_extractions x2
                   where x2.document_id = x.document_id
                     and x2.raw_json is not null );

  l_inv  := json_object_t(l_raw);
  l_text := l_inv.get('total_amount').to_string;

  sys.dbms_output.put_line('the value as text:  ' || l_text);

  -- 1. get_number reads the JSON number itself and never looks at NLS. This is
  --    the one to use, and the only one inv_extract_pkg uses.
  l_number := l_inv.get_number('total_amount');
  sys.dbms_output.put_line('get_number:         ' || l_number);

  -- 2. to_number on the text, TOLD which separators the text uses. D in the
  --    format model means "the decimal separator", and the third argument says
  --    which character that is. Correct in every session.
  l_number := to_number(l_text, '99999999D99', 'NLS_NUMERIC_CHARACTERS=''.,''');
  sys.dbms_output.put_line('to_number, told:    ' || l_number);

  -- 3. The same call told the WRONG separators, which is what a session with a
  --    comma does to code that never says which it means.
  --
  --    Read the answer carefully. It is not an error. It is 7676.51 read as
  --    767651: a hundred times too big, in a column that holds money.
  l_number := to_number(l_text default null on conversion error
                      , '99999999D99', 'NLS_NUMERIC_CHARACTERS='',.''');
  sys.dbms_output.put_line('to_number, wrong:   '
    || nvl(to_char(l_number), '(null)'));

  -- 4. validate_conversion asks whether a conversion works before you rely on
  --    it. It returns 1 or 0 and never raises, and it is the right tool for text
  --    that might not be a number at all.
  --
  --    It does NOT save you here, and this is the point: both conversions above
  --    are valid. One of them is just valid and wrong.
  select validate_conversion(l_text as number, '99999999D99'
                           , 'NLS_NUMERIC_CHARACTERS=''.,''')
    into l_valid
    from sys.dual;
  sys.dbms_output.put_line('validate, told:     ' || l_valid);

  select validate_conversion(l_text as number, '99999999D99'
                           , 'NLS_NUMERIC_CHARACTERS='',.''')
    into l_valid
    from sys.dual;
  sys.dbms_output.put_line('validate, wrong:    ' || l_valid);

  sys.dbms_output.put_line('---');
  sys.dbms_output.put_line('Use get_number. It reads the JSON number and cannot');
  sys.dbms_output.put_line('be told the wrong thing.');
end;
/

-- ---------------------------------------------------------------------------
-- 3. All four documents, and the review queue
-- ---------------------------------------------------------------------------
prompt
prompt === 3. Write all four ===
declare
  l_invoice_id inv_invoices.id%type;
begin
  -- So you can run this script again. inv_invoice_lines goes with the header,
  -- because the foreign key says "on delete cascade".
  delete from inv_invoices;

  <<extraction_loop>>
  for x in ( select e.id, d.filename
               from inv_extractions e
               join inv_documents d on d.id = e.document_id
              where e.raw_json is not null
                and e.id = ( select max(e2.id)
                               from inv_extractions e2
                              where e2.document_id = e.document_id
                                and e2.raw_json is not null )
              order by e.id )
  loop
    begin
      l_invoice_id := inv_extract_pkg.post_extraction(x.id);
      sys.dbms_output.put_line(rpad(x.filename, 30)
        || nvl(to_char(l_invoice_id), 'no invoice row'));
    exception
      when others then
        -- @dblinter ignore(g-5040): the loop reports and carries on, which is the
        -- behaviour lesson 5 turns into one call
        -- @dblinter ignore(g-5080): the message is what the reader needs to see
        sys.dbms_output.put_line(rpad(x.filename, 30)
          || substr(sqlerrm, 1, 80));
    end;
  end loop extraction_loop;

  commit;
end;
/

column filename format a30
column reasons format a32
prompt
prompt -- what a person has to look at
select d.filename
     , i.invoice_no
     , i.needs_review as rev
     , i.review_reasons as reasons
     , i.total_amount
  from inv_documents d
  left join inv_invoices i on i.document_id = d.id
 order by d.id;
