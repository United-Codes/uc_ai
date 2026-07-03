# Workflow Agents — Sequential, Conditional, and Loop

Workflows execute agents in a deterministic structure defined as JSON in `p_workflow_definition` on a `uc_ai_agents_api.c_type_workflow` agent. Steps reference profile agents by `agent_code`; each step's output is stored under its `output_key` and available to later steps via `{$.steps.<output_key>}`.

Workflow type constants in `uc_ai_agents_api`: `c_workflow_sequential`, `c_workflow_conditional`, `c_workflow_parallel`, `c_workflow_loop` (the JSON `workflow_type` values `"sequential"`, `"conditional"`, `"parallel"`, `"loop"`).

## Sequential workflow

```sql
declare
  l_workflow_id  number;
  l_result       json_object_t;
  l_workflow_def clob;
begin
  l_workflow_def := '{
    "workflow_type": "sequential",
    "steps": [
      {
        "agent_code": "math_agent",
        "input_mapping": {
          "question": "{$.input.question}"
        },
        "output_key": "step1_result"
      },
      {
        "agent_code": "summarizer_agent",
        "input_mapping": {
          "text": "{$.steps.step1_result}"
        },
        "output_key": "step2_result"
      }
    ]
  }';

  l_workflow_id := uc_ai_agents_api.create_agent(
    p_code                => 'math_summary_pipeline'
  , p_description         => 'Solves a math question then summarizes the answer'
  , p_agent_type          => uc_ai_agents_api.c_type_workflow
  , p_workflow_definition => l_workflow_def
  , p_status              => uc_ai_agents_api.c_status_active
  );

  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'math_summary_pipeline'
  , p_input_parameters => json_object_t('{"question": "What is 7 + 8?"}')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  );

  dbms_output.put_line('Result: ' || l_result.get_clob('final_message'));
end;
/
```

How it works: `math_agent` receives `{"question": ...}` from the input; its output lands under `step1_result`; `summarizer_agent` receives it as `text`. The final result is the last step's output.

### Helper for simple pipelines

When every step just chains agent codes in order, skip the JSON:

```sql
function create_sequential_workflow(
  p_code        in uc_ai_agents.code%type,
  p_description in uc_ai_agents.description%type,
  p_agent_steps in json_array_t,
  p_status      in uc_ai_agents.status%type default c_status_draft
) return uc_ai_agents.id%type;
```

A `create_parallel_workflow(p_code, p_description, p_agent_steps, p_aggregation_strategy default 'merge', p_status)` helper exists too (aggregation strategies: `'merge'`, `'array'`, `'first'`).

## Conditional workflow

Like sequential, but each step may carry a `condition` — a string containing a **PL/SQL boolean expression**. `{$.path}` placeholders are resolved to plain text first, then the expression is evaluated, so quote them when comparing strings:

```json
{
  "workflow_type": "conditional",
  "steps": [
    {
      "agent_code": "geography_agent",
      "condition": "'{$.input.category}' = 'geography'",
      "input_mapping": { "question": "{$.input.text}" },
      "output_key": "geo_result"
    },
    {
      "agent_code": "summarizer_agent",
      "condition": "'{$.input.category}' = 'summary'",
      "input_mapping": { "text": "{$.input.text}" },
      "output_key": "sum_result"
    }
  ]
}
```

- Steps without a `condition` always run; skipped steps produce no output.
- A common pattern: an unconditional classifier step with a response schema, then steps gated on its structured output — `"condition": "'{$.steps.classification.category}' = 'complaint'"`.
- Numeric comparisons and function calls work too: `"{$.steps.classification.confidence} >= 0.8"`.
- If every condition is false, the workflow completes successfully but with no `final_message` and `_workflow_iterations` = 0.

## Loop workflow

Loop steps repeat until `exit_condition` is true or `max_iterations` is reached. `pre_steps` run once before the loop, `post_steps` once after, and `final_message` selects which step output becomes the overall result:

```sql
declare
  l_workflow_id  number;
  l_result       json_object_t;
  l_workflow_def clob;
begin
  l_workflow_def := '{
    "workflow_type": "loop",
    "pre_steps": [
      {
        "agent_code": "haiku_creator_agent",
        "input_mapping": {
          "topic": "{$.input.topic}"
        },
        "output_key": "current_haiku"
      }
    ],
    "steps": [
      {
        "agent_code": "haiku_rater_agent",
        "input_mapping": {
          "haiku": "{$.steps.current_haiku}",
          "topic": "{$.input.topic}"
        },
        "output_key": "haiku_rating"
      },
      {
        "agent_code": "haiku_improver_agent",
        "input_mapping": {
          "topic": "{$.input.topic}",
          "feedback": "{$.steps.haiku_rating.rating_feedback}",
          "haiku": "{$.steps.current_haiku}"
        },
        "output_key": "current_haiku"
      }
    ],
    "post_steps": [
      {
        "agent_code": "haiku_translator_agent",
        "input_mapping": {
          "language": "german",
          "haiku": "{$.steps.current_haiku}"
        },
        "output_key": "translated_haiku"
      }
    ],
    "loop_config": {
      "max_iterations": 3,
      "exit_condition": "{$.steps.haiku_rating.quality} >= 8"
    },
    "final_message": "{$.steps.translated_haiku}"
  }';

  l_workflow_id := uc_ai_agents_api.create_agent(
    p_code                => 'haiku_refinement'
  , p_description         => 'Creates, refines, and translates a haiku'
  , p_agent_type          => uc_ai_agents_api.c_type_workflow
  , p_workflow_definition => l_workflow_def
  , p_max_iterations      => 3
  , p_status              => uc_ai_agents_api.c_status_active
  );

  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code       => 'haiku_refinement'
  , p_input_parameters => json_object_t('{"topic": "Star Wars"}')
  , p_session_id       => uc_ai_agents_api.generate_session_id
  );

  dbms_output.put_line('Final haiku: ' || l_result.get_clob('final_message'));
end;
/
```

Note how the improver writes back to `output_key: "current_haiku"` — later iterations overwrite the state key, so `{$.steps.current_haiku}` always holds the latest version.

### Exit conditions need structured output

`exit_condition` is the same PL/SQL-expression syntax as step conditions. It typically reads a structured field, so the deciding agent's prompt profile must have a response schema (see the `uc-ai-structured-output` skill):

```sql
declare
  l_profile_id number;
  l_schema clob := '{
    "type": "object",
    "properties": {
      "quality": {
        "type": "number",
        "minimum": 1,
        "maximum": 10,
        "description": "Quality rating from 1 to 10"
      },
      "rating_feedback": {
        "type": "string",
        "description": "One-sentence feedback for improvement"
      }
    },
    "required": ["quality", "rating_feedback"]
  }';
begin
  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'haiku_rater_profile'
  , p_description            => 'Rates haikus on a 1-10 scale'
  , p_system_prompt_template => 'You are a haiku critic. Rate haikus based on form, imagery, and emotional impact.'
  , p_user_prompt_template   => 'Rate this haiku about "{topic}": {haiku}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_4o_mini
  , p_response_schema        => l_schema
  , p_status                 => uc_ai_prompt_profiles_api.c_status_active
  );

  commit;
end;
/
```

The workflow then references the fields directly: `"exit_condition": "{$.steps.haiku_rating.quality} >= 8"`.

### Loop without pre/post steps

Use the extended `optional` mapping so the first iteration works before feedback exists:

```json
{
  "workflow_type": "loop",
  "steps": [
    {
      "agent_code": "haiku_creator_agent",
      "input_mapping": {
        "topic": "{$.input.topic}",
        "feedback": {
          "path": "{$.steps.haiku_rating.rating_feedback}",
          "optional": true
        }
      },
      "output_key": "haiku_result"
    },
    {
      "agent_code": "haiku_rater_agent",
      "input_mapping": {
        "haiku": "{$.steps.haiku_result}",
        "topic": "{$.input.topic}"
      },
      "output_key": "haiku_rating"
    }
  ],
  "loop_config": {
    "max_iterations": 3,
    "exit_condition": "{$.steps.haiku_rating.quality} >= 8"
  }
}
```

In iteration 1 the `feedback` key is simply omitted; from iteration 2 onwards the rater's feedback flows to the creator.

## Validation and debugging

- `uc_ai_agents_api.validate_workflow_definition(p_workflow_definition)` returns a `t_validation_result` record (`is_valid`, `error_reason`) — useful before creating the agent.
- Each step execution is its own row in `uc_ai_agent_executions` (same `session_id`, linked by `parent_execution_id`), so you can see per-step tokens and failures. The workflow result also carries `_workflow_iterations`.

Full guide: https://www.united-codes.com/products/uc-ai/docs/guides/multi-agent-systems/workflows/
