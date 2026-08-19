---
name: uc-ai-multi-agent
description: Use when building multi-agent AI systems in Oracle PL/SQL with UC AI — creating agents with uc_ai_agents_api.create_agent, running them via execute_agent with session IDs, sequential/loop/conditional workflow definitions, orchestrator agents that delegate to sub-agents as tools, round-robin or AI-moderated agent conversations, handoff agents with transfer tools and can_transfer_to graphs, input mapping ({$.input.*}, {$.steps.*}), follow-up messages, conversation sessions with titles and feedback, and debugging via uc_ai_agent_executions, uc_ai_agent_sessions and uc_ai_agent_messages.
---

# UC AI Multi-Agent Systems

UC AI lets you compose specialized AI agents into workflows, orchestrators, and conversations — all defined in the database and executed through one API: `uc_ai_agents_api.execute_agent()`.

**Reach for agents deliberately.** A single `uc_ai.generate_text()` call with tools is often enough (see the `uc-ai-quickstart` and `uc-ai-tools` skills). Agents add value when you need execution tracking (tokens, timing, audit trail), session grouping across calls, or composition of multiple AI steps.

## Choosing a pattern

| Pattern | Use when... | Example |
|---------|-------------|---------|
| **Profile agent** | A single AI call with execution tracking and composability | Classify a support ticket, answer a question |
| **Sequential workflow** | Steps must run in a fixed order, each building on the previous | Classify text, then summarize based on category |
| **Loop workflow** | Iterative refinement until a quality threshold is met | Generate a haiku, rate it, improve it, repeat |
| **Orchestrator** | A central AI should decide which agents to call and in what order | Travel planner delegating to calendar, flight, and hotel agents |
| **Handoff** | Agents pass control to each other based on their own output | Support triage agent handing off to a technical or sales specialist |
| **Round-robin conversation** | Multiple perspectives should take turns in a fixed order | Brainstormer, critic, and synthesizer collaborate on a plan |
| **AI-driven conversation** | A moderator should dynamically decide who speaks next | Panel discussion where the moderator picks the most relevant expert |

Deep dives sit next to this file: **workflows.md** (sequential/conditional/loop JSON), **orchestrator.md** (delegation config), **conversations.md** (round-robin and AI-driven dialogue).

## The building block: profile agents

Every AI-calling agent wraps a **prompt profile** that defines its instructions, provider, and model (see the `uc-ai-prompt-profiles` skill or https://www.united-codes.com/products/uc-ai/docs/guides/prompt-profiles/). Higher-level patterns (workflows, orchestrators, conversations) compose profile agents by their `agent_code`.

The `create_agent` signature (from `uc_ai_agents_api`):

```sql
function create_agent(
  p_code                   in uc_ai_agents.code%type,
  p_description            in uc_ai_agents.description%type,
  p_agent_type             in uc_ai_agents.agent_type%type,
  p_prompt_profile_code    in uc_ai_agents.prompt_profile_code%type default null,
  p_prompt_profile_version in uc_ai_agents.prompt_profile_version%type default null,
  p_workflow_definition    in uc_ai_agents.workflow_definition%type default null,
  p_orchestration_config   in uc_ai_agents.orchestration_config%type default null,
  p_input_schema           in uc_ai_agents.input_schema%type default null,
  p_output_schema          in uc_ai_agents.output_schema%type default null,
  p_timeout_seconds        in uc_ai_agents.timeout_seconds%type default null,
  p_max_iterations         in uc_ai_agents.max_iterations%type default null,
  p_max_history_messages   in uc_ai_agents.max_history_messages%type default null,
  p_version                in uc_ai_agents.version%type default 1,
  p_status                 in uc_ai_agents.status%type default c_status_draft
) return uc_ai_agents.id%type;
```

Agent type constants: `uc_ai_agents_api.c_type_profile`, `c_type_workflow`, `c_type_orchestrator`, `c_type_handoff`, `c_type_conversation`. Status constants: `c_status_draft`, `c_status_active`, `c_status_archived`. **Always use these constants, never string literals.**

Complete example — profile + agent, activated:

```sql
declare
  l_profile_id number;
  l_agent_id   number;
begin
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'geo_assistant'
  , p_description            => 'Answers geography questions'
  , p_system_prompt_template => 'You are a geography assistant. Answer in one short sentence.'
  , p_user_prompt_template   => '{question}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_4o_mini
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  l_agent_id := uc_ai_agents_api.create_agent(
    p_code                => 'geo_agent'
  , p_description         => 'Answers geography questions in one sentence'
  , p_agent_type          => uc_ai_agents_api.c_type_profile
  , p_prompt_profile_code => 'geo_assistant'
  , p_status              => uc_ai_agents_api.c_status_active
  );

  commit;
end;
/
```

The agent uses the latest active version of the profile unless pinned with `p_prompt_profile_version`. Agents are versioned too: `create_new_version(p_code, p_source_version)` copies an agent, `change_status(...)` activates or archives.

## Executing agents

All agent types share the same API:

```sql
function execute_agent(
  p_agent_code        in uc_ai_agents.code%type,
  p_agent_version     in uc_ai_agents.version%type default null,
  p_input_parameters  in json_object_t default null,
  p_follow_up_message in clob default null,
  p_session_id        in varchar2 default null,
  p_parent_exec_id    in uc_ai_agent_executions.id%type default null,
  p_response_schema   in json_object_t default null
) return json_object_t;
```

(An overload taking `p_agent_id` instead of code/version exists as well.)

```sql
declare
  l_result     json_object_t;
  l_session_id varchar2(100);
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_session_id := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'geo_agent'
  , p_input_parameters => json_object_t('{"question": "What is the capital of France?"}')
  , p_session_id       => l_session_id
  );

  dbms_output.put_line('Answer: ' || l_result.get_clob('final_message'));
end;
/
```

- `p_input_parameters` keys map to `{placeholder}` names in the prompt profile templates (for workflows/conversations, they feed `{$.input.*}` mappings).
- `p_session_id` groups related executions — one workflow run with three steps produces multiple rows in `uc_ai_agent_executions` under the same session. Generate one with `uc_ai_agents_api.generate_session_id` (SYS_GUID-based).
- The result is a `json_object_t` in the `generate_text` shape: `final_message` (clob), `messages`, `usage`, `finish_reason` — plus pattern-specific keys (workflows add `_workflow_iterations`, orchestrators expose `tool_calls_count`, handoffs add `handoff_count` and `conversation_history`).
- `p_response_schema` validates the response against a JSON schema (profile agents only).

### Follow-up messages (multi-turn)

Profile and orchestrator agents support conversation continuation. Pass `p_follow_up_message` **with the same `p_session_id`** — the previous conversation is loaded from the session and your message is appended:

```sql
declare
  l_result     json_object_t;
  l_session_id varchar2(100);
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_session_id := uc_ai_agents_api.generate_session_id;

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'geo_agent'
  , p_input_parameters => json_object_t('{"question": "What are the 5 largest cities in Europe?"}')
  , p_session_id       => l_session_id
  );

  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code        => 'geo_agent'
  , p_follow_up_message => 'Which of those have the best public transport?'
  , p_session_id        => l_session_id
  );

  dbms_output.put_line(l_result.get_clob('final_message'));
end;
/
```

To cap token usage in long conversations, set `p_max_history_messages` on the agent — the system then keeps the system message plus the most recent N messages.

## Handoff agents

`c_type_handoff` transfers control between agents with **tools**. The engine registers a temporary `transfer_to_<agent>` tool for each allowed target. The AI transfers by calling one with a context summary, and the target agent answers the user directly.

```sql
l_config := '{
  "initial_agent_code": "support_triage",
  "handoff_agents": [
    {"agent_code": "support_triage",   "description": "Triage and general support"},
    {"agent_code": "support_product",  "description": "Product specs, prices, availability"},
    {"agent_code": "support_shipping", "description": "Shipping options, costs, delivery times"}
  ],
  "max_handoffs": 3
}';

l_id := uc_ai_agents_api.create_agent(
  p_code                 => 'customer_support'
, p_description          => 'Customer support entry point'
, p_agent_type           => uc_ai_agents_api.c_type_handoff
, p_orchestration_config => l_config
, p_status               => uc_ai_agents_api.c_status_active
);
```

**Restricting the transfer graph.** Add `can_transfer_to` to an entry to limit its outgoing edges. Use it for hierarchies — triage reaches product support, and only product support reaches the product technician:

```json
{"agent_code": "support_triage", "description": "...", "can_transfer_to": ["support_product", "support_shipping"]}
```

Without `can_transfer_to`, every agent may transfer to every other one (full mesh).

**Multi-turn (sticky agent).** Handoff agents accept `p_follow_up_message`. The follow-up turn resumes with the agent that answered the previous turn and continues its history. It keeps its transfer tools, so it can hand off again when the topic changes.

**Results.** The result object carries `final_agent_code`, `handoff_count`, `handoff_trail`, and `max_handoffs_reached`. The hop at `max_handoffs` runs without transfer tools and must answer — a graceful cap, not an error. Transfer tool calls are persisted in the session message log.

## Input mapping cheat sheet

Input mappings define how data flows between agents inside workflow definitions and orchestration configs. Paths are wrapped in `{...}`:

| Path | Description |
|------|-------------|
| `{$.input.<param>}` | Original input parameters passed to `execute_agent` |
| `{$.steps.<output_key>}` | Full output of a previous step |
| `{$.steps.<output_key>.<field>}` | Field from a step's structured (JSON schema) output |
| `{$.chat_history}` | Conversation history (conversation agents) |
| `{$.agent_description}` | The current agent's description (conversation agents) |
| `{$.available_agents}` | Agent list with descriptions (conversation moderator only) |
| `{$.moderator_rationale}` | Why this agent was picked (AI-driven conversation participants) |

Simple syntax maps directly; extended syntax handles missing values:

```json
{
  "input_mapping": {
    "question": "{$.input.question}",
    "context": "{$.steps.step1_result}",
    "feedback": { "path": "{$.steps.reviewer.feedback}", "optional": true },
    "temperature": { "path": "{$.input.temperature}", "default": "0.7" }
  }
}
```

`optional: true` omits the key when the path doesn't resolve (e.g. first loop iteration); `default` substitutes a fallback value.

## Debugging: session tracking

Every execution is a row in `uc_ai_agent_executions` — query by session:

```sql
select ae.id, a.code as agent_code, ae.status, ae.iteration_count,
       ae.tool_calls_count, ae.total_input_tokens, ae.total_output_tokens,
       ae.started_at, ae.completed_at, ae.error_message
  from uc_ai_agent_executions ae
  join uc_ai_agents a on a.id = ae.agent_id
 where ae.session_id = :session_id
 order by ae.started_at;
```

Nested calls (workflow steps, orchestrator delegates) each get their own row linked via `parent_execution_id`, so you can see exactly which step burned tokens or failed. Rows also capture caller context (`created_by`, `apex_user`, `apex_app_id`, `module`, full `env_context` JSON).

Rows also carry `audience` — the caller class at the start of the run: `public` (anonymous APEX visitor), `authenticated` (logged-in APEX user), or `db` (database or job session).

Programmatic access: `uc_ai_agents_api.get_execution_details(p_execution_id)` returns a `json_object_t` (status, token counts, timing, error_message, caller context); `get_execution_history(...)` returns a filterable `sys_refcursor`.

### Conversation sessions and transcript

Two more tables sit above the executions:

- **`uc_ai_agent_sessions`** — one row per conversation. Holds `title`, `feedback_rating`/`feedback_comment`/`feedback_at`, `status` of the latest turn, `turn_count`, `message_count`, summed `total_input_tokens`/`total_output_tokens`, and the caller context of the opening turn. Each execution records only its own LLM tokens, so the session totals never double count nested runs. Read it with `uc_ai_agents_api.list_sessions(...)` — a ready-made conversation list.
- **`uc_ai_agent_messages`** — the normalized, untrimmed transcript: one row per message content item, ordered by `seq`, with `agent_code` attribution per message. History-window trimming only governs what is sent to the LLM, so the persisted record stays complete. Read it with `uc_ai_agents_api.get_session_messages(p_session_id)`.

Your front end owns the title and the rating; the engine never sets them:

```sql
uc_ai_agents_api.set_session_title(:session_id, 'Invoice question from March', :APP_USER);
uc_ai_agents_api.set_session_feedback(:session_id, 'up', 'Answered in one turn.', :APP_USER);
```

A second call overwrites, so these also rename and change a verdict. A null rating withdraws the feedback. `p_created_by` restricts the write to the user who opened the session — pass `null` for a session opened by a background job, whose header records the DB user.

## Best practices

- **Always set limits**: `max_turns` (conversations), `max_iterations` / `p_max_iterations` (loops), `max_delegations` (orchestrators), `max_handoffs` (handoffs). Runaway agents burn tokens fast.
- **Structured output for decision points**: exit conditions and routing read structured fields (`{$.steps.rating.quality} >= 8`) — give the deciding agent a `p_response_schema` on its prompt profile.
- **Match model to role**: capable models for orchestrators and moderators (they reason about delegation); fast/cheap models for leaf agents with narrow tasks.
- **Descriptive agent descriptions**: orchestrators and moderators pick agents by their `p_description` — write them like tool descriptions.
- **Test with small limits first**: validate the flow with `max_turns: 2` or `max_iterations: 2` before raising limits.
- **Start simple**: begin with a profile agent, compose later — `execute_agent` works the same for every agent type, so swapping a profile agent for a workflow needs no caller changes.

## Pitfalls

- **Agents default to `draft` status.** `execute_agent` resolves the latest **active** version — create with `p_status => uc_ai_agents_api.c_status_active` or call `change_status` afterwards.
- **`p_follow_up_message` requires `p_session_id`** and a previous completed execution for that session and agent; otherwise an error is raised. Only profile and orchestrator agents support follow-ups.
- **Referenced agent codes are validated.** Workflow/orchestration configs referencing nonexistent `agent_code` values fail validation; deleting an agent referenced by others raises an error.
- **API keys still apply.** Agent execution ultimately calls providers — set up `uc_ai_get_key` or web credentials as in the `uc-ai-quickstart` skill before executing.
- **Conversation cost multiplies**: a 3-agent round-robin with `max_turns: 5` is up to 15 AI calls.
- **Handoff targets must be active profile agents.** `create_agent` validates every `agent_code` in `handoff_agents`. A draft or missing target fails validation.

## Full documentation

- Multi-agent overview: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/
- Profile agents: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/profile-agents/
- Workflows: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/workflows/
- Orchestrator: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/orchestrator/
- Conversations: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/conversations/
- Handoff: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/handoff/
- Agentic AI concepts: https://www.united-codes.com/products/uc-ai/docs/guides/agentic-ai/
