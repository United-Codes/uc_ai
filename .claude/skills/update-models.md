# Update Provider Models

Updates model constants across all AI provider packages and regenerates the `uc_ai_utils` package body.

## Trigger

When asked to update, add, or sync AI provider models/constants.

## Architecture

Models are defined in exactly **one place**: as `c_model_*` constants in each provider's package spec (`.pks` file). The `uc_ai_utils.pkb` body is auto-generated from these constants — never edit it manually.

### Key files

| File | Purpose |
|------|---------|
| `src/packages/uc_ai.pks` | Provider constants (`c_provider_*`) |
| `src/packages/uc_ai_openai.pks` | OpenAI model constants |
| `src/packages/uc_ai_anthropic.pks` | Anthropic model constants |
| `src/packages/uc_ai_google.pks` | Google Gemini model constants |
| `src/packages/uc_ai_oci.pks` | OCI GenAI model constants |
| `src/packages/uc_ai_xai.pks` | xAI Grok model constants |
| `src/packages/uc_ai_ollama.pks` | Ollama (no hardcoded models — dynamic) |
| `src/packages/uc_ai_openrouter.pks` | OpenRouter (no hardcoded models — dynamic) |
| `src/packages/uc_ai_utils.pks` | Package spec with pipelined function signatures and record types |
| `src/packages/uc_ai_utils.pkb` | **Auto-generated** — do NOT edit manually |
| `scripts/generate_uc_ai_utils_body.sh` | Bash script that generates `uc_ai_utils.pkb` |

### Documentation URLs for each provider

- OpenAI: https://platform.openai.com/docs/models (or pricing page)
- Anthropic: https://docs.anthropic.com/en/docs/about-claude/models
- Google: https://ai.google.dev/gemini-api/docs/models
- xAI: https://docs.x.ai/docs/models
- OCI: https://docs.oracle.com/en-us/iaas/Content/generative-ai/pretrained-models.htm

## Steps

### 1. Look up current models from provider docs

Fetch each provider's documentation page to get the current list of model IDs. Compare against existing `c_model_*` constants in the corresponding `.pks` file.

### 2. Add missing constants to provider specs

Add new `c_model_*` constants to the appropriate provider `.pks` file. Follow existing naming conventions:

```sql
-- Pattern: c_model_<name> constant uc_ai.model_type := '<api-model-id>';
c_model_gpt_5_4 constant uc_ai.model_type := 'gpt-5.4';
```

- Constants for embedding models should contain `embed` in the name (the generator uses this to set `model_type`).
- Order: newest models first within each provider file.
- Keep deprecated/legacy models — users may still reference them.

### 3. If adding a new provider

1. Add `c_provider_<name>` constant to `src/packages/uc_ai.pks`
2. Add a display name case to `provider_display_name()` in `scripts/generate_uc_ai_utils_body.sh`
3. The generator will auto-discover the new provider and its models

### 4. Regenerate the utils body

```bash
bash scripts/generate_uc_ai_utils_body.sh
```

This reads all `c_provider_*` from `uc_ai.pks` and all `c_model_*` from each provider spec, then generates `src/packages/uc_ai_utils.pkb` with pipelined `pipe row` calls.

### 5. Compile and test

```bash
echo "@@src/packages/uc_ai_<provider>.pks
@@src/packages/uc_ai_utils.pkb
show errors package uc_ai_<provider>;
show errors package body uc_ai_utils;" | sql -name local-23ai-uc_ai
```

Then verify:

```sql
select provider, model_type, count(*) as cnt
  from table(uc_ai_utils.get_models)
 group by provider, model_type
 order by provider, model_type;
```

### 6. Regenerate install script

```bash
bash scripts/generate_install_script.sh
```

## Important notes

- `uc_ai_utils.pkb` is compiled as an API package body (after all provider specs), so it can reference any provider's constants.
- Ollama and OpenRouter have no hardcoded models — they support dynamic model selection. The generator skips providers with 0 `c_model_*` constants.
- The `model_type` field is auto-detected: constants containing `embed` in the name → `embedding`, everything else → `chat`.
