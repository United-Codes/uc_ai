---
name: uc-ai-prompt-profiles
description: Use when managing reusable, versioned AI prompt templates in Oracle PL/SQL with UC AI — uc_ai_prompt_profiles_api.create_prompt_profile, execute_profile with {placeholder} parameters, model_config_json settings, runtime overrides (p_provider_override, p_model_override, p_config_override), create_new_version, and change_status with draft/active/archived lifecycle.
---

# UC AI Prompt Profiles — Versioned Prompt Templates in the Database

Prompt profiles move prompts out of your code and into database tables (`uc_ai_prompt_profiles`). Each profile is identified by a **code**, carries a **version** and a **status** (draft/active/archived), holds system/user prompt templates with `{placeholder}` substitution, and stores the provider, model, model configuration, and an optional structured-output schema alongside the prompt. Update prompts, roll out new versions, and A/B test models — without code changes.

## Creating a profile

```sql
function create_prompt_profile(
  p_code                    in uc_ai_prompt_profiles.code%type,
  p_description             in uc_ai_prompt_profiles.description%type,
  p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
  p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
  p_provider                in uc_ai_prompt_profiles.provider%type,
  p_model                   in uc_ai_prompt_profiles.model%type,
  p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
  p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
  p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null,
  p_version                 in uc_ai_prompt_profiles.version%type default 1,
  p_status                  in uc_ai_prompt_profiles.status%type default c_status_draft
) return uc_ai_prompt_profiles.id%type;
```

Complete example — a support-ticket classifier with a structured-output schema:

```sql
declare
  l_profile_id number;
  l_schema     clob;
begin
  l_schema := '{
    "type": "object",
    "properties": {
      "category": {
        "type": "string",
        "enum": ["bug", "feature", "question", "documentation"]
      },
      "priority": {
        "type": "string",
        "enum": ["low", "medium", "high", "urgent"]
      },
      "summary": {
        "type": "string",
        "description": "Brief summary of the issue"
      }
    },
    "required": ["category", "priority", "summary"]
  }';

  l_profile_id := uc_ai_prompt_profiles_api.create_prompt_profile(
    p_code                   => 'CLASSIFY_ISSUE'
  , p_description            => 'Classifies customer support issues'
  , p_system_prompt_template => 'You are a support ticket classifier. Analyze issues and categorize them accurately.'
  , p_user_prompt_template   => 'Classify this issue: {issue_text}'
  , p_provider               => uc_ai.c_provider_openai
  , p_model                  => uc_ai_openai.c_model_gpt_5_6_luna
  , p_response_schema        => l_schema
  , p_version                => 1
  , p_status                 => uc_ai_prompt_profiles_api.c_status_draft
  );

  -- promote to production
  uc_ai_prompt_profiles_api.change_status(
    p_id     => l_profile_id
  , p_status => uc_ai_prompt_profiles_api.c_status_active
  );

  commit;
end;
/
```

Use provider/model package constants, never string literals; model constants change with releases — check the installed provider package spec.

### Placeholders

- Syntax: `{placeholder_name}` inside the system or user template.
- Names may contain only **alphanumerics and underscores** (`{valid_name_123}`).
- Matching against `p_parameters` keys is **case-insensitive** (`{Country}` matches a parameter `country`).
- Every placeholder must have a parameter — a missing one raises an error (ORA-20506, `Missing parameter for placeholder: {text}`) before any AI call is made. Extra parameters are ignored.

## Executing a profile

Two overloads; both return the same `json_object_t` as `uc_ai.generate_text` (`final_message`, `messages`, `usage`, `finish_reason`, ...):

```sql
function execute_profile(
  p_code              in uc_ai_prompt_profiles.code%type,
  p_version           in uc_ai_prompt_profiles.version%type default null,
  p_parameters        in json_object_t default null,
  p_provider_override in uc_ai_prompt_profiles.provider%type default null,
  p_model_override    in uc_ai_prompt_profiles.model%type default null,
  p_config_override   in json_object_t default null
) return json_object_t;

function execute_profile(
  p_id                in uc_ai_prompt_profiles.id%type,
  p_parameters        in json_object_t default null,
  p_provider_override in uc_ai_prompt_profiles.provider%type default null,
  p_model_override    in uc_ai_prompt_profiles.model%type default null,
  p_config_override   in json_object_t default null
) return json_object_t;
```

```sql
declare
  l_result json_object_t;
  l_params json_object_t := json_object_t();
  l_output json_object_t;
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_params.put('issue_text', 'The export button fails with an error when I download the report.');

  l_result := uc_ai_prompt_profiles_api.execute_profile(
    p_code       => 'CLASSIFY_ISSUE'   -- p_version omitted: latest ACTIVE version
  , p_parameters => l_params
  );

  -- profile has a response_schema, so final_message is schema-conforming JSON text
  l_output := json_object_t(l_result.get_clob('final_message'));
  dbms_output.put_line('Category: ' || l_output.get_string('category'));
  dbms_output.put_line('Priority: ' || l_output.get_string('priority'));
end;
/
```

### Runtime overrides

Override provider, model, or config per call — useful for A/B tests and temporary provider switches:

```sql
l_result := uc_ai_prompt_profiles_api.execute_profile(
  p_code              => 'CLASSIFY_ISSUE'
, p_parameters        => l_params
, p_provider_override => uc_ai.c_provider_anthropic
, p_model_override    => uc_ai_anthropic.c_model_claude_4_5_haiku
, p_config_override   => json_object_t('{"anthropic": {"g_max_tokens": 2000}}')
);
```

`p_config_override` **replaces** the stored `model_config_json` entirely — it is not merged.

## model_config_json

Store call configuration with the prompt. Root-level keys mirror `uc_ai` globals; provider-specific keys are nested under the provider name:

```json
{
  "g_enable_tools": true,
  "g_tool_tags": ["tickets"],
  "g_enable_reasoning": true,
  "openai": {"g_reasoning_effort": "low"}
}
```

The config is applied when the profile is executed (globals are reset to defaults first, then the config is applied). Unknown keys raise ORA-20503; an unknown provider raises ORA-20306. Full key reference with a complete example: see `reference.md` in this skill.

## Lifecycle: versions and status

Status constants (verbatim from the spec):

```sql
c_status_draft    constant uc_ai_prompt_profiles.status%type := 'draft';
c_status_active   constant uc_ai_prompt_profiles.status%type := 'active';
c_status_archived constant uc_ai_prompt_profiles.status%type := 'archived';
```

Create a new version (an exact copy of the source, starting in `draft`):

```sql
function create_new_version(
  p_code           in uc_ai_prompt_profiles.code%type,
  p_source_version in uc_ai_prompt_profiles.version%type,
  p_new_version    in uc_ai_prompt_profiles.version%type default null  -- null: source + 1
) return uc_ai_prompt_profiles.id%type;
```

Promote/retire with `change_status` (overloads by `p_id` or by `p_code`/`p_version`):

```sql
begin
  l_new_id := uc_ai_prompt_profiles_api.create_new_version(
    p_code           => 'CLASSIFY_ISSUE'
  , p_source_version => 1
  );

  -- ... edit the draft (update_prompt_profile), test it via execute_profile(p_id => l_new_id) ...

  uc_ai_prompt_profiles_api.change_status(
    p_code => 'CLASSIFY_ISSUE', p_version => 2
  , p_status => uc_ai_prompt_profiles_api.c_status_active
  );
  uc_ai_prompt_profiles_api.change_status(
    p_code => 'CLASSIFY_ISSUE', p_version => 1
  , p_status => uc_ai_prompt_profiles_api.c_status_archived
  );
  commit;
end;
/
```

Executing by code without `p_version` uses the **latest active version** (highest version number with status `active`). Prefer archiving over `delete_prompt_profile` to keep history.

## Pitfalls

- **Execution resets your session globals.** `execute_profile` applies the profile config by first calling `uc_ai.reset_globals`, then setting only the keys in `model_config_json`. Globals you set beforehand (e.g. `uc_ai.g_enable_tools`) are wiped — put everything the call needs into `model_config_json` or `p_config_override`. API-key setup via the `uc_ai_get_key` function is unaffected; credential globals belong in the config (`g_apex_web_credential`).
- **`p_config_override` replaces, never merges** the stored config.
- **Drafts are invisible to execute-by-code.** Without `p_version`, only `active` profiles are considered; test drafts explicitly via `p_version` or `p_id`.
- **No implicit commit.** The API does not commit — `commit` after create/update/status changes.
- **Missing placeholder parameters raise ORA-20506** before any tokens are spent; extra parameters are silently ignored.
- **Structured output**: set `p_response_schema` on the profile; parse `final_message` with `json_object_t(...)`. See the `uc-ai-structured-output` skill or https://www.united-codes.com/products/uc-ai/docs/guides/structured_output/
- **Don't edit live versions.** `update_prompt_profile` changes a version in place — for production profiles, `create_new_version` and switch statuses instead.

## Full documentation

- Prompt profiles guide: https://www.united-codes.com/products/uc-ai/docs/guides/prompt-profiles/
- generate_text API (result object): https://www.united-codes.com/products/uc-ai/docs/api/generate_text/
- Tools / function calling: https://www.united-codes.com/products/uc-ai/docs/guides/tools/
