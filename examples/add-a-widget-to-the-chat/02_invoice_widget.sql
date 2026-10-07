-- ============================================================================
-- UC AI tutorial - "Add Your Own Widget to the Chat" - lesson 2
-- The widget type sc_invoices: a list of invoices that the user can open.
-- ============================================================================
-- Creates the package SC_WIDGET_PKG and registers the type with the chat.
-- Safe to run more than one time: the package is replaced and the
-- registration is merged.
--
-- The model writes only invoice numbers:
--   {"type":"sc_invoices","invoice_nos":["INV-1001","INV-1003"]}
-- The package turns them into a list. Number, date, amounts, and the credit
-- status come from the tables, not from the model.
--
-- To remove everything again, run 00_teardown.sql.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.
-- @dblinter ignore(G-7220): the package body sits in a .sql file next to its specification,
-- and the private function money is declared before its first use.

set define off
set serveroutput on

create or replace package sc_widget_pkg
as
  /**
   * UC AI tutorial - "Add Your Own Widget to the Chat"
   * Provider of the widget type sc_invoices. The chat calls the two members
   * below; the contract between the two is described in the Chat Widgets guide.
   */

  c_type_invoices constant varchar2(30 char) := 'sc_invoices';

  -- The action name that the click of a row sends to the page.
  c_action_open constant varchar2(30 char) := 'sc-open-invoice';

  /*
   * The lines that describe this type in the WIDGET PROTOCOL block of the
   * system prompt.
   */
  function get_protocol(p_type in varchar2) return clob;

  /*
   * Builds the list for one widget block.
   *
   * p_spec        the JSON that the model wrote
   * p_tool_calls  the tool calls of this answer: [{"name","args","output"}, ...]
   * po_spec       the list to show (JSON object of the type item_list)
   * po_reason     not null = reject the widget; the user sees the block as text
   */
  procedure build_spec(
    p_type       in  varchar2
  , p_spec       in  clob
  , p_tool_calls in  clob
  , po_spec      out nocopy clob
  , po_reason    out nocopy varchar2
  );
end sc_widget_pkg;
/

create or replace package body sc_widget_pkg
as
  c_max_invoices constant pls_integer := 10;
  c_nls          constant varchar2(40 char) := 'NLS_NUMERIC_CHARACTERS=''.,''';

  -- 1234.5 -> '1234.50', with a dot whatever the NLS setting of the session
  function money(p_amount in number) return varchar2
  as
  begin
    return to_char(p_amount, 'FM999999990.00', c_nls);
  end money;

  function get_protocol(p_type in varchar2) return clob
  as
  begin
    return
      '- ' || p_type || ': {"type":"' || p_type || '","invoice_nos":["INV-1001"],"title":"..."} '
      || 'Shows invoices of this contract as a list that the user can open. '
      || 'Use it whenever you name invoices: put it instead of a list of invoice numbers in the text. '
      || '"invoice_nos" are invoice_no values that SC_LIST_INVOICES returned while you write this answer (1 to '
      || c_max_invoices || '). '
      || 'Do not write amounts or dates: the system fills them in. "title" is optional.';
  end get_protocol;

  procedure build_spec(
    p_type       in  varchar2
  , p_spec       in  clob
  , p_tool_calls in  clob
  , po_spec      out nocopy clob
  , po_reason    out nocopy varchar2
  )
  as
    l_spec     json_object_t;
    l_el       json_element_t;
    l_nos      json_array_t;
    l_no       varchar2(100 char);
    l_wanted   apex_t_varchar2 := apex_t_varchar2();
    l_items    json_array_t := json_array_t();
    l_item     json_object_t;
    l_badge    json_object_t;
    l_badges   json_array_t;
    l_meta     json_array_t;
    l_action   json_object_t;
    l_out      json_object_t := json_object_t();
    type t_items is table of json_object_t index by varchar2(20 char);
    l_found_map t_items;
    l_uncredited number;
  begin
    begin
      l_spec := json_object_t.parse(p_spec);
    exception
      when others then -- @dblinter ignore(g-5040): not JSON is a rejected widget, nothing to log
        po_reason := 'the widget is not valid JSON';
        return;
    end;

    l_el := l_spec.get('invoice_nos');
    if l_el is null or not l_el.is_array then
      po_reason := 'invoice_nos must be an array of invoice numbers';
      return;
    end if;
    l_nos := treat(l_el as json_array_t);
    if l_nos.get_size = 0 or l_nos.get_size > c_max_invoices then
      po_reason := 'invoice_nos must hold 1 to ' || c_max_invoices || ' invoice numbers';
      return;
    end if;

    <<no_loop>>
    for i in 0 .. l_nos.get_size - 1 loop
      l_no := case when l_nos.get(i).is_string then l_nos.get_string(i) end;
      if l_no is null or not regexp_like(l_no, '^[A-Za-z0-9-]{1,20}$') then
        po_reason := 'every entry must be an invoice_no as the tool returned it';
        return;
      end if;
      if l_no not member of l_wanted then
        l_wanted.extend;
        l_wanted(l_wanted.count) := l_no;
      end if;
    end loop no_loop;

    -- An invoice is shown only when SC_LIST_INVOICES returned it in this answer.
    -- That tool reads only the contract of the run, so the list cannot reach
    -- another contract. A number that no tool returned is left out.
    <<inv_loop>>
    for rec in (
      select i.invoice_no
           , i.invoiced_on
           , i.parts_amount
           , i.labour_amount
           , i.parts_amount + i.labour_amount as total_amount
           , nvl((select sum(cn.amount) from sc_credit_notes cn where cn.invoice_id = i.id), 0) as credited_amount
        from sc_invoices i
       where i.invoice_no in (select w.column_value from table(l_wanted) w)
         and exists (
           select 1
             from json_table(
                    p_tool_calls
                  , '$[*]'
                    columns (
                      tool_name varchar2(100 char) path '$.name'
                    , nested path '$.output.invoices[*]' columns (returned_no varchar2(20 char) path '$.invoice_no')
                    )
                  ) tc
            where upper(tc.tool_name) like '%SC_LIST_INVOICES'
              and tc.returned_no = i.invoice_no
         )
    ) loop
      l_item := json_object_t();
      l_item.put('title', rec.invoice_no);
      l_item.put('subtitle', 'Invoiced on ' || to_char(rec.invoiced_on, 'YYYY-MM-DD'));
      l_item.put('icon', 'text');

      l_uncredited := rec.total_amount - rec.credited_amount;
      l_badge := json_object_t();
      if rec.credited_amount = 0 then
        l_badge.put('text', 'Not credited');
        l_badge.put('tone', 'info');
      elsif l_uncredited <= 0 then
        l_badge.put('text', 'Fully credited');
        l_badge.put('tone', 'ok');
      else
        l_badge.put('text', 'Partly credited');
        l_badge.put('tone', 'warn');
      end if;
      l_badges := json_array_t();
      l_badges.append(l_badge);
      l_item.put('badges', l_badges);

      l_meta := json_array_t();
      l_meta.append('Total ' || money(rec.total_amount));
      l_meta.append('Parts ' || money(rec.parts_amount));
      l_meta.append('Labour ' || money(rec.labour_amount));
      l_item.put('meta', l_meta);

      l_action := json_object_t();
      l_action.put('name', c_action_open);
      l_action.put('id', rec.invoice_no);
      l_action.put('label', 'Open');
      l_item.put('action', l_action);

      l_found_map(rec.invoice_no) := l_item;
    end loop inv_loop;

    -- keep the order in which the model named the invoices
    <<order_loop>>
    for i in 1 .. l_wanted.count loop
      if l_found_map.exists(l_wanted(i)) then
        l_items.append(l_found_map(l_wanted(i)));
      end if;
    end loop order_loop;

    if l_items.get_size = 0 then
      -- one answer for "not returned by the tool" and "no such invoice"
      po_reason := 'none of the invoices can be shown';
      return;
    end if;

    l_out.put('type', 'item_list');
    l_el := l_spec.get('title');
    if l_el is not null and l_el.is_string then
      l_out.put('title', substr(l_spec.get_string('title'), 1, 120));
    end if;
    l_out.put('items', l_items);
    po_spec := l_out.to_clob();
  end build_spec;
end sc_widget_pkg;
/

show errors package body sc_widget_pkg

begin
  uc_ai_chat_widgets.register_type(
    p_type             => sc_widget_pkg.c_type_invoices
  , p_provider_package => 'sc_widget_pkg'
  );
  commit;
  sys.dbms_output.put_line('Registered the widget type ' || sc_widget_pkg.c_type_invoices);
end;
/
