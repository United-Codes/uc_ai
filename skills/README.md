# UC AI — Claude Code Skills

Agent skills that teach [Claude Code](https://claude.com/claude-code) (and other agents that support the skill format) how to use the [UC AI](https://www.united-codes.com/products/uc-ai/docs/) PL/SQL framework in your Oracle project. Each skill is self-contained with copy-pasteable PL/SQL, verified against the UC AI package specs.

## Installation

Copy the skills you need into your project's `.claude/skills/` directory:

```bash
# all skills
cp -r uc_ai/skills/uc-ai-* your-project/.claude/skills/

# or just the ones you need
cp -r uc_ai/skills/uc-ai-tools your-project/.claude/skills/
```

Claude Code discovers them automatically; each skill loads when a task matches its description.

## Skills

| Skill | Use it for |
|-------|-----------|
| [`uc-ai-quickstart`](./uc-ai-quickstart/SKILL.md) | First `generate_text` call, provider/model constants, API key setup, parsing results, conversations, embeddings |
| [`uc-ai-tools`](./uc-ai-tools/SKILL.md) | Function calling — letting the AI execute your PL/SQL functions |
| [`uc-ai-reasoning`](./uc-ai-reasoning/SKILL.md) | Enabling and tuning extended thinking / reasoning |
| [`uc-ai-structured-output`](./uc-ai-structured-output/SKILL.md) | Getting schema-validated JSON back; TOON encoding for token-efficient input |
| [`uc-ai-prompt-profiles`](./uc-ai-prompt-profiles/SKILL.md) | Versioned, reusable prompt templates stored in the database |
| [`uc-ai-multi-agent`](./uc-ai-multi-agent/SKILL.md) | Agents, workflows, orchestrators, and agent conversations |
| [`uc-ai-file-analysis`](./uc-ai-file-analysis/SKILL.md) | Sending PDFs and images (BLOBs) to multimodal models |
| [`uc-ai-event-callbacks`](./uc-ai-event-callbacks/SKILL.md) | Observing AI activity: streaming-style UIs, audit logging of tool calls |

## Versioning

The skills are written for the UC AI version they ship with (see `uc_ai.c_version` in your installed `uc_ai` package spec). Model constants in examples evolve with releases — when in doubt, check the installed `uc_ai_<provider>` package spec for the current list.

Full documentation: https://www.united-codes.com/products/uc-ai/docs/
