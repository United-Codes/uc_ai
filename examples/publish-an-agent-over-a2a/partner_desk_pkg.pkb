create or replace package body partner_desk_pkg
as

  /**
  * UC AI tutorial — "Publish an Agent over A2A"
  * Tool handlers of the partner service desk. See the specification for the
  * three rules every handler follows.
  */

  -- ==========================================================================
  -- Helpers
  -- ==========================================================================

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


  function client_customer_id(p_arguments in clob) return number
  as
    l_args     json_object_t;
    l_context  json_object_t;
    l_client   varchar2(255 char);
    l_customer number;
  begin
    if p_arguments is null then
      return null;
    end if;

    l_args    := json_object_t(p_arguments);
    l_context := l_args.get_object(uc_ai.c_run_context_key);

    if l_context is null then
      return null;
    end if;

    l_client := l_context.get_string('a2a_client');

    if l_client is null then
      return null;
    end if;

    -- A client that is not in the table is not a partner: max() returns null for
    -- no row, and every handler then refuses. It never falls back to "all customers".
    select max(pc.customer_id)
      into l_customer
      from partner_clients pc
     where pc.client_id = l_client;

    return l_customer;
  end client_customer_id;


  -- Reads one string argument that the model chose.
  function string_argument(
    p_arguments in clob
  , p_name      in varchar2
  ) return varchar2
  as
  begin
    return json_object_t(p_arguments).get_string(p_name);
  exception
    when others then
      -- @dblinter ignore(g-5040): a model can send any type for an argument, and every bad
      -- value has the same answer: treat the argument as missing
      -- @dblinter ignore(g-5080): a rejected argument is expected input, not a fault to report
      return null;
  end string_argument;


  -- The asset of this customer with this tag. Null for a missing tag and for a
  -- tag of another customer, so both cases get the same answer.
  function find_asset_id(
    p_asset_tag   in varchar2
  , p_customer_id in number
  ) return number
  as
    l_asset_id number;
  begin
    select max(a.id)
      into l_asset_id
      from sc_assets a
      join sc_contracts c on c.id = a.contract_id
     where upper(a.asset_tag) = upper(trim(p_asset_tag))
       and c.customer_id = p_customer_id;

    return l_asset_id;
  end find_asset_id;


  function no_asset_refusal(p_asset_tag in varchar2) return clob
  as
  begin
    return refusal(
             c_reason_no_asset
           , 'There is no asset ' || p_asset_tag || ' for your company.');
  end no_asset_refusal;


  function unknown_client_refusal return clob
  as
  begin
    return refusal(c_reason_unknown_client, 'This client is not a known partner.');
  end unknown_client_refusal;


  -- ==========================================================================
  -- The booking rule, on plain values
  -- ==========================================================================

  -- Monday is 0 and Sunday is 6, whatever the NLS territory says.
  function is_working_day(p_date in date) return boolean
  as
  begin
    return trunc(p_date) - trunc(p_date, 'IW') < 5;
  end is_working_day;


  function add_working_days(
    p_from in date
  , p_days in pls_integer
  ) return date
  as
    l_date date;
    l_left pls_integer := p_days;
  begin
    l_date := trunc(p_from);

    <<days>>
    while l_left > 0 loop
      l_date := l_date + 1;
      if is_working_day(l_date) then
        l_left := l_left - 1;
      end if;
    end loop days;

    return l_date;
  end add_working_days;


  function check_visit(
    p_asset_id    in number
  , p_date        in date
  , p_customer_id in number
  , p_today       in date default trunc(sysdate)
  ) return reason_type
  as
    l_starts_on date;
    l_ends_on   date;
    l_open      pls_integer;
  begin
    -- Rule 1: the asset belongs to this customer.
    select max(c.starts_on)
         , max(c.ends_on)
      into l_starts_on
         , l_ends_on
      from sc_assets a
      join sc_contracts c on c.id = a.contract_id
     where a.id = p_asset_id
       and c.customer_id = p_customer_id;

    if l_starts_on is null then
      return c_reason_no_asset;
    end if;

    -- Rule 2: the date is inside the coverage window of the contract.
    if trunc(p_date) not between l_starts_on and l_ends_on then
      return c_reason_out_of_cover;
    end if;

    -- Rule 3: no request is open for this asset.
    select count(*)
      into l_open
      from partner_visits v
     where v.asset_id = p_asset_id
       and v.status = 'REQUESTED'
       and rownum = 1;

    if l_open > 0 then
      return c_reason_open_request;
    end if;

    -- Rule 4: enough notice.
    if trunc(p_date) < add_working_days(p_today, c_notice_working_days) then
      return c_reason_too_soon;
    end if;

    return null;
  end check_visit;


  -- ==========================================================================
  -- Tools
  -- ==========================================================================

  function list_assets(p_arguments in clob) return clob
  as
    l_customer_id number;
    l_result      clob;
  begin
    l_customer_id := client_customer_id(p_arguments);

    if l_customer_id is null then
      return unknown_client_refusal;
    end if;

    select json_object(
             'count' value count(*)
           , 'assets' value coalesce(
               json_arrayagg(
                 json_object(
                   'asset_tag'      value x.asset_tag
                 , 'model'          value x.model
                 , 'installed_on'   value to_char(x.installed_on, 'YYYY-MM-DD')
                 , 'contract_no'    value x.contract_no
                 , 'coverage_level' value x.coverage_level
                 , 'coverage_from'  value to_char(x.starts_on, 'YYYY-MM-DD')
                 , 'coverage_to'    value to_char(x.ends_on, 'YYYY-MM-DD')
                 , 'under_contract' value x.under_contract format json
                 )
                 order by x.asset_tag
                 returning clob
               )
             , to_clob('[]')) format json
           returning clob)
      into l_result
      from ( select a.asset_tag
                  , a.model
                  , a.installed_on
                  , c.contract_no
                  , c.coverage_level
                  , c.starts_on
                  , c.ends_on
                  , case
                      when trunc(sysdate) between c.starts_on and c.ends_on then 'true'
                      else 'false'
                    end as under_contract
               from sc_assets a
               join sc_contracts c on c.id = a.contract_id
              -- The customer comes from the run context. An asset of another
              -- customer can never appear here, whatever the model asked for.
              where c.customer_id = l_customer_id ) x;

    return l_result;
  end list_assets;


  function get_asset_history(p_arguments in clob) return clob
  as
    l_customer_id number;
    l_asset_tag   varchar2(100 char);
    l_asset_id    number;
    l_result      clob;
  begin
    l_customer_id := client_customer_id(p_arguments);

    if l_customer_id is null then
      return unknown_client_refusal;
    end if;

    l_asset_tag := string_argument(p_arguments, 'asset_tag');
    l_asset_id  := find_asset_id(l_asset_tag, l_customer_id);

    if l_asset_id is null then
      return no_asset_refusal(l_asset_tag);
    end if;

    select json_object(
             'asset_tag' value l_asset_tag
           , 'count' value count(*)
           , 'service_calls' value coalesce(
               json_arrayagg(
                 json_object(
                   'called_on' value to_char(sc.called_on, 'YYYY-MM-DD')
                 , 'summary'   value sc.summary
                 )
                 order by sc.called_on desc
                 returning clob
               )
             , to_clob('[]')) format json
           returning clob)
      into l_result
      from sc_service_calls sc
     where sc.asset_id = l_asset_id;

    return l_result;
  end get_asset_history;


  function book_visit(p_arguments in clob) return clob
  as
    l_customer_id number;
    l_asset_tag   varchar2(100 char);
    l_asset_id    number;
    l_date        date;
    l_reason      reason_type;
    l_starts_on   date;
    l_ends_on     date;
    l_visit_id    number;
    l_client      varchar2(255 char);
    l_result      json_object_t := json_object_t();
  begin
    l_customer_id := client_customer_id(p_arguments);

    if l_customer_id is null then
      return unknown_client_refusal;
    end if;

    l_asset_tag := string_argument(p_arguments, 'asset_tag');
    l_asset_id  := find_asset_id(l_asset_tag, l_customer_id);

    if l_asset_id is null then
      return no_asset_refusal(l_asset_tag);
    end if;

    begin
      l_date := to_date(string_argument(p_arguments, 'visit_date'), 'YYYY-MM-DD');
    exception
      when others then
        -- @dblinter ignore(g-5040): every unreadable date has the same answer: ask for ISO format
        -- @dblinter ignore(g-5080): a rejected argument is expected input, not a fault to report
        return refusal(c_reason_bad_date, 'Give the visit date as YYYY-MM-DD.');
    end;

    l_reason := check_visit(l_asset_id, l_date, l_customer_id);

    if l_reason is not null then
      select max(c.starts_on)
           , max(c.ends_on)
        into l_starts_on
           , l_ends_on
        from sc_assets a
        join sc_contracts c on c.id = a.contract_id
       where a.id = l_asset_id;

      return refusal(
               l_reason
             , case l_reason
                 when c_reason_out_of_cover then
                   'The date ' || to_char(l_date, 'YYYY-MM-DD')
                   || ' is outside the contract coverage of ' || l_asset_tag
                   || ', which runs from ' || to_char(l_starts_on, 'YYYY-MM-DD')
                   || ' to ' || to_char(l_ends_on, 'YYYY-MM-DD') || '.'
                 when c_reason_open_request then
                   'A visit request for ' || l_asset_tag
                   || ' is already open. Only one open request is allowed for each asset.'
                 when c_reason_too_soon then
                   'A visit needs at least ' || c_notice_working_days
                   || ' working days notice. The earliest date is '
                   || to_char(add_working_days(trunc(sysdate), c_notice_working_days), 'YYYY-MM-DD')
                   || '.'
               end);
    end if;

    -- The client id of the run is written to the row. The handler does not commit.
    l_client := json_object_t(p_arguments).get_object(uc_ai.c_run_context_key).get_string('a2a_client');

    insert into partner_visits (asset_id, requested_for, status, client_id)
    values (l_asset_id, l_date, 'REQUESTED', l_client)
    returning id into l_visit_id;

    l_result.put('status', 'requested');
    l_result.put('visit_id', l_visit_id);
    l_result.put('asset_tag', l_asset_tag);
    l_result.put('requested_for', to_char(l_date, 'YYYY-MM-DD'));
    l_result.put('note', 'This is a request. A planner at the service company confirms the visit.');
    return l_result.to_clob;
  end book_visit;

end partner_desk_pkg;
/
