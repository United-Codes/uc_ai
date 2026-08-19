# Orchestrator Agents — Autonomous Delegation

An orchestrator is a central AI agent that autonomously decides which specialized agents to call, in what order, and with what parameters. It is created with `p_agent_type => uc_ai_agents_api.c_type_orchestrator` and a JSON `p_orchestration_config`.

## How it works

1. UC AI registers each delegate agent as a **temporary tool** for the orchestrator's LLM call
2. The orchestrator's prompt profile provides the coordination instructions
3. The LLM decides which agents to call (as tool calls); each delegation executes the referenced agent and returns its result
4. The orchestrator synthesizes the results into a final answer
5. Temporary tools are cleaned up after execution

Two things drive delegation quality:

- **The delegate's `p_description`** — this is the tool description the orchestrator LLM sees when deciding which agent to call. Write it like a good tool description: what the agent does and when to call it.
- **The delegate's `p_input_schema`** — a JSON schema defining the parameters the orchestrator passes. Clear `description` fields help the LLM pass the right values.

## Config reference

| Field | Type | Description |
|-------|------|-------------|
| `pattern_type` | String | Must be `"orchestrator"` |
| `orchestrator_profile_code` | String | Prompt profile code for the orchestrator AI |
| `delegate_agents` | Array | List of agent codes the orchestrator can call |
| `max_delegations` | Number | Maximum number of agent calls allowed |

## Example: travel planner

An orchestrator coordinating calendar, flight, and hotel agents. (In real life the delegates would query external data; here the data is hardcoded in the system prompts for simplicity.)

### Step 1: prompt profiles

```sql
declare
  l_profile_id number;
begin
  -- calendar agent: knows the user's schedule
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'calendar_agent_profile'
  , p_description            => 'Provides calendar and scheduling information'
  , p_system_prompt_template => 'You have access to the users calendar.
Schedule:
- Monday 12.01: 8-11 AM Board Meeting (New York, non-reschedulable), 1-2 PM team lunch
- Tuesday 13.01: 9 AM-12 PM Tech Conference (San Francisco, mandatory)
- Wednesday 14.01: Free all day
- Thursday 15.01: Free until 3 PM, 3-5 PM client call (remote, mandatory)
Note: User is in New York, needs ~6 hours for cross-country travel to SF.
Answer shortly and precisely.'
  , p_user_prompt_template   => 'Calendar query: {prompt}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_4o_mini
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  -- flight booking agent: knows available flights
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'flight_booking_agent_profile'
  , p_description            => 'Provides flight booking options'
  , p_system_prompt_template => 'You are a flight booking assistant.
Available flights JFK to SFO:
1. AA123: 12 PM-3 PM, $450, Economy, American Airlines
2. UA456: 2 PM-5 PM, $385, Economy, aisle, United Airlines
3. DL789: 5 PM-8 PM, $520, Business, Delta
4. B6999: 7 PM-10 PM, $340, Economy, Budget Air
Return flights available 2 hours later same day.
Return 3 best options based on preferences. No additional text.'
  , p_user_prompt_template   => 'Flight search: {prompt}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_4o_mini
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  -- hotel booking agent: knows available hotels
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'hotel_booking_agent_profile'
  , p_description            => 'Provides hotel accommodation options'
  , p_system_prompt_template => 'You are a hotel booking assistant.
Available hotels near SF Tech Conference:
1. Grand Hyatt: 0.2 mi, $320/night, 4.5 stars
2. Holiday Inn: 0.8 mi, $180/night, 3.8 stars
3. Marriott Marquis: 0.5 mi, $280/night, 4.3 stars
4. Airport Hotel Express: 15 mi, $120/night, 3.5 stars
Return 3 best options based on preferences. No additional text.'
  , p_user_prompt_template   => 'Hotel search: {prompt}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_4o_mini
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  -- orchestrator: coordinates the other agents (use a more capable model here)
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'travel_planner_orchestrator'
  , p_description            => 'Orchestrates travel planning'
  , p_system_prompt_template => 'You are a travel planning coordinator.
You have access to calendar, flight, and hotel booking agents.
First check the calendar for constraints, then find flights and hotels that fit.
Provide a recommended travel plan with reasoning.'
  , p_user_prompt_template   => '{prompt}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_5_mini
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  commit;
end;
/
```

### Step 2: delegate agents with input schemas

```sql
declare
  l_agent_id     number;
  l_input_schema json_object_t;
begin
  l_input_schema := json_object_t('{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
      "prompt": {
        "type": "string",
        "description": "The query or context for the agent"
      }
    },
    "required": ["prompt"]
  }');

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'calendar_agent'
  , p_description         => 'Provides calendar and scheduling information. Call this to check availability and scheduling constraints.'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'calendar_agent_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  , p_input_schema        => l_input_schema.to_clob
  );

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'flight_booking_agent'
  , p_description         => 'Provides flight booking options between cities. Call this to search for available flights.'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'flight_booking_agent_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  , p_input_schema        => l_input_schema.to_clob
  );

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'hotel_booking_agent'
  , p_description         => 'Provides hotel accommodation options near destinations. Call this to search for hotels.'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'hotel_booking_agent_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  , p_input_schema        => l_input_schema.to_clob
  );
end;
/
```

### Step 3: the orchestrator agent

```sql
declare
  l_orchestrator_id number;
  l_orch_config     clob;
begin
  l_orch_config := '{
    "pattern_type": "orchestrator",
    "orchestrator_profile_code": "travel_planner_orchestrator",
    "delegate_agents": [
      "calendar_agent",
      "flight_booking_agent",
      "hotel_booking_agent"
    ],
    "max_delegations": 8
  }';

  l_orchestrator_id := uc_ai_agents_api.create_agent(
    p_code                 => 'travel_planner'
  , p_description          => 'Plans travel by coordinating calendar, flights, and hotels'
  , p_agent_type           => uc_ai_agents_api.c_type_orchestrator
  , p_orchestration_config => l_orch_config
  , p_status               => uc_ai_agents_api.c_status_active
  );
end;
/
```

### Step 4: execute

```sql
declare
  l_result json_object_t;
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'travel_planner'
  , p_input_parameters => json_object_t('{
      "prompt": "I need to travel from New York to San Francisco for a tech conference on Tuesday. I have a board meeting Monday until 11 AM."
    }')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  );

  dbms_output.put_line('Plan: ' || l_result.get_clob('final_message'));
  dbms_output.put_line('Agents called: ' || l_result.get_number('tool_calls_count'));
end;
/
```

The orchestrator autonomously checks the calendar, searches flights that fit, finds hotels near the venue, and synthesizes a plan. Each delegate execution is tracked as its own row in `uc_ai_agent_executions` under the same session.

## Follow-up messages

Orchestrators support conversation continuation via `p_follow_up_message` (with the same `p_session_id`). On each follow-up the delegates are re-registered as temporary tools, and the full history — including previous tool calls and results — is sent to the LLM:

```sql
l_result := uc_ai_agents_api.execute_agent(
  p_agent_code        => 'travel_planner'
, p_follow_up_message => 'Actually, I prefer business class. Can you find better flight options?'
, p_session_id        => l_session_id
);
```

## Tips

- **Give the orchestrator a plan**: describe the delegation strategy in its system prompt ("First check calendar constraints, then search flights, then hotels").
- **Limit delegations**: set `max_delegations` high enough to call all relevant agents, low enough to stop loops.
- **Structured final answers**: add a response schema to the orchestrator's prompt profile if you need a parseable result.
- **Capable model for the orchestrator, cheap models for delegates** — the orchestrator reasons about coordination; delegates have narrow tasks.
- **Validate first**: `uc_ai_agents_api.validate_orchestration_config(p_orchestration_config)` returns `is_valid`/`error_reason` before you create the agent.

Full guide: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/orchestrator/
