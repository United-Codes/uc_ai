---
title: FAQ
description: Frequently Asked Questions about UC AI
sidebar:
    order: 1
---

## What is UC AI?

UC AI is an Oracle PL/SQL framework for calling AI models from your database. Its tool system lets models request database functions.

## Which Oracle Database versions are supported?

UC AI supports Oracle Database 12.2 or later. You don't need Oracle 23ai - the framework works with existing Oracle databases.

The one exception is [Programmatic Tool Calling (Code Mode)](/products/uc-ai/docs/guides/programmatic-tool-calling/), an opt-in feature that runs model-authored JavaScript via Oracle's Multilingual Engine and therefore requires Oracle 23ai plus a one-time sandbox install. Everything else works on 12.2+.

## Which AI providers are supported?

Currently, UC AI supports eight AI providers:

- **OpenAI** (GPT models)
- **Anthropic** (Claude models)
- **Google** (Gemini models)
- **OCI** (Oracle Cloud Infrastructure Generative AI)
- **Ollama** (Open source models like Llama, Mistral, Qwen, etc.)
- **xAI** (Grok models)
- **Mistral** (Mistral Large/Medium/Small, Magistral, Codestral models)
- **OpenRouter** (Unified access to models from many providers)

The framework provides a common API for calls to different providers.

## Do I need to install additional dependencies?

The only dependency is the Logger package, which is included in the project. You can either install the full Logger for debugging capabilities or use the "no-op" version if you don't need logging functionality.

## Can AI models interact with my database data?

Yes. You can register database functions as tools that a model can request during a conversation. These functions can retrieve data or perform calculations.

## How do I get started quickly?

1. Clone the repository
2. Install Logger (or Logger no-op)
3. Run the installation script
4. Set up your API keys for your chosen AI provider
5. Start using `uc_ai.generate_text()` in your PL/SQL code

Read the [Installation Guide](/products/uc-ai/docs/guides/installation/) for detailed steps.

<a id="custom-model-strings"></a>

## What if UC AI doesn't have a constant for a new model?

If UC AI has no constant for a model, pass its name as a string to `p_model`:

```sql
declare
  l_result json_object_t;
begin
  l_result := uc_ai.generate_text(
    p_user_prompt => 'What is Oracle APEX?',
    p_provider => uc_ai.c_provider_openai,
    p_model => 'gpt-5.4'
  );
end;
```

The `p_model` parameter accepts any `varchar2` value, so you are not limited to the pre-defined constants. The constants are provided for convenience and to avoid typos, but any valid model identifier string that the provider accepts will work.

<a id="no-model-table"></a>

## Why doesn't UC AI have a table of providers and models instead of constants?

UC AI provides constants for common model names. The `p_model` parameter also accepts a model name as a string, so a model needs no catalog row before use.

Your application can maintain its own model catalog, including display names, permitted providers, and approval status.
