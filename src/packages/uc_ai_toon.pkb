create or replace package body uc_ai_toon as

  c_indent constant varchar2(2 char) := '  '; -- 2 spaces for indentation

  /**
   * Record type to hold homogeneous array check results
   */
  type r_homogeneous_check_type is record (
    is_homogeneous boolean,
    keys_arr json_key_list
  );

  /**
   * Check if a string should remain quoted according to TOON rules
   */
  function needs_quotes(p_value in varchar2) return boolean is
  begin
    if p_value is null then
      return false; -- null doesn't need quotes
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

    -- Starts with hyphen or equals "-"
    if substr(p_value, 1, 1) = '-' then
      return true;
    end if;

    -- Numeric-like: matches /^-?\d+(?:.\d+)?(?:e[+-]?\d+)?$/i or /^0\d+$/
    if regexp_like(p_value, '^\d+$') or
       regexp_like(p_value, '^\d+\.\d+$') or
       regexp_like(p_value, '^\d+(?:\.\d+)?[eE][+-]?\d+$') or
       regexp_like(p_value, '^0\d+$') then
      return true;
    end if;

    -- Contains special characters that require quoting
    if instr(p_value, ':') > 0 or
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

    -- Keep quotes if the string needs them according to TOON rules
    if needs_quotes(l_str) then
      return '"' || l_str || '"';
    end if;

    -- Return unquoted string for simple values
    return l_str;
  end remove_quotes_when_needed;

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
   * Check if array contains homogeneous objects (same keys)
   */
  function is_homogeneous_object_array(
    p_array in json_array_t
  ) return r_homogeneous_check_type is
    l_element json_element_t;
    l_obj json_object_t;
    l_first_keys_arr json_key_list;
    l_current_keys_arr json_key_list;
    l_key_count number;
    l_result r_homogeneous_check_type;
  begin
    l_result.is_homogeneous := false;

    if p_array.get_size = 0 then
      return l_result;
    end if;

    -- Check if all elements are objects
    <<check_objects_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      l_element := p_array.get(i);
      if not l_element.is_object then
        return l_result;
      end if;
    end loop check_objects_loop;

    -- Get keys from first object
    l_obj := treat(p_array.get(0) as json_object_t);
    l_current_keys_arr := l_obj.get_keys;
    l_key_count := l_current_keys_arr.count;
    l_first_keys_arr := l_current_keys_arr;

    -- Check all other objects have same keys
    <<check_keys_loop>>
    for i in 1 .. p_array.get_size - 1 loop
      l_obj := treat(p_array.get(i) as json_object_t);
      l_current_keys_arr := l_obj.get_keys;
      
      if l_current_keys_arr.count != l_key_count then
        return l_result;
      end if;

      <<compare_keys_loop>>
      for j in 1 .. l_current_keys_arr.count loop
        if l_current_keys_arr(j) != l_first_keys_arr(j) then
          return l_result;
        end if;
      end loop compare_keys_loop;
    end loop check_keys_loop;

    l_result.is_homogeneous := true;
    l_result.keys_arr := l_first_keys_arr;
    return l_result;
  end is_homogeneous_object_array;

  /**
   * Forward declaration for recursive processing
   */
  function process_object(
    p_object in json_object_t,
    p_indent_level in number
  ) return clob;

  function process_array(
    p_array in json_array_t,
    p_indent_level in number
  ) return clob;

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
    end loop primitive_loop;

    return l_result;
  end process_primitive_array;

  /**
   * Process homogeneous object array in columnar format
   */
  function process_homogeneous_array(
    p_array in json_array_t,
    p_keys in json_key_list,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_obj json_object_t;
    l_element json_element_t;
    l_value varchar2(32767 char);
  begin
    sys.dbms_output.put_line('Processing homogeneous array with ' || p_array.get_size || ' elements and ' || p_keys.count || ' keys.');
    sys.dbms_output.put_line('Array: ' || p_array.stringify);


    sys.dbms_lob.createtemporary(l_result, true);
    -- Data rows should always be indented at least one level
    l_indent := rpad(' ', (p_indent_level + 1) * length(c_indent), c_indent);

    -- Write header: [count]{key1,key2,key3}:
    sys.dbms_lob.writeappend(l_result, length('[' || p_array.get_size || ']{'), '[' || p_array.get_size || ']{');
    <<header_loop>>
    for i in 1 .. p_keys.count loop
      if i > 1 then
        sys.dbms_lob.writeappend(l_result, 1, ',');
      end if;
      sys.dbms_lob.writeappend(l_result, length(p_keys(i)), p_keys(i));
    end loop header_loop;
    sys.dbms_lob.writeappend(l_result, 3, '}:' || chr(10));

    -- Write data rows
    <<data_rows_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      sys.dbms_output.put_line('Processing row ' || i || ': ' || p_array.get(i).stringify);
      sys.dbms_output.put_line('Indent: "' || l_indent || '"');

      sys.dbms_lob.writeappend(l_result, length(l_indent), l_indent);
      l_obj := treat(p_array.get(i) as json_object_t);
      
      <<columns_loop>>
      for j in 1 .. p_keys.count loop
        if j > 1 then
          sys.dbms_lob.writeappend(l_result, 1, ',');
        end if;
        l_element := l_obj.get(p_keys(j));
        l_value := element_to_toon_value(l_element);
        sys.dbms_lob.writeappend(l_result, length(l_value), l_value);
      end loop columns_loop;

      if i < p_array.get_size - 1 then
        sys.dbms_lob.writeappend(l_result, 1, chr(10));
      end if;
    end loop data_rows_loop;

    return l_result;
  end process_homogeneous_array;

  /**
   * Process an array
   */
  function process_array(
    p_array in json_array_t,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_element json_element_t;
    l_obj json_object_t;
    l_arr json_array_t;
    l_homogeneous_check r_homogeneous_check_type;
    l_nested clob;
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
      l_nested := process_primitive_array(p_array);
      sys.dbms_lob.append(l_result, l_nested);
      return l_result;
    end if;

    -- Homogeneous object array (columnar format)
    l_homogeneous_check := is_homogeneous_object_array(p_array);
    if l_homogeneous_check.is_homogeneous then
      return process_homogeneous_array(p_array, l_homogeneous_check.keys_arr, p_indent_level);
    end if;

    -- Irregular array (each element on its own line with dash)
    sys.dbms_lob.writeappend(l_result, length('[' || p_array.get_size || ']:' || chr(10)), '[' || p_array.get_size || ']:' || chr(10));
    
    <<irregular_array_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      l_element := p_array.get(i);
      sys.dbms_lob.writeappend(l_result, length(l_indent || '- '), l_indent || '- ');

      if l_element.is_object then
        l_obj := treat(l_element as json_object_t);
        l_nested := process_object(l_obj, p_indent_level + 1);
        -- Remove first line's indent as we already have "- "
        l_nested := regexp_replace(l_nested, '^' || rpad(' ', (p_indent_level + 1) * length(c_indent), c_indent), null);
        sys.dbms_lob.append(l_result, l_nested);
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
   * Process an object
   */
  function process_object(
    p_object in json_object_t,
    p_indent_level in number
  ) return clob is
    l_result clob;
    l_indent varchar2(200 char);
    l_keys_arr json_key_list;
    l_element json_element_t;
    l_obj json_object_t;
    l_arr json_array_t;
    l_value varchar2(32767 char);
    l_nested clob;
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

      l_element := p_object.get(l_keys_arr(i));

      if l_element.is_object then
        l_obj := treat(l_element as json_object_t);
        l_nested := process_object(l_obj, p_indent_level + 1);
        sys.dbms_lob.writeappend(l_result, length(l_indent || l_keys_arr(i) || ':'), l_indent || l_keys_arr(i) || ':');
        -- Only add newline if object is not empty
        if l_nested is not null and length(l_nested) > 0 then
          sys.dbms_lob.writeappend(l_result, 1, chr(10));
          sys.dbms_lob.append(l_result, l_nested);
        end if;
      elsif l_element.is_array then
        l_arr := treat(l_element as json_array_t);
        sys.dbms_lob.writeappend(l_result, length(l_indent || l_keys_arr(i)), l_indent || l_keys_arr(i));
        l_nested := process_array(l_arr, p_indent_level);
        -- Remove space after [0]: for empty arrays only
        if l_arr.get_size = 0 then
          l_nested := replace(l_nested, '[0]: ', '[0]:');
        end if;
        sys.dbms_lob.append(l_result, l_nested);
      else
        sys.dbms_lob.writeappend(l_result, length(l_indent || l_keys_arr(i) || ': '), l_indent || l_keys_arr(i) || ': ');
        l_value := element_to_toon_value(l_element);
        sys.dbms_output.put_line('Processing key "' || l_keys_arr(i) || '" with value: ' || l_value);
        if length(trim(l_value)) != 0 then
          sys.dbms_lob.writeappend(l_result, length(l_value), l_value);
        end if;
      end if;
    end loop object_keys_loop;

    return l_result;
  end process_object;

  /**
   * Convert a JSON_OBJECT_T to TOON format
   */
  function to_toon(p_json_object in json_object_t) return clob is
    l_result clob;
  begin
    if p_json_object is null then
      return null;
    end if;
    l_result := process_object(p_json_object, 0);
    -- Remove trailing newlines
    <<trim_newlines>>
    while length(l_result) > 0 and substr(l_result, -1) = chr(10) loop
      l_result := substr(l_result, 1, length(l_result) - 1);
    end loop trim_newlines;
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
    l_result := process_array(p_json_array, 0);
    -- Remove trailing newlines
    <<trim_newlines>>
    while length(l_result) > 0 and substr(l_result, -1) = chr(10) loop
      l_result := substr(l_result, 1, length(l_result) - 1);
    end loop trim_newlines;
    return l_result;
  end to_toon;

  /**
   * Convert a JSON string to TOON format
   */
  function to_toon(p_json_string in clob) return clob is
    l_element json_element_t;
  begin
    if p_json_string is null then
      return null;
    end if;

    l_element := json_element_t.parse(p_json_string);

    if l_element.is_object then
      return to_toon(treat(l_element as json_object_t));
    elsif l_element.is_array then
      return to_toon(treat(l_element as json_array_t));
    end if;

    -- Handle primitive values
    return element_to_toon_value(l_element);
  end to_toon;

end uc_ai_toon;
/
