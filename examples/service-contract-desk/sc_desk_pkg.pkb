create or replace package body sc_desk_pkg
as

  /**
  * UC AI tutorial — "Build an Agent"
  * Tool handlers of the service-contract desk. See the specification for the
  * two rules every handler follows.
  */

  -- ==========================================================================
  -- Helpers
  -- ==========================================================================

  /*
   * Builds the JSON a refusal returns. The `message` is for the model, the
   * `reason` is for your own code and for the tests.
   */
  function refusal(
    p_reason  in reason_type
  , p_message in varchar2
  ) return clob
  as
    l_result json_object_t := json_object_t();
  begin
    l_result.put('status', 'refused');
    l_result.put('reason', p_reason);
    l_result.put('message', p_message);
    return l_result.to_clob;
  end refusal;


  function bound_contract_id(p_arguments in clob) return number
  as
    l_args    json_object_t;
    l_context json_object_t;
    l_value   varchar2(4000 char);
  begin
    if p_arguments is null then
      return null;
    end if;

    l_args := json_object_t(p_arguments);

    -- UC AI always adds this key. It holds an empty object when the run carries
    -- no context, so the get_object below is safe either way.
    l_context := l_args.get_object(uc_ai.c_run_context_key);

    if l_context is null then
      return null;
    end if;

    l_value := l_context.get_string('contract_id');

    if l_value is null then
      return null;
    end if;

    return to_number(l_value);
  exception
    when value_error then
      -- A context value that is not a number is the same situation as no
      -- contract at all: the handler must refuse, not raise.
      return null;
  end bound_contract_id;


  -- ==========================================================================
  -- Read tools
  -- ==========================================================================

  function get_contract(p_arguments in clob) return clob
  as
    l_contract_id number;
    l_result      json_object_t := json_object_t();
  begin
    l_contract_id := bound_contract_id(p_arguments);

    if l_contract_id is null then
      return refusal(c_reason_no_contract
           , 'This conversation is not bound to a service contract, so I cannot read one.');
    end if;

    <<contract_row>>
    for r in (
      select c.contract_no
           , c.coverage_level
           , c.starts_on
           , c.ends_on
           , cu.name as customer_name
           , cu.city as customer_city
        from sc_contracts c
        join sc_customers cu on cu.id = c.customer_id
       where c.id = l_contract_id
    ) loop
      l_result.put('contract_no', r.contract_no);
      l_result.put('customer', r.customer_name);
      l_result.put('city', r.customer_city);
      l_result.put('coverage_level', r.coverage_level);
      l_result.put('coverage_from', to_char(r.starts_on, 'YYYY-MM-DD'));
      l_result.put('coverage_to', to_char(r.ends_on, 'YYYY-MM-DD'));
      l_result.put('covers'
        , case r.coverage_level
            when 'GOLD'   then 'parts and labour'
            when 'SILVER' then 'labour only'
          end);
    end loop contract_row;

    if l_result.get_size = 0 then
      return refusal(c_reason_no_contract, 'Contract ' || l_contract_id || ' does not exist.');
    end if;

    return l_result.to_clob;
  end get_contract;


  /*
   * Reads the optional max_rows argument, with a default and a ceiling. A model
   * may send anything, so the handler decides the real limit.
   */
  function requested_rows(p_arguments in clob) return pls_integer
  as
    c_default constant pls_integer := 20;
    c_ceiling constant pls_integer := 100;
    l_args    json_object_t;
    l_rows    number;
  begin
    if p_arguments is null then
      return c_default;
    end if;

    l_args := json_object_t(p_arguments);
    l_rows := l_args.get_number('max_rows');

    if l_rows is null or l_rows < 1 then
      return c_default;
    end if;

    return least(trunc(l_rows), c_ceiling);
  exception
    when others then
      -- @dblinter ignore(g-5040): a model can send anything for max_rows, and every bad
      -- value has the same safe answer: use the default instead of failing the run
      -- @dblinter ignore(g-5080): a rejected argument is expected input, not a fault to report
      return c_default;
  end requested_rows;


  function list_calls(p_arguments in clob) return clob
  as
    l_contract_id number;
    l_rows        pls_integer;
    l_calls       json_array_t := json_array_t();
    l_result      json_object_t := json_object_t();
  begin
    l_contract_id := bound_contract_id(p_arguments);

    if l_contract_id is null then
      return refusal(c_reason_no_contract
           , 'This conversation is not bound to a service contract, so I cannot list its calls.');
    end if;

    l_rows := requested_rows(p_arguments);

    <<call_rows>>
    for r in (
      select sc.id
           , sc.called_on
           , sc.summary
           , sc.parts_cost
           , sc.labour_cost
           , a.asset_tag
           , case
               when sc.called_on between c.starts_on and c.ends_on then 'Y'
               else 'N'
             end as in_coverage
        from sc_service_calls sc
        join sc_contracts c on c.id = sc.contract_id
        join sc_assets a on a.id = sc.asset_id
       -- The contract comes from the run context. A call of another contract can
       -- never appear here, whatever the model asked for.
       where sc.contract_id = l_contract_id
       order by sc.called_on desc
       fetch first l_rows rows only
    ) loop
      l_calls.append(
        json_object_t(
          json_object(
            'call_id'     value r.id
          , 'called_on'   value to_char(r.called_on, 'YYYY-MM-DD')
          , 'asset'       value r.asset_tag
          , 'summary'     value r.summary
          , 'parts_cost'  value r.parts_cost
          , 'labour_cost' value r.labour_cost
          , 'in_coverage' value case r.in_coverage when 'Y' then 'true' else 'false' end
          )
        )
      );
    end loop call_rows;

    l_result.put('service_calls', l_calls);
    l_result.put('count', l_calls.get_size);
    return l_result.to_clob;
  end list_calls;


  function list_invoices(p_arguments in clob) return clob
  as
    l_contract_id number;
    l_rows        pls_integer;
    l_invoices    json_array_t := json_array_t();
    l_result      json_object_t := json_object_t();
  begin
    l_contract_id := bound_contract_id(p_arguments);

    if l_contract_id is null then
      return refusal(c_reason_no_contract
           , 'This conversation is not bound to a service contract, so I cannot list its invoices.');
    end if;

    l_rows := requested_rows(p_arguments);

    <<invoice_rows>>
    for r in (
      select i.invoice_no
           , i.invoiced_on
           , i.parts_amount
           , i.labour_amount
           , i.parts_amount + i.labour_amount as total_amount
           , nvl((select sum(cn.amount)
                    from sc_credit_notes cn
                   where cn.invoice_id = i.id), 0) as credited_amount
           , case
               when sc.called_on between c.starts_on and c.ends_on then 'Y'
               else 'N'
             end as in_coverage
        from sc_invoices i
        join sc_contracts c on c.id = i.contract_id
        join sc_service_calls sc on sc.id = i.service_call_id
       where i.contract_id = l_contract_id
       order by i.invoiced_on desc
       fetch first l_rows rows only
    ) loop
      l_invoices.append(
        json_object_t(
          json_object(
            'invoice_no'        value r.invoice_no
          , 'invoiced_on'       value to_char(r.invoiced_on, 'YYYY-MM-DD')
          , 'parts_amount'      value r.parts_amount
          , 'labour_amount'     value r.labour_amount
          , 'total_amount'      value r.total_amount
          , 'credited_amount'   value r.credited_amount
          , 'uncredited_amount' value r.total_amount - r.credited_amount
          , 'in_coverage'       value case r.in_coverage when 'Y' then 'true' else 'false' end
          )
        )
      );
    end loop invoice_rows;

    l_result.put('invoices', l_invoices);
    l_result.put('count', l_invoices.get_size);
    return l_result.to_clob;
  end list_invoices;


  -- ==========================================================================
  -- Write tool
  -- ==========================================================================

  function raise_credit_note(p_arguments in clob) return clob
  as
    l_args        json_object_t;
    l_contract_id number;
    l_invoice_no  varchar2(20 char);
    l_amount      number;
    l_reason      varchar2(400 char);

    l_invoice_id     number;
    l_inv_contract   number;
    l_total          number;
    l_parts          number;
    l_labour         number;
    l_credited       number;
    l_coverage       varchar2(10 char);
    l_in_window      varchar2(1 char);
    l_credit_no      varchar2(20 char);
    l_eligible_base  number;
    l_engineer       varchar2(255 char);
    l_result         json_object_t := json_object_t();
  begin
    l_contract_id := bound_contract_id(p_arguments);

    if l_contract_id is null then
      return refusal(c_reason_no_contract
           , 'This conversation is not bound to a service contract, so I cannot raise a credit note.');
    end if;

    l_args       := json_object_t(p_arguments);
    l_invoice_no := upper(trim(l_args.get_string('invoice_no')));
    l_amount     := l_args.get_number('amount');
    l_reason      := l_args.get_string('reason');

    if l_invoice_no is null then
      return refusal(c_reason_unknown_invoice, 'Tell me which invoice number to credit.');
    end if;

    if l_amount is null or l_amount <= 0 then
      return refusal(c_reason_bad_amount, 'The credit amount must be a positive number.');
    end if;

    -- Read the invoice WITHOUT restricting to the bound contract, so a request
    -- for another contract's invoice can be refused with a clear reason instead
    -- of looking like an invoice that does not exist.
    begin
      select i.id
           , i.contract_id
           , i.parts_amount
           , i.labour_amount
           , i.parts_amount + i.labour_amount
           , nvl((select sum(cn.amount)
                    from sc_credit_notes cn
                   where cn.invoice_id = i.id), 0)
           , c.coverage_level
           , case
               when sc.called_on between c.starts_on and c.ends_on then 'Y'
               else 'N'
             end
        into l_invoice_id
           , l_inv_contract
           , l_parts
           , l_labour
           , l_total
           , l_credited
           , l_coverage
           , l_in_window
        from sc_invoices i
        join sc_contracts c on c.id = i.contract_id
        join sc_service_calls sc on sc.id = i.service_call_id
       where i.invoice_no = l_invoice_no;
    exception
      when no_data_found then
        return refusal(c_reason_unknown_invoice
             , 'There is no invoice ' || l_invoice_no || '.');
    end;

    -- Condition 1: the invoice must belong to the contract bound to this run.
    -- This is the check that makes the run context a security boundary and not
    -- only a convenience.
    if l_inv_contract != l_contract_id then
      return refusal(c_reason_wrong_contract
           , 'Invoice ' || l_invoice_no || ' belongs to another service contract, '
             || 'so it cannot be credited in this conversation.');
    end if;

    -- Condition 2: the service call must fall inside the coverage window.
    if l_in_window = 'N' then
      return refusal(c_reason_out_of_window
           , 'The service call behind invoice ' || l_invoice_no || ' is outside the '
             || 'coverage window of this contract, so the contract does not cover it.');
    end if;

    -- Condition 3: the coverage level decides what may be credited.
    -- GOLD covers parts and labour. SILVER covers labour only.
    l_eligible_base := case l_coverage
                         when 'GOLD'   then l_total
                         when 'SILVER' then l_labour
                       end;

    if l_coverage = 'SILVER' and l_amount > l_labour then
      return refusal(c_reason_not_entitled
           , 'This is a SILVER contract, which covers labour only. Invoice '
             || l_invoice_no || ' has ' || to_char(l_labour) || ' of labour and '
             || to_char(l_parts) || ' of parts, so at most ' || to_char(l_labour)
             || ' can be credited.');
    end if;

    -- Condition 4: never credit more than is still uncredited.
    if l_credited >= l_eligible_base then
      return refusal(c_reason_already_credited
           , 'Invoice ' || l_invoice_no || ' is already credited in full ('
             || to_char(l_credited) || ' of ' || to_char(l_eligible_base) || ').');
    end if;

    if l_amount > l_eligible_base - l_credited then
      return refusal(c_reason_amount_too_high
           , 'Only ' || to_char(l_eligible_base - l_credited) || ' is still uncredited on '
             || 'invoice ' || l_invoice_no || ', so ' || to_char(l_amount)
             || ' is too much.');
    end if;

    -- Every condition holds, so the credit note may be created.
    l_credit_no := 'CN-' || to_char(sc_credit_notes_no_seq.nextval);

    -- Record WHO asked, from the run context. Do not read APEX$SESSION here:
    -- inside an agent run that gives UC AI's synthetic user, not the engineer.
    -- The column default (the database user) applies when the run carries no
    -- engineer.
    l_engineer := uc_ai.run_context_value(
                    json_object_t(p_arguments).get_object(uc_ai.c_run_context_key).to_clob
                  , 'engineer');

    insert into sc_credit_notes (invoice_id, contract_id, credit_no, amount, reason, created_by)
    values (l_invoice_id, l_contract_id, l_credit_no, l_amount
          , nvl(l_reason, 'Raised by the service-contract desk agent')
          , coalesce(l_engineer, sys_context('userenv', 'session_user')));

    -- No commit here on purpose. The caller owns the transaction, so the
    -- application decides when the credit note becomes permanent. Lesson 5
    -- explains what that means when a run fails after this point.

    l_result.put('status', 'created');
    l_result.put('credit_note', l_credit_no);
    l_result.put('invoice_no', l_invoice_no);
    l_result.put('amount', l_amount);
    return l_result.to_clob;
  end raise_credit_note;

end sc_desk_pkg;
/
