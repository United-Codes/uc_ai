create or replace package body mx_desk_pkg
as
  /**
  * UC AI tutorial — "Give an Agent a Memory"
  * The two read tools of the maintenance desk. See the specification for the
  * two rules both handlers follow.
  */

  -- What a handler answers when the run bound no asset. It is a message for the
  -- model, not an exception: a tool that raises ends the run, and a tool that
  -- explains itself lets the model tell the technician what is wrong.
  function no_asset return clob
  as
    l_result json_object_t := json_object_t();
  begin
    l_result.put('status', 'refused');
    l_result.put('reason', 'no_asset_in_run_context');
    l_result.put('message', 'This run is not bound to an asset, so there is nothing '
                         || 'to read. Tell the technician that the desk was opened '
                         || 'without an asset.');
    return l_result.to_clob;
  end no_asset;


  function context_value(
    p_arguments in clob
  , p_key       in varchar2
  ) return varchar2
  as
    l_args    json_object_t;
    l_context json_object_t;
  begin
    if p_arguments is null then
      return null;
    end if;

    l_args := json_object_t(p_arguments);

    -- UC AI always adds this key. It holds an empty object when the run carries
    -- no context. Read it by NAME; never reason about how many keys the
    -- arguments have.
    l_context := l_args.get_object(uc_ai.c_run_context_key);

    if l_context is null then
      return null;
    end if;

    return uc_ai.run_context_value(l_context.to_clob, p_key);
  exception
    when others then
      -- Arguments that are not a JSON object are the same situation as a run
      -- with no context.
      -- @dblinter ignore(g-5040): one answer is correct for every malformed bag
      -- @dblinter ignore(g-5080): the caller turns null into a refusal with a reason
      return null;
  end context_value;


  function get_asset(p_arguments in clob) return clob
  as
    l_asset_no varchar2(30 char);
    l_result   json_object_t := json_object_t();
    l_alarms   json_array_t  := json_array_t();
    l_found    boolean       := false;
  begin
    l_asset_no := substr(context_value(p_arguments, 'asset_no'), 1, 30);

    if l_asset_no is null then
      return no_asset;
    end if;

    <<asset_row>>
    for r in (
      select a.asset_no
           , a.asset_name
           , a.asset_type
           , a.line_code
           , a.status
           , to_char(a.installed_on, 'YYYY-MM-DD') as installed_on
        from mx_assets a
       where a.asset_no = l_asset_no
    )
    loop
      l_found := true;
      l_result.put('asset_no', r.asset_no);
      l_result.put('asset_name', r.asset_name);
      l_result.put('asset_type', r.asset_type);
      l_result.put('line_code', r.line_code);
      l_result.put('status', r.status);
      l_result.put('installed_on', r.installed_on);
    end loop asset_row;

    if not l_found then
      l_result.put('status', 'not_found');
      l_result.put('message', 'No asset ' || l_asset_no || ' on this site.');
      return l_result.to_clob;
    end if;

    <<open_alarms>>
    for r in (
      select al.alarm_code
           , al.alarm_text
           , al.severity
           , to_char(al.raised_at, 'YYYY-MM-DD') as raised_at
        from mx_alarms al
       where al.asset_no = l_asset_no
         and al.alarm_status = 'OPEN'
       order by al.raised_at desc
    )
    loop
      l_alarms.append(json_object_t(
        json_object('alarm_code'  value r.alarm_code
                  , 'alarm_text'  value r.alarm_text
                  , 'severity'    value r.severity
                  , 'raised_at'   value r.raised_at)));
    end loop open_alarms;

    l_result.put('open_alarms', l_alarms);
    return l_result.to_clob;
  end get_asset;


  function list_work_orders(p_arguments in clob) return clob
  as
    l_asset_no varchar2(30 char);
    l_result   json_object_t := json_object_t();
    l_orders   json_array_t  := json_array_t();
  begin
    l_asset_no := substr(context_value(p_arguments, 'asset_no'), 1, 30);

    if l_asset_no is null then
      return no_asset;
    end if;

    <<order_rows>>
    for r in (
      select w.wo_no
           , to_char(w.opened_on, 'YYYY-MM-DD') as opened_on
           , w.symptom
           , w.cause
           , w.action_taken
           , w.downtime_minutes
        from mx_work_orders w
       where w.asset_no = l_asset_no
       order by w.opened_on desc
    )
    loop
      l_orders.append(json_object_t(
        json_object('wo_no'            value r.wo_no
                  , 'opened_on'        value r.opened_on
                  , 'symptom'          value r.symptom
                  , 'cause'            value r.cause
                  , 'action_taken'     value r.action_taken
                  , 'downtime_minutes' value r.downtime_minutes)));
    end loop order_rows;

    l_result.put('asset_no', l_asset_no);
    l_result.put('work_orders', l_orders);
    return l_result.to_clob;
  end list_work_orders;

end mx_desk_pkg;
/
