create or replace package body uc_ai_structured_output as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

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
   * Recursively convert a JSON schema object to Google format
   */
  function convert_schema_to_google(p_schema in json_object_t) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'convert_schema_to_google';
    l_google_schema json_object_t := json_object_t();
    l_properties json_object_t;
    l_google_properties json_object_t := json_object_t();
    l_items json_object_t;
    l_required json_array_t;
    l_property_names json_key_list;
    l_property_name varchar2(4000 char);
    l_property_value json_object_t;
    l_type varchar2(100 char);
  begin
    uc_ai_logger.log('Converting schema to Google format', l_scope);

    -- Convert type
    if p_schema.has('type') then
      l_type := p_schema.get_string('type');
      l_google_schema.put('type', convert_type_to_google(l_type));
    end if;

    -- Convert description
    if p_schema.has('description') then
      l_google_schema.put('description', p_schema.get_string('description'));
    end if;

    -- Convert properties for object types
    if p_schema.has('properties') then
      l_properties := p_schema.get_object('properties');
      l_property_names := l_properties.get_keys();
      
      <<property_loop>>
      for i in 1 .. l_property_names.count loop
        l_property_name := l_property_names(i);
        l_property_value := l_properties.get_object(l_property_name);
        l_google_properties.put(l_property_name, convert_schema_to_google(l_property_value));
      end loop property_loop;
      
      l_google_schema.put('properties', l_google_properties);
    end if;

    -- Convert items for array types
    if p_schema.has('items') then
      l_items := p_schema.get_object('items');
      l_google_schema.put('items', convert_schema_to_google(l_items));
    end if;

    -- Convert required array
    if p_schema.has('required') then
      l_required := p_schema.get_array('required');
      l_google_schema.put('required', l_required);
    end if;

    -- Add propertyOrdering for better structure (Google-specific)
    if p_schema.has('properties') and p_schema.has('required') then
      l_required := p_schema.get_array('required');
      l_google_schema.put('propertyOrdering', l_required);
    end if;

    return l_google_schema;
  end convert_schema_to_google;

  /*
   * Recursively process schema to add additionalProperties: false to all object types
   */
  function process_openai_strict_schema(p_schema in json_object_t) return json_object_t
  as
    l_result json_object_t := json_object_t(p_schema.to_clob);
    l_properties json_object_t;
    l_processed_properties json_object_t := json_object_t();
    l_items json_object_t;
    l_property_names json_key_list;
    l_property_name varchar2(4000 char);
    l_property_value json_object_t;
    l_type varchar2(100 char);
  begin
    -- Remove unsupported properties for OpenAI strict mode
    l_result.remove('$schema');
    l_result.remove('title');
    l_result.remove('description');
    
    -- Add additionalProperties: false for object types
    if l_result.has('type') then
      l_type := l_result.get_string('type');
      if l_type = 'object' then
        l_result.put('additionalProperties', false);
      end if;
    end if;

    -- Process nested properties and ensure all are required
    if l_result.has('properties') then
      l_properties := l_result.get_object('properties');
      l_property_names := l_properties.get_keys();
      
      <<property_loop>>
      for i in 1 .. l_property_names.count loop
        l_property_name := l_property_names(i);
        l_property_value := l_properties.get_object(l_property_name);
        l_processed_properties.put(l_property_name, process_openai_strict_schema(l_property_value));
      end loop property_loop;
      
      l_result.put('properties', l_processed_properties);
      
      -- For OpenAI strict mode, all properties must be required
      declare
        l_required_array json_array_t := json_array_t();
      begin
        <<required_loop>>
        for i in 1 .. l_property_names.count loop
          l_required_array.append(l_property_names(i));
        end loop required_loop;
        
        l_result.put('required', l_required_array);
      end;
    end if;

    -- Process array items
    if l_result.has('items') then
      l_items := l_result.get_object('items');
      l_result.put('items', process_openai_strict_schema(l_items));
    end if;

    return l_result;
  end process_openai_strict_schema;

  /*
   * Convert a standard JSON schema to OpenAI format for structured output
   */
  function to_openai_format(
    p_schema in json_object_t,
    p_name in varchar2 default 'structured_output',
    p_strict in boolean default true
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'to_openai_format';
    l_response_format json_object_t := json_object_t();
    l_schema_copy json_object_t;
    l_json_schema json_object_t;
  begin
    uc_ai_logger.log('Converting schema to OpenAI format', l_scope, 'Name: ' || p_name || ', Strict: ' || case when p_strict then 'true' else 'false' end);

    -- Create a copy of the input schema and process for strict mode
    if p_strict then
      l_schema_copy := process_openai_strict_schema(p_schema);
    else
      l_schema_copy := json_object_t(p_schema.to_clob);
    end if;

    l_response_format.put('type', 'json_schema');

    l_json_schema := json_object_t();
    l_json_schema.put('name', p_name);
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
    return convert_schema_to_google(p_schema);
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
   * Generic function to convert schema based on provider
   */
  function format_schema(
    p_schema in json_object_t,
    p_provider in uc_ai.provider_type,
    p_name in varchar2 default 'structured_output',
    p_strict in boolean default true
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := c_scope_prefix || 'format_schema';
    l_result json_object_t;
  begin
    uc_ai_logger.log('Formatting schema for provider: ' || p_provider, l_scope);
    
    case p_provider
      when uc_ai.c_provider_openai then
        l_result := to_openai_format(p_schema, p_name, p_strict);
      when uc_ai.c_provider_google then
        l_result := to_google_format(p_schema);
      when uc_ai.c_provider_ollama then
        l_result := to_ollama_format(p_schema);
      else
        uc_ai_logger.log_error('Unsupported provider for structured output: ' || p_provider, l_scope);
        raise_application_error(-20999, 'Provider ' || p_provider || ' does not support structured output');
    end case;
    
    return l_result;
  end format_schema;

end uc_ai_structured_output;
/
