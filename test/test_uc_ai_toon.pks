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

end test_uc_ai_toon;
/
