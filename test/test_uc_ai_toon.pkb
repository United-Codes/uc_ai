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
    l_json  json_object_t;
    l_items json_array_t;
    l_item  json_object_t;
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

    l_json := json_object_t();
    l_json.put('items', l_items);
    
    l_result := uc_ai_toon.to_toon(l_json);
    
    l_expected := 'items[1]:' || chr(10)
               || '  - users[2]{id,name}:' || chr(10)
               || '    1,Ada' || chr(10)
               || '    2,Bob' || chr(10)
               || '    status: active';
    
    ut.expect(l_result).to_equal(l_expected);
    sys.dbms_output.put_line('Result:' || chr(10) || l_result);
  end nested_mixed;

  procedure glossary_structure
  as
    l_result clob;
    l_expected clob;
  begin
    l_result := uc_ai_toon.to_toon(q'!{
    "glossary": {
        "title": "example glossary",
		"GlossDiv": {
            "title": "S",
			"GlossList": {
                "GlossEntry": {
                    "ID": "SGML",
					"SortAs": "SGML",
					"GlossTerm": "Standard Generalized Markup Language",
					"Acronym": "SGML",
					"Abbrev": "ISO 8879:1986",
					"GlossDef": {
                        "para": "A meta-markup language, used to create markup languages such as DocBook.",
						"GlossSeeAlso": ["GML", "XML"]
                    },
					"GlossSee": "markup"
                }
            }
        }
    }
}
!');
    l_expected := q'!glossary:
  title: example glossary
  GlossDiv:
    title: S
    GlossList:
      GlossEntry:
        ID: SGML
        SortAs: SGML
        GlossTerm: Standard Generalized Markup Language
        Acronym: SGML
        Abbrev: "ISO 8879:1986"
        GlossDef:
          para: "A meta-markup language, used to create markup languages such as DocBook."
          GlossSeeAlso[2]: GML,XML
        GlossSee: markup!';

    ut.expect(l_result).to_equal(l_expected);

  end glossary_structure;


  procedure countries_array
  as
    l_result clob;
    l_expected clob;
  begin
    l_result := uc_ai_toon.to_toon(q'![
  {
    "name": "France",
    "capital": "Paris",
    "population": 67364357,
    "area": 551695,
    "currency": "Euro",
    "languages": [
      "French"
    ],
    "region": "Europe",
    "subregion": "Western Europe",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/c/c3/Flag_of_France.svg"
  },
  {
    "name": "Germany",
    "capital": "Berlin",
    "population": 83240525,
    "area": 357022,
    "currency": "Euro",
    "languages": [
      "German"
    ],
    "region": "Europe",
    "subregion": "Western Europe",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/b/ba/Flag_of_Germany.svg"
  },
  {
    "name": "United States",
    "capital": "Washington, D.C.",
    "population": 331893745,
    "area": 9833517,
    "currency": "USD",
    "languages": [
      "English"
    ],
    "region": "Americas",
    "subregion": "Northern America",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/a/a4/Flag_of_the_United_States.svg"
  },
  {
    "name": "Belgium",
    "capital": "Brussels",
    "population": 11589623,
    "area": 30528,
    "currency": "Euro",
    "languages": [
      "Flemish",
      "French",
      "German"
    ],
    "region": "Europe",
    "subregion": "Western Europe",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/6/65/Flag_of_Belgium.svg"
  }
]
!');
    l_expected := q'![4]:
  - name: France
    capital: Paris
    population: 67364357
    area: 551695
    currency: Euro
    languages[1]: French
    region: Europe
    subregion: Western Europe
    flag: "https://upload.wikimedia.org/wikipedia/commons/c/c3/Flag_of_France.svg"
  - name: Germany
    capital: Berlin
    population: 83240525
    area: 357022
    currency: Euro
    languages[1]: German
    region: Europe
    subregion: Western Europe
    flag: "https://upload.wikimedia.org/wikipedia/commons/b/ba/Flag_of_Germany.svg"
  - name: United States
    capital: "Washington, D.C."
    population: 331893745
    area: 9833517
    currency: USD
    languages[1]: English
    region: Americas
    subregion: Northern America
    flag: "https://upload.wikimedia.org/wikipedia/commons/a/a4/Flag_of_the_United_States.svg"
  - name: Belgium
    capital: Brussels
    population: 11589623
    area: 30528
    currency: Euro
    languages[3]: Flemish,French,German
    region: Europe
    subregion: Western Europe
    flag: "https://upload.wikimedia.org/wikipedia/commons/6/65/Flag_of_Belgium.svg"!';

    ut.expect(l_result).to_equal(l_expected);

  end countries_array;

  procedure products_array
  as
    l_result clob;
    l_expected clob;
  begin
    l_result := uc_ai_toon.to_toon(q'![
  {
    "productId": 1001,
    "productName": "Wireless Headphones",
    "description": "Noise-cancelling wireless headphones with Bluetooth 5.0 and 20-hour battery life.",
    "brand": "SoundPro",
    "category": "Electronics",
    "price": 199.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 50
    },
    "images": [
      "https://example.com/products/1001/main.jpg",
      "https://example.com/products/1001/side.jpg"
    ],
    "variants": [
      {
        "variantId": "1001_01",
        "color": "Black",
        "price": 199.99,
        "stockQuantity": 20
      },
      {
        "variantId": "1001_02",
        "color": "White",
        "price": 199.99,
        "stockQuantity": 30
      }
    ],
    "dimensions": {
      "weight": "0.5kg",
      "width": "18cm",
      "height": "20cm",
      "depth": "8cm"
    },
    "ratings": {
      "averageRating": 4.7,
      "numberOfReviews": 120
    },
    "reviews": [
      {
        "reviewId": 501,
        "userId": 101,
        "username": "techguy123",
        "rating": 5,
        "comment": "Amazing sound quality and battery life!"
      },
      {
        "reviewId": 502,
        "userId": 102,
        "username": "jane_doe",
        "rating": 4,
        "comment": "Great headphones but a bit pricey."
      }
    ]
  },
  {
    "productId": 1002,
    "productName": "Smartphone Case",
    "description": "Durable and shockproof case for smartphones, available in multiple colors.",
    "brand": "CaseMate",
    "category": "Accessories",
    "price": 29.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 200
    },
    "images": [
      "https://example.com/products/1002/main.jpg",
      "https://example.com/products/1002/back.jpg"
    ],
    "variants": [
      {
        "variantId": "1002_01",
        "color": "Black",
        "price": 29.99,
        "stockQuantity": 100
      },
      {
        "variantId": "1002_02",
        "color": "Blue",
        "price": 29.99,
        "stockQuantity": 100
      }
    ],
    "dimensions": {
      "weight": "0.2kg",
      "width": "8cm",
      "height": "15cm",
      "depth": "1cm"
    },
    "ratings": {
      "averageRating": 4.4,
      "numberOfReviews": 80
    },
    "reviews": [
      {
        "reviewId": 601,
        "userId": 103,
        "username": "caseuser456",
        "rating": 4,
        "comment": "Very sturdy and fits perfectly."
      },
      {
        "reviewId": 602,
        "userId": 104,
        "username": "mobile_fan",
        "rating": 5,
        "comment": "Best case I've bought for my phone!"
      }
    ]
  },
  {
    "productId": 1003,
    "productName": "4K Ultra HD Smart TV",
    "description": "55-inch 4K Ultra HD Smart TV with built-in Wi-Fi and streaming apps.",
    "brand": "Visionary",
    "category": "Electronics",
    "price": 799.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 30
    },
    "images": [
      "https://example.com/products/1003/main.jpg",
      "https://example.com/products/1003/side.jpg"
    ],
    "variants": [
      {
        "variantId": "1003_01",
        "screenSize": "55 inch",
        "price": 799.99,
        "stockQuantity": 30
      }
    ],
    "dimensions": {
      "weight": "15kg",
      "width": "123cm",
      "height": "80cm",
      "depth": "10cm"
    },
    "ratings": {
      "averageRating": 4.8,
      "numberOfReviews": 250
    },
    "reviews": [
      {
        "reviewId": 701,
        "userId": 105,
        "username": "techlover123",
        "rating": 5,
        "comment": "Incredible picture quality, streaming works seamlessly."
      },
      {
        "reviewId": 702,
        "userId": 106,
        "username": "homecinema",
        "rating": 4,
        "comment": "Great TV, but a little bulky."
      }
    ]
  },
  {
    "productId": 1004,
    "productName": "Bluetooth Speaker",
    "description": "Portable Bluetooth speaker with 12-hour battery life and water resistance.",
    "brand": "AudioX",
    "category": "Electronics",
    "price": 59.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 100
    },
    "images": [
      "https://example.com/products/1004/main.jpg",
      "https://example.com/products/1004/side.jpg"
    ],
    "variants": [
      {
        "variantId": "1004_01",
        "color": "Red",
        "price": 59.99,
        "stockQuantity": 50
      },
      {
        "variantId": "1004_02",
        "color": "Blue",
        "price": 59.99,
        "stockQuantity": 50
      }
    ],
    "dimensions": {
      "weight": "0.3kg",
      "width": "15cm",
      "height": "8cm",
      "depth": "5cm"
    },
    "ratings": {
      "averageRating": 4.6,
      "numberOfReviews": 150
    },
    "reviews": [
      {
        "reviewId": 801,
        "userId": 107,
        "username": "musicfan23",
        "rating": 5,
        "comment": "Excellent sound quality for its size!"
      },
      {
        "reviewId": 802,
        "userId": 108,
        "username": "outdoor_lover",
        "rating": 4,
        "comment": "Great for outdoor use, but the battery could last longer."
      }
    ]
  },
  {
    "productId": 1005,
    "productName": "Winter Jacket",
    "description": "Men's water-resistant winter jacket with a fur-lined hood.",
    "brand": "ColdTech",
    "category": "Clothing",
    "price": 129.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 80
    },
    "images": [
      "https://example.com/products/1005/main.jpg",
      "https://example.com/products/1005/back.jpg"
    ],
    "variants": [
      {
        "variantId": "1005_01",
        "size": "M",
        "color": "Black",
        "price": 129.99,
        "stockQuantity": 30
      },
      {
        "variantId": "1005_02",
        "size": "L",
        "color": "Gray",
        "price": 129.99,
        "stockQuantity": 50
      }
    ],
    "dimensions": {
      "weight": "1.5kg",
      "width": "60cm",
      "height": "85cm",
      "depth": "5cm"
    },
    "ratings": {
      "averageRating": 4.5,
      "numberOfReviews": 60
    },
    "reviews": [
      {
        "reviewId": 901,
        "userId": 109,
        "username": "outdoor_adventurer",
        "rating": 5,
        "comment": "Perfect for cold weather, very comfortable!"
      },
      {
        "reviewId": 902,
        "userId": 110,
        "username": "winter_gear",
        "rating": 4,
        "comment": "Nice jacket, but could be a little warmer."
      }
    ]
  }
]!');

  l_expected := q'![5]:
  - productId: 1001
    productName: Wireless Headphones
    description: Noise-cancelling wireless headphones with Bluetooth 5.0 and 20-hour battery life.
    brand: SoundPro
    category: Electronics
    price: 199.99
    currency: USD
    stock:
      available: true
      quantity: 50
    images[2]: "https://example.com/products/1001/main.jpg","https://example.com/products/1001/side.jpg"
    variants[2]{variantId,color,price,stockQuantity}:
      1001_01,Black,199.99,20
      1001_02,White,199.99,30
    dimensions:
      weight: 0.5kg
      width: 18cm
      height: 20cm
      depth: 8cm
    ratings:
      averageRating: 4.7
      numberOfReviews: 120
    reviews[2]{reviewId,userId,username,rating,comment}:
      501,101,techguy123,5,Amazing sound quality and battery life!
      502,102,jane_doe,4,Great headphones but a bit pricey.
  - productId: 1002
    productName: Smartphone Case
    description: "Durable and shockproof case for smartphones, available in multiple colors."
    brand: CaseMate
    category: Accessories
    price: 29.99
    currency: USD
    stock:
      available: true
      quantity: 200
    images[2]: "https://example.com/products/1002/main.jpg","https://example.com/products/1002/back.jpg"
    variants[2]{variantId,color,price,stockQuantity}:
      1002_01,Black,29.99,100
      1002_02,Blue,29.99,100
    dimensions:
      weight: 0.2kg
      width: 8cm
      height: 15cm
      depth: 1cm
    ratings:
      averageRating: 4.4
      numberOfReviews: 80
    reviews[2]{reviewId,userId,username,rating,comment}:
      601,103,caseuser456,4,Very sturdy and fits perfectly.
      602,104,mobile_fan,5,Best case I've bought for my phone!
  - productId: 1003
    productName: 4K Ultra HD Smart TV
    description: 55-inch 4K Ultra HD Smart TV with built-in Wi-Fi and streaming apps.
    brand: Visionary
    category: Electronics
    price: 799.99
    currency: USD
    stock:
      available: true
      quantity: 30
    images[2]: "https://example.com/products/1003/main.jpg","https://example.com/products/1003/side.jpg"
    variants[1]{variantId,screenSize,price,stockQuantity}:
      1003_01,55 inch,799.99,30
    dimensions:
      weight: 15kg
      width: 123cm
      height: 80cm
      depth: 10cm
    ratings:
      averageRating: 4.8
      numberOfReviews: 250
    reviews[2]{reviewId,userId,username,rating,comment}:
      701,105,techlover123,5,"Incredible picture quality, streaming works seamlessly."
      702,106,homecinema,4,"Great TV, but a little bulky."
  - productId: 1004
    productName: Bluetooth Speaker
    description: Portable Bluetooth speaker with 12-hour battery life and water resistance.
    brand: AudioX
    category: Electronics
    price: 59.99
    currency: USD
    stock:
      available: true
      quantity: 100
    images[2]: "https://example.com/products/1004/main.jpg","https://example.com/products/1004/side.jpg"
    variants[2]{variantId,color,price,stockQuantity}:
      1004_01,Red,59.99,50
      1004_02,Blue,59.99,50
    dimensions:
      weight: 0.3kg
      width: 15cm
      height: 8cm
      depth: 5cm
    ratings:
      averageRating: 4.6
      numberOfReviews: 150
    reviews[2]{reviewId,userId,username,rating,comment}:
      801,107,musicfan23,5,Excellent sound quality for its size!
      802,108,outdoor_lover,4,"Great for outdoor use, but the battery could last longer."
  - productId: 1005
    productName: Winter Jacket
    description: Men's water-resistant winter jacket with a fur-lined hood.
    brand: ColdTech
    category: Clothing
    price: 129.99
    currency: USD
    stock:
      available: true
      quantity: 80
    images[2]: "https://example.com/products/1005/main.jpg","https://example.com/products/1005/back.jpg"
    variants[2]{variantId,size,color,price,stockQuantity}:
      1005_01,M,Black,129.99,30
      1005_02,L,Gray,129.99,50
    dimensions:
      weight: 1.5kg
      width: 60cm
      height: 85cm
      depth: 5cm
    ratings:
      averageRating: 4.5
      numberOfReviews: 60
    reviews[2]{reviewId,userId,username,rating,comment}:
      901,109,outdoor_adventurer,5,"Perfect for cold weather, very comfortable!"
      902,110,winter_gear,4,"Nice jacket, but could be a little warmer."!';

    ut.expect(l_result).to_equal(l_expected);
  end products_array;

end test_uc_ai_toon;
/
