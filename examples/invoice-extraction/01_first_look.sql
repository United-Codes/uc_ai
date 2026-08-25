-- ============================================================================
-- UC AI tutorial — "Extract structured data from a PDF" — Lesson 1
-- Send a PDF, and see what comes back
-- ============================================================================
-- Four blocks:
--   1  what a PDF costs before a single token is counted
--   2  the call that works
--   3  the same question again, so you can compare the wording
--   4  three ways to get it wrong, each with the error it really gives
--
-- Run 00_setup.sql, 00_load_pdfs.sql and 00_precheck.sql first.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- 1. What the PDF weighs
-- ---------------------------------------------------------------------------
-- create_file_content puts the file in the request as base64 text. Base64 needs
-- four characters for every three bytes, so the request is a third larger than
-- the file on disk, before the model has read anything.
prompt
prompt === 1. The size of the request ===
declare
  l_blob   blob;
  l_base64 clob;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_base64 := apex_web_service.blob2clobbase64(
    p_blob => l_blob, p_newlines => 'N', p_padding => 'Y');

  sys.dbms_output.put_line('PDF on disk:      '
    || sys.dbms_lob.getlength(l_blob) || ' bytes');
  sys.dbms_output.put_line('Base64 on the wire: '
    || sys.dbms_lob.getlength(l_base64) || ' characters');
end;
/

-- ---------------------------------------------------------------------------
-- 2. The call
-- ---------------------------------------------------------------------------
-- generate_text has no file parameter. A file goes in the p_messages overload,
-- inside a USER message, as one entry of a content array.
prompt
prompt === 2. Ask about the invoice ===
declare
  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_messages.append(uc_ai_message_api.create_system_message(
    'You read supplier invoices. Answer in two or three sentences.'));

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => 'ferrotek.pdf'
  ));
  l_content.append(uc_ai_message_api.create_text_content(
    'What is this invoice, and what do we owe?'));

  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_gpt_5_6_terra
  );

  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  sys.dbms_output.put_line('---');
  sys.dbms_output.put_line('Tokens: ' || l_result.get_object('usage').to_clob);
end;
/

-- ---------------------------------------------------------------------------
-- 3. The same question again
-- ---------------------------------------------------------------------------
-- Nothing changed: the same PDF, the same prompt, the same model. Compare the
-- two paragraphs. Both are right. No two lines of your PL/SQL could read both.
prompt
prompt === 3. The same question, a second time ===
declare
  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_messages.append(uc_ai_message_api.create_system_message(
    'You read supplier invoices. Answer in two or three sentences.'));

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => 'ferrotek.pdf'
  ));
  l_content.append(uc_ai_message_api.create_text_content(
    'What is this invoice, and what do we owe?'));

  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_gpt_5_6_terra
  );

  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- 4. Three ways to get it wrong
-- ---------------------------------------------------------------------------
-- Each block catches its own error, so the script runs to the end.
prompt
prompt === 4a. The file in a SYSTEM message ===
-- A file is legal only in a user message. In a system message it is dropped.
-- There is no error, no warning, and no sign in the result. The model simply
-- answers a question about a document it never received.
declare
  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_system   json_object_t := json_object_t();
  l_result   json_object_t;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_content.append(uc_ai_message_api.create_text_content('You read invoices.'));
  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => 'ferrotek.pdf'
  ));

  l_system.put('role', 'system');
  l_system.put('content', l_content);
  l_messages.append(l_system);

  l_messages.append(uc_ai_message_api.create_simple_user_message(
    'What is the invoice number on the attached document? '
    || 'If you cannot see a document, answer NO DOCUMENT.'));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_gpt_5_6_luna
  );

  sys.dbms_output.put_line('Answer: ' || l_result.get_clob('final_message'));
exception
  when others then
    -- @dblinter ignore(g-5040): the point of the block is to print whatever comes back
    -- @dblinter ignore(g-5080): the message is the lesson; a backtrace is not
    sys.dbms_output.put_line('Error: ' || substr(sqlerrm, 1, 200));
end;
/

prompt
prompt === 4b. No filename ===
-- create_file_content leaves the key out when p_filename is null, and OpenAI
-- answers with a 500. Not a 400 that names the problem: a server error that
-- suggests you retry.
declare
  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/pdf'
  , p_data_blob  => l_blob
  , p_filename   => null
  ));
  l_content.append(uc_ai_message_api.create_text_content(
    'What is the invoice number?'));

  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_gpt_5_6_luna
  );

  sys.dbms_output.put_line('Answer: ' || l_result.get_clob('final_message'));
exception
  when others then
    -- @dblinter ignore(g-5040): the point of the block is to print whatever comes back
    -- @dblinter ignore(g-5080): the message is the lesson; a backtrace is not
    sys.dbms_output.put_line('Error: ' || substr(sqlerrm, 1, 400));
end;
/

prompt
prompt === 4c. A media type this provider does not take ===
-- UC AI refuses before anything leaves the database. ORA-20303 names the type
-- it could not use, which is the error you want.
declare
  l_blob     blob;
  l_messages json_array_t := json_array_t();
  l_content  json_array_t := json_array_t();
  l_result   json_object_t;
begin
  select content into l_blob from inv_documents where filename = 'ferrotek.pdf';

  l_content.append(uc_ai_message_api.create_file_content(
    p_media_type => 'application/msword'
  , p_data_blob  => l_blob
  , p_filename   => 'ferrotek.doc'
  ));
  l_content.append(uc_ai_message_api.create_text_content(
    'What is the invoice number?'));

  l_messages.append(uc_ai_message_api.create_user_message(l_content));

  l_result := uc_ai.generate_text(
    p_messages => l_messages
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_gpt_5_6_luna
  );

  sys.dbms_output.put_line('Answer: ' || l_result.get_clob('final_message'));
exception
  when others then
    -- @dblinter ignore(g-5040): the point of the block is to print whatever comes back
    -- @dblinter ignore(g-5080): the message is the lesson; a backtrace is not
    sys.dbms_output.put_line('Error: ' || substr(sqlerrm, 1, 200));
end;
/
