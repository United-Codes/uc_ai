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

  -- Keys whose branches the Gemini conversion collects into one anyOf, in this order.
  c_branch_keys constant apex_t_varchar2 := apex_t_varchar2('anyOf', 'oneOf');

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
   * Structural keywords both strict decoders reject. Every one is a measured HTTP 400:
   *   Anthropic: "Schema keyword 'not' is not supported",
   *              "For 'array' type, property 'contains' is not supported",
   *              "For 'object' type, property 'if' is not supported",
   *              "For 'object' type, property 'propertyNames' is not supported".
   *   OpenAI:    "Unsupported keywords ('not',)", "'contains' is not permitted",
   *              "'if' is not permitted", "'propertyNames' is not permitted".
   * then and else only mean something next to an if, so they go with it.
   */
  c_structural_strip constant apex_t_varchar2 := apex_t_varchar2(
    'not', 'contains', 'if', 'then', 'else', 'propertyNames'
  );

  /*
   * The string formats each decoder accepts. A value outside the list is a measured
   * HTTP 400: OpenAI "'phone' is not a valid format" and "'uri' is not a valid format",
   * Anthropic "For 'string' type, format 'phone' is not supported". uuid and email
   * return HTTP 200 on both, and uri returns HTTP 200 on Anthropic - which is why the
   * two lists differ. The remaining entries are the ones the reference SDK keeps
   * (sanitize-json-schema.ts:4-15) and were not measured one by one.
   */
  c_openai_formats constant apex_t_varchar2 := apex_t_varchar2(
    'date-time', 'time', 'date', 'duration', 'email', 'hostname', 'ipv4', 'ipv6', 'uuid'
  );

  c_anthropic_formats constant apex_t_varchar2 := apex_t_varchar2(
    'date-time', 'time', 'date', 'duration', 'email', 'hostname', 'uri', 'ipv4', 'ipv6', 'uuid'
  );

  /*
   * Constraints the Gemini Schema proto has no field for, so the whitelist below cannot
   * carry them.
   */
  c_google_strip constant apex_t_varchar2 := apex_t_varchar2(
    'exclusiveMinimum', 'exclusiveMaximum', 'multipleOf', 'uniqueItems'
  );

  /*
   * How many $ref hops the Google conversion follows on one path. Only a hop through a
   * $ref counts: the limit used to be charged for every descent into properties, items
   * or anyOf as well, so a shallow schema with a handful of definitions reached it and
   * the conversion stopped in the middle of a node.
   */
  c_max_ref_depth constant pls_integer := 25;

  /*
   * How much of a nested schema is written into a description note. Long enough for the
   * shapes `not`, `if` and `contains` carry in practice, short enough that the note
   * cannot crowd out the description the author wrote.
   */
  c_note_schema_length constant pls_integer := 500;

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
    -- remove c_structural_strip and rewrite a tuple as one items node
  , strip_structural   boolean
    -- the string formats this provider accepts; null keeps every format
  , allowed_formats    apex_t_varchar2
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
   * minimum, maximum, multipleOf, minLength, maxLength, minItems, maxItems, default,
   * examples and const are all accepted. A format outside c_openai_formats and every
   * keyword in c_structural_strip are rejected.
   */
  function openai_policy return t_policy
  as
    l_policy t_policy;
  begin
    l_policy.force_all_required := true;
    l_policy.close_objects      := true;
    l_policy.strip_openai       := true;
    l_policy.strip_anthropic    := false;
    l_policy.strip_structural   := true;
    l_policy.allowed_formats    := c_openai_formats;
    l_policy.describe_stripped  := true;
    return l_policy;
  end openai_policy;

  /*
   * Anthropic output_config.format.
   *
   * Measured: a partial `required` is accepted, so the author's list is kept. A missing
   * additionalProperties is rejected. Number constraints, maxItems, uniqueItems,
   * minProperties and maxProperties are rejected with a named reason. minLength,
   * maxLength, enum, pattern, default, examples, title and $schema are accepted. A
   * format outside c_anthropic_formats and every keyword in c_structural_strip are
   * rejected, each with its own named reason.
   */
  function anthropic_policy return t_policy
  as
    l_policy t_policy;
  begin
    l_policy.force_all_required := false;
    l_policy.close_objects      := true;
    l_policy.strip_openai       := false;
    l_policy.strip_anthropic    := true;
    l_policy.strip_structural   := true;
    l_policy.allowed_formats    := c_anthropic_formats;
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
   * Two notes in one sentence sequence, either of which may be missing.
   */
  function join_notes(
    p_first  in varchar2
  , p_second in varchar2
  ) return varchar2
  as
  begin
    return case
      when p_first is null then p_second
      when p_second is null then p_first
      else p_first || ' ' || p_second
    end;
  end join_notes;

  /*
   * Whether a list holds the given value.
   */
  function in_list(
    p_list  in apex_t_varchar2
  , p_value in varchar2
  ) return boolean
  as
  begin
    <<list_loop>>
    for i in 1 .. p_list.count loop
      if p_list(i) = p_value then
        return true;
      end if;
    end loop list_loop;

    return false;
  end in_list;

  /*
   * The nested schema under p_key as JSON text, cut to c_note_schema_length, or null
   * when the key is missing or does not carry a schema object.
   */
  function schema_text(
    p_schema in json_object_t
  , p_key    in varchar2
  ) return varchar2
  as
    l_child json_object_t;
  begin
    l_child := p_schema.get_object(p_key);
    if l_child is null then
      return null;
    end if;

    return sys.dbms_lob.substr(l_child.to_clob, c_note_schema_length, 1);
  end schema_text;

  /*
   * ==========================================================================
   * Structural keywords no target can carry.
   *
   * not, contains, if/then/else and propertyNames state a rule about the value, not a
   * shape. The Gemini Schema proto has no field for them, and both strict decoders
   * answer HTTP 400 when they are sent (see c_structural_strip). They used to be
   * dropped without a word. The model reads the description, so the rule is written
   * there instead - the same trade the constraint notes above make for minimum,
   * maximum and the rest.
   * ==========================================================================
   */
  function structural_notes(p_schema in json_object_t) return varchar2
  as
    l_notes varchar2(4000 char);
    l_text  varchar2(1000 char);
  begin
    l_text := schema_text(p_schema, 'not');
    if l_text is not null then
      l_notes := join_notes(l_notes, 'The value must not match this JSON schema: ' || l_text || '.');
    end if;

    l_text := schema_text(p_schema, 'contains');
    if l_text is not null then
      l_notes := join_notes(l_notes, 'At least one item must match this JSON schema: ' || l_text || '.');
    end if;

    l_text := schema_text(p_schema, 'if');
    if l_text is not null then
      l_notes := join_notes(
        l_notes
      , 'A rule applies to this value: when it matches ' || l_text
        || ' it must also match ' || nvl(schema_text(p_schema, 'then'), 'any schema')
        || ', and when it does not it must match ' || nvl(schema_text(p_schema, 'else'), 'any schema') || '.'
      );
    end if;

    l_text := schema_text(p_schema, 'propertyNames');
    if l_text is not null then
      l_notes := join_notes(l_notes, 'Every property name must match this JSON schema: ' || l_text || '.');
    end if;

    return l_notes;
  end structural_notes;

  /*
   * Flatten one converted allOf branch into the node being built.
   *
   * allOf means every branch applies at once. The proto has no allOf field, so the
   * branches are merged into the parent. The parent's own value wins on a conflict,
   * which is how the reference converter merges a $ref with the keys next to it
   * (convert-json-schema-to-openapi-schema.ts: { ...definition, ...siblingSchema }).
   * properties, required and propertyOrdering are unions, because dropping the branch's
   * half of any of the three loses fields the model is supposed to answer with.
   */
  procedure merge_google_node(
    pio_target in out nocopy json_object_t
  , p_source in json_object_t
  )
  as
    l_key_arr json_key_list;
    l_key varchar2(4000 char);
    l_merged_props json_object_t;
    l_source_props json_object_t;
    l_prop_key_arr json_key_list;
    l_merged_arr json_array_t;
    l_source_arr json_array_t;
    l_value varchar2(4000 char);
    l_found boolean;
  begin
    l_key_arr := p_source.get_keys;

    <<merge_loop>>
    for i in 1 .. l_key_arr.count loop
      l_key := l_key_arr(i);

      if not pio_target.has(l_key) then
        pio_target.put(l_key, p_source.get(l_key));

      elsif l_key = 'properties' then
        l_merged_props := pio_target.get_object('properties');
        l_source_props := p_source.get_object('properties');

        if l_merged_props is not null and l_source_props is not null then
          l_merged_props := json_object_t(l_merged_props.to_clob);
          l_prop_key_arr := l_source_props.get_keys;

          <<merge_property_loop>>
          for j in 1 .. l_prop_key_arr.count loop
            if not l_merged_props.has(l_prop_key_arr(j)) then
              l_merged_props.put(l_prop_key_arr(j), l_source_props.get(l_prop_key_arr(j)));
            end if;
          end loop merge_property_loop;

          pio_target.put('properties', l_merged_props);
        end if;

      elsif l_key in ('required', 'propertyOrdering') then
        l_merged_arr := pio_target.get_array(l_key);
        l_source_arr := p_source.get_array(l_key);

        if l_merged_arr is not null and l_source_arr is not null then
          l_merged_arr := json_array_t(l_merged_arr.to_clob);

          <<merge_name_loop>>
          for j in 0 .. l_source_arr.get_size - 1 loop
            l_value := l_source_arr.get_string(j);
            l_found := false;

            <<duplicate_loop>>
            for k in 0 .. l_merged_arr.get_size - 1 loop
              if l_merged_arr.get_string(k) = l_value then
                l_found := true;
              end if;
            end loop duplicate_loop;

            if not l_found then
              l_merged_arr.append(l_value);
            end if;
          end loop merge_name_loop;

          pio_target.put(l_key, l_merged_arr);
        end if;
      end if;
    end loop merge_loop;
  end merge_google_node;

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
   *
   * p_resolving carries the $ref pointers already open on the path from the root to
   * this node, so that a schema which points back at itself is refused instead of being
   * written out until a depth limit stops it.
   */
  function convert_schema_to_google(
    p_schema    in json_object_t
  , p_root      in json_object_t
  , p_resolving in apex_t_varchar2 default apex_t_varchar2()
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_schema_to_google';
    l_google_schema json_object_t := json_object_t();
    l_properties json_object_t;
    l_google_properties json_object_t := json_object_t();
    l_items json_object_t;
    l_items_node json_object_t;
    l_tuple_arr json_array_t;
    l_branch_arr json_array_t;
    l_google_any_of json_array_t;
    l_ordering json_array_t;
    l_type_arr json_array_t;
    l_elem json_element_t;
    l_property_name_arr json_key_list;
    l_key_arr json_key_list;
    l_property_name varchar2(4000 char);
    l_property_value json_object_t;
    l_key varchar2(4000 char);
    l_type varchar2(100 char);
    l_ref varchar2(4000 char);
    l_target json_object_t;
    l_definition json_object_t;
    l_merged json_object_t;
    l_resolving apex_t_varchar2;
    l_enum json_array_t;
    l_google_enum json_array_t;
    l_enum_value varchar2(4000 char);
    l_all_string boolean := true;
    l_all_number boolean := true;
    l_all_integer boolean := true;
    l_all_boolean boolean := true;
    l_notes varchar2(32767 char);
    l_note_text varchar2(32767 char);
    l_nullable boolean := false;
  begin
    uc_ai_logger.log('Converting schema to Google format', l_scope);

    /*
     * Resolve a local $ref against the root and convert the node it points at. Only the
     * pointer forms JSON Schema uses for a local definition are followed; a URL or a
     * deep pointer is refused, because dropping it leaves a node with no shape in it.
     *
     * The definition and the keys written next to the $ref are merged, with the node's
     * own keys winning, so the description Pydantic writes next to a $ref survives. The
     * reference converter merges the same way (convert-json-schema-to-openapi-schema.ts:
     * { ...definition, ...siblingSchema }).
     */
    if p_schema.has('$ref') then
      l_ref := p_schema.get_string('$ref');

      if l_ref like '#/$defs/%' then
        l_target := p_root.get_object('$defs');
        l_key := substr(l_ref, length('#/$defs/') + 1);
      elsif l_ref like '#/definitions/%' then
        l_target := p_root.get_object('definitions');
        l_key := substr(l_ref, length('#/definitions/') + 1);
      end if;

      if l_target is not null and l_key is not null and l_target.has(l_key) then
        l_definition := l_target.get_object(l_key);
      end if;

      if l_definition is null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_structured_unsupported
        , p_scope      => l_scope
        , p_message    => 'Google structured output follows only a $ref to a direct child of the '
                          || 'root $defs or definitions. Cannot resolve: ' || l_ref
        );
      end if;

      -- A schema that points back at itself has no finite expansion. Writing it out
      -- until a depth limit stopped the recursion produced hundreds of KB of
      -- responseSchema that still ended in empty nodes, so refuse it instead.
      <<cycle_loop>>
      for i in 1 .. p_resolving.count loop
        if p_resolving(i) = l_ref then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_structured_unsupported
          , p_scope      => l_scope
          , p_message    => 'Google structured output does not support a recursive JSON schema '
                            || 'reference: ' || l_ref
          );
        end if;
      end loop cycle_loop;

      if p_resolving.count >= c_max_ref_depth then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_structured_unsupported
        , p_scope      => l_scope
        , p_message    => 'Google structured output follows at most ' || c_max_ref_depth
                          || ' nested $ref hops. Reached at: ' || l_ref
        );
      end if;

      l_resolving := p_resolving;
      l_resolving.extend;
      l_resolving(l_resolving.count) := l_ref;

      l_merged := json_object_t(l_definition.to_clob);
      l_key_arr := p_schema.get_keys;

      <<sibling_loop>>
      for i in 1 .. l_key_arr.count loop
        if l_key_arr(i) != '$ref' then
          l_merged.put(l_key_arr(i), p_schema.get(l_key_arr(i)));
        end if;
      end loop sibling_loop;

      return convert_schema_to_google(l_merged, p_root, l_resolving);
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
    end if;

    /*
     * Convert enum, and `const` with it: const is an enum of one member, and the proto
     * has no const field, so dropping it removed the only statement of what the value
     * has to be.
     *
     * Measured HTTP 400 for a number member: "Invalid value at ... .enum[0]
     * (TYPE_STRING), 1". The proto types this field as an array of strings. Rendering
     * every value as a string is accepted on INTEGER, NUMBER and BOOLEAN nodes as well,
     * and the model still answers with the node's own type.
     *
     * A JSON null member has no string form: it used to reach Gemini as the
     * four-character text "null" and the model answered with that word. The proto says
     * "may be absent" with nullable, so a null member becomes nullable: true instead.
     */
    if p_schema.has('enum') or p_schema.has('const') then
      if p_schema.has('enum') then
        l_enum := p_schema.get_array('enum');
      else
        l_enum := json_array_t();
        l_enum.append(p_schema.get('const'));
      end if;

      if l_enum is not null then
        l_google_enum := json_array_t();

        <<enum_loop>>
        for i in 0 .. l_enum.get_size - 1 loop
          l_elem := l_enum.get(i);

          if l_elem.is_null then
            l_nullable := true;
          else
            l_all_string  := l_all_string and l_elem.is_string;
            l_all_boolean := l_all_boolean and l_elem.is_boolean;
            l_all_number  := l_all_number and l_elem.is_number;
            l_all_integer := l_all_integer
                             and l_elem.is_number
                             and l_enum.get_number(i) = trunc(l_enum.get_number(i));

            l_enum_value := l_enum.get_string(i);
            if l_enum_value is null then
              l_enum_value := trim(both '"' from l_elem.to_string);
            end if;
            l_google_enum.append(l_enum_value);
          end if;
        end loop enum_loop;

        if l_google_enum.get_size > 0 then
          l_google_schema.put('enum', l_google_enum);

          -- A node that states only an enum has no type field, and the proto needs one.
          -- The members say which type it is.
          if not l_google_schema.has('type') then
            l_google_schema.put('type', case
              when l_all_string  then 'STRING'
              when l_all_boolean then 'BOOLEAN'
              when l_all_integer then 'INTEGER'
              when l_all_number  then 'NUMBER'
              else 'STRING'
            end);
          end if;
        end if;
      end if;
    end if;

    if l_nullable and not l_google_schema.has('nullable') then
      l_google_schema.put('nullable', true);
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
        , convert_schema_to_google(l_property_value, p_root, p_resolving)
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

    /*
     * Convert items for array types.
     *
     * A tuple is written either as an array of schemas under `items` (the draft-07
     * target of Zod) or under `prefixItems` (draft 2020-12, which Pydantic and Zod v4
     * emit). get_object returns null for both, so an ARRAY node used to go out with no
     * item schema at all, which the proto does not allow. The proto's `items` is one
     * schema, so the positions are merged into a single anyOf and the fixed length is
     * written into the description.
     */
    if p_schema.has('items') then
      l_items := p_schema.get_object('items');
      if l_items is null then
        l_tuple_arr := p_schema.get_array('items');
      end if;
    end if;

    if l_items is null and l_tuple_arr is null and p_schema.has('prefixItems') then
      l_tuple_arr := p_schema.get_array('prefixItems');
    end if;

    if l_items is not null then
      l_google_schema.put('items', convert_schema_to_google(l_items, p_root, p_resolving));
    elsif l_tuple_arr is not null and l_tuple_arr.get_size > 0 then
      l_google_any_of := json_array_t();

      <<tuple_loop>>
      for i in 0 .. l_tuple_arr.get_size - 1 loop
        l_elem := l_tuple_arr.get(i);
        if l_elem.is_object then
          l_google_any_of.append(
            convert_schema_to_google(treat(l_elem as json_object_t), p_root, p_resolving)
          );
        end if;
      end loop tuple_loop;

      if l_google_any_of.get_size = 1 then
        l_items_node := treat(l_google_any_of.get(0) as json_object_t);
      else
        l_items_node := json_object_t();
        l_items_node.put('anyOf', l_google_any_of);
      end if;

      if l_google_any_of.get_size > 0 then
        l_google_schema.put('items', l_items_node);

        -- anyOf says what an item may be, not how many there are. minItems and maxItems
        -- are proto fields, so the length is written there where the author left it open.
        if not l_google_schema.has('minItems') and not l_google_schema.has('maxItems') then
          l_google_schema.put('minItems', l_tuple_arr.get_size);
          l_google_schema.put('maxItems', l_tuple_arr.get_size);
        end if;

        l_note_text := 'This array is a tuple of ' || l_tuple_arr.get_size
                       || ' items: item 1 must match the first schema listed under anyOf, '
                       || 'item 2 the second, and so on.';
      end if;
    end if;

    /*
     * Convert anyOf and oneOf branches. The proto has anyOf and no oneOf, and the
     * difference between them - at least one branch matches, against exactly one branch
     * matches - has no field to carry it, so oneOf becomes anyOf and the exclusive part
     * is written into the description. A dropped oneOf left the node with no shape in
     * it, and a root-level oneOf converted to nothing at all.
     */
    if p_schema.has('anyOf') or p_schema.has('oneOf') then
      l_google_any_of := json_array_t();

      <<branch_source_loop>>
      for i in 1 .. c_branch_keys.count loop
        l_branch_arr := p_schema.get_array(c_branch_keys(i));

        if l_branch_arr is not null then
          <<branch_loop>>
          for j in 0 .. l_branch_arr.get_size - 1 loop
            l_elem := l_branch_arr.get(j);
            if l_elem.is_object then
              l_google_any_of.append(
                convert_schema_to_google(treat(l_elem as json_object_t), p_root, p_resolving)
              );
            end if;
          end loop branch_loop;
        end if;
      end loop branch_source_loop;

      if l_google_any_of.get_size > 0 then
        l_google_schema.put('anyOf', l_google_any_of);
      end if;

      if p_schema.has('oneOf') then
        l_note_text := join_notes(l_note_text, 'The value must match exactly one of the listed schemas.');
      end if;
    end if;

    /*
     * Flatten allOf into this node. Pydantic writes a nested model as
     * {"allOf":[{"$ref":"#/$defs/X"}],"description":"..."}: dropping allOf left the
     * description alone and the nested model disappeared from the request.
     */
    if p_schema.has('allOf') then
      l_branch_arr := p_schema.get_array('allOf');

      if l_branch_arr is not null then
        <<all_of_loop>>
        for i in 0 .. l_branch_arr.get_size - 1 loop
          l_elem := l_branch_arr.get(i);
          if l_elem.is_object then
            merge_google_node(
              l_google_schema
            , convert_schema_to_google(treat(l_elem as json_object_t), p_root, p_resolving)
            );
          end if;
        end loop all_of_loop;
      end if;
    end if;

    -- The proto has no field for the four constraints in c_google_strip, and none for
    -- not, contains and if/then/else, so record all of them in the description instead.
    -- ---- fix 4: delete this block to stop the package editing the author's text.
    l_note_text := join_notes(constraint_notes(p_schema, c_google_strip), l_note_text);
    l_note_text := join_notes(l_note_text, structural_notes(p_schema));

    l_notes := described(l_google_schema, l_note_text);
    if l_notes is not null then
      l_google_schema.put('description', l_notes);
    end if;

    /*
     * A node with no type, properties, items, anyOf or enum tells Gemini nothing about
     * the shape it has to answer with. Measured: the model then invents its own field
     * names ("quantity" where the schema said "qty"), and the answer no longer parses
     * against the schema the caller wrote. That is worse than a failed request, so the
     * conversion refuses instead of sending it.
     *
     * An author who wrote an empty schema asked for no constraint and gets one back;
     * only a node that carried something and lost all of it is refused.
     */
    if p_schema.get_size > 0
       and not (l_google_schema.has('type')
                or l_google_schema.has('properties')
                or l_google_schema.has('items')
                or l_google_schema.has('anyOf')
                or l_google_schema.has('enum'))
    then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_structured_unsupported
      , p_scope      => l_scope
      , p_message    => 'Google structured output cannot express this schema node: nothing '
                        || 'is left that states its type or its shape'
      , p_extra      => p_schema.to_clob
      );
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
  ) return json_object_t;

  /*
   * Every object in an array of schemas, rewritten for the same policy. Used for the
   * combinator arrays and for a tuple written as an array of schemas under `items`.
   * A member that is not an object - a boolean schema, for instance - is copied as it is.
   */
  function process_branches(
    p_array  in json_array_t
  , p_policy in t_policy
  ) return json_array_t
  as
    l_result json_array_t := json_array_t();
    l_elem json_element_t;
  begin
    <<branch_loop>>
    for i in 0 .. p_array.get_size - 1 loop
      l_elem := p_array.get(i);
      if l_elem.is_object then
        l_result.append(process_schema(treat(l_elem as json_object_t), p_policy));
      else
        l_result.append(l_elem);
      end if;
    end loop branch_loop;

    return l_result;
  end process_branches;

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
    l_tuple_arr json_array_t;
    l_processed_arr json_array_t;
    l_required_array json_array_t;
    l_type_arr json_array_t;
    l_property_name_arr json_key_list;
    l_map_key_arr json_key_list;
    l_property_name varchar2(4000 char);
    l_key varchar2(4000 char);
    l_format varchar2(4000 char);
    l_notes varchar2(32767 char);
    l_description varchar2(32767 char);
    l_is_object boolean := false;
    l_tuple_handled boolean := false;
    l_strip apex_t_varchar2 := apex_t_varchar2();
  begin
    -- work on a copy, so the caller's schema is never changed
    l_result := json_object_t(p_schema.to_clob);

    if p_policy.strip_openai then
      -- Measured HTTP 400: "In context=('properties','tags'), 'uniqueItems' is not
      -- permitted." and "In context=(), 'minProperties' is not permitted."
      -- oneOf and allOf are rejected too, but they say what the value has to be, so
      -- removing them would change the schema. They are left for the caller to fix.
      -- not, contains, if and propertyNames are handled by c_structural_strip below.
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

    -- Remove the structural keywords both decoders reject, and say in words what they
    -- said in JSON. The measured HTTP 400 of each one is quoted at c_structural_strip.
    if p_policy.strip_structural then
      if p_policy.describe_stripped then
        l_notes := join_notes(l_notes, structural_notes(l_result));
      end if;

      <<structural_loop>>
      for i in 1 .. c_structural_strip.count loop
        l_result.remove(c_structural_strip(i));
      end loop structural_loop;
    end if;

    -- Measured HTTP 400: OpenAI "'phone' is not a valid format", Anthropic "For
    -- 'string' type, format 'phone' is not supported". A format the decoder cannot
    -- enforce still tells the model what to write, so it moves into the description.
    if p_policy.allowed_formats is not null and l_result.has('format') then
      l_format := l_result.get_string('format');

      if l_format is not null and not in_list(p_policy.allowed_formats, l_format) then
        if p_policy.describe_stripped then
          l_notes := join_notes(l_notes, 'The value must be in the ' || l_format || ' format.');
        end if;
        l_result.remove('format');
      end if;
    end if;

    /*
     * A tuple - an array of schemas under `items` (the draft-07 target of Zod) or under
     * `prefixItems` (draft 2020-12, which Pydantic and Zod v4 emit) - is rejected by
     * both decoders. Measured HTTP 400:
     *   Anthropic "Array types must be specified with a single object schema for
     *             'items'" and "For 'array' type, property 'prefixItems' is not
     *             supported".
     *   OpenAI    "[...] is not of type 'object', 'boolean'" for the tuple and
     *             "array schema missing items" for prefixItems.
     * Both accept one items node holding an anyOf, and both answered with a conforming
     * tuple when sent that shape, so that is what a tuple becomes here. Nothing is left
     * to carry the fixed length, so it goes into the description.
     *
     * The tuple used to pass through untouched, which also meant the objects inside it
     * reached the provider with neither additionalProperties nor a completed required
     * list.
     */
    if p_policy.strip_structural then
      if l_result.has('items') and l_result.get_object('items') is null then
        l_tuple_arr := l_result.get_array('items');
      end if;

      if l_tuple_arr is null and l_result.has('prefixItems') then
        l_tuple_arr := l_result.get_array('prefixItems');
      end if;

      if l_tuple_arr is not null and l_tuple_arr.get_size > 0 then
        l_processed_arr := process_branches(l_tuple_arr, p_policy);
        l_result.remove('prefixItems');

        if l_processed_arr.get_size = 1 and l_processed_arr.get(0).is_object then
          l_result.put('items', treat(l_processed_arr.get(0) as json_object_t));
        else
          l_child := json_object_t();
          l_child.put('anyOf', l_processed_arr);
          l_result.put('items', l_child);
        end if;

        l_tuple_handled := true;

        /*
         * anyOf says what an item may be, not how many there are, and a model that is
         * only told the shape answers with as many items as it likes: gpt-4o-mini
         * returned four for a two-member tuple. minItems and maxItems are accepted by
         * OpenAI (measured), so the length is written there where the author left it
         * open. Anthropic rejects maxItems and a minItems above 1, and l_strip already
         * carries that fact, so on that path the sentence below is all there is.
         */
        if not in_list(l_strip, 'maxItems')
           and not l_result.has('minItems')
           and not l_result.has('maxItems')
        then
          l_result.put('minItems', l_tuple_arr.get_size);
          l_result.put('maxItems', l_tuple_arr.get_size);
        end if;

        if p_policy.describe_stripped then
          l_notes := join_notes(
            l_notes
          , 'This array is a tuple of ' || l_tuple_arr.get_size || ' items: item 1 must match '
            || 'the first schema listed under anyOf, item 2 the second, and so on.'
          );
        end if;
      end if;
    end if;

    l_description := described(l_result, l_notes);
    if l_description is not null then
      l_result.put('description', l_description);
    end if;

    /*
     * Add additionalProperties: false for object types.
     * Measured HTTP 400 on both providers when it is missing:
     * "For 'object' type, 'additionalProperties' must be explicitly set to false".
     *
     * A node counts as an object when it has properties, or when its type says object -
     * including a union type such as ["object","null"], where get_string returns null
     * and only get_array reads the value. The test used to be get_string('type') alone,
     * so a union-typed node and a type-less properties container were both skipped,
     * while force_all_required below keys on properties and did write a required list
     * into both. OpenAI strict then rejected the schema for the missing
     * additionalProperties. The two now key on the same test.
     *
     * Both providers demand the literal false, so an author-supplied
     * additionalProperties sub-schema is overwritten instead of being carried through.
     */
    if p_policy.close_objects then
      l_is_object := l_result.has('properties');

      if not l_is_object and l_result.has('type') then
        l_type_arr := l_result.get_array('type');

        if l_type_arr is null then
          l_is_object := l_result.get_string('type') = 'object';
        else
          <<type_union_loop>>
          for i in 0 .. l_type_arr.get_size - 1 loop
            if lower(l_type_arr.get_string(i)) = 'object' then
              l_is_object := true;
            end if;
          end loop type_union_loop;
        end if;
      end if;

      if l_is_object then
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
      -- a tuple was already rewritten and processed above
      if l_result.has(l_key) and not (l_key = 'items' and l_tuple_handled) then
        l_child := l_result.get_object(l_key);

        if l_child is not null then
          l_result.put(l_key, process_schema(l_child, p_policy));
        else
          /*
           * A tuple writes `items` as an array of schemas, which is what the draft-07
           * target of Zod emits. get_object returns null for an array, so the whole
           * tuple used to pass through unprocessed and the objects inside it reached
           * the provider with neither additionalProperties nor a completed required
           * list. prefixItems - the draft 2020-12 spelling of the same thing - is
           * handled by the array loop below, and this treats both the same way.
           */
          l_arr := l_result.get_array(l_key);
          if l_arr is not null then
            l_result.put(l_key, process_branches(l_arr, p_policy));
          end if;
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
          l_result.put(l_key, process_branches(l_arr, p_policy));
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
