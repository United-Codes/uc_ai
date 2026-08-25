-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 6
-- Move code mode off your code and onto a row, then measure it
-- ============================================================================
-- Creates the prompt profile and the agent of the cold-chain analyst, runs the
-- agent, and reads the program back out of the message log.
--
-- The flag stops being a line in your PL/SQL. It becomes one key in the model
-- configuration of the prompt profile:
--
--   "g_enable_programmatic_tools": true
--
-- After this you can turn code mode on and off for a deployed agent with an
-- update to one row, and you never touch the calling code again.
--
-- Safe to run more than one time.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on

-- ---------------------------------------------------------------------------
-- 1. The prompt profile
-- ---------------------------------------------------------------------------
-- g_tool_tags in this configuration is written in LOWER CASE. Tags are stored in
-- lower case and the filter is case sensitive, so 'ColdChain' would match no
-- tool, the model would get no tools, and there would be no error to read.
declare
  l_profile_id number;
  l_exists     pls_integer;

  c_description constant varchar2(500 char) := 'Cold-chain analyst. Code mode is on.';

  c_system_prompt constant varchar2(2000 char) :=
'You are the cold-chain analyst of a pharmaceutical logistics operator.
You answer for {analyst_name}. Today is {today}.

A shipment BREAKS THE COLD CHAIN when its temperature stays above the limit of
its product class for LONGER than max_minutes_above, without interruption. One
reading stands for sample_minutes minutes. Add up the minutes of the runs that
are too long. The claim is ceil(total_minutes / 60) * claim_per_hour_eur.

Rules you must follow:
- A single reading above the limit is not a break, and a run that is short
  enough is not a break either.
- Never estimate over readings. Compute.
- File one claim for each shipment that broke the cold chain, with the minutes
  you computed and the amount you computed.
- The database decides whether a claim is allowed. You only ask. Report every
  refusal and the reason it gave.';

  c_config constant clob := '{
    "g_enable_tools": true,
    "g_enable_programmatic_tools": true,
    "g_tool_tags": ["coldchain"],
    "g_max_tool_calls": 10
  }';

  c_parameters constant varchar2(1000 char) := '{
      "type": "object",
      "properties": {
        "analyst_name": { "type": "string", "description": "Name of the analyst" },
        "today":        { "type": "string", "description": "Todays date, as YYYY-MM-DD" },
        "question":     { "type": "string", "description": "What the analyst asked" }
      },
      "required": ["analyst_name", "today", "question"]
    }';
begin
  -- rownum stops at the first hit: this asks "is there one?", not "how many?"
  select count(*)
    into l_exists
    from uc_ai_prompt_profiles
   where code = 'CC_ANALYST_PROFILE'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'CC_ANALYST_PROFILE'
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_anthropic
    , p_model                  => uc_ai_anthropic.c_model_claude_4_6_sonnet
    , p_model_config_json      => c_config
    , p_parameters_schema      => c_parameters
    );
    sys.dbms_output.put_line('Prompt profile CC_ANALYST_PROFILE created, id=' || l_profile_id);
  else
    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_code                   => 'CC_ANALYST_PROFILE'
    , p_version                => 1
    , p_description            => c_description
    , p_system_prompt_template => c_system_prompt
    , p_user_prompt_template   => '{question}'
    , p_provider               => uc_ai.c_provider_anthropic
    , p_model                  => uc_ai_anthropic.c_model_claude_4_6_sonnet
    , p_model_config_json      => c_config
    , p_parameters_schema      => c_parameters
    );
    sys.dbms_output.put_line('Prompt profile CC_ANALYST_PROFILE updated.');
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
  select count(*)
    into l_exists
    from uc_ai_agents
   where code = 'CC_ANALYST'
     and version = 1
     and rownum = 1;

  if l_exists = 0 then
    l_agent_id := uc_ai_agents_api.create_agent(
      p_code                => 'CC_ANALYST'
    , p_description         => 'Cold-chain analyst agent'
    , p_agent_type          => uc_ai_agents_api.c_type_profile
    , p_prompt_profile_code => 'CC_ANALYST_PROFILE'
    , p_timeout_seconds     => 300
    );
    sys.dbms_output.put_line('Agent CC_ANALYST created, id=' || l_agent_id);
  else
    sys.dbms_output.put_line('Agent CC_ANALYST is already there, left as it is.');
  end if;
end;
/

-- ---------------------------------------------------------------------------
-- 3. Activate both. Do not skip this.
-- ---------------------------------------------------------------------------
begin
  uc_ai_prompt_profiles_api.change_status(
    p_code    => 'CC_ANALYST_PROFILE'
  , p_version => 1
  , p_status  => uc_ai_prompt_profiles_api.c_status_active
  );

  uc_ai_agents_api.change_status(
    p_code    => 'CC_ANALYST'
  , p_version => 1
  , p_status  => uc_ai_agents_api.c_status_active
  );
  commit;
  sys.dbms_output.put_line('Profile and agent are active.');
end;
/

-- ---------------------------------------------------------------------------
-- 4. Run it
-- ---------------------------------------------------------------------------
-- Nothing in this block mentions code mode. The row does.
declare
  l_result  json_object_t;
  l_params  json_object_t := json_object_t();
  l_start   number;
  l_seconds number;
begin
  -- So this lesson repeats. A second run refuses every claim with ALREADY_FILED,
  -- which is correct, and not what this block is here to show.
  delete from cc_claims;
  commit;

  -- Prove that the globals are not what turns code mode on here.
  uc_ai.reset_globals;

  l_start := sys.dbms_utility.get_time;

  -- The date comes from the database, not from a literal. 00_setup.sql makes every
  -- date relative to sysdate, so a literal here would age.
  l_params.put('analyst_name', 'Ines');
  l_params.put('today', to_char(sysdate, 'yyyy-mm-dd'));
  l_params.put('question', 'Audit every shipment. File a claim for each one that broke '
    || 'the cold chain, then tell me what you filed and what the database refused.');

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'CC_ANALYST'
  , p_input_parameters => l_params
  );

  l_seconds := round((sys.dbms_utility.get_time - l_start) / 100, 1);

  cc_analyst_pkg.print_header;
  cc_analyst_pkg.print_metrics('agent run', l_result, l_seconds);

  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line('session_id: ' || l_result.get_string('session_id'));
  sys.dbms_output.put_line(' ');
  sys.dbms_output.put_line(l_result.get_clob('final_message'));
  commit;
end;
/

-- ---------------------------------------------------------------------------
-- 5. The program is in the message log
-- ---------------------------------------------------------------------------
-- An agent run records every message. The program the model wrote is the
-- tool_input of the uc_ai__run_code call, and tool_input is a CLOB, so the whole
-- program is there. This is the audit trail of a code-mode run.
set feedback off

prompt
prompt  What the last run of CC_ANALYST did:
prompt

select m.seq
     , m.role
     , m.tool_name
     , length(coalesce(m.tool_input, m.tool_output, m.content)) as detail_chars
  from uc_ai_agent_messages m
 where m.session_id = ( select e.session_id
                          from uc_ai_agent_executions e
                         where e.agent_id = ( select a.id from uc_ai_agents a where a.code = 'CC_ANALYST' )
                         order by e.started_at desc
                         fetch first 1 row only )
 order by m.seq;

prompt
prompt  The numbers of the last five runs:
prompt

select e.status
     , e.tool_calls_count
     , e.total_input_tokens
     , e.total_output_tokens
     , round(extract(second from (e.completed_at - e.started_at))
             + extract(minute from (e.completed_at - e.started_at)) * 60, 1) as seconds
  from uc_ai_agent_executions e
 where e.agent_id = ( select a.id from uc_ai_agents a where a.code = 'CC_ANALYST' )
 order by e.started_at desc
 fetch first 5 rows only;

set feedback on

-- ---------------------------------------------------------------------------
-- 6. Read the program back
-- ---------------------------------------------------------------------------
declare
  l_program clob;
begin
  select m.tool_input
    into l_program
    from uc_ai_agent_messages m
   where m.session_id = ( select e.session_id
                            from uc_ai_agent_executions e
                           where e.agent_id = ( select a.id from uc_ai_agents a where a.code = 'CC_ANALYST' )
                           order by e.started_at desc
                           fetch first 1 row only )
     and m.role = 'tool_call'
     and m.tool_name = uc_ai_tools_api.c_code_mode_tool_code
     and rownum = 1;

  sys.dbms_output.put_line('--- the program of the last agent run ---');
  sys.dbms_output.put_line(json_object_t.parse(l_program).get_clob('code'));
exception
  when no_data_found then
    sys.dbms_output.put_line('The last run wrote no program. Code mode is an offer, not an order.');
end;
/

-- ---------------------------------------------------------------------------
-- 7. Turn it off again, with no code change
-- ---------------------------------------------------------------------------
-- This is the point of putting the flag on the row. Nothing that CALLS the agent
-- changes. Read the configuration back, then update it.
set feedback off

prompt
prompt  The claims the agent filed:
prompt

select s.shipment_no
     , c.minutes_over
     , c.amount_eur
     , c.filed_by
  from cc_claims c
  join cc_shipments s on s.id = c.shipment_id
 order by s.shipment_no;

prompt
prompt  The model configuration of the profile, before the change:
prompt

select p.model_config_json
  from uc_ai_prompt_profiles p
 where p.code = 'CC_ANALYST_PROFILE'
   and p.version = 1;

set feedback on

-- Switch code mode off, and raise the tool-call budget at the same time, because
-- this question needs 26 calls without a program.
declare
  l_profile uc_ai_prompt_profiles%rowtype;
  c_off constant clob := '{
    "g_enable_tools": true,
    "g_enable_programmatic_tools": false,
    "g_tool_tags": ["coldchain"],
    "g_max_tool_calls": 40
  }';
begin
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('CC_ANALYST_PROFILE', 1);

  uc_ai_prompt_profiles_api.update_prompt_profile(
    p_code                   => l_profile.code
  , p_version                => l_profile.version
  , p_description            => l_profile.description
  , p_system_prompt_template => l_profile.system_prompt_template
  , p_user_prompt_template   => l_profile.user_prompt_template
  , p_provider               => l_profile.provider
  , p_model                  => l_profile.model
  , p_model_config_json      => c_off
  , p_parameters_schema      => l_profile.parameters_schema
  );
  commit;

  sys.dbms_output.put_line('Code mode is OFF for CC_ANALYST. No calling code changed.');
end;
/

-- And back on again, so the course is left as the lessons describe it.
declare
  l_profile uc_ai_prompt_profiles%rowtype;
  c_on constant clob := '{
    "g_enable_tools": true,
    "g_enable_programmatic_tools": true,
    "g_tool_tags": ["coldchain"],
    "g_max_tool_calls": 10
  }';
begin
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('CC_ANALYST_PROFILE', 1);

  uc_ai_prompt_profiles_api.update_prompt_profile(
    p_code                   => l_profile.code
  , p_version                => l_profile.version
  , p_description            => l_profile.description
  , p_system_prompt_template => l_profile.system_prompt_template
  , p_user_prompt_template   => l_profile.user_prompt_template
  , p_provider               => l_profile.provider
  , p_model                  => l_profile.model
  , p_model_config_json      => c_on
  , p_parameters_schema      => l_profile.parameters_schema
  );
  commit;

  sys.dbms_output.put_line('Code mode is ON again.');
end;
/

set feedback off

prompt
prompt  The model configuration of the profile, after both updates:
prompt

select p.model_config_json
  from uc_ai_prompt_profiles p
 where p.code = 'CC_ANALYST_PROFILE'
   and p.version = 1;

set feedback on
