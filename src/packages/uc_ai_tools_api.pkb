create or replace package body uc_ai_tools_api as 

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

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
    p_tool_id  in uc_ai_tools.id%type
  , p_provider in uc_ai.provider_type
  ) 
    return json_object_t 
  as
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
      raise_application_error(-20001, 'If your tool has more than one parameter, you must define a single parent object with the parameters as attributes. This is required for the AI to understand the tool parameters.');
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
    p_provider in uc_ai.provider_type
  ) return json_array_t
  as
    l_tools_array  json_array_t := json_array_t();
    l_tool_obj     json_object_t;
    l_tool_cpy_obj json_object_t;
  begin
    if not uc_ai.g_enable_tools then
      return l_tools_array;
    end if;

    <<fetch_tools>>
    for rec in (
      select id
        from uc_ai_tools
    )
    loop
      l_tool_obj := get_tool_schema(rec.id, p_provider);

      -- openai has an additional object wrapper for function calls
      -- {type: "function", function: {...}}
      -- where others like anthropic/claude use the function object directly
      if p_provider in (uc_ai.c_provider_openai, uc_ai.c_provider_ollama) then
        l_tool_cpy_obj := l_tool_obj;

        l_tool_obj := json_object_t();
        l_tool_obj.put('type', 'function');
        l_tool_obj.put('function', l_tool_cpy_obj);
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

      return l_return;

    end if;
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
    l_param_name uc_ai_tool_parameters.name%type;
  begin
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

end uc_ai_tools_api;
/
