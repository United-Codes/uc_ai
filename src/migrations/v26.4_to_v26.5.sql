-- ============================================================================
-- UC AI Migration: v26.4 to v26.5
-- ============================================================================
-- Safe to run more than once: every step checks the data dictionary first.
-- Run upgrade_packages.sql after this script.

-- ============================================================================
-- AGENT MESSAGES: provider tool call id
-- ============================================================================
-- Pairs a tool_call row with its tool_result row. Rows written before this
-- release keep a null id.

declare
  l_column user_tab_columns.column_name%type;
  c_stmt   constant varchar2(200 char) := 'alter table uc_ai_agent_messages add (tool_call_id varchar2(255 char))';
begin
  select max(column_name)
    into l_column
    from user_tab_columns
   where table_name  = 'UC_AI_AGENT_MESSAGES'
     and column_name = 'TOOL_CALL_ID';

  if l_column is null then
    execute immediate c_stmt;
  end if;
end;
/

comment on column uc_ai_agent_messages.tool_call_id is 'Provider tool call id, set on tool_call and tool_result rows (null on all other roles and on rows written before v26.5). Pairs a tool_call row with its tool_result row. Google and Ollama synthesize ids such as tool_call_1 from a per-run counter, so an id is unique only within one execution_id. Pair rows on (execution_id, tool_call_id), never on tool_call_id alone';
