create or replace package body test_uc_ai_toon as
  -- @dblinter ignore(g-5010): allow logger in test packages

  procedure basic_object
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"name": "Alice", "age": 30}
    l_json := json_object_t();
    l_json.put('name', 'Alice');
    l_json.put('age', 30);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'name: Alice' || chr(10) || 'age: 30';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result: ' || l_result);
  end basic_object;


  procedure basic_array
  as
    l_json json_array_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: [1, 2, 3]
    l_json := json_array_t();
    l_json.append(1);
    l_json.append(2);
    l_json.append(3);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := '[3]: 1,2,3';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result: ' || l_result);
  end basic_array;


  procedure nested_object
  as
    l_json json_object_t;
    l_user json_object_t;
    l_contact json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"user": {"name": "Bob", "contact": {"email": "bob@ex.com"}}}
    l_contact := json_object_t();
    l_contact.put('email', 'bob@ex.com');
    
    l_user := json_object_t();
    l_user.put('name', 'Bob');
    l_user.put('contact', l_contact);
    
    l_json := json_object_t();
    l_json.put('user', l_user);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'user:' || chr(10) 
               || '  name: Bob' || chr(10)
               || '  contact:' || chr(10)
               || '    email: bob@ex.com';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end nested_object;


  procedure empty_collections
  as
    l_json json_object_t;
    l_arr json_array_t;
    l_obj json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"data": [], "metadata": {}}
    l_arr := json_array_t();
    l_obj := json_object_t();
    
    l_json := json_object_t();
    l_json.put('data', l_arr);
    l_json.put('metadata', l_obj);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'data[0]:' || chr(10) || 'metadata:';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end empty_collections;


  procedure null_values
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"a": null, "b": null}
    l_json := json_object_t();
    l_json.put_null('a');
    l_json.put_null('b');

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'a: null' || chr(10) || 'b: null';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result: ' || l_result);
  end null_values;


  procedure mixed_types
  as
    l_json json_object_t;
    l_arr json_array_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"str": "text", "num": 42, "bool": true, "nil": null, "arr": [1, "two"]}
    l_arr := json_array_t();
    l_arr.append(1);
    l_arr.append('two');
    
    l_json := json_object_t();
    l_json.put('str', 'text');
    l_json.put('num', 42);
    l_json.put('bool', true);
    l_json.put_null('nil');
    l_json.put('arr', l_arr);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'str: text' || chr(10)
               || 'num: 42' || chr(10)
               || 'bool: true' || chr(10)
               || 'nil: null' || chr(10)
               || 'arr[2]: 1,two';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end mixed_types;


  procedure special_characters
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"text": "He said \"hello\"", "path": "C:\\Users\\file", "newline": "line1\nline2"}
    l_json := json_object_t();
    l_json.put('text', 'He said "hello"');
    l_json.put('path', 'C:\Users\file');
    l_json.put('newline', 'line1' || chr(10) || 'line2');

    l_result := uc_ai_toon.to_toon(l_json);
    
    -- Values with special chars should be quoted and escaped
    l_expected := 'text: "He said \"hello\""' || chr(10)
               || 'path: "C:\\Users\\file"' || chr(10)
               || 'newline: "line1\nline2"';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end special_characters;


  procedure numbers
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"zero": 0, "negative": -5, "float": 3.14, "large": 9007199254740991}
    l_json := json_object_t();
    l_json.put('zero', 0);
    l_json.put('negative', -5);
    l_json.put('float', 3.14);
    l_json.put('large', 9007199254740991);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'zero: 0' || chr(10)
               || 'negative: -5' || chr(10)
               || 'float: 3.14' || chr(10)
               || 'large: 9007199254740991';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end numbers;


  procedure strings
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
    l_empty_str varchar2(1 char) := '';
  begin
    -- Original JSON: {"empty": "", "space": " ", "tab": "\t"}
    l_json := json_object_t();
    l_json.put('empty', l_empty_str);
    l_json.put('space', ' ');
    l_json.put('tab', chr(9));

    l_result := uc_ai_toon.to_toon(l_json);
    
    -- Empty strings and strings with leading/trailing spaces or special chars need quotes
    l_expected := 'empty: ""' || chr(10)
               || 'space: " "' || chr(10)
               || 'tab: "\t"';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end strings;


  procedure deeply_nested
  as
    l_json json_object_t;
    l_a json_object_t;
    l_b json_object_t;
    l_c json_object_t;
    l_d json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"a": {"b": {"c": {"d": {"e": "value"}}}}}
    l_d := json_object_t();
    l_d.put('e', 'value');
    
    l_c := json_object_t();
    l_c.put('d', l_d);
    
    l_b := json_object_t();
    l_b.put('c', l_c);
    
    l_a := json_object_t();
    l_a.put('b', l_b);
    
    l_json := json_object_t();
    l_json.put('a', l_a);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'a:' || chr(10)
               || '  b:' || chr(10)
               || '    c:' || chr(10)
               || '      d:' || chr(10)
               || '        e: value';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end deeply_nested;


  procedure large_array
  as
    l_json json_object_t;
    l_arr json_array_t;
    l_result clob;
    l_expected clob;
    l_expected_values varchar2(32767 char);
    l_max_num constant pls_integer := 99;
  begin
    -- Original JSON: {"items": [0,1,2,...,99]}
    l_arr := json_array_t();
    <<array_loop>>
    for i in 0 .. l_max_num loop
      l_arr.append(i);
    end loop array_loop;
    
    l_json := json_object_t();
    l_json.put('items', l_arr);

    l_result := uc_ai_toon.to_toon(l_json);
    
    -- Build expected comma-separated values
    l_expected_values := '0';
    <<expected_loop>>
    for i in 1 .. l_max_num loop
      l_expected_values := l_expected_values || ',' || i;
    end loop expected_loop;
    
    l_expected := 'items[100]: ' || l_expected_values;
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result length: ' || length(l_result));
  end large_array;


  procedure booleans
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"t": true, "f": false}
    l_json := json_object_t();
    l_json.put('t', true);
    l_json.put('f', false);

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 't: true' || chr(10) || 'f: false';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result: ' || l_result);
  end booleans;


  procedure unicode_characters
  as
    l_json json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"greeting": "こんにちは", "emoji": "🚀", "symbol": "€"}
    l_json := json_object_t();
    l_json.put('greeting', 'こんにちは');
    l_json.put('emoji', '🚀');
    l_json.put('symbol', '€');

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'greeting: こんにちは' || chr(10)
               || 'emoji: 🚀' || chr(10)
               || 'symbol: €';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end unicode_characters;


  procedure api_response
  as
    l_json json_object_t;
    l_data json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"status": 200, "data": {"id": 1, "name": "Test"}, "errors": null}
    l_data := json_object_t();
    l_data.put('id', 1);
    l_data.put('name', 'Test');
    
    l_json := json_object_t();
    l_json.put('status', 200);
    l_json.put('data', l_data);
    l_json.put_null('errors');

    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'status: 200' || chr(10)
               || 'data:' || chr(10)
               || '  id: 1' || chr(10)
               || '  name: Test' || chr(10)
               || 'errors: null';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end api_response;


  procedure records_homogeneous
  as
    l_json json_array_t;
    l_obj1 json_object_t;
    l_obj2 json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: [{"id": 1, "active": true}, {"id": 2, "active": false}]
    l_obj1 := json_object_t();
    l_obj1.put('id', 1);
    l_obj1.put('active', true);
    
    l_obj2 := json_object_t();
    l_obj2.put('id', 2);
    l_obj2.put('active', false);
    
    l_json := json_array_t();
    l_json.append(l_obj1);
    l_json.append(l_obj2);

    l_result := uc_ai_toon.to_toon(l_json);
    
    -- Columnar format for homogeneous object arrays
    l_expected := '[2]{id,active}:' || chr(10)
               || '  1,true' || chr(10)
               || '  2,false';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end records_homogeneous;


  procedure irregular_array
  as
    l_json json_array_t;
    l_obj1 json_object_t;
    l_obj2 json_object_t;
    l_obj3 json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: [{"a": 1}, {"a": 1, "b": 2}, {"c": 3}]
    l_obj1 := json_object_t();
    l_obj1.put('a', 1);
    
    l_obj2 := json_object_t();
    l_obj2.put('a', 1);
    l_obj2.put('b', 2);
    
    l_obj3 := json_object_t();
    l_obj3.put('c', 3);
    
    l_json := json_array_t();
    l_json.append(l_obj1);
    l_json.append(l_obj2);
    l_json.append(l_obj3);

    l_result := uc_ai_toon.to_toon(l_json);
    
    -- Irregular arrays use dash notation
    l_expected := '[3]:' || chr(10)
               || '  - a: 1' || chr(10)
               || '  - a: 1' || chr(10)
               || '    b: 2' || chr(10)
               || '  - c: 3';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end irregular_array;


  procedure json_string_conversion
  as
    l_json_str clob;
    l_result clob;
    l_expected clob;
  begin
    -- Test converting from JSON string to TOON
    l_json_str := '{"name": "Charlie", "age": 25}';

    l_result := uc_ai_toon.to_toon(l_json_str);
    
    l_expected := 'name: Charlie' || chr(10) || 'age: 25';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result: ' || l_result);
  end json_string_conversion;


  procedure null_input
  as
    l_json_obj json_object_t;
    l_json_arr json_array_t;
    l_json_str clob;
    l_result clob;
  begin
    -- Test null input handling
    l_json_obj := null;
    l_result := uc_ai_toon.to_toon(l_json_obj);
    ut.expect(l_result).to_be_null();
    
    l_json_arr := null;
    l_result := uc_ai_toon.to_toon(l_json_arr);
    ut.expect(l_result).to_be_null();
    
    l_json_str := null;
    l_result := uc_ai_toon.to_toon(l_json_str);
    ut.expect(l_result).to_be_null();
    
    sys.dbms_output.put_line('Null input test passed');
  end null_input;

  procedure nested_mixed
  as
    l_items json_array_t;
    l_item json_object_t;
    l_users json_array_t;
    l_user1 json_object_t;
    l_user2 json_object_t;
    l_result clob;
    l_expected clob;
  begin
    -- Original JSON: {"items": [{"users": [{"id": 1, "name": "Ada"}, {"id": 2, "name": "Bob"}], "status": "active"}]}
    l_user1 := json_object_t();
    l_user1.put('id', 1);
    l_user1.put('name', 'Ada');
    
    l_user2 := json_object_t();
    l_user2.put('id', 2);
    l_user2.put('name', 'Bob');
    
    l_users := json_array_t();
    l_users.append(l_user1);
    l_users.append(l_user2);
    
    l_item := json_object_t();
    l_item.put('users', l_users);
    l_item.put('status', 'active');
    
    l_items := json_array_t();
    l_items.append(l_item);
    
    l_result := uc_ai_toon.to_toon(l_items);
    
    l_expected := 'items[1]:' || chr(10)
               || '  - users[2]{id,name}:' || chr(10)
               || '    1,Ada' || chr(10)
               || '    2,Bob' || chr(10)
               || '    status: active';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end nested_mixed;

end test_uc_ai_toon;
/
