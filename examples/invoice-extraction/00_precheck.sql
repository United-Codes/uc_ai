-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 1
-- Run this after 00_setup.sql and 00_load_pdfs.sql
-- ============================================================================
-- Checks the three things the whole course depends on, and names the fix for
-- each failure.
--
-- Check 3 sends a real PDF, not a text prompt. That is deliberate. A text prompt
-- is a request of a few hundred bytes. A PDF is a request of a hundred kilobytes,
-- and a proxy that is happy with the first can still refuse the second. Only a
-- file call proves the path this course needs.
--
-- The network step is the one that needs somebody else. A database cannot call
-- an HTTPS API until a DBA grants a network ACL and, on many systems, adds the
-- provider certificate to a wallet. Budget about 20 minutes and ask early.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on
set feedback off

prompt
prompt ==========================================================
prompt  UC AI tutorial - prerequisite check
prompt ==========================================================
prompt

-- ---------------------------------------------------------------------------
-- 1. Is UC AI installed, and which version?
-- ---------------------------------------------------------------------------
declare
  l_version varchar2(16 char);
begin
  -- @dblinter ignore(g-6010): a compile-time constant statement; dynamic only so the
  -- script still runs and reports when UC AI is not installed at all
  execute immediate 'begin :1 := uc_ai.c_version; end;' using out l_version;
  sys.dbms_output.put_line('1. UC AI is installed. Version ' || l_version || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): any error here has one meaning for the reader, and the
    -- script must report it and continue to the next check
    -- @dblinter ignore(g-5080): the message below is the diagnosis this check exists to give;
    -- a backtrace of a probe would only confuse the reader
    sys.dbms_output.put_line('1. FAILED: UC AI is not installed in this schema, or you '
      || 'cannot see it.');
    sys.dbms_output.put_line('   Fix: run install_uc_ai.sql, then come back. '
      || 'See the installation guide.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
end;
/

-- ---------------------------------------------------------------------------
-- 2. Is the demo schema in place, with its documents?
-- ---------------------------------------------------------------------------
declare
  l_tables pls_integer;
  l_docs   pls_integer := 0;
begin
  select count(*)
    into l_tables
    from user_tables
   where table_name in ('INV_DOCUMENTS', 'INV_EXTRACTIONS', 'INV_INVOICES'
                      , 'INV_INVOICE_LINES', 'INV_PURCHASE_ORDERS');

  if l_tables = 5 then
    select count(*) into l_docs from inv_documents;
  end if;

  if l_tables = 5 and l_docs = 4 then
    sys.dbms_output.put_line('2. The demo schema is in place (5 tables, 4 documents).');
  else
    sys.dbms_output.put_line('2. The demo schema is not ready ('
      || l_tables || ' of 5 tables, ' || l_docs || ' of 4 documents).');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql, then 00_load_pdfs.sql.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 3. Can this schema send a PDF to the provider?
-- ---------------------------------------------------------------------------
-- One real call with a real file. It costs about 2500 tokens.
declare
  l_blob     blob;
  l_filename inv_documents.filename%type;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
begin
  select content, filename
    into l_blob, l_filename
    from inv_documents
   where filename = 'ferrotek.pdf';

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => l_filename
  ));
  l_content.append(uc_ai_message_api.create_text_content(
    'Reply with the invoice number on this document and nothing else.'));

  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_gpt_5_6_terra
  );

  sys.dbms_output.put_line('3. The provider read the PDF: '
    || substr(l_result.get_clob('final_message'), 1, 60));
  sys.dbms_output.put_line('   Tokens used: '
    || l_result.get_object('usage').get_number('total_tokens') || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): every provider error is reported to the reader with its
    -- fix below, so one handler is correct here
    -- @dblinter ignore(g-5080): sqlerrm is printed and mapped to a fix; a backtrace of the
    -- framework internals would not help the reader correct their network setup
    sys.dbms_output.put_line('3. FAILED: the call to the provider did not work.');
    sys.dbms_output.put_line('   Error: ' || substr(sqlerrm, 1, 300));
    sys.dbms_output.put_line('   ');
    sys.dbms_output.put_line('   Find your error below:');
    sys.dbms_output.put_line('   ORA-24247  no network ACL. A DBA must grant this schema');
    sys.dbms_output.put_line('              access to api.openai.com on port 443.');
    sys.dbms_output.put_line('   ORA-29024  certificate not trusted. The OpenAI certificate');
    sys.dbms_output.put_line('   ORA-28860  chain must be in the wallet the database uses.');
    sys.dbms_output.put_line('   ORA-29273  a proxy sits in front of you, or the host is');
    sys.dbms_output.put_line('              not reachable. A proxy that passes a small');
    sys.dbms_output.put_line('              prompt can still refuse a request of 100 kB.');
    sys.dbms_output.put_line('   ORA-20303  this provider cannot take application/pdf.');
    sys.dbms_output.put_line('              Use OpenAI, Anthropic, Google or OCI.');
    sys.dbms_output.put_line('   ORA-20502  no API key. Set one up (uc_ai_get_key), or use');
    sys.dbms_output.put_line('              an APEX web credential.');
    sys.dbms_output.put_line('   ');
    sys.dbms_output.put_line('   The network guide covers all of these. The first two need a DBA.');
end;
/

prompt
prompt ==========================================================
prompt  When all three lines above are good, start lesson 1.
prompt  If step 3 failed, fix that first: every lesson sends a PDF.
prompt ==========================================================
prompt

set feedback on
