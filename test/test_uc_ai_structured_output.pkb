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


  /*
   * Every JSON schema keyword a user is likely to write, on the node type it belongs
   * to. The keyword survival tests below state which of them each provider keeps.
   */
  function kitchen_schema return json_object_t
  as
  begin
    return json_object_t('{
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Kitchen Sink",
      "description": "Every keyword",
      "type": "object",
      "minProperties": 1,
      "maxProperties": 9,
      "properties": {
        "text": {
          "type": "string", "title": "Text", "description": "a string",
          "minLength": 2, "maxLength": 9, "pattern": "^[a-z]+$",
          "format": "email", "default": "x", "examples": ["a"]
        },
        "num": {
          "type": "number", "description": "a number",
          "minimum": 0, "maximum": 10,
          "exclusiveMinimum": -1, "exclusiveMaximum": 11, "multipleOf": 0.5
        },
        "count": {"type": "integer", "enum": [1, 2, 3]},
        "list": {
          "type": "array", "description": "a list",
          "items": {"type": "string", "maxLength": 4},
          "minItems": 2, "maxItems": 7, "uniqueItems": true
        },
        "child": {
          "type": "object", "description": "a child",
          "minProperties": 1,
          "properties": {"inner": {"type": "string"}},
          "required": ["inner"]
        },
        "opt": {"type": ["string", "null"], "description": "optional"}
      },
      "required": ["text"]
    }');
  end kitchen_schema;


  /*
   * Schema that puts objects everywhere the recursion has to reach: $defs, definitions
   * and the three combinator arrays. None of the nested objects carries
   * additionalProperties or a complete required list.
   */
  function reference_schema return json_object_t
  as
  begin
    return json_object_t('{
      "type": "object",
      "$defs": {
        "Line": {
          "type": "object",
          "properties": {"sku": {"type": "string"}, "qty": {"type": "integer", "maxItems": 3}}
        }
      },
      "definitions": {
        "Addr": {
          "type": "object",
          "properties": {"city": {"type": "string"}, "zip": {"type": "string"}}
        }
      },
      "properties": {
        "lines": {"type": "array", "items": {"$ref": "#/$defs/Line"}},
        "payload": {
          "anyOf": [
            {"type": "object", "properties": {"a": {"type": "string"}}},
            {"type": "string"}
          ]
        },
        "either": {
          "oneOf": [{"type": "object", "properties": {"b": {"type": "string"}}}]
        },
        "both": {
          "allOf": [{"type": "object", "properties": {"c": {"type": "string"}}}]
        }
      },
      "required": ["lines"]
    }');
  end reference_schema;


  function openai_schema_of(p_schema in json_object_t) return json_object_t
  as
  begin
    return uc_ai_structured_output.to_openai_format(p_schema)
             .get_object('json_schema').get_object('schema');
  end openai_schema_of;


  function anthropic_schema_of(p_schema in json_object_t) return json_object_t
  as
  begin
    return uc_ai_structured_output.to_anthropic_format(p_schema)
             .get_object('format').get_object('schema');
  end anthropic_schema_of;


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


  /*
   * Measured on both /v1/responses and /v1/chat/completions: a schema carrying $schema,
   * title and description returns HTTP 200, and a description that says "ALWAYS render
   * in UPPER CASE" changes the answer. Removing them cost the user that instruction.
   */
  procedure openai_strict_keeps_metadata
  as
    l_schema json_object_t;
    l_name   json_object_t;
  begin
    l_schema := openai_schema_of(standard_schema);

    ut.expect(l_schema.get_string('$schema')).to_equal('https://json-schema.org/draft/2020-12/schema');
    ut.expect(l_schema.get_string('title')).to_equal('Person Data');
    ut.expect(l_schema.get_string('description')).to_equal('A person record');

    -- and inside each property (recursion)
    l_name := l_schema.get_object('properties').get_object('name');
    ut.expect(l_name.get_string('description')).to_equal('full name');
  end openai_strict_keeps_metadata;


  procedure openai_keyword_survival
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_node   json_object_t;
  begin
    l_schema := openai_schema_of(kitchen_schema);
    l_props  := l_schema.get_object('properties');

    -- root annotations
    ut.expect(l_schema.has('$schema')).to_be_true();
    ut.expect(l_schema.has('title')).to_be_true();
    ut.expect(l_schema.has('description')).to_be_true();

    -- string constraints: accepted, and maxLength is enforced by the provider
    l_node := l_props.get_object('text');
    ut.expect(l_node.has('title')).to_be_true();
    ut.expect(l_node.has('description')).to_be_true();
    ut.expect(l_node.get_number('minLength')).to_equal(2);
    ut.expect(l_node.get_number('maxLength')).to_equal(9);
    ut.expect(l_node.get_string('pattern')).to_equal('^[a-z]+$');
    ut.expect(l_node.get_string('format')).to_equal('email');
    ut.expect(l_node.has('default')).to_be_true();
    ut.expect(l_node.has('examples')).to_be_true();

    -- number constraints: all accepted
    l_node := l_props.get_object('num');
    ut.expect(l_node.get_number('minimum')).to_equal(0);
    ut.expect(l_node.get_number('maximum')).to_equal(10);
    ut.expect(l_node.get_number('exclusiveMinimum')).to_equal(-1);
    ut.expect(l_node.get_number('exclusiveMaximum')).to_equal(11);
    ut.expect(l_node.get_number('multipleOf')).to_equal(0.5);

    -- enum keeps its own value types
    ut.expect(l_props.get_object('count').get_array('enum').get_number(0)).to_equal(1);

    -- array constraints: minItems and maxItems accepted
    l_node := l_props.get_object('list');
    ut.expect(l_node.get_number('minItems')).to_equal(2);
    ut.expect(l_node.get_number('maxItems')).to_equal(7);
    ut.expect(l_node.get_object('items').get_number('maxLength')).to_equal(4);

    -- a union with null is the provider's own way of writing an optional field
    ut.expect(l_props.get_object('opt').get_array('type').get_size).to_equal(2);
  end openai_keyword_survival;


  /*
   * Measured HTTP 400: "'uniqueItems' is not permitted." and "'minProperties' is not
   * permitted." Those three are the whole strip list for this path.
   */
  procedure openai_strips_rejected_keywords
  as
    l_schema json_object_t;
    l_props  json_object_t;
  begin
    l_schema := openai_schema_of(kitchen_schema);
    l_props  := l_schema.get_object('properties');

    ut.expect(l_schema.has('minProperties')).to_be_false();
    ut.expect(l_schema.has('maxProperties')).to_be_false();
    ut.expect(l_props.get_object('list').has('uniqueItems')).to_be_false();
    ut.expect(l_props.get_object('child').has('minProperties')).to_be_false();
  end openai_strips_rejected_keywords;


  procedure openai_strict_additional_props
  as
    l_schema json_object_t;
    l_props  json_object_t;
  begin
    l_schema := openai_schema_of(nested_schema);

    ut.expect(l_schema.get_boolean('additionalProperties')).to_be_false();

    l_props := l_schema.get_object('properties');
    -- nested object property gets additionalProperties=false
    ut.expect(l_props.get_object('customer').get_boolean('additionalProperties')).to_be_false();
    -- non-object property does not
    ut.expect(l_props.get_object('lines').has('additionalProperties')).to_be_false();
  end openai_strict_additional_props;


  /*
   * Measured HTTP 400 for a partial list: "'required' is required to be supplied and to
   * be an array including every key in properties. Missing 'discount'."
   */
  procedure openai_strict_forces_all_required
  as
    l_schema json_object_t;
    l_req    json_array_t;
  begin
    l_schema := openai_schema_of(standard_schema);

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
    l_schema := openai_schema_of(nested_schema);

    l_items := l_schema.get_object('properties').get_object('lines').get_object('items');

    -- items object schema went through strict processing too
    ut.expect(l_items.get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_items.get_array('required').get_size).to_equal(2);
  end openai_strict_recurses_items;


  /*
   * Measured HTTP 400 before this recursion existed: an object inside $defs got neither
   * additionalProperties nor a completed required list, so the whole request failed.
   */
  procedure openai_strict_recurses_defs
  as
    l_schema json_object_t;
    l_line   json_object_t;
    l_addr   json_object_t;
  begin
    l_schema := openai_schema_of(reference_schema);

    l_line := l_schema.get_object('$defs').get_object('Line');
    ut.expect(l_line.get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_line.get_array('required').get_size).to_equal(2);
    -- a rejected keyword inside $defs is removed there too
    ut.expect(l_line.get_object('properties').get_object('qty').has('maxItems')).to_be_true();

    l_addr := l_schema.get_object('definitions').get_object('Addr');
    ut.expect(l_addr.get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_addr.get_array('required').get_size).to_equal(2);
  end openai_strict_recurses_defs;


  /*
   * Measured HTTP 400: "In context=('properties','payload','anyOf','0'),
   * 'additionalProperties' is required to be supplied and to be false."
   */
  procedure openai_strict_recurses_branches
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_branch json_object_t;
  begin
    l_schema := openai_schema_of(reference_schema);
    l_props  := l_schema.get_object('properties');

    l_branch := treat(l_props.get_object('payload').get_array('anyOf').get(0) as json_object_t);
    ut.expect(l_branch.get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_branch.get_array('required').get_size).to_equal(1);

    -- the non-object branch survives untouched
    ut.expect(l_props.get_object('payload').get_array('anyOf').get_size).to_equal(2);

    l_branch := treat(l_props.get_object('either').get_array('oneOf').get(0) as json_object_t);
    ut.expect(l_branch.get_boolean('additionalProperties')).to_be_false();

    l_branch := treat(l_props.get_object('both').get_array('allOf').get(0) as json_object_t);
    ut.expect(l_branch.get_boolean('additionalProperties')).to_be_false();
  end openai_strict_recurses_branches;


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
    l_input  json_object_t := kitchen_schema;
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_openai_format(l_input);

    ut.expect(l_input.get_string('title')).to_equal('Kitchen Sink');
    ut.expect(l_input.get_array('required').get_size).to_equal(1);
    ut.expect(l_input.get_number('minProperties')).to_equal(1);
    ut.expect(l_input.get_object('properties').get_object('list').get_boolean('uniqueItems')).to_be_true();
    ut.expect(l_input.get_object('properties').get_object('num').get_string('description')).to_equal('a number');
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


  /*
   * The live v1beta discovery document gives schemas.Schema 22 fields. A schema carrying
   * every one of them returns HTTP 200, so every one of them has to survive.
   */
  procedure google_keyword_survival
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_node   json_object_t;
  begin
    l_schema := uc_ai_structured_output.to_google_format(kitchen_schema);
    l_props  := l_schema.get_object('properties');

    -- root
    ut.expect(l_schema.get_string('title')).to_equal('Kitchen Sink');
    ut.expect(l_schema.get_string('description')).to_equal('Every keyword');
    ut.expect(l_schema.get_number('minProperties')).to_equal(1);
    ut.expect(l_schema.get_number('maxProperties')).to_equal(9);
    ut.expect(l_schema.has('propertyOrdering')).to_be_true();

    -- string node
    l_node := l_props.get_object('text');
    ut.expect(l_node.get_string('title')).to_equal('Text');
    ut.expect(l_node.get_number('minLength')).to_equal(2);
    ut.expect(l_node.get_number('maxLength')).to_equal(9);
    ut.expect(l_node.get_string('pattern')).to_equal('^[a-z]+$');
    ut.expect(l_node.get_string('format')).to_equal('email');
    ut.expect(l_node.get_string('default')).to_equal('x');

    -- number node
    l_node := l_props.get_object('num');
    ut.expect(l_node.get_number('minimum')).to_equal(0);
    ut.expect(l_node.get_number('maximum')).to_equal(10);

    -- enum
    ut.expect(l_props.get_object('count').has('enum')).to_be_true();

    -- array node
    l_node := l_props.get_object('list');
    ut.expect(l_node.get_number('minItems')).to_equal(2);
    ut.expect(l_node.get_number('maxItems')).to_equal(7);
    ut.expect(l_node.get_object('items').get_number('maxLength')).to_equal(4);

    -- nested object keeps its own required list and ordering
    l_node := l_props.get_object('child');
    ut.expect(l_node.get_number('minProperties')).to_equal(1);
    ut.expect(l_node.get_array('required').get_string(0)).to_equal('inner');
    ut.expect(l_node.get_array('propertyOrdering').get_string(0)).to_equal('inner');
  end google_keyword_survival;


  /*
   * Measured HTTP 400: 'Unknown name "additionalProperties" ... Cannot find field.'
   * Gemini rejects any field the proto does not have, so the conversion stays a
   * whitelist and these have to go.
   */
  procedure google_drops_non_proto_keys
  as
    l_schema json_object_t;
    l_props  json_object_t;
  begin
    l_schema := uc_ai_structured_output.to_google_format(kitchen_schema);
    l_props  := l_schema.get_object('properties');

    ut.expect(l_schema.has('$schema')).to_be_false();
    ut.expect(l_schema.has('additionalProperties')).to_be_false();

    -- examples is not a proto field; example is
    ut.expect(l_props.get_object('text').has('examples')).to_be_false();

    ut.expect(l_props.get_object('num').has('exclusiveMinimum')).to_be_false();
    ut.expect(l_props.get_object('num').has('exclusiveMaximum')).to_be_false();
    ut.expect(l_props.get_object('num').has('multipleOf')).to_be_false();
    ut.expect(l_props.get_object('list').has('uniqueItems')).to_be_false();
  end google_drops_non_proto_keys;


  /*
   * The proto wants propertyOrdering to name every property in schema order. Listing
   * only the required ones left an optional property with no fixed position.
   */
  procedure google_property_ordering
  as
    l_schema json_object_t := standard_schema;
    l_result json_object_t;
    l_order  json_array_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(l_schema);

    l_order := l_result.get_array('propertyOrdering');
    ut.expect(l_order.get_size).to_equal(3);
    ut.expect(l_order.get_string(0)).to_equal('name');
    ut.expect(l_order.get_string(1)).to_equal('age');
    ut.expect(l_order.get_string(2)).to_equal('tags');

    -- an ordering is emitted even when nothing is required
    l_schema.remove('required');
    l_result := uc_ai_structured_output.to_google_format(l_schema);
    ut.expect(l_result.get_array('propertyOrdering').get_size).to_equal(3);

    -- a node without properties gets no ordering
    l_result := uc_ai_structured_output.to_google_format(json_object_t('{"type":"string"}'));
    ut.expect(l_result.has('propertyOrdering')).to_be_false();
  end google_property_ordering;


  procedure google_keeps_author_ordering
  as
    l_schema json_object_t := standard_schema;
    l_result json_object_t;
  begin
    l_schema.put('propertyOrdering', json_array_t('["tags","name","age"]'));

    l_result := uc_ai_structured_output.to_google_format(l_schema);

    ut.expect(l_result.get_array('propertyOrdering').get_string(0)).to_equal('tags');
  end google_keeps_author_ordering;


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


  /*
   * Measured HTTP 400 for a number: "Invalid value at ... .enum[0] (TYPE_STRING), 1".
   * The proto types enum as an array of strings. Gemini still answers with the node's
   * own type, so a stringified enum keeps the constraint without breaking the request.
   */
  procedure google_enum_as_strings
  as
    l_result json_object_t;
    l_enum   json_array_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(kitchen_schema);

    l_enum := l_result.get_object('properties').get_object('count').get_array('enum');
    ut.expect(l_enum.get_size).to_equal(3);
    ut.expect(l_enum.get_string(0)).to_equal('1');
    ut.expect(l_enum.get_string(2)).to_equal('3');
  end google_enum_as_strings;


  /*
   * Measured HTTP 400: 'Unknown name "$defs"' and 'Unknown name "$ref"'. Dropping the
   * $ref used to leave an empty node, and Gemini then invented its own field names
   * ("quantity" instead of "qty"). The definition is written out in place instead.
   */
  procedure google_inlines_local_ref
  as
    l_result json_object_t;
    l_items  json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(reference_schema);

    ut.expect(l_result.has('$defs')).to_be_false();
    ut.expect(l_result.has('definitions')).to_be_false();

    l_items := l_result.get_object('properties').get_object('lines').get_object('items');
    ut.expect(l_items.has('$ref')).to_be_false();
    ut.expect(l_items.get_string('type')).to_equal('OBJECT');
    ut.expect(l_items.get_object('properties').get_object('sku').get_string('type')).to_equal('STRING');
    ut.expect(l_items.get_object('properties').get_object('qty').get_string('type')).to_equal('INTEGER');
  end google_inlines_local_ref;


  /*
   * nullable is the only way the proto expresses an optional value, so a JSON schema
   * union with null has to become one.
   */
  procedure google_union_becomes_nullable
  as
    l_result json_object_t;
    l_opt    json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(kitchen_schema);

    l_opt := l_result.get_object('properties').get_object('opt');
    ut.expect(l_opt.get_string('type')).to_equal('STRING');
    ut.expect(l_opt.get_boolean('nullable')).to_be_true();
  end google_union_becomes_nullable;


  procedure google_does_not_mutate_input
  as
    l_input  json_object_t := kitchen_schema;
    l_result json_object_t;
  begin
    l_result := uc_ai_structured_output.to_google_format(l_input);

    ut.expect(l_input.get_string('$schema')).to_equal('https://json-schema.org/draft/2020-12/schema');
    ut.expect(l_input.get_object('properties').get_object('count').get_array('enum').get_number(0)).to_equal(1);
    ut.expect(l_input.get_object('properties').get_object('num').get_number('multipleOf')).to_equal(0.5);
    ut.expect(l_input.get_object('properties').get_object('opt').get_array('type').get_size).to_equal(2);
  end google_does_not_mutate_input;


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

    l_schema := l_format.get_object('schema');
    -- title is accepted, so it stays
    ut.expect(l_schema.get_string('title')).to_equal('Person Data');
    -- measured HTTP 400 when missing: "'additionalProperties' must be explicitly set to false"
    ut.expect(l_schema.get_boolean('additionalProperties')).to_be_false();
  end anthropic_envelope;


  /*
   * Measured: a partial required list returns HTTP 200 on /v1/messages, and the model
   * then leaves the optional property out of its answer. Overwriting the list made
   * every property mandatory, which is not what the author wrote.
   */
  procedure anthropic_keeps_author_required
  as
    l_schema json_object_t;
    l_child  json_object_t;
  begin
    l_schema := anthropic_schema_of(kitchen_schema);

    ut.expect(l_schema.get_array('required').get_size).to_equal(1);
    ut.expect(l_schema.get_array('required').get_string(0)).to_equal('text');

    -- a nested object keeps its own list too
    l_child := l_schema.get_object('properties').get_object('child');
    ut.expect(l_child.get_array('required').get_size).to_equal(1);
    ut.expect(l_child.get_array('required').get_string(0)).to_equal('inner');

    -- a nested object with no required list does not get one invented
    ut.expect(anthropic_schema_of(reference_schema).get_object('$defs').get_object('Line')
      .has('required')).to_be_false();
  end anthropic_keeps_author_required;


  procedure anthropic_keyword_survival
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_node   json_object_t;
  begin
    l_schema := anthropic_schema_of(kitchen_schema);
    l_props  := l_schema.get_object('properties');

    -- root annotations are accepted
    ut.expect(l_schema.has('$schema')).to_be_true();
    ut.expect(l_schema.has('title')).to_be_true();
    ut.expect(l_schema.has('description')).to_be_true();

    -- minLength and maxLength return HTTP 200, so they are kept
    l_node := l_props.get_object('text');
    ut.expect(l_node.get_number('minLength')).to_equal(2);
    ut.expect(l_node.get_number('maxLength')).to_equal(9);
    ut.expect(l_node.get_string('pattern')).to_equal('^[a-z]+$');
    ut.expect(l_node.get_string('format')).to_equal('email');
    ut.expect(l_node.has('default')).to_be_true();
    ut.expect(l_node.has('examples')).to_be_true();
    ut.expect(l_node.get_string('title')).to_equal('Text');

    -- enum and a union with null are accepted
    ut.expect(l_props.get_object('count').has('enum')).to_be_true();
    ut.expect(l_props.get_object('opt').get_array('type').get_size).to_equal(2);

    -- descriptions carry instructions and are kept everywhere
    ut.expect(l_props.get_object('list').get_string('description')).to_be_like('a list%');
  end anthropic_keyword_survival;


  /*
   * Measured HTTP 400 for each of these, with the reason named by the provider:
   * "For 'number' type, properties maximum, minimum are not supported",
   * "properties exclusiveMaximum, exclusiveMinimum, multipleOf are not supported",
   * "For 'array' type, property 'maxItems' is not supported",
   * "property 'uniqueItems' is not supported",
   * "For 'object' type, property 'minProperties' is not supported".
   */
  procedure anthropic_strips_constraints
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_node   json_object_t;
  begin
    l_schema := anthropic_schema_of(kitchen_schema);
    l_props  := l_schema.get_object('properties');

    ut.expect(l_schema.has('minProperties')).to_be_false();
    ut.expect(l_schema.has('maxProperties')).to_be_false();

    l_node := l_props.get_object('num');
    ut.expect(l_node.has('minimum')).to_be_false();
    ut.expect(l_node.has('maximum')).to_be_false();
    ut.expect(l_node.has('exclusiveMinimum')).to_be_false();
    ut.expect(l_node.has('exclusiveMaximum')).to_be_false();
    ut.expect(l_node.has('multipleOf')).to_be_false();

    l_node := l_props.get_object('list');
    ut.expect(l_node.has('maxItems')).to_be_false();
    ut.expect(l_node.has('uniqueItems')).to_be_false();

    ut.expect(l_props.get_object('child').has('minProperties')).to_be_false();

    -- and inside a $defs entry
    ut.expect(anthropic_schema_of(reference_schema).get_object('$defs').get_object('Line')
      .get_object('properties').get_object('qty').has('maxItems')).to_be_false();
  end anthropic_strips_constraints;


  /*
   * Measured: minItems 0 and 1 return HTTP 200; 2 returns HTTP 400 "'minItems' values
   * other than 0 or 1 are not supported". Only a larger value is removed.
   */
  procedure anthropic_min_items_boundary
  as
    l_tags json_object_t;

    function tags_with(p_min_items in varchar2) return json_object_t
    as
    begin
      return anthropic_schema_of(json_object_t(
               '{"type":"object","properties":{"tags":{"type":"array","description":"the tags",'
               || '"items":{"type":"string"},"minItems":' || p_min_items || '}}}'
             )).get_object('properties').get_object('tags');
    end tags_with;
  begin
    l_tags := tags_with('0');
    ut.expect(l_tags.get_number('minItems')).to_equal(0);

    l_tags := tags_with('1');
    ut.expect(l_tags.get_number('minItems')).to_equal(1);

    l_tags := tags_with('2');
    ut.expect(l_tags.has('minItems')).to_be_false();
    ut.expect(l_tags.get_string('description')).to_be_like('%at least 2 items%');
  end anthropic_min_items_boundary;


  procedure anthropic_recurses_defs_and_anyof
  as
    l_schema json_object_t;
    l_branch json_object_t;
  begin
    l_schema := anthropic_schema_of(reference_schema);

    ut.expect(l_schema.get_object('$defs').get_object('Line')
      .get_boolean('additionalProperties')).to_be_false();
    ut.expect(l_schema.get_object('definitions').get_object('Addr')
      .get_boolean('additionalProperties')).to_be_false();

    l_branch := treat(l_schema.get_object('properties').get_object('payload')
                        .get_array('anyOf').get(0) as json_object_t);
    ut.expect(l_branch.get_boolean('additionalProperties')).to_be_false();
  end anthropic_recurses_defs_and_anyof;


  /*
   * A provider that cannot express a constraint still reads the description, so the
   * constraint is written there instead of being lost.
   */
  procedure constraint_folded_into_desc
  as
    l_num  json_object_t;
    l_list json_object_t;
  begin
    l_num := anthropic_schema_of(kitchen_schema).get_object('properties').get_object('num');

    ut.expect(l_num.get_string('description')).to_be_like('a number.%');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be at least 0.%');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be at most 10.%');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be greater than -1.%');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be less than 11.%');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be a multiple of 0.5.%');

    l_list := anthropic_schema_of(kitchen_schema).get_object('properties').get_object('list');
    ut.expect(l_list.get_string('description')).to_be_like('%Must have at most 7 items.%');
    ut.expect(l_list.get_string('description')).to_be_like('%All items must be unique.%');

    -- the OpenAI path folds the three keywords it has to remove
    l_list := openai_schema_of(kitchen_schema).get_object('properties').get_object('list');
    ut.expect(l_list.get_string('description')).to_be_like('%All items must be unique.%');

    -- Google folds the constraints the proto has no field for
    l_num := uc_ai_structured_output.to_google_format(kitchen_schema)
               .get_object('properties').get_object('num');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be a multiple of 0.5.%');
    ut.expect(l_num.get_string('description')).to_be_like('%Must be greater than -1.%');
  end constraint_folded_into_desc;


  procedure constraint_note_formatting
  as
    l_schema json_object_t;
    l_node   json_object_t;
  begin
    -- a description with no closing punctuation gets a full stop before the note
    l_schema := json_object_t('{"type":"object","properties":{
      "a":{"type":"number","description":"already ends.","minimum":1},
      "b":{"type":"number","description":"no full stop","minimum":2},
      "c":{"type":"number","minimum":0.01,"maximum":-0.5}}}');

    l_node := anthropic_schema_of(l_schema).get_object('properties');

    ut.expect(l_node.get_object('a').get_string('description')).to_equal('already ends. Must be at least 1.');
    ut.expect(l_node.get_object('b').get_string('description')).to_equal('no full stop. Must be at least 2.');
    -- a node with no description of its own gets only the note, and the leading zero
    -- of a fraction is kept on both signs
    ut.expect(l_node.get_object('c').get_string('description'))
      .to_equal('Must be at least 0.01. Must be at most -0.5.');
  end constraint_note_formatting;


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

    l_result := uc_ai_structured_output.to_anthropic_format(json_object_t())
                  .get_object('format').get_object('schema');
    ut.expect(l_result.get_size).to_equal(0);
  end empty_schema_handled;

end test_uc_ai_structured_output;
/
