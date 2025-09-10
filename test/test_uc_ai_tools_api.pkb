create or replace package body test_uc_ai_tools_api as

  gc_test_user constant varchar2(255 char) := 'TEST_USER';
  gc_test_prefix constant varchar2(50 char) := 'TEST_TOOL_';

  /*
   * Setup procedure to initialize test environment
   */
  procedure setup_test_data as
  begin
    -- Clean up any existing test data first
    cleanup_test_data;
  end setup_test_data;

  /*
   * Cleanup procedure to remove test data
   */
  procedure cleanup_test_data as
  begin
    -- Delete test tools and their parameters and tags (cascade should handle parameters and tags)
    delete from uc_ai_tools 
    where code like gc_test_prefix || '%';
  exception
    when others then
      raise;
  end cleanup_test_data;


  /*
   * Test creating a tool from a JSON schema with various parameter types
   */
  procedure test_create_tool_from_schema as
    l_tool_id uc_ai_tools.id%type;
    l_schema clob;
    l_tool_count number;
    l_param_count number;
    l_tools_array json_array_t;
  begin
    -- Prepare the test schema (settlement creation example from user request)
    l_schema := '{
      "$schema": "http://json-schema.org/draft-07/schema#",
      "type": "object",
      "title": "Create Settlement Request",
      "description": "Create a new settlement in the database",
      "properties": {
        "incident_date": {
          "type": "string",
          "description": "Date of the incident in YYYY-MM-DD format"
        },
        "claimant_first_name": {
          "type": "string",
          "description": "First name of the person making the claim"
        },
        "claimant_last_name": {
          "type": "string",
          "description": "Last name of the person making the claim"
        },
        "policy_type": {
          "type": "string",
          "description": "Type of insurance policy",
          "enum": [
            "Auto",
            "Homeowners",
            "Life",
            "Medical",
            "Property",
            "Personal Liability",
            "Marine",
            "Disability"
          ]
        },
        "incident_description": {
          "type": "string",
          "description": "Brief description of what happened during the incident"
        },
        "claimant_email": {
          "type": "string",
          "description": "Email address of the claimant"
        },
        "claimant_phone": {
          "type": "string",
          "description": "Phone number of the claimant (international format preferred)"
        },
        "insured_first_name": {
          "type": "string",
          "description": "First name of the insured person (if different from claimant)"
        },
        "insured_last_name": {
          "type": "string",
          "description": "Last name of the insured person (if different from claimant)"
        },
        "settlement_amount": {
          "type": "number",
          "description": "Initial settlement amount (defaults to 0 if not provided)",
          "minimum": 0,
          "maximum": 99999999999999.98
        },
        "currency_code": {
          "type": "string",
          "description": "3-letter ISO currency code (defaults to EUR if not provided)",
          "enum": [
            "EUR",
            "USD",
            "GBP",
            "CHF",
            "JPY",
            "CAD",
            "AUD"
          ]
        },
        "notes": {
          "type": "string",
          "description": "Additional notes or comments about the settlement"
        }
      },
      "required": [
        "incident_date",
        "claimant_first_name",
        "claimant_last_name"
      ]
    }';

    -- Create the tool
    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code => gc_test_prefix || 'CREATE_SETTLEMENT',
      p_description => 'Create a new settlement in the database',
      p_function_call => 'return create_settlement_function(:parameters);',
      p_json_schema => json_object_t.parse(l_schema),
      p_created_by => gc_test_user
    );

    -- Verify tool was created
    select count(*) into l_tool_count 
    from uc_ai_tools 
    where id = l_tool_id and code = gc_test_prefix || 'CREATE_SETTLEMENT';

    ut.expect(l_tool_count).to_equal(1);

    -- Verify parameters were created correctly
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id;

    ut.expect(l_param_count).to_equal(12); -- 12 properties in the schema

    -- Verify required parameters
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id and required = 1;

    ut.expect(l_param_count).to_equal(3); -- 3 required properties

    -- Verify enum parameters
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id and enum_values is not null;

    ut.expect(l_param_count).to_equal(2); -- policy_type and currency_code have enums

    -- Verify numeric parameter constraints
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id 
      and name = 'settlement_amount' 
      and data_type = 'number' 
      and min_num_val = 0 
      and max_num_val = 99999999999999.98;

    ut.expect(l_param_count).to_equal(1);

    uc_ai.g_enable_tools := true;

    -- Test tool appears in tools array
    l_tools_array := uc_ai_tools_api.get_tools_array(
      p_provider => uc_ai.c_provider_openai
    );

    ut.expect(l_tools_array.get_size).to_be_greater_than(0);

  end test_create_tool_from_schema;

  /*
   * Test creating a tool with nested object parameters
   */
  procedure test_create_tool_with_nested_objects as
    l_tool_id uc_ai_tools.id%type;
    l_schema clob;
    l_param_count number;
    l_tools_array json_array_t;
  begin
    -- Prepare schema with nested objects
    l_schema := '{
      "type": "object",
      "properties": {
        "customer": {
          "type": "object",
          "description": "Customer information",
          "properties": {
            "name": {
              "type": "string",
              "description": "Customer name"
            },
            "address": {
              "type": "object",
              "description": "Customer address",
              "properties": {
                "street": {"type": "string"},
                "city": {"type": "string"},
                "country": {"type": "string"}
              },
              "required": ["street", "city"]
            }
          },
          "required": ["name"]
        },
        "order_id": {
          "type": "string",
          "description": "Order identifier"
        }
      },
      "required": ["customer", "order_id"]
    }';

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code => gc_test_prefix || 'NESTED_OBJECTS',
      p_description => 'Test tool with nested objects',
      p_function_call => 'return nested_test_function(:parameters);',
      p_json_schema => json_object_t.parse(l_schema),
      p_created_by => gc_test_user
    );

    -- Count total parameters (including nested ones)
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id;

    -- Should have: customer, order_id, name, address, street, city, country = 7 total
    ut.expect(l_param_count).to_equal(7);

    -- Verify nested structure
    select count(*) into l_param_count 
    from uc_ai_tool_parameters p1
    join uc_ai_tool_parameters p2 on p1.id = p2.parent_param_id
    where p1.tool_id = l_tool_id 
      and p1.name = 'customer' 
      and p1.data_type = 'object'
      and p2.name = 'name';

    ut.expect(l_param_count).to_equal(1);

    uc_ai.g_enable_tools := true;

    -- Test tool appears in tools array
    l_tools_array := uc_ai_tools_api.get_tools_array(
      p_provider => uc_ai.c_provider_openai
    );

    ut.expect(l_tools_array.get_size).to_be_greater_than(0);

  end test_create_tool_with_nested_objects;

  /*
   * Test creating a tool with array parameters
   */
  procedure test_create_tool_with_arrays as
    l_tool_id uc_ai_tools.id%type;
    l_schema clob;
    l_param_count number;
    l_tools_array json_array_t;
  begin
    l_schema := '{
      "type": "object",
      "properties": {
        "tags": {
          "type": "array",
          "description": "List of tags",
          "items": {
            "type": "string"
          },
          "minItems": 1,
          "maxItems": 10
        },
        "scores": {
          "type": "array",
          "description": "List of scores",
          "items": {
            "type": "number",
            "minimum": 0,
            "maximum": 100
          }
        }
      }
    }';

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code => gc_test_prefix || 'ARRAYS',
      p_description => 'Test tool with arrays',
      p_function_call => 'return array_test_function(:parameters);',
      p_json_schema => json_object_t.parse(l_schema),
      p_created_by => gc_test_user
    );

    -- Verify array parameters
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id 
      and is_array = 1;

    ut.expect(l_param_count).to_equal(2);

    -- Verify array constraints
    select count(*) into l_param_count 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id 
      and name = 'tags'
      and array_min_items = 1 
      and array_max_items = 10;

    ut.expect(l_param_count).to_equal(1);

    uc_ai.g_enable_tools := true;

    -- Test tool appears in tools array
    l_tools_array := uc_ai_tools_api.get_tools_array(
      p_provider => uc_ai.c_provider_openai
    );

    ut.expect(l_tools_array.get_size).to_be_greater_than(0);

  end test_create_tool_with_arrays;

  /*
   * Test creating a tool with enum parameters
   */
  procedure test_create_tool_with_enums as
    l_tool_id uc_ai_tools.id%type;
    l_schema clob;
    l_enum_values varchar2(4000 char);
    l_tools_array json_array_t;
  begin
    l_schema := '{
      "type": "object",
      "properties": {
        "status": {
          "type": "string",
          "description": "Status code",
          "enum": ["active", "inactive", "pending"]
        },
        "priority": {
          "type": "integer",
          "description": "Priority level",
          "enum": [1, 2, 3, 4, 5]
        }
      }
    }';

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code => gc_test_prefix || 'ENUMS',
      p_description => 'Test tool with enums',
      p_function_call => 'return enum_test_function(:parameters);',
      p_json_schema => json_object_t.parse(l_schema),
      p_created_by => gc_test_user
    );

    -- Verify enum values for string enum
    select enum_values into l_enum_values 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id and name = 'status';

    ut.expect(l_enum_values).to_equal('active:inactive:pending');

    -- Verify enum values for integer enum
    select enum_values into l_enum_values 
    from uc_ai_tool_parameters 
    where tool_id = l_tool_id and name = 'priority';

    ut.expect(l_enum_values).to_equal('1:2:3:4:5');

    uc_ai.g_enable_tools := true;

    -- Test tool appears in tools array
    l_tools_array := uc_ai_tools_api.get_tools_array(
      p_provider => uc_ai.c_provider_openai
    );

    ut.expect(l_tools_array.get_size).to_be_greater_than(0);

  end test_create_tool_with_enums;

  /*
   * Test tool retrieval and execution after creation
   */
  procedure test_tool_retrieval as
    l_tool_id uc_ai_tools.id%type;
    l_schema clob;
    l_tools_array json_array_t;
  begin
    l_schema := '{
      "type": "object",
      "properties": {
        "message": {
          "type": "string",
          "description": "Test message"
        }
      },
      "required": ["message"]
    }';

    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code => gc_test_prefix || 'RETRIEVAL_TEST',
      p_description => 'Test tool retrieval',
      p_function_call => 'return ''Test result'';',
      p_json_schema => json_object_t.parse(l_schema),
      p_created_by => gc_test_user
    );

    uc_ai.g_enable_tools := true;

    -- Test tool appears in tools array
    l_tools_array := uc_ai_tools_api.get_tools_array(
      p_provider => uc_ai.c_provider_openai
    );

    ut.expect(l_tools_array.get_size).to_be_greater_than(0);

  end test_tool_retrieval;

  /*
   * Test creating a tool with tags
   */
  procedure test_create_tool_with_tags as
    l_tool_id uc_ai_tools.id%type;
    l_schema clob;
    l_tags apex_t_varchar2 := apex_t_varchar2('test-tag', 'integration', 'demo');
    l_tag_count number;
  begin
    l_schema := '{
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name parameter"
        }
      },
      "required": ["name"]
    }';

    -- Create tool with tags
    l_tool_id := uc_ai_tools_api.create_tool_from_schema(
      p_tool_code => gc_test_prefix || 'WITH_TAGS',
      p_description => 'Test tool with tags',
      p_function_call => 'return ''Test result'';',
      p_json_schema => json_object_t.parse(l_schema),
      p_created_by => gc_test_user,
      p_tags => l_tags
    );

    -- Verify tool was created
    ut.expect(l_tool_id).to_be_not_null();

    -- Verify tags were created
    select count(*) into l_tag_count 
    from uc_ai_tool_tags 
    where tool_id = l_tool_id;

    ut.expect(l_tag_count).to_equal(3);

    -- Verify specific tag names exist
    select count(*) into l_tag_count
    from uc_ai_tool_tags 
    where tool_id = l_tool_id 
      and tag_name = 'test-tag';

    ut.expect(l_tag_count).to_equal(1);

    select count(*) into l_tag_count
    from uc_ai_tool_tags 
    where tool_id = l_tool_id 
      and tag_name = 'integration';

    ut.expect(l_tag_count).to_equal(1);

    select count(*) into l_tag_count
    from uc_ai_tool_tags 
    where tool_id = l_tool_id 
      and tag_name = 'demo';

    ut.expect(l_tag_count).to_equal(1);

  end test_create_tool_with_tags;

end test_uc_ai_tools_api;
/
