CREATE OR REPLACE PACKAGE tt_timetracking_api AS
/**
 * Time Tracking API Package
 * Designed for AI agents and tools to interact with time tracking data
 * 
 * Author: AI Assistant
 * Created: June 2025
 */

-- Constants
gc_max_json_size CONSTANT NUMBER := 32767;

-- Exception error codes
gc_user_not_found_err CONSTANT NUMBER := -20001;
gc_project_not_found_err CONSTANT NUMBER := -20002;
gc_already_clocked_in_err CONSTANT NUMBER := -20003;
gc_not_clocked_in_err CONSTANT NUMBER := -20004;
gc_invalid_data_err CONSTANT NUMBER := -20005;

/**
 * USER MANAGEMENT FUNCTIONS
 */

-- Add a new user
FUNCTION add_user(
    p_first_name IN VARCHAR2,
    p_last_name IN VARCHAR2,
    p_email IN VARCHAR2,
    p_hire_date IN DATE DEFAULT SYSDATE,
    p_is_active IN VARCHAR2 DEFAULT 'Y'
) RETURN NUMBER;

-- Get user information as JSON
FUNCTION get_user_json(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL
) RETURN CLOB;

-- Get all users as JSON
FUNCTION get_all_users_json(
    p_active_only IN VARCHAR2 DEFAULT 'Y'
) RETURN CLOB;

-- Update user status
PROCEDURE update_user_status(
    p_user_id IN NUMBER,
    p_is_active IN VARCHAR2
);

/**
 * PROJECT MANAGEMENT FUNCTIONS
 */

-- Add a new project
FUNCTION add_project(
    p_project_name IN VARCHAR2,
    p_description IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT SYSDATE,
    p_end_date IN DATE DEFAULT NULL,
    p_status IN VARCHAR2 DEFAULT 'Active'
) RETURN NUMBER;

-- Get project information as JSON
FUNCTION get_project_json(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL
) RETURN CLOB;

-- Get all projects as JSON
FUNCTION get_all_projects_json(
    p_status IN VARCHAR2 DEFAULT NULL
) RETURN CLOB;

-- Update project status
PROCEDURE update_project_status(
    p_project_id IN NUMBER,
    p_status IN VARCHAR2
);

/**
 * TIME ENTRY MANAGEMENT FUNCTIONS
 */

-- Clock in (start time entry)
FUNCTION clock_in(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_notes IN VARCHAR2 DEFAULT NULL,
    p_clock_in_time IN TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP
) RETURN CLOB;

FUNCTION clock_in_json(p_parameters in clob) return clob;

-- Clock out (end time entry)
FUNCTION clock_out(
    p_entry_id IN NUMBER DEFAULT NULL,
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_clock_out_time IN TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP,
    p_notes IN VARCHAR2 DEFAULT NULL
) RETURN CLOB;

-- Add complete time entry (with both clock in and out times)
FUNCTION add_time_entry(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_clock_in_time IN TIMESTAMP WITH LOCAL TIME ZONE,
    p_clock_out_time IN TIMESTAMP WITH LOCAL TIME ZONE,
    p_notes IN VARCHAR2 DEFAULT NULL
) RETURN NUMBER;

-- Get current active time entries (users currently clocked in)
FUNCTION get_active_entries_json RETURN CLOB;

-- Get time entries for a specific user
FUNCTION get_user_time_entries_json(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT NULL,
    p_end_date IN DATE DEFAULT NULL
) RETURN CLOB;

-- Get time entries for a specific project
FUNCTION get_project_time_entries_json(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT NULL,
    p_end_date IN DATE DEFAULT NULL
) RETURN CLOB;

/**
 * REPORTING FUNCTIONS
 */

-- Get monthly time summary for a user
FUNCTION get_user_monthly_summary_json(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL,
    p_year IN NUMBER DEFAULT EXTRACT(YEAR FROM SYSDATE),
    p_month IN NUMBER DEFAULT EXTRACT(MONTH FROM SYSDATE)
) RETURN CLOB;

-- Get project time summary
FUNCTION get_project_summary_json(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL,
    p_start_date IN DATE DEFAULT NULL,
    p_end_date IN DATE DEFAULT NULL
) RETURN CLOB;

-- Get team productivity report
FUNCTION get_team_productivity_json(
    p_start_date IN DATE DEFAULT TRUNC(SYSDATE, 'MM'),
    p_end_date IN DATE DEFAULT LAST_DAY(SYSDATE)
) RETURN CLOB;

-- Get daily time summary
FUNCTION get_daily_summary_json(
    p_date IN DATE DEFAULT SYSDATE
) RETURN CLOB;

/**
 * UTILITY FUNCTIONS
 */

-- Validate user exists and is active
FUNCTION is_user_valid(
    p_user_id IN NUMBER DEFAULT NULL,
    p_email IN VARCHAR2 DEFAULT NULL
) RETURN BOOLEAN;

-- Validate project exists and is active
FUNCTION is_project_valid(
    p_project_id IN NUMBER DEFAULT NULL,
    p_project_name IN VARCHAR2 DEFAULT NULL
) RETURN BOOLEAN;

-- Get user ID from email
FUNCTION get_user_id_by_email(
    p_email IN VARCHAR2
) RETURN NUMBER;

-- Get project ID from name
FUNCTION get_project_id_by_name(
    p_project_name IN VARCHAR2
) RETURN NUMBER;

-- Calculate hours between timestamps
FUNCTION calculate_hours(
    p_start_time IN TIMESTAMP WITH LOCAL TIME ZONE,
    p_end_time IN TIMESTAMP WITH LOCAL TIME ZONE
) RETURN NUMBER;

-- Format timestamp for JSON
FUNCTION format_timestamp_json(
    p_timestamp IN TIMESTAMP WITH LOCAL TIME ZONE
) RETURN VARCHAR2;

END tt_timetracking_api;
/
