-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - lesson 1
-- Render a built-in widget without a model.
-- ============================================================================
-- The chat renders an answer after the run: it cuts the text of the model into
-- parts and rebuilds each widget block. This script calls that step directly
-- with an answer that you write yourself, so no model and no tokens are needed.
--
-- The tool result comes from the real tool SC_LIST_INVOICES of the desk, for the
-- contract 88.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set long 100000

declare
  c_fence constant varchar2(3 char) := '```';
  c_nl    constant varchar2(1 char) := chr(10);

  l_tool_output clob;
  l_calls       json_array_t := json_array_t();
  l_call        json_object_t := json_object_t();
  l_answer      clob;
  l_types       varchar2(200 char);
  l_parts       json_array_t;
  l_json        clob;
  l_pretty      clob;
begin
  -- 1. The tool result, as the desk returns it. The _ctx key is what UC AI adds
  --    to the arguments of every tool: it binds the call to contract 88.
  l_tool_output := sc_desk_pkg.list_invoices('{"_ctx":{"contract_id":"88"}}');

  -- 2. The record of the tool call, in the shape that the chat passes to render.
  l_call.put('name', 'SC_LIST_INVOICES');
  l_call.put('output', json_element_t.parse(l_tool_output));
  l_calls.append(l_call);

  -- 3. An answer as a model could write it: text, one valid table widget, and one
  --    table widget that names a column which the rows do not have.
  l_answer := 'Contract 88 has three invoices.' || c_nl
    || c_fence || 'ucai-widget' || c_nl
    || '{"type":"table","title":"Invoices","columns":["invoice_no","total_amount","uncredited_amount"],"source":"tool:SC_LIST_INVOICES"}' || c_nl
    || c_fence || c_nl
    || 'This second table names a column that does not exist:' || c_nl
    || c_fence || 'ucai-widget' || c_nl
    || '{"type":"table","columns":["Invoice Number"],"source":"tool:SC_LIST_INVOICES"}' || c_nl
    || c_fence;

  -- 4. The region attribute Widgets decides which types are on. Here: table.
  l_types := uc_ai_chat_widgets.normalize_types('table');
  sys.dbms_output.put_line('Enabled types : ' || l_types);

  l_parts := uc_ai_chat_widgets.render(
    p_answer     => l_answer
  , p_types      => l_types
  , p_tool_calls => l_calls
  );

  l_json := l_parts.to_clob();
  select json_serialize(l_json returning clob pretty) into l_pretty from dual;
  sys.dbms_output.put_line('Parts          :');
  sys.dbms_output.put_line(l_pretty);
end;
/
