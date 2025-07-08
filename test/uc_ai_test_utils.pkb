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


  function get_tool_user_messages 
    return json_array_t
  as
  begin
    return json_array_t(
      '[
      {
        "role": "system",
        "content": "You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short."
      },
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "What is the email address of Jim?"
          }
        ]
      },
      {
        "role": "assistant",
        "content": [
          {
            "type": "tool_call",
            "toolCallId": "tool_call_1",
            "toolName": "TT_GET_USERS",
            "args": "{}"
          }
        ]
      },
      {
        "role": "tool",
        "content": [
          {
            "type": "tool_result",
            "toolCallId": "tool_call_1",
            "toolName": "TT_GET_USERS",
            "result": "[{\"user_id\":2,\"first_name\":\"Pam\",\"last_name\":\"Beesly\",\"email\":\"pam.beesly@dundermifflin.com\",\"hire_date\":\"2024-11-01\",\"is_active\":\"Y\"},{\"user_id\":4,\"first_name\":\"Jim\",\"last_name\":\"Halpert\",\"email\":\"jim.halpert@dundermifflin.com\",\"hire_date\":\"2024-02-01\",\"is_active\":\"Y\"},{\"user_id\":6,\"first_name\":\"Kevin\",\"last_name\":\"Malone\",\"email\":\"kevin.malone@dundermifflin.com\",\"hire_date\":\"2024-10-01\",\"is_active\":\"N\"},{\"user_id\":5,\"first_name\":\"Angela\",\"last_name\":\"Martin\",\"email\":\"angela.martin@dundermifflin.com\",\"hire_date\":\"2024-05-01\",\"is_active\":\"Y\"},{\"user_id\":3,\"first_name\":\"Dwight\",\"last_name\":\"Schrute\",\"email\":\"dwight.schrute@dundermifflin.com\",\"hire_date\":\"2024-02-01\",\"is_active\":\"Y\"},{\"user_id\":1,\"first_name\":\"Michael\",\"last_name\":\"Scott\",\"email\":\"michael.scott@dundermifflin.com\",\"hire_date\":\"2024-05-01\",\"is_active\":\"Y\"}]"
          }
        ]
      }
      ]'
    );
  end get_tool_user_messages;

end uc_ai_test_utils;
