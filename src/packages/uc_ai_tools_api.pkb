create or replace package body uc_ai_tools_api as 

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';


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
    l_scope logger_logs.scope%type := gc_scope_prefix || 'convert_input_schema_to_cohere';
    
    l_result_obj     json_object_t := json_object_t();
    l_properties     json_object_t;
    l_parameters_obj json_object_t;
    l_param_props    json_object_t;
    l_required_arr   json_array_t;
    l_param_obj      json_object_t;
    l_keys           json_key_list;
    l_required_keys  json_key_list;
    l_prop_name      varchar2(255 char);
    l_is_required    boolean;
    
  begin
    -- Get the properties object from the input schema
    l_properties := treat(p_input_schema.get('properties') as json_object_t);
    
    if l_properties is null then
      logger.log_error('No properties found in input schema', l_scope);
      return l_result_obj;
    end if;
    
    -- Look for the parameters object within properties
    -- In most cases this will be the first (and likely only) property
    l_keys := l_properties.get_keys;
    
    if l_keys is null or l_keys.count = 0 then
      logger.log_error('No properties keys found in input schema', l_scope);
      return l_result_obj;
    end if;
    
    -- Get the first property (assumed to be the parameters object)
    l_parameters_obj := treat(l_properties.get(l_keys(1)) as json_object_t);
    
    if l_parameters_obj is null then
      logger.log_error('Parameters object is null for key: %s', l_scope, l_keys(1));
      return l_result_obj;
    end if;
    
    -- Get the properties within the parameters object
    l_param_props := treat(l_parameters_obj.get('properties') as json_object_t);
    
    if l_param_props is null then
      logger.log_error('No properties found in parameters object', l_scope);
      return l_result_obj;
    end if;
    
    -- Get the required array from the parameters object
    l_required_arr := treat(l_parameters_obj.get('required') as json_array_t);
    
    -- Convert required array to a list for easier lookup
    l_required_keys := json_key_list();
    if l_required_arr is not null then
      <<required_loop>>
      for i in 0 .. l_required_arr.get_size - 1 loop
        l_required_keys.extend;
        l_required_keys(l_required_keys.count) := l_required_arr.get_string(i);
      end loop required_loop;
    end if;
    
    -- Process each property in the parameters
    l_keys := l_param_props.get_keys;
    
    <<property_loop>>
    for i in 1 .. l_keys.count loop
      l_prop_name := l_keys(i);
      l_param_obj := treat(l_param_props.get(l_prop_name) as json_object_t);
      
      if l_param_obj is not null then
        -- Clone the parameter object to avoid modifying the original
        l_param_obj := l_param_obj.clone();
        
        -- Check if this property is required
        l_is_required := false;
        if l_required_keys is not null then
          <<check_required>>
          for j in 1 .. l_required_keys.count loop
            if l_required_keys(j) = l_prop_name then
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
    
    logger.log('Converted schema to Cohere format', l_scope, l_result_obj.to_clob());
    
    return l_result_obj;
    
  exception
    when others then
      logger.log_error('Error in convert_input_schema_to_cohere: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
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
      logger.log_error('Error in wrap_as_array: %s', sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
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
  , po_param_obj   out    json_object_t
  )
  as
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
        logger.log_error('Unhandled data type: %s', p_row.data_type);
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
      apex_debug.error('Error in prepare_single_parameter: %s', sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end prepare_single_parameter;


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
    l_scope logger_logs.scope%type := gc_scope_prefix || 'get_tool_schema';

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

    select count(*)
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

    if p_provider in (uc_ai.c_provider_google, uc_ai.c_provider_ollama) then
      l_input_schema_name := 'parameters';
    else
      l_input_schema_name := 'input_schema';
    end if;
    
    l_function.put(l_input_schema_name, l_input_schema);
    l_function.put('name', l_tool_code);
    l_function.put('description', l_tool_description);
  
    return l_function;
  exception
    when others then
      apex_debug.error('Error in get_tool_schema: %s', sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  END get_tool_schema;


  function get_tools_array (
    p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  ) return json_array_t
  as
    l_scope logger_logs.scope%type := gc_scope_prefix || 'get_tools_array';

    l_tools_array  json_array_t := json_array_t();
    l_tool_obj     json_object_t;
    l_tool_cpy_obj json_object_t;
    l_enable_tool_filter boolean := false;
  begin
    if not uc_ai.g_enable_tools then
      return l_tools_array;
    end if;

    if uc_ai.g_tool_tags is not null and uc_ai.g_tool_tags.count > 0 then
      l_enable_tool_filter := true;
    end if;

    <<fetch_tools>>
    for rec in (
      select id
        from uc_ai_tools
       where (
              not l_enable_tool_filter
               or id in (
                 select tt.tool_id
                   from uc_ai_tool_tags tt
                  where tt.tag_name member of uc_ai.g_tool_tags
                  group by tt.tool_id
               )
             )
         and active = 1
    )
    loop
      l_tool_obj := get_tool_schema(rec.id, p_provider, p_additional_info);

      -- openai has an additional object wrapper for function calls
      -- {type: "function", function: {...}}
      -- where others like anthropic/claude use the function object directly
      if p_provider in (uc_ai.c_provider_openai, uc_ai.c_provider_ollama) then
        l_tool_cpy_obj := l_tool_obj.clone();

        l_tool_obj := json_object_t();
        l_tool_obj.put('type', 'function');
        l_tool_obj.put('function', l_tool_cpy_obj);
      elsif p_provider = uc_ai.c_provider_oci then
        l_tool_cpy_obj := l_tool_obj.clone();
        logger.log('Creating tool schema for OCI provider (' || p_additional_info || ')', l_scope, l_tool_cpy_obj.to_clob());

        l_tool_obj := json_object_t();
        if p_additional_info != gc_cohere then
          l_tool_obj.put('type', 'FUNCTION');
        end if;

        l_tool_obj.put('description', l_tool_cpy_obj.get_string('description'));
        l_tool_obj.put('name', l_tool_cpy_obj.get_string('name'));

        if p_additional_info != gc_cohere then
          l_tool_obj.put('parameters', l_tool_cpy_obj.get_object('input_schema'));
        else
          l_tool_obj.put('parameterDefinitions',  convert_input_schema_to_cohere(l_tool_cpy_obj.get_object('input_schema')));
        end if;
      end if;

      l_tools_array.append(l_tool_obj);
    end loop fetch_tools;

    return l_tools_array;
  exception
    when others then
      apex_debug.error('Error in get_tools_array: %s', sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
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
  function execute_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  ) return clob
  as
    l_scope logger_logs.scope%type := gc_scope_prefix || 'execute_tool';

    l_fc_code      clob;
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
    select function_call
      into l_fc_code
      from uc_ai_tools
     where code = p_tool_code;

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
    if sys_context('APEX$SESSION', 'APP_SESSION') is not null then

      logger.log('Executing tool with apex_plugin_util.get_plsql_func_result_clob', l_scope, l_fc_code);

      if l_found_binds is null or l_found_binds.count = 0 then
        null;
      elsif l_found_binds.count = 1 then
        -- Bind the entire JSON arguments object to the single parameter
        -- Tool function must parse JSON to extract individual values
        l_bind.name  := upper(l_found_binds(1));
        l_bind.value := p_arguments.to_clob;
        l_bind_list(1) := l_bind;
        logger.log('Bind variable found', l_scope, l_bind.name || ' = ' || l_bind.value);
      else
        logger.log_error('Error in execute_tool: %s', 'Multiple bind variables found in tool fc code: ' || apex_string.join(l_found_binds, ', '));
        raise_application_error(-20001, 'You are only allowed to set one parameter bind. Multiple bind variables found in tool fc code: ' || apex_string.join(l_found_binds, ', '));
      end if;

      logger.log('Executing tool', l_scope, l_fc_code);

      -- Execute the tool's PL/SQL function with bound arguments
      -- Function should return CLOB result that gets sent back to AI
      l_return := apex_plugin_util.get_plsql_func_result_clob (
        p_plsql_function   => l_fc_code
      , p_auto_bind_items  => false
      , p_bind_list        => l_bind_list
      );
    
      logger.log('Tool execution result', l_scope, l_return);

      if l_return is null then
        logger.log_error('Error in execute_tool: %s', 'Tool execution returned NULL');
        raise_application_error(-20001, 'Tool execution returned NULL');
      end if;

      return l_return;

    else
      logger.log('Executing tool with dbms_sql', l_scope, l_fc_code);

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
        logger.log('l_plsql_block', l_scope, l_plsql_block);
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

        logger.log('Bind variable found', l_scope, l_bind.name || ' = ' || l_bind.value);

        -- Construct the PL/SQL block for DBMS_SQL with a bind variable and an OUT parameter
        l_plsql_block := replace(l_plsql_block, ':' || l_bind.name, ':' || l_bind.name);
        logger.log('l_plsql_block', l_scope, l_plsql_block);

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
        logger.log_error('Error in execute_tool: %s', 'Multiple bind variables found in tool fc code: ' || apex_string.join(l_found_binds, ', '));
        raise_application_error(-20001, 'You are only allowed to set one parameter bind. Multiple bind variables found in tool fc code: ' || apex_string.join(l_found_binds, ', '));
      end if;
    end if;

    return l_return;
  exception
    when others then
      logger.log_error('Error in execute_tool: %s', sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;

  end execute_tool;


  function get_tools_object_param_name (
    p_tool_code in uc_ai_tools.code%type
  ) return uc_ai_tool_parameters.name%type result_cache
  as
    l_scope logger_logs.scope%type := gc_scope_prefix || 'get_tools_object_param_name';
    l_count pls_integer;
    l_param_name uc_ai_tool_parameters.name%type;
  begin
    select count(*)
      into l_count
      from uc_ai_tool_parameters tp
      join uc_ai_tools t
        on tp.tool_id = t.id
      where t.code = p_tool_code
        and parent_param_id is null;

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
      logger.log_error('Error in get_tools_object_param_name: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
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
    l_scope logger_logs.scope%type := gc_scope_prefix || 'create_parameters_recursive';

    l_prop_keys json_key_list;
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
    l_nested_required_keys json_key_list := json_key_list();
  begin
    if p_properties is null then
      return;
    end if;
    
    l_prop_keys := p_properties.get_keys;
    
    if l_prop_keys is null or l_prop_keys.count = 0 then
      return;
    end if;
    
    <<property_loop>>
    for i in 1 .. l_prop_keys.count loop
      l_prop_name := l_prop_keys(i);
      l_prop_obj := treat(p_properties.get(l_prop_name) as json_object_t);
      
      if l_prop_obj is null then
        logger.log_warn('Property object is null for: ' || l_prop_name, l_scope);
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
      
      -- Insert the parameter
      insert into uc_ai_tool_parameters (
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
        case when l_is_array then 1 else 0 end,
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
        l_nested_required_keys := json_key_list();
        if l_nested_required is not null then
          <<nested_required_loop>>
          for j in 0 .. l_nested_required.get_size - 1 loop
            l_nested_required_keys.extend;
            l_nested_required_keys(l_nested_required_keys.count) := l_nested_required.get_string(j);
          end loop nested_required_loop;
        end if;
        
        -- Recursively create nested parameters
        create_parameters_recursive(
          p_properties => l_nested_properties
        , p_required_keys => l_nested_required_keys
        , p_parent_param_id => l_current_param_id
        , p_created_by => p_created_by
        , p_tool_id => p_tool_id
      );
      end if;
      
    end loop property_loop;
  exception
    when others then
      logger.log_error('Error in create_parameters_recursive: %s', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;  
  end create_parameters_recursive;

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
    p_tags                  in apex_t_varchar2 default apex_t_varchar2()
  ) return uc_ai_tools.id%type
  as
    l_scope logger_logs.scope%type := gc_scope_prefix || 'create_tool_from_schema';
    
    l_tool_id uc_ai_tools.id%type;
    l_properties json_object_t;
    l_required_arr json_array_t;
    l_required_keys json_key_list := json_key_list();
    l_schema_clob clob;
  begin
    logger.log('Creating tool from schema', l_scope, 'Tool: ' || p_tool_code);

    l_schema_clob := p_json_schema.to_clob;

    -- Create the tool record
    insert into uc_ai_tools (
      code,
      description,
      active,
      response_schema,
      version,
      function_call,
      authorization_schema,
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
      p_created_by,
      systimestamp,
      p_created_by,
      systimestamp
    ) returning id into l_tool_id;
    
    logger.log('Created tool with ID: ' || l_tool_id, l_scope);
    
    -- Extract properties and required array from schema
    l_properties := treat(p_json_schema.get('properties') as json_object_t);
    l_required_arr := treat(p_json_schema.get('required') as json_array_t);
    
    -- Convert required array to key list for easier processing
    if l_required_arr is not null then
      <<required_loop>>
      for i in 0 .. l_required_arr.get_size - 1 loop
        l_required_keys.extend;
        l_required_keys(l_required_keys.count) := l_required_arr.get_string(i);
      end loop required_loop;
    end if;
    
    -- Create parameters from schema properties
    create_parameters_recursive(
      p_properties => l_properties
    , p_required_keys => l_required_keys
    , p_parent_param_id => null
    , p_created_by => p_created_by
    , p_tool_id => l_tool_id
    );
    
    -- Create tags if provided
    if p_tags is not null and p_tags.count > 0 then
      <<tag_loop>>
      for i in 1 .. p_tags.count loop
        insert into uc_ai_tool_tags (
          tool_id,
          tag_name,
          created_by,
          created_at,
          updated_by,
          updated_at
        ) values (
          l_tool_id,
          lower(p_tags(i)),
          p_created_by,
          systimestamp,
          p_created_by,
          systimestamp
        );
      end loop tag_loop;
    end if;
    
    logger.log('Successfully created tool with schema', l_scope, 'Tool ID: ' || l_tool_id);
    
    return l_tool_id;
    
  exception
    when others then
      logger.log_error('Error in create_tool_from_schema', l_scope, sqlerrm || ' ' || sys.dbms_utility.format_error_backtrace);
      raise;
  end create_tool_from_schema;

end uc_ai_tools_api;
/
