-- ============================================================================
-- UC AI tutorial — "Build an Agent" — Lesson 2
-- The prompt profile, and the agent that uses it
-- ============================================================================
-- Moves the prompt out of your code and into a prompt profile, then creates the
-- agent that runs it.
--
-- Watch the two change_status calls at the end. Both create_prompt_profile and
-- create_agent make a DRAFT, but a call that does not name a version resolves
-- the latest ACTIVE one. Without those two calls the agent cannot be found.
-- ============================================================================
-- Repeatable: an agent cannot be deleted once it has run, because its
-- conversation history points at it. So this script deletes nothing. It creates
-- each object when it is absent, and updates it when it is already there. You
-- can run it as many times as you like, before or after the agent has run.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- 1. The prompt profile
-- ---------------------------------------------------------------------------
-- {engineer_name}, {today} and {question} are placeholders. Every placeholder in
-- either template must have a value on every call, or the run stops with an
-- error.
declare
  l_profile_id number;
  l_exists     pls_integer;

  c_description constant varchar2(400 char) :=
    'The service-contract desk: answers questions about one service contract and '
    || 'can raise a credit note against it.';

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
  -- rownum stops at the first hit: this asks "is there one?", not "how many?"
  select count(*)
    into l_exists
    from uc_ai_prompt_profiles
   where code = 'SC_DESK_PROFILE'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'SC_DESK_PROFILE'
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_parameters_schema      => c_parameters
    );
    sys.dbms_output.put_line('Prompt profile SC_DESK_PROFILE created, id=' || l_profile_id);
  else
    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_code                   => 'SC_DESK_PROFILE'
    , p_version                => 1
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_openai
    , p_model                  => uc_ai_openai.c_model_gpt_5_6_terra
    , p_parameters_schema      => c_parameters
    );
    sys.dbms_output.put_line('Prompt profile SC_DESK_PROFILE updated.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 2. The agent
-- ---------------------------------------------------------------------------
declare
  l_agent_id number;
  l_exists   pls_integer;
begin
  -- rownum stops at the first hit: this asks "is there one?", not "how many?"
  select count(*)
    into l_exists
    from uc_ai_agents
   where code = 'SC_DESK'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'SC_DESK'
    , p_description         => 'Service-contract desk agent'
    , p_agent_type          => uc_ai_agents_api.c_type_profile
    , p_prompt_profile_code => 'SC_DESK_PROFILE'
    , p_timeout_seconds     => 120
    );
    sys.dbms_output.put_line('Agent SC_DESK created, id=' || l_agent_id);
  else
    sys.dbms_output.put_line('Agent SC_DESK is already there, left as it is.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 3. Activate both. Do not skip this.
-- ---------------------------------------------------------------------------
-- A draft is invisible to a call that does not name a version. Miss either line
-- and the next lesson fails with "no data found" and nothing says why.
begin
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
  sys.dbms_output.put_line('Profile and agent are both active.');
end;
/

-- ---------------------------------------------------------------------------
-- Verification — both rows must say 'active'
-- ---------------------------------------------------------------------------
set feedback off
prompt

select 'prompt profile' as object, code, version, status
  from uc_ai_prompt_profiles
 where code = 'SC_DESK_PROFILE'
union all
select 'agent', code, version, status
  from uc_ai_agents
 where code = 'SC_DESK';

set feedback on
