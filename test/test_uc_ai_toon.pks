create or replace package test_uc_ai_toon as

  --%suite(TOON Format Encoding tests)

  --%test(Basic Object)
  procedure basic_object;

  --%test(Basic Array)
  procedure basic_array;

  --%test(Nested Object)
  procedure nested_object;

  --%test(Empty Collections)
  procedure empty_collections;

  --%test(Null Values)
  procedure null_values;

  --%test(Mixed Types)
  procedure mixed_types;

  --%test(Special Characters)
  procedure special_characters;

  --%test(Numbers)
  procedure numbers;

  --%test(Strings)
  procedure strings;

  --%test(Deeply Nested Structure)
  procedure deeply_nested;

  --%test(Large Array)
  procedure large_array;

  --%test(Booleans)
  procedure booleans;

  --%test(Unicode Characters)
  procedure unicode_characters;

  --%test(API Response)
  procedure api_response;

  --%test(Records - Homogeneous Array of Objects)
  procedure records_homogeneous;

  --%test(Irregular Array)
  procedure irregular_array;

  --%test(Convert from JSON string)
  procedure json_string_conversion;

  --%test(Null input handling)
  procedure null_input;

  --%test(Nested Mixed Types)
  procedure nested_mixed;

  --%test(Glossary Structure)
  procedure glossary_structure;

  --%test(Countries Array Data Set)
  procedure countries_array;

  --%test(Products Array Data Set)
  procedure products_array;

  --%test(Hash-leading Strings are quoted)
  procedure hash_strings;

  --%test(Keys requiring quotes are quoted)
  procedure key_quoting;

  --%test(Plus-leading numeric strings are quoted)
  procedure plus_number_strings;

  --%test(Tabular Array with reordered keys)
  procedure tabular_key_order_varies;

  --%test(Empty object as list item uses bare dash)
  procedure empty_object_list_item;

  --%test(Nested uniform columns use nested field groups)
  procedure nested_uniform_columns;

  --%test(Single row with nested uniform columns)
  procedure nested_uniform_single_row;

  --%test(Deeply nested uniform columns)
  procedure nested_uniform_deep;

  --%test(Keyed tabular form for uniform ID-keyed objects)
  procedure keyed_tabular;

  --%test(Keyed tabular form at document root)
  procedure keyed_tabular_root;

  --%test(Single-entry object stays nested)
  procedure keyed_tabular_single_fallback;

  --%test(Non-uniform values stay nested)
  procedure keyed_tabular_nonuniform_fallback;

  --%test(Entry keys requiring quotes are quoted)
  procedure keyed_tabular_entry_key_quoting;

  --%test(Nested uniform columns inside keyed tabular form)
  procedure keyed_tabular_nested_columns;

  --%test(JSON-only escapes translated to TOON escapes)
  procedure control_escapes;

  --%test(Multibyte values in tabular rows)
  procedure unicode_tabular;

  --%test(Root primitives from JSON string)
  procedure root_primitives;

end test_uc_ai_toon;
/
