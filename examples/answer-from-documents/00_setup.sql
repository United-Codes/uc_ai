-- ============================================================================
-- UC AI tutorial — "Answer from Your Documents"
-- One-time setup for the whole course
-- ============================================================================
-- Creates the handbook of a field-service company: five articles that field
-- engineers read, and an empty table for their chunks.
--
-- Needs Oracle 23ai or 26ai, because HB_CHUNKS has a VECTOR column.
--
-- Safe to run again. Both tables are dropped and created again, so the chunks
-- and embeddings of lesson 1 are deleted. Run 01_chunk_embed.sql after it.
--
-- Remove everything again with 00_teardown.sql.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on
set feedback off

prompt
prompt === UC AI tutorial: Answer from Your Documents =====================
prompt

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
drop table if exists hb_chunks purge;
drop table if exists hb_documents purge;

create table hb_documents (
  doc_id  number generated always as identity primary key
, title   varchar2(100 char) not null
, body    clob not null
);

-- One row per chunk. text-embedding-3-small returns 1536 numbers per text, so
-- the column holds exactly that. Another embedding model needs another number.
create table hb_chunks (
  chunk_id      number generated always as identity primary key
, doc_id        number not null references hb_documents
, chunk_offset  number not null
, chunk_text    clob not null
, embedding     vector(1536, float32)
);

create index hb_chunks_doc_ix on hb_chunks (doc_id);

-- ---------------------------------------------------------------------------
-- The handbook
-- ---------------------------------------------------------------------------
insert into hb_documents (title, body) values (
  'Travel and expenses'
, 'Book hotels through the travel desk whenever you can. The standard limit for '
  || 'a hotel is 110 EUR per night, breakfast included. In Munich, Frankfurt, '
  || 'Hamburg and Paris the limit is 150 EUR per night. If no room is available '
  || 'under the limit, ask your team lead for approval before you book, and add '
  || 'the approval email to the expense report. '
  || 'You receive a meal allowance of 28 EUR for each day on which you are away '
  || 'from home for more than 8 hours. For a day with 8 hours or less there is no '
  || 'meal allowance. Do not submit restaurant receipts, because the allowance '
  || 'replaces them. '
  || 'Submit all receipts in the expense app within 30 days of the trip. Receipts '
  || 'that are older than 30 days are not paid. Take a photo of each receipt with '
  || 'the app. You do not need to send the paper originals.'
);

insert into hb_documents (title, body) values (
  'Company vans'
, 'Every field engineer has a company van with a fuel card. Use the fuel card '
  || 'only for the van, never for a private car. The van can be used to travel '
  || 'between home and the first customer, but not for holidays or other private '
  || 'trips. '
  || 'If the van is damaged, stop in a safe place first. Take photos of the damage '
  || 'and of the scene, and call dispatch on +49 89 555 0100. Then complete form '
  || 'VAN-7 in the fleet portal within 24 hours, also when nobody else was '
  || 'involved and the damage is small. '
  || 'Parking and speeding fines are paid by the driver. The fleet team books a '
  || 'service every 30,000 km. You get an email with the date and the workshop.'
);

insert into hb_documents (title, body) values (
  'On-call duty'
, 'On-call duty rotates weekly and starts on Monday at 08:00. The rota is '
  || 'published in the scheduling tool four weeks in advance. You can swap a week '
  || 'with a colleague if your team lead agrees before the week starts. '
  || 'For each weekday night on standby you receive an allowance of 45 EUR. For '
  || 'each Saturday, Sunday or public holiday on standby the allowance is 90 EUR. '
  || 'Time spent on an actual call-out is paid as overtime in addition to the '
  || 'allowance. '
  || 'Customers with a GOLD contract must see an engineer on site within 4 hours of '
  || 'their phone call. For SILVER contracts the target is the next business day. '
  || 'The time starts when dispatch accepts the call, not when you receive it.'
);

insert into hb_documents (title, body) values (
  'Safety on site'
, 'Before you open a machine, isolate it from all energy sources and put your own '
  || 'lock and tag on the isolator. Never work on a machine that another person '
  || 'has only switched off. '
  || 'Work at a height of more than 2 metres needs a harness and a second person '
  || 'on site. A ladder alone is not enough for work on a roof unit. '
  || 'When you work alone, check in with the safety app every 2 hours. If you do '
  || 'not check in, dispatch calls you, and after 15 minutes without an answer '
  || 'dispatch calls the local emergency services. '
  || 'Every engineer has the authority to stop work that is not safe. Nobody at '
  || 'the company will blame you for a job that you stopped for safety.'
);

insert into hb_documents (title, body) values (
  'Returning parts'
, 'Return every faulty part that was replaced under warranty. Put it in the box '
  || 'of the new part, attach the RMA label from the parts portal, and hand it to '
  || 'the courier within 14 days. '
  || 'If a part is not returned within 14 days, the supplier charges a core fee of '
  || '60 EUR. The fee is booked to the cost centre of your team. '
  || 'Unused parts that you ordered by mistake go back to the central warehouse. '
  || 'Book the return in the parts portal first, so that the stock of your van is '
  || 'correct.'
);

commit;

-- ---------------------------------------------------------------------------
-- Setup report
-- ---------------------------------------------------------------------------
declare
  l_docs  pls_integer;
  l_words pls_integer;
begin
  select count(*)
       , sum(regexp_count(body, '\S+'))
    into l_docs, l_words
    from hb_documents;

  sys.dbms_output.put_line('Setup OK: ' || l_docs || ' handbook articles, '
                        || l_words || ' words, 0 chunks.');
end;
/
