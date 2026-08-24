-- ============================================================================
-- UC AI tutorial — "Build an Agent" — Lesson 7
-- Structured output your user interface can use
-- ============================================================================
-- Puts a response schema on the prompt profile, so the desk answers with a JSON
-- object instead of prose. A page can then render each field, and your code can
-- branch on needs_human without reading English.
--
-- CAUTION: a response schema changes the TYPE of final_message. Without a schema
-- it is text, and get_clob reads it. With a schema it is a JSON object, and
-- get_clob returns nothing at all. Read it with get_object instead.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- Put the schema on the profile
-- ---------------------------------------------------------------------------
-- The response schema belongs on the profile, next to the prompt it shapes. The
-- p_response_schema parameter of execute_agent exists for a one-off override.
declare
  l_profile uc_ai_prompt_profiles%rowtype;

  c_schema constant varchar2(2000 char) := '{
    "type": "object",
    "properties": {
      "answer":        { "type": "string",
                         "description": "The reply for the engineer, in one or two sentences" },
      "actions_taken": { "type": "array", "items": { "type": "string" },
                         "description": "What you did, one entry for each tool you used" },
      "needs_human":   { "type": "boolean",
                         "description": "True when a person must decide before anything else happens" },
      "confidence":    { "type": "string", "enum": ["low", "medium", "high"],
                         "description": "How sure you are of the answer" }
    },
    "required": ["answer", "actions_taken", "needs_human", "confidence"],
    "additionalProperties": false
  }';
begin
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('SC_DESK_PROFILE', 1);

  uc_ai_prompt_profiles_api.update_prompt_profile(
    p_code                   => l_profile.code
  , p_version                => l_profile.version
  , p_description            => l_profile.description
  , p_system_prompt_template => l_profile.system_prompt_template
  , p_user_prompt_template   => l_profile.user_prompt_template
  , p_provider               => l_profile.provider
  , p_model                  => l_profile.model
  , p_model_config_json      => l_profile.model_config_json
  , p_response_schema        => c_schema
  , p_parameters_schema      => l_profile.parameters_schema
  );

  commit;
  sys.dbms_output.put_line('Response schema added to SC_DESK_PROFILE v1.');
end;
/

-- ---------------------------------------------------------------------------
-- Run it, and read the answer as an object
-- ---------------------------------------------------------------------------
declare
  l_result  json_object_t;
  l_answer  json_object_t;
  l_actions json_array_t;
  l_session varchar2(255 char) := uc_ai_agents_api.generate_session_id;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'SC_DESK'
  , p_input_parameters => json_object_t('{"engineer_name":"Petra"
      ,"today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"Can I credit 350 on INV-1002? Check it properly."}')
  , p_session_id       => l_session
  , p_run_context      => json_object_t('{"contract_id":"88","engineer":"petra.k"}')
  );

  -- THE TRAP: with a response schema this returns nothing.
  sys.dbms_output.put_line('get_clob  -> ['
    || nvl(l_result.get_clob('final_message'), '(empty)') || ']');

  -- The answer is an object now.
  l_answer := l_result.get_object('final_message');

  sys.dbms_output.put_line('answer      -> ' || l_answer.get_string('answer'));
  sys.dbms_output.put_line('needs_human -> '
    || case when l_answer.get_boolean('needs_human') then 'true' else 'false' end);
  sys.dbms_output.put_line('confidence  -> ' || l_answer.get_string('confidence'));

  l_actions := l_answer.get_array('actions_taken');
  <<action_rows>>
  for i in 0 .. l_actions.get_size - 1 loop
    sys.dbms_output.put_line('action      -> ' || l_actions.get_string(i));
  end loop action_rows;

  -- The tool calls of this run, so you can see the model did not answer blind.
  <<tool_rows>>
  for r in ( select m.seq
                  , m.tool_name
               from uc_ai_agent_messages m
              where m.session_id = l_session
                and m.role = 'tool_call'
              order by m.seq ) loop
    sys.dbms_output.put_line('tool call   -> ' || r.seq || ' ' || r.tool_name);
  end loop tool_rows;
end;
/
