-- ============================================================================
-- UC AI tutorial — "Answer from Your Documents" — Lesson 2
-- Search the handbook by meaning
-- ============================================================================
-- Run 01_chunk_embed.sql first. This lesson needs the embeddings it stores.
--
-- Sections in the order that the lesson explains them:
--   Create a function that embeds one text   no model call
--   Search with a keyword                    no model call
--   Search by meaning                        one embedding call
--   Search for a chunk that lost its context one embedding call
--
-- Safe to run again.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200
set feedback off
set sqlformat default
set pagesize 100
column object_name format a20
column status      format a10

-- ---------------------------------------------------------------------------
-- Create a function that embeds one text
-- ---------------------------------------------------------------------------
prompt
prompt === Create a function that embeds one text =========================
prompt

-- A question must be embedded with the SAME model as the chunks. Vectors of two
-- different models cannot be compared, even when they have the same length.
-- @dblinter ignore(G-7410): the course adds one small function per lesson, so the reader can run each step on its own
create or replace function hb_embed (
  p_text in clob
) return vector
as
  l_input   json_array_t := json_array_t();
  l_vectors json_array_t;
begin
  l_input.append(p_text);

  l_vectors := uc_ai.generate_embeddings(
    p_input    => l_input
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_text_embedding_3_small
  );

  return to_vector(l_vectors.get(0).to_clob, 1536, float32);
end hb_embed;
/

select object_name, status
  from user_objects
 where object_name = 'HB_EMBED';

-- ---------------------------------------------------------------------------
-- Search with a keyword
-- ---------------------------------------------------------------------------
prompt
prompt === Search with a keyword ==========================================
prompt

-- The question of this lesson:
--   "I reversed into a bollard and the bumper is dented. What do I do now?"
-- The handbook says what to do, but it never uses the words of the question.
select count(*) as keyword_hits
  from hb_chunks
 where lower(chunk_text) like '%bollard%'
    or lower(chunk_text) like '%bumper%'
    or lower(chunk_text) like '%dented%'
    or lower(chunk_text) like '%reversed%';

-- ---------------------------------------------------------------------------
-- Search by meaning
-- ---------------------------------------------------------------------------
prompt
prompt === Search by meaning ==============================================
prompt

declare
  l_question vector;
begin
  -- One embedding call, for the question.
  l_question := hb_embed('I reversed into a bollard and the bumper is dented. '
                      || 'What do I do now?');

  -- The rest is SQL. A smaller cosine distance means a closer meaning.
  <<chunk_loop>>
  for r in (
    select d.title
         , c.chunk_text
         -- @dblinter ignore(G-3120): COSINE is the distance metric keyword, not a column
         , vector_distance(c.embedding, l_question, cosine) as distance
      from hb_chunks c
      join hb_documents d on d.doc_id = c.doc_id
     order by distance
     fetch first 3 rows only
  ) loop
    sys.dbms_output.put_line(to_char(r.distance, '0.0000') || '  ' || r.title);
    sys.dbms_output.put_line('        ' || sys.dbms_lob.substr(r.chunk_text, 90, 1) || '...');
  end loop chunk_loop;
end;
/

-- ---------------------------------------------------------------------------
-- Search for a chunk that lost its context
-- ---------------------------------------------------------------------------
prompt
prompt === Search for a chunk that lost its context =======================
prompt

-- The answer to "where" is the chunk "You get an email with the date and the
-- workshop." from lesson 1. That chunk does not say that it is about a service.
declare
  l_question vector;
begin
  l_question := hb_embed('When is the next service of my van, and where?');

  <<chunk_loop>>
  for r in (
    select d.title
         , c.chunk_text
         -- @dblinter ignore(G-3120): COSINE is the distance metric keyword, not a column
         , vector_distance(c.embedding, l_question, cosine) as distance
      from hb_chunks c
      join hb_documents d on d.doc_id = c.doc_id
     order by distance
     fetch first 3 rows only
  ) loop
    sys.dbms_output.put_line(to_char(r.distance, '0.0000') || '  ' || r.title);
    sys.dbms_output.put_line('        ' || sys.dbms_lob.substr(r.chunk_text, 90, 1) || '...');
  end loop chunk_loop;
end;
/
