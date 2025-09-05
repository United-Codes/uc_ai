declare
  l_schema json_object_t;
  l_tool_id uc_ai_tools.id%type;
begin
  l_schema := json_object_t.parse('{
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
    }');

    -- Create the tool
  l_tool_id := uc_ai_tools_api.create_tool_from_schema(
    p_tool_code => 'PAME_CREATE_SETTLEMENT',
    p_description => 'Create a new insurance settlement from initial provided data',
    p_function_call => 'return pame_pkg.create_new_settlement(:parameters);',
    p_json_schema => l_schema,
    p_tags => apex_t_varchar2('pame', 'pame_create_settlement')
  );

  commit;
end;
/
