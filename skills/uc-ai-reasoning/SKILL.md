---
name: uc-ai-reasoning
description: Use when enabling reasoning / extended thinking for AI calls from Oracle PL/SQL with UC AI — uc_ai.g_enable_reasoning and uc_ai.g_reasoning_level (c_reasoning_level_low/medium/high), provider tuning via uc_ai_openai.g_reasoning_effort, uc_ai_anthropic.g_reasoning_budget_tokens, uc_ai_google.g_reasoning_budget, uc_ai_xai.g_reasoning_effort, checking usage.reasoning_tokens, or extracting reasoning content from the message array.
---

# UC AI Reasoning — Extended Thinking for AI Calls

Reasoning (also called thinking) lets a model work through a problem step by step before answering. Enable it for multi-step problems, tricky analysis, and especially for better tool planning — a reasoning model picks tools and their arguments far more precisely. The trade-off is cost: reasoning consumes extra output tokens, visible in the result as `usage.reasoning_tokens`.

## Enabling reasoning (generic)

Set two globals in the `uc_ai` package — this works across providers, UC AI translates the level into the provider-specific setting:

```sql
declare
  l_result json_object_t;
begin
  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  uc_ai.reset_globals;  -- globals are session-scoped, start clean
  uc_ai.g_enable_reasoning := true;
  uc_ai.g_reasoning_level  := uc_ai.c_reasoning_level_medium; -- low | medium | high

  l_result := uc_ai.generate_text(
    p_user_prompt => 'Answer in one sentence. If there is a great filter, are we before or after it and why?'
  , p_provider    => uc_ai.c_provider_openai
  , p_model       => uc_ai_openai.c_model_gpt_o4_mini -- must be a reasoning-capable model
  );

  dbms_output.put_line('Answer: ' || l_result.get_clob('final_message'));
  dbms_output.put_line('Reasoning tokens: '
    || l_result.get_object('usage').get_number('reasoning_tokens'));
end;
/
```

The level constants are `uc_ai.c_reasoning_level_low`, `c_reasoning_level_medium`, `c_reasoning_level_high`. Model constants change with releases — check the installed `uc_ai_<provider>` spec for current reasoning-capable models.

## Provider-specific tuning

For productive systems, fine-tune the provider global instead of (or in addition to) the generic level. `uc_ai.g_enable_reasoning := true;` is always required.

| Provider | Global | Values / notes |
|----------|--------|----------------|
| OpenAI | `uc_ai_openai.g_reasoning_effort` | `'minimal'`, `'low'`, `'medium'`, `'high'`, `'xhigh'` — default `'low'` |
| Anthropic | `uc_ai_anthropic.g_reasoning_budget_tokens` | thinking token budget, minimum 1024; also raise `uc_ai_anthropic.g_max_tokens` (default 8192) — the budget counts against it |
| Google | `uc_ai_google.g_reasoning_budget` | thinking token budget; `-1` = dynamic, `0` = off; min/max are model-dependent, 2.5 Pro cannot disable reasoning |
| xAI | `uc_ai_xai.g_reasoning_effort` | `'low'`, `'high'` — default `'low'` |
| OpenRouter | `uc_ai_openrouter.g_reasoning_effort` | `'minimal'`, `'low'`, `'medium'`, `'high'` — default `'low'` |
| Mistral | — | no effort parameter; the magistral models reason by default |

Anthropic example — leave room for thinking plus the answer:

```sql
uc_ai.reset_globals;
uc_ai.g_enable_reasoning := true;
uc_ai_anthropic.g_reasoning_budget_tokens := 2048;  -- minimum is 1024
uc_ai_anthropic.g_max_tokens := 16384;              -- default 8192; budget counts against it
```

OpenAI note: UC AI calls OpenAI through the Responses API by default (`uc_ai_openai.g_use_responses_api := true`). The Responses API only returns reasoning content when you opt in via the `uc_ai_responses_api` globals `g_reasoning_summary` (`'concise'`, `'detailed'`, `'auto'`, null for off), `g_store_responses`, and `g_include_encrypted_reasoning` — see https://www.united-codes.com/products/uc-ai/docs/providers/openai/.

## Config-driven equivalent

Globals are session-scoped; for reusable/library code prefer the `p_config` overloads of `generate_text`, which neither read nor mutate globals:

```sql
l_result := uc_ai.generate_text(
  p_user_prompt => 'Plan the migration steps and answer concisely.'
, p_provider    => uc_ai.c_provider_openai
, p_model       => uc_ai_openai.c_model_gpt_o4_mini
, p_config      => json_object_t('{
    "g_enable_reasoning": true,
    "openai": {"g_reasoning_effort": "medium"}
  }')
);
```

## Extracting the reasoning content

With reasoning enabled, the final assistant message contains a content item of `"type": "reasoning"` next to the `"type": "text"` answer. Loop over the last assistant message's `content` array:

```sql
declare
  l_result            json_object_t;
  l_messages          json_array_t;
  l_assistant_message json_object_t;
  l_content_array     json_array_t;
  l_content_item      json_object_t;
  l_reasoning_found   boolean := false;
begin
  -- API key: uc_ai_get_key function or uc_ai_google.g_apex_web_credential := 'GEMINI';
  uc_ai.reset_globals;
  uc_ai.g_enable_reasoning := true;
  uc_ai_google.g_reasoning_budget := 512;

  l_result := uc_ai.generate_text(
    p_user_prompt => 'Answer in one sentence. If there is a great filter, are we before or after it and why?'
  , p_provider    => uc_ai.c_provider_google
  , p_model       => uc_ai_google.c_model_gemini_2_5_flash
  );

  l_messages := treat(l_result.get('messages') as json_array_t);

  -- get the assistant message (the last one)
  l_assistant_message := treat(l_messages.get(l_messages.get_size - 1) as json_object_t);

  if l_assistant_message.get_string('role') = 'assistant' then
    l_content_array := l_assistant_message.get_array('content');

    -- loop through content items
    for i in 0 .. l_content_array.get_size - 1 loop
      l_content_item := treat(l_content_array.get(i) as json_object_t);

      if l_content_item.get_string('type') = 'reasoning' then
        l_reasoning_found := true;
        dbms_output.put_line('Reasoning: ' || l_content_item.get_clob('text'));
      end if;
    end loop;

    if not l_reasoning_found then
      dbms_output.put_line('No reasoning content found (may not be supported by this provider/model)');
    end if;
  else
    raise_application_error(-20001, 'Did not find expected assistant message structure');
  end if;
end;
/
```

To observe reasoning live while a call runs (e.g. streaming it to a UI), register a callback for the `assistant_reasoning` event (`uc_ai.c_event_assistant_reasoning`) — see the `uc-ai-event-callbacks` skill.

## Pitfalls

- **Not every model reasons.** Non-reasoning models ignore the settings or the provider rejects the request. Check the provider page and the installed `uc_ai_<provider>` spec for reasoning-capable models (xAI even has separate `-reasoning`/`-non-reasoning` model constants).
- **Globals persist for the session.** A `g_enable_reasoning := true` from earlier code makes every later call pay for reasoning tokens. Call `uc_ai.reset_globals;` before configuring; use the `p_config` overloads in library code.
- **Anthropic: budget below 1024 is invalid**, and the thinking budget counts against `g_max_tokens` — raise `uc_ai_anthropic.g_max_tokens` or the visible answer gets squeezed (watch for `finish_reason = 'length'`).
- **OpenAI Responses API hides reasoning by default** — opt in via `uc_ai_responses_api.g_reasoning_summary` etc. if you need the reasoning text back.
- **Reasoning costs real money.** Track `usage.reasoning_tokens` and start with low effort/budget; increase only when quality demands it.

## Full documentation

- Reasoning guide: https://www.united-codes.com/products/uc-ai/docs/guides/reasoning/
- OpenAI: https://www.united-codes.com/products/uc-ai/docs/providers/openai/
- Anthropic: https://www.united-codes.com/products/uc-ai/docs/providers/anthropic/
- Google: https://www.united-codes.com/products/uc-ai/docs/providers/google/
- xAI: https://www.united-codes.com/products/uc-ai/docs/providers/xai/
- Ollama: https://www.united-codes.com/products/uc-ai/docs/providers/ollama/
- Mistral: https://www.united-codes.com/products/uc-ai/docs/providers/mistral/
