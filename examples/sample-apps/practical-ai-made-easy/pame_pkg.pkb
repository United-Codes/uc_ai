create or replace package body pame_pkg as

  procedure reset_global_variables
  as
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

  end reset_global_variables;

  function create_new_settlement(p_settlement_data in json_object_t) return clob
  as
    l_settlement_id      number;
    l_claim_number       varchar2(50 char);
    l_policy_number      varchar2(50 char);
    l_policy_type        varchar2(100 char);
    l_incident_date      date;
    l_incident_desc      varchar2(500 char);
    l_claimant_fname     varchar2(100 char);
    l_claimant_lname     varchar2(100 char);
    l_claimant_email     varchar2(255 char);
    l_claimant_phone     varchar2(20 char);
    l_insured_fname      varchar2(100 char);
    l_insured_lname      varchar2(100 char);
    l_settlement_amount  number(18, 2);
    l_currency_code      varchar2(3 char);
    l_notes              varchar2(1000 char);
    l_result             clob;
  begin
    -- Validate required fields and extract from JSON    
    if not p_settlement_data.has('incident_date') then
      return '{"status": "error", "message": "Missing required field: incident_date"}';
    end if;
    
    if not p_settlement_data.has('claimant_first_name') then
      return '{"status": "error", "message": "Missing required field: claimant_first_name"}';
    end if;
    
    if not p_settlement_data.has('claimant_last_name') then
      return '{"status": "error", "message": "Missing required field: claimant_last_name"}';
    end if;

    -- Extract required fields
    -- generate pattern like this: CL2025-009-ACC
    l_claim_number := 'CL' || to_char(sysdate, 'YYYY') || '-' || sys.dbms_random.value(100, 999999) || '-AI';
    l_policy_number := 'POL' || to_char(sysdate, 'YYYY') || '-' || sys.dbms_random.value(100, 999999) || '-AI';
    l_incident_date := to_date(p_settlement_data.get_String('incident_date'), 'FXYYYY-MM-DD');
    l_claimant_fname := p_settlement_data.get_String('claimant_first_name');
    l_claimant_lname := p_settlement_data.get_String('claimant_last_name');

    -- Extract optional fields
    l_policy_type := case when p_settlement_data.has('policy_type') 
                         then p_settlement_data.get_String('policy_type') 
                         else null end;
    l_incident_desc := case when p_settlement_data.has('incident_description') 
                           then p_settlement_data.get_String('incident_description') 
                           else null end;
    l_claimant_email := case when p_settlement_data.has('claimant_email') 
                            then p_settlement_data.get_String('claimant_email') 
                            else null end;
    l_claimant_phone := case when p_settlement_data.has('claimant_phone') 
                            then p_settlement_data.get_String('claimant_phone') 
                            else null end;
    l_insured_fname := case when p_settlement_data.has('insured_first_name') 
                           then p_settlement_data.get_String('insured_first_name') 
                           else null end;
    l_insured_lname := case when p_settlement_data.has('insured_last_name') 
                           then p_settlement_data.get_String('insured_last_name') 
                           else null end;
    l_settlement_amount := case when p_settlement_data.has('settlement_amount') 
                               then p_settlement_data.get_Number('settlement_amount') 
                               else 0 end;
    l_currency_code := case when p_settlement_data.has('currency_code') 
                           then p_settlement_data.get_String('currency_code') 
                           else 'EUR' end;
    l_notes := case when p_settlement_data.has('notes') 
                   then p_settlement_data.get_String('notes') 
                   else null end;

    -- Generate new settlement ID
    select nvl(max(settlement_id), 0) + 1 
    into l_settlement_id 
    from pame_settlement_demo;

    -- Insert new settlement record
    insert into pame_settlement_demo (
      settlement_id,
      claim_number,
      policy_number,
      policy_type,
      incident_date,
      incident_description,
      claimant_first_name,
      claimant_last_name,
      claimant_email,
      claimant_phone,
      insured_first_name,
      insured_last_name,
      settlement_date,
      settlement_amount,
      currency_code,
      settlement_status,
      notes
    ) values (
      l_settlement_id,
      l_claim_number,
      l_policy_number,
      l_policy_type,
      l_incident_date,
      l_incident_desc,
      l_claimant_fname,
      l_claimant_lname,
      l_claimant_email,
      l_claimant_phone,
      l_insured_fname,
      l_insured_lname,
      sysdate, -- settlement_date defaults to current date
      l_settlement_amount,
      l_currency_code,
      'Proposed', -- initial status is always 'Proposed'
      l_notes
    );

    l_result := '{"status": "success", "message": "Settlement created successfully", "settlement_id": ' || l_settlement_id || ', "claim_number": "' || l_claim_number || '"}';
    return l_result;

  exception
    when dup_val_on_index then
      return '{"status": "error", "message": "Claim number already exists: ' || l_claim_number || '"}';
    when others then
      return '{"status": "error", "message": "Database error: ' || sqlerrm || '", "backtrace": "' || sys.dbms_utility.format_error_backtrace || '"}';
  end create_new_settlement;

end pame_pkg;
/
