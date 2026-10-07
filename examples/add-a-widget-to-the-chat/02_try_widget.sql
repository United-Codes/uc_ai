-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - lesson 2
-- Try the widget type sc_invoices without a model.
-- ============================================================================
-- Run 02_invoice_widget.sql first. The script prints the protocol text that the
-- model receives, then renders an answer with an sc_invoices block.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited
set long 100000

declare
  c_fence constant varchar2(3 char) := '```';
  c_nl    constant varchar2(1 char) := chr(10);

  l_calls  json_array_t := json_array_t();
  l_call   json_object_t := json_object_t();
  l_types  varchar2(200 char);
  l_parts  json_array_t;
  l_pretty clob;
  l_json   clob;
  l_text   clob;
begin
  -- The types of a region that checks Chart and lists sc_invoices as a custom widget.
  l_types := uc_ai_chat_widgets.normalize_types('chart:sc_invoices');
  sys.dbms_output.put_line('Enabled types : ' || l_types);

  -- The protocol that the chat adds to the system prompt (last lines).
  l_text := uc_ai_chat_widgets.get_protocol(l_types);
  sys.dbms_output.put_line('Protocol text : ' || sys.dbms_lob.getlength(l_text) || ' characters. The line of the new type:');
  sys.dbms_output.put_line(substr(l_text, sys.dbms_lob.instr(l_text, '- sc_invoices')));

  -- A tool result of the desk, for contract 88.
  l_call.put('name', 'SC_LIST_INVOICES');
  l_call.put('output', json_element_t.parse(sc_desk_pkg.list_invoices('{"_ctx":{"contract_id":"88"}}')));
  l_calls.append(l_call);

  l_parts := uc_ai_chat_widgets.render(
    p_answer     => 'Here are two invoices of this contract:' || c_nl
      || c_fence || 'ucai-widget' || c_nl
      || '{"type":"sc_invoices","invoice_nos":["INV-1003","INV-1001"],"title":"Two invoices"}' || c_nl
      || c_fence
  , p_types      => l_types
  , p_tool_calls => l_calls
  );

  l_json := l_parts.to_clob();
  select json_serialize(l_json returning clob pretty) into l_pretty from dual;
  sys.dbms_output.put_line('Parts          :');
  sys.dbms_output.put_line(l_pretty);
end;
/
