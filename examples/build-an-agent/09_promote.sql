-- ============================================================================
-- UC AI tutorial — "Build an Agent" — Lesson 9
-- Move the desk to another database
-- ============================================================================
-- Your prompt profile, your tools and your agent are ROWS, not source files. So
-- they are not in your repository, and a deployment does not carry them.
--
-- This script is the deployment. Run it against the target schema after the
-- packages are compiled there. It is written to be run more than one time, so it
-- also works as an upgrade: nothing is deleted, and every object is created when
-- it is absent and updated when it is there.
--
-- What it does NOT carry, on purpose:
--   the demo tables       -- your real tables are already there
--   the run history       -- the history of a development schema is not production data
--   the memory stores     -- what the desk learned in development is not true there
-- ============================================================================

-- @dblinter ignore(g-5010): a deployment script reports what it did with dbms_output on
-- purpose, so the output is visible in a release log. A logging framework would hide it.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- 1. The tools
-- ---------------------------------------------------------------------------
-- merge_tool_from_schema is create-or-replace for a tool, so this is safe to
-- repeat. The handler package must already be compiled in the target schema.
declare
  l_tool_id number;
begin
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_GET_CONTRACT'
  , p_description   => 'Get the service contract of the current conversation: '
                    || 'the customer, the coverage level, and the coverage window. '
                    || 'Call this first when you need to know what the contract covers.'
  , p_function_call => 'return sc_desk_pkg.get_contract(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{},"required":[]}')
  , p_tags          => apex_t_varchar2('scdesk')
  );

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_LIST_CALLS'
  , p_description   => 'List the service calls of the contract of this conversation, '
                    || 'newest first. Each call says whether it falls inside the '
                    || 'coverage window of the contract.'
  , p_function_call => 'return sc_desk_pkg.list_calls(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{"max_rows":
      {"type":"integer","description":"How many calls to return at most. Defaults to 20."}},
      "required":[]}')
  , p_tags          => apex_t_varchar2('scdesk')
  );

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_LIST_INVOICES'
  , p_description   => 'List the invoices of the contract of this conversation, with '
                    || 'the parts amount, the labour amount, how much is already '
                    || 'credited, and how much is still uncredited. Use this before '
                    || 'you raise a credit note.'
  , p_function_call => 'return sc_desk_pkg.list_invoices(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{"max_rows":
      {"type":"integer","description":"How many invoices to return at most. Defaults to 20."}},
      "required":[]}')
  , p_tags          => apex_t_varchar2('scdesk')
  );

  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'SC_RAISE_CREDIT_NOTE'
  , p_description   => 'Raise a credit note against one invoice of the contract of this '
                    || 'conversation. The database checks the contract, the coverage '
                    || 'window, the coverage level and the amount that is still '
                    || 'uncredited, and refuses with a reason when a check fails.'
  , p_function_call => 'return sc_desk_pkg.raise_credit_note(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{"type":"object","properties":{
      "invoice_no":{"type":"string","description":"The invoice to credit, for example INV-1001"},
      "amount":{"type":"number","description":"The amount to credit"},
      "reason":{"type":"string","description":"Why the credit note is raised, in one sentence"}},
      "required":["invoice_no","amount"]}')
  , p_tags          => apex_t_varchar2('scdesk')
  );

  commit;
  sys.dbms_output.put_line('Four tools merged.');
end;
/

-- ---------------------------------------------------------------------------
-- 2. The prompt profile
-- ---------------------------------------------------------------------------
-- A profile is versioned data. This deploys version 1. To ship a changed prompt
-- without touching the running one, raise the version here and activate it when
-- you are ready. Remember that activating a new version retires the old one for
-- every caller that resolves by null.
declare
  l_id      number;
  l_exists  pls_integer;
  l_profile uc_ai_prompt_profiles%rowtype;

  c_version constant number := 1;

  c_system_prompt constant varchar2(2000 char) :=
'You are the service-contract desk of a field-service company.
You help {engineer_name}, an internal support engineer. Today is {today}.

You work on ONE service contract at a time. You cannot choose the contract: the
application decides which one this conversation is about, and your tools always
read that contract.

Rules you must follow:
- Never guess a number. Read it with a tool.
- The database decides whether a credit note is allowed. You only ask.
- When a tool refuses, explain the reason to the engineer in plain language.
- Keep answers short. The engineer is on the phone with the customer.';

  c_config constant varchar2(400 char) :=
    '{"g_enable_tools": true, "g_tool_tags": ["scdesk"], "g_max_tool_calls": 8}';

  c_parameters constant varchar2(1000 char) := '{
      "type": "object",
      "properties": {
        "engineer_name": { "type": "string", "description": "Name of the support engineer" },
        "today":         { "type": "string", "description": "Todays date, as YYYY-MM-DD" },
        "question":      { "type": "string", "description": "What the engineer asked" }
      },
      "required": ["engineer_name", "today", "question"]
    }';
begin
  select count(*)
    into l_exists
    from uc_ai_prompt_profiles
   where code = 'SC_DESK_PROFILE'
     and version = c_version
     and rownum = 1;

  if l_exists = 0 then
    -- @dblinter ignore(g-2135): the new id is not needed; the script reports the
    -- code and version instead, which is what a release log should show
    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'SC_DESK_PROFILE'
    , p_description            => 'The service-contract desk.'
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_model_config_json      => c_config
    , p_parameters_schema      => c_parameters
    , p_version                => c_version
    );
    sys.dbms_output.put_line('Profile created at version ' || c_version || '.');
  else
    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('SC_DESK_PROFILE', c_version);
    l_profile.description            := 'The service-contract desk.';
    l_profile.system_prompt_template := c_system_prompt;
    l_profile.user_prompt_template   := '{question}';
    l_profile.provider               := uc_ai.c_provider_openai;
    l_profile.model                  := uc_ai_openai.c_model_gpt_5_6_terra;
    l_profile.model_config_json      := c_config;
    l_profile.parameters_schema      := c_parameters;
    uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_profile);
    sys.dbms_output.put_line('Profile updated at version ' || c_version || '.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 3. The agent
-- ---------------------------------------------------------------------------
declare
  l_id     number;
  l_exists pls_integer;
begin
  select count(*)
    into l_exists
    from uc_ai_agents
   where code = 'SC_DESK'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    -- @dblinter ignore(g-2135): the new id is not needed, as above
    l_id := uc_ai_agents_api.create_agent(
      p_code                => 'SC_DESK'
    , p_description         => 'Service-contract desk agent'
    , p_agent_type          => uc_ai_agents_api.c_type_profile
    , p_prompt_profile_code => 'SC_DESK_PROFILE'
    , p_timeout_seconds     => 120
    );
    sys.dbms_output.put_line('Agent created.');
  else
    sys.dbms_output.put_line('Agent is already there.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 4. Memory, and the two activations
-- ---------------------------------------------------------------------------
-- enable_for_agent writes the memory tag into the profile version the agent
-- resolves to now, so it must run AFTER the profile exists and it must run again
-- whenever you ship a new profile version.
begin
  uc_ai_memory.enable_for_agent(
    p_agent_code  => 'SC_DESK'
  , p_scope       => uc_ai_memory.c_scope_context
  , p_context_key => 'contract_id'
  );

  uc_ai_prompt_profiles_api.change_status(
    p_code    => 'SC_DESK_PROFILE'
  , p_version => 1
  , p_status  => uc_ai_prompt_profiles_api.c_status_active
  );

  uc_ai_agents_api.change_status(
    p_code    => 'SC_DESK'
  , p_version => 1
  , p_status  => uc_ai_agents_api.c_status_active
  );

  commit;
  sys.dbms_output.put_line('Memory enabled. Profile and agent are active.');
end;
/

-- ---------------------------------------------------------------------------
-- Verification — what a release log should show
-- ---------------------------------------------------------------------------
set feedback off
prompt

select 'tools' as object, to_char(count(*)) as detail
  from uc_ai_tools
 where code like 'SC\_%' escape '\'
union all
select 'profile', code || ' v' || version || ' ' || status
  from uc_ai_prompt_profiles
 where code = 'SC_DESK_PROFILE'
union all
select 'agent', code || ' v' || version || ' ' || status
  from uc_ai_agents
 where code = 'SC_DESK'
union all
select 'memory', scope || ' on ' || context_key
  from uc_ai_memory_config
 where agent_code = 'SC_DESK';

set feedback on
