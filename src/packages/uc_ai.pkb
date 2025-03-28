create or replace package body uc_ai as

  FUNCTION get_tool_schema(p_tool_id IN NUMBER) 
    RETURN JSON_OBJECT_T 
  AS
    l_tool_code VARCHAR2(255);
    l_tool_description VARCHAR2(4000);
    
    -- JSON objects
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_function   JSON_OBJECT_T := JSON_OBJECT_T();
    l_parameters JSON_OBJECT_T := JSON_OBJECT_T();
    l_properties JSON_OBJECT_T := JSON_OBJECT_T();
    l_required   JSON_ARRAY_T  := JSON_ARRAY_T();
    
  BEGIN
    -- Get tool information
    SELECT code, description
    INTO l_tool_code, l_tool_description
    FROM uc_ai_tools
    WHERE id = p_tool_id;
    
    -- Process each parameter
    FOR param_rec IN (
      SELECT 
        name,
        description,
        data_type,
        required,
        min_num_val,
        max_num_val,
        enum_values,
        default_value,
        array_min_items,
        array_max_items,
        pattern,
        format,
        min_length,
        max_length
      FROM uc_ai_tool_parameters
      WHERE tool_id = p_tool_id
      ORDER BY name
    ) LOOP
      -- Create JSON object for this parameter
      DECLARE
        l_param_obj JSON_OBJECT_T := JSON_OBJECT_T();
      BEGIN
        -- Add description
        l_param_obj.put('description', param_rec.description);
        
        -- Handle different data types
        IF param_rec.data_type = 'array' THEN
          l_param_obj.put('type', 'array');
          
          -- Create items specification
          DECLARE
            l_items_obj JSON_OBJECT_T := JSON_OBJECT_T();
          BEGIN
            l_items_obj.put('type', param_rec.data_type);
            
            -- Add additional array item constraints
            IF param_rec.data_type = 'string' AND param_rec.pattern IS NOT NULL THEN
              l_items_obj.put('pattern', param_rec.pattern);
            END IF;
            
            -- Handle enum values for array items
            IF param_rec.data_type IN ('string', 'number', 'integer') AND param_rec.enum_values IS NOT NULL THEN
              -- Parse the JSON array from enum_values CLOB
              l_items_obj.put('enum', JSON_ARRAY_T.parse(param_rec.enum_values));
            END IF;
            
            l_param_obj.put('items', l_items_obj);
          END;
          
          -- Array constraints
          IF param_rec.array_min_items IS NOT NULL THEN
            l_param_obj.put('minItems', param_rec.array_min_items);
          END IF;
          
          IF param_rec.array_max_items IS NOT NULL THEN
            l_param_obj.put('maxItems', param_rec.array_max_items);
          END IF;
        ELSE
          -- Handle scalar types
          l_param_obj.put('type', param_rec.data_type);
          
          -- Add type-specific constraints
          CASE param_rec.data_type
            WHEN 'string' THEN
              IF param_rec.min_length IS NOT NULL THEN
                l_param_obj.put('minLength', param_rec.min_length);
              END IF;
              
              IF param_rec.max_length IS NOT NULL THEN
                l_param_obj.put('maxLength', param_rec.max_length);
              END IF;
              
              IF param_rec.pattern IS NOT NULL THEN
                l_param_obj.put('pattern', param_rec.pattern);
              END IF;
              
              IF param_rec.format IS NOT NULL THEN
                l_param_obj.put('format', param_rec.format);
              END IF;
            
            WHEN 'number' THEN
              IF param_rec.min_num_val IS NOT NULL THEN
                l_param_obj.put('minimum', param_rec.min_num_val);
              END IF;
              
              IF param_rec.max_num_val IS NOT NULL THEN
                l_param_obj.put('maximum', param_rec.max_num_val);
              END IF;
            
            WHEN 'integer' THEN
              IF param_rec.min_num_val IS NOT NULL THEN
                l_param_obj.put('minimum', FLOOR(param_rec.min_num_val));
              END IF;
              
              IF param_rec.max_num_val IS NOT NULL THEN
                l_param_obj.put('maximum', FLOOR(param_rec.max_num_val));
              END IF;
          END CASE;
          
          -- Add enum values for scalar types
          IF param_rec.data_type IN ('string', 'number', 'integer') AND param_rec.enum_values IS NOT NULL THEN
            -- Parse the JSON array from enum_values CLOB
            l_param_obj.put('enum', JSON_ARRAY_T.parse(param_rec.enum_values));
          END IF;
        END IF;
        
        -- Add default value if specified
        IF param_rec.default_value IS NOT NULL THEN
          -- Handle different types of default values
          IF param_rec.data_type = 'string' THEN
            l_param_obj.put('default', param_rec.default_value);
          ELSIF param_rec.data_type = 'boolean' THEN
            -- Convert string representation to boolean
            IF LOWER(param_rec.default_value) IN ('true', '1') THEN
              l_param_obj.put('default', TRUE);
            ELSE
              l_param_obj.put('default', FALSE);
            END IF;
          ELSIF param_rec.data_type = 'number' THEN
            l_param_obj.put('default', TO_NUMBER(param_rec.default_value));
          ELSIF param_rec.data_type = 'integer' THEN
            l_param_obj.put('default', FLOOR(TO_NUMBER(param_rec.default_value)));
          ELSIF param_rec.data_type = 'array' AND param_rec.default_value LIKE '[%]' THEN
            -- Parse JSON array from default_value
            l_param_obj.put('default', JSON_ARRAY_T.parse(param_rec.default_value));
          END IF;
        END IF;
        
        -- Add parameter to properties
        l_properties.put(param_rec.name, l_param_obj);
        
        -- Add to required array if needed
        IF param_rec.required = 1 THEN
          l_required.append(param_rec.name);
        END IF;
      END;
    END LOOP;
    
    -- Build the complete JSON structure
    l_parameters.put('type', 'object');
    l_parameters.put('properties', l_properties);
    l_parameters.put('required', l_required);
    
    l_function.put('name', l_tool_code);
    l_function.put('description', l_tool_description);
    l_function.put('parameters', l_parameters);
    
    l_result.put('type', 'function');
    l_result.put('function', l_function);
    
    return l_result;
  exception
    when others then
      apex_debug.error('Error in get_tool_schema: %s', sqlerrm || ' ' || dbms_utility.format_call_stack);
      raise;
  END get_tool_schema;

end uc_ai;
/
