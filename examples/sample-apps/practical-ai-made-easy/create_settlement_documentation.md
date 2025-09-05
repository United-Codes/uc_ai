# Settlement Creation Function Documentation

## Overview
The `create_new_settlement` function in the `pame_pkg` package allows for creating new settlement records using JSON input. This function is designed to be used as a tool for LLMs (Large Language Models) to create insurance settlements based on initial damage reports.

## Function Signature
```sql
function create_new_settlement(p_settlement_data in json_object_t) return clob;
```

## Parameters
- `p_settlement_data`: A JSON object containing the settlement information

## Required Fields
The following fields must be present in the JSON object:
- `claim_number` (string): Unique identifier for the claim
- `policy_number` (string): Policy number associated with the claim
- `incident_date` (string): Date of the incident in YYYY-MM-DD format
- `claimant_first_name` (string): First name of the claimant
- `claimant_last_name` (string): Last name of the claimant

## Optional Fields
- `policy_type` (string): Type of insurance policy (e.g., 'Auto', 'Homeowners', 'Life')
- `incident_description` (string): Description of the incident
- `claimant_email` (string): Email address of the claimant
- `claimant_phone` (string): Phone number of the claimant
- `insured_first_name` (string): First name of the insured person (if different from claimant)
- `insured_last_name` (string): Last name of the insured person
- `settlement_amount` (number): Initial settlement amount (defaults to 0)
- `currency_code` (string): Currency code (defaults to 'EUR')
- `notes` (string): Additional notes about the settlement

## Automatic Values
The function automatically sets the following values:
- `settlement_id`: Auto-generated unique identifier
- `settlement_date`: Current system date
- `settlement_status`: Always set to 'Proposed' for new settlements

## Return Value
The function returns a CLOB containing a JSON response with the following structure:

### Success Response
```json
{
  "status": "success",
  "message": "Settlement created successfully",
  "settlement_id": 123,
  "claim_number": "CL2025-001-AUTO"
}
```

### Error Response
```json
{
  "status": "error",
  "message": "Error description"
}
```

## Error Handling
The function handles various error scenarios:
- Missing required fields
- Duplicate claim numbers
- Database constraints violations
- General database errors (includes backtrace for debugging)

## Usage Examples

### Example 1: Full Settlement Creation
```sql
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('claim_number', 'CL2025-001-AUTO');
  l_settlement_data.put('policy_number', 'POL-AX789');
  l_settlement_data.put('policy_type', 'Auto');
  l_settlement_data.put('incident_date', '2025-09-05');
  l_settlement_data.put('incident_description', 'Rear-end collision at traffic light');
  l_settlement_data.put('claimant_first_name', 'John');
  l_settlement_data.put('claimant_last_name', 'Doe');
  l_settlement_data.put('claimant_email', 'john.doe@example.com');
  l_settlement_data.put('claimant_phone', '+33123456789');
  l_settlement_data.put('settlement_amount', 2500.00);
  l_settlement_data.put('currency_code', 'EUR');
  l_settlement_data.put('notes', 'Initial claim submission');
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
end;
```

### Example 2: Minimal Settlement Creation
```sql
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('claim_number', 'CL2025-002-HOME');
  l_settlement_data.put('policy_number', 'POL-HM123');
  l_settlement_data.put('incident_date', '2025-09-04');
  l_settlement_data.put('claimant_first_name', 'Jane');
  l_settlement_data.put('claimant_last_name', 'Smith');
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
end;
```

## LLM Tool Integration
This function is designed to be called by LLMs as a tool. The JSON structure makes it easy for AI systems to:
1. Collect necessary information from users
2. Format it as a JSON object
3. Call the function to create settlements
4. Parse the response to provide feedback to users

## Database Impact
- Creates a new record in the `pame_settlement_demo` table
- Automatically commits the transaction on success
- Rolls back the transaction on error
- Uses sequence-like ID generation (max + 1)
