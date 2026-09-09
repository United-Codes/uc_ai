# UC AI — Agent Skills

Agent skills that teach a coding agent how to use the [UC AI](https://www.united-codes.com/products/uc-ai/docs/) PL/SQL framework in your Oracle project. Each skill is self-contained with copy-pasteable PL/SQL, verified against the UC AI package specs.

They use the `SKILL.md` format, so any agent that reads it can use them — Claude Code, Cursor, opencode, Codex, Gemini CLI, and others.

## Installation

With the [skills CLI](https://github.com/vercel-labs/skills):

```bash
# see what is in here
npx skills add United-Codes/uc_ai --list

# all nine, into the agents the CLI finds in the project
npx skills add United-Codes/uc_ai --all

# or one skill, for one agent
npx skills add United-Codes/uc_ai --skill uc-ai-tools -a claude-code
```

Or copy the directories you need yourself:

```bash
# all skills
cp -r uc_ai/skills/uc-ai-* your-project/.claude/skills/

# or just the ones you need
cp -r uc_ai/skills/uc-ai-tools your-project/.claude/skills/
```

The agent discovers them automatically; each skill loads when a task matches its description.

## Skills

| Skill | Use it for |
|-------|-----------|
| [`uc-ai-quickstart`](./uc-ai-quickstart/SKILL.md) | First `generate_text` call, provider/model constants, API key setup, parsing results, conversations, embeddings |
| [`uc-ai-tools`](./uc-ai-tools/SKILL.md) | Function calling — letting the AI execute your PL/SQL functions, and the run context a tool reads under `_ctx` |
| [`uc-ai-reasoning`](./uc-ai-reasoning/SKILL.md) | Enabling and tuning extended thinking / reasoning |
| [`uc-ai-structured-output`](./uc-ai-structured-output/SKILL.md) | Getting schema-validated JSON back; TOON encoding for token-efficient input |
| [`uc-ai-prompt-profiles`](./uc-ai-prompt-profiles/SKILL.md) | Versioned, reusable prompt templates stored in the database |
| [`uc-ai-multi-agent`](./uc-ai-multi-agent/SKILL.md) | Agents, workflows, orchestrators, agent conversations, and reaching an agent as a tool |
| [`uc-ai-agent-memory`](./uc-ai-agent-memory/SKILL.md) | Persistent agent memory: the MEMORY tool, store scopes, size caps and housekeeping |
| [`uc-ai-file-analysis`](./uc-ai-file-analysis/SKILL.md) | Sending PDFs and images (BLOBs) to multimodal models |
| [`uc-ai-event-callbacks`](./uc-ai-event-callbacks/SKILL.md) | Observing AI activity: streaming-style UIs, audit logging of tool calls |

## Versioning

The skills are written for the UC AI version they ship with (see `uc_ai.c_version` in your installed `uc_ai` package spec). Model constants in examples evolve with releases — when in doubt, check the installed `uc_ai_<provider>` package spec for the current list.

Full documentation: https://www.united-codes.com/products/uc-ai/docs/
