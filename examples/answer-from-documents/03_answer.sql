-- ============================================================================
-- UC AI tutorial — "Answer from Your Documents" — Lesson 3
-- Answer questions from the handbook
-- ============================================================================
-- Run 02_search.sql first. This lesson uses its function HB_EMBED.
--
-- Sections in the order that the lesson explains them:
--   Collect the excerpts for a question   no model call
--   Create the answer function            no model call
--   Look at the excerpts of one question  one embedding call
--   Ask three questions                   three embedding and three model calls
--   Call the function from your application  one embedding and one model call
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
-- Collect the excerpts for a question
-- ---------------------------------------------------------------------------
prompt
prompt === Collect the excerpts for a question ============================
prompt

-- Returns the p_top_k chunks that are closest to the question, as one text.
-- Each chunk starts with the title of its article in square brackets, so the
-- model can say where a fact comes from.
-- @dblinter ignore(G-7410): the course adds one small function per lesson, so the reader can run each step on its own
create or replace function hb_retrieve (
  p_question in varchar2
, p_top_k    in pls_integer default 4
) return clob
as
  l_question vector;
  l_excerpts clob;
begin
  l_question := hb_embed(p_question);

  <<chunk_loop>>
  for r in (
    select d.title
         , c.chunk_text
      from hb_chunks c
      join hb_documents d on d.doc_id = c.doc_id
     order by vector_distance(c.embedding, l_question, cosine)
     fetch first p_top_k rows only
  ) loop
    l_excerpts := l_excerpts
               || '[' || r.title || ']' || chr(10)
               || r.chunk_text || chr(10) || chr(10);
  end loop chunk_loop;

  return l_excerpts;
end hb_retrieve;
/

-- ---------------------------------------------------------------------------
-- Create the answer function
-- ---------------------------------------------------------------------------
prompt
prompt === Create the answer function =====================================
prompt

-- @dblinter ignore(G-7410): the course adds one small function per lesson, so the reader can run each step on its own
create or replace function hb_answer (
  p_question in varchar2
) return clob
as
  c_system_prompt constant varchar2(1000 char) :=
       'You answer questions of field engineers about the company handbook.' || chr(10)
    || 'Use only the handbook excerpts in the user message.' || chr(10)
    || 'After each fact, name its article in square brackets, for example [Company vans].' || chr(10)
    || 'If the excerpts do not contain the answer, say that the handbook does not cover it. '
    || 'Do not guess.';

  l_result json_object_t;
begin
  l_result := uc_ai.generate_text(
    p_system_prompt => c_system_prompt
  , p_user_prompt   => 'Handbook excerpts:' || chr(10) || chr(10)
                    || hb_retrieve(p_question)
                    || 'Question: ' || p_question
  , p_provider      => uc_ai.c_provider_openai
  , p_model         => uc_ai_openai.c_model_gpt_5_6_terra
  );

  return l_result.get_clob('final_message');
end hb_answer;
/

select object_name, status
  from user_objects
 where object_name in ('HB_EMBED', 'HB_RETRIEVE', 'HB_ANSWER')
 order by object_name;

-- ---------------------------------------------------------------------------
-- Look at the excerpts of one question
-- ---------------------------------------------------------------------------
prompt
prompt === Look at the excerpts of one question ===========================
prompt

-- This is the text that the model gets for the question. No chat model is
-- called here, only the embedding model for the question.
begin
  sys.dbms_output.put_line(hb_retrieve(
    'I stay in Munich next week. How much can I spend on a hotel per night?'
  ));
end;
/

-- ---------------------------------------------------------------------------
-- Ask three questions
-- ---------------------------------------------------------------------------
prompt
prompt === Ask three questions ============================================
prompt

declare
  type t_question_arr is table of varchar2(200 char);
  l_question_arr t_question_arr;
begin
  l_question_arr := t_question_arr(
    'I stay in Munich next week. How much can I spend on a hotel per night?'
  , 'I am on standby this Saturday and Sunday. What allowance do I get?'
  , 'How many days of vacation do I get per year?'
  );

  <<question_loop>>
  for i in 1 .. l_question_arr.count loop
    sys.dbms_output.put_line('Q: ' || l_question_arr(i));
    sys.dbms_output.put_line('A: ' || hb_answer(l_question_arr(i)));
    sys.dbms_output.put_line(' ');
  end loop question_loop;
end;
/

-- ---------------------------------------------------------------------------
-- Call the function from your application
-- ---------------------------------------------------------------------------
prompt
prompt === Call the function from your application ========================
prompt

set long 4000
column answer format a100 word_wrapped

-- One embedding call and one model call, from plain SQL.
select hb_answer('Where do I report damage to my van?') as answer
  from dual;
