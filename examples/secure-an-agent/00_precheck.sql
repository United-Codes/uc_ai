-- ============================================================================
-- UC AI tutorial — "Secure an Agent" — run this before lesson 1
-- ============================================================================
-- Checks the four things this course depends on and names the fix for each
-- failure. The network step is the one that needs somebody else: a DBA has to
-- grant a network ACL and, on many systems, add the provider certificate to a
-- wallet. Budget about 20 minutes and ask early.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl

set serveroutput on
set feedback off

prompt
prompt ==========================================================
prompt  UC AI tutorial - "Secure an Agent" - prerequisite check
prompt ==========================================================
prompt

declare
  l_version varchar2(16 char);
begin
  -- @dblinter ignore(g-6010): dynamic only so the script still reports when UC AI is
  -- not installed at all
  execute immediate 'begin :1 := uc_ai.c_version; end;' using out l_version;
  sys.dbms_output.put_line('1. UC AI is installed. Version ' || l_version || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): any error here has one meaning for the reader
    -- @dblinter ignore(g-5080): the message below is the diagnosis this check exists to give
    sys.dbms_output.put_line('1. FAILED: UC AI is not installed in this schema.');
    sys.dbms_output.put_line('   Fix: run install_uc_ai.sql. See the installation guide.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
end;
/

declare
  l_result json_object_t;
begin
  l_result := uc_ai.generate_text(
    p_user_prompt => 'Reply with exactly: READY'
  , p_provider    => uc_ai.c_provider_openai
  , p_model       => uc_ai_openai.c_model_gpt_5_6_luna
  );
  sys.dbms_output.put_line('2. The provider answered: '
    || substr(l_result.get_clob('final_message'), 1, 40));
  sys.dbms_output.put_line('   Tokens used: '
    || l_result.get_object('usage').get_number('total_tokens') || '.');
exception
  when others then
    -- @dblinter ignore(g-5040): every provider error is reported with its fix below
    -- @dblinter ignore(g-5080): sqlerrm is mapped to a fix; a backtrace would not help
    sys.dbms_output.put_line('2. FAILED: the call to the provider did not work.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
    sys.dbms_output.put_line('   ORA-24247  no network ACL. A DBA must grant this schema');
    sys.dbms_output.put_line('              access to api.openai.com on port 443.');
    sys.dbms_output.put_line('   ORA-29024  certificate not trusted. The provider certificate');
    sys.dbms_output.put_line('   ORA-28860  chain must be in the wallet the database uses.');
    sys.dbms_output.put_line('   ORA-29273  a proxy sits in front of you, or the host is');
    sys.dbms_output.put_line('              not reachable at all.');
    sys.dbms_output.put_line('   ORA-20502  no API key. Set one up (uc_ai_get_key), or use');
    sys.dbms_output.put_line('              an APEX web credential.');
    sys.dbms_output.put_line('   The network guide covers all of these. The first two need a DBA.');
end;
/

declare
  l_tables pls_integer;
begin
  select count(*)
    into l_tables
    from user_tables
   where table_name in ('AP_ENTITIES', 'AP_VENDORS', 'AP_CLERKS', 'AP_INVOICES'
                      , 'AP_MESSAGES', 'AP_APPROVALS', 'AP_OUTBOX'
                      , 'AP_VENDOR_BANK_CHANGES', 'AP_REPLY_TEMPLATES'
                      , 'AP_CONTROLS', 'AP_DESK_ERRORS');

  if l_tables = 11 then
    sys.dbms_output.put_line('3. The demo schema is in place (11 tables).');
  else
    sys.dbms_output.put_line('3. The demo schema is missing (' || l_tables || ' of 11 tables).');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql. To remove it later, run 00_teardown.sql.');
  end if;
end;
/

-- The check that belongs in a security course: what else is in this schema, and
-- what would an agent with tools enabled and no tag be handed?
declare
  l_tools json_array_t;
begin
  l_tools := uc_ai_tools_api.get_tools_array(
               p_provider     => uc_ai.c_provider_openai
             , p_tool_tags    => null
             , p_enable_tools => true
             );
  sys.dbms_output.put_line('4. Tools already registered in this schema: '
    || l_tools.get_size || '.');
  sys.dbms_output.put_line('   That is what an agent with tools enabled and NO tag is');
  sys.dbms_output.put_line('   offered. Lesson 2 is about this number.');
end;
/

prompt
prompt ==========================================================
prompt  When lines 1 to 3 are good, start lesson 1.
prompt  If step 2 failed, fix that first: every lesson calls a model.
prompt ==========================================================
prompt

set feedback on
