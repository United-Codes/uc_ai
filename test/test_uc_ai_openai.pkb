create or replace package body test_uc_ai_openai as

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

  procedure basic_recipe
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
  begin
    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'I have tomatoes, salad, potatoes, olives, and cheese. What an I cook with that?',
      p_system_prompt => 'You are an assistant helping users to get recipes. Please answer in short sentences.'
    );

    l_final_message := l_result.get_clob('final_message');
    ut.expect(l_final_message).to_be_not_null();

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    ut.expect(l_message_count).to_equal(3);

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    sys.dbms_output.put_line('Last message: ' || l_final_message);
  end basic_recipe;



  procedure tool_user_info
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_tool_calls_count pls_integer;
  begin
    delete from UC_AI_TOOLS where 1 = 1;
    add_get_users_tool;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'What is the email address of Jim?',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.'
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);
    

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%jim.halpert@dundermifflin.com%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- system proppt, user, tool call, tool_response, assistant
    ut.expect(l_message_count).to_equal(5);

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_equal(1);

  end tool_user_info;


  procedure tool_clock_in_user
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_tool_calls_count pls_integer;

    l_user_id number;
  begin
    delete from UC_AI_TOOL_PARAMETERS where 1 = 1;
    delete from UC_AI_TOOLS where 1 = 1;
    add_get_users_tool;
    add_get_projects_tool;
    add_clock_tools;

    -- delete all time entries for Michael Scott (to avouid error "aleady clocked in")
    select user_id into l_user_id from TT_USERS where email = 'michael.scott@dundermifflin.com';
    delete from TT_TIME_ENTRIES where user_id = l_user_id;

    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.
        The current user is Michael Scott.

        If you clock somebody in, answer with: "You are now clocked in to the project "{{project_name}}" with the note "{{notes| - }}".'
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%now clocked in%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- multiple cool calls
    ut.expect(l_message_count).to_be_greater_than(5);

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_be_greater_than(1);

  end tool_clock_in_user;


  procedure tool_clock_in_user_eror_handling
  as
    l_result json_object_t;
    l_final_message clob;
    l_messages json_array_t;
    l_message_count pls_integer;
    l_tool_calls_count pls_integer;
  begin
    delete from UC_AI_TOOLS where 1 = 1;
    add_get_users_tool;
    add_get_projects_tool;
    add_clock_tools;


    l_result := uc_ai.GENERATE_TEXT(
      p_user_prompt => 'Please clock me in to the marketing project with the note "meeting".',
      p_system_prompt => 'You are an assistant to a time tracking system. Your tools give you access to user, project and timetracking information. Answer concise and short.
        The current user is Michael Scott.

        If you clock somebody in, answer with: "You are now clocked in to the project "{{project_name}}" with the note "{{notes| - }}".'
    );

    sys.dbms_output.put_line('Result: ' || l_result.to_string);

    l_final_message := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Last message: ' || l_final_message);
    ut.expect(lower(l_final_message)).to_be_like('%now clocked in%');

    l_messages := treat(l_result.get('messages') as json_array_t);
    l_message_count := l_messages.get_size;
    -- multiple cool calls
    ut.expect(l_message_count).to_be_greater_than(5);

    l_tool_calls_count := l_result.get_number('tool_calls_count');
    sys.dbms_output.put_line('Tool calls: ' || l_tool_calls_count);
    ut.expect(l_tool_calls_count).to_be_greater_than(1);

  end tool_clock_in_user_eror_handling;

end test_uc_ai_openai;
/
