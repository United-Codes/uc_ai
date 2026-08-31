-- ============================================================================
-- UC AI tutorial — "Build an Agent" — Lesson 1
-- Run this FIRST
-- ============================================================================
-- Checks the three things the whole course depends on, and names the fix for
-- each failure. Run it before you write any code.
--
-- The network step is the one that needs somebody else. A database cannot call
-- an HTTPS API until a DBA grants a network ACL and, on many systems, adds the
-- provider certificate to a wallet. Budget about 20 minutes and ask early.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

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
-- 2. Can this schema reach the provider, and is the key configured?
-- ---------------------------------------------------------------------------
-- This makes one real call, the smallest possible. It costs a few tokens.
declare
  l_result json_object_t;
  l_answer clob;
begin
  l_result := uc_ai.generate_text(
    p_user_prompt => 'Reply with exactly: READY'
  , p_provider    => uc_ai.c_provider_openai
  , p_model       => uc_ai_openai.c_model_gpt_5_6_luna
  );

  l_answer := l_result.get_clob('final_message');
  sys.dbms_output.put_line('2. The provider answered: ' || substr(l_answer, 1, 40));
  sys.dbms_output.put_line('   Tokens used: '
    || l_result.get_object('usage').get_number('total_tokens') || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): every provider error is reported to the reader with its
    -- fix below, so one handler is correct here
    -- @dblinter ignore(g-5080): sqlerrm is printed and mapped to a fix; a backtrace of the
    -- framework internals would not help the reader correct their network setup
    sys.dbms_output.put_line('2. FAILED: the call to the provider did not work.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
    sys.dbms_output.put_line('   ');
    sys.dbms_output.put_line('   Find your error below:');
    sys.dbms_output.put_line('   ORA-24247  no network ACL. A DBA must grant this schema');
    sys.dbms_output.put_line('              access to api.openai.com on port 443.');
    sys.dbms_output.put_line('   ORA-29024  certificate not trusted. The OpenAI certificate');
    sys.dbms_output.put_line('   ORA-28860  chain must be in the wallet the database uses.');
    sys.dbms_output.put_line('   ORA-29273  a proxy sits in front of you, or the host is');
    sys.dbms_output.put_line('              not reachable at all.');
    sys.dbms_output.put_line('   ORA-20502  no API key. Set one up (uc_ai_get_key), or use');
    sys.dbms_output.put_line('              an APEX web credential.');
    sys.dbms_output.put_line('   ');
    sys.dbms_output.put_line('   The network guide covers all of these. The first two need a DBA.');
end;
/

-- ---------------------------------------------------------------------------
-- 3. Is the demo schema in place?
-- ---------------------------------------------------------------------------
declare
  l_tables pls_integer;
begin
  select count(*)
    into l_tables
    from user_tables
   where table_name in ('SC_CUSTOMERS', 'SC_CONTRACTS', 'SC_ASSETS'
                      , 'SC_SERVICE_CALLS', 'SC_INVOICES', 'SC_CREDIT_NOTES');

  if l_tables = 6 then
    sys.dbms_output.put_line('3. The demo schema is in place (6 tables).');
  else
    sys.dbms_output.put_line('3. The demo schema is missing (' || l_tables
      || ' of 6 tables).');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql. To remove it later, run 00_teardown.sql.');
  end if;
end;
/

prompt
prompt ==========================================================
prompt  When all three lines above are good, start lesson 1.
prompt  If step 2 failed, fix that first: every lesson calls a model.
prompt ==========================================================
prompt

set feedback on
