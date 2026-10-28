-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A" — Lesson 3
-- Book a visit: the database decides
-- ============================================================================
-- Run it after 01_publish.sql. It does four things:
--
--   1. Calls the booking rule without a model, with a fixed "today".
--   2. Registers the tool PARTNER_BOOK_VISIT under the tag partner.
--   3. Creates version 2 of the prompt profile with a booking prompt, activates
--      it and pins the agent to it. The published endpoint uses it at once.
--   4. Prints the profile versions and the pinned agent.
--
-- Repeatable: the tool is updated, and an existing version 2 is updated, not
-- created a second time.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on size unlimited

-- ---------------------------------------------------------------------------
-- Call the booking rule without a model
-- ---------------------------------------------------------------------------
-- p_today is a parameter, so this block fixes it to a Friday. Every date is
-- relative to the Monday of this week, so the result is the same on any day.
-- Asset 1001 is the press FX-PRESS-01 of Ferrolux (customer 1).
declare
  l_friday date;

  procedure try(
    p_label  in varchar2
  , p_date   in date
  , p_friday in date
  ) is
  begin
    sys.dbms_output.put_line(
      rpad(p_label, 28) || to_char(p_date, 'Dy YYYY-MM-DD') || '  ->  '
      || nvl(partner_desk_pkg.check_visit(1001, p_date, 1, p_today => p_friday), 'allowed'));
  end try;
begin
  l_friday := trunc(sysdate, 'IW') + 4;
  sys.dbms_output.put_line('Today is ' || to_char(l_friday, 'Dy YYYY-MM-DD') || ' (fixed).');
  try('Monday, one working day', l_friday + 3, l_friday);
  try('Tuesday, two working days', l_friday + 4, l_friday);

  <<coverage>>
  for r in ( select c.ends_on
               from sc_assets a
               join sc_contracts c on c.id = a.contract_id
              where a.id = 1001 ) loop
    try('The day after the contract', r.ends_on + 1, l_friday);
  end loop coverage;
end;
/

-- ---------------------------------------------------------------------------
-- Register the booking tool
-- ---------------------------------------------------------------------------
declare
  l_tool_id number;
begin
  l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'PARTNER_BOOK_VISIT'
  , p_description   => 'Ask for a service visit on one machine of the calling partner. '
                    || 'The visit is a request that a planner confirms. The database '
                    || 'refuses a request that breaks the rules, and the refusal '
                    || 'has a message that explains why.'
  , p_function_call => 'return partner_desk_pkg.book_visit(:ARGUMENTS);'
  , p_json_schema   => json_object_t('{
      "type": "object",
      "properties": {
        "asset_tag": {
          "type": "string",
          "description": "The tag of the machine, for example FX-PRESS-01"
        },
        "visit_date": {
          "type": "string",
          "description": "The wanted date of the visit, as YYYY-MM-DD"
        }
      },
      "required": ["asset_tag", "visit_date"]
    }')
  , p_tags          => apex_t_varchar2('partner')
  );
  sys.dbms_output.put_line('PARTNER_BOOK_VISIT  id=' || l_tool_id);

  commit;
end;
/

-- ---------------------------------------------------------------------------
-- Create version 2 of the prompt profile
-- ---------------------------------------------------------------------------
-- create_new_version copies version 1 as a draft. The copy keeps the tag
-- partner, so the agent offers PARTNER_BOOK_VISIT. Version 1 stays active, as
-- the version to go back to. The agent is then pinned to version 2: the agent
-- row, not the endpoint, names the profile version. An agent with no pinned
-- version runs the latest active one, so every new active version would reach
-- all partners at once. A pin makes each change a deliberate update_agent call.
declare
  l_new_id   number;
  l_exists   pls_integer;
  l_profile  uc_ai_prompt_profiles%rowtype;

  c_system_prompt constant varchar2(2000 char) :=
'You are the service desk of a field-service company. You answer questions of a
partner company about its machines under service contract, and you take requests
for service visits.

Rules you must follow:
- Never guess a fact. Read it with a tool.
- Your tools show the machines of the partner that is calling. If a tool says that
  there is no such machine or that the client is unknown, say so. Do not try to
  find the answer in another way.
- To request a visit you need the tag of the machine and a date as YYYY-MM-DD.
  If the partner gives no date, or a date that is not clear, ask for it. Never
  guess a date.
- The database decides whether a visit is allowed. You only ask. When a tool
  refuses, tell the partner the reason in plain words.
- A visit is a request until a planner confirms it. Do not say that a visit is
  confirmed.
- Keep answers short and in plain text.';
begin
  select count(*)
    into l_exists
    from uc_ai_prompt_profiles
   where code = 'PARTNER_DESK_PROFILE'
     and version = 2
     and rownum = 1;

  if l_exists = 0 then
    l_new_id := uc_ai_prompt_profiles_api.create_new_version(
      p_code           => 'PARTNER_DESK_PROFILE'
    , p_source_version => 1
    , p_new_version    => 2
    );
    sys.dbms_output.put_line('Prompt profile PARTNER_DESK_PROFILE version 2 created, id=' || l_new_id);
  end if;

  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile('PARTNER_DESK_PROFILE', 2);
  l_profile.system_prompt_template := c_system_prompt;
  uc_ai_prompt_profiles_api.update_prompt_profile(p_profile => l_profile);

  uc_ai_prompt_profiles_api.change_status(
    p_code    => 'PARTNER_DESK_PROFILE'
  , p_version => 2
  , p_status  => uc_ai_prompt_profiles_api.c_status_active
  );

  -- Pin the agent to version 2. To go back, call this again with version 1.
  <<agent_row>>
  for r in ( select a.id
               from uc_ai_agents a
              where a.code = 'partner_desk'
                and a.version = 1 ) loop
    uc_ai_agents_api.update_agent(
      p_id                     => r.id
    , p_prompt_profile_version => 2
    );
  end loop agent_row;

  commit;
  sys.dbms_output.put_line('Version 2 is active and the agent uses it. The endpoint answers with it from now on.');
end;
/

-- ---------------------------------------------------------------------------
-- Verification — both profile versions, the pinned agent, and the tools
-- ---------------------------------------------------------------------------
set feedback off
prompt

select p.code
     , p.version
     , p.status
     , json_value(p.model_config_json, '$.g_tool_tags[0]') as tool_tag
     , length(p.system_prompt_template) as prompt_chars
  from uc_ai_prompt_profiles p
 where p.code = 'PARTNER_DESK_PROFILE'
 order by p.version;

prompt The agent and the profile version it runs:

select a.code
     , a.version
     , a.status
     , a.prompt_profile_code
     , a.prompt_profile_version
  from uc_ai_agents a
 where a.code = 'partner_desk';

prompt Tools with the tag partner:

select t.code
  from uc_ai_tools t
  join uc_ai_tool_tags tg on tg.tool_id = t.id
 where lower(tg.tag_name) = 'partner'
 order by t.code;

set feedback on
