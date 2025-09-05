-- Test script for the create_new_settlement function
-- This demonstrates how to use the function with JSON input

-- Example 1: Create a new auto claim settlement
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('claim_number', 'CL2025-TEST-001');
  l_settlement_data.put('policy_number', 'POL-TEST123');
  l_settlement_data.put('policy_type', 'Auto');
  l_settlement_data.put('incident_date', '2025-09-05');
  l_settlement_data.put('incident_description', 'Rear-end collision at traffic light');
  l_settlement_data.put('claimant_first_name', 'John');
  l_settlement_data.put('claimant_last_name', 'Doe');
  l_settlement_data.put('claimant_email', 'john.doe@example.com');
  l_settlement_data.put('claimant_phone', '+33123456789');
  l_settlement_data.put('insured_first_name', 'John');
  l_settlement_data.put('insured_last_name', 'Doe');
  l_settlement_data.put('settlement_amount', 2500.00);
  l_settlement_data.put('currency_code', 'EUR');
  l_settlement_data.put('notes', 'Initial claim submission via AI tool');
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
  
  dbms_output.put_line('Test 1 Result: ' || l_result);
end;
/

-- Example 2: Create settlement with minimal required fields only
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('claim_number', 'CL2025-TEST-002');
  l_settlement_data.put('policy_number', 'POL-TEST456');
  l_settlement_data.put('incident_date', '2025-09-04');
  l_settlement_data.put('claimant_first_name', 'Jane');
  l_settlement_data.put('claimant_last_name', 'Smith');
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
  
  dbms_output.put_line('Test 2 Result: ' || l_result);
end;
/

-- Example 3: Test error handling - missing required field
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('policy_number', 'POL-TEST789');
  l_settlement_data.put('incident_date', '2025-09-03');
  l_settlement_data.put('claimant_first_name', 'Bob');
  l_settlement_data.put('claimant_last_name', 'Wilson');
  -- Missing claim_number - should generate error
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
  
  dbms_output.put_line('Test 3 Result: ' || l_result);
end;
/

-- Example 4: Test duplicate claim number error
declare
  l_settlement_data json_object_t;
  l_result clob;
begin
  l_settlement_data := json_object_t();
  l_settlement_data.put('claim_number', 'CL2025-TEST-001'); -- Same as Test 1
  l_settlement_data.put('policy_number', 'POL-TEST999');
  l_settlement_data.put('incident_date', '2025-09-02');
  l_settlement_data.put('claimant_first_name', 'Alice');
  l_settlement_data.put('claimant_last_name', 'Brown');
  
  l_result := pame_pkg.create_new_settlement(l_settlement_data);
  
  dbms_output.put_line('Test 4 Result: ' || l_result);
end;
/

-- View the created settlements
select settlement_id, claim_number, policy_number, claimant_first_name, claimant_last_name, 
       settlement_date, settlement_status, settlement_amount, currency_code
from pame_settlement_demo 
where claim_number like 'CL2025-TEST-%'
order by settlement_id;
