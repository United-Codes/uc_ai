create or replace package body pame_pkg as

  procedure reset_global_variables
  as
  begin
    uc_ai.g_base_url := 'host.containers.internal:11434/api';
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;
    uc_ai_oci.g_compartment_id := 'change_to_your_compartment_id';
    uc_ai_oci.g_region := 'change_to_your_region';
    uc_ai_oci.g_apex_web_credential := 'change_to_your_awc';
  end reset_global_variables;

  function create_new_settlement(p_settlement_data in clob) return clob
  as
    l_settlement_data json_object_t;

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
    BEGIN
      l_settlement_data := json_object_t.parse(p_settlement_data);
    EXCEPTION
      when others then
        return '{"status": "error", "message": "Invalid JSON input: ' || sqlerrm || '"}';
    END;

    -- Validate required fields and extract from JSON    
    if not l_settlement_data.has('incident_date') then
      return '{"status": "error", "message": "Missing required field: incident_date"}';
    end if;

    if not l_settlement_data.has('claimant_first_name') then
      return '{"status": "error", "message": "Missing required field: claimant_first_name"}';
    end if;

    if not l_settlement_data.has('claimant_last_name') then
      return '{"status": "error", "message": "Missing required field: claimant_last_name"}';
    end if;

    -- Extract required fields
    -- generate pattern like this: CL2025-009-ACC
    l_claim_number := 'CL' || to_char(sysdate, 'YYYY') || '-' || round(sys.dbms_random.value(100, 999999)) || '-AI';
    l_policy_number := 'POL' || to_char(sysdate, 'YYYY') || '-' || round(sys.dbms_random.value(100, 999999)) || '-AI';
    l_incident_date := to_date(l_settlement_data.get_String('incident_date'), 'FXYYYY-MM-DD');
    l_claimant_fname := l_settlement_data.get_String('claimant_first_name');
    l_claimant_lname := l_settlement_data.get_String('claimant_last_name');

    -- Extract optional fields
    l_policy_type := case when l_settlement_data.has('policy_type') 
                         then l_settlement_data.get_String('policy_type') 
                         else null end;
    l_incident_desc := case when l_settlement_data.has('incident_description') 
                           then l_settlement_data.get_String('incident_description') 
                           else null end;
    l_claimant_email := case when l_settlement_data.has('claimant_email') 
                            then l_settlement_data.get_String('claimant_email') 
                            else null end;
    l_claimant_phone := case when l_settlement_data.has('claimant_phone') 
                            then l_settlement_data.get_String('claimant_phone') 
                            else null end;
    l_insured_fname := case when l_settlement_data.has('insured_first_name') 
                           then l_settlement_data.get_String('insured_first_name') 
                           else null end;
    l_insured_lname := case when l_settlement_data.has('insured_last_name') 
                           then l_settlement_data.get_String('insured_last_name') 
                           else null end;
    l_settlement_amount := case when l_settlement_data.has('settlement_amount') 
                               then l_settlement_data.get_Number('settlement_amount') 
                               else 0 end;
    l_currency_code := case when l_settlement_data.has('currency_code') 
                           then l_settlement_data.get_String('currency_code') 
                           else 'EUR' end;
    l_notes := case when l_settlement_data.has('notes') 
                   then l_settlement_data.get_String('notes') 
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

  function get_user_info(p_email_data in clob) return clob
  as
    l_email_data   json_object_t;
    l_email        varchar2(255 char);
    l_user_record  pame_users%rowtype;
    l_result       clob;
  begin
    BEGIN
      l_email_data := json_object_t.parse(p_email_data);
    EXCEPTION
      when others then
        return '{"status": "error", "message": "Invalid JSON input: ' || sqlerrm || '", "backtrace": "' || sys.dbms_utility.format_error_backtrace || '"}';
    END;

    -- Validate required field
    if not l_email_data.has('email') then
      return '{"status": "error", "message": "Missing required field: email"}';
    end if;

    -- Extract email from JSON
    l_email := l_email_data.get_String('email');

    -- Validate email format (basic check)
    if l_email is null or length(trim(l_email)) = 0 then
      return '{"status": "error", "message": "Email cannot be empty"}';
    end if;

    if instr(l_email, '@') = 0 then
      return '{"status": "error", "message": "Invalid email format"}';
    end if;

    -- Query user by email
    begin
      select user_id, first_name, last_name, email, phone, created_at, updated_at
      into l_user_record.user_id, l_user_record.first_name, l_user_record.last_name, 
           l_user_record.email, l_user_record.phone, l_user_record.created_at, l_user_record.updated_at
      from pame_users
      where lower(email) = lower(l_email);

      -- Build success response with user data
      l_result := '{"status": "success", "user": {' ||
        '"user_id": "' || l_user_record.user_id || '",' ||
        '"first_name": "' || l_user_record.first_name || '",' ||
        '"last_name": "' || l_user_record.last_name || '",' ||
        '"email": "' || l_user_record.email || '",' ||
        '"phone": "' || nvl(l_user_record.phone, 'null') || '",' ||
        '"created_at": "' || to_char(l_user_record.created_at, 'YYYY-MM-DD"T"HH24:MI:SS') || '",' ||
        '"updated_at": "' || to_char(l_user_record.updated_at, 'YYYY-MM-DD"T"HH24:MI:SS') || '"' ||
        '}}';

    exception
      when no_data_found then
        l_result := '{"status": "error", "message": "No user found with email: ' || l_email || '"}';
      when too_many_rows then
        l_result := '{"status": "error", "message": "Multiple users found with email: ' || l_email || ' (data integrity issue)"}';
      when others then
        l_result := '{"status": "error", "message": "Database error in user lookup: ' || sqlerrm || '", "backtrace": "' || sys.dbms_utility.format_error_backtrace || '"}';
    end;

    return l_result;

  exception
    when others then
      return '{"status": "error", "message": "Database error: ' || sqlerrm || '", "backtrace": "' || sys.dbms_utility.format_error_backtrace || '"}';
  end get_user_info;


  function get_tools_markdown 
    return clob
  as
    cursor c_tools is
      with tool_tags as (
        select 
          tool_id,
          listagg('`' || tag_name || '`', ', ') within group (order by tag_name) as tags
        from uc_ai_tool_tags
        group by tool_id
      ), parameter_hierarchy as (
        select 
          p.id,
          p.tool_id,
          t.code as tool_code,
          t.description as tool_description,
          t.function_call,
          p.name as parameter_name,
          p.description as parameter_description,
          p.required,
          p.data_type,
          p.is_array,
          p.parent_param_id,
          p.min_num_val,
          p.max_num_val,
          p.enum_values,
          p.default_value,
          p.array_min_items,
          p.array_max_items,
          p.pattern,
          p.format,
          p.min_length,
          p.max_length,
          level as hierarchy_level,
          sys_connect_by_path(p.name, ' > ') as parameter_path,
          connect_by_root p.id as root_parameter_id,
          connect_by_isleaf as is_leaf_parameter,
          tt.tags
        from uc_ai_tool_parameters p
        join uc_ai_tools t on p.tool_id = t.id
        left join tool_tags tt on t.id = tt.tool_id
        where t.active = 1
        start with p.parent_param_id is null
        connect by prior p.id = p.parent_param_id
        order siblings by p.name
      )
      select 
        ph.tool_code,
        ph.tool_description,
        ph.tags,
        ph.function_call,
        ph.parameter_name,
        lpad(' ', (ph.hierarchy_level - 1) * 2, ' ') || ph.parameter_name as indented_name,
        ph.parameter_description,
        case ph.required 
          when 1 then 'Yes' 
          else 'No' 
        end as required_display,
        case 
          when ph.is_array = 1 then ph.data_type || '[]'
          else ph.data_type
        end as data_type_display,
        ph.hierarchy_level,
        case 
          when ph.data_type in ('number', 'integer') and (ph.min_num_val is not null or ph.max_num_val is not null) then
            'Range: ' || 
            coalesce(to_char(ph.min_num_val), '∞') || ' - ' || 
            coalesce(to_char(ph.max_num_val), '∞')
          when ph.data_type = 'string' and (ph.min_length is not null or ph.max_length is not null) then
            'Length: ' || 
            coalesce(to_char(ph.min_length), '0') || ' - ' || 
            coalesce(to_char(ph.max_length), '∞') || ' chars'
          when ph.enum_values is not null then
            'Values: ' || ph.enum_values
          when ph.pattern is not null then
            'Pattern: ' || ph.pattern
        end as validation_info,
        case 
          when ph.is_array = 1 and (ph.array_min_items is not null or ph.array_max_items is not null) then
            'Items: ' || 
            coalesce(to_char(ph.array_min_items), '0') || ' - ' || 
            coalesce(to_char(ph.array_max_items), '∞')
        end as array_constraints,
        ph.default_value,
        ph.format,
        case when lead(ph.tool_code) over (partition by ph.tool_code order by ph.hierarchy_level, ph.required desc, ph.parameter_name) is null then 1 else 0 end as is_last_parameter
      from parameter_hierarchy ph
      where lower(tool_code) like 'pame_%'
      order by ph.tool_code, ph.hierarchy_level, ph.required desc, ph.parameter_name;

    l_current_tool varchar2(500 char);
    l_markdown_output clob;
    l_tool_function_call clob;
  begin
    <<tool_loop>>
    for rec in c_tools loop
      -- Check if we're starting a new tool
      if l_current_tool != rec.tool_code or l_current_tool is null then
        l_current_tool := rec.tool_code;

        -- Add tool header
        l_markdown_output := l_markdown_output || chr(10) || '## ' || rec.tool_code || chr(10) || chr(10);
        l_markdown_output := l_markdown_output || rec.tool_description || chr(10) || chr(10);
        l_markdown_output := l_markdown_output || 'Tags: ' || nvl(rec.tags, '-') || chr(10) || chr(10);
        l_markdown_output := l_markdown_output || '### Parameters' || chr(10) || chr(10);
        l_markdown_output := l_markdown_output || '| Parameter | Type | Required | Description | Constraints |' || chr(10);
        l_markdown_output := l_markdown_output || '|-----------|------|----------|-------------|-------------|' || chr(10);

        l_tool_function_call := '### Function Call: ' || chr(10) || chr(10) 
              || '```sql' || chr(10)
              || rec.function_call || chr(10)
              || '```' || chr(10) || chr(10);
      end if;

      -- Add parameter row
      l_markdown_output := l_markdown_output || '| ';

      -- Parameter name with indentation for hierarchy
      if rec.hierarchy_level > 1 then
        l_markdown_output := l_markdown_output || lpad('└─ ', (rec.hierarchy_level - 1) * 2, '&nbsp;&nbsp;') || rec.parameter_name;
      else
        l_markdown_output := l_markdown_output || rec.parameter_name;
      end if;

      l_markdown_output := l_markdown_output || ' | ' || rec.data_type_display;
      l_markdown_output := l_markdown_output || ' | ' || rec.required_display;
      l_markdown_output := l_markdown_output || ' | ' || nvl(rec.parameter_description, '-');

      -- Constraints column
      l_markdown_output := l_markdown_output || ' | ';
      if rec.validation_info is not null then
        l_markdown_output := l_markdown_output || rec.validation_info;
      end if;
      if rec.array_constraints is not null then
        if rec.validation_info is not null then
          l_markdown_output := l_markdown_output || '<br>';
        end if;
        l_markdown_output := l_markdown_output || rec.array_constraints;
      end if;
      if rec.default_value is not null then
        if rec.validation_info is not null or rec.array_constraints is not null then
          l_markdown_output := l_markdown_output || '<br>';
        end if;
        l_markdown_output := l_markdown_output || 'Default: ' || rec.default_value;
      end if;
      if rec.format is not null then
        if rec.validation_info is not null or rec.array_constraints is not null or rec.default_value is not null then
          l_markdown_output := l_markdown_output || '<br>';
        end if;
        l_markdown_output := l_markdown_output || 'Format: ' || rec.format;
      end if;
      if rec.validation_info is null and rec.array_constraints is null and rec.default_value is null and rec.format is null then
        l_markdown_output := l_markdown_output || '-';
      end if;

      l_markdown_output := l_markdown_output || ' |' || chr(10);

      if rec.is_last_parameter = 1 then  
        l_markdown_output := l_markdown_output || chr(10) || l_tool_function_call;
      end if;
    end loop tool_loop;

    -- Output the markdown
    return l_markdown_output;
  end get_tools_markdown;

end pame_pkg;
/
