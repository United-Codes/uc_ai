-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - teardown
-- Removes what this course created: the registration of the type sc_invoices
-- and the package SC_WIDGET_PKG. The service-contract desk stays.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

set define off
set serveroutput on

begin
  uc_ai_chat_widgets.unregister_type('sc_invoices');
  commit;
  sys.dbms_output.put_line('Unregistered the widget type sc_invoices');
end;
/

begin
  -- the conversations that 03_ask_the_desk.sql started
  delete from uc_ai_chat_messages where session_id like 'SCW\_%' escape '\';
  commit;
  sys.dbms_output.put_line('Deleted the chat rows of the sessions that start with SCW_');
end;
/

declare
  e_no_package exception;
  pragma exception_init(e_no_package, -4043);
begin
  -- @dblinter ignore(G-6010): DDL cannot take a bind variable, and the name is a literal
  execute immediate 'drop package sc_widget_pkg';
  sys.dbms_output.put_line('Dropped package SC_WIDGET_PKG');
exception
  when e_no_package then
    sys.dbms_output.put_line('Package SC_WIDGET_PKG was not there');
end;
/
