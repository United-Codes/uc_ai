# Conversation Agents — Multi-Agent Dialogue

Conversation agents let multiple profile agents collaborate in a shared chat history. Created with `p_agent_type => uc_ai_agents_api.c_type_conversation` and a JSON `p_orchestration_config`.

Two modes (constants in `uc_ai_agents_api`):

| Mode | Constant | Who speaks next |
|------|----------|-----------------|
| Round-robin | `c_conversation_round_robin` (`'round_robin'`) | Fixed order from the `agents` array |
| AI-driven | `c_conversation_ai_driven` (`'ai_driven'`) | A moderator agent decides each turn |

## Config reference

| Field | Type | Description |
|-------|------|-------------|
| `pattern_type` | String | Must be `"conversation"` |
| `conversation_mode` | String | `"round_robin"` or `"ai_driven"` |
| `agents` | Array | Participant agents with their input mappings |
| `max_turns` | Number | Maximum conversation turns |
| `termination_condition` | Object | (Round-robin) when to stop early |
| `moderator_agent` | Object | (AI-driven) moderator agent config |
| `moderator_agent.summary_mapping` | Object | (AI-driven) input mapping for the final summary |

Template variables available in conversation input mappings:

| Variable | Description | Available to |
|----------|-------------|--------------|
| `{$.chat_history}` | Full conversation history | All participants |
| `{$.agent_description}` | The current agent's description | All participants |
| `{$.available_agents}` | List of agents with descriptions | Moderator only |
| `{$.moderator_rationale}` | Why this agent was picked to speak | Participants in AI-driven mode |

## Round-robin example: party planning

A brainstormer proposes ideas, a critic checks feasibility, and a synthesizer merges them into a plan.

### Step 1: prompt profiles for the participants

```sql
declare
  l_profile_id number;
begin
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'party_brainstormer_profile'
  , p_description            => 'Brainstorms creative party ideas'
  , p_system_prompt_template => 'You are Brainstormer. Propose 2-3 creative party ideas based on the task and chat history. Be enthusiastic! Structure: "Idea 1: [desc]. Idea 2: [desc]." Reference recent messages.'
  , p_user_prompt_template   => 'Generate or refine party ideas: {prompt}. Your role: {role}.'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_5_6_luna
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'party_critic_profile'
  , p_description            => 'Critiques party ideas for budget, safety, and feasibility'
  , p_system_prompt_template => 'You are Critic. Analyze previous ideas: check budget, safety, and practical limits. Suggest fixes or reject bad ideas. Structure: "Critique: [idea] is [good/bad because...]. Fix: [suggestion]." Be realistic.'
  , p_user_prompt_template   => 'Chat history: {prompt}. Your role: {role}.'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_5_6_luna
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'party_synthesizer_profile'
  , p_description            => 'Synthesizes ideas into a cohesive party plan with cost estimates'
  , p_system_prompt_template => 'You are Synthesizer. Merge good ideas from history into 1 polished plan. Estimate total cost. Structure: "Combined Plan: 1. [activity] ($X). 2. [food] ($Y). Total: $Z." If you finalize, say "Final Plan: ..."'
  , p_user_prompt_template   => 'Chat history: {prompt}. Your role: {role}.'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_5_6_luna
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  commit;
end;
/
```

### Step 2: profile agents for each participant

```sql
declare
  l_agent_id number;
begin
  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'brainstormer_agent'
  , p_description         => 'Creative brainstormer who proposes party ideas'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'party_brainstormer_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  );

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'critic_agent'
  , p_description         => 'Practical critic who checks feasibility and budget'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'party_critic_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  );

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'synthesizer_agent'
  , p_description         => 'Synthesizer who merges ideas into a final plan'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'party_synthesizer_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  );
end;
/
```

### Step 3: the conversation agent

```sql
declare
  l_conv_id     number;
  l_conv_config clob;
begin
  l_conv_config := '{
    "pattern_type": "conversation",
    "conversation_mode": "round_robin",
    "agents": [
      {
        "agent_code": "brainstormer_agent",
        "input_mapping": {
          "prompt": "{$.chat_history}",
          "role": "{$.agent_description}"
        }
      },
      {
        "agent_code": "critic_agent",
        "input_mapping": {
          "prompt": "{$.chat_history}",
          "role": "{$.agent_description}"
        }
      },
      {
        "agent_code": "synthesizer_agent",
        "input_mapping": {
          "prompt": "{$.chat_history}",
          "role": "{$.agent_description}"
        }
      }
    ],
    "max_turns": 3,
    "termination_condition": {
      "type": "keyword_in_response",
      "keyword": "Final Plan"
    }
  }';

  l_conv_id := uc_ai_agents_api.create_agent(
    p_code                 => 'party_planning_roundrobin'
  , p_description          => 'Party planning with brainstormer, critic, and synthesizer'
  , p_agent_type           => uc_ai_agents_api.c_type_conversation
  , p_orchestration_config => l_conv_config
  , p_max_iterations       => 2
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
    p_agent_code       => 'party_planning_roundrobin'
  , p_input_parameters => json_object_t('{
      "prompt": "Plan a birthday party for a 12 year old who loves pirates and football. Max 14 kids, $200 budget."
    }')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  );

  dbms_output.put_line('Result: ' || l_result.get_clob('final_message'));
end;
/
```

How it works: each turn the agents speak in listed order; every agent receives the full history via `{$.chat_history}` and its role via `{$.agent_description}`. The conversation ends when any response contains `"Final Plan"` (the `termination_condition` keyword) or after `max_turns`.

## AI-driven example: moderated party planning

Reusing the participants above, a moderator agent decides who speaks next and produces the final summary.

### Step 1: moderator profile and agent

```sql
declare
  l_profile_id number;
  l_agent_id   number;
begin
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'party_moderator_profile'
  , p_description            => 'Moderates the party planning conversation'
  , p_system_prompt_template => 'You are the Moderator. Oversee the party planning conversation. Decide who speaks next based on the chat history. If you think there is a solid plan ready, you can finalize the conversation. When done, summarize the final plan for the user.'
  , p_user_prompt_template   => '{prompt}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_5_6_luna
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'moderator_agent'
  , p_description         => 'Moderator who decides which agent speaks next'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'party_moderator_profile'
  , p_status              => uc_ai_agents_api.c_status_active
  );

  commit;
end;
/
```

### Step 2: the AI-driven conversation agent

```sql
declare
  l_conv_id     number;
  l_conv_config clob;
begin
  l_conv_config := '{
    "pattern_type": "conversation",
    "conversation_mode": "ai_driven",
    "moderator_agent": {
      "agent_code": "moderator_agent",
      "input_mapping": {
        "prompt": "Chat history: {$.chat_history} | Available agents: {$.available_agents}"
      },
      "summary_mapping": {
        "prompt": "The conversation was ended. Please outline the final plan for the user. Max 2 sentences. | Chat history: {$.chat_history}"
      }
    },
    "max_turns": 6,
    "agents": [
      {
        "agent_code": "brainstormer_agent",
        "input_mapping": {
          "prompt": "{$.chat_history}",
          "role": "{$.agent_description} | Why you were picked: {$.moderator_rationale}"
        }
      },
      {
        "agent_code": "critic_agent",
        "input_mapping": {
          "prompt": "{$.chat_history}",
          "role": "{$.agent_description} | Why you were picked: {$.moderator_rationale}"
        }
      },
      {
        "agent_code": "synthesizer_agent",
        "input_mapping": {
          "prompt": "{$.chat_history}",
          "role": "{$.agent_description} | Why you were picked: {$.moderator_rationale}"
        }
      }
    ]
  }';

  l_conv_id := uc_ai_agents_api.create_agent(
    p_code                 => 'party_planning_ai_driven'
  , p_description          => 'AI-moderated party planning discussion'
  , p_agent_type           => uc_ai_agents_api.c_type_conversation
  , p_orchestration_config => l_conv_config
  , p_max_iterations       => 1
  , p_status               => uc_ai_agents_api.c_status_active
  );
end;
/
```

Execute exactly like the round-robin agent (`execute_agent` with `p_input_parameters` containing `prompt`).

How it works:

1. Each turn the moderator receives the chat history and the participant list via `{$.available_agents}`
2. It picks who speaks next and provides a rationale
3. The selected agent speaks, receiving the history plus `{$.moderator_rationale}`
4. When the moderator finalizes, `summary_mapping` is used for one last moderator call that produces the final summary
5. The conversation ends when the moderator finalizes or after `max_turns`

## Tips

- **Distinct personalities**: each participant needs a clear role in its system prompt; overlap produces redundant responses.
- **Pass `{$.agent_description}` as context** so an agent knows its role — especially when one prompt template serves multiple roles.
- **Cost scales with turns**: 3 agents with `max_turns: 5` means up to 15 AI calls (plus moderator calls in AI-driven mode).
- **Round-robin termination**: instruct the final agent to emit the termination keyword (e.g. "Final Plan") when the discussion is ready to conclude.
- **Moderator instructions**: in AI-driven mode, explicitly tell the moderator when to finalize, or it will keep going until `max_turns`.
- **Capable moderator, cheap participants**: the moderator makes routing decisions; use a stronger model there if selection quality matters.

Full guide: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/conversations/
