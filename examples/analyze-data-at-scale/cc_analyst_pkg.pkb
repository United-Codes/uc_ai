create or replace package body cc_analyst_pkg
as
  -- @dblinter ignore(g-2160): a local declaration that calls a function keeps the value
  -- next to the one place that uses it, which a tutorial reader follows more easily
  -- @dblinter ignore(g-5010): a tutorial package prints its results with dbms_output on
  -- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
  -- the output this course asks the reader to compare against the page.

  -- ---------------------------------------------------------------------------
  -- The rule
  -- ---------------------------------------------------------------------------
  function minutes_over(p_shipment_id in number) return number
  as
    l_minutes number;
  begin
    -- The run-length rule. Mark every reading above the limit, group the
    -- consecutive ones with the row_number difference, then keep only the groups
    -- that last LONGER than the class allows.
    with flagged as (
      select l.sample_minutes
           , l.max_minutes_above
           , row_number() over (order by r.reading_ts)
             - row_number() over (partition by case when r.temp_c > l.max_temp_c then 1 else 0 end
                                  order by r.reading_ts) as run_key
           , case when r.temp_c > l.max_temp_c then 1 else 0 end as is_above
        from cc_readings r
        join cc_shipments s on s.id = r.shipment_id
        join cc_limits    l on l.product_class = s.product_class
       where r.shipment_id = p_shipment_id
    ), runs as (
      select count(*) * min(sample_minutes) as run_minutes
           , min(max_minutes_above)         as max_minutes_above
        from flagged
       where is_above = 1
       group by run_key
    )
    select coalesce(sum(run_minutes), 0)
      into l_minutes
      from runs
     where run_minutes > max_minutes_above;

    return l_minutes;
  end minutes_over;

  -- ---------------------------------------------------------------------------
  -- Tool handlers
  -- ---------------------------------------------------------------------------
  function list_shipments(p_arguments in clob) return clob
  as
    l_args  json_object_t := json_object_t(p_arguments);
    l_class cc_shipments.product_class%type;
    l_rows  clob;
  begin
    -- Read by NAME. Never by position, and never by counting the keys: every
    -- tool also receives the run context under `_ctx`.
    l_class := upper(l_args.get_string('product_class'));

    select json_arrayagg(
             json_object( 'shipment_id'   value s.id
                        , 'shipment_no'   value s.shipment_no
                        , 'carrier'       value s.carrier
                        , 'lane'          value s.lane
                        , 'product_class' value s.product_class
                        , 'departed_at'   value to_char(s.departed_at, 'yyyy-mm-dd"T"hh24:mi')
                        returning clob )
             order by s.shipment_no returning clob )
      into l_rows
      from cc_shipments s
     where l_class is null
        or s.product_class = l_class;

    return coalesce(l_rows, to_clob('[]'));
  end list_shipments;


  function get_readings(p_arguments in clob) return clob
  as
    l_args        json_object_t := json_object_t(p_arguments);
    l_shipment_id number;
    l_out         json_object_t := json_object_t();
    l_rows        clob;
  begin
    l_shipment_id := l_args.get_number('shipment_id');

    if l_shipment_id is null then
      l_out.put('status', 'refused');
      l_out.put('reason', c_reason_unknown_shipment);
      l_out.put('message', 'shipment_id is required. Take it from CC_LIST_SHIPMENTS.');
      return l_out.to_clob;
    end if;

    select json_arrayagg(
             json_object( 'ts'     value to_char(r.reading_ts, 'yyyy-mm-dd"T"hh24:mi')
                        , 'temp_c' value r.temp_c
                        returning clob )
             order by r.reading_ts returning clob )
      into l_rows
      from cc_readings r
     where r.shipment_id = l_shipment_id;

    l_out.put('shipment_id', l_shipment_id);
    l_out.put('readings', json_array_t(coalesce(l_rows, to_clob('[]'))));
    return l_out.to_clob;
  end get_readings;


  function get_limits(p_arguments in clob) return clob
  as
    -- @dblinter ignore(g-7150): the signature is fixed by UC AI; this tool takes no arguments
    l_rows clob;
  begin
    select json_arrayagg(
             json_object( 'product_class'      value l.product_class
                        , 'max_temp_c'         value l.max_temp_c
                        , 'sample_minutes'     value l.sample_minutes
                        , 'max_minutes_above'  value l.max_minutes_above
                        , 'claim_per_hour_eur' value l.claim_per_hour_eur
                        returning clob )
             order by l.product_class returning clob )
      into l_rows
      from cc_limits l;

    return coalesce(l_rows, to_clob('[]'));
  end get_limits;


  -- Who to record as the author of a claim.
  --
  -- The obvious answer, coalesce(apex_user, db_user), is wrong inside an agent
  -- run. UC AI needs an APEX session to make an HTTPS call, so it creates a
  -- synthetic one and names it UC_AI_AGENT_EXEC. That name is not a person and not
  -- a schema, and an audit column that records it says nothing. UC AI treats the
  -- name the same way in its own execution row, where apex_user comes out null.
  function filing_user return varchar2
  as
    l_apex_user varchar2(255 char) := sys_context('APEX$SESSION', 'app_user');
  begin
    if l_apex_user = uc_ai_agent_exec_api.c_synthetic_apex_user then
      l_apex_user := null;
    end if;

    return coalesce(l_apex_user, sys_context('userenv', 'session_user'));
  end filing_user;


  function file_claim(p_arguments in clob) return clob
  as
    l_args         json_object_t := json_object_t(p_arguments);
    l_out          json_object_t := json_object_t();
    l_shipment_id  number;
    l_minutes_said number;
    l_amount_said  number;
    l_note         varchar2(400 char);

    l_shipment_no  cc_shipments.shipment_no%type;
    l_rate         cc_limits.claim_per_hour_eur%type;
    l_minutes_true number;
    l_amount_true  number;
    l_existing     pls_integer;
    l_filed_by     varchar2(120 char);

    procedure refuse(p_reason in reason_type, p_message in varchar2)
    is
    begin
      l_out.put('status', 'refused');
      l_out.put('reason', p_reason);
      l_out.put('message', p_message);
    end refuse;
  begin
    l_shipment_id  := l_args.get_number('shipment_id');
    l_minutes_said := l_args.get_number('minutes_over');
    l_amount_said  := l_args.get_number('amount_eur');
    l_note         := substr(l_args.get_string('note'), 1, 400);

    -- Guard the missing argument before the query. Without this, the refusal
    -- message reads "There is no shipment with id ." and the model has to guess
    -- what it did wrong.
    if l_shipment_id is null then
      refuse(c_reason_unknown_shipment
           , 'shipment_id is required. Take it from CC_LIST_SHIPMENTS.');
      return l_out.to_clob;
    end if;

    -- Both numbers are required, and the comparison below cannot enforce that.
    -- NULL != 240 is NULL, not true, so a missing number would fall through the
    -- check and the claim would be written from the values the database computed.
    -- The model has to state what it is claiming.
    if l_minutes_said is null or l_amount_said is null then
      refuse(c_reason_wrong_amount
           , 'minutes_over and amount_eur are both required. State the numbers you '
             || 'computed, and the database compares them with the readings.');
      return l_out.to_clob;
    end if;

    begin
      select s.shipment_no, l.claim_per_hour_eur
        into l_shipment_no, l_rate
        from cc_shipments s
        join cc_limits l on l.product_class = s.product_class
       where s.id = l_shipment_id;
    exception
      when no_data_found then
        refuse(c_reason_unknown_shipment
             , 'There is no shipment with id ' || l_shipment_id || '.');
        return l_out.to_clob;
    end;

    -- The database owns the rule. Whatever the program computed, the claim is
    -- written only when the readings agree.
    l_minutes_true := minutes_over(l_shipment_id);

    if l_minutes_true = 0 then
      refuse(c_reason_no_excursion
           , l_shipment_no || ' did not break the cold chain. It was above its limit, '
             || 'but never for longer than the limit allows. No claim is possible.');
      return l_out.to_clob;
    end if;

    l_amount_true := ceil(l_minutes_true / 60) * l_rate;

    if l_minutes_said != l_minutes_true or l_amount_said != l_amount_true then
      refuse(c_reason_wrong_amount
           , 'The claim does not match the readings. You said ' || l_minutes_said
             || ' minutes and ' || l_amount_said || ' EUR. The database computes '
             || l_minutes_true || ' minutes and ' || l_amount_true || ' EUR.');
      return l_out.to_clob;
    end if;

    -- @dblinter ignore(g-8110): a presence check; a scalar count is the clearest form here
    select count(*) into l_existing from cc_claims where shipment_id = l_shipment_id;

    if l_existing > 0 then
      refuse(c_reason_already_filed
           , 'A claim for ' || l_shipment_no || ' is already filed.');
      return l_out.to_clob;
    end if;

    -- A local variable, because a private package function cannot be called from
    -- inside SQL.
    l_filed_by := filing_user;

    insert into cc_claims (shipment_id, minutes_over, amount_eur, filed_by, note)
    values (l_shipment_id, l_minutes_true, l_amount_true, l_filed_by, l_note);

    l_out.put('status', 'filed');
    l_out.put('shipment_no', l_shipment_no);
    l_out.put('minutes_over', l_minutes_true);
    l_out.put('amount_eur', l_amount_true);
    return l_out.to_clob;
  end file_claim;

  -- ---------------------------------------------------------------------------
  -- Measuring
  -- ---------------------------------------------------------------------------
  -- Walks the normalised messages array of a generate_text result and hands each
  -- content item to the caller. The shape is:
  --   messages[i].content[j] = { "type": "tool_call", "toolName": ..., "args": "<json string>" }
  function tool_call_arguments(
    p_result    in json_object_t
  , p_tool_name in varchar2
  ) return clob
  as
    l_messages json_array_t;
    l_message  json_object_t;
    l_content  json_array_t;
    l_item     json_object_t;
  begin
    l_messages := p_result.get_array('messages');

    if l_messages is null then
      return null;
    end if;

    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_message := treat(l_messages.get(i) as json_object_t);

      if l_message.get('content') is not null and l_message.get('content').is_array then
        l_content := l_message.get_array('content');

        <<content_loop>>
        for j in 0 .. l_content.get_size - 1 loop
          l_item := treat(l_content.get(j) as json_object_t);

          if l_item.get_string('type') = 'tool_call'
             and l_item.get_string('toolName') = p_tool_name
          then
            -- get_clob, not get_string: a generated program passes 32k easily.
            return l_item.get_clob('args');
          end if;
        end loop content_loop;
      end if;
    end loop message_loop;

    return null;
  end tool_call_arguments;


  function used_program(p_result in json_object_t) return boolean
  as
  begin
    return tool_call_arguments(p_result, uc_ai_tools_api.c_code_mode_tool_code) is not null;
  end used_program;


  function program_source(p_result in json_object_t) return clob
  as
    l_args clob := tool_call_arguments(p_result, uc_ai_tools_api.c_code_mode_tool_code);
  begin
    if l_args is null then
      return null;
    end if;

    return json_object_t.parse(l_args).get_clob('code');
  end program_source;


  function round_trips(p_result in json_object_t) return pls_integer
  as
    l_messages json_array_t := p_result.get_array('messages');
    l_message  json_object_t;
    l_count    pls_integer := 0;
  begin
    if l_messages is null then
      return 0;
    end if;

    <<message_loop>>
    for i in 0 .. l_messages.get_size - 1 loop
      l_message := treat(l_messages.get(i) as json_object_t);

      if l_message.get_string('role') = 'assistant' then
        l_count := l_count + 1;
      end if;
    end loop message_loop;

    return l_count;
  end round_trips;


  procedure print_header
  as
  begin
    sys.dbms_output.put_line(
      rpad('run', 22) || rpad('program', 9) || lpad('calls', 6) || lpad('in', 9)
      || lpad('out', 8) || lpad('trips', 7) || lpad('secs', 7) || '  finish_reason');
    sys.dbms_output.put_line(rpad('-', 22 + 9 + 6 + 9 + 8 + 7 + 7 + 16, '-'));
  end print_header;


  procedure print_metrics(
    p_label   in varchar2
  , p_result  in json_object_t
  , p_seconds in number default null
  )
  as
    l_usage json_object_t := p_result.get_object('usage');
  begin
    sys.dbms_output.put_line(
      rpad(substr(p_label, 1, 21), 22)
      || rpad(case when used_program(p_result) then 'yes' else 'no' end, 9)
      || lpad(to_char(p_result.get_number('tool_calls_count')), 6)
      || lpad(to_char(l_usage.get_number('prompt_tokens')), 9)
      || lpad(to_char(l_usage.get_number('completion_tokens')), 8)
      || lpad(to_char(round_trips(p_result)), 7)
      || lpad(coalesce(to_char(p_seconds), '-'), 7)
      || '  ' || p_result.get_string('finish_reason'));
  end print_metrics;

end cc_analyst_pkg;
/
