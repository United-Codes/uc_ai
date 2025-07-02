---
title: FAQ
description: Frequently Asked Questions about UC AI
sidebar:
    order: 1
---

## What is UC AI?

UC AI is a comprehensive Oracle PL/SQL framework that enables direct integration with AI models (OpenAI GPT, Anthropic Claude, Google Gemini) from within your Oracle database. It allows AI models to execute database functions through a structured tool system, bringing AI capabilities directly to where your data lives.

## Which Oracle Database versions are supported?

UC AI supports Oracle Database 12.2 or later. You don't need Oracle 23ai - the framework works with existing Oracle databases.

## Which AI providers are supported?

Currently, UC AI supports three major AI providers:
- **OpenAI** (GPT models)
- **Anthropic** (Claude models) 
- **Google** (Gemini models)

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

Check out the [Installation Guide](/guides/installation/) for detailed steps.
