# JSON Schema Usage Guide for create_new_settlement

## Overview
The `create_new_settlement` function has been simplified to require only 3 essential fields:
- `incident_date` - When the incident occurred
- `claimant_first_name` - First name of the person making the claim  
- `claimant_last_name` - Last name of the person making the claim

The function now **automatically generates**:
- `claim_number` - Format: `CL{YYYY}-{random_6_digits}-AI`
- `policy_number` - Format: `POL{YYYY}-{random_6_digits}-AI`

## Required Parameters
```json
{
  "incident_date": "2025-09-05",
  "claimant_first_name": "John",
  "claimant_last_name": "Doe"
}
```

## Full Example with Optional Fields
```json
{
  "incident_date": "2025-09-05",
  "claimant_first_name": "John", 
  "claimant_last_name": "Doe",
  "policy_type": "Auto",
  "incident_description": "Rear-end collision at traffic light during rush hour",
  "claimant_email": "john.doe@example.com",
  "claimant_phone": "+33123456789",
  "insured_first_name": "John",
  "insured_last_name": "Doe", 
  "settlement_amount": 2500.00,
  "currency_code": "EUR",
  "notes": "Initial claim submission via AI assistant"
}
```

## Response Format

### Success Response
```json
{
  "status": "success",
  "message": "Settlement created successfully", 
  "settlement_id": 111,
  "claim_number": "CL2025-456789-AI"
}
```

### Error Response  
```json
{
  "status": "error",
  "message": "Missing required field: incident_date"
}
```

## Field Validation Rules

| Field | Type | Max Length | Format | Required |
|-------|------|------------|--------|----------|
| incident_date | string | - | YYYY-MM-DD | ✅ |
| claimant_first_name | string | 100 | - | ✅ |
| claimant_last_name | string | 100 | - | ✅ |
| policy_type | string | 100 | Enum values | ❌ |
| incident_description | string | 500 | - | ❌ |
| claimant_email | string | 255 | Valid email | ❌ |
| claimant_phone | string | 20 | Phone format | ❌ |
| insured_first_name | string | 100 | - | ❌ |
| insured_last_name | string | 100 | - | ❌ |
| settlement_amount | number | - | >= 0 | ❌ |
| currency_code | string | 3 | ISO code | ❌ |
| notes | string | 1000 | - | ❌ |

## Policy Type Enum Values
- Auto
- Homeowners  
- Life
- Medical
- Property
- Personal Liability
- Marine
- Disability

## Currency Code Examples
- EUR (default)
- USD
- GBP
- CHF
- JPY
- CAD
- AUD

## Usage in Oracle SQL
```sql
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('incident_date', '2025-09-05');
  l_settlement_data.put('claimant_first_name', 'John');
  l_settlement_data.put('claimant_last_name', 'Doe');
  l_settlement_data.put('policy_type', 'Auto');
  l_settlement_data.put('incident_description', 'Minor fender bender');
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
  
  -- Parse the result
  dbms_output.put_line(l_result);
end;
/
```

## For LLM Integration
The function is designed to be called as a tool by Large Language Models. The simplified parameter structure makes it easier for AI to:
1. Collect minimal required information from users
2. Format as JSON
3. Call the function
4. Parse and present results to users

The auto-generation of claim and policy numbers eliminates the need for AI to create unique identifiers.
