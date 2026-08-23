/*
  UC AI tools — complete timetracking example
  =============================================================================
  A multi-tool setup from the UC AI tools guide
  (https://www.united-codes.com/products/uc-ai/docs/guides/tools/):
  employees (tt_users) can clock in on projects (tt_projects) with a note.

  The AI gets three tools:
    - TT_GET_USERS     read-only, no parameters
    - TT_GET_PROJECTS  read-only, no parameters
    - TT_CLOCK_IN      action with a JSON parameter object

  NOTE: the tables (tt_users, tt_projects, tt_time_entries) belong to an
  illustrative timetracking demo schema — adapt table and column names to
  your own data model. Expected shape:
    tt_users        (user_id, first_name, last_name, email, hire_date, is_active)
    tt_projects     (project_id, project_name, description, is_active)
    tt_time_entries (entry_id, user_id, project_id, clock_in_ts, notes)

  Run order: package spec -> package body -> tool registrations -> test block.
*/


-- =============================================================================
-- 1) Tool functions
-- =============================================================================

create or replace package tt_timetracking_api
as

  -- read-only tool: all users as one JSON CLOB
  function get_all_users_json
  return clob;

  -- read-only tool: all projects as one JSON CLOB
  function get_all_projects_json
  return clob;

  -- action tool: clock a user in on a project
  -- p_parameters is a JSON object: {"user_email": "...", "project_name": "...", "notes": "..."}
  function clock_in_json (
    p_parameters in clob
  ) return clob;

end tt_timetracking_api;
/

create or replace package body tt_timetracking_api
as

  function get_all_users_json
  return clob
  as
    l_json clob;
  begin
    select json_arrayagg(
             json_object(
               'user_id'    value user_id,
               'first_name' value first_name,
               'last_name'  value last_name,
               'email'      value email,
               'hire_date'  value to_char(hire_date, 'YYYY-MM-DD'),
               'is_active'  value is_active
             )
             order by last_name, first_name
             returning clob
           )
      into l_json
      from tt_users;

    return coalesce(l_json, '[]');
  end get_all_users_json;


  function get_all_projects_json
  return clob
  as
    l_json clob;
  begin
    select json_arrayagg(
             json_object(
               'project_id'   value project_id,
               'project_name' value project_name,
               'description'  value description,
               'is_active'    value is_active
             )
             order by project_name
             returning clob
           )
      into l_json
      from tt_projects;

    return coalesce(l_json, '[]');
  end get_all_projects_json;


  -- internal helper: does the actual clock-in, returns feedback text for the AI
  function clock_in (
    p_email        in varchar2
  , p_project_name in varchar2
  , p_notes        in varchar2
  ) return clob
  as
    l_user_id    tt_users.user_id%type;
    l_project_id tt_projects.project_id%type;
  begin
    begin
      select user_id
        into l_user_id
        from tt_users
       where lower(email) = lower(p_email)
         and is_active = 'Y';
    exception
      when no_data_found then
        return 'Error: no active user found with email "' || p_email
            || '". Use the TT_GET_USERS tool to look up valid users.';
    end;

    begin
      select project_id
        into l_project_id
        from tt_projects
       where lower(project_name) = lower(p_project_name);
    exception
      when no_data_found then
        return 'Error: project "' || p_project_name
            || '" not found. Use the TT_GET_PROJECTS tool to look up valid project names.';
    end;

    insert into tt_time_entries (user_id, project_id, clock_in_ts, notes)
    values (l_user_id, l_project_id, systimestamp, p_notes);

    return 'User "' || p_email || '" clocked in successfully on project "' || p_project_name || '"'
        || case when p_notes is not null then ' with note: ' || p_notes end;
  end clock_in;


  function clock_in_json (
    p_parameters in clob
  ) return clob
  as
    l_json         json_object_t;
    l_user_email   varchar2(255 char);
    l_project_name varchar2(255 char);
    l_notes        varchar2(4000 char);
  begin
    l_json := json_object_t(p_parameters);
    l_user_email   := l_json.get_string('user_email');
    l_project_name := l_json.get_string('project_name');
    l_notes        := l_json.get_string('notes');

    -- validate inputs: return error text (don't raise) so the AI can self-correct
    if l_user_email is null then
      return 'Error: user_email is required';
    elsif l_project_name is null then
      return 'Error: project_name is required';
    end if;

    begin
      return clock_in(
        p_email        => l_user_email
      , p_project_name => l_project_name
      , p_notes        => l_notes
      );
    exception
      when others then
        return 'Error: ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace;
    end;
  end clock_in_json;

end tt_timetracking_api;
/


-- =============================================================================
-- 2) Tool registrations
--    merge_tool_from_schema is an idempotent upsert -> safe to re-run in
--    deployment scripts (parameters and tags are replaced on update)
-- =============================================================================

declare
  l_tool_id uc_ai_tools.id%type;
  l_schema  json_object_t;
begin
  -- parameterless read-only tool: p_json_schema => null, no bind variable
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'TT_GET_USERS'
  , p_description   => 'Get information on all the users in the system'
  , p_function_call => 'return tt_timetracking_api.get_all_users_json();'
  , p_json_schema   => null
  , p_tags          => apex_t_varchar2('time-tracking', 'users')
  );

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'TT_GET_PROJECTS'
  , p_description   => 'Get information on all the projects in the system'
  , p_function_call => 'return tt_timetracking_api.get_all_projects_json();'
  , p_json_schema   => null
  , p_tags          => apex_t_varchar2('time-tracking', 'projects')
  );

  -- tool with parameters: JSON schema + exactly one bind (:parameters)
  l_schema := json_object_t('{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
      "user_email": {
        "type": "string",
        "description": "The email address of the user to clock in"
      },
      "project_name": {
        "type": "string",
        "description": "The name of the project to clock in to"
      },
      "notes": {
        "type": "string",
        "description": "Optional description of what the user is working on"
      }
    },
    "required": [
      "user_email",
      "project_name"
    ]
  }');

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'TT_CLOCK_IN'
  , p_description   => 'Clock in a user to the time tracking system. This needs a user_email and project_name as parameters. You can get these from other tools. Optionally pass notes if given by the user.
Example parameters: {"user_email": "user@example.com","project_name": "TV Marketing", "notes": "Look for actors"} or {"user_email": "john.doe@gmail.com","project_name": "Inventing Teleportation"}'
  , p_function_call => 'return tt_timetracking_api.clock_in_json(:parameters);'
  , p_json_schema   => l_schema
  , p_tags          => apex_t_varchar2('time-tracking', 'users', 'projects')
  );

  commit;
end;
/


-- =============================================================================
-- 3) Test: let the AI chain the tools
--    (it should look up the user, look up the project, then clock in)
-- =============================================================================

declare
  l_result        json_object_t;
  l_final_message clob;
begin
  -- API key: uc_ai_get_key function or uc_ai_google.g_apex_web_credential := 'GEMINI';
  uc_ai.reset_globals;         -- globals are session-scoped, start clean
  uc_ai.g_enable_tools := true;
  -- optionally restrict which tools the AI sees
  uc_ai.g_tool_tags := apex_t_varchar2('time-tracking');

  l_result := uc_ai.generate_text(
    p_user_prompt    => 'Please clock me in on the Website Relaunch project. I am pam.beesly@dundermifflin.com and I will design the new landing page.'
  , p_system_prompt  => 'You are an assistant to a time tracking system.
    Your tools give you access to user, project and timetracking information.
    Answer concise and short.'
  , p_provider       => uc_ai.c_provider_google
  , p_model          => uc_ai_google.c_model_gemini_3_7_flash
    -- model constants change with releases: check the installed uc_ai_google spec
  , p_max_tool_calls => 6
  );

  l_final_message := l_result.get_clob('final_message');
  sys.dbms_output.put_line('AI Response: ' || l_final_message);
  sys.dbms_output.put_line('Finish reason: ' || l_result.get_string('finish_reason'));
end;
/
