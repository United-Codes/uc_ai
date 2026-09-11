-- ============================================================================
-- UC AI tutorial — "Build an Agent" — Lesson 3
-- The read tools of the service-contract desk
-- ============================================================================
-- Registers three tools that read the contract of the current run.
--
-- Look at what is NOT in these schemas: none of them has a contract parameter.
-- The contract arrives in the run context, which UC AI adds to the arguments
-- under the reserved key `_ctx` AFTER the model produced them. The model cannot
-- name a contract, so it cannot read another customer's contract.
--
-- merge_tool_from_schema is used instead of create_tool_from_schema, so you can
-- run this script again after you change a description.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

declare
  l_tool_id number;
begin
  -- --------------------------------------------------------------------------
  -- SC_GET_CONTRACT — no arguments at all
  -- --------------------------------------------------------------------------
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_GET_CONTRACT'
  , p_description   => 'Get the service contract of the current conversation: '
                    || 'the customer, the coverage level, and the coverage window. '
                    || 'Call this first when you need to know what the contract covers.'
  , p_function_call => 'return sc_desk_pkg.get_contract(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {},
      "required": []
    }')
  , p_tags          => apex_t_varchar2('scdesk')
  );
  sys.dbms_output.put_line('SC_GET_CONTRACT   id=' || l_tool_id);

  -- --------------------------------------------------------------------------
  -- SC_LIST_CALLS
  -- --------------------------------------------------------------------------
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_LIST_CALLS'
  , p_description   => 'List the service calls of the contract of this conversation, '
                    || 'newest first. Each call says whether it falls inside the '
                    || 'coverage window of the contract.'
  , p_function_call => 'return sc_desk_pkg.list_calls(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "max_rows": {
          "type": "integer",
          "description": "How many calls to return at most. Defaults to 20."
        }
      },
      "required": []
    }')
  , p_tags          => apex_t_varchar2('scdesk')
  );
  sys.dbms_output.put_line('SC_LIST_CALLS     id=' || l_tool_id);

  -- --------------------------------------------------------------------------
  -- SC_LIST_INVOICES
  -- --------------------------------------------------------------------------
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_LIST_INVOICES'
  , p_description   => 'List the invoices of the contract of this conversation, with '
                    || 'the parts amount, the labour amount, how much is already '
                    || 'credited, and how much is still uncredited. Use this before '
                    || 'you raise a credit note.'
  , p_function_call => 'return sc_desk_pkg.list_invoices(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "max_rows": {
          "type": "integer",
          "description": "How many invoices to return at most. Defaults to 20."
        }
      },
      "required": []
    }')
  , p_tags          => apex_t_varchar2('scdesk')
  );
  sys.dbms_output.put_line('SC_LIST_INVOICES  id=' || l_tool_id);

  commit;
end;
/

-- ---------------------------------------------------------------------------
-- Give the tools to the agent
-- ---------------------------------------------------------------------------
-- The tools reach the model through the prompt profile of the agent. The tag
-- 'scdesk' selects exactly these tools, so the agent never sees any other tool
-- in your schema.
--
-- This updates the SAME profile version lesson 2 created. It does not create a
-- new version, so the agent keeps resolving to the profile it already used.
-- get_prompt_profile returns the profile row, so the update below changes only
-- the model configuration and keeps every other value exactly as it was.
declare
  l_profile uc_ai_prompt_profiles%rowtype;
  c_config  constant clob := '{
    "g_enable_tools": true,
    "g_tool_tags": ["scdesk"],
    "g_max_tool_calls": 8
  }';
begin
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
                 p_code    => 'SC_DESK_PROFILE'
               , p_version => 1
               );

  l_profile.model_config_json := c_config;
  uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_profile);

  commit;
  sys.dbms_output.put_line('Profile SC_DESK_PROFILE v1 now offers the "scdesk" tools.');
end;
/

-- ---------------------------------------------------------------------------
-- Verification — the three tools, and the proof that none takes a contract
-- ---------------------------------------------------------------------------
set feedback off
prompt
prompt The three tools, and every parameter each one declares:
prompt

select t.code
     , t.active
     , nvl(( select listagg(p.name, ', ' on overflow truncate)
                     within group (order by p.name)
               from uc_ai_tool_parameters p
              where p.tool_id = t.id )
          , '(none)') as declared_parameters
  from uc_ai_tools t
 where t.code like 'SC\_%' escape '\'
 order by t.code;

prompt
prompt No row above may name a contract. The contract comes from the run context.
prompt

set feedback on

-- ---------------------------------------------------------------------------
-- Run it
-- ---------------------------------------------------------------------------
-- The same question as lesson 1, through the agent, with the run bound to
-- contract 88. The block generates the session id itself and prints it, because
-- lesson 4 reads the trace of this run by that id.
set serveroutput on
declare
  l_result  json_object_t;
  l_session varchar2(255 char) := uc_ai_agents_api.generate_session_id;
begin
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'SC_DESK'
  , p_input_parameters => json_object_t('{"engineer_name":"Petra"
      ,"today":"' || to_char(sysdate, 'YYYY-MM-DD') || '"
      ,"question":"How much can I still credit on INV-1003, and is the call inside the coverage window?"}')
  , p_session_id       => l_session
  , p_run_context      => json_object_t('{"contract_id":"88"}')
  );

  sys.dbms_output.put_line('SESSION: ' || l_session);
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
end;
/
