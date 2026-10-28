-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A" — Lesson 1
-- Publish a read-only service desk
-- ============================================================================
-- Run it in SQLcl, in the schema of UC AI, after 00_setup.sql and after you
-- compiled partner_desk_pkg.pks and partner_desk_pkg.pkb.
--
-- It registers two read tools, checks them without a model, creates a prompt
-- profile and an agent, publishes the agent as the A2A endpoint service-desk,
-- and creates one API key for each partner.
--
-- Repeatable: tools and profile are updated, and a second run replaces the
-- endpoint and creates NEW API keys. The keys of the first run stop working.
--
-- Needs: the schema is REST-enabled in ORDS, and it has execute on dbms_crypto.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- Register the two read tools
-- ---------------------------------------------------------------------------
-- Neither schema has a customer parameter. The partner arrives in the run
-- context, under the key a2a_client, after the model produced the arguments.
declare
  l_tool_id number;
begin
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'PARTNER_LIST_ASSETS'
  , p_description   => 'List the machines of the partner company that is calling: '
                    || 'the tag, the model, the contract number, the coverage level, '
                    || 'the coverage window, and whether the machine is under contract today.'
  , p_function_call => 'return partner_desk_pkg.list_assets(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {},
      "required": []
    }')
  , p_tags          => apex_t_varchar2('partner')
  );
  sys.dbms_output.put_line('PARTNER_LIST_ASSETS    id=' || l_tool_id);

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'PARTNER_ASSET_HISTORY'
  , p_description   => 'List the service calls of one machine of the calling partner, '
                    || 'newest first, with the date and a summary of the work.'
  , p_function_call => 'return partner_desk_pkg.get_asset_history(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "asset_tag": {
          "type": "string",
          "description": "The tag of the machine, for example FX-PRESS-01"
        }
      },
      "required": ["asset_tag"]
    }')
  , p_tags          => apex_t_varchar2('partner')
  );
  sys.dbms_output.put_line('PARTNER_ASSET_HISTORY  id=' || l_tool_id);

  commit;
end;
/

-- ---------------------------------------------------------------------------
-- Call the tools without a model
-- ---------------------------------------------------------------------------
-- The arguments below are what UC AI passes to a handler in an A2A run: the
-- arguments of the model, plus the run context under _ctx. Nothing here calls
-- a provider, so the result is the same on every run.
declare
  procedure show(
    p_label in varchar2
  , p_json  in clob
  ) is
  begin
    sys.dbms_output.put_line(p_label);
    sys.dbms_output.put_line('  ' || p_json);
  end show;
begin
  show('northwind, list_assets:'
     , partner_desk_pkg.list_assets('{"_ctx":{"a2a_client":"apikey:northwind"}}'));
  show('ferrolux, list_assets:'
     , partner_desk_pkg.list_assets('{"_ctx":{"a2a_client":"apikey:ferrolux"}}'));
  show('ferrolux asks for the asset of northwind:'
     , partner_desk_pkg.get_asset_history('{"asset_tag":"NW-CHILL-02","_ctx":{"a2a_client":"apikey:ferrolux"}}'));
  show('an unknown client, list_assets:'
     , partner_desk_pkg.list_assets('{"_ctx":{"a2a_client":"apikey:unknown"}}'));
end;
/

-- ---------------------------------------------------------------------------
-- Create the prompt profile and the agent
-- ---------------------------------------------------------------------------
-- The profile has one required input, question. The A2A server fills it with the
-- text of the first message. The tag partner gives the agent exactly these tools.
declare
  l_profile_id number;
  l_exists     pls_integer;
  l_profile    uc_ai_prompt_profiles%rowtype;

  c_description constant varchar2(400 char) :=
    'The partner service desk: answers questions of a partner company about its '
    || 'machines under service contract.';

  c_system_prompt constant varchar2(2000 char) :=
'You are the service desk of a field-service company. You answer questions of a
partner company about its machines under service contract.

Rules you must follow:
- Never guess a fact. Read it with a tool.
- Your tools show the machines of the partner that is calling. If a tool says that
  there is no such machine or that the client is unknown, say so. Do not try to
  find the answer in another way.
- Keep answers short and in plain text.';

  c_parameters constant varchar2(1000 char) := '{
      "type": "object",
      "properties": {
        "question": { "type": "string", "description": "What the partner asked" }
      },
      "required": ["question"]
    }';

  c_config constant clob := '{
    "g_enable_tools": true,
    "g_tool_tags": ["partner"],
    "g_max_tool_calls": 8
  }';
begin
  select count(*)
    into l_exists
    from uc_ai_prompt_profiles
   where code = 'PARTNER_DESK_PROFILE'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'PARTNER_DESK_PROFILE'
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_model_config_json      => c_config
    , p_parameters_schema      => c_parameters
    );
    sys.dbms_output.put_line('Prompt profile PARTNER_DESK_PROFILE created, id=' || l_profile_id);
  else
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('PARTNER_DESK_PROFILE', 1);
    l_profile.description            := c_description;
    l_profile.system_prompt_template := c_system_prompt;
    l_profile.user_prompt_template   := '{question}';
    l_profile.provider               := uc_ai.c_provider_openai;
    l_profile.model                  := uc_ai_openai.c_model_gpt_5_6_terra;
    l_profile.model_config_json      := c_config;
    l_profile.parameters_schema      := c_parameters;
    uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_profile);
    sys.dbms_output.put_line('Prompt profile PARTNER_DESK_PROFILE updated.');
  end if;
end;
/

declare
  l_agent_id number;
  l_exists   pls_integer;
begin
  select count(*)
    into l_exists
    from uc_ai_agents
   where code = 'partner_desk'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'partner_desk'
    , p_description         => 'Answers questions of a partner company about its machines and service contracts.'
    , p_agent_type          => uc_ai_agents_api.c_type_profile
    , p_prompt_profile_code => 'PARTNER_DESK_PROFILE'
    , p_timeout_seconds     => 120
    );
    sys.dbms_output.put_line('Agent partner_desk created, id=' || l_agent_id);
  else
    sys.dbms_output.put_line('Agent partner_desk is already there, left as it is.');
  end if;

  -- Both objects are drafts after creation. A draft is invisible to a call that
  -- names no version, so activate both.
  uc_ai_prompt_profiles_api.change_status(
    p_code    => 'PARTNER_DESK_PROFILE'
  , p_version => 1
  , p_status  => uc_ai_prompt_profiles_api.c_status_active
  );

  uc_ai_agents_api.change_status(
    p_code    => 'partner_desk'
  , p_version => 1
  , p_status  => uc_ai_agents_api.c_status_active
  );

  commit;
  sys.dbms_output.put_line('Profile and agent are both active.');
end;
/

-- ---------------------------------------------------------------------------
-- Publish the agent as an A2A endpoint
-- ---------------------------------------------------------------------------
-- install_ords_module creates the ORDS module that serves every endpoint of the
-- schema. expose_agent creates the endpoint. create_api_key returns a key that
-- is visible only now. The client names must match the client ids that
-- 00_setup.sql put into partner_clients: 'apikey:' followed by the name.
declare
  e_endpoint_missing exception;
  pragma exception_init(e_endpoint_missing, -20430);
begin
  uc_ai_a2a.install_ords_module;

  -- A second run starts clean: this deletes the endpoint with its keys and tasks.
  begin
    uc_ai_a2a.remove_endpoint('service-desk');
  exception
    when e_endpoint_missing then
      -- @dblinter ignore(g-5080): an absent endpoint is the normal case on a first run
      null;
  end;

  uc_ai_a2a.expose_agent(
    p_code             => 'service-desk'
  , p_agent_code       => 'partner_desk'
  , p_name             => 'Partner service desk'
  , p_description      => 'Answers questions of a partner company about its machines and service contracts.'
  , p_text_input_param => 'question'
  );

  sys.dbms_output.put_line('ferrolux key:  ' || uc_ai_a2a.create_api_key('service-desk', 'ferrolux'));
  sys.dbms_output.put_line('northwind key: ' || uc_ai_a2a.create_api_key('service-desk', 'northwind'));

  -- The request handler of ORDS reads the committed endpoint.
  commit;
end;
/

-- ---------------------------------------------------------------------------
-- Verification — one endpoint, two keys
-- ---------------------------------------------------------------------------
set feedback off
prompt
prompt Keep both keys from above: UC AI stores only a hash of each key.
prompt

select e.code as endpoint
     , e.agent_code
     , e.auth_mode
     , e.enabled
     , (select count(*) from uc_ai_a2a_api_keys k where k.endpoint_id = e.id) as api_keys
  from uc_ai_a2a_endpoints e
 where e.code = 'service-desk';

set feedback on
