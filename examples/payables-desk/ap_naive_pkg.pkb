create or replace package body ap_naive_pkg
as
  /**
  * UC AI tutorial — "Secure an Agent" — lesson 1 ONLY
  * DELIBERATELY UNSAFE. See the package specification.
  */

  -- @dblinter ignore(g-5010): a tutorial demonstration package prints nothing and logs
  -- nothing on purpose, so the reader sees only what the tables record

  function get_invoice(p_arguments in clob) return clob
  as
    l_args   json_object_t;
    l_result json_object_t;
    l_no     varchar2(20 char);
  begin
    l_args   := json_object_t(p_arguments);
    l_result := json_object_t();
    l_no     := l_args.get_string('invoice_no');
    <<invoice_row>>
    for r in (
      select i.invoice_no
           , i.net_amount + i.tax_amount as gross_amount
           , i.currency
           , i.po_no
           , i.goods_receipt_yn
           , i.status
           , to_char(i.due_date, 'YYYY-MM-DD') as due_date
           , v.vendor_no
           , v.name as vendor_name
           , v.iban
           , v.status as vendor_status
        from ap_invoices i
        join ap_vendors v on v.id = i.vendor_id
       where i.invoice_no = l_no
    ) loop
      l_result.put('invoice_no', r.invoice_no);
      l_result.put('gross_amount', r.gross_amount);
      l_result.put('currency', r.currency);
      l_result.put('po_no', r.po_no);
      l_result.put('goods_receipt', r.goods_receipt_yn);
      l_result.put('status', r.status);
      l_result.put('due_date', r.due_date);
      l_result.put('vendor_no', r.vendor_no);
      l_result.put('vendor_name', r.vendor_name);
      l_result.put('vendor_iban', r.iban);
      l_result.put('vendor_status', r.vendor_status);
    end loop invoice_row;

    if l_result.get_size = 0 then
      l_result.put('error', 'No invoice ' || l_no);
    end if;

    return l_result.to_clob;
  end get_invoice;


  function read_email(p_arguments in clob) return clob
  as
    l_args   json_object_t;
    l_result json_object_t;
    l_no     varchar2(20 char);
  begin
    l_args   := json_object_t(p_arguments);
    l_result := json_object_t();
    l_no     := l_args.get_string('invoice_no');
    -- The body goes to the model exactly as the supplier wrote it, with nothing
    -- around it to say who wrote it. Lesson 4 changes this.
    <<message_row>>
    for r in (
      select m.sender
           , m.subject
           , m.body
           , to_char(m.received_at, 'YYYY-MM-DD') as received_at
        from ap_messages m
        join ap_invoices i on i.id = m.invoice_id
       where i.invoice_no = l_no
         and m.direction = 'IN'
       order by m.received_at
       fetch first 1 rows only
    ) loop
      l_result.put('sender', r.sender);
      l_result.put('subject', r.subject);
      l_result.put('received_at', r.received_at);
      l_result.put('body', r.body);
    end loop message_row;

    if l_result.get_size = 0 then
      l_result.put('error', 'No message for ' || l_no);
    end if;

    return l_result.to_clob;
  end read_email;


  function approve_invoice(p_arguments in clob) return clob
  as
    l_args       json_object_t;
    l_result     json_object_t;
    l_no         varchar2(20 char);
    l_amount     number;
    l_note       varchar2(1000 char);
    l_invoice_id number;
    l_entity_id  number;
    l_seq        number;
    l_approval   varchar2(20 char);
  begin
    l_args   := json_object_t(p_arguments);
    l_result := json_object_t();
    l_no     := l_args.get_string('invoice_no');
    l_amount := l_args.get_number('amount');
    l_note   := substr(l_args.get_string('note'), 1, 1000);
    select i.id, i.entity_id
      into l_invoice_id, l_entity_id
      from ap_invoices i
     where i.invoice_no = l_no;

    l_seq      := ap_approvals_no_seq.nextval;
    l_approval := 'AP-' || l_seq;

    -- No goods receipt. No clerk. No entity. No limit. The arguments decide.
    insert into ap_approvals (id, invoice_id, entity_id, approval_no, amount
                            , approved_by, source, note)
    values (l_seq, l_invoice_id, l_entity_id, l_approval
          , l_amount, sys_context('userenv', 'session_user'), 'AGENT', l_note);

    update ap_invoices set status = 'APPROVED' where id = l_invoice_id;

    l_result.put('status', 'approved');
    l_result.put('approval_no', l_approval);
    l_result.put('amount', l_amount);
    return l_result.to_clob;
  exception
    when no_data_found then
      return '{"status":"error","message":"No invoice ' || l_no || '"}';
  end approve_invoice;


  function update_vendor_bank(p_arguments in clob) return clob
  as
    l_args      json_object_t;
    l_vendor_no varchar2(20 char);
    l_iban      varchar2(40 char);
    l_vendor_id number;
    l_old_iban  varchar2(40 char);
  begin
    l_args      := json_object_t(p_arguments);
    l_vendor_no := l_args.get_string('vendor_no');
    l_iban      := l_args.get_string('iban');
    select v.id, v.iban into l_vendor_id, l_old_iban
      from ap_vendors v where v.vendor_no = l_vendor_no;

    update ap_vendors set iban = l_iban where id = l_vendor_id;

    insert into ap_vendor_bank_changes (vendor_id, old_iban, new_iban, changed_by, source)
    values (l_vendor_id, l_old_iban, l_iban
          , sys_context('userenv', 'session_user'), 'AGENT');

    return '{"status":"updated","vendor_no":"' || l_vendor_no || '"}';
  exception
    when no_data_found then
      return '{"status":"error","message":"No vendor ' || l_vendor_no || '"}';
  end update_vendor_bank;


  function send_vendor_reply(p_arguments in clob) return clob
  as
    l_args json_object_t;
    l_to   varchar2(240 char);
    l_subj varchar2(400 char);
    l_body clob;
  begin
    l_args := json_object_t(p_arguments);
    l_to   := l_args.get_string('to_address');
    l_subj := l_args.get_string('subject');
    l_body := l_args.get_string('body');
    -- A free-text body and an address the model chose. Lesson 5 closes both.
    insert into ap_outbox (to_address, subject, body, created_by)
    values (l_to, l_subj, l_body, sys_context('userenv', 'session_user'));

    return '{"status":"queued"}';
  end send_vendor_reply;

end ap_naive_pkg;
/
