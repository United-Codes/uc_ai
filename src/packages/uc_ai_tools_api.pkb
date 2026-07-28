create or replace package body uc_ai_tools_api as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- Programmatic tool-calling (code mode) run context. Set by execute_agent_tool
  -- around a sandboxed run and read by the uc_ai_ptc_api gateway (same session,
  -- same package instantiation) to enforce the allow-list + inner-call budget.
  gc_ptc_max_inner_calls constant pls_integer := 100;
  g_ptc_active     boolean := false;
  g_ptc_enable     boolean := false;
  g_ptc_tag_filter number(1) := 0;  -- @dblinter ignore(G-2410): used in a SQL predicate (member-of filter), so kept numeric like l_enable_tool_filter
  g_ptc_tags       apex_t_varchar2 := apex_t_varchar2();
  g_ptc_calls      pls_integer := 0;
  g_ptc_max_calls  pls_integer := gc_ptc_max_inner_calls;
  -- settings of the active run, so inner callTool()s can fire the per-tool-call hook
  g_ptc_settings   uc_ai_settings.t_settings;
  -- message of a hook veto raised for an inner call; re-raised after the run so a
  -- veto aborts the whole request instead of being swallowed into an error result
  g_ptc_veto_msg   varchar2(4000 char);
  g_ptc_runner_ok  pls_integer;  -- null = not yet checked, 1 = present, 0 = absent

  -- Snapshot of the run context, so a nested code-mode run (e.g. a program that
  -- calls an agent-as-tool whose agent itself uses code mode) restores the outer
  -- run instead of deactivating it.
  type t_ptc_ctx is record (
    active     boolean
  , enable     boolean
  , tag_filter number(1)
  , tags       apex_t_varchar2
  , calls      pls_integer
  , max_calls  pls_integer
  , settings   uc_ai_settings.t_settings
  , veto_msg   varchar2(4000 char)
  );


  /*
   * Converts an input schema to Cohere format
   * 
   * Takes a JSON schema with nested parameters object and extracts the properties
   * from within the outer object, adding isRequired attributes based on the required array.
   * 
   * Input example:
   * {
   *   "type": "object",
   *   "properties": {
   *     "parameters": {
   *       "type": "object",
   *       "description": "JSON object containing parameters",
   *       "properties": {
   *         "user_email": {"type": "string", "description": "Email of the user"},
   *         "project_name": {"type": "string", "description": "Name of the project"},
   *         "notes": {"type": "string", "description": "Optional description"}
   *       },
   *       "required": ["user_email", "project_name"]
   *     }
   *   },
   *   "required": ["parameters"]
   * }
   * 
   * Output example:
   * {
   *   "user_email": {"type": "string", "description": "Email of the user", "isRequired": true},
   *   "project_name": {"type": "string", "description": "Name of the project", "isRequired": true},
   *   "notes": {"type": "string", "description": "Optional description", "isRequired": false}
   * }
   */
  function convert_input_schema_to_cohere (
    p_input_schema in json_object_t
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'convert_input_schema_to_cohere';
    
    l_result_obj        json_object_t := json_object_t();
    l_properties        json_object_t;
    l_parameters_obj    json_object_t;
    l_param_props       json_object_t;
    l_required_arr      json_array_t;
    l_param_obj         json_object_t;
    l_keys_arr          json_key_list;
    l_required_keys_arr json_key_list;
    l_prop_name         varchar2(255 char);
    l_is_required       boolean;
    
  begin
    -- Get the properties object from the input schema
    l_properties := treat(p_input_schema.get('properties') as json_object_t);
    
    if l_properties is null then
      uc_ai_logger.log_error('No properties found in input schema', l_scope);
      return l_result_obj;
    end if;
    
    -- Look for the parameters object within properties
    -- In most cases this will be the first (and likely only) property
    l_keys_arr := l_properties.get_keys;
    
    if l_keys_arr is null or l_keys_arr.count = 0 then
      uc_ai_logger.log_error('No properties keys found in input schema', l_scope);
      return l_result_obj;
    end if;
    
    -- Get the first property (assumed to be the parameters object)
    l_parameters_obj := treat(l_properties.get(l_keys_arr(1)) as json_object_t);
    
    if l_parameters_obj is null then
      uc_ai_logger.log_error('Parameters object is null for key: %s', l_scope, l_keys_arr(1));
      return l_result_obj;
    end if;
    
    -- Get the properties within the parameters object
    l_param_props := treat(l_parameters_obj.get('properties') as json_object_t);
    
    if l_param_props is null then
      uc_ai_logger.log_error('No properties found in parameters object', l_scope);
      return l_result_obj;
    end if;
    
    -- Get the required array from the parameters object
    l_required_arr := treat(l_parameters_obj.get('required') as json_array_t);
    
    -- Convert required array to a list for easier lookup
    l_required_keys_arr := json_key_list();
    if l_required_arr is not null then
      <<required_loop>>
      for i in 0 .. l_required_arr.get_size - 1 loop
        l_required_keys_arr.extend;
        l_required_keys_arr(l_required_keys_arr.count) := l_required_arr.get_string(i);
      end loop required_loop;
    end if;
    
    -- Process each property in the parameters
    l_keys_arr := l_param_props.get_keys;
    
    <<property_loop>>
    for i in 1 .. l_keys_arr.count loop
      l_prop_name := l_keys_arr(i);
      l_param_obj := treat(l_param_props.get(l_prop_name) as json_object_t);
      
      if l_param_obj is not null then
        -- Clone the parameter object to avoid modifying the original
        l_param_obj := l_param_obj.clone();
        
        -- Check if this property is required
        l_is_required := false;
        if l_required_keys_arr is not null then
          <<check_required>>
          for j in 1 .. l_required_keys_arr.count loop
            if l_required_keys_arr(j) = l_prop_name then
              l_is_required := true;
              exit;
            end if;
          end loop check_required;
        end if;
        
        -- Add the isRequired attribute
        l_param_obj.put('isRequired', l_is_required);
        
        -- Add the modified parameter to the result
        l_result_obj.put(l_prop_name, l_param_obj);
      end if;
    end loop property_loop;
    
    uc_ai_logger.log('Converted schema to Cohere format', l_scope, l_result_obj.to_clob());
    
    return l_result_obj;
    
  exception
    when others then
      uc_ai_logger.log_error('Error in convert_input_schema_to_cohere: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end convert_input_schema_to_cohere;

  /*
   * Wraps a parameter definition as an array type
   * Used when is_array=1 in tool parameter definition
   * Takes the base parameter schema and wraps it in array structure with min/max items
   */
  procedure wrap_as_array (
    p_row         in uc_ai_tool_parameters%rowtype
  , pio_param_obj in out nocopy json_object_t
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'wrap_as_array';
    l_param_copy json_object_t := pio_param_obj;
  begin
    pio_param_obj := json_object_t();

    pio_param_obj.put('type', 'array');
    pio_param_obj.put('items', l_param_copy);

    if p_row.array_min_items is not null then
      pio_param_obj.put('minItems', p_row.array_min_items);
    end if;

    if p_row.array_max_items is not null then
      pio_param_obj.put('maxItems', p_row.array_max_items);
    end if;
  exception
    when others then
      uc_ai_logger.log_error('Error in wrap_as_array: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end wrap_as_array;

  /*
   * Converts a database parameter row into proper JSON schema parameter object
   * Handles all data types, validation rules, nested objects, arrays, enums, defaults
   * 
   * Key logic:
   * - Processes data_type (string/number/integer/boolean/object) with type-specific constraints
   * - Builds nested object schemas recursively for parent_param_id relationships  
   * - Handles array wrapping when is_array=1
   * - Adds parameter to required array if required=1
   */
  procedure prepare_single_parameter (
    p_row          in uc_ai_tool_parameters%rowtype
  , pio_required   in out nocopy json_array_t
  , po_param_obj   out nocopy json_object_t
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'prepare_single_parameter';
    e_unhandled_type exception;

    l_obj_attrs     json_object_t;
    l_obj_required  json_array_t;

    l_new_required json_array_t;
  begin
    po_param_obj := json_object_t();
    po_param_obj.put('type', p_row.data_type);
    po_param_obj.put('description', p_row.description);

    l_new_required := pio_required;
    
    -- Add type-specific constraints
    CASE p_row.data_type
      WHEN 'string' THEN
        IF p_row.min_length IS NOT NULL THEN
          po_param_obj.put('minLength', p_row.min_length);
        END IF;
        
        IF p_row.max_length IS NOT NULL THEN
          po_param_obj.put('maxLength', p_row.max_length);
        END IF;
        
        IF p_row.pattern IS NOT NULL THEN
          po_param_obj.put('pattern', p_row.pattern);
        END IF;
        
        IF p_row.format IS NOT NULL THEN
          po_param_obj.put('format', p_row.format);
        END IF;
      
      WHEN 'number' THEN
        IF p_row.min_num_val IS NOT NULL THEN
          po_param_obj.put('minimum', p_row.min_num_val);
        END IF;
        
        IF p_row.max_num_val IS NOT NULL THEN
          po_param_obj.put('maximum', p_row.max_num_val);
        END IF;
      
      WHEN 'integer' THEN
        IF p_row.min_num_val IS NOT NULL THEN
          po_param_obj.put('minimum', FLOOR(p_row.min_num_val));
        END IF;
        
        IF p_row.max_num_val IS NOT NULL THEN
          po_param_obj.put('maximum', FLOOR(p_row.max_num_val));
        END IF;
      WHEN 'boolean' THEN
        null;
      WHEN 'object' THEN
        l_obj_attrs    := json_object_t();
        l_obj_required := json_array_t();
        <<nested_parameters>>
        for sub_param in (
          select *
            from uc_ai_tool_parameters
           where parent_param_id = p_row.id
        )
        loop
          declare
            l_sub_param_obj json_object_t := json_object_t();
          begin
            -- Prepare the sub-parameter
            prepare_single_parameter(sub_param, l_obj_required, l_sub_param_obj);
            
            -- Add to object attributes
            l_obj_attrs.put(sub_param.name, l_sub_param_obj);
          end;
        end loop nested_parameters;
        po_param_obj.put('properties', l_obj_attrs);
        po_param_obj.put('required', l_obj_required);
      ELSE
        uc_ai_logger.log_error('Unhandled data type: %s', l_scope, p_row.data_type);
        raise e_unhandled_type;
    END CASE;
    
    -- Add enum values for scalar types
    IF p_row.data_type IN ('string', 'number', 'integer') AND p_row.enum_values IS NOT NULL THEN
      declare
        l_enum_values apex_t_varchar2;
        l_enum_arr    json_array_t := json_array_t();
      begin
        l_enum_values := apex_string.split(p_row.enum_values, ':');
        <<enum_values>>
        for i in 1 .. l_enum_values.count loop
          l_enum_arr.append(l_enum_values(i));
        end loop enum_values;
        -- Parse the JSON array from enum_values CLOB
        po_param_obj.put('enum', l_enum_arr);
      end;
    END IF;
 
    -- Add default value if specified
    IF p_row.default_value IS NOT NULL THEN
      -- Handle different types of default values
      IF p_row.data_type = 'string' THEN
        po_param_obj.put('default', p_row.default_value);
      ELSIF p_row.data_type = 'boolean' THEN
        -- Convert string representation to boolean
        IF LOWER(p_row.default_value) IN ('true', '1') THEN
          po_param_obj.put('default', TRUE);
        ELSE
          po_param_obj.put('default', FALSE);
        END IF;
      ELSIF p_row.data_type = 'number' THEN
        po_param_obj.put('default', TO_NUMBER(p_row.default_value default null on conversion error));
      ELSIF p_row.data_type = 'integer' THEN
        po_param_obj.put('default', FLOOR(TO_NUMBER(p_row.default_value default null on conversion error)));
      ELSIF p_row.data_type = 'array' AND p_row.default_value LIKE '[%]' THEN
        -- Parse JSON array from default_value
        po_param_obj.put('default', JSON_ARRAY_T.parse(p_row.default_value));
      END IF;
    END IF;

      -- Handle array type
    if p_row.is_array = 1 then
      wrap_as_array(p_row, po_param_obj);
    end if;

    apex_debug.trace('Is parameter required: ' || p_row.name || ', required: ' ||  p_row.required);
    -- Add to required array if needed
    IF p_row.required = 1 THEN
      l_new_required.append(p_row.name);
      apex_debug.trace('Added to l_new_required: ' || pio_required.stringify);
    END IF;


    pio_required := l_new_required;
  exception
    when others then
      uc_ai_logger.log_error('Error in prepare_single_parameter: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end prepare_single_parameter;


  /*
   * Name of the key a provider expects the tool's JSON schema under.
   *
   * Google/Ollama (and the OpenAI-compatible xAI/OpenRouter/Mistral endpoints) call
   * it "parameters", the rest "input_schema". Single source of truth: every builder
   * (get_tool_schema, build_code_mode_tool) and every reader (format_tool_for_provider,
   * tool_param_names) must derive the key from here, otherwise a tool definition is
   * silently emitted under a key the provider ignores.
   */
  function input_schema_key (
    p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  ) return varchar2
  as
  begin
    if    p_provider in (uc_ai.c_provider_google, uc_ai.c_provider_ollama)
       -- xAI uses "parameters" as input schema name
       or (p_provider = uc_ai.c_provider_openai and p_additional_info in (uc_ai.c_provider_xai, uc_ai.c_provider_openrouter, uc_ai.c_provider_mistral))
    then
      return 'parameters';
    else
      return 'input_schema';
    end if;
  end input_schema_key;


  /*
   * Main function to build complete JSON schema for a tool
   *
   * Workflow:
   * 1. Gets tool info (code, description) from uc_ai_tools
   * 2. Processes all top-level parameters (parent_param_id IS NULL)
   * 3. Each parameter recursively processes its children via prepare_single_parameter
   * 4. Builds final JSON schema with properties, required array, additionalProperties: false
   * 5. Returns format: {name, description, input_schema: {type: "object", properties: {...}}}
   */
  function get_tool_schema(
    p_tool_id         in uc_ai_tools.id%type
  , p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  ) 
    return json_object_t 
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_tool_schema';

    l_tool_code        uc_ai_tools.code%type;
    l_tool_description uc_ai_tools.description%type;

    l_param_count pls_integer;
    
    -- JSON objects
    l_function     json_object_t := json_object_t();
    l_input_schema json_object_t := json_object_t();
    l_properties   json_object_t := json_object_t();
    l_required     json_array_t  := json_array_t();

    l_param_rec uc_ai_tool_parameters%rowtype;
    l_param_obj JSON_OBJECT_T := JSON_OBJECT_T();

    l_input_schema_name varchar2(255 char);
    
  BEGIN
    -- Get tool information
    SELECT code, description
    INTO l_tool_code, l_tool_description
    FROM uc_ai_tools
    WHERE id = p_tool_id;

    
    select count(*) -- @dblinter ignore(G-8110) we distinct between 1 and >1
      into l_param_count
      from uc_ai_tool_parameters
     where tool_id = p_tool_id
       and parent_param_id is null;

    if l_param_count = 1 then
      SELECT *
        INTO l_param_rec
        FROM uc_ai_tool_parameters
       WHERE tool_id = p_tool_id
         AND parent_param_id IS NULL
      ;

      prepare_single_parameter(l_param_rec, l_required, l_param_obj);
      l_properties.put(l_param_rec.name, l_param_obj);
    
      -- Build the complete JSON structure
      l_input_schema.put('type', 'object');
      l_input_schema.put('properties', l_properties);
      l_input_schema.put('required', l_required);
      if p_provider != uc_ai.c_provider_google then
        l_input_schema.put('additionalProperties', FALSE);
        l_input_schema.put('$schema', 'http://json-schema.org/draft-07/schema#');
      end if;
    
    elsif l_param_count > 1 then
      -- Multiple top-level parameters: wrap them into a "parameters" object
      <<multiple_params>>
      for param_rec in (
        SELECT *
        FROM uc_ai_tool_parameters
        WHERE tool_id = p_tool_id
          AND parent_param_id IS NULL
      )
      loop
        prepare_single_parameter(param_rec, l_required, l_param_obj);
        l_properties.put(param_rec.name, l_param_obj);
        l_param_obj := json_object_t(); -- Reset for next iteration
      end loop multiple_params;
      
      -- Build the complete JSON structure with wrapped parameters
      l_input_schema.put('type', 'object');
      l_input_schema.put('properties', l_properties);
      l_input_schema.put('required', l_required);
      if p_provider != uc_ai.c_provider_google then
        l_input_schema.put('additionalProperties', FALSE);
        l_input_schema.put('$schema', 'http://json-schema.org/draft-07/schema#');
      end if;
    else
      -- when no parameters are defined, use an empty object schema
      l_input_schema.put('type', 'object');
      l_input_schema.put('properties', json_object_t());
      l_input_schema.put('required', json_array_t());
      if p_provider != uc_ai.c_provider_google then
        l_input_schema.put('$schema', 'http://json-schema.org/draft-07/schema#');
      end if;
    end if;

    l_input_schema_name := input_schema_key(p_provider, p_additional_info);

    l_function.put(l_input_schema_name, l_input_schema);
    l_function.put('name', l_tool_code);
    l_function.put('description', l_tool_description);
  
    return l_function;
  exception
    when others then
      uc_ai_logger.log_error('Error in get_tool_schema: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  END get_tool_schema;


  -- Wrap a base tool definition ({name, description, <schema key>}) into the
  -- shape a given provider expects. Anthropic/google/xai/openrouter/mistral use
  -- the base form directly; openai/ollama/responses/oci need their own envelope.
  function format_tool_for_provider (
    p_tool_base       in json_object_t
  , p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  ) return json_object_t
  as
    l_base       json_object_t := p_tool_base;
    l_out        json_object_t;
    l_schema_key varchar2(30 char);
  begin
    l_schema_key := input_schema_key(p_provider, p_additional_info);

    if p_provider in (uc_ai.c_provider_openai, uc_ai.c_provider_ollama) then
      l_out := json_object_t();
      l_out.put('type', 'function');
      l_out.put('function', l_base.clone());
    elsif p_provider = uc_ai.c_provider_responses_api then
      l_out := json_object_t();
      l_out.put('type', 'function');
      l_out.put('name', l_base.get_string('name'));
      l_out.put('description', l_base.get_string('description'));
      l_out.put('parameters', l_base.get_object(l_schema_key));
    elsif p_provider = uc_ai.c_provider_oci then
      l_out := json_object_t();
      if p_additional_info != gc_cohere then
        l_out.put('type', 'FUNCTION');
      end if;
      l_out.put('description', l_base.get_string('description'));
      l_out.put('name', l_base.get_string('name'));
      if p_additional_info != gc_cohere then
        l_out.put('parameters', l_base.get_object(l_schema_key));
      else
        l_out.put('parameterDefinitions', convert_input_schema_to_cohere(l_base.get_object(l_schema_key)));
      end if;
    else
      l_out := l_base;
    end if;

    return l_out;
  end format_tool_for_provider;


  -- Build the base definition of the code-mode meta-tool. The tool takes a single
  -- `code` string; the model authors JavaScript that calls the other tools via
  -- callTool(name, args) and returns only its final `result`.
  -- The schema goes under the same key the provider's regular tools use, so the
  -- `code` parameter is actually declared for every provider.
  function build_code_mode_tool(
    p_catalog         in varchar2
  , p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  ) return json_object_t
  as
    l_tool         json_object_t := json_object_t();
    l_input_schema json_object_t := json_object_t();
    l_props        json_object_t := json_object_t();
    l_code_prop    json_object_t := json_object_t();
    l_required     json_array_t  := json_array_t();
    l_code_desc    varchar2(32767 char);
  begin
    l_code_desc :=
      'JavaScript source executed in the database. Your code runs as the body of an '
      || 'async function, so you can use await at the top level. Call the tools listed '
      || 'below with `await callTool("TOOL_CODE", { ...args })` - ALWAYS await it - which '
      || 'returns the tool''s parsed JSON result (an object or array). ONLY the exact tool '
      || 'codes listed here are callable - there is no discovery/list function, so never '
      || 'invent tool names. Loop, filter and aggregate locally, then assign your final '
      || 'answer to a top-level variable named `result` (an object or a string). Only '
      || '`result` is returned to you - intermediate tool outputs stay in the sandbox. '
      || 'Use plain JavaScript only: there is no SQL, network, file or module access, '
      || 'and callTool is the only way to reach data. You may use console.log() while '
      || 'developing: its output is returned to you if the program fails or sets no '
      || '`result`.' || chr(10) || chr(10)
      || 'Callable tools (await callTool code -> arguments):' || chr(10)
      || p_catalog;

    l_code_prop.put('type', 'string');
    l_code_prop.put('description', l_code_desc);
    l_props.put('code', l_code_prop);
    l_required.append('code');

    l_input_schema.put('type', 'object');
    l_input_schema.put('properties', l_props);
    l_input_schema.put('required', l_required);
    -- Google rejects the request outright for unknown schema keys, so the meta-tool
    -- follows the same rule as get_tool_schema and omits them there.
    if p_provider != uc_ai.c_provider_google then
      l_input_schema.put('additionalProperties', false);
    end if;

    l_tool.put('name', c_code_mode_tool_code);
    l_tool.put('description',
      'Programmatically orchestrate the other available tools by writing a short '
      || 'JavaScript program that calls them and returns only the final result. Prefer '
      || 'this when a task needs many tool calls or would pull large intermediate data '
      || 'into the conversation. The exact callable tool codes are documented in the '
      || '`code` parameter description.');
    l_tool.put(input_schema_key(p_provider, p_additional_info), l_input_schema);

    return l_tool;
  end build_code_mode_tool;


  -- Comma-separated parameter names of a base tool definition, for the code-mode
  -- catalog line (e.g. "employee_id, quarter"). Empty string for a no-arg tool.
  -- p_schema_key is the provider's schema key (input_schema_key), because the base
  -- definition already carries the provider-specific name.
  function tool_param_names(
    p_tool_base  in json_object_t
  , p_schema_key in varchar2
  ) return varchar2
  as
    l_props json_object_t;
    l_keys  json_key_list;
    l_out   varchar2(4000 char);
  begin
    if not p_tool_base.has(p_schema_key) then
      return null;
    end if;
    l_props := p_tool_base.get_object(p_schema_key);
    if l_props is null or not l_props.has('properties') then
      return null;
    end if;
    l_keys := l_props.get_object('properties').get_keys();
    <<param_names_loop>>
    for i in 1 .. l_keys.count loop
      l_out := l_out || case when i > 1 then ', ' end || l_keys(i);
    end loop param_names_loop;
    return l_out;
  end tool_param_names;


  function get_tools_array (
    p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  , p_tool_tags       in apex_t_varchar2 default null
  , p_enable_tools    in boolean default null
  , p_provider_tools  in json_array_t default null
  , p_programmatic_tools       in boolean default false
  ) return json_array_t
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_tools_array';

    l_tools_array  json_array_t := json_array_t();
    l_tool_obj     json_object_t;
    l_tool_base    json_object_t;
    l_catalog      varchar2(32767 char);
    l_schema_key   varchar2(30 char);
    l_skipped_cat  pls_integer := 0;
    l_enable_tool_filter number(1) := 0; -- @dbLinter ignore(G-2410) used in SQL
    l_found_tools number := 0;
    -- Prefer explicitly threaded values (from the per-call settings record); fall
    -- back to the globals for direct callers that still rely on them. coalesce does
    -- not work on collection types, so branch explicitly.
    l_tool_tags    apex_t_varchar2; -- @dbLinter ignore(G-2410) used in SQL
    l_enable_tools boolean;
  begin
    l_schema_key := input_schema_key(p_provider, p_additional_info);

    if p_tool_tags is not null then
      l_tool_tags := p_tool_tags;
    else
      l_tool_tags := uc_ai.g_tool_tags;
    end if;

    if p_enable_tools is not null then
      l_enable_tools := p_enable_tools;
    else
      l_enable_tools := uc_ai.g_enable_tools;
    end if;

    uc_ai_logger.log('Building tools array for provider: ' || p_provider, l_scope, 'enable_tools=' || case when l_enable_tools then 'true' else 'false' end || ', tool_tags=' || apex_string.join(l_tool_tags, ', '));

    -- Local function tools are only fetched when tools are enabled. Provider
    -- tools (appended below) are sent regardless, so we do NOT early-return here.
    if l_enable_tools then

    if l_tool_tags is not null and l_tool_tags.count > 0 then
      l_enable_tool_filter := 1;
    end if;

    <<fetch_tools>>
    for rec in (
      select id, code_mode_access
        from uc_ai_tools
       where (
              l_enable_tool_filter = 0
               or id in (
                 select tt.tool_id
                   from uc_ai_tool_tags tt
                  where tt.tag_name member of l_tool_tags
                  group by tt.tool_id
               )
             )
         and active = 1
    )
    loop
      l_found_tools := l_found_tools + 1;
      l_tool_base := get_tool_schema(rec.id, p_provider, p_additional_info);

      -- In code mode, a tool's code_mode_access decides where it shows up:
      --   'direct' -> normal tool only, 'code' -> catalog only, 'both' -> both.
      -- (When code mode is off, code_mode_access is ignored and every tool is a
      -- normal tool, exactly as before.)

      -- Catalog entry (callable via callTool) for code/both tools. One line per
      -- tool, so newlines in a description are folded to keep the line intact.
      if p_programmatic_tools and rec.code_mode_access in ('code', 'both') then
        if nvl(length(l_catalog), 0) < 30000 then
          l_catalog := l_catalog
            || '  await callTool("' || l_tool_base.get_string('name') || '", { '
            || tool_param_names(l_tool_base, l_schema_key) || ' })  // '
            || substr(translate(l_tool_base.get_string('description'), chr(10) || chr(13) || chr(9), '   '), 1, 200) || chr(10);
        else
          l_skipped_cat := l_skipped_cat + 1;
        end if;
      end if;

      -- Direct (normal) tool for direct/both tools - and always when code mode is off.
      if not p_programmatic_tools or rec.code_mode_access in ('direct', 'both') then
        -- Providers expect different envelopes (openai/ollama/responses/oci);
        -- anthropic/google/xai/openrouter/mistral use the base form directly.
        l_tool_obj := format_tool_for_provider(l_tool_base, p_provider, p_additional_info);
        l_tools_array.append(l_tool_obj);
      end if;
    end loop fetch_tools;

    uc_ai_logger.log('Total tools found: ' || l_found_tools, l_scope);

    -- Programmatic tool calling: append the code-mode meta-tool, but only if at
    -- least one tool is actually code-callable (otherwise there is nothing to run).
    if p_programmatic_tools and l_catalog is not null then
      l_tools_array.append(
        format_tool_for_provider(
          build_code_mode_tool(l_catalog, p_provider, p_additional_info)
        , p_provider
        , p_additional_info
        )
      );
      uc_ai_logger.log('Appended code-mode meta-tool ' || c_code_mode_tool_code, l_scope);

      -- never drop tools from the catalog silently
      if l_skipped_cat > 0 then
        uc_ai_logger.log_warning(
          'Code-mode catalog size limit reached: ' || l_skipped_cat
          || ' tool(s) left out and NOT callable from a program'
        , l_scope
        );
      end if;
    end if;

    end if; -- l_enable_tools

    -- Append raw provider/server-side tool definitions verbatim (executed by the
    -- provider, not locally). Sent independently of enable_tools.
    if p_provider_tools is not null then
      <<provider_tools_loop>>
      for i in 0 .. p_provider_tools.get_size - 1 loop
        l_tools_array.append(p_provider_tools.get(i));
      end loop provider_tools_loop;
      uc_ai_logger.log('Appended ' || p_provider_tools.get_size || ' provider tool(s)', l_scope);
    end if;

    return l_tools_array;
  exception
    when others then
      uc_ai_logger.log_error('Error in get_tools_array: %s', sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace, l_scope);
      raise;
  end get_tools_array;


  /*
   * Executes a tool by calling its stored PL/SQL function with JSON arguments
   * 
   * Critical workflow for AI tool execution:
   * 1. Looks up function_call PL/SQL code from uc_ai_tools by tool code
   * 2. Scans for bind variables (:PARAM_NAME) - only allows ONE for security
   * 3. Binds the entire p_arguments JSON object to that variable
   * 4. Executes PL/SQL function using apex_plugin_util.get_plsql_func_result_clob
   * 5. Returns result to AI for further processing
   * 
   * Security: Only one bind variable allowed to prevent SQL injection
   * The PL/SQL function should parse the JSON and extract needed values
   */
  procedure before_tool_call(
    p_tool_code in uc_ai_tools.code%type
  , p_settings  in uc_ai_settings.t_settings default null
  )
  as
  begin
    uc_ai_agents_api.fire_before_tool_hook(
      p_tool_code   => p_tool_code
    , p_agent_id    => p_settings.ctx_agent_id
    , p_agent_code  => p_settings.ctx_agent_code
      -- attribute standalone (non-agent) tool calls to the DB session user
    , p_created_by  => coalesce(
                         p_settings.ctx_created_by
                       , sys_context('APEX$SESSION', 'app_user')
                       , sys_context('userenv', 'session_user')
                       )
    , p_session_id  => p_settings.ctx_session_id
    , p_apex_app_id => p_settings.ctx_apex_app_id
    );
  end before_tool_call;


  function execute_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  ) return clob
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'execute_tool';
    l_fc_code clob;
  begin
    begin
      select function_call
        into l_fc_code
        from uc_ai_tools
       where code = p_tool_code;
    exception
      when no_data_found then -- @dblinter ignore(g-5040): error is handled in raise_error
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_tool_not_found
        , p_scope      => l_scope
        , p0           => p_tool_code
        );
    end;

    return exec_function_call(
      p_function_call => l_fc_code
    , p_arguments     => p_arguments
    );
  exception
    when others then
      uc_ai_logger.log_error('Error in execute_tool: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_tool;


  -- ---- Code mode (programmatic tool calling) --------------------------------

  -- Save the current run context so a nested run can restore it (a program may
  -- call an agent-as-tool whose agent itself runs in code mode).
  function save_ptc_ctx return t_ptc_ctx
  as
    l_ctx t_ptc_ctx;
  begin
    l_ctx.active     := g_ptc_active;
    l_ctx.enable     := g_ptc_enable;
    l_ctx.tag_filter := g_ptc_tag_filter;
    l_ctx.tags       := g_ptc_tags;
    l_ctx.calls      := g_ptc_calls;
    l_ctx.max_calls  := g_ptc_max_calls;
    l_ctx.settings   := g_ptc_settings;
    l_ctx.veto_msg   := g_ptc_veto_msg;
    return l_ctx;
  end save_ptc_ctx;

  procedure restore_ptc_ctx(p_ctx in t_ptc_ctx)
  as
  begin
    g_ptc_active     := p_ctx.active;
    g_ptc_enable     := p_ctx.enable;
    g_ptc_tag_filter := p_ctx.tag_filter;
    g_ptc_tags       := p_ctx.tags;
    g_ptc_calls      := p_ctx.calls;
    g_ptc_max_calls  := p_ctx.max_calls;
    g_ptc_settings   := p_ctx.settings;
    g_ptc_veto_msg   := p_ctx.veto_msg;
  end restore_ptc_ctx;

  procedure begin_ptc_run(
    p_settings  in uc_ai_settings.t_settings
  , p_max_calls in pls_integer
  )
  as
    l_tool_tags apex_t_varchar2;
  begin
    -- Prefer the explicitly threaded per-call settings; fall back to the globals
    -- for direct callers that still rely on them (same rule as get_tools_array).
    if nvl(p_settings.initialized, false) then
      g_ptc_settings := p_settings;
      g_ptc_enable   := nvl(p_settings.enable_tools, false);
      l_tool_tags    := p_settings.tool_tags;
    else
      g_ptc_settings := uc_ai_settings.build_from_globals;
      g_ptc_enable   := nvl(uc_ai.g_enable_tools, false);
      l_tool_tags    := uc_ai.g_tool_tags;
    end if;

    if l_tool_tags is not null and l_tool_tags.count > 0 then
      g_ptc_tags       := l_tool_tags;
      g_ptc_tag_filter := 1;
    else
      g_ptc_tags       := apex_t_varchar2();
      g_ptc_tag_filter := 0;
    end if;
    g_ptc_calls     := 0;
    g_ptc_max_calls := nvl(p_max_calls, gc_ptc_max_inner_calls);
    g_ptc_veto_msg  := null;
    g_ptc_active    := true;
  end begin_ptc_run;

  procedure check_ptc_tool_allowed(
    p_tool_code in uc_ai_tools.code%type
  )
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'check_ptc_tool_allowed';
    l_cnt   pls_integer;
  begin
    if not g_ptc_active then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'code mode'
      , p1           => 'callTool used outside an active code-mode run'
      );
    end if;

    g_ptc_calls := g_ptc_calls + 1;
    if g_ptc_calls > g_ptc_max_calls then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'code mode call budget'
      , p1           => 'Exceeded the maximum of ' || g_ptc_max_calls || ' tool calls in one program'
      );
    end if;

    -- The tool must belong to THIS run's exposed set: active, and matching the
    -- run's tag filter (same predicate get_tools_array uses). This stops a
    -- program from reaching tools that were never offered for the run.
    if not g_ptc_enable then
      l_cnt := 0;
    else
      select count(*)
        into l_cnt
        from uc_ai_tools t
       where t.code = p_tool_code
         and t.active = 1
         and t.code_mode_access in ('code', 'both')
         and (
              g_ptc_tag_filter = 0
               or t.id in (
                 select tt.tool_id
                   from uc_ai_tool_tags tt
                  where tt.tag_name member of g_ptc_tags
               )
             );
    end if;

    if l_cnt = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_tool_not_found
      , p_scope      => l_scope
      , p0           => p_tool_code
      );
    end if;

    -- Inner calls go through the same per-tool-call hook as direct calls, so
    -- hook-based authorization and auditing cover tools called from a program too.
    -- A veto (the hook raising) blocks this call and is remembered: execute_agent_tool
    -- re-raises it after the run, so a veto still aborts the request rather than
    -- being swallowed into an error result the model may retry.
    begin
      before_tool_call(p_tool_code => p_tool_code, p_settings => g_ptc_settings);
    exception
      -- @dblinter ignore(G-5040): the veto is re-raised immediately; it is only recorded on the way out
      -- @dblinter ignore(G-5080): the hook's own error is re-raised unchanged; adding a backtrace here would hide the veto message the caller asserts on
      when others then
        g_ptc_veto_msg := substr(sqlerrm, 1, 4000);
        raise;
    end;
  end check_ptc_tool_allowed;

  /*
   * Is the code-mode sandbox installed for THIS schema?
   *
   * The sandbox installer creates a private synonym (c_ptc_runner_synonym) here that
   * points at the runner in the sandbox schema it created, so both schema names stay
   * the DBA's choice and two UC AI installs never share a sandbox. Resolving the
   * synonym also tells us the sandbox schema for log and error messages.
   */
  function ptc_runner_available return boolean
  as
    l_cnt pls_integer;
  begin
    -- Only a positive result is cached: sessions are long-lived in ORDS/APEX pools,
    -- so caching "absent" would keep code mode disabled in pooled sessions that
    -- existed before the sandbox was installed.
    if g_ptc_runner_ok = 1 then
      return true;
    end if;

    -- Checks the package SPEC, not the body: ALL_OBJECTS is privilege-filtered, and
    -- an EXECUTE grant only ever exposes the spec to the grantee. A least-privilege
    -- UC AI schema therefore never sees the sandbox's PACKAGE BODY row, so matching
    -- on it would report "not installed" on every correct installation. (Dev schemas
    -- with DB_DEVELOPER_ROLE do see the body, which masks the difference.) A valid
    -- spec plus the private synonym is exactly what makes the runner callable; if the
    -- body were missing or invalid, the dynamic call raises a clear ORA-04063 anyway.
    -- @dblinter ignore(G-8110): presence check for the sandbox runner; a scalar count is the clearest form here
    select count(*)
      into l_cnt
      from all_synonyms syn
      join all_objects obj
        on obj.owner = syn.table_owner
       and obj.object_name = syn.table_name
     where syn.owner = $$plsql_unit_owner
       and syn.synonym_name = c_ptc_runner_synonym
       and obj.object_type = 'PACKAGE'
       and obj.status = 'VALID';

    if l_cnt > 0 then
      g_ptc_runner_ok := 1;
    end if;

    return l_cnt > 0;
  end ptc_runner_available;

  /*
   * Hands the model-authored program to the sandbox runner.
   *
   * Called dynamically only to avoid a compile-time dependency on the optional
   * sandbox package. The runner evaluates the program in a PURE MLE context, which
   * has no SQL access at all, so the generated JavaScript cannot commit or roll
   * back the caller's transaction; the tools it calls run in the caller's
   * transaction exactly like a direct tool call.
   */
  function run_in_sandbox(p_code in clob) return clob
  as
    l_result clob;
    -- @dblinter ignore(G-6010): statement built from a compile-time constant (no user input) with both binds bound
    l_stmt   varchar2(200 char) := 'begin :r := ' || c_ptc_runner_synonym || '.run_code(:c); end;';
  begin
    execute immediate l_stmt using out l_result, in p_code;
    return l_result;
  end run_in_sandbox;

  function execute_agent_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  , p_settings  in uc_ai_settings.t_settings default null
  ) return clob
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'execute_agent_tool';
    l_result clob;
    l_code   clob;
    l_outer  t_ptc_ctx;
    l_veto   varchar2(4000 char);
  begin
    -- Normal tool: unchanged behaviour.
    if p_tool_code <> c_code_mode_tool_code then
      return execute_tool(p_tool_code => p_tool_code, p_arguments => p_arguments);
    end if;

    -- Code mode is mandatory-sandboxed: run the model-authored program in the
    -- dedicated low-privilege schema, or fail clearly. There is no in-schema path.
    if not ptc_runner_available then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_missing_config
      , p_scope      => l_scope
      , p0           => c_ptc_runner_synonym
      , p_message    => 'Code mode requires the MLE sandbox, which is not installed for this schema (no valid %0 synonym). Run scripts/install_ptc_sandbox.sql as a DBA to enable code mode.'
      );
    end if;

    -- get_clob, not get_string: generated programs can exceed the 32 KB varchar2 limit
    l_code := p_arguments.get_clob('code');

    -- Publish this run's allow-list + budget for the gateway, invoke the sandbox,
    -- and always restore the previous context afterwards (a nested code-mode run
    -- must not deactivate the outer one).
    l_outer := save_ptc_ctx;
    begin_ptc_run(
      p_settings  => p_settings
    , p_max_calls => gc_ptc_max_inner_calls
    );

    begin
      l_result := run_in_sandbox(l_code);
      l_veto   := g_ptc_veto_msg;
      restore_ptc_ctx(l_outer);
    exception
      when others then
        restore_ptc_ctx(l_outer);
        raise;
    end;

    -- A per-tool-call hook veto for an inner call must abort the request, not come
    -- back as an error result the model can retry (the runner turns every failure
    -- inside the program into data, which would otherwise swallow the veto).
    if l_veto is not null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'code mode tool call'
      , p1           => 'vetoed by the before_tool_call hook: ' || l_veto
      );
    end if;

    return l_result;
  exception
    when others then
      uc_ai_logger.log_error('Error in execute_agent_tool: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end execute_agent_tool;


  function exec_function_call(
    p_function_call in clob
  , p_arguments     in json_object_t
  ) return clob
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'exec_function_call';

    l_fc_code      clob := p_function_call;
    l_found_binds  apex_t_varchar2 := apex_t_varchar2();
    l_bind_list    apex_plugin_util.t_bind_list := apex_plugin_util.c_empty_bind_list;
    l_bind         apex_plugin_util.t_bind;
    l_return       clob;

    l_clob         clob;
    l_cursor_id    pls_integer;
    l_rows_fetched pls_integer;
    l_bind_value   clob;
    l_plsql_block  varchar2(32767 char);
  begin

    -- Extract bind variables from the PL/SQL function call
    -- Security: Only allow ONE bind variable to prevent complex injection attacks
    -- The entire JSON arguments object gets bound to this single parameter
    l_found_binds := apex_string.grep ( 
      p_str           => l_fc_code
    , p_pattern       => ':([a-zA-Z0-9:\_]+)'
    , p_modifier      => 'i'
    , p_subexpression => '1'
    );

    -- use apex_plugin_util.get_plsql_func_result_clob if apex_session is available
    if apex_application.g_instance is not null then

      uc_ai_logger.log('Executing tool with apex_plugin_util.get_plsql_func_result_clob', l_scope, l_fc_code);

      if l_found_binds is null or l_found_binds.count = 0 then
        null;
      elsif l_found_binds.count = 1 then
        -- Bind the entire JSON arguments object to the single parameter
        -- Tool function must parse JSON to extract individual values
        l_bind.name  := upper(l_found_binds(1));
        l_bind.value := p_arguments.to_clob;
        l_bind_list(1) := l_bind;
        uc_ai_logger.log('Bind variable found', l_scope, l_bind.name || ' = ' || l_bind.value);
      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'tool function call'
        , p1           => 'Multiple bind variables found: ' || apex_string.join(l_found_binds, ', ') || '. Only one parameter bind is allowed.'
        );
      end if;

      uc_ai_logger.log('Executing tool', l_scope, l_fc_code);

      -- Execute the tool's PL/SQL function with bound arguments
      -- Function should return CLOB result that gets sent back to AI
      l_return := apex_plugin_util.get_plsql_func_result_clob (
        p_plsql_function   => l_fc_code
      , p_auto_bind_items  => false
      , p_bind_list        => l_bind_list
      );
    
      uc_ai_logger.log('Tool execution result', l_scope, l_return);

      if l_return is null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'tool execution'
        , p1           => 'Function call execution returned NULL'
        );
      end if;

      return l_return;

    else
      uc_ai_logger.log('Executing tool with dbms_sql', l_scope, l_fc_code);

      l_plsql_block := '
        DECLARE
          function user_function
          return clob
          as
          begin
            ' || l_fc_code || '
          end user_function;
        BEGIN
          :return_val := user_function;
        END;';

      if l_found_binds is null or l_found_binds.count = 0 then
        -- No binds, directly execute a block that selects the function result into a CLOB variable
        -- For DBMS_SQL, we need a full PL/SQL block that assigns the result to an OUT variable
        
        l_cursor_id := sys.dbms_sql.open_cursor;
        uc_ai_logger.log('l_plsql_block', l_scope, l_plsql_block);
        sys.dbms_sql.parse(l_cursor_id, l_plsql_block, sys.dbms_sql.native);
        sys.dbms_sql.bind_variable(l_cursor_id, ':return_val', l_clob); -- Bind the OUT variable

        l_rows_fetched := sys.dbms_sql.execute(l_cursor_id);
        sys.dbms_sql.variable_value(l_cursor_id, ':return_val', l_clob); -- Get the value from the OUT variable
        sys.dbms_sql.close_cursor(l_cursor_id);

        l_return := l_clob;
      elsif l_found_binds.count = 1 then
        -- Bind the entire JSON arguments object to the single parameter
        -- Tool function must parse JSON to extract individual values
        l_bind.name  := upper(l_found_binds(1));
        l_bind.value := p_arguments.to_clob;
        l_bind_value := l_bind.value;

        uc_ai_logger.log('Bind variable found', l_scope, l_bind.name || ' = ' || l_bind.value);

        -- Construct the PL/SQL block for DBMS_SQL with a bind variable and an OUT parameter
        l_plsql_block := replace(l_plsql_block, ':' || l_bind.name, ':' || l_bind.name);
        uc_ai_logger.log('l_plsql_block', l_scope, l_plsql_block);

        l_cursor_id := sys.dbms_sql.open_cursor;
        sys.dbms_sql.parse(l_cursor_id, l_plsql_block, sys.dbms_sql.native);

        -- Bind the input CLOB variable
        sys.dbms_sql.bind_variable(l_cursor_id, ':' || l_bind.name, l_bind_value);
        -- Bind the OUT CLOB variable for the function's result
        sys.dbms_sql.bind_variable(l_cursor_id, ':return_val', l_clob);

        l_rows_fetched := sys.dbms_sql.execute(l_cursor_id);
        sys.dbms_sql.variable_value(l_cursor_id, ':return_val', l_clob); -- Get the value from the OUT variable
        sys.dbms_sql.close_cursor(l_cursor_id);

        l_return := l_clob;

      else
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'tool function call'
        , p1           => 'Multiple bind variables found: ' || apex_string.join(l_found_binds, ', ') || '. Only one parameter bind is allowed.'
        );
      end if;
    end if;

    return l_return;
  exception
    when others then
      uc_ai_logger.log_error('Error in exec_function_call: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;

  end exec_function_call;


  function get_tools_object_param_name (
    p_tool_code in uc_ai_tools.code%type
  ) return uc_ai_tool_parameters.name%type result_cache
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'get_tools_object_param_name';
    l_count pls_integer;
    l_param_name uc_ai_tool_parameters.name%type;
  begin
    select count(*)  -- @dblinter ignore(G-8110) we check for exactly 1
      into l_count
      from uc_ai_tool_parameters tp
      join uc_ai_tools t
        on tp.tool_id = t.id
      where t.code = p_tool_code
        and parent_param_id is null
        and data_type = 'object';

    if l_count != 1 then
      return null; -- Not exactly one top-level parameter, return null
    end if;

    -- Get the parameter name for the tool's input object
    select tp.name
      into l_param_name
      from uc_ai_tool_parameters tp
      join uc_ai_tools t
        on tp.tool_id = t.id
     where t.code = p_tool_code
       and parent_param_id is null
    ;

    return l_param_name;
  exception
    when no_data_found then
      return null; -- No parameter found, return null
    when others then
      uc_ai_logger.log_error('Error in get_tools_object_param_name: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end get_tools_object_param_name;

  /*
   * Recursive procedure to create parameters from JSON schema properties
   */
  procedure create_parameters_recursive(
    p_properties in json_object_t,
    p_required_keys in json_key_list,
    p_parent_param_id in uc_ai_tool_parameters.id%type default null,
    p_created_by in varchar2,
    p_tool_id in uc_ai_tools.id%type
  ) 
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'create_parameters_recursive';

    l_prop_keys_arr json_key_list;
    l_prop_name varchar2(255 char);
    l_prop_obj json_object_t;
    l_current_param_id uc_ai_tool_parameters.id%type;
    l_is_required number(1);
    l_data_type varchar2(255 char);
    l_description varchar2(4000 char);
    l_min_num_val number;
    l_max_num_val number;
    l_enum_values varchar2(4000 char);
    l_default_value varchar2(4000 char);
    l_is_array boolean := false;
    l_is_array_num number(1);
    l_array_min_items number;
    l_array_max_items number;
    l_pattern varchar2(4000 char);
    l_format varchar2(255 char);
    l_min_length number;
    l_max_length number;
    l_enum_arr json_array_t;
    l_enum_str_arr apex_t_varchar2 := apex_t_varchar2();
    l_nested_properties json_object_t;
    l_nested_required json_array_t;
    l_nested_required_keys_arr json_key_list := json_key_list();
  begin
    if p_properties is null then
      return;
    end if;
    
    l_prop_keys_arr := p_properties.get_keys;
    
    if l_prop_keys_arr is null or l_prop_keys_arr.count = 0 then
      return;
    end if;
    
    <<property_loop>>
    for i in 1 .. l_prop_keys_arr.count loop
      l_prop_name := l_prop_keys_arr(i);
      l_prop_obj := treat(p_properties.get(l_prop_name) as json_object_t);
      
      if l_prop_obj is null then
        uc_ai_logger.log_warn('Property object is null for: ' || l_prop_name, l_scope);
        continue;
      end if;
      
      -- Reset variables for each property
      l_data_type := null;
      l_description := null;
      l_min_num_val := null;
      l_max_num_val := null;
      l_enum_values := null;
      l_default_value := null;
      l_is_array := false;
      l_array_min_items := null;
      l_array_max_items := null;
      l_pattern := null;
      l_format := null;
      l_min_length := null;
      l_max_length := null;
      
      -- Extract basic properties
      l_data_type := l_prop_obj.get_string('type');
      l_description := l_prop_obj.get_string('description');
      
      -- Check if this property is required
      l_is_required := 0;
      if p_required_keys is not null then
        <<check_required>>
        for j in 1 .. p_required_keys.count loop
          if p_required_keys(j) = l_prop_name then
            l_is_required := 1;
            exit;
          end if;
        end loop check_required;
      end if;
      
      -- Handle array type
      if l_data_type = 'array' then
        l_is_array := true;
        l_array_min_items := l_prop_obj.get_number('minItems');
        l_array_max_items := l_prop_obj.get_number('maxItems');
        
        -- Get the items schema for array element type
        declare
          l_items_obj json_object_t;
        begin
          l_items_obj := treat(l_prop_obj.get('items') as json_object_t);
          if l_items_obj is not null then
            l_data_type := l_items_obj.get_string('type');
            -- Copy other properties from items schema
            if l_data_type = 'string' then
              l_min_length := l_items_obj.get_number('minLength');
              l_max_length := l_items_obj.get_number('maxLength');
              l_pattern := l_items_obj.get_string('pattern');
              l_format := l_items_obj.get_string('format');
            elsif l_data_type in ('number', 'integer') then
              l_min_num_val := l_items_obj.get_number('minimum');
              l_max_num_val := l_items_obj.get_number('maximum');
            end if;
            
            -- Handle enum in items
            l_enum_arr := treat(l_items_obj.get('enum') as json_array_t);
          end if;
        end;
      else
        -- Handle non-array types
        if l_data_type = 'string' then
          l_min_length := l_prop_obj.get_number('minLength');
          l_max_length := l_prop_obj.get_number('maxLength');
          l_pattern := l_prop_obj.get_string('pattern');
          l_format := l_prop_obj.get_string('format');
        elsif l_data_type in ('number', 'integer') then
          l_min_num_val := l_prop_obj.get_number('minimum');
          l_max_num_val := l_prop_obj.get_number('maximum');
        end if;
        
        -- Handle enum
        l_enum_arr := treat(l_prop_obj.get('enum') as json_array_t);
      end if;
      
      -- Process enum values
      if l_enum_arr is not null and l_enum_arr.get_size > 0 then
        l_enum_str_arr := apex_t_varchar2();
        <<enum_loop>>
        for j in 0 .. l_enum_arr.get_size - 1 loop
          l_enum_str_arr.extend;
          l_enum_str_arr(l_enum_str_arr.count) := l_enum_arr.get_string(j);
        end loop enum_loop;
        l_enum_values := apex_string.join(l_enum_str_arr, ':');
      end if;
      
      -- Handle default value
      if l_prop_obj.has('default') then
        case l_data_type
          when 'string' then
            l_default_value := l_prop_obj.get_string('default');
          when 'boolean' then
            l_default_value := case when l_prop_obj.get_boolean('default') then '1' else '0' end;
          when 'number' then
            l_default_value := to_char(l_prop_obj.get_number('default'));
          when 'integer' then
            l_default_value := to_char(l_prop_obj.get_number('default'));
          else
            l_default_value := l_prop_obj.get_string('default');
        end case;
      end if;

      l_is_array_num := case when l_is_array then 1 else 0 end;

      -- Insert the parameter
      insert into uc_ai_tool_parameters ( -- @dbLinter ignore(G-3210) we do not process too many rows and do pre-processing
        tool_id,
        name,
        description,
        required,
        data_type,
        min_num_val,
        max_num_val,
        enum_values,
        default_value,
        is_array,
        array_min_items,
        array_max_items,
        pattern,
        format,
        min_length,
        max_length,
        parent_param_id,
        created_by,
        created_at,
        updated_by,
        updated_at
      ) values (
        p_tool_id,
        l_prop_name,
        nvl(l_description, 'Parameter: ' || l_prop_name),
        l_is_required,
        l_data_type,
        l_min_num_val,
        l_max_num_val,
        l_enum_values,
        l_default_value,
        l_is_array_num,
        l_array_min_items,
        l_array_max_items,
        l_pattern,
        l_format,
        l_min_length,
        l_max_length,
        p_parent_param_id,
        p_created_by,
        systimestamp,
        p_created_by,
        systimestamp
      ) returning id into l_current_param_id;
      
      -- Handle nested object properties
      if l_data_type = 'object' then
        l_nested_properties := treat(l_prop_obj.get('properties') as json_object_t);
        l_nested_required := treat(l_prop_obj.get('required') as json_array_t);
        
        -- Convert required array to key list
        l_nested_required_keys_arr := json_key_list();
        if l_nested_required is not null then
          <<nested_required_loop>>
          for j in 0 .. l_nested_required.get_size - 1 loop
            l_nested_required_keys_arr.extend;
            l_nested_required_keys_arr(l_nested_required_keys_arr.count) := l_nested_required.get_string(j);
          end loop nested_required_loop;
        end if;
        
        -- Recursively create nested parameters
        create_parameters_recursive(
          p_properties => l_nested_properties
        , p_required_keys => l_nested_required_keys_arr
        , p_parent_param_id => l_current_param_id
        , p_created_by => p_created_by
        , p_tool_id => p_tool_id
      );
      end if;
      
    end loop property_loop;
  exception
    when others then
      uc_ai_logger.log_error('Error in create_parameters_recursive: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;  
  end create_parameters_recursive;

  /*
   * Inserts tags for a tool.
   *
   * Tag names are lowercased to satisfy the uc_ai_tool_tags_tag_lower_ck check
   * constraint and de-duplicated (case-insensitively) before insert. Without the
   * de-duplication a p_tags array containing repeated or case-variant values
   * (e.g. 'Foo' and 'foo') would violate the uc_ai_tool_tags_uk unique key
   * (tool_id, tag_name) and raise ORA-00001, aborting the enclosing tool merge.
   */
  procedure insert_tool_tags(
    p_tool_id    in uc_ai_tools.id%type
  , p_tags       in apex_t_varchar2
  , p_created_by in uc_ai_tool_tags.created_by%type
  )
  as
  begin
    if p_tags is null or p_tags.count = 0 then
      return;
    end if;

    insert into uc_ai_tool_tags (
      tool_id,
      tag_name,
      created_by,
      created_at,
      updated_by,
      updated_at
    )
    select p_tool_id,
           tag_name,
           p_created_by,
           systimestamp,
           p_created_by,
           systimestamp
      from (
        select distinct lower(column_value) as tag_name
          from table(p_tags)
         where column_value is not null
      );
  end insert_tool_tags;

  /*
   * Creates a new tool definition from a JSON schema
   */
  function create_tool_from_schema(
    p_tool_code             in uc_ai_tools.code%type,
    p_description           in uc_ai_tools.description%type,
    p_function_call         in uc_ai_tools.function_call%type,
    p_json_schema           in json_object_t,
    p_active                in uc_ai_tools.active%type default 1,
    p_version               in uc_ai_tools.version%type default '1.0',
    p_authorization_schema  in uc_ai_tools.authorization_schema%type default null,
    p_created_by            in uc_ai_tools.created_by%type default coalesce(sys_context('APEX$SESSION','app_user'), sys_context('userenv', 'session_user')),
    p_tags                  in apex_t_varchar2 default apex_t_varchar2(),
    p_code_mode_access      in uc_ai_tools.code_mode_access%type default 'both'
  ) return uc_ai_tools.id%type
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'create_tool_from_schema';

    l_tool_id uc_ai_tools.id%type;
    l_properties json_object_t;
    l_required_arr json_array_t;
    l_required_keys_arr json_key_list := json_key_list();
    l_schema_clob clob;
  begin
    uc_ai_logger.log('Creating tool from schema', l_scope, 'Tool: ' || p_tool_code);

    l_schema_clob := case when p_json_schema is not null then p_json_schema.to_clob else null end;

    -- Create the tool record
    insert into uc_ai_tools (
      code,
      description,
      active,
      response_schema,
      version,
      function_call,
      authorization_schema,
      code_mode_access,
      created_by,
      created_at,
      updated_by,
      updated_at
    ) values (
      p_tool_code,
      p_description,
      p_active,
      l_schema_clob, -- Store the original schema for reference
      p_version,
      p_function_call,
      p_authorization_schema,
      p_code_mode_access,
      p_created_by,
      systimestamp,
      p_created_by,
      systimestamp
    ) returning id into l_tool_id;

    uc_ai_logger.log('Created tool with ID: ' || l_tool_id, l_scope);

    if l_schema_clob is null then
      return l_tool_id;
    end if;

    -- Extract properties and required array from schema
    l_properties := treat(p_json_schema.get('properties') as json_object_t);
    l_required_arr := treat(p_json_schema.get('required') as json_array_t);

    -- Convert required array to key list for easier processing
    if l_required_arr is not null then
      <<required_loop>>
      for i in 0 .. l_required_arr.get_size - 1 loop
        l_required_keys_arr.extend;
        l_required_keys_arr(l_required_keys_arr.count) := l_required_arr.get_string(i);
      end loop required_loop;
    end if;

    -- Create parameters from schema properties
    create_parameters_recursive(
      p_properties => l_properties
    , p_required_keys => l_required_keys_arr
    , p_parent_param_id => null
    , p_created_by => p_created_by
    , p_tool_id => l_tool_id
    );

    -- Create tags if provided
    insert_tool_tags(
      p_tool_id    => l_tool_id
    , p_tags       => p_tags
    , p_created_by => p_created_by
    );

    uc_ai_logger.log('Successfully created tool with schema', l_scope, 'Tool ID: ' || l_tool_id);

    return l_tool_id;

  exception
    when others then
      uc_ai_logger.log_error('Error in create_tool_from_schema', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end create_tool_from_schema;

  /*
   * Creates or updates a tool definition from a JSON schema
   *
   * If a tool with the same code already exists, it will be updated.
   * Parameters and tags are replaced (deleted and recreated) on update.
   */
  function merge_tool_from_schema(
    p_tool_code             in uc_ai_tools.code%type,
    p_description           in uc_ai_tools.description%type,
    p_function_call         in uc_ai_tools.function_call%type,
    p_json_schema           in json_object_t,
    p_active                in uc_ai_tools.active%type default 1,
    p_version               in uc_ai_tools.version%type default '1.0',
    p_authorization_schema  in uc_ai_tools.authorization_schema%type default null,
    p_created_by            in uc_ai_tools.created_by%type default coalesce(sys_context('APEX$SESSION','app_user'), sys_context('userenv', 'session_user')),
    p_tags                  in apex_t_varchar2 default apex_t_varchar2(),
    p_code_mode_access      in uc_ai_tools.code_mode_access%type default null
  ) return uc_ai_tools.id%type
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'merge_tool_from_schema';

    l_tool_id uc_ai_tools.id%type;
    l_existing_tool_id uc_ai_tools.id%type;
    l_properties json_object_t;
    l_required_arr json_array_t;
    l_required_keys_arr json_key_list := json_key_list();
    l_schema_clob clob;
  begin
    uc_ai_logger.log('Merging tool from schema', l_scope, 'Tool: ' || p_tool_code);

    l_schema_clob := case when p_json_schema is not null then p_json_schema.to_clob else null end;

    -- Check if tool already exists
    begin
      select id
        into l_existing_tool_id
        from uc_ai_tools
       where code = p_tool_code;
    exception
      when no_data_found then
        l_existing_tool_id := null;
    end;

    if l_existing_tool_id is not null then
      -- Update existing tool
      update uc_ai_tools
         set description          = p_description,
             active               = p_active,
             response_schema      = l_schema_clob,
             version              = p_version,
             function_call        = p_function_call,
             authorization_schema = p_authorization_schema,
             -- null keeps the stored value: re-running a merge script must not
             -- silently widen a tool that was narrowed to 'direct' or 'code'
             code_mode_access     = nvl(p_code_mode_access, code_mode_access),
             updated_by           = p_created_by,
             updated_at           = systimestamp
       where id = l_existing_tool_id;

      l_tool_id := l_existing_tool_id;

      uc_ai_logger.log('Updated existing tool with ID: ' || l_tool_id, l_scope);

      -- Delete existing parameters (cascade will handle nested params)
      delete from uc_ai_tool_parameters
       where tool_id = l_tool_id;

      -- Delete existing tags
      delete from uc_ai_tool_tags
       where tool_id = l_tool_id;
    else
      -- Create new tool record
      insert into uc_ai_tools (
        code,
        description,
        active,
        response_schema,
        version,
        function_call,
        authorization_schema,
        code_mode_access,
        created_by,
        created_at,
        updated_by,
        updated_at
      ) values (
        p_tool_code,
        p_description,
        p_active,
        l_schema_clob,
        p_version,
        p_function_call,
        p_authorization_schema,
        nvl(p_code_mode_access, 'both'),
        p_created_by,
        systimestamp,
        p_created_by,
        systimestamp
      ) returning id into l_tool_id;

      uc_ai_logger.log('Created new tool with ID: ' || l_tool_id, l_scope);
    end if;

    if l_schema_clob is null then
      return l_tool_id;
    end if;

    -- Extract properties and required array from schema
    l_properties := treat(p_json_schema.get('properties') as json_object_t);
    l_required_arr := treat(p_json_schema.get('required') as json_array_t);

    -- Convert required array to key list for easier processing
    if l_required_arr is not null then
      <<required_loop>>
      for i in 0 .. l_required_arr.get_size - 1 loop
        l_required_keys_arr.extend;
        l_required_keys_arr(l_required_keys_arr.count) := l_required_arr.get_string(i);
      end loop required_loop;
    end if;

    -- Create parameters from schema properties
    create_parameters_recursive(
      p_properties => l_properties
    , p_required_keys => l_required_keys_arr
    , p_parent_param_id => null
    , p_created_by => p_created_by
    , p_tool_id => l_tool_id
    );

    -- Create tags if provided
    insert_tool_tags(
      p_tool_id    => l_tool_id
    , p_tags       => p_tags
    , p_created_by => p_created_by
    );

    uc_ai_logger.log('Successfully merged tool with schema', l_scope, 'Tool ID: ' || l_tool_id);

    return l_tool_id;

  exception
    when others then
      uc_ai_logger.log_error('Error in merge_tool_from_schema', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end merge_tool_from_schema;

end uc_ai_tools_api;
/
