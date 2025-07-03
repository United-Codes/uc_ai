create or replace package body uc_ai_test_utils as

  procedure add_get_users_tool
  as
  begin
    insert into UC_AI_TOOLS (
      ID,
      CODE,
      DESCRIPTION,
      ACTIVE,
      VERSION,
      FUNCTION_CALL
    ) values (
      -343,
      'TT_GET_USERS',
      'Get information on all the users in the system',
      1,
      '1.0'
      ,'return tt_timetracking_api.get_all_users_json(''N'');'
    );
  end add_get_users_tool;

  procedure add_get_projects_tool
  as
  begin
    insert into UC_AI_TOOLS (
      ID,
      CODE,
      DESCRIPTION,
      ACTIVE,
      VERSION,
      FUNCTION_CALL
    ) values (
      -495,
      'TT_GET_PROJETS',
      'Get information on all the projects in the system',
      1,
      '1.0'
      ,'return tt_timetracking_api.get_all_projects_json();'
    );
  end add_get_projects_tool;

  procedure add_clock_tools
  as
  begin
    insert into UC_AI_TOOLS (
      ID,
      CODE,
      DESCRIPTION,
      ACTIVE,
      VERSION,
      FUNCTION_CALL
    ) values (
      -874,
      'TT_CLOCK_IN',
      'Clock in a user to the time tracking system. This needs a user_email and project_name as parameters. You can get these from other tools. Optionally pass notes if given by the user.
Example parameters: {"user_email": "user@example.com","project_name": "TV Marketing", "notes": "Look for actors"} or {"user_email": "john.doe@gmail.com","project_name": "Inventing Teleportation"}',
      1,
      '1.0'
      ,'return tt_timetracking_api.clock_in_json(:parameters);'
    );

    Insert into UC_AI_TOOL_PARAMETERS (ID,TOOL_ID,NAME,DESCRIPTION,REQUIRED,DATA_TYPE,PARENT_PARAM_ID) 
    values ('1',-874,'parameters','JSON object containing parameters','1','object', null);
    Insert into UC_AI_TOOL_PARAMETERS (ID,TOOL_ID,NAME,DESCRIPTION,REQUIRED,DATA_TYPE,PARENT_PARAM_ID) 
    values ('2',-874,'user_email','Email of the user','1','string', 1);
    Insert into UC_AI_TOOL_PARAMETERS (ID,TOOL_ID,NAME,DESCRIPTION,REQUIRED,DATA_TYPE,PARENT_PARAM_ID) 
    values ('3',-874,'project_name','Name of the project','1','string', 1);
    Insert into UC_AI_TOOL_PARAMETERS (ID,TOOL_ID,NAME,DESCRIPTION,REQUIRED,DATA_TYPE,PARENT_PARAM_ID) 
    values ('4',-874,'notes','Optional description of what the user is working on','0','string', 1);

  end add_clock_tools;
end uc_ai_test_utils;
