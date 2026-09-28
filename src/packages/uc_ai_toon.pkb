create or replace package body uc_ai_toon as

  /**
   * TOON specification compliance: 4.1 (2026-07-26), encoding direction
   * with the default comma delimiter. Verified against the reference
   * implementation @toon-format/toon 4.1.1. No decode direction.
   */

  c_indent constant varchar2(2 char) := '  '; -- 2 spaces for indentation

  /**
   * Record type for one node of a uniform field tree (TOON spec 4.x, 9.3/9.5).
   * Nodes are stored depth-first in a flat list; a branch's subtree occupies
   * the indexes after it (terminated by the first node at or above its depth).
   */
  type r_field_def_type is record (
    field_name varchar2(32767 char),
    is_leaf boolean,
    depth pls_integer,
    path apex_t_varchar2
  );
  type t_field_defs is table of r_field_def_type index by pls_integer;

  /**
   * Working list of JSON objects for uniform-column analysis
   */
  type t_object_list is table of json_object_t index by pls_integer;

  /**
   * Check if a string should remain quoted according to TOON rules
   * (TOON spec 4.x, section 7.2)
   */
  function needs_quotes(p_value in varchar2) return boolean is
  begin
    if p_value is null or trim(p_value) is null then
      return true; -- null doesn't need quotes
    end if;

    -- Empty string must be quoted
    if length(p_value) = 0 then
      return true;
    end if;

    -- Has leading or trailing whitespace
    if p_value != trim(p_value) then
      return true;
    end if;

    -- Equals true, false, or null (case-sensitive)
    if p_value in ('true', 'false', 'null') then
      return true;
    end if;

    -- Equals "-" or starts with hyphen (list-item marker)
    if p_value = '-' or substr(p_value, 1, 1) = '-' then
      return true;
    end if;

    -- Equals "#" or starts with "#" (comment lines are stripped on decode)
    if p_value = '#' or substr(p_value, 1, 1) = '#' then
      return true;
    end if;

    -- Numeric-like (spec 7.2): /^[+-]?[0-9]+(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?$/i
    if regexp_like(p_value, '^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$') then
      return true;
    end if;

    -- Contains special characters that require quoting
    if instr(p_value, ':') > 0 or
       instr(p_value, ',') > 0 or
       instr(p_value, '"') > 0 or
       instr(p_value, '\') > 0 or
       instr(p_value, '[') > 0 or
       instr(p_value, ']') > 0 or
       instr(p_value, '{') > 0 or
       instr(p_value, '}') > 0 then
      return true;
    end if;

    -- Contains control characters (newline, carriage return, tab)
    if instr(p_value, chr(10)) > 0 or
       instr(p_value, chr(13)) > 0 or
       instr(p_value, chr(9)) > 0 then
      return true;
    end if;

    -- String is safe to remain unquoted
    return false;
  end needs_quotes;

  /**
   * Escape special characters in a string value
   */
  function remove_quotes_when_needed(p_value in varchar2) return varchar2
  as
    l_str varchar2(32767 char) := p_value;
  begin
    if p_value is null then
      return 'null';
    end if;

    -- JSON to_string returns quoted string, so strip the outer quotes
    if substr(l_str, 1, 1) = '"' and substr(l_str, -1) = '"' then
      l_str := substr(l_str, 2, length(l_str) - 2);
    end if;

    -- TOON allows only \\ \" \n \r \t \uXXXX (spec 7.1): translate the
    -- JSON-only escapes \b \f \/. Escaped backslashes are protected first
    -- so that a literal backslash followed by "b"/"f"/"/" is not mistaken
    -- for an escape (a raw chr(1) never occurs here: to_string emits it
    -- as \u0001, so it is a safe placeholder).
    l_str := replace(l_str, '\\', chr(1));
    l_str := replace(l_str, '\b', '\u0008');
    l_str := replace(l_str, '\f', '\u000c');
    l_str := replace(l_str, '\/', '/');
    l_str := replace(l_str, chr(1), '\\');

    -- Keep quotes if the string needs them according to TOON rules
    if needs_quotes(l_str) then
      return '"' || l_str || '"';
    end if;

    -- Return unquoted string for simple values
    return l_str;
  end remove_quotes_when_needed;

  /**
   * Escape a string for quoted TOON output (TOON spec 4.x, section 7.1)
   */
  function escape_toon_string(p_value in varchar2) return varchar2
  as
    l_result varchar2(32767 char) := p_value;
    l_char varchar2(1 char);
    c_max_c0_control constant pls_integer := 31; -- U+0000..U+001F
  begin
    if p_value is null then
      return null;
    end if;

    l_result := replace(l_result, '\', '\\');
    l_result := replace(l_result, '"', '\"');
    l_result := replace(l_result, chr(10), '\n');
    l_result := replace(l_result, chr(13), '\r');
    l_result := replace(l_result, chr(9), '\t');

    -- Remaining C0 controls use lowercase \uXXXX
    <<escape_controls_loop>>
    for i in 0 .. c_max_c0_control loop
      l_char := chr(i);
      if l_char is not null
         and l_char not in (chr(9), chr(10), chr(13))
         and instr(l_result, l_char) > 0 then
        l_result := replace(l_result, l_char, '\u' || lpad(trim(to_char(i, 'xx')), 4, '0'));
      end if;
    end loop escape_controls_loop;

    return l_result;
  end escape_toon_string;

  /**
   * Encode an object key or header field name (TOON spec 4.x, section 7.3).
   * Unquoted only for ^[A-Za-z_][A-Za-z0-9_.]*$, quoted otherwise.
   */
  function encode_key(p_key in varchar2) return varchar2 is
  begin
    if p_key is null then
      return '""';
    end if;

    if regexp_like(p_key, '^[A-Za-z_][A-Za-z0-9_.]*$') then
      return p_key;
    end if;

    return '"' || escape_toon_string(p_key) || '"';
  end encode_key;

  /**
   * Convert a JSON element to its TOON string representation
   */
  function element_to_toon_value(p_element in json_element_t) return varchar2 is
    l_str varchar2(32767 char);
  begin
    if p_element.is_null then
      return 'null';
    elsif p_element.is_boolean then
      return case when p_element.to_boolean then 'true' else 'false' end;
    elsif p_element.is_number then
      return p_element.to_string;
    elsif p_element.is_string then
      -- Get the string value from JSON element
      l_str := p_element.to_string;
      
      return remove_quotes_when_needed(l_str);
    end if;

    return null; -- Will be handled as nested object/array
  end element_to_toon_value;

  /**
   * Check if array contains only primitive values (not objects/arrays)
   */
  function is_primitive_array(p_array in json_array_t) return boolean is
    l_element json_element_t;
  begin
    <<check_primitive_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      l_element := p_array.get(i);
      if l_element.is_object or l_element.is_array then
        return false;
      end if;
    end loop check_primitive_loop;
    return true;
  end is_primitive_array;

  /**
   * Recursively build uniform field definitions for the given objects.
   *
   * A column is uniform-primitive when every value is a primitive, or
   * nested-uniform when every value is a non-empty object whose sub-columns
   * are themselves uniform (TOON spec 4.x, section 9.3). Returns an empty
   * list when the objects do not form uniform columns (different key sets,
   * mixed or array values, empty objects). A valid result is never empty:
   * every analyzed object carries at least one key.
   */
  function build_uniform_fields(
    p_objects in t_object_list,
    p_depth in pls_integer,
    p_path_prefix in apex_t_varchar2
  ) return t_field_defs is
    l_result_arr t_field_defs;
    l_child_arr t_field_defs;
    l_first json_object_t;
    l_keys_arr json_key_list;
    l_key varchar2(32767 char);
    l_element json_element_t;
    l_nested_obj json_object_t;
    l_nested_arr t_object_list;
    l_all_primitive boolean;
    l_all_objects boolean;
    l_def r_field_def_type;
    l_path apex_t_varchar2;
    c_first_compared_idx constant pls_integer := 2; -- compares all but the first object
  begin
    l_first := p_objects(1);
    l_keys_arr := l_first.get_keys;

    -- All objects must carry the same key set (order may vary)
    <<check_size_loop>>
    for i in 1 .. p_objects.count loop
      if p_objects(i).get_size != l_first.get_size then
        l_result_arr.delete;
        return l_result_arr;
      end if;
    end loop check_size_loop;

    <<columns_loop>>
    for k in 1 .. l_keys_arr.count loop
      l_key := l_keys_arr(k);

      <<check_key_loop>>
      for i in c_first_compared_idx .. p_objects.count loop
        if not p_objects(i).has(l_key) then
          l_result_arr.delete;
          return l_result_arr;
        end if;
      end loop check_key_loop;

      l_all_primitive := true;
      l_all_objects := true;
      l_nested_arr.delete;

      <<classify_loop>>
      for i in 1 .. p_objects.count loop
        l_element := p_objects(i).get(l_key);
        if l_element is null then
          l_result_arr.delete;
          return l_result_arr;
        elsif l_element.is_array then
          -- Arrays never form uniform columns
          l_result_arr.delete;
          return l_result_arr;
        elsif l_element.is_object then
          l_all_primitive := false;
          l_nested_obj := treat(l_element as json_object_t);
          if l_nested_obj.get_size = 0 then
            l_result_arr.delete;
            return l_result_arr;
          end if;
          l_nested_arr(l_nested_arr.count + 1) := l_nested_obj;
        else
          -- Primitive value (string, number, boolean, null)
          l_all_objects := false;
        end if;
      end loop classify_loop;

      l_path := p_path_prefix;
      l_path.extend;
      l_path(l_path.count) := l_key;

      if l_all_objects and not l_all_primitive then
        -- Nested-uniform column: branch node, then recurse for children
        l_child_arr := build_uniform_fields(
          p_objects => l_nested_arr,
          p_depth => p_depth + 1,
          p_path_prefix => l_path
        );
        if l_child_arr.count = 0 then
          l_result_arr.delete;
          return l_result_arr;
        end if;

        l_def.field_name := l_key;
        l_def.is_leaf := false;
        l_def.depth := p_depth;
        l_def.path := l_path;
        l_result_arr(l_result_arr.count + 1) := l_def;

        <<append_children_loop>>
        for c in 1 .. l_child_arr.count loop
          l_result_arr(l_result_arr.count + 1) := l_child_arr(c);
        end loop append_children_loop;
      elsif l_all_primitive and not l_all_objects then
        -- Uniform-primitive column: leaf node
        l_def.field_name := l_key;
        l_def.is_leaf := true;
        l_def.depth := p_depth;
        l_def.path := l_path;
        l_result_arr(l_result_arr.count + 1) := l_def;
      else
        -- Mixed primitives and objects in one column
        l_result_arr.delete;
        return l_result_arr;
      end if;
    end loop columns_loop;

    return l_result_arr;
  end build_uniform_fields;

  /**
   * Analyze an array for tabular form (TOON spec 4.x, section 9.3).
   * Returns the field tree, or an empty list when the array is not tabular.
   */
  function analyze_tabular_array(
    p_array in json_array_t
  ) return t_field_defs is
    l_field_arr t_field_defs;
    l_object_arr t_object_list;
    l_element json_element_t;
    l_obj json_object_t;
  begin
    if p_array.get_size = 0 then
      return l_field_arr;
    end if;

    <<collect_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      l_element := p_array.get(i);
      if l_element is null or not l_element.is_object then
        return l_field_arr;
      end if;
      l_obj := treat(l_element as json_object_t);
      if l_obj.get_size = 0 then
        return l_field_arr;
      end if;
      l_object_arr(i + 1) := l_obj;
    end loop collect_loop;

    return build_uniform_fields(
      p_objects => l_object_arr,
      p_depth => 0,
      p_path_prefix => apex_t_varchar2()
    );
  end analyze_tabular_array;

  /**
   * Analyze an object for keyed tabular form (TOON spec 4.x, section 9.5).
   * Returns the shared field tree of the entry values, or an empty list
   * when the object does not qualify (fewer than 2 entries, or values that
   * are not uniform non-empty objects).
   */
  function analyze_keyed_object(
    p_object in json_object_t
  ) return t_field_defs is
    l_field_arr t_field_defs;
    l_object_arr t_object_list;
    l_keys_arr json_key_list;
    l_element json_element_t;
    l_obj json_object_t;
    c_min_keyed_entries constant pls_integer := 2;
  begin
    l_keys_arr := p_object.get_keys;

    if l_keys_arr.count < c_min_keyed_entries then
      return l_field_arr;
    end if;

    <<collect_loop>>
    for i in 1 .. l_keys_arr.count loop
      l_element := p_object.get(l_keys_arr(i));
      if l_element is null or not l_element.is_object then
        return l_field_arr;
      end if;
      l_obj := treat(l_element as json_object_t);
      if l_obj.get_size = 0 then
        return l_field_arr;
      end if;
      l_object_arr(i) := l_obj;
    end loop collect_loop;

    return build_uniform_fields(
      p_objects => l_object_arr,
      p_depth => 0,
      p_path_prefix => apex_t_varchar2()
    );
  end analyze_keyed_object;

  /**
   * Render the inner part of a tabular/keyed header, e.g. "id,customer{name,country}"
   */
  function build_header_inner(
    p_fields in t_field_defs,
    p_parent_idx in pls_integer,
    p_child_depth in pls_integer
  ) return varchar2 is
    l_result varchar2(32767 char);
    l_first boolean := true;
    l_start_idx pls_integer;
    l_parent_depth pls_integer;
  begin
    if p_parent_idx = 0 then
      l_start_idx := 1;
      l_parent_depth := -1;
    else
      l_start_idx := p_parent_idx + 1;
      l_parent_depth := p_fields(p_parent_idx).depth;
    end if;

    <<header_fields_loop>>
    for i in l_start_idx .. p_fields.count loop
      if p_parent_idx > 0 and p_fields(i).depth <= l_parent_depth then
        exit;
      end if;

      if p_fields(i).depth = p_child_depth then
        if not l_first then
          l_result := l_result || ',';
        end if;
        l_first := false;

        l_result := l_result || encode_key(p_fields(i).field_name);
        if not p_fields(i).is_leaf then
          l_result := l_result || '{'
            || build_header_inner(p_fields, i, p_child_depth + 1) || '}';
        end if;
      end if;
    end loop header_fields_loop;

    return l_result;
  end build_header_inner;

  /**
   * Render one tabular/entry row: leaf values in depth-first header order
   */
  function render_row_cells(
    p_object in json_object_t,
    p_fields in t_field_defs
  ) return varchar2 is
    l_result varchar2(32767 char);
    l_first boolean := true;
    l_current json_object_t;
    l_element json_element_t;
    l_value varchar2(32767 char);
  begin
    <<leaf_loop>>
    for i in 1 .. p_fields.count loop
      if p_fields(i).is_leaf then
        if not l_first then
          l_result := l_result || ',';
        end if;
        l_first := false;

        l_current := p_object;
        <<path_loop>>
        for p in 1 .. p_fields(i).path.count loop
          if p < p_fields(i).path.count then
            l_current := treat(l_current.get(p_fields(i).path(p)) as json_object_t);
          else
            l_element := l_current.get(p_fields(i).path(p));
          end if;
        end loop path_loop;

        l_value := element_to_toon_value(l_element);
        l_result := l_result || l_value;
      end if;
    end loop leaf_loop;

    return l_result;
  end render_row_cells;

 /**
   * Process a primitive array in compact format: [length]: val1,val2,val3
   */
  function process_primitive_array(p_array in json_array_t) return varchar2 is
    l_result varchar2(32767 char);
    l_element json_element_t;
  begin
    l_result := '[' || p_array.get_size || ']: ';
    
    <<primitive_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      if i > 0 then
        l_result := l_result || ',';
      end if;
      l_element := p_array.get(i);
      l_result := l_result || element_to_toon_value(l_element);
      -- dbms_output.put_line('Primitive array element ' || i || ': ' || l_result);
    end loop primitive_loop;

    return l_result;
  end process_primitive_array;

  /**
   * Process homogeneous object array in columnar format:
   * [count]{field1,field2{nested}}: with one row per element
   */
  function process_homogeneous_array(
    p_array in json_array_t,
    p_fields in t_field_defs,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_obj json_object_t;
    l_row varchar2(32767 char);
  begin
    sys.dbms_lob.createtemporary(l_result, true);
    -- Data rows should always be indented at least one level
    l_indent := rpad(' ', (p_indent_level + 1) * length(c_indent), c_indent);

    -- Write header: [count]{field1,field2{nested}}:
    sys.dbms_lob.writeappend(l_result,
      length('[' || p_array.get_size || ']{'
        || build_header_inner(p_fields, 0, 0) || '}:' || chr(10)),
      '[' || p_array.get_size || ']{'
        || build_header_inner(p_fields, 0, 0) || '}:' || chr(10));

    -- Write data rows
    <<data_rows_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      sys.dbms_lob.writeappend(l_result, length(l_indent), l_indent);
      l_obj := treat(p_array.get(i) as json_object_t);
      l_row := render_row_cells(l_obj, p_fields);

      if length(l_row) > 0 then
        sys.dbms_lob.writeappend(l_result, lengthb(l_row), l_row);
      end if;

      if i < p_array.get_size - 1 then
        sys.dbms_lob.writeappend(l_result, 1, chr(10));
      end if;
    end loop data_rows_loop;

    return l_result;
  end process_homogeneous_array;

  /**
   * Render the entry rows of a keyed tabular block (no header line).
   * Each row is "entrykey: cell,cell,..." at one indent below the header.
   */
  function render_keyed_entries(
    p_object in json_object_t,
    p_fields in t_field_defs,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_keys_arr json_key_list;
    l_obj json_object_t;
    l_row varchar2(32767 char);
  begin
    sys.dbms_lob.createtemporary(l_result, true);
    l_indent := rpad(' ', (p_indent_level + 1) * length(c_indent), c_indent);
    l_keys_arr := p_object.get_keys;

    <<entry_rows_loop>>
    for i in 1 .. l_keys_arr.count loop
      sys.dbms_lob.writeappend(l_result, length(l_indent), l_indent);
      sys.dbms_lob.writeappend(l_result,
        lengthb(encode_key(l_keys_arr(i)) || ': '),
        encode_key(l_keys_arr(i)) || ': ');
      l_obj := treat(p_object.get(l_keys_arr(i)) as json_object_t);
      l_row := render_row_cells(l_obj, p_fields);

      if length(l_row) > 0 then
        sys.dbms_lob.writeappend(l_result, lengthb(l_row), l_row);
      end if;

      if i < l_keys_arr.count then
        sys.dbms_lob.writeappend(l_result, 1, chr(10));
      end if;
    end loop entry_rows_loop;

    return l_result;
  end render_keyed_entries;

  /* Forward declaration of process_array 
   * as process_object and process_array both call each other
  */
  function process_array(
    p_array in json_array_t,
    p_indent_level in number
  ) return clob;

  /**
   * Process an object
   */
  function process_object(
    p_object in json_object_t,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_keys_arr json_key_list;
    l_key varchar2(32767 char);
    l_element json_element_t;
    l_obj json_object_t;
    l_arr json_array_t;
    l_value varchar2(32767 char);
    l_nested clob;
    l_keyed_field_arr t_field_defs;
    l_tmp_keys json_key_list;
    l_entry_count pls_integer;
    l_first boolean := true;
  begin
    sys.dbms_lob.createtemporary(l_result, true);
    l_indent := rpad(' ', p_indent_level * length(c_indent), c_indent);
    l_keys_arr := p_object.get_keys;

    <<object_keys_loop>>
    for i in 1 .. l_keys_arr.count loop
      if not l_first then
        sys.dbms_lob.writeappend(l_result, 1, chr(10));
      end if;
      l_first := false;

      l_key := l_keys_arr(i);
      l_element := p_object.get(l_key);

      if l_element.is_object then
        l_obj := treat(l_element as json_object_t);
        -- Keyed tabular form for uniform entry values (spec 9.5)
        l_keyed_field_arr := analyze_keyed_object(l_obj);
        if l_keyed_field_arr.count > 0 then
          l_tmp_keys := l_obj.get_keys;
          l_entry_count := l_tmp_keys.count;
          sys.dbms_lob.writeappend(l_result,
            length(l_indent || encode_key(l_key) || '['
              || l_entry_count || ':]{'
              || build_header_inner(l_keyed_field_arr, 0, 0) || '}:' || chr(10)),
            l_indent || encode_key(l_key) || '['
              || l_entry_count || ':]{'
              || build_header_inner(l_keyed_field_arr, 0, 0) || '}:' || chr(10));
          l_nested := render_keyed_entries(l_obj, l_keyed_field_arr, p_indent_level);
          sys.dbms_lob.append(l_result, l_nested);
        else
          l_nested := process_object(l_obj, p_indent_level + 1);
          sys.dbms_lob.writeappend(l_result,
            length(l_indent || encode_key(l_key) || ':'),
            l_indent || encode_key(l_key) || ':');
          -- Only add newline if object is not empty
          if l_nested is not null and length(l_nested) > 0 then
            sys.dbms_lob.writeappend(l_result, 1, chr(10));
            sys.dbms_lob.append(l_result, l_nested);
          end if;
        end if;
      elsif l_element.is_array then
        l_arr := treat(l_element as json_array_t);
        if l_arr.get_size = 0 then
          -- Empty arrays use the explicit [] form (spec 9.1)
          sys.dbms_lob.writeappend(l_result,
            length(l_indent || encode_key(l_key) || ': []'),
            l_indent || encode_key(l_key) || ': []');
        else
          sys.dbms_lob.writeappend(l_result,
            length(l_indent || encode_key(l_key)),
            l_indent || encode_key(l_key));
          l_nested := process_array(l_arr, p_indent_level);
          sys.dbms_lob.append(l_result, l_nested);
        end if;
      else
        sys.dbms_lob.writeappend(l_result,
          length(l_indent || encode_key(l_key) || ': '),
          l_indent || encode_key(l_key) || ': ');
        l_value := element_to_toon_value(l_element);
        -- sys.dbms_output.put_line('Processing key "' || l_key || '" with value: ' || l_value);
        sys.dbms_lob.writeappend(l_result, lengthb(l_value), l_value);
      end if;
    end loop object_keys_loop;

    return l_result;
  end process_object;

  /**
   * Process an array
   */
  function process_array(
    p_array in json_array_t,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_indent_next_line varchar2(200 char);
    l_element json_element_t;
    l_obj json_object_t;
    l_arr json_array_t;
    l_tabular_field_arr t_field_defs;
    l_nested clob;
    l_parts apex_t_varchar2;
    l_part varchar2(32767 char);
  begin
    sys.dbms_lob.createtemporary(l_result, true);
    l_indent := rpad(' ', p_indent_level * length(c_indent), c_indent);

    -- Empty array
    if p_array.get_size = 0 then
      sys.dbms_lob.writeappend(l_result, 4, '[0]:');
      return l_result;
    end if;

    -- Primitive array (compact format)
    if is_primitive_array(p_array) then
      -- dbms_output.put_line('is_primitive_array: yes');
      l_nested := process_primitive_array(p_array);
      sys.dbms_lob.append(l_result, l_nested);
      return l_result;
    end if;

    -- Homogeneous object array (columnar format, incl. nested field groups)
    l_tabular_field_arr := analyze_tabular_array(p_array);
    if l_tabular_field_arr.count > 0 then
      -- dbms_output.put_line('is_tabular_array: yes');
      return process_homogeneous_array(p_array, l_tabular_field_arr, p_indent_level);
    end if;

    -- Irregular array (each element on its own line with dash)
    sys.dbms_lob.writeappend(l_result, length('[' || p_array.get_size || ']:' || chr(10)), '[' || p_array.get_size || ']:' || chr(10));
    
    -- dbms_output.put_line('Processing irregular array of size ' || p_array.get_size);
    <<irregular_array_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      l_element := p_array.get(i);
      l_indent := rpad(' ', (p_indent_level + 1) * length(c_indent), c_indent);

      if l_element.is_object then
        l_obj := treat(l_element as json_object_t);

        if l_obj.get_size = 0 then
          -- Empty object list items use a bare dash (spec 10)
          sys.dbms_lob.writeappend(l_result, length(l_indent || '-'), l_indent || '-');
        else
          sys.dbms_lob.writeappend(l_result, length(l_indent || '- '), l_indent || '- ');
          l_nested := process_object(l_obj, p_indent_level + 1);
          l_parts := apex_string.split(l_nested, chr(10));

          <<nested_object_parts>>
          for j in 1 .. l_parts.count loop
            -- Remove the leading indent from all parts since process_object added it
            l_part := l_parts(j);
            -- Strip the leading indent if it exists
            if length(l_part) > (p_indent_level + 1) * length(c_indent) then
              l_part := substr(l_part, (p_indent_level + 1) * length(c_indent) + 1);
            end if;

            -- every next part gets its own line without dash
            if j > 1 then
              sys.dbms_lob.writeappend(l_result, 1, chr(10));
              -- indent to align with the first property (after the "- " prefix)
              l_indent_next_line := l_indent || c_indent;
              sys.dbms_lob.writeappend(l_result, length(l_indent_next_line), l_indent_next_line);
              sys.dbms_lob.writeappend(l_result, length(l_part), l_part);
            else
              sys.dbms_lob.writeappend(l_result, length(l_part), l_part);
            end if;
          end loop nested_object_parts;
        end if;

        -- Remove the first line's indent since we already have "- " prefix
        -- Replace first occurrence of indent only
        --if l_nested is not null and length(l_nested) > 0 then
        --  l_nested := substr(l_nested, (p_indent_level + 1) * length(c_indent) + 1);
        --end if;
        --sys.dbms_lob.append(l_result, l_nested);
      elsif l_element.is_array then
        l_arr := treat(l_element as json_array_t);
        l_nested := process_array(l_arr, p_indent_level + 1);
        sys.dbms_lob.append(l_result, l_nested);
      else
        sys.dbms_lob.writeappend(l_result, length(element_to_toon_value(l_element)), element_to_toon_value(l_element));
      end if;

      if i < p_array.get_size - 1 then
        sys.dbms_lob.writeappend(l_result, 1, chr(10));
      end if;
    end loop irregular_array_loop;

    return l_result;
  end process_array;

  /**
   * Convert a JSON_OBJECT_T to TOON format
   */
  function to_toon(p_json_object in json_object_t) return clob is
    l_result clob;
    l_keyed_field_arr t_field_defs;
    l_tmp_keys json_key_list;
    l_entry_count pls_integer;
  begin
    if p_json_object is null then
      return null;
    end if;
    -- Keyed tabular form at the document root (keyless header, spec 9.5)
    l_keyed_field_arr := analyze_keyed_object(p_json_object);
    if l_keyed_field_arr.count > 0 then
      l_tmp_keys := p_json_object.get_keys;
      l_entry_count := l_tmp_keys.count;
      sys.dbms_lob.createtemporary(l_result, true);
      sys.dbms_lob.writeappend(l_result,
        length('[' || l_entry_count || ':]{'
          || build_header_inner(l_keyed_field_arr, 0, 0) || '}:' || chr(10)),
        '[' || l_entry_count || ':]{'
          || build_header_inner(l_keyed_field_arr, 0, 0) || '}:' || chr(10));
      sys.dbms_lob.append(l_result,
        render_keyed_entries(p_json_object, l_keyed_field_arr, 0));
      return l_result;
    end if;
    l_result := process_object(p_json_object, 0);
    -- Remove trailing newlines
    -- <<trim_newlines>>
    -- while length(l_result) > 0 and substr(l_result, -1) = chr(10) loop
    --   l_result := substr(l_result, 1, length(l_result) - 1);
    -- end loop trim_newlines;
    return l_result;
  end to_toon;

  /**
   * Convert a JSON_ARRAY_T to TOON format
   */
  function to_toon(p_json_array in json_array_t) return clob is
    l_result clob;
  begin
    if p_json_array is null then
      return null;
    end if;
    -- Empty arrays use the explicit [] form (spec 9.1)
    if p_json_array.get_size = 0 then
      return '[]';
    end if;
    l_result := process_array(p_json_array, 0);
    -- Remove trailing newlines
    --<<trim_newlines>>
    --while length(l_result) > 0 and substr(l_result, -1) = chr(10) loop
    --  l_result := substr(l_result, 1, length(l_result) - 1);
    --end loop trim_newlines;
    return l_result;
  end to_toon;

  /**
   * Convert a JSON string to TOON format
   */
  function to_toon(p_json_string in clob) return clob is
    l_trimmed varchar2(32767 char);
    l_first_char varchar2(1 char);
  begin
    if p_json_string is null then
      return null;
    end if;

    l_trimmed := trim(both ' ' || chr(9) || chr(10) || chr(13) || chr(12) || chr(8)
      from substr(p_json_string, 1, 32767));
    l_first_char := substr(l_trimmed, 1, 1);

    case l_first_char
      when '{' then
        return to_toon(json_object_t.parse(p_json_string));
      when '[' then
        return to_toon(json_array_t.parse(p_json_string));
      else
        -- Scalar value: wrap into an array to obtain a json_element_t, as
        -- json_element_t.parse does not accept scalars in this database version
        return element_to_toon_value(
          json_array_t.parse('[' || p_json_string || ']').get(0));
    end case;
  end to_toon;

end uc_ai_toon;
/
