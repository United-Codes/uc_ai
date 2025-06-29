CREATE OR REPLACE PACKAGE BODY tt_timetracking_api AS

-- Private constants
gc_date_format CONSTANT VARCHAR2(30 char) := 'YYYY-MM-DD"T"HH24:MI:SS';

/**
 * UTILITY FUNCTIONS
 */

FUNCTION format_timestamp_json(
    p_timestamp IN TIMESTAMP WITH LOCAL TIME ZONE
) RETURN VARCHAR2 IS
BEGIN
    IF p_timestamp IS NULL THEN
        RETURN 'null';
    END IF;
    RETURN '"' || TO_CHAR(p_timestamp, gc_date_format) || '"';
END format_timestamp_json;

FUNCTION calculate_hours(
    p_start_time IN TIMESTAMP WITH LOCAL TIME ZONE,
    p_end_time IN TIMESTAMP WITH LOCAL TIME ZONE
) RETURN NUMBER IS
BEGIN
    IF p_start_time IS NULL OR p_end_time IS NULL THEN
        RETURN NULL;
    END IF;
    
    RETURN EXTRACT(DAY FROM (p_end_time - p_start_time)) * 24 +
           EXTRACT(HOUR FROM (p_end_time - p_start_time)) +
           EXTRACT(MINUTE FROM (p_end_time - p_start_time)) / 60 +
           EXTRACT(SECOND FROM (p_end_time - p_start_time)) / 3600;
END calculate_hours;

FUNCTION get_user_id_by_email(
    p_email IN VARCHAR2
) RETURN NUMBER IS
    l_user_id NUMBER;
BEGIN
    SELECT user_id 
    INTO l_user_id
    FROM tt_users
    WHERE UPPER(email) = UPPER(p_email)
    AND is_active = 'Y';
    
    RETURN l_user_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(gc_user_not_found_err, 'User with email ' || p_email || ' not found or inactive');
END get_user_id_by_email;

FUNCTION get_project_id_by_name(
    p_project_name IN VARCHAR2
) RETURN NUMBER IS
    l_project_id NUMBER;
BEGIN
    SELECT project_id 
    INTO l_project_id
    FROM tt_projects
    WHERE UPPER(project_name) = UPPER(p_project_name)
    AND status IN ('Active', 'On Hold');
    
    RETURN l_project_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(gc_project_not_found_err, 'Project ' || p_project_name || ' not found or not active');
END get_project_id_by_name;

FUNCTION is_user_valid(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL
) RETURN BOOLEAN IS
    l_count NUMBER;
    l_user_id NUMBER;
BEGIN
    IF p_user_id IS NOT NULL THEN
        l_user_id := p_user_id;
    ELSIF p_email IS NOT NULL THEN
        l_user_id := get_user_id_by_email(p_email);
    ELSE
        RETURN FALSE;
    END IF;
    
    SELECT COUNT(*)
    INTO l_count
    FROM tt_users
    WHERE user_id = l_user_id
    AND is_active = 'Y';
    
    RETURN l_count > 0;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END is_user_valid;

FUNCTION is_project_valid(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL
) RETURN BOOLEAN IS
    l_count NUMBER;
    l_project_id NUMBER;
BEGIN
    IF p_project_id IS NOT NULL THEN
        l_project_id := p_project_id;
    ELSIF p_project_name IS NOT NULL THEN
        l_project_id := get_project_id_by_name(p_project_name);
    ELSE
        RETURN FALSE;
    END IF;
    
    SELECT COUNT(*)
    INTO l_count
    FROM tt_projects
    WHERE project_id = l_project_id
    AND status IN ('Active', 'On Hold');
    
    RETURN l_count > 0;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END is_project_valid;

/**
 * USER MANAGEMENT FUNCTIONS
 */

FUNCTION add_user(
    p_first_name IN VARCHAR2,
    p_last_name IN VARCHAR2,
    p_email IN VARCHAR2,
    p_hire_date IN DATE DEFAULT SYSDATE,
    p_is_active IN VARCHAR2 DEFAULT 'Y'
) RETURN NUMBER IS
    l_user_id NUMBER;
BEGIN
    -- Validate input
    IF p_first_name IS NULL OR p_last_name IS NULL OR p_email IS NULL THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'First name, last name, and email are required');
    END IF;
    
    INSERT INTO tt_users (first_name, last_name, email, hire_date, is_active)
    VALUES (p_first_name, p_last_name, p_email, p_hire_date, p_is_active)
    RETURNING user_id INTO l_user_id;
    
    RETURN l_user_id;
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'User with email ' || p_email || ' already exists');
END add_user;

FUNCTION get_user_json(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL
) RETURN CLOB IS
    l_json CLOB;
    l_user_id NUMBER;
BEGIN
    IF p_user_id IS NOT NULL THEN
        l_user_id := p_user_id;
    ELSIF p_email IS NOT NULL THEN
        l_user_id := get_user_id_by_email(p_email);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either user_id or email must be provided');
    END IF;
    
    SELECT JSON_OBJECT(
        'user_id' VALUE user_id,
        'first_name' VALUE first_name,
        'last_name' VALUE last_name,
        'email' VALUE email,
        'hire_date' VALUE TO_CHAR(hire_date, 'YYYY-MM-DD'),
        'is_active' VALUE is_active
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_users
    WHERE user_id = l_user_id;
    
    RETURN l_json;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(gc_user_not_found_err, 'User not found');
END get_user_json;

FUNCTION get_all_users_json(
    p_active_only IN VARCHAR2 DEFAULT 'Y'
) RETURN CLOB IS
    l_json CLOB;
BEGIN
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'user_id' VALUE user_id,
            'first_name' VALUE first_name,
            'last_name' VALUE last_name,
            'email' VALUE email,
            'hire_date' VALUE TO_CHAR(hire_date, 'YYYY-MM-DD'),
            'is_active' VALUE is_active
        )
        ORDER BY last_name, first_name
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_users
    WHERE (p_active_only = 'N' OR is_active = 'Y');
    
    RETURN NVL(l_json, '[]');
END get_all_users_json;

PROCEDURE update_user_status(
    p_user_id IN NUMBER,
    p_is_active IN VARCHAR2
) IS
    l_count NUMBER;
BEGIN
    -- Validate status
    IF p_is_active NOT IN ('Y', 'N') THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Status must be Y or N');
    END IF;
    
    UPDATE tt_users
    SET is_active = p_is_active
    WHERE user_id = p_user_id;
    
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(gc_user_not_found_err, 'User not found');
    END IF;
    
    -- If deactivating user, clock out any active time entries
    IF p_is_active = 'N' THEN
        UPDATE tt_time_entries
        SET clock_out_time = SYSTIMESTAMP,
            notes = CASE 
                WHEN notes IS NULL THEN 'Auto-clocked out due to user deactivation'
                ELSE notes || ' (Auto-clocked out due to user deactivation)'
            END
        WHERE user_id = p_user_id
        AND clock_out_time IS NULL;
    END IF;
END update_user_status;

/**
 * PROJECT MANAGEMENT FUNCTIONS
 */

FUNCTION add_project(
    p_project_name IN VARCHAR2,
    p_description IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT SYSDATE,
    p_end_date IN DATE DEFAULT NULL,
    p_status IN VARCHAR2 DEFAULT 'Active'
) RETURN NUMBER IS
    l_project_id NUMBER;
BEGIN
    -- Validate input
    IF p_project_name IS NULL THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Project name is required');
    END IF;
    
    IF p_status NOT IN ('Active', 'Completed', 'On Hold', 'Archived') THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Invalid status. Must be Active, Completed, On Hold, or Archived');
    END IF;
    
    INSERT INTO tt_projects (project_name, project_description, start_date, end_date, status)
    VALUES (p_project_name, p_description, p_start_date, p_end_date, p_status)
    RETURNING project_id INTO l_project_id;
    
    RETURN l_project_id;
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Project with name ' || p_project_name || ' already exists');
END add_project;

FUNCTION get_project_json(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL
) RETURN CLOB IS
    l_json CLOB;
    l_project_id NUMBER;
BEGIN
    IF p_project_id IS NOT NULL THEN
        l_project_id := p_project_id;
    ELSIF p_project_name IS NOT NULL THEN
        l_project_id := get_project_id_by_name(p_project_name);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either project_id or project_name must be provided');
    END IF;
    
    SELECT JSON_OBJECT(
        'project_id' VALUE project_id,
        'project_name' VALUE project_name,
        'project_description' VALUE project_description,
        'start_date' VALUE TO_CHAR(start_date, 'YYYY-MM-DD'),
        'end_date' VALUE TO_CHAR(end_date, 'YYYY-MM-DD'),
        'status' VALUE status
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_projects
    WHERE project_id = l_project_id;
    
    RETURN l_json;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(gc_project_not_found_err, 'Project not found');
END get_project_json;

FUNCTION get_all_projects_json(
    p_status IN VARCHAR2 DEFAULT NULL
) RETURN CLOB IS
    l_json CLOB;
BEGIN
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'project_id' VALUE project_id,
            'project_name' VALUE project_name,
            'project_description' VALUE project_description,
            'start_date' VALUE TO_CHAR(start_date, 'YYYY-MM-DD'),
            'end_date' VALUE TO_CHAR(end_date, 'YYYY-MM-DD'),
            'status' VALUE status
        )
        ORDER BY project_name
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_projects
    WHERE (p_status IS NULL OR status = p_status);
    
    RETURN NVL(l_json, '[]');
END get_all_projects_json;

PROCEDURE update_project_status(
    p_project_id IN NUMBER,
    p_status IN VARCHAR2
) IS
BEGIN
    -- Validate status
    IF p_status NOT IN ('Active', 'Completed', 'On Hold', 'Archived') THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Invalid status. Must be Active, Completed, On Hold, or Archived');
    END IF;
    
    UPDATE tt_projects
    SET status = p_status
    WHERE project_id = p_project_id;
    
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(gc_project_not_found_err, 'Project not found');
    END IF;
    
    -- If completing or archiving project, clock out any active time entries
    IF p_status IN ('Completed', 'Archived') THEN
        UPDATE tt_time_entries
        SET clock_out_time = SYSTIMESTAMP,
            notes = CASE 
                WHEN notes IS NULL THEN 'Auto-clocked out due to project status change'
                ELSE notes || ' (Auto-clocked out due to project status change)'
            END
        WHERE project_id = p_project_id
        AND clock_out_time IS NULL;
    END IF;
END update_project_status;

/**
 * TIME ENTRY MANAGEMENT FUNCTIONS
 */

FUNCTION clock_in(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_notes IN VARCHAR2 DEFAULT NULL,
    p_clock_in_time IN TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP
) RETURN CLOB IS
    l_entry_id NUMBER;
    l_user_id NUMBER;
    l_project_id NUMBER;
    l_active_count NUMBER;
BEGIN
    -- Get user ID
    IF p_user_id IS NOT NULL THEN
        l_user_id := p_user_id;
    ELSIF p_email IS NOT NULL THEN
        l_user_id := get_user_id_by_email(p_email);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either user_id or email must be provided');
    END IF;
    
    -- Get project ID
    IF p_project_id IS NOT NULL THEN
        l_project_id := p_project_id;
    ELSIF p_project_name IS NOT NULL THEN
        l_project_id := get_project_id_by_name(p_project_name);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either project_id or project_name must be provided');
    END IF;
    
    -- Check if user is already clocked in
    SELECT COUNT(*)
    INTO l_active_count
    FROM tt_time_entries
    WHERE user_id = l_user_id
    AND clock_out_time IS NULL;
    
    IF l_active_count > 0 THEN
        RAISE_APPLICATION_ERROR(gc_already_clocked_in_err, 'User is already clocked in to a project');
    END IF;
    
    -- Validate user and project
    IF NOT is_user_valid(l_user_id) THEN
        RAISE_APPLICATION_ERROR(gc_user_not_found_err, 'User not found or inactive');
    END IF;
    
    IF NOT is_project_valid(l_project_id) THEN
        RAISE_APPLICATION_ERROR(gc_project_not_found_err, 'Project not found or inactive');
    END IF;
    
    INSERT INTO tt_time_entries (user_id, project_id, clock_in_time, notes)
    VALUES (l_user_id, l_project_id, p_clock_in_time, p_notes)
    RETURNING entry_id INTO l_entry_id;
    
    RETURN 'User is succesfully clocked id (entry_id: ' || l_entry_id || ')';
END clock_in;

FUNCTION clock_in_json(
    p_parameters in clob
) return clob
as
    l_json json_object_t;
    l_user_email VARCHAR2(255 char);
    l_project_name VARCHAR2(255 char);
    l_notes VARCHAR2(4000 char);
begin
    logger.log_info('clock_in_json called with parameters: ' || p_parameters);

    l_json := json_object_t(p_parameters);
    l_user_email := l_json.get_string('user_email');
    l_project_name := l_json.get_string('project_name');
    l_notes := l_json.get_string('notes');

    if l_user_email is null then
        return 'Error: user_email is required';
    elsif l_project_name is null then
        return 'Error: project_name is required';
    end if;

    begin
        return clock_in(
            p_email => l_user_email,
            p_project_name => l_project_name,
            p_notes => l_notes
        );
    exception
        when others then
            return 'Error: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace;
    end;
end clock_in_json;

FUNCTIOn clock_out(
    p_entry_id IN NUMBER DEFAULT NULL,
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_clock_out_time IN TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP,
    p_notes IN VARCHAR2 DEFAULT NULL
) RETURN CLOB IS
    l_user_id NUMBER;
    l_entry_id NUMBER;
    l_count NUMBER;
BEGIN
    IF p_entry_id IS NOT NULL THEN
        -- Clock out specific entry
        UPDATE tt_time_entries
        SET clock_out_time = p_clock_out_time,
            notes = CASE 
                WHEN p_notes IS NOT NULL THEN p_notes
                ELSE notes
            END
        WHERE entry_id = p_entry_id
        AND clock_out_time IS NULL;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(gc_not_clocked_in_err, 'Time entry not found or already clocked out');
        END IF;
    ELSE
        -- Get user ID and clock out their active entry
        IF p_user_id IS NOT NULL THEN
            l_user_id := p_user_id;
        ELSIF p_email IS NOT NULL THEN
            l_user_id := get_user_id_by_email(p_email);
        ELSE
            RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either entry_id or user identification must be provided');
        END IF;
        
        UPDATE tt_time_entries
        SET clock_out_time = p_clock_out_time,
            notes = CASE 
                WHEN p_notes IS NOT NULL THEN p_notes
                ELSE notes
            END
        WHERE user_id = l_user_id
        AND clock_out_time IS NULL;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(gc_not_clocked_in_err, 'User is not currently clocked in');
        END IF;
    END IF;

    RETURN 'User is succesfully clocked out';
END clock_out;

FUNCTION add_time_entry(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_clock_in_time IN TIMESTAMP WITH LOCAL TIME ZONE,
    p_clock_out_time IN TIMESTAMP WITH LOCAL TIME ZONE,
    p_notes IN VARCHAR2 DEFAULT NULL
) RETURN NUMBER IS
    l_entry_id NUMBER;
    l_user_id NUMBER;
    l_project_id NUMBER;
BEGIN
    -- Validate times
    IF p_clock_in_time IS NULL OR p_clock_out_time IS NULL THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Both clock in and clock out times are required');
    END IF;
    
    IF p_clock_out_time <= p_clock_in_time THEN
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Clock out time must be after clock in time');
    END IF;
    
    -- Get user ID
    IF p_user_id IS NOT NULL THEN
        l_user_id := p_user_id;
    ELSIF p_email IS NOT NULL THEN
        l_user_id := get_user_id_by_email(p_email);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either user_id or email must be provided');
    END IF;
    
    -- Get project ID
    IF p_project_id IS NOT NULL THEN
        l_project_id := p_project_id;
    ELSIF p_project_name IS NOT NULL THEN
        l_project_id := get_project_id_by_name(p_project_name);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either project_id or project_name must be provided');
    END IF;
    
    -- Validate user and project
    IF NOT is_user_valid(l_user_id) THEN
        RAISE_APPLICATION_ERROR(gc_user_not_found_err, 'User not found or inactive');
    END IF;
    
    IF NOT is_project_valid(l_project_id) THEN
        RAISE_APPLICATION_ERROR(gc_project_not_found_err, 'Project not found or inactive');
    END IF;
    
    INSERT INTO tt_time_entries (user_id, project_id, clock_in_time, clock_out_time, notes)
    VALUES (l_user_id, l_project_id, p_clock_in_time, p_clock_out_time, p_notes)
    RETURNING entry_id INTO l_entry_id;
    
    RETURN l_entry_id;
END add_time_entry;

FUNCTION get_active_entries_json RETURN CLOB IS
    l_json CLOB;
BEGIN
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'entry_id' VALUE te.entry_id,
            'user_id' VALUE te.user_id,
            'user_name' VALUE u.first_name || ' ' || u.last_name,
            'user_email' VALUE u.email,
            'project_id' VALUE te.project_id,
            'project_name' VALUE p.project_name,
            'clock_in_time' VALUE TO_CHAR(te.clock_in_time, gc_date_format),
            'hours_worked' VALUE ROUND(calculate_hours(te.clock_in_time, SYSTIMESTAMP), 2),
            'notes' VALUE te.notes
        )
        ORDER BY te.clock_in_time
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_time_entries te
    JOIN tt_users u ON te.user_id = u.user_id
    JOIN tt_projects p ON te.project_id = p.project_id
    WHERE te.clock_out_time IS NULL
    AND u.is_active = 'Y';
    
    RETURN NVL(l_json, '[]');
END get_active_entries_json;

FUNCTION get_user_time_entries_json(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT NULL,
    p_end_date IN DATE DEFAULT NULL
) RETURN CLOB IS
    l_json CLOB;
    l_user_id NUMBER;
    l_start_date DATE;
    l_end_date DATE;
BEGIN
    -- Get user ID
    IF p_user_id IS NOT NULL THEN
        l_user_id := p_user_id;
    ELSIF p_email IS NOT NULL THEN
        l_user_id := get_user_id_by_email(p_email);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either user_id or email must be provided');
    END IF;
    
    -- Set default date range if not provided
    l_start_date := coalesce(p_start_date, TRUNC(SYSDATE, 'MM'));
    l_end_date := coalesce(p_end_date, LAST_DAY(SYSDATE));
    
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'entry_id' VALUE te.entry_id,
            'project_id' VALUE te.project_id,
            'project_name' VALUE p.project_name,
            'clock_in_time' VALUE TO_CHAR(te.clock_in_time, gc_date_format),
            'clock_out_time' VALUE 
                CASE 
                    WHEN te.clock_out_time IS NULL THEN 'null'
                    ELSE TO_CHAR(te.clock_out_time, gc_date_format)
                END,
            'hours_worked' VALUE 
                CASE 
                    WHEN te.clock_out_time IS NULL THEN null
                    ELSE ROUND(calculate_hours(te.clock_in_time, te.clock_out_time), 2)
                END,
            'notes' VALUE te.notes,
            'is_active' VALUE 
                CASE 
                    WHEN te.clock_out_time IS NULL THEN 'true'
                    ELSE 'false'
                END
        )
        ORDER BY te.clock_in_time DESC
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_time_entries te
    JOIN tt_projects p ON te.project_id = p.project_id
    WHERE te.user_id = l_user_id
    AND TRUNC(te.clock_in_time) BETWEEN l_start_date AND l_end_date;
    
    RETURN NVL(l_json, '[]');
END get_user_time_entries_json;

FUNCTION get_project_time_entries_json(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT NULL,
    p_end_date IN DATE DEFAULT NULL
) RETURN CLOB IS
    l_json CLOB;
    l_project_id NUMBER;
    l_start_date DATE;
    l_end_date DATE;
BEGIN
    -- Get project ID
    IF p_project_id IS NOT NULL THEN
        l_project_id := p_project_id;
    ELSIF p_project_name IS NOT NULL THEN
        l_project_id := get_project_id_by_name(p_project_name);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either project_id or project_name must be provided');
    END IF;
    
    -- Set default date range if not provided
    l_start_date := coalesce(p_start_date, TRUNC(SYSDATE, 'MM'));
    l_end_date := coalesce(p_end_date, LAST_DAY(SYSDATE));
    
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'entry_id' VALUE te.entry_id,
            'user_id' VALUE te.user_id,
            'user_name' VALUE u.first_name || ' ' || u.last_name,
            'user_email' VALUE u.email,
            'clock_in_time' VALUE TO_CHAR(te.clock_in_time, gc_date_format),
            'clock_out_time' VALUE 
                CASE 
                    WHEN te.clock_out_time IS NULL THEN 'null'
                    ELSE TO_CHAR(te.clock_out_time, gc_date_format)
                END,
            'hours_worked' VALUE 
                CASE 
                    WHEN te.clock_out_time IS NULL THEN null
                    ELSE ROUND(calculate_hours(te.clock_in_time, te.clock_out_time), 2)
                END,
            'notes' VALUE te.notes,
            'is_active' VALUE 
                CASE 
                    WHEN te.clock_out_time IS NULL THEN 'true'
                    ELSE 'false'
                END
        )
        ORDER BY te.clock_in_time DESC
        RETURNING CLOB
    )
    INTO l_json
    FROM tt_time_entries te
    JOIN tt_users u ON te.user_id = u.user_id
    WHERE te.project_id = l_project_id
    AND TRUNC(te.clock_in_time) BETWEEN l_start_date AND l_end_date;
    
    RETURN NVL(l_json, '[]');
END get_project_time_entries_json;

/**
 * REPORTING FUNCTIONS
 */

FUNCTION get_user_monthly_summary_json(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_year IN NUMBER DEFAULT EXTRACT(YEAR FROM SYSDATE),
    p_month IN NUMBER DEFAULT EXTRACT(MONTH FROM SYSDATE)
) RETURN CLOB IS
    l_json CLOB;
    l_user_id NUMBER;
    l_start_date DATE;
    l_end_date DATE;
BEGIN
    -- Get user ID
    IF p_user_id IS NOT NULL THEN
        l_user_id := p_user_id;
    ELSIF p_email IS NOT NULL THEN
        l_user_id := get_user_id_by_email(p_email);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either user_id or email must be provided');
    END IF;
    
    -- Calculate date range
    l_start_date := TO_DATE(p_year || '-' || LPAD(p_month, 2, '0') || '-01', 'FXYYYY-MM-DD');
    l_end_date := LAST_DAY(l_start_date);
    
    WITH monthly_summary AS (
        SELECT 
            te.project_id,
            p.project_name,
            COUNT(*) as total_entries,
            SUM(CASE WHEN te.clock_out_time IS NULL THEN 0 ELSE calculate_hours(te.clock_in_time, te.clock_out_time) END) as total_hours,
            COUNT(CASE WHEN te.clock_out_time IS NULL THEN 1 END) as active_entries
        FROM tt_time_entries te
        JOIN tt_projects p ON te.project_id = p.project_id
        WHERE te.user_id = l_user_id
        AND TRUNC(te.clock_in_time) BETWEEN l_start_date AND l_end_date
        GROUP BY te.project_id, p.project_name
    ),
    user_info AS (
        SELECT first_name, last_name, email
        FROM tt_users
        WHERE user_id = l_user_id
    )
    SELECT JSON_OBJECT(
        'user_id' VALUE l_user_id,
        'user_name' VALUE ui.first_name || ' ' || ui.last_name,
        'user_email' VALUE ui.email,
        'year' VALUE p_year,
        'month' VALUE p_month,
        'month_name' VALUE TO_CHAR(l_start_date, 'Month'),
        'total_hours' VALUE ROUND(NVL(SUM(ms.total_hours), 0), 2),
        'total_entries' VALUE NVL(SUM(ms.total_entries), 0),
        'active_entries' VALUE NVL(SUM(ms.active_entries), 0),
        'projects' VALUE JSON_ARRAYAGG(
            JSON_OBJECT(
                'project_id' VALUE ms.project_id,
                'project_name' VALUE ms.project_name,
                'total_hours' VALUE ROUND(ms.total_hours, 2),
                'total_entries' VALUE ms.total_entries,
                'active_entries' VALUE ms.active_entries
            )
            ORDER BY ms.total_hours DESC
        )
        RETURNING CLOB
    )
    INTO l_json
    FROM user_info ui
    LEFT JOIN monthly_summary ms ON 1=1
    GROUP BY ui.first_name, ui.last_name, ui.email;
    
    RETURN l_json;
END get_user_monthly_summary_json;

FUNCTION get_project_summary_json(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT NULL,
    p_end_date IN DATE DEFAULT NULL
) RETURN CLOB IS
    l_json CLOB;
    l_project_id NUMBER;
    l_start_date DATE;
    l_end_date DATE;
BEGIN
    -- Get project ID
    IF p_project_id IS NOT NULL THEN
        l_project_id := p_project_id;
    ELSIF p_project_name IS NOT NULL THEN
        l_project_id := get_project_id_by_name(p_project_name);
    ELSE
        RAISE_APPLICATION_ERROR(gc_invalid_data_err, 'Either project_id or project_name must be provided');
    END IF;
    
    -- Set default date range if not provided
    l_start_date := coalesce(p_start_date, TRUNC(SYSDATE, 'MM'));
    l_end_date := coalesce(p_end_date, LAST_DAY(SYSDATE));
    
    WITH project_summary AS (
        SELECT 
            te.user_id,
            u.first_name || ' ' || u.last_name as user_name,
            u.email,
            COUNT(*) as total_entries,
            SUM(CASE WHEN te.clock_out_time IS NULL THEN 0 ELSE calculate_hours(te.clock_in_time, te.clock_out_time) END) as total_hours,
            COUNT(CASE WHEN te.clock_out_time IS NULL THEN 1 END) as active_entries
        FROM tt_time_entries te
        JOIN tt_users u ON te.user_id = u.user_id
        WHERE te.project_id = l_project_id
        AND TRUNC(te.clock_in_time) BETWEEN l_start_date AND l_end_date
        GROUP BY te.user_id, u.first_name, u.last_name, u.email
    ),
    project_info AS (
        SELECT project_name, project_description, status
        FROM tt_projects
        WHERE project_id = l_project_id
    )
    SELECT JSON_OBJECT(
        'project_id' VALUE l_project_id,
        'project_name' VALUE pi.project_name,
        'project_description' VALUE pi.project_description,
        'project_status' VALUE pi.status,
        'start_date' VALUE TO_CHAR(l_start_date, 'YYYY-MM-DD'),
        'end_date' VALUE TO_CHAR(l_end_date, 'YYYY-MM-DD'),
        'total_hours' VALUE ROUND(NVL(SUM(ps.total_hours), 0), 2),
        'total_entries' VALUE NVL(SUM(ps.total_entries), 0),
        'active_entries' VALUE NVL(SUM(ps.active_entries), 0),
        'users' VALUE JSON_ARRAYAGG(
            JSON_OBJECT(
                'user_id' VALUE ps.user_id,
                'user_name' VALUE ps.user_name,
                'user_email' VALUE ps.email,
                'total_hours' VALUE ROUND(ps.total_hours, 2),
                'total_entries' VALUE ps.total_entries,
                'active_entries' VALUE ps.active_entries
            )
            ORDER BY ps.total_hours DESC
        )
        RETURNING CLOB
    )
    INTO l_json
    FROM project_info pi
    LEFT JOIN project_summary ps ON 1=1
    GROUP BY pi.project_name, pi.project_description, pi.status;
    
    RETURN l_json;
END get_project_summary_json;

FUNCTION get_team_productivity_json(
    p_start_date IN DATE DEFAULT TRUNC(SYSDATE, 'MM'),
    p_end_date IN DATE DEFAULT LAST_DAY(SYSDATE)
) RETURN CLOB IS
    l_json CLOB;
BEGIN
    WITH productivity_summary AS (
        SELECT 
            u.user_id,
            u.first_name || ' ' || u.last_name as user_name,
            u.email,
            COUNT(*) as total_entries,
            SUM(CASE WHEN te.clock_out_time IS NULL THEN 0 ELSE calculate_hours(te.clock_in_time, te.clock_out_time) END) as total_hours,
            COUNT(CASE WHEN te.clock_out_time IS NULL THEN 1 END) as active_entries,
            COUNT(DISTINCT te.project_id) as projects_worked_on
        FROM tt_users u
        LEFT JOIN tt_time_entries te ON u.user_id = te.user_id 
            AND TRUNC(te.clock_in_time) BETWEEN p_start_date AND p_end_date
        WHERE u.is_active = 'Y'
        GROUP BY u.user_id, u.first_name, u.last_name, u.email
    )
    SELECT JSON_OBJECT(
        'start_date' VALUE TO_CHAR(p_start_date, 'YYYY-MM-DD'),
        'end_date' VALUE TO_CHAR(p_end_date, 'YYYY-MM-DD'),
        'total_team_hours' VALUE ROUND(NVL(SUM(ps.total_hours), 0), 2),
        'total_team_entries' VALUE NVL(SUM(ps.total_entries), 0),
        'active_team_entries' VALUE NVL(SUM(ps.active_entries), 0),
        'team_members' VALUE JSON_ARRAYAGG(
            JSON_OBJECT(
                'user_id' VALUE ps.user_id,
                'user_name' VALUE ps.user_name,
                'user_email' VALUE ps.email,
                'total_hours' VALUE ROUND(NVL(ps.total_hours, 0), 2),
                'total_entries' VALUE NVL(ps.total_entries, 0),
                'active_entries' VALUE NVL(ps.active_entries, 0),
                'projects_worked_on' VALUE NVL(ps.projects_worked_on, 0)
            )
            ORDER BY ps.total_hours DESC
        )
        RETURNING CLOB
    )
    INTO l_json
    FROM productivity_summary ps;
    
    RETURN l_json;
END get_team_productivity_json;

FUNCTION get_daily_summary_json(
    p_date IN DATE DEFAULT SYSDATE
) RETURN CLOB IS
    l_json CLOB;
    l_target_date DATE;
BEGIN
    l_target_date := TRUNC(p_date);
    
    WITH daily_summary AS (
        SELECT 
            p.project_id,
            p.project_name,
            COUNT(*) as total_entries,
            SUM(CASE WHEN te.clock_out_time IS NULL THEN 0 ELSE calculate_hours(te.clock_in_time, te.clock_out_time) END) as total_hours,
            COUNT(CASE WHEN te.clock_out_time IS NULL THEN 1 END) as active_entries,
            COUNT(DISTINCT te.user_id) as users_worked
        FROM tt_projects p
        LEFT JOIN tt_time_entries te ON p.project_id = te.project_id 
            AND TRUNC(te.clock_in_time) = l_target_date
        GROUP BY p.project_id, p.project_name
        HAVING COUNT(te.entry_id) > 0
    )
    SELECT JSON_OBJECT(
        'date' VALUE TO_CHAR(l_target_date, 'YYYY-MM-DD'),
        'day_of_week' VALUE TO_CHAR(l_target_date, 'Day'),
        'total_hours' VALUE ROUND(NVL(SUM(ds.total_hours), 0), 2),
        'total_entries' VALUE NVL(SUM(ds.total_entries), 0),
        'active_entries' VALUE NVL(SUM(ds.active_entries), 0),
        'projects' VALUE JSON_ARRAYAGG(
            JSON_OBJECT(
                'project_id' VALUE ds.project_id,
                'project_name' VALUE ds.project_name,
                'total_hours' VALUE ROUND(ds.total_hours, 2),
                'total_entries' VALUE ds.total_entries,
                'active_entries' VALUE ds.active_entries,
                'users_worked' VALUE ds.users_worked
            )
            ORDER BY ds.total_hours DESC
        )
        RETURNING CLOB
    )
    INTO l_json
    FROM daily_summary ds;
    
    RETURN l_json;
END get_daily_summary_json;

END tt_timetracking_api;
/
