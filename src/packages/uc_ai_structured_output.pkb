create or replace package body uc_ai_structured_output as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  /*
   * Provider behaviour recorded below was measured with live API calls, not read from
   * documentation. Every "rejected" entry is a real HTTP 400 and its message is quoted
   * next to the code that acts on it. Every "accepted" entry returned HTTP 200.
   *
   * The rule the package follows: remove a keyword only when the provider rejects it.
   * Descriptions, titles and author-supplied `required` lists carry instructions the
   * model obeys, so removing them changes the answer the user gets.
   */

  -- Keys of a JSON schema node whose value is itself a single schema.
  c_child_nodes constant apex_t_varchar2 := apex_t_varchar2(
    'items', 'not', 'contains', 'if', 'then', 'else', 'propertyNames'
  );

  -- Keys whose value is an array of schemas.
  c_child_arrays constant apex_t_varchar2 := apex_t_varchar2(
    'anyOf', 'oneOf', 'allOf', 'prefixItems'
  );

  -- Keys whose value is an object mapping names to schemas.
  c_child_maps constant apex_t_varchar2 := apex_t_varchar2(
    '$defs', 'definitions', 'patternProperties'
  );

  /*
   * Keywords OpenAI strict mode rejects that only constrain a value, so removing them
   * leaves the shape of the schema unchanged.
   */
  c_openai_strip constant apex_t_varchar2 := apex_t_varchar2(
    'uniqueItems', 'minProperties', 'maxProperties'
  );

  /*
   * Keywords Anthropic rejects. minItems is added to this list at run time, and only
   * when its value is above 1, because 0 and 1 are accepted.
   */
  c_anthropic_strip constant apex_t_varchar2 := apex_t_varchar2(
    'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum', 'multipleOf'
  , 'maxItems', 'uniqueItems', 'minProperties', 'maxProperties'
  );

  /*
   * Constraints the Gemini Schema proto has no field for, so the whitelist below cannot
   * carry them.
   */
  c_google_strip constant apex_t_varchar2 := apex_t_varchar2(
    'exclusiveMinimum', 'exclusiveMaximum', 'multipleOf', 'uniqueItems'
  );

  -- How deep a chain of local $ref pointers the Google conversion follows.
  c_max_ref_depth constant pls_integer := 25;

  /*
   * Gemini validates `responseSchema` against the Schema proto and rejects any field
   * the proto does not have ("Unknown name ... Cannot find field"), so the Google
   * conversion has to be a whitelist. The list below is the complete set of Schema
   * fields in the live v1beta discovery document, minus the five handled separately
   * (type, enum, properties, items, anyOf).
   */
  c_google_keys constant apex_t_varchar2 := apex_t_varchar2(
    'format', 'title', 'description', 'nullable', 'default', 'example'
  , 'pattern', 'minimum', 'maximum', 'minLength', 'maxLength', 'minItems', 'maxItems'
  , 'minProperties', 'maxProperties', 'required', 'propertyOrdering'
  );

  /*
   * What one provider family needs done to a schema. Both members of the family that
   * need rewriting (the OpenAI strict path and Anthropic) share one recursion, so a
   * schema nested in $defs or anyOf is treated the same as one under properties.
   */
  type t_policy is record (
    -- overwrite `required` with every property name of the node
    force_all_required boolean
    -- add additionalProperties: false to every object node
  , close_objects      boolean
    -- remove the keywords OpenAI strict mode rejects
  , strip_openai       boolean
    -- remove the keywords Anthropic rejects
  , strip_anthropic    boolean
    -- append a plain-language note about a removed constraint to the node description
  , describe_stripped  boolean
  );

  /*
   * OpenAI Chat Completions and the Responses API, and therefore also xAI, OpenRouter,
   * Mistral and Ollama on their default routes.
   *
   * Measured: a partial `required` is rejected ("'required' is required to be supplied
   * and to be an array including every key in properties"), a missing
   * additionalProperties is rejected, and `uniqueItems`, `minProperties` and
   * `maxProperties` are "not permitted". Descriptions, titles, $schema, enum, pattern,
   * format, minimum, maximum, multipleOf, minLength, maxLength, minItems, maxItems,
   * default, examples and const are all accepted.
   */
  function openai_policy return t_policy
  as
    l_policy t_policy;
  begin
    l_policy.force_all_required := true;
    l_policy.close_objects      := true;
    l_policy.strip_openai       := true;
    l_policy.strip_anthropic    := false;
    l_policy.describe_stripped  := true;
    return l_policy;
  end openai_policy;

  /*
   * Anthropic output_config.format.
   *
   * Measured: a partial `required` is accepted, so the author's list is kept. A missing
   * additionalProperties is rejected. Number constraints, maxItems, uniqueItems,
   * minProperties and maxProperties are rejected with a named reason. minLength,
   * maxLength, enum, pattern, format, default, examples, title and $schema are accepted.
   */
  function anthropic_policy return t_policy
  as
    l_policy t_policy;
  begin
    l_policy.force_all_required := false;
    l_policy.close_objects      := true;
    l_policy.strip_openai       := false;
    l_policy.strip_anthropic    := true;
    l_policy.describe_stripped  := true;
    return l_policy;
  end anthropic_policy;

  /*
   * ==========================================================================
   * fix 4: constraint notes.
   *
   * A provider that cannot express a constraint still reads the description, so the
   * three functions below turn a constraint the converter has to remove into a short
   * sentence and append it. Anthropic's own schema transformation does the same.
   *
   * This is the only part of the package that edits text the author wrote. Setting
   * describe_stripped to false in openai_policy and anthropic_policy, and deleting the
   * described() call in convert_schema_to_google, turns it off completely.
   * ==========================================================================
   */

  /*
   * Shortest readable text for a schema constraint value, independent of the session's
   * decimal separator. to_char with TM9 drops the leading zero of a fraction, so 0.01
   * would read ".01"; put it back.
   */
  function number_text(p_value in number) return varchar2
  as
    l_text varchar2(100 char);
  begin
    l_text := trim(to_char(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    return case
      when l_text like '.%'  then '0' || l_text
      when l_text like '-.%' then '-0' || substr(l_text, 2)
      else l_text
    end;
  end number_text;

  /*
   * The sentence for one constraint, or null when the node does not carry it.
   */
  function constraint_note(
    p_schema in json_object_t
  , p_key    in varchar2
  ) return varchar2
  as
    l_value varchar2(100 char);
  begin
    if not p_schema.has(p_key) then
      return null;
    end if;

    l_value := number_text(p_schema.get_number(p_key));

    return case p_key
      when 'minimum'          then 'Must be at least ' || l_value || '.'
      when 'maximum'          then 'Must be at most ' || l_value || '.'
      when 'exclusiveMinimum' then 'Must be greater than ' || l_value || '.'
      when 'exclusiveMaximum' then 'Must be less than ' || l_value || '.'
      when 'multipleOf'       then 'Must be a multiple of ' || l_value || '.'
      when 'minItems'         then 'Must have at least ' || l_value || ' items.'
      when 'maxItems'         then 'Must have at most ' || l_value || ' items.'
      when 'minLength'        then 'Must be at least ' || l_value || ' characters long.'
      when 'maxLength'        then 'Must be at most ' || l_value || ' characters long.'
      when 'minProperties'    then 'Must have at least ' || l_value || ' properties.'
      when 'maxProperties'    then 'Must have at most ' || l_value || ' properties.'
      when 'uniqueItems'      then
        case when nvl(p_schema.get_boolean(p_key), false) then 'All items must be unique.' else null end
      else null
    end;
  end constraint_note;

  /*
   * The sentences for a list of constraints, in the order given.
   */
  function constraint_notes(
    p_schema in json_object_t
  , p_keys   in apex_t_varchar2
  ) return varchar2
  as
    l_notes varchar2(4000 char);
    l_note varchar2(200 char);
  begin
    <<note_loop>>
    for i in 1 .. p_keys.count loop
      l_note := constraint_note(p_schema, p_keys(i));
      if l_note is not null then
        l_notes := l_notes || case when l_notes is not null then ' ' end || l_note;
      end if;
    end loop note_loop;

    return l_notes;
  end constraint_notes;

  /*
   * The node's description with the notes appended, or null when there is nothing to
   * add. Reading the description as a CLOB keeps a very long one from raising, and a
   * description that no longer leaves room for the notes is returned unchanged as null.
   */
  function described(
    p_schema in json_object_t
  , p_notes  in varchar2
  ) return varchar2
  as
    l_description clob;
    l_text varchar2(32767 char);
  begin
    if p_notes is null then
      return null;
    end if;

    l_description := p_schema.get_clob('description');
    if nvl(sys.dbms_lob.getlength(l_description), 0) + length(p_notes) >= 30000 then
      return null;
    end if;

    l_text := sys.dbms_lob.substr(l_description, 30000, 1);

    -- Start a new sentence, so the note never runs into the author's last word.
    if l_text is not null and substr(l_text, -1) not in ('.', '!', '?', ':', ';') then
      l_text := l_text || '.';
    end if;

    return ltrim(l_text || ' ' || p_notes);
  end described;

  /*
   * Convert JSON schema type from standard format to Google format
   * Standard: "string", "number", "integer", "boolean", "array", "object"
   * Google: "STRING", "NUMBER", "INTEGER", "BOOLEAN", "ARRAY", "OBJECT"
   */
  function convert_type_to_google(p_type in varchar2) return varchar2
  as
  begin
    return case upper(p_type)
      when 'STRING' then 'STRING'
      when 'NUMBER' then 'NUMBER'
      when 'INTEGER' then 'INTEGER'
      when 'BOOLEAN' then 'BOOLEAN'
      when 'ARRAY' then 'ARRAY'
      when 'OBJECT' then 'OBJECT'
      else upper(p_type)
    end;
  end convert_type_to_google;

  /*
   * Recursively convert a JSON schema object to Google format.
   *
   * Rebuilds the node from the whitelist above because Gemini rejects unknown fields.
   * A union type such as ["string","null"] becomes a single type plus nullable: true,
   * which is how the proto expresses an optional value.
   *
   * p_root carries the root schema so that a local $ref can be resolved and written out
   * in place. Gemini rejects both $ref and $defs, and a dropped $ref used to leave an
   * empty node behind, which made the model invent its own field names.
   */
  function convert_schema_to_google(
    p_schema in json_object_t
  , p_root   in json_object_t
  , p_depth  in pls_integer default 0
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_schema_to_google';
    l_google_schema json_object_t := json_object_t();
    l_properties json_object_t;
    l_google_properties json_object_t := json_object_t();
    l_items json_object_t;
    l_any_of json_array_t;
    l_google_any_of json_array_t;
    l_ordering json_array_t;
    l_type_arr json_array_t;
    l_elem json_element_t;
    l_property_name_arr json_key_list;
    l_property_name varchar2(4000 char);
    l_property_value json_object_t;
    l_key varchar2(4000 char);
    l_type varchar2(100 char);
    l_ref varchar2(4000 char);
    l_target json_object_t;
    l_enum json_array_t;
    l_google_enum json_array_t;
    l_enum_value varchar2(4000 char);
    l_notes varchar2(32767 char);
    l_nullable boolean := false;
  begin
    uc_ai_logger.log('Converting schema to Google format', l_scope);

    -- Resolve a local $ref against the root and convert the node it points at. Only the
    -- pointer forms JSON Schema uses for a local definition are followed; anything else
    -- (a URL, a deep pointer) is left to fall through to the whitelist, which drops it.
    if p_schema.has('$ref') and p_depth < c_max_ref_depth then
      l_ref := p_schema.get_string('$ref');
      if l_ref like '#/$defs/%' then
        l_target := p_root.get_object('$defs');
        l_key := substr(l_ref, length('#/$defs/') + 1);
      elsif l_ref like '#/definitions/%' then
        l_target := p_root.get_object('definitions');
        l_key := substr(l_ref, length('#/definitions/') + 1);
      end if;

      if l_target is not null and l_target.has(l_key) then
        return convert_schema_to_google(l_target.get_object(l_key), p_root, p_depth + 1);
      end if;
    end if;

    -- Every whitelisted field the author supplied is copied over untouched. Copying the
    -- raw element keeps `default`, `example` and `enum` at whatever type they have.
    <<whitelist_loop>>
    for i in 1 .. c_google_keys.count loop
      l_key := c_google_keys(i);
      if p_schema.has(l_key) then
        l_google_schema.put(l_key, p_schema.get(l_key));
      end if;
    end loop whitelist_loop;

    -- Convert type. An array of types is a JSON Schema union; Gemini has one type field.
    if p_schema.has('type') then
      l_type_arr := p_schema.get_array('type');
      if l_type_arr is not null then
        <<type_union_loop>>
        for i in 0 .. l_type_arr.get_size - 1 loop
          if lower(l_type_arr.get_string(i)) = 'null' then
            l_nullable := true;
          elsif l_type is null then
            l_type := l_type_arr.get_string(i);
          end if;
        end loop type_union_loop;
      else
        l_type := p_schema.get_string('type');
      end if;

      if l_type is not null then
        l_google_schema.put('type', convert_type_to_google(l_type));
      end if;
      if l_nullable and not l_google_schema.has('nullable') then
        l_google_schema.put('nullable', true);
      end if;
    end if;

    -- Convert enum. The proto types this field as an array of strings and rejects a
    -- number: "Invalid value at ... .enum[0] (TYPE_STRING), 1". Rendering every value as
    -- a string is accepted on INTEGER, NUMBER and BOOLEAN nodes as well, and the model
    -- still answers with the node's own type.
    if p_schema.has('enum') then
      l_enum := p_schema.get_array('enum');
      if l_enum is not null then
        l_google_enum := json_array_t();
        <<enum_loop>>
        for i in 0 .. l_enum.get_size - 1 loop
          l_enum_value := l_enum.get_string(i);
          if l_enum_value is null then
            l_enum_value := trim(both '"' from l_enum.get(i).to_string);
          end if;
          l_google_enum.append(l_enum_value);
        end loop enum_loop;
        l_google_schema.put('enum', l_google_enum);
      end if;
    end if;

    -- Convert properties for object types
    if p_schema.has('properties') then
      l_properties := p_schema.get_object('properties');
      l_property_name_arr := l_properties.get_keys();

      <<property_loop>>
      for i in 1 .. l_property_name_arr.count loop
        l_property_name := l_property_name_arr(i);
        l_property_value := l_properties.get_object(l_property_name);
        l_google_properties.put(
          l_property_name
        , convert_schema_to_google(l_property_value, p_root, p_depth + 1)
        );
      end loop property_loop;

      l_google_schema.put('properties', l_google_properties);

      -- propertyOrdering fixes the order the model emits keys in. The proto wants every
      -- property, not only the required ones, so an optional property is ordered too.
      -- An author-supplied ordering came through the whitelist loop and is kept.
      if not l_google_schema.has('propertyOrdering') then
        l_ordering := json_array_t();
        <<ordering_loop>>
        for i in 1 .. l_property_name_arr.count loop
          l_ordering.append(l_property_name_arr(i));
        end loop ordering_loop;
        l_google_schema.put('propertyOrdering', l_ordering);
      end if;
    end if;

    -- Convert items for array types
    if p_schema.has('items') then
      l_items := p_schema.get_object('items');
      if l_items is not null then
        l_google_schema.put('items', convert_schema_to_google(l_items, p_root, p_depth + 1));
      end if;
    end if;

    -- Convert anyOf branches
    if p_schema.has('anyOf') then
      l_any_of := p_schema.get_array('anyOf');
      if l_any_of is not null then
        l_google_any_of := json_array_t();
        <<any_of_loop>>
        for i in 0 .. l_any_of.get_size - 1 loop
          l_elem := l_any_of.get(i);
          if l_elem.is_object then
            l_google_any_of.append(
              convert_schema_to_google(treat(l_elem as json_object_t), p_root, p_depth + 1)
            );
          end if;
        end loop any_of_loop;
        l_google_schema.put('anyOf', l_google_any_of);
      end if;
    end if;

    -- The proto has no field for these four, so record them in the description instead.
    -- ---- fix 4: delete this block to stop the package editing the author's text.
    l_notes := described(l_google_schema, constraint_notes(p_schema, c_google_strip));
    if l_notes is not null then
      l_google_schema.put('description', l_notes);
    end if;

    return l_google_schema;
  end convert_schema_to_google;

  /*
   * Recursively rewrite a schema for one provider family.
   *
   * Descends into properties, items, $defs, definitions, patternProperties and the
   * anyOf / oneOf / allOf branches, so an object nested anywhere gets the same treatment
   * as one at the root. Both OpenAI and Anthropic reject a nested object that has no
   * additionalProperties, and both check constraints inside $defs.
   */
  function process_schema(
    p_schema in json_object_t
  , p_policy in t_policy
  ) return json_object_t
  as
    l_result json_object_t;
    l_properties json_object_t;
    l_processed_properties json_object_t := json_object_t();
    l_child json_object_t;
    l_map json_object_t;
    l_processed_map json_object_t;
    l_arr json_array_t;
    l_processed_arr json_array_t;
    l_required_array json_array_t;
    l_elem json_element_t;
    l_property_name_arr json_key_list;
    l_map_key_arr json_key_list;
    l_property_name varchar2(4000 char);
    l_key varchar2(4000 char);
    l_type varchar2(100 char);
    l_notes varchar2(4000 char);
    l_description varchar2(32767 char);
    l_strip apex_t_varchar2 := apex_t_varchar2();
  begin
    -- work on a copy, so the caller's schema is never changed
    l_result := json_object_t(p_schema.to_clob);

    if p_policy.strip_openai then
      -- Measured HTTP 400: "In context=('properties','tags'), 'uniqueItems' is not
      -- permitted." and "In context=(), 'minProperties' is not permitted."
      -- oneOf, allOf and not are rejected too but are structural, so removing them
      -- would change what the schema means. They are left for the caller to fix.
      l_strip := c_openai_strip;
    elsif p_policy.strip_anthropic then
      -- Measured HTTP 400: "For 'number' type, properties maximum, minimum are not
      -- supported", "properties exclusiveMaximum, exclusiveMinimum, multipleOf are not
      -- supported", "For 'array' type, property 'maxItems' is not supported",
      -- "property 'uniqueItems' is not supported" and "For 'object' type, property
      -- 'minProperties' is not supported".
      -- minLength and maxLength are accepted and are therefore kept.
      l_strip := c_anthropic_strip;

      -- Measured HTTP 400: "'minItems' values other than 0 or 1 are not supported".
      -- 0 and 1 are accepted, so only a larger value has to go.
      if nvl(l_result.get_number('minItems'), 0) > 1 then
        l_strip.extend;
        l_strip(l_strip.count) := 'minItems';
      end if;
    end if;

    if p_policy.describe_stripped then
      l_notes := constraint_notes(l_result, l_strip);
    end if;

    <<strip_loop>>
    for i in 1 .. l_strip.count loop
      l_result.remove(l_strip(i));
    end loop strip_loop;

    l_description := described(l_result, l_notes);
    if l_description is not null then
      l_result.put('description', l_description);
    end if;

    -- Add additionalProperties: false for object types.
    -- Measured HTTP 400 on both providers when it is missing:
    -- "For 'object' type, 'additionalProperties' must be explicitly set to false".
    if p_policy.close_objects and l_result.has('type') then
      l_type := l_result.get_string('type');
      if l_type = 'object' then
        l_result.put('additionalProperties', false);
      end if;
    end if;

    -- Process nested properties
    if l_result.has('properties') then
      l_properties := l_result.get_object('properties');
      l_property_name_arr := l_properties.get_keys();

      <<property_loop>>
      for i in 1 .. l_property_name_arr.count loop
        l_property_name := l_property_name_arr(i);
        l_processed_properties.put(
          l_property_name
        , process_schema(l_properties.get_object(l_property_name), p_policy)
        );
      end loop property_loop;

      l_result.put('properties', l_processed_properties);

      -- OpenAI rejects a partial list: "'required' is required to be supplied and to be
      -- an array including every key in properties." Anthropic accepts a partial list,
      -- so the author's own list survives there.
      if p_policy.force_all_required then
        l_required_array := json_array_t();
        <<required_loop>>
        for i in 1 .. l_property_name_arr.count loop
          l_required_array.append(l_property_name_arr(i));
        end loop required_loop;

        l_result.put('required', l_required_array);
      end if;
    end if;

    -- Process single nested schemas (items, not, contains, ...)
    <<child_node_loop>>
    for i in 1 .. c_child_nodes.count loop
      l_key := c_child_nodes(i);
      if l_result.has(l_key) then
        l_child := l_result.get_object(l_key);
        if l_child is not null then
          l_result.put(l_key, process_schema(l_child, p_policy));
        end if;
      end if;
    end loop child_node_loop;

    -- Process arrays of schemas (anyOf, oneOf, allOf, prefixItems)
    <<child_array_loop>>
    for i in 1 .. c_child_arrays.count loop
      l_key := c_child_arrays(i);
      if l_result.has(l_key) then
        l_arr := l_result.get_array(l_key);
        if l_arr is not null then
          l_processed_arr := json_array_t();
          <<branch_loop>>
          for j in 0 .. l_arr.get_size - 1 loop
            l_elem := l_arr.get(j);
            if l_elem.is_object then
              l_processed_arr.append(process_schema(treat(l_elem as json_object_t), p_policy));
            else
              l_processed_arr.append(l_elem);
            end if;
          end loop branch_loop;
          l_result.put(l_key, l_processed_arr);
        end if;
      end if;
    end loop child_array_loop;

    -- Process named schema maps ($defs, definitions, patternProperties)
    <<child_map_loop>>
    for i in 1 .. c_child_maps.count loop
      l_key := c_child_maps(i);
      if l_result.has(l_key) then
        l_map := l_result.get_object(l_key);
        if l_map is not null then
          l_processed_map := json_object_t();
          l_map_key_arr := l_map.get_keys();
          <<definition_loop>>
          for j in 1 .. l_map_key_arr.count loop
            l_processed_map.put(
              l_map_key_arr(j)
            , process_schema(l_map.get_object(l_map_key_arr(j)), p_policy)
            );
          end loop definition_loop;
          l_result.put(l_key, l_processed_map);
        end if;
      end if;
    end loop child_map_loop;

    return l_result;
  end process_schema;

  /*
   * Convert a standard JSON schema to OpenAI format for structured output
   */
  function to_openai_format(
    p_schema in json_object_t,
    p_strict in boolean default true
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'to_openai_format';
    l_response_format json_object_t := json_object_t();
    l_schema_copy json_object_t;
    l_json_schema json_object_t;
    l_name varchar2(4000 char) := 'structured_output';
  begin
    uc_ai_logger.log('Converting schema to OpenAI format', l_scope, ' Strict: ' || case when p_strict then 'true' else 'false' end);

    if p_schema.has('title') then
      l_name := replace(p_schema.get_string('title'), ' ', '_');
      -- make it match [a-zA-Z0-9_-]+
      l_name := regexp_replace(l_name, '[^a-zA-Z0-9_-]', null);
      l_name := coalesce(l_name, 'structured_output');
    end if;

    -- Create a copy of the input schema and process for strict mode
    if p_strict then
      l_schema_copy := process_schema(p_schema, openai_policy);
    else
      l_schema_copy := json_object_t(p_schema.to_clob);
    end if;

    l_response_format.put('type', 'json_schema');

    l_json_schema := json_object_t();
    l_json_schema.put('name', l_name);
    l_json_schema.put('schema', l_schema_copy);
    l_json_schema.put('strict', p_strict);

    l_response_format.put('json_schema', l_json_schema);

    uc_ai_logger.log('OpenAI format conversion complete', l_scope, l_response_format.to_clob);
    return l_response_format;
  end to_openai_format;

  /*
   * Convert a standard JSON schema to Google Gemini format for structured output
   */
  function to_google_format(
    p_schema in json_object_t
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'to_google_format';
  begin
    uc_ai_logger.log('Converting schema to Google format', l_scope);
    return convert_schema_to_google(p_schema, p_root => p_schema);
  end to_google_format;

  /*
   * Convert a standard JSON schema to Ollama format for structured output
   */
  function to_ollama_format(
    p_schema in json_object_t
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'to_ollama_format';
    l_schema_copy json_object_t;
  begin
    uc_ai_logger.log('Converting schema to Ollama format', l_scope);

    -- Ollama uses the schema directly, just make a clean copy
    l_schema_copy := json_object_t(p_schema.to_clob);

    -- Remove metadata that Ollama doesn't need
    l_schema_copy.remove('$schema');
    l_schema_copy.remove('title');
    -- Keep description as Ollama can use it

    return l_schema_copy;
  end to_ollama_format;

  /*
   * Convert a standard JSON schema to Anthropic format for structured output
   * Anthropic uses output_config: { format: { type: "json_schema", schema: {...} } }
   */
  function to_anthropic_format(
    p_schema in json_object_t
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'to_anthropic_format';
    l_output_config json_object_t := json_object_t();
    l_format json_object_t := json_object_t();
    l_schema_copy json_object_t;
  begin
    uc_ai_logger.log('Converting schema to Anthropic format', l_scope);

    -- One pass closes every object and removes only what Anthropic rejects. The
    -- author's `required` list is kept, because a partial list is accepted.
    l_schema_copy := process_schema(p_schema, anthropic_policy);

    l_format.put('type', 'json_schema');
    l_format.put('schema', l_schema_copy);

    l_output_config.put('format', l_format);

    uc_ai_logger.log('Anthropic format conversion complete', l_scope, l_output_config.to_clob);
    return l_output_config;
  end to_anthropic_format;

 /*
   * Convert a standard JSON schema to Responses API format for structured output
   */
  function to_responses_api_format(
    p_schema in json_object_t,
    p_strict in boolean default true
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'to_responses_api_format';
    l_response_format json_object_t := json_object_t();
    l_schema_copy json_object_t;
    l_name varchar2(4000 char) := 'structured_output';
  begin
    uc_ai_logger.log('Converting schema to Responses API format', l_scope, ' Strict: ' || case when p_strict then 'true' else 'false' end);

    if p_schema.has('title') then
      l_name := replace(p_schema.get_string('title'), ' ', '_');
      -- make it match [a-zA-Z0-9_-]+
      l_name := regexp_replace(l_name, '[^a-zA-Z0-9_-]', null);
      l_name := coalesce(l_name, 'structured_output');
    end if;

    -- Create a copy of the input schema and process for strict mode
    if p_strict then
      l_schema_copy := process_schema(p_schema, openai_policy);
    else
      l_schema_copy := json_object_t(p_schema.to_clob);
    end if;

    l_response_format.put('type', 'json_schema');
    l_response_format.put('name', l_name);
    l_response_format.put('strict', p_strict);
    l_response_format.put('schema', l_schema_copy);

    uc_ai_logger.log('Responses API format conversion complete', l_scope, l_response_format.to_clob);
    return l_response_format;
  end to_responses_api_format;


  /*
   * Generic function to convert schema based on provider
   */
  function format_schema(
    p_schema in json_object_t,
    p_provider in uc_ai.provider_type,
    p_strict in boolean default true
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'format_schema';
    l_result json_object_t;
  begin
    uc_ai_logger.log('Formatting schema for provider: ' || p_provider, l_scope);

    case p_provider
      when uc_ai.c_provider_openai then
        l_result := to_openai_format(p_schema, p_strict);
      when uc_ai.c_provider_google then
        l_result := to_google_format(p_schema);
      when uc_ai.c_provider_ollama then
        l_result := to_ollama_format(p_schema);
      when uc_ai.c_provider_anthropic then
        l_result := to_anthropic_format(p_schema);
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_structured_unsupported
        , p_scope      => l_scope
        , p0           => p_provider
        );
    end case;

    return l_result;
  end format_schema;

end uc_ai_structured_output;
/
