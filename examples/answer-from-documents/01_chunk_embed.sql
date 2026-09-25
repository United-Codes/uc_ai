-- ============================================================================
-- UC AI tutorial — "Answer from Your Documents" — Lesson 1
-- Split the handbook into chunks and embed them
-- ============================================================================
-- Run 00_setup.sql and 00_precheck.sql first.
--
-- Sections in the order that the lesson explains them:
--   Ask a model without the handbook   one model call
--   Preview the chunks of one article  no model call
--   Store the chunks of every article  no model call
--   Embed every chunk in one call      one embedding call
--   Look at the stored vectors         no model call
--
-- Safe to run again: the chunks are deleted and made again.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200
set long 4000
set feedback off
set sqlformat default
set pagesize 100

-- ---------------------------------------------------------------------------
-- Ask a model without the handbook
-- ---------------------------------------------------------------------------
prompt
prompt === Ask a model without the handbook ===============================
prompt

declare
  l_result json_object_t;
begin
  l_result := uc_ai.generate_text(
    p_user_prompt => 'I am a field engineer at our company and I stay in Munich '
                  || 'next week. How much can I spend on a hotel per night?'
  , p_provider    => uc_ai.c_provider_openai
  , p_model       => uc_ai_openai.c_model_gpt_5_6_terra
  );
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/

-- ---------------------------------------------------------------------------
-- Preview the chunks of one article
-- ---------------------------------------------------------------------------
prompt
prompt === Preview the chunks of one article ==============================
prompt

column chunk_offset format 9999
column chunk_length format 9999
column chunk_text   format a110 word_wrapped

select c.chunk_offset
     , c.chunk_length
     , c.chunk_text
  from hb_documents d
 cross join vector_chunks(
         d.body by words max 50 overlap 0 split by sentence
       ) c
 where d.title = 'Travel and expenses';

-- ---------------------------------------------------------------------------
-- Store the chunks of every article
-- ---------------------------------------------------------------------------
prompt
prompt === Store the chunks of every article ==============================
prompt

delete from hb_chunks;

insert into hb_chunks (doc_id, chunk_offset, chunk_text)
select d.doc_id
     , c.chunk_offset
     , c.chunk_text
  from hb_documents d
 cross join vector_chunks(
         d.body by words max 50 overlap 0 split by sentence
       ) c;

commit;

column title format a20
select d.title
     , count(*) as chunks
  from hb_documents d
  join hb_chunks c on c.doc_id = d.doc_id
 group by d.title
 order by d.title;

-- The shortest chunk. A sentence alone in a chunk loses the words that the
-- sentence before it gave it.
column chunk_text format a70 word_wrapped
select d.title
     , c.chunk_text
  from hb_chunks c
  join hb_documents d on d.doc_id = c.doc_id
 order by length(c.chunk_text)
 fetch first 1 row only;

-- ---------------------------------------------------------------------------
-- Embed every chunk in one call
-- ---------------------------------------------------------------------------
prompt
prompt === Embed every chunk in one call ==================================
prompt

declare
  type t_id_arr   is table of hb_chunks.chunk_id%type;
  type t_text_arr is table of clob;
  l_chunk_id_arr t_id_arr;
  l_text_arr     t_text_arr;
  l_vector_arr   t_text_arr := t_text_arr();
  l_texts        json_array_t := json_array_t();
  l_vectors      json_array_t;
begin
  -- 1. Collect the text of every chunk into one JSON array.
  select chunk_id, chunk_text
    bulk collect into l_chunk_id_arr, l_text_arr
    from hb_chunks
   order by chunk_id;

  <<text_loop>>
  for i in 1 .. l_text_arr.count loop
    l_texts.append(l_text_arr(i));
  end loop text_loop;

  -- 2. One call. The result is an array of vectors, in the order of the input.
  l_vectors := uc_ai.generate_embeddings(
    p_input    => l_texts
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_text_embedding_3_small
  );

  -- 3. Store each vector with its chunk. SQL cannot read a json_array_t, so
  --    each vector goes into SQL as a CLOB, and TO_VECTOR converts it.
  l_vector_arr.extend(l_chunk_id_arr.count);
  <<vector_loop>>
  for i in 1 .. l_chunk_id_arr.count loop
    l_vector_arr(i) := l_vectors.get(i - 1).to_clob;
  end loop vector_loop;

  forall i in 1 .. l_chunk_id_arr.count
    update hb_chunks
       set embedding = to_vector(l_vector_arr(i), 1536, float32)
     where chunk_id = l_chunk_id_arr(i);

  commit;
  sys.dbms_output.put_line('Embedded ' || l_vectors.get_size || ' chunks.');
end;
/

-- ---------------------------------------------------------------------------
-- Look at the stored vectors
-- ---------------------------------------------------------------------------
prompt
prompt === Look at the stored vectors =====================================
prompt

column first_numbers format a60

select chunk_id
     , vector_dimension_count(embedding) as dimensions
     , sys.dbms_lob.substr(from_vector(embedding returning clob), 55, 1) || '...' as first_numbers
  from hb_chunks
 order by chunk_id
 fetch first 3 rows only;

select count(*) as chunks
     , count(case when embedding is not null then 1 end) as with_embedding
  from hb_chunks;
