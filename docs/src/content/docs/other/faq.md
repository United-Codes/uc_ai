---
title: FAQ
description: Frequently Asked Questions about UC AI
sidebar:
    order: 1
---

## What is UC AI?

UC AI is a comprehensive Oracle PL/SQL framework that enables direct integration with AI models (OpenAI GPT, Anthropic Claude, Google Gemini, Ollama) from within your Oracle database. It allows AI models to execute database functions through a structured tool system, bringing AI capabilities directly to where your data lives.

## Which Oracle Database versions are supported?

UC AI supports Oracle Database 12.2 or later. You don't need Oracle 23ai - the framework works with existing Oracle databases.

## Which AI providers are supported?

Currently, UC AI supports seven AI providers:
- **OpenAI** (GPT models)
- **Anthropic** (Claude models)
- **Google** (Gemini models)
- **OCI** (Oracle Cloud Infrastructure Generative AI)
- **Ollama** (Open source models like Llama, Mistral, Qwen, etc.)
- **xAI** (Grok models)
- **OpenRouter** (Unified access to models from many providers)

The framework is designed to make it easy to switch between providers without changing your code.

## Do I need to install additional dependencies?

The only dependency is the Logger package, which is included in the project. You can either install the full Logger for debugging capabilities or use the "no-op" version if you don't need logging functionality.

## Can AI models interact with my database data?

Yes! One of UC AI's key features is function calling (tools). You can register database functions that the AI can call during conversations to look up data, perform calculations, or interact with your database - making your AI assistant truly powerful.

## How do I get started quickly?

1. Clone the repository
2. Install Logger (or Logger no-op)
3. Run the installation script
4. Set up your API keys for your chosen AI provider
5. Start using `uc_ai.generate_text()` in your PL/SQL code

Check out the [Installation Guide](/products/uc-ai/docs/guides/installation/) for detailed steps.

## What if UC AI doesn't have a constant for a new model? {#custom-model-strings}

AI providers frequently release new models. If UC AI doesn't yet offer a constant for a model, you can simply pass the model name as a string directly to the `p_model` parameter:

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

## Why doesn't UC AI have a table of providers and models instead of constants? {#no-model-table}

This is a deliberate design decision. UC AI provides package constants for common models as a convenience, but intentionally does not maintain a configuration table of providers and models. Here's why:

- **You can use any model immediately** — as explained [above](#custom-model-strings), you can pass any model name as a string to `p_model` without waiting for a UC AI update.
- **The model landscape changes too fast** — new models are released constantly. A configuration table would always be outdated unless maintained by the user anyway.
- **Some providers have hundreds of models** — OpenRouter alone supports over 600 models. Maintaining a complete list is not feasible.
- **Override scenarios make it impractical** — OpenAI-compatible providers like DeepSeek work through base URL overrides without first-class support. There is no way to provide constants for all possible override combinations.
- **Organizations want their own governance** — most teams want to restrict which providers and models are available to their users. This kind of policy logic is better owned by your application.

The focus of UC AI is on making LLMs work reliably across providers. If you need a model catalog or approval workflow, we recommend implementing that in your own application layer.
