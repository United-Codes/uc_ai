create or replace package body uc_ai_chat_widgets as

  c_scope        constant varchar2(30 char) := 'uc_ai_chat_widgets.render';
  c_scope_emit   constant varchar2(30 char) := 'uc_ai_chat_widgets.write_parts';
  c_invalid_code constant pls_integer := -20900;
  c_max_str      constant pls_integer := 200;
  c_max_body     constant pls_integer := 30000;

  e_invalid exception;
  pragma exception_init(e_invalid, -20900);

  procedure fail(p_reason in varchar2)
  as
  begin
    raise_application_error(c_invalid_code, p_reason);
  end fail;

  function type_enabled(
    p_types in varchar2,
    p_type  in varchar2
  ) return boolean
  as
  begin
    return instr(':' || p_types || ':', ':' || p_type || ':') > 0;
  end type_enabled;

  -- The provider package of a registered, enabled type; null when there is none.
  function provider_package_of(
    p_type in varchar2
  ) return varchar2
  as
    l_pkg uc_ai_chat_widget_types.provider_package%type;
  begin
    select provider_package
      into l_pkg
      from uc_ai_chat_widget_types
     where type_code = p_type
       and enabled = 'Y';
    return l_pkg;
  exception
    when no_data_found then
      return null;
  end provider_package_of;

  function is_builtin(
    p_type in varchar2
  ) return boolean
  as
  begin
    return p_type = c_type_item_list or type_enabled(c_all_types, p_type);
  end is_builtin;

  -- Is any type of the list a registered one (not built in)?
  function has_provider_types(
    p_types in varchar2
  ) return boolean
  as
  begin
    <<t_loop>>
    for i in 1 .. regexp_count(p_types, '[^:]+') loop
      if not is_builtin(regexp_substr(p_types, '[^:]+', 1, i)) then
        return true;
      end if;
    end loop t_loop;
    return false;
  end has_provider_types;

  function normalize_types(
    p_types in varchar2
  ) return varchar2
  as
    l_in  varchar2(4000 char);
    l_t   varchar2(30 char);
    l_out varchar2(200 char);
  begin
    l_in := ':' || lower(replace(p_types, ' ')) || ':';
    if p_types is null then
      return null;
    end if;

    -- walk c_all_types, not the input: the built-in part cannot hold anything else
    <<t_loop>>
    for i in 1 .. regexp_count(c_all_types, ':') + 1 loop
      l_t := regexp_substr(c_all_types, '[^:]+', 1, i);
      if instr(l_in, ':' || l_t || ':') > 0 then
        l_out := case when l_out is null then l_t else l_out || ':' || l_t end;
      end if;
    end loop t_loop;

    -- then the custom types, but only those that are registered and enabled
    <<p_loop>>
    for i in 1 .. regexp_count(l_in, '[^:]+') loop
      l_t := substr(regexp_substr(l_in, '[^:]+', 1, i), 1, 30);
      if not is_builtin(l_t)
         and not type_enabled(l_out, l_t)
         and nvl(length(l_out), 0) + length(l_t) + 1 <= 200
         and provider_package_of(l_t) is not null
      then
        l_out := case when l_out is null then l_t else l_out || ':' || l_t end;
      end if;
    end loop p_loop;
    return l_out;
  end normalize_types;

  procedure register_type(
    p_type             in varchar2,
    p_provider_package in varchar2
  )
  as
    l_pkg    varchar2(261 char);
    l_owner  varchar2(128 char);
    l_name   varchar2(128 char);
    l_dot    pls_integer;
    l_found  pls_integer;
  begin
    if p_type is null or not regexp_like(p_type, '^[a-z][a-z0-9_]{1,29}$') then
      raise_application_error(-20901, 'widget type must be 2 to 30 characters of a-z, 0-9 and _, starting with a letter');
    end if;
    if is_builtin(p_type) then
      raise_application_error(-20901, 'widget type ' || p_type || ' is reserved');
    end if;

    -- raises ORA-44004 / ORA-44002 for anything that is not a (qualified) package name
    l_pkg := sys.dbms_assert.qualified_sql_name(p_provider_package);
    l_dot := instr(l_pkg, '.');
    l_owner := upper(case when l_dot > 0 then substr(l_pkg, 1, l_dot - 1)
                          else sys_context('USERENV', 'CURRENT_SCHEMA') end);
    l_name := upper(case when l_dot > 0 then substr(l_pkg, l_dot + 1) else l_pkg end);

    -- @dblinter ignore(G-8110): the count IS the check (both members must exist), not an existence probe
    select count(distinct procedure_name)
      into l_found
      from all_procedures
     where owner = l_owner
       and object_name = l_name
       and procedure_name in ('GET_PROTOCOL', 'BUILD_SPEC');
    if l_found <> 2 then
      raise_application_error(-20901, l_pkg || ' must be a package with get_protocol and build_spec');
    end if;

    merge into uc_ai_chat_widget_types t
    using (select p_type as type_code, l_pkg as provider_package from dual) s
       on (t.type_code = s.type_code)
     when matched then update set t.provider_package = s.provider_package, t.enabled = 'Y'
     when not matched then insert (type_code, provider_package) values (s.type_code, s.provider_package);
  end register_type;

  function type_in_list(
    p_list in varchar2,
    p_type in varchar2
  ) return boolean
  as
  begin
    return type_enabled(p_list, p_type);
  end type_in_list;

  procedure unregister_type(
    p_type in varchar2
  )
  as
  begin
    delete from uc_ai_chat_widget_types where type_code = lower(p_type);
  end unregister_type;

  function slice(
    p_clob in clob,
    p_from in pls_integer,
    p_to   in pls_integer
  ) return clob
  as
    l_out clob;
  begin
    if p_to < p_from then
      return null;
    end if;
    sys.dbms_lob.createtemporary(l_out, true);
    sys.dbms_lob.copy(l_out, p_clob, p_to - p_from + 1, 1, p_from);
    return l_out;
  end slice;

  -- A string or number member as text; null when absent.
  function str_of(
    p_obj      in json_object_t,
    p_key      in varchar2,
    p_required in boolean default false,
    p_max      in pls_integer default c_max_str
  ) return varchar2
  as
    l_el  json_element_t;
    l_val varchar2(4000 char);
  begin
    l_el := p_obj.get(p_key);
    if l_el is null or l_el.is_null then
      if p_required then
        fail(p_key || ' is required');
      end if;
      return null;
    end if;

    if l_el.is_string then
      l_val := p_obj.get_string(p_key);
    elsif l_el.is_number then
      l_val := trim(to_char(p_obj.get_number(p_key), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    else
      fail(p_key || ' must be a string or a number');
    end if;

    if length(l_val) > p_max then
      fail(p_key || ' is longer than ' || p_max || ' characters');
    end if;
    return l_val;
  end str_of;

  function enum_of(
    p_obj      in json_object_t,
    p_key      in varchar2,
    p_allowed  in varchar2,
    p_required in boolean default false
  ) return varchar2
  as
    l_val varchar2(100 char);
  begin
    l_val := lower(str_of(p_obj, p_key, p_required, 100));
    if l_val is not null and instr(':' || p_allowed || ':', ':' || l_val || ':') = 0 then
      fail(p_key || ' must be one of ' || replace(p_allowed, ':', ', '));
    end if;
    return l_val;
  end enum_of;

  procedure put_if(
    pio_obj in out nocopy json_object_t,
    p_key   in varchar2,
    p_val   in varchar2
  )
  as
  begin
    if p_val is not null then
      pio_obj.put(p_key, p_val);
    end if;
  end put_if;

  -- Copy one scalar cell of a row into a clean object.
  procedure copy_cell(
    p_src in json_object_t,
    p_key in varchar2,
    pio_dst in out nocopy json_object_t,
    p_dst_key in varchar2 default null
  )
  as
    l_el json_element_t;
    l_dst_key varchar2(64 char);
  begin
    l_el := p_src.get(p_key);
    l_dst_key := coalesce(p_dst_key, p_key);
    if l_el is null or l_el.is_null then
      pio_dst.put_null(l_dst_key);
    elsif l_el.is_string then
      if length(p_src.get_string(p_key)) > c_max_str then
        fail('a cell in column ' || p_key || ' is longer than ' || c_max_str || ' characters');
      end if;
      pio_dst.put(l_dst_key, p_src.get_string(p_key));
    elsif l_el.is_number then
      pio_dst.put(l_dst_key, p_src.get_number(p_key));
    else
      fail('column ' || p_key || ' holds a value that is not a string or number');
    end if;
  end copy_cell;

  -- Text to number with '.' as the decimal mark whatever the session NLS says.
  -- Null when the text is not a number.
  function to_num(p_text in varchar2) return number
  as
  begin
    return to_number(
      p_text default null on conversion error,
      '999999999999999999999999.999999999999',
      'NLS_NUMERIC_CHARACTERS=''.,''');
  end to_num;

  -- The part of a tool name after the last dot: the models of one provider write
  -- "functions.get_sales" for a tool that is called "get_sales".
  function base_name(p_name in varchar2) return varchar2
  as
  begin
    return substr(p_name, instr(p_name, '.', -1) + 1);
  end base_name;

  -- Does one argument of a call hold the value the widget asked for? Strings are
  -- compared as text, case-sensitive. When either side is a number, both are
  -- compared as numbers.
  function arg_equal(
    p_want in json_object_t,
    p_have in json_object_t,
    p_key  in varchar2
  ) return boolean
  as
    l_want json_element_t;
    l_have json_element_t;
    l_w    varchar2(4000 char);
    l_h    varchar2(4000 char);
    l_wn   number;
    l_hn   number;
  begin
    l_want := p_want.get(p_key);
    l_have := p_have.get(p_key);
    if l_have is null or l_have.is_null or not (l_have.is_string or l_have.is_number or l_have.is_boolean) then
      return false;
    end if;

    -- a boolean never equals a number
    if (l_want.is_boolean and l_have.is_number) or (l_want.is_number and l_have.is_boolean) then
      return false;
    end if;

    if l_want.is_number or l_have.is_number then
      l_wn := case when l_want.is_number then p_want.get_number(p_key) else to_num(p_want.get_string(p_key)) end;
      l_hn := case when l_have.is_number then p_have.get_number(p_key) else to_num(p_have.get_string(p_key)) end;
      return l_wn is not null and l_hn is not null and l_wn = l_hn;
    end if;

    l_w := case when l_want.is_boolean
             then case when p_want.get_boolean(p_key) then 'true' else 'false' end
             else p_want.get_string(p_key) end;
    l_h := case when l_have.is_boolean
             then case when p_have.get_boolean(p_key) then 'true' else 'false' end
             else p_have.get_string(p_key) end;
    return l_w = l_h;
  end arg_equal;

  -- The widget's "args" holds only scalars, at most 10.
  procedure check_args(p_args in json_object_t)
  as
    l_keys json_key_list := p_args.get_keys;
    l_el   json_element_t;
  begin
    if l_keys.count > 10 then
      fail('args holds more than 10 members');
    end if;
    <<i_loop>>
    for i in 1 .. l_keys.count loop
      l_el := p_args.get(l_keys(i));
      if l_el is null or l_el.is_null or not (l_el.is_string or l_el.is_number or l_el.is_boolean) then
        fail('args member ' || substr(l_keys(i), 1, 60) || ' must be a string, number or boolean');
      end if;
    end loop i_loop;
  end check_args;

  -- The arguments of one recorded call as an object; null when the call has none
  -- or they are not a JSON object.
  function call_args(p_call in json_object_t) return json_object_t
  as
    l_el json_element_t;
  begin
    l_el := p_call.get('args');
    if l_el is null or l_el.is_null then
      return null;
    end if;
    if l_el.is_object then
      return treat(l_el as json_object_t);
    end if;
    if l_el.is_string then
      begin
        return json_object_t.parse(p_call.get_clob('args'));
      exception
        when others then -- @dblinter ignore(g-5040): arguments that are not a JSON object just match no "args"
          return null;
      end;
    end if;
    return null;
  end call_args;

  -- The call of this turn the widget names: the latest call of the tool whose
  -- arguments contain every member of the widget's "args".
  function find_call(
    p_calls in json_array_t,
    p_tool  in varchar2,
    p_want  in json_object_t
  ) return json_object_t
  as
    l_call   json_object_t;
    l_have   json_object_t;
    l_keys   json_key_list;
    l_named  boolean := false;
    l_match  boolean;
    l_base   varchar2(255 char);
    l_name   varchar2(255 char);
  begin
    l_base := base_name(p_tool);
    if p_calls is null then
      fail('no result of tool ' || p_tool || ' in this turn');
    end if;
    if p_want is not null then
      check_args(p_want);
      l_keys := p_want.get_keys;
    end if;

    <<call_loop>>
    for i in reverse 0 .. p_calls.get_size - 1 loop
      l_call := treat(p_calls.get(i) as json_object_t);
      l_name := lower(l_call.get_string('name'));
      continue call_loop when l_name is null or (l_name <> p_tool and l_name <> l_base);
      l_named := true;

      l_match := true;
      if l_keys is not null and l_keys.count > 0 then
        l_have := call_args(l_call);
        <<key_loop>>
        for k in 1 .. l_keys.count loop
          if l_have is null or not arg_equal(p_want, l_have, l_keys(k)) then
            l_match := false;
            exit key_loop;
          end if;
        end loop key_loop;
      end if;

      if l_match then
        return l_call;
      end if;
    end loop call_loop;

    if l_named then
      fail('no call of tool ' || p_tool || ' matches the args');
    end if;
    fail('no result of tool ' || p_tool || ' in this turn');
    return null; -- unreachable: fail always raises
  end find_call;

  -- Rows from inline "data" or from "source": "tool:<name>" (+ optional "args").
  function resolve_rows(
    p_spec       in json_object_t,
    p_tool_calls in json_array_t
  ) return json_array_t
  as
    l_source varchar2(300 char);
    l_tool   varchar2(255 char);
    l_el     json_element_t;
    l_obj    json_object_t;
    l_call   json_object_t;
    l_args   json_object_t;
    l_keys   json_key_list;
  begin
    if p_spec.has('data') and p_spec.has('source') then
      fail('use either data or source, not both');
    end if;

    if p_spec.has('data') then
      l_el := p_spec.get('data');
      if l_el is null or not l_el.is_array then
        fail('data must be an array of objects');
      end if;
      return treat(l_el as json_array_t);
    end if;

    l_source := str_of(p_spec, 'source', true, 300);
    if lower(substr(l_source, 1, 5)) <> 'tool:' then
      fail('source must look like tool:<tool_name>');
    end if;
    -- tool names are matched case-insensitive
    l_tool := lower(trim(substr(l_source, 6)));

    l_el := p_spec.get('args');
    if l_el is not null and not l_el.is_null then
      if not l_el.is_object then
        fail('args must be an object');
      end if;
      l_args := treat(l_el as json_object_t);
    end if;

    l_call := find_call(p_tool_calls, l_tool, l_args);

    l_el := l_call.get('output');
    if l_el is null or l_el.is_null then
      fail('the result of tool ' || l_tool || ' is not JSON');
    end if;
    if l_el.is_array then
      return treat(l_el as json_array_t);
    end if;

    -- an object result: take the first member that is an array
    if l_el.is_object then
      l_obj := treat(l_el as json_object_t);
      l_keys := l_obj.get_keys;
      <<i_loop>>
      for i in 1 .. l_keys.count loop
        if l_obj.get(l_keys(i)).is_array then
          return treat(l_obj.get(l_keys(i)) as json_array_t);
        end if;
      end loop i_loop;
    end if;
    fail('the result of tool ' || l_tool || ' holds no array of rows');
    return null; -- unreachable: fail always raises
  end resolve_rows;

  function row_at(
    p_rows in json_array_t,
    p_idx  in pls_integer
  ) return json_object_t
  as
    l_el json_element_t;
  begin
    l_el := p_rows.get(p_idx);
    if l_el is null or not l_el.is_object then
      fail('row ' || (p_idx + 1) || ' is not an object');
    end if;
    return treat(l_el as json_object_t);
  end row_at;

  function clean_stat_card(p_spec in json_object_t) return json_object_t
  as
    l_out json_object_t := json_object_t();
  begin
    l_out.put('type', c_type_stat_card);
    l_out.put('label', str_of(p_spec, 'label', true, 80));
    l_out.put('value', str_of(p_spec, 'value', true, 40));
    put_if(l_out, 'unit', str_of(p_spec, 'unit', false, 20));
    put_if(l_out, 'delta', str_of(p_spec, 'delta', false, 40));
    put_if(l_out, 'trend', enum_of(p_spec, 'trend', 'up:down:flat'));
    return l_out;
  end clean_stat_card;

  function clean_status(p_spec in json_object_t) return json_object_t
  as
    l_out json_object_t := json_object_t();
  begin
    l_out.put('type', c_type_status);
    l_out.put('level', enum_of(p_spec, 'level', 'ok:info:warn:error', true));
    l_out.put('title', str_of(p_spec, 'title', true, 120));
    put_if(l_out, 'text', str_of(p_spec, 'text', false, 500));
    return l_out;
  end clean_status;

  function clean_key_value(p_spec in json_object_t) return json_object_t
  as
    l_out   json_object_t := json_object_t();
    l_items json_array_t;
    l_clean json_array_t := json_array_t();
    l_item  json_object_t;
    l_pair  json_object_t;
    l_el    json_element_t;
  begin
    l_el := p_spec.get('items');
    if l_el is null or not l_el.is_array then
      fail('items must be an array');
    end if;
    l_items := treat(l_el as json_array_t);
    if l_items.get_size = 0 or l_items.get_size > 20 then
      fail('items must hold 1 to 20 entries');
    end if;

    <<i_loop>>
    for i in 0 .. l_items.get_size - 1 loop
      l_item := row_at(l_items, i);
      l_pair := json_object_t();
      l_pair.put('label', str_of(l_item, 'label', true, 80));
      l_pair.put('value', str_of(l_item, 'value', true, c_max_str));
      l_clean.append(l_pair);
    end loop i_loop;

    l_out.put('type', c_type_key_value);
    put_if(l_out, 'title', str_of(p_spec, 'title', false, 120));
    l_out.put('items', l_clean);
    return l_out;
  end clean_key_value;

  -- A column that no row has is a wrong name (a display label instead of the
  -- key of the row): fail instead of showing a table or chart full of nulls.
  procedure require_column(
    p_rows  in json_array_t,
    p_col   in varchar2,
    p_limit in pls_integer
  )
  as
    l_row json_object_t;
  begin
    <<row_loop>>
    for i in 0 .. p_limit - 1 loop
      l_row := row_at(p_rows, i);
      if l_row.has(p_col) then
        return;
      end if;
    end loop row_loop;
    if p_limit > 0 then
      fail('column ' || p_col || ' is not in the rows; use the exact keys of the rows');
    end if;
  end require_column;

  function clean_table(
    p_spec       in json_object_t,
    p_tool_calls in json_array_t
  ) return json_object_t
  as
    l_out    json_object_t := json_object_t();
    l_cols   json_array_t;
    l_colnm  json_array_t := json_array_t();
    l_rows   json_array_t;
    l_clean  json_array_t := json_array_t();
    l_row    json_object_t;
    l_new    json_object_t;
    l_el     json_element_t;
    l_col    varchar2(64 char);
    l_limit  pls_integer;
  begin
    l_el := p_spec.get('columns');
    if l_el is null or not l_el.is_array then
      fail('columns must be an array of column names');
    end if;
    l_cols := treat(l_el as json_array_t);
    if l_cols.get_size = 0 or l_cols.get_size > 12 then
      fail('columns must hold 1 to 12 names');
    end if;
    <<i_loop>>
    for i in 0 .. l_cols.get_size - 1 loop
      if not l_cols.get(i).is_string then
        fail('a column name is not a string');
      end if;
      l_col := l_cols.get_string(i);
      l_colnm.append(l_col);
    end loop i_loop;

    l_rows := resolve_rows(p_spec, p_tool_calls);
    l_limit := least(l_rows.get_size, c_max_rows);
    <<col_loop>>
    for c in 0 .. l_colnm.get_size - 1 loop
      require_column(l_rows, l_colnm.get_string(c), l_limit);
    end loop col_loop;
    <<i_loop>>
    for i in 0 .. l_limit - 1 loop
      l_row := row_at(l_rows, i);
      l_new := json_object_t();
      <<c_loop>>
      for c in 0 .. l_colnm.get_size - 1 loop
        copy_cell(l_row, l_colnm.get_string(c), l_new);
      end loop c_loop;
      l_clean.append(l_new);
    end loop i_loop;

    l_out.put('type', c_type_table);
    put_if(l_out, 'title', str_of(p_spec, 'title', false, 120));
    l_out.put('columns', l_colnm);
    l_out.put('rows', l_clean);
    l_out.put('truncated', l_rows.get_size > c_max_rows);
    return l_out;
  end clean_table;

  function clean_chart(
    p_spec       in json_object_t,
    p_tool_calls in json_array_t
  ) return json_object_t
  as
    l_out   json_object_t := json_object_t();
    l_rows  json_array_t;
    l_clean json_array_t := json_array_t();
    l_row   json_object_t;
    l_pt    json_object_t;
    l_x     varchar2(64 char);
    l_y     varchar2(64 char);
    l_yel   json_element_t;
    l_ynum  number;
  begin
    l_x := str_of(p_spec, 'x', true, 64);
    l_y := str_of(p_spec, 'y', true, 64);
    l_rows := resolve_rows(p_spec, p_tool_calls);
    if l_rows.get_size = 0 then
      fail('the chart has no rows');
    end if;
    if l_rows.get_size > c_max_points then
      fail('the chart has more than ' || c_max_points || ' points');
    end if;
    require_column(l_rows, l_x, l_rows.get_size);
    require_column(l_rows, l_y, l_rows.get_size);

    <<i_loop>>
    for i in 0 .. l_rows.get_size - 1 loop
      l_row := row_at(l_rows, i);
      l_pt := json_object_t();
      copy_cell(l_row, l_x, l_pt, 'x');
      l_yel := l_row.get(l_y);
      if l_yel is not null and l_yel.is_number then
        l_ynum := l_row.get_number(l_y);
      elsif l_yel is not null and l_yel.is_string then
        -- the model writes '.' as the decimal mark whatever the session NLS says
        l_ynum := to_num(l_row.get_string(l_y));
      else
        l_ynum := null;
      end if;
      if l_ynum is null then
        fail('column ' || l_y || ' is not a number in row ' || (i + 1));
      end if;
      l_pt.put('y', l_ynum);
      l_clean.append(l_pt);
    end loop i_loop;

    l_out.put('type', c_type_chart);
    l_out.put('kind', coalesce(enum_of(p_spec, 'kind', 'bar:line'), 'bar'));
    put_if(l_out, 'title', str_of(p_spec, 'title', false, 120));
    put_if(l_out, 'x_label', str_of(p_spec, 'x_label', false, 60));
    put_if(l_out, 'y_label', str_of(p_spec, 'y_label', false, 60));
    l_out.put('data', l_clean);
    return l_out;
  end clean_chart;

  -- One short text of an array: a string or a number, bounded.
  function text_at(
    p_arr in json_array_t,
    p_idx in pls_integer,
    p_max in pls_integer
  ) return varchar2
  as
    l_el  json_element_t;
    l_val varchar2(4000 char);
  begin
    l_el := p_arr.get(p_idx);
    if l_el is null or l_el.is_null then
      return null;
    elsif l_el.is_string then
      l_val := p_arr.get_string(p_idx);
    elsif l_el.is_number then
      l_val := trim(to_char(p_arr.get_number(p_idx), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    else
      fail('a list entry must be a string or a number');
    end if;
    if length(l_val) > p_max then
      fail('a list entry is longer than ' || p_max || ' characters');
    end if;
    return l_val;
  end text_at;

  function clean_badges(p_item in json_object_t) return json_array_t
  as
    l_el    json_element_t;
    l_arr   json_array_t;
    l_badge json_object_t;
    l_clean json_array_t := json_array_t();
    l_out   json_object_t;
  begin
    l_el := p_item.get('badges');
    if l_el is null or l_el.is_null then
      return null;
    end if;
    if not l_el.is_array then
      fail('badges must be an array');
    end if;
    l_arr := treat(l_el as json_array_t);
    if l_arr.get_size > 3 then
      fail('an item holds more than 3 badges');
    end if;
    <<b_loop>>
    for i in 0 .. l_arr.get_size - 1 loop
      l_badge := row_at(l_arr, i);
      l_out := json_object_t();
      l_out.put('text', str_of(l_badge, 'text', true, 40));
      l_out.put('tone', coalesce(enum_of(l_badge, 'tone', 'neutral:info:ok:warn:error'), 'neutral'));
      l_clean.append(l_out);
    end loop b_loop;
    return l_clean;
  end clean_badges;

  function clean_meta(p_item in json_object_t) return json_array_t
  as
    l_el    json_element_t;
    l_arr   json_array_t;
    l_clean json_array_t := json_array_t();
    l_text  varchar2(200 char);
  begin
    l_el := p_item.get('meta');
    if l_el is null or l_el.is_null then
      return null;
    end if;
    if not l_el.is_array then
      fail('meta must be an array');
    end if;
    l_arr := treat(l_el as json_array_t);
    if l_arr.get_size > 4 then
      fail('an item holds more than 4 meta entries');
    end if;
    <<m_loop>>
    for i in 0 .. l_arr.get_size - 1 loop
      l_text := text_at(l_arr, i, 60);
      if l_text is not null then
        l_clean.append(l_text);
      end if;
    end loop m_loop;
    return case when l_clean.get_size > 0 then l_clean end;
  end clean_meta;

  function clean_action(p_item in json_object_t) return json_object_t
  as
    l_el  json_element_t;
    l_act json_object_t;
    l_out json_object_t := json_object_t();
    l_nm  varchar2(100 char);
  begin
    l_el := p_item.get('action');
    if l_el is null or l_el.is_null then
      return null;
    end if;
    if not l_el.is_object then
      fail('action must be an object');
    end if;
    l_act := treat(l_el as json_object_t);
    l_nm := str_of(l_act, 'name', true, 40);
    if not regexp_like(l_nm, '^[a-z0-9_.-]{1,40}$') then
      fail('action name may hold only a-z, 0-9, _, . and -');
    end if;
    l_out.put('name', l_nm);
    l_out.put('id', str_of(l_act, 'id', true, 100));
    put_if(l_out, 'label', str_of(l_act, 'label', false, 40));
    return l_out;
  end clean_action;

  -- The render type of third-party widgets. The model cannot ask for it; it exists
  -- only as the output of a provider, and is rebuilt here from a whitelist anyway.
  function clean_item_list(p_spec in json_object_t) return json_object_t
  as
    l_out   json_object_t := json_object_t();
    l_items json_array_t;
    l_clean json_array_t := json_array_t();
    l_item  json_object_t;
    l_new   json_object_t;
    l_el    json_element_t;
    l_arr   json_array_t;
    l_obj   json_object_t;
  begin
    l_el := p_spec.get('items');
    if l_el is null or not l_el.is_array then
      fail('items must be an array');
    end if;
    l_items := treat(l_el as json_array_t);
    if l_items.get_size = 0 or l_items.get_size > 20 then
      fail('items must hold 1 to 20 entries');
    end if;

    <<i_loop>>
    for i in 0 .. l_items.get_size - 1 loop
      l_item := row_at(l_items, i);
      l_new := json_object_t();
      l_new.put('title', str_of(l_item, 'title', true, c_max_str));
      put_if(l_new, 'subtitle', str_of(l_item, 'subtitle', false, c_max_str));
      put_if(l_new, 'icon', enum_of(l_item, 'icon', 'file:pdf:image:sheet:text:archive:folder'));
      l_arr := clean_badges(l_item);
      if l_arr is not null then
        l_new.put('badges', l_arr);
      end if;
      l_arr := clean_meta(l_item);
      if l_arr is not null then
        l_new.put('meta', l_arr);
      end if;
      l_obj := clean_action(l_item);
      if l_obj is not null then
        l_new.put('action', l_obj);
      end if;
      l_clean.append(l_new);
    end loop i_loop;

    l_out.put('type', c_type_item_list);
    put_if(l_out, 'title', str_of(p_spec, 'title', false, 120));
    l_out.put('items', l_clean);
    return l_out;
  end clean_item_list;

  -- Runs the provider of a registered type. Whatever it returns is only input for
  -- clean_item_list; the provider cannot put a member into the part itself.
  function clean_provider(
    p_type       in varchar2,
    p_spec       in json_object_t,
    p_calls_clob in clob
  ) return json_object_t
  as
    l_pkg    uc_ai_chat_widget_types.provider_package%type;
    l_out    clob;
    l_reason varchar2(500 char);
    l_parsed json_object_t;
  begin
    l_pkg := provider_package_of(p_type);
    if l_pkg is null then
      fail('unknown widget type ' || p_type);
    end if;

    -- @dblinter ignore(G-6010): the package name comes from the registry (checked with dbms_assert when it was registered) and is asserted again here; everything else is bound
    -- @dblinter ignore(G-9501): l_pkg comes from the registry table, not from p_type (that only selects a row), and is asserted again here
    execute immediate
      'begin ' || sys.dbms_assert.qualified_sql_name(l_pkg)
      || '.build_spec(p_type => :1, p_spec => :2, p_tool_calls => :3, po_spec => :4, po_reason => :5); end;'
      using in p_type, in p_spec.to_clob(), in p_calls_clob, out l_out, out l_reason;

    if l_reason is not null then
      fail(l_reason);
    end if;

    begin
      l_parsed := json_object_t.parse(l_out);
    exception
      when others then -- @dblinter ignore(g-5040): a provider that returns no JSON object is a rejected widget, not a failed turn
        fail('the provider of ' || p_type || ' did not return a JSON object');
    end;
    return clean_item_list(l_parsed);
  end clean_provider;

  -- Validate one parsed spec and return the clean one. Raises e_invalid.
  function clean_spec(
    p_spec       in json_object_t,
    p_types      in varchar2,
    p_tool_calls in json_array_t,
    p_calls_clob in clob
  ) return json_object_t
  as
    l_type varchar2(30 char);
  begin
    l_type := lower(str_of(p_spec, 'type', true, 30));
    if not type_enabled(p_types, l_type) then
      fail('widget type ' || l_type || ' is not enabled');
    end if;

    case l_type
      when c_type_stat_card then return clean_stat_card(p_spec);
      when c_type_status    then return clean_status(p_spec);
      when c_type_key_value then return clean_key_value(p_spec);
      when c_type_table     then return clean_table(p_spec, p_tool_calls);
      when c_type_chart     then return clean_chart(p_spec, p_tool_calls);
      else
        -- not built in: only a registered type that this region enabled gets here
        return clean_provider(l_type, p_spec, p_calls_clob);
    end case;
    return null; -- unreachable: fail always raises
  end clean_spec;

  procedure add_text(
    pio_parts in out nocopy json_array_t,
    p_text  in clob,
    p_rejected in varchar2 default null
  )
  as
    l_part json_object_t;
  begin
    -- blank text between two widgets is layout, not content
    if p_text is null or (p_rejected is null and trim(p_text) is null) then
      return;
    end if;
    l_part := json_object_t();
    l_part.put('kind', 'text');
    l_part.put('text', p_text);
    if p_rejected is not null then
      l_part.put('rejected', p_rejected);
    end if;
    pio_parts.append(l_part);
  end add_text;

  function get_protocol(
    p_types in varchar2
  ) return clob
  as
    c_nl   constant varchar2(1 char) := chr(10);
    l_out  clob;
    l_t    varchar2(30 char);
    l_pkg  uc_ai_chat_widget_types.provider_package%type;
    l_line clob;
  begin
    if p_types is null then
      return null;
    end if;

    l_out := '# WIDGET PROTOCOL' || c_nl
      || 'You can show a small widget inside your answer. Write it as a fenced block with the language "'
      || c_fence || '" that holds ONE JSON object, for example:' || c_nl
      || '```' || c_fence || c_nl
      || '{"type":"stat_card","label":"Open invoices","value":42}' || c_nl
      || '```' || c_nl
      || 'Rules:' || c_nl
      || '1. Use a widget only when it shows the data better than a sentence. Put at most '
      || c_max_widgets || ' widgets in one answer. Write the explanation as normal text around them.' || c_nl
      || '2. Use only the widget types below. Do not add other keys.' || c_nl
      || '3. Never invent numbers. Show only values that you got from a tool or from the user.' || c_nl
      || '4. A widget does not replace the answer. State the key finding in text as well.' || c_nl
      || 'Widget types:' || c_nl;

    if type_enabled(p_types, c_type_stat_card) then
      l_out := l_out || '- stat_card: {"type":"stat_card","label":"...","value":"...","unit":"...","delta":"+4%","trend":"up|down|flat"} (unit, delta, trend are optional)' || c_nl;
    end if;
    if type_enabled(p_types, c_type_status) then
      l_out := l_out || '- status: {"type":"status","level":"ok|info|warn|error","title":"...","text":"..."} (text is optional)' || c_nl;
    end if;
    if type_enabled(p_types, c_type_key_value) then
      l_out := l_out || '- key_value: {"type":"key_value","title":"...","items":[{"label":"...","value":"..."}]} (1 to 20 items)' || c_nl;
    end if;
    if type_enabled(p_types, c_type_table) then
      l_out := l_out || '- table: {"type":"table","title":"...","columns":["col_a","col_b"],"source":"tool:<tool_name>"} (at most 12 columns)' || c_nl;
    end if;
    if type_enabled(p_types, c_type_chart) then
      l_out := l_out || '- chart: {"type":"chart","kind":"bar|line","title":"...","x":"col_a","y":"col_b","source":"tool:<tool_name>"} (y must be a numeric column)' || c_nl;
    end if;

    <<provider_loop>>
    for i in 1 .. regexp_count(p_types, '[^:]+') loop
      l_t := regexp_substr(p_types, '[^:]+', 1, i);
      l_pkg := case when is_builtin(l_t) then null else provider_package_of(l_t) end;
      if l_pkg is not null then
        begin
          -- @dblinter ignore(G-9501): l_pkg comes from the registry table, not from p_types (that only selects a row), and is asserted again here
          -- @dblinter ignore(G-6010): the package name cannot be bound; the value is asserted
          execute immediate
            'begin :1 := ' || sys.dbms_assert.qualified_sql_name(l_pkg) || '.get_protocol(p_type => :2); end;'
            using out l_line, in l_t;
          if l_line is not null then
            l_out := l_out || l_line || c_nl;
          end if;
        exception
          when others then -- @dblinter ignore(g-5040): a broken provider must not take the other widget types out of the prompt; its type then stays out
            apex_debug.error(
              '%s | protocol of widget type %s failed: %s - %s',
              c_scope, l_t, sqlerrm, sys.dbms_utility.format_error_backtrace);
        end;
      end if;
    end loop provider_loop;

    if type_enabled(p_types, c_type_table) or type_enabled(p_types, c_type_chart) then
      l_out := l_out || 'Data for a table or chart: when a tool in this conversation returned the rows, set "source" to '
        || '"tool:<tool_name>" and name the columns exactly as the keys of the rows (for example "lifetime_value", not "Lifetime Value"). Do NOT copy the rows into your answer; the system reads them from the tool result. '
        || 'When the same tool ran more than once in this conversation, also give "args": the arguments of the call whose result you want, '
        || 'for example "source":"tool:get_sales","args":{"year":2025}. Without "args" the system uses the latest call of that tool. '
        || 'Only tool calls made while you write this answer count; for rows from an earlier answer, give them inline. '
        || 'Only when no tool returned the data, give at most ' || c_max_points || ' rows inline as "data":[{...}].';
    end if;
    return l_out;
  end get_protocol;

  function render(
    p_answer     in clob,
    p_types      in varchar2,
    p_tool_calls in json_array_t default null
  ) return json_array_t
  as
    c_open     constant varchar2(30 char) := '```' || c_fence;
    l_parts    json_array_t := json_array_t();
    l_len      pls_integer;
    l_pos      pls_integer := 1;
    l_open     pls_integer;
    l_nl       pls_integer;
    l_close    pls_integer;
    l_body     clob;
    l_spec     json_object_t;
    l_clean    json_object_t;
    l_part     json_object_t;
    l_widgets  pls_integer := 0;
    l_reason   varchar2(500 char);
    l_calls    clob;
  begin
    l_len := coalesce(sys.dbms_lob.getlength(p_answer), 0);
    if l_len = 0 then
      return l_parts;
    end if;

    -- feature off: the answer stays one text part, fences and all
    if p_types is null then
      add_text(l_parts, p_answer);
      return l_parts;
    end if;

    -- the tool calls go to a provider as text; build that once per answer, and only when a registered type is enabled
    if has_provider_types(p_types) then
      l_calls := case when p_tool_calls is null then to_clob('[]') else p_tool_calls.to_clob() end;
    end if;

    <<scan>>
    while l_pos <= l_len loop
      l_open := sys.dbms_lob.instr(p_answer, c_open, l_pos);
      l_nl := case when l_open > 0
                then sys.dbms_lob.instr(p_answer, chr(10), l_open + length(c_open))
                else 0 end;
      l_close := case when l_nl > 0
                  then sys.dbms_lob.instr(p_answer, '```', l_nl + 1)
                  else 0 end;

      -- no fence, or a fence that never closes (a cut-off answer): the rest is text
      if l_open = 0 or l_nl = 0 or l_close = 0 then
        add_text(l_parts, slice(p_answer, l_pos, l_len));
        exit scan;
      end if;

      add_text(l_parts, slice(p_answer, l_pos, l_open - 1));
      l_body := slice(p_answer, l_nl + 1, l_close - 1);
      l_reason := null;
      l_clean := null;

      begin
        if l_widgets >= c_max_widgets then
          fail('more than ' || c_max_widgets || ' widgets in one answer');
        end if;
        if sys.dbms_lob.getlength(l_body) > c_max_body then
          fail('the widget is too large');
        end if;
        begin
          l_spec := json_object_t.parse(l_body);
        exception
          when others then -- @dblinter ignore(g-5040): any parse failure only means invalid JSON; the reason goes back as text
            fail('the widget is not valid JSON');
        end;
        l_clean := clean_spec(l_spec, p_types, p_tool_calls, l_calls);
      exception
        when e_invalid then
          -- @dblinter ignore(g-5080): a rejected widget is an expected outcome, the message is the reason and a backtrace adds nothing
          -- ORA-20900: <reason>
          l_reason := substr(sqlerrm, instr(sqlerrm, ':') + 2, 500);
        when others then -- @dblinter ignore(g-5040): a bad widget must never fail the turn; it is logged and shown as text
          apex_debug.error(
            '%s | widget could not be processed: %s %s',
            c_scope, sqlerrm, sys.dbms_utility.format_error_backtrace);
          l_reason := 'the widget could not be processed';
      end;

      if l_clean is not null then
        l_widgets := l_widgets + 1;
        l_part := json_object_t();
        l_part.put('kind', 'widget');
        l_part.put('type', l_clean.get_string('type'));
        l_part.put('spec', l_clean);
        l_parts.append(l_part);
      else
        -- keep the block as visible text so nothing the model said is lost
        add_text(l_parts, slice(p_answer, l_open, l_close + 2), l_reason);
      end if;

      l_pos := l_close + 3;
    end loop scan;

    return l_parts;
  end render;

  -- Writes a stored JSON object/array to apex_json member by member, so the
  -- output is valid JSON by construction (no raw string splicing).
  procedure write_json_array(
    p_name in varchar2,
    p_arr  in json_array_t
  );

  procedure write_json_object(
    p_name in varchar2,
    p_obj  in json_object_t
  )
  is
    l_keys json_key_list := p_obj.get_keys;
    l_el   json_element_t;
  begin
    apex_json.open_object(p_name);
    <<key_loop>>
    for i in 1 .. l_keys.count loop
      l_el := p_obj.get(l_keys(i));
      if l_el.is_object then
        write_json_object(l_keys(i), treat(l_el as json_object_t));
      elsif l_el.is_array then
        write_json_array(l_keys(i), treat(l_el as json_array_t));
      elsif l_el.is_string then
        apex_json.write(l_keys(i), p_obj.get_string(l_keys(i)));
      elsif l_el.is_number then
        apex_json.write(l_keys(i), p_obj.get_number(l_keys(i)));
      elsif l_el.is_boolean then
        apex_json.write(l_keys(i), p_obj.get_boolean(l_keys(i)));
      else
        apex_json.write(l_keys(i), cast(null as varchar2));
      end if;
    end loop key_loop;
    apex_json.close_object;
  end write_json_object;

  procedure write_json_array(
    p_name in varchar2,
    p_arr  in json_array_t
  )
  is
    l_el json_element_t;
  begin
    apex_json.open_array(p_name);
    <<item_loop>>
    for i in 0 .. p_arr.get_size - 1 loop
      l_el := p_arr.get(i);
      if l_el.is_object then
        write_json_object(null, treat(l_el as json_object_t));
      elsif l_el.is_array then
        write_json_array(null, treat(l_el as json_array_t));
      elsif l_el.is_string then
        apex_json.write(p_arr.get_string(i));
      elsif l_el.is_number then
        apex_json.write(p_arr.get_number(i));
      elsif l_el.is_boolean then
        apex_json.write(p_arr.get_boolean(i));
      else
        apex_json.write(cast(null as varchar2));
      end if;
    end loop item_loop;
    apex_json.close_array;
  end write_json_array;

  -- Emits the 'parts' member of an assistant message from its stored snapshot:
  -- {kind:"text",text,rejected?} or {kind:"widget",type,spec}. The reason a
  -- widget was rejected is shown only when the show_errors debug flag is on.
  -- A snapshot that does not parse is skipped: the content member still holds
  -- the whole answer.
  procedure write_parts(
    p_parts       in clob,
    p_show_rejected in boolean
  )
  is
    l_parts json_array_t;
    l_part  json_object_t;
    l_kind  varchar2(20 char);
  begin
    -- parse first: nothing is written to the response unless the snapshot is sound
    begin
      l_parts := json_array_t.parse(p_parts);
    exception
      when others then -- @dblinter ignore(G-5040): a broken snapshot must not break the fetch; content still holds the whole answer
        apex_debug.error(
          '%s | stored widget parts could not be parsed: %s - %s',
          c_scope_emit, sqlerrm, sys.dbms_utility.format_error_backtrace
        );
        return;
    end;

    apex_json.open_array('parts');
    <<part_loop>>
    for i in 0 .. l_parts.get_size - 1 loop
      l_part := treat(l_parts.get(i) as json_object_t);
      l_kind := l_part.get_string('kind');
      apex_json.open_object;
      apex_json.write('kind', l_kind);
      if l_kind = 'widget' then
        apex_json.write('type', l_part.get_string('type'));
        write_json_object('spec', treat(l_part.get('spec') as json_object_t));
      else
        apex_json.write('text', l_part.get_clob('text'));
        if p_show_rejected and l_part.has('rejected') then
          apex_json.write('rejected', l_part.get_string('rejected'));
        end if;
      end if;
      apex_json.close_object;
    end loop part_loop;
    apex_json.close_array;
  end write_parts;

end uc_ai_chat_widgets;
/
