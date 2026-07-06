create or replace package body test_uc_ai_structured_output as

  /*
   * Standard test schema: object with a string, an integer and an array
   * property, metadata keys and constraints on every level.
   */
  function standard_schema return json_object_t
  as
  begin
    return json_object_t('{
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Person Data",
      "description": "A person record",
      "type": "object",
      "properties": {
        "name": {"type": "string", "description": "full name", "minLength": 2},
        "age": {"type": "integer", "minimum": 0},
        "tags": {"type": "array", "items": {"type": "string", "maxLength": 5}, "maxItems": 10, "minItems": 1}
      },
      "required": ["name"]
    }');
  end standard_schema;


  /*
   * Schema with a nested object property and an array of objects
   * to exercise recursion through properties and items.
   */
  function nested_schema return json_object_t
  as
  begin
    return json_object_t('{
      "title": "Order",
      "type": "object",
      "properties": {
        "customer": {
          "type": "object",
          "description": "the buyer",
          "properties": {
            "name": {"type": "string"}
          }
        },
        "lines": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "sku": {"type": "string"},
              "qty": {"type": "integer", "minimum": 1}
            }
          }
        }
      },
      "required": ["customer"]
    }');
  end nested_schema;


  procedure openai_strict_envelope
  as
    l_result      json_object_t;
    l_json_schema json_object_t;
  begin
    l_result := uc_ai_structured_output.to_openai_format(standard_schema);

    ut.expect(l_result.get_string('type')).to_equal('json_schema');

    l_json_schema := l_result.get_object('json_schema');
    ut.expect(l_json_schema.get_boolean('strict')).to_be_true();
    ut.expect(l_json_schema.get_string('name')).to_equal('Person_Data');
    ut.expect(l_json_schema.has('schema')).to_be_true();
  end openai_strict_envelope;


  procedure openai_strict_removes_metadata
  as
    l_schema json_object_t;
    l_name   json_object_t;
  begin
    l_schema := uc_ai_structured_output.to_openai_format(standard_schema)
                  .get_object('json_schema').get_object('schema');

    ut.expect(l_schema.has('$schema')).to_be_false();
    ut.expect(l_schema.has('title')).to_be_false();
    ut.expect(l_schema.has('description')).to_be_false();

    -- metadata is also removed inside each property (recursion)
    l_name := l_schema.get_object('properties').get_object('name');
    ut.expect(l_name.has('description')).to_be_false();
  end openai_strict_removes_metadata;


  procedure openai_strict_additional_props
  as
    l_schema json_object_t;
    l_props  json_object_t;
  begin
    l_schema := uc_ai_structured_output.to_openai_format(nested_schema)
                  .get_object('json_schema').get_object('schema');

    ut.expect(l_schema.get_boolean('additionalProperties')).to_be_false();

    l_props := l_schema.get_object('properties');
    -- nested object property gets additionalProperties=false
    ut.expect(l_props.get_object('customer').get_boolean('additionalProperties')).to_be_false();
    -- non-object property does not
    ut.expect(l_props.get_object('lines').has('additionalProperties')).to_be_false();
  end openai_strict_additional_props;


  procedure openai_strict_forces_all_required
  as
    l_schema json_object_t;
    l_req    json_array_t;
  begin
    l_schema := uc_ai_structured_output.to_openai_format(standard_schema)
                  .get_object('json_schema').get_object('schema');

    -- input required only "name"; strict mode requires all three properties
    l_req := l_schema.get_array('required');
    ut.expect(l_req.get_size).to_equal(3);
    ut.expect(l_req.to_string).to_be_like('%"name"%');
    ut.expect(l_req.to_string).to_be_like('%"age"%');
    ut.expect(l_req.to_string).to_be_like('%"tags"%');
  end openai_strict_forces_all_required;


  procedure openai_strict_recurses_items
  as
    l_schema json_object_t;
    l_items  json_object_t;
  begin
    l_schema := uc_ai_structured_output.to_openai_format(nested_schema)
                  .get_object('json_schema').get_object('schema');

    l_items := l_schema.get_object('properties').get_object('lines').get_object('items');

    -- items object schema went through strict processing too
    ut.expect(l_items.get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_items.get_array('required').get_size).to_equal(2);
  end openai_strict_recurses_items;


  procedure openai_name_sanitized
  as
    l_schema json_object_t := standard_schema;
    l_name   varchar2(4000 char);
  begin
    l_schema.put('title', 'My Schema! (v2)');

    l_name := uc_ai_structured_output.to_openai_format(l_schema)
                .get_object('json_schema').get_string('name');

    -- spaces become underscores, remaining invalid characters are stripped
    ut.expect(l_name).to_equal('My_Schema_v2');
  end openai_name_sanitized;


  procedure openai_name_fallback
  as
    l_schema json_object_t := standard_schema;
    l_name   varchar2(4000 char);
  begin
    l_schema.put('title', '!!!');

    l_name := uc_ai_structured_output.to_openai_format(l_schema)
                .get_object('json_schema').get_string('name');

    ut.expect(l_name).to_equal('structured_output');

    -- no title at all also falls back
    l_schema.remove('title');
    l_name := uc_ai_structured_output.to_openai_format(l_schema)
                .get_object('json_schema').get_string('name');

    ut.expect(l_name).to_equal('structured_output');
  end openai_name_fallback;


  procedure openai_non_strict_passthrough
  as
    l_result      json_object_t;
    l_json_schema json_object_t;
    l_schema      json_object_t;
  begin
    l_result := uc_ai_structured_output.to_openai_format(standard_schema, p_strict => false);

    l_json_schema := l_result.get_object('json_schema');
    ut.expect(l_json_schema.get_boolean('strict')).to_be_false();

    -- schema is passed through unchanged
    l_schema := l_json_schema.get_object('schema');
    ut.expect(l_schema.get_string('title')).to_equal('Person Data');
    ut.expect(l_schema.get_string('description')).to_equal('A person record');
    ut.expect(l_schema.get_array('required').get_size).to_equal(1);
    ut.expect(l_schema.has('additionalProperties')).to_be_false();
  end openai_non_strict_passthrough;


  procedure openai_does_not_mutate_input
  as
    l_input  json_object_t := standard_schema;
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_openai_format(l_input);

    ut.expect(l_input.get_string('title')).to_equal('Person Data');
    ut.expect(l_input.get_array('required').get_size).to_equal(1);
    ut.expect(l_input.get_object('properties').get_object('name').has('description')).to_be_true();
  end openai_does_not_mutate_input;


  procedure google_type_conversion
  as
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(json_object_t('{"type":"string"}'));
    ut.expect(l_result.get_string('type')).to_equal('STRING');

    -- unknown types are uppercased as-is
    l_result := uc_ai_structured_output.to_google_format(json_object_t('{"type":"date"}'));
    ut.expect(l_result.get_string('type')).to_equal('DATE');
  end google_type_conversion;


  procedure google_nested_conversion
  as
    l_result json_object_t;
    l_props  json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(standard_schema);

    ut.expect(l_result.get_string('type')).to_equal('OBJECT');
    ut.expect(l_result.get_string('description')).to_equal('A person record');

    l_props := l_result.get_object('properties');
    ut.expect(l_props.get_object('name').get_string('type')).to_equal('STRING');
    ut.expect(l_props.get_object('name').get_string('description')).to_equal('full name');
    ut.expect(l_props.get_object('age').get_string('type')).to_equal('INTEGER');

    -- required is copied verbatim
    ut.expect(l_result.get_array('required').get_size).to_equal(1);
    ut.expect(l_result.get_array('required').get_string(0)).to_equal('name');
  end google_nested_conversion;


  procedure google_property_ordering
  as
    l_schema json_object_t := standard_schema;
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(l_schema);

    -- propertyOrdering mirrors the required array when both keys exist
    ut.expect(l_result.has('propertyOrdering')).to_be_true();
    ut.expect(l_result.get_array('propertyOrdering').get_string(0)).to_equal('name');

    l_schema.remove('required');
    l_result := uc_ai_structured_output.to_google_format(l_schema);
    ut.expect(l_result.has('propertyOrdering')).to_be_false();
  end google_property_ordering;


  procedure google_array_items
  as
    l_result json_object_t;
    l_tags   json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(standard_schema);

    l_tags := l_result.get_object('properties').get_object('tags');
    ut.expect(l_tags.get_string('type')).to_equal('ARRAY');
    ut.expect(l_tags.get_object('items').get_string('type')).to_equal('STRING');
  end google_array_items;


  procedure google_drops_unknown_keys
  as
    l_result json_object_t;
  begin
    -- Google conversion only maps type/description/properties/items/required;
    -- everything else (constraints, enum, title, ...) is dropped.
    -- Characterization of the current limitation.
    l_result := uc_ai_structured_output.to_google_format(standard_schema);

    ut.expect(l_result.has('title')).to_be_false();
    ut.expect(l_result.has('$schema')).to_be_false();
    ut.expect(l_result.get_object('properties').get_object('name').has('minLength')).to_be_false();
    ut.expect(l_result.get_object('properties').get_object('age').has('minimum')).to_be_false();
    ut.expect(l_result.get_object('properties').get_object('tags').has('maxItems')).to_be_false();
  end google_drops_unknown_keys;


  procedure ollama_removes_metadata_only
  as
    l_input  json_object_t := standard_schema;
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_ollama_format(l_input);

    ut.expect(l_result.has('$schema')).to_be_false();
    ut.expect(l_result.has('title')).to_be_false();

    -- everything else survives
    ut.expect(l_result.get_string('description')).to_equal('A person record');
    ut.expect(l_result.get_array('required').get_size).to_equal(1);
    ut.expect(l_result.get_object('properties').get_object('name').get_number('minLength')).to_equal(2);

    -- input is not mutated
    ut.expect(l_input.get_string('title')).to_equal('Person Data');
  end ollama_removes_metadata_only;


  procedure anthropic_envelope
  as
    l_result json_object_t;
    l_format json_object_t;
    l_schema json_object_t;
  begin
    l_result := uc_ai_structured_output.to_anthropic_format(standard_schema);

    -- the returned object is the output_config value itself: {"format": {...}}
    l_format := l_result.get_object('format');
    ut.expect(l_format.get_string('type')).to_equal('json_schema');

    -- schema went through strict processing
    l_schema := l_format.get_object('schema');
    ut.expect(l_schema.has('title')).to_be_false();
    ut.expect(l_schema.get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_schema.get_array('required').get_size).to_equal(3);
  end anthropic_envelope;


  procedure anthropic_strips_constraints
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_tags   json_object_t;
  begin
    l_schema := uc_ai_structured_output.to_anthropic_format(standard_schema)
                  .get_object('format').get_object('schema');

    l_props := l_schema.get_object('properties');
    ut.expect(l_props.get_object('name').has('minLength')).to_be_false();
    ut.expect(l_props.get_object('age').has('minimum')).to_be_false();

    l_tags := l_props.get_object('tags');
    ut.expect(l_tags.has('minItems')).to_be_false();
    ut.expect(l_tags.has('maxItems')).to_be_false();
    -- constraints inside items are stripped too
    ut.expect(l_tags.get_object('items').has('maxLength')).to_be_false();
  end anthropic_strips_constraints;


  procedure responses_api_flat_shape
  as
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_responses_api_format(standard_schema);

    -- name, strict and schema sit at the top level (no json_schema wrapper)
    ut.expect(l_result.get_string('type')).to_equal('json_schema');
    ut.expect(l_result.get_string('name')).to_equal('Person_Data');
    ut.expect(l_result.get_boolean('strict')).to_be_true();
    ut.expect(l_result.has('schema')).to_be_true();
    ut.expect(l_result.has('json_schema')).to_be_false();

    ut.expect(l_result.get_object('schema').get_boolean('additionalProperties')).to_be_false();
  end responses_api_flat_shape;


  procedure format_schema_dispatch
  as
    l_direct   json_object_t;
    l_dispatch json_object_t;
  begin
    l_direct   := uc_ai_structured_output.to_openai_format(standard_schema, p_strict => true);
    l_dispatch := uc_ai_structured_output.format_schema(standard_schema, uc_ai.c_provider_openai, p_strict => true);
    ut.expect(l_dispatch.to_clob).to_equal(l_direct.to_clob);

    l_direct   := uc_ai_structured_output.to_google_format(standard_schema);
    l_dispatch := uc_ai_structured_output.format_schema(standard_schema, uc_ai.c_provider_google);
    ut.expect(l_dispatch.to_clob).to_equal(l_direct.to_clob);

    l_direct   := uc_ai_structured_output.to_ollama_format(standard_schema);
    l_dispatch := uc_ai_structured_output.format_schema(standard_schema, uc_ai.c_provider_ollama);
    ut.expect(l_dispatch.to_clob).to_equal(l_direct.to_clob);

    l_direct   := uc_ai_structured_output.to_anthropic_format(standard_schema);
    l_dispatch := uc_ai_structured_output.format_schema(standard_schema, uc_ai.c_provider_anthropic);
    ut.expect(l_dispatch.to_clob).to_equal(l_direct.to_clob);
  end format_schema_dispatch;


  procedure format_schema_unknown_provider
  as
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.format_schema(standard_schema, uc_ai.c_provider_oci);
  end format_schema_unknown_provider;


  procedure empty_schema_handled
  as
    l_result json_object_t;
    l_schema json_object_t;
  begin
    l_result := uc_ai_structured_output.to_openai_format(json_object_t());

    ut.expect(l_result.get_object('json_schema').get_string('name')).to_equal('structured_output');
    l_schema := l_result.get_object('json_schema').get_object('schema');
    -- no type key means no additionalProperties is added
    ut.expect(l_schema.has('additionalProperties')).to_be_false();

    l_result := uc_ai_structured_output.to_google_format(json_object_t());
    ut.expect(l_result.get_size).to_equal(0);
  end empty_schema_handled;

end test_uc_ai_structured_output;
/
