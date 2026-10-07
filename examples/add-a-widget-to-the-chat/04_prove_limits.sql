-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - lesson 4
-- Test what the widget type sc_invoices can show. No model.
-- ============================================================================
-- Each case calls SC_WIDGET_PKG.BUILD_SPEC with a spec that a model could write
-- and with the tool calls of one answer. The script prints the reason of a
-- rejection, or the invoices of the list.
--
-- The contract 88 owns INV-1001, INV-1002 and INV-1003. The contract 99 owns
-- INV-2001. The tool result in these cases is the real result of SC_LIST_INVOICES
-- for contract 88.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on size unlimited

declare
  l_calls_88 clob;
  c_calls_none constant clob := '[]';
  l_owner    number;

  procedure try(p_label in varchar2, p_spec in clob, p_calls in clob) is
    l_out    clob;
    l_reason varchar2(500 char);
    l_titles varchar2(500 char);
  begin
    sc_widget_pkg.build_spec('sc_invoices', p_spec, p_calls, l_out, l_reason);
    if l_reason is not null then
      sys.dbms_output.put_line(rpad(p_label, 46) || 'REJECTED: ' || l_reason);
    else
      select listagg(jt.title, ', ') within group (order by jt.rn)
        into l_titles
        from json_table(l_out, '$.items[*]' columns (rn for ordinality, title varchar2(50 char) path '$.title')) jt;
      sys.dbms_output.put_line(rpad(p_label, 46) || 'SHOWN: ' || l_titles);
    end if;
  end try;
begin
  -- the tool result of the desk for contract 88, as the chat records it
  l_calls_88 := '[{"name":"SC_LIST_INVOICES","output":'
             || sc_desk_pkg.list_invoices('{"_ctx":{"contract_id":"88"}}') || '}]';

  -- INV-2001 is a real invoice of contract 99. Cases 3 and 4 use it.
  select contract_id into l_owner from sc_invoices where invoice_no = 'INV-2001';
  sys.dbms_output.put_line('INV-2001 exists and belongs to contract ' || l_owner || chr(10));

  try('1 invoice of the contract',
      '{"type":"sc_invoices","invoice_nos":["INV-1001"]}', l_calls_88);
  try('2 two invoices, the order of the model',
      '{"type":"sc_invoices","invoice_nos":["INV-1003","INV-1001"]}', l_calls_88);
  try('3 an invoice of contract 99',
      '{"type":"sc_invoices","invoice_nos":["INV-2001"]}', l_calls_88);
  try('4 one of contract 88 and one of contract 99',
      '{"type":"sc_invoices","invoice_nos":["INV-1002","INV-2001"]}', l_calls_88);
  try('5 no tool ran in this answer',
      '{"type":"sc_invoices","invoice_nos":["INV-1001"]}', c_calls_none);
  try('6 a number that does not exist',
      '{"type":"sc_invoices","invoice_nos":["INV-9999"]}', l_calls_88);
  try('7 text instead of numbers',
      '{"type":"sc_invoices","invoice_nos":"INV-1001"}', l_calls_88);
  try('8 SQL in a number',
      '{"type":"sc_invoices","invoice_nos":["INV-1001'' or 1=1 --"]}', l_calls_88);
  try('9 no JSON',
      'not json', l_calls_88);
  -- models of one provider write the name of a tool with a prefix, in lower case
  try('10 the tool name has a prefix and lower case',
      '{"type":"sc_invoices","invoice_nos":["INV-1001"]}',
      replace(l_calls_88, '"SC_LIST_INVOICES"', '"functions.sc_list_invoices"'));

  -- 11. The whole path, as the chat runs it: the answer of a model that points at
  --     an invoice of contract 99. The part that the user sees is text.
  declare
    c_nl    constant varchar2(1 char) := chr(10);
    l_parts json_array_t;
    l_part  json_object_t;
  begin
    l_parts := uc_ai_chat_widgets.render(
      p_answer     => 'This invoice belongs to the other contract:' || c_nl
        || '```ucai-widget' || c_nl
        || '{"type":"sc_invoices","invoice_nos":["INV-2001"]}' || c_nl
        || '```'
    , p_types      => uc_ai_chat_widgets.normalize_types('sc_invoices')
    , p_tool_calls => json_array_t.parse(l_calls_88)
    );
    sys.dbms_output.put_line(chr(10) || '11 the same spec through render:');
    <<part_loop>>
    for i in 0 .. l_parts.get_size - 1 loop
      l_part := treat(l_parts.get(i) as json_object_t);
      sys.dbms_output.put_line('   part ' || (i + 1) || ': kind=' || l_part.get_string('kind')
        || case when l_part.has('rejected') then ', rejected=' || l_part.get_string('rejected') end);
    end loop part_loop;
  end;
end;
/
