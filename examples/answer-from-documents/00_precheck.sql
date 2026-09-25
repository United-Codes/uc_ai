-- ============================================================================
-- UC AI tutorial — "Answer from Your Documents" — Lesson 1
-- Run this after 00_setup.sql
-- ============================================================================
-- Checks the four things the whole course depends on, and names the fix for
-- each failure. Checks 3 and 4 call OpenAI, so they use a few tokens.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200
set feedback off

prompt
prompt === Precheck: Answer from Your Documents ===========================
prompt

-- ---------------------------------------------------------------------------
-- 1. Is UC AI installed, and which version?
-- ---------------------------------------------------------------------------
declare
  l_version varchar2(32 char);
  -- c_version is a package constant, so it cannot be read in plain SQL.
  c_read_version constant varchar2(100 char) := 'begin :1 := uc_ai.c_version; end;';
begin
  execute immediate c_read_version using out l_version;
  sys.dbms_output.put_line('1. UC AI is installed. Version ' || l_version || '.');
exception
  when others then
    sys.dbms_output.put_line('1. FAILED: UC AI is not installed in this schema, or you '
                          || 'cannot see it.');
    sys.dbms_output.put_line('   Fix: run install_uc_ai.sql, then come back.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
    sys.dbms_output.put_line('   ' || sys.dbms_utility.format_error_backtrace);
end;
/

-- ---------------------------------------------------------------------------
-- 2. Is the demo schema in place?
-- ---------------------------------------------------------------------------
declare
  l_docs pls_integer := 0;
begin
  select count(*) into l_docs from hb_documents;

  if l_docs = 5 then
    sys.dbms_output.put_line('2. The handbook is in place (5 articles).');
  else
    sys.dbms_output.put_line('2. The handbook is not ready (' || l_docs || ' articles).');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql.');
  end if;
exception
  when others then
    sys.dbms_output.put_line('2. FAILED: the demo tables are missing.');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql. It needs Oracle 23ai or 26ai.');
end;
/

-- ---------------------------------------------------------------------------
-- 3. Can this database get an embedding?
-- ---------------------------------------------------------------------------
declare
  l_input   json_array_t := json_array_t();
  l_vectors json_array_t;
  l_vector  vector;
begin
  l_input.append('ready');
  l_vectors := uc_ai.generate_embeddings(
    p_input    => l_input
  , p_provider => uc_ai.c_provider_openai
  , p_model    => uc_ai_openai.c_model_text_embedding_3_small
  );
  l_vector := to_vector(l_vectors.get(0).to_clob, 1536, float32);
  sys.dbms_output.put_line('3. An embedding came back with '
                        || vector_dimension_count(l_vector) || ' dimensions.');
exception
  when others then
    sys.dbms_output.put_line('3. FAILED: no embedding came back.');
    sys.dbms_output.put_line('   ORA-24247 or ORA-29024 is a network grant or a wallet, '
                          || 'and a DBA has to do it. See the network setup guide.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
    sys.dbms_output.put_line('   ' || sys.dbms_utility.format_error_backtrace);
end;
/

-- ---------------------------------------------------------------------------
-- 4. Can this database reach a chat model?
-- ---------------------------------------------------------------------------
declare
  l_result json_object_t;
  l_start  number := sys.dbms_utility.get_time;
begin
  l_result := uc_ai.generate_text(
    p_user_prompt => 'Reply with the single word: ready'
  , p_provider    => uc_ai.c_provider_openai
  , p_model       => uc_ai_openai.c_model_gpt_5_6_terra
  );
  sys.dbms_output.put_line('4. A model answered: '
                        || l_result.get_clob('final_message')
                        || ' (' || to_char((sys.dbms_utility.get_time - l_start) / 100
                                         , 'fm990.00', 'nls_numeric_characters=''.,''')
                        || ' seconds).');
exception
  when others then
    sys.dbms_output.put_line('4. FAILED: this database cannot reach the chat model.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
    sys.dbms_output.put_line('   ' || sys.dbms_utility.format_error_backtrace);
end;
/

prompt
prompt If all four lines above are good, start with 01_chunk_embed.sql.
prompt
