-- ============================================================================
-- UC AI tutorial — "Give an Agent a Memory" — Lesson 1
-- Run this after 00_setup.sql
-- ============================================================================
-- Checks the four things the whole course depends on, and names the fix for
-- each failure.
--
-- The network step is the one that needs somebody else. A database cannot call
-- an HTTPS API until a DBA grants a network ACL and, on many systems, adds the
-- provider certificate to a wallet. Ask early.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set linesize 200

prompt
prompt === Precheck: Give an Agent a Memory ===============================
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
  l_assets pls_integer := 0;
  l_orders pls_integer := 0;
begin
  select count(*) into l_assets from mx_assets;
  select count(*) into l_orders from mx_work_orders;

  if l_assets = 6 and l_orders = 18 then
    sys.dbms_output.put_line('2. The demo schema is in place (6 assets, 18 work orders).');
  else
    sys.dbms_output.put_line('2. The demo schema is not ready ('
                          || l_assets || ' assets, ' || l_orders || ' work orders).');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql.');
  end if;
exception
  when others then
    sys.dbms_output.put_line('2. FAILED: the demo tables are missing.');
    sys.dbms_output.put_line('   Fix: run 00_setup.sql.');
end;
/

-- ---------------------------------------------------------------------------
-- 3. Is the MEMORY tool there?
-- ---------------------------------------------------------------------------
-- The installer of UC AI creates this row. One row serves every agent, because
-- the tool resolves the store of the caller at each call. There is nothing for
-- you to register.
declare
  l_tool  pls_integer;
  l_agent pls_integer;
begin
  select count(*) into l_tool
    from uc_ai_tools
   where code = 'MEMORY';

  select count(*) into l_agent
    from uc_ai_agents
   where code = 'MX_DESK' and status = 'active';

  if l_tool = 1 and l_agent = 1 then
    sys.dbms_output.put_line('3. The MEMORY tool is registered and MX_DESK is active.');
  else
    sys.dbms_output.put_line('3. Not ready: MEMORY tool rows = ' || l_tool
                          || ', active MX_DESK = ' || l_agent || '.');
    sys.dbms_output.put_line('   Fix for a missing MEMORY row: run the UC AI post-scripts.');
    sys.dbms_output.put_line('   Fix for a missing agent: run 00_setup.sql.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 4. Can this database reach a model?
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
                        || ' (' || round((sys.dbms_utility.get_time - l_start) / 100, 2)
                        || ' seconds).');
exception
  when others then
    sys.dbms_output.put_line('4. FAILED: this database cannot reach the provider.');
    sys.dbms_output.put_line('   ORA-24247 or ORA-29024 is a network grant or a wallet, '
                          || 'and a DBA has to do it. See the network setup guide.');
    sys.dbms_output.put_line('   Error: ' || sqlerrm);
    sys.dbms_output.put_line('   ' || sys.dbms_utility.format_error_backtrace);
end;
/

prompt
prompt If all four lines above are good, start with 01_recall.sql.
prompt
