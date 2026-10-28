-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - precheck
-- Run this ONCE, before lesson 1. It changes nothing.
-- ============================================================================
-- This course adds a widget type to the chat of the service-contract desk.
-- The desk comes from "Put an Agent in APEX" (script 00_setup.sql of that
-- course). The chat tables and packages come from the APEX Chat plug-in.
--
-- Run it in the schema that holds the chat tables and the desk. It reports what
-- is present. Every line must say OK before lesson 1.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on

declare
  l_failed pls_integer := 0;

  -- Prints one line. Returns 1 for a failed check and 0 for a passed one.
  function report(p_label in varchar2, p_ok in boolean, p_hint in varchar2) return pls_integer is
  begin
    sys.dbms_output.put_line(rpad(p_label, 34) || ': ' || case when p_ok then 'OK' else 'MISSING OR INVALID - ' || p_hint end);
    return case when p_ok then 0 else 1 end;
  end report;

  function has_column(p_table in varchar2, p_column in varchar2) return boolean is
    l_n pls_integer;
  begin
    -- @dblinter ignore(G-8110): a tutorial check that reports presence; at most one row matches
    select count(*) into l_n from user_tab_columns where table_name = p_table and column_name = p_column;
    return l_n > 0;
  end has_column;

  function count_of(p_sql in varchar2) return pls_integer is
    l_n pls_integer;
  begin
    -- @dblinter ignore(G-9501): every caller passes a literal of this script, never an outside value
    -- Dynamic on purpose: a static query on a missing table would stop the whole script with ORA-00942.
    execute immediate p_sql into l_n;
    return l_n;
  end count_of;

  function has_object(p_name in varchar2, p_type in varchar2) return boolean is
    l_n pls_integer;
  begin
    -- @dblinter ignore(G-8110): a tutorial check that reports presence; at most one row matches
    select count(*) into l_n from user_objects where object_name = p_name and object_type = p_type and status = 'VALID';
    return l_n > 0;
  end has_object;
begin
  sys.dbms_output.put_line('Checking the schema ' || sys_context('userenv', 'current_schema') || ' ...');

  l_failed := l_failed + report('UC AI 26.5 (tool_call_id)', has_column('UC_AI_AGENT_MESSAGES', 'TOOL_CALL_ID'),
         'upgrade UC AI to 26.5 (run upgrade_uc_ai.sql)');
  l_failed := l_failed + report('UC AI 26.5 (prompt addendum)',
         count_of('select count(*) from user_arguments where package_name = ''UC_AI_AGENTS_API'' '
                  || 'and object_name = ''EXECUTE_AGENT'' and argument_name = ''P_PROMPT_ADDENDUM''') > 0,
         'upgrade UC AI to 26.5 (run upgrade_uc_ai.sql)');
  l_failed := l_failed + report('Chat table: widgets, parts', has_column('UC_AI_CHAT_MESSAGES', 'WIDGETS') and has_column('UC_AI_CHAT_MESSAGES', 'PARTS'),
         'run the upgrade block of ai_tables.sql of the plug-in');
  l_failed := l_failed + report('Registry table', has_column('UC_AI_CHAT_WIDGET_TYPES', 'PROVIDER_PACKAGE'),
         'step 3 of Requirements and upgrade in the Chat Widgets guide');
  l_failed := l_failed + report('Package UC_AI_CHAT_WIDGETS', has_object('UC_AI_CHAT_WIDGETS', 'PACKAGE BODY'),
         'step 4 of Requirements and upgrade in the Chat Widgets guide');
  l_failed := l_failed + report('Package UC_AI_CHAT', has_object('UC_AI_CHAT', 'PACKAGE BODY'),
         'step 4 of Requirements and upgrade in the Chat Widgets guide');
  l_failed := l_failed + report('Desk tables (sc_*)', count_of('select count(*) from user_tables where table_name like ''SC\_%'' escape ''\''') = 6,
         'run 00_setup.sql of the course Put an Agent in APEX');
  l_failed := l_failed + report('Desk package SC_DESK_PKG', has_object('SC_DESK_PKG', 'PACKAGE BODY'),
         'run 00_setup.sql of the course Put an Agent in APEX, or compile SC_DESK_PKG');
  l_failed := l_failed + report('Desk tools (4)', count_of('select count(*) from uc_ai_tools where code in (''SC_GET_CONTRACT'', ''SC_LIST_CALLS'', ''SC_LIST_INVOICES'', ''SC_RAISE_CREDIT_NOTE'')') = 4,
         'run 00_setup.sql of the course Put an Agent in APEX');
  l_failed := l_failed + report('Desk agent SC_DESK (active)', count_of('select count(*) from uc_ai_agents where code = ''SC_DESK'' and status = ''active''') > 0,
         'run 00_setup.sql of the course Put an Agent in APEX');

  if l_failed = 0 then
    sys.dbms_output.put_line('Precheck OK. Start lesson 1.');
  else
    sys.dbms_output.put_line(l_failed || ' check(s) failed. Fix them, then run this script again.');
  end if;
end;
/
