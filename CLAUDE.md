# UC AI

Oracle PL/SQL framework for integrating AI models (OpenAI, Anthropic, Google, OCI, Ollama, xAI, OpenRouter) into Oracle databases. Provides a unified SDK with function calling, prompt profiles, multi-agent workflows, and structured output validation.

License: LGPL v3.0 | Docs: https://www.united-codes.com/products/uc-ai/docs/

## Tech Stack

- **Source code**: PL/SQL (Oracle database packages)
- **Database**: Oracle (tables, triggers, migrations)
- **Test framework**: utPLSQL (`ut.run()`)
- **Documentation site**: Astro + Starlight (in `docs/`), built with Bun
- **CI/CD**: GitLab CI (`.gitlab-ci.yml`)
- **Dependency**: OraOpenSource Logger v3.1.1 (`src/dependencies/`)

## Project Structure

```
src/
  packages/         PL/SQL package specs (.pks) and bodies (.pkb)
  tables/           Table DDL (install.sql)
  triggers/         Database triggers
  migrations/       Schema migration scripts
  post-scripts/     Post-install verification
  dependencies/     External deps (Logger framework)
test/
  test_uc_ai_*.pks/.pkb   utPLSQL test packages
  uc_ai_test_utils.*       Shared test helpers
  samples/                 JSON request/response fixtures
  testdata/                Test data files
docs/
  src/content/docs/  MDX documentation (Astro/Starlight)
  package.json       Docs site config
scripts/
  generate_install_script.sh         Generate install_uc_ai.sql
  generate_upgrade_script.sh         Generate upgrade_packages.sql
  generate_uninstall_script.sh       Generate uninstall.sql
  generate_install_script_complete.sh  Install with Logger bundled
  package_utils.sh                   Shared build utilities
```

## Key Packages

| Package | Purpose |
|---------|---------|
| `uc_ai` | Main entry point: `generate_text()`, `generate_embeddings()`, provider/model constants |
| `uc_ai_anthropic`, `uc_ai_google`, `uc_ai_openai`, `uc_ai_oci`, `uc_ai_ollama`, `uc_ai_xai`, `uc_ai_openrouter` | Provider implementations |
| `uc_ai_agents_api` | Agent CRUD, validation, versioning |
| `uc_ai_agent_exec_api` | Agent execution engine (sequential, conditional, parallel, loop workflows) |
| `uc_ai_agent_workflow_api` | Workflow helpers: input mapping, condition evaluation, step execution |
| `uc_ai_tools_api` | Tool/function-calling registration and execution |
| `uc_ai_prompt_profiles_api` | Versioned prompt templates with `{var}` substitution |
| `uc_ai_message_api` | Message construction and conversation history |
| `uc_ai_structured_output` | JSON schema-based output validation |
| `uc_ai_logger` | Logging wrapper around OraOpenSource Logger |
| `uc_ai_toon` | Token-Oriented Object Notation package |
| `uc_ai_responses_api` | OpenAI Responses API support |

## Build & Install

Generate install/upgrade scripts (run from repo root):

```bash
# Generate fresh install script
bash scripts/generate_install_script.sh

# Generate upgrade script (packages only, no table changes)
bash scripts/generate_upgrade_script.sh

# Generate complete install with Logger dependency
bash scripts/generate_install_script_complete.sh
```

Run in Oracle via SQL*Plus:

```sql
-- Fresh install
@install_uc_ai.sql

-- Upgrade packages only
@upgrade_packages.sql
```

Installation order is dependency-aware: tables -> triggers -> specs (core first, then API, then providers) -> bodies -> post-scripts. See `install_uc_ai.sql` for exact order.

## Testing

Tests use utPLSQL. Run from SQL*Plus with `set serveroutput on`:

```sql
-- Single test
begin ut.run('test_uc_ai_anthropic.basic_recipe'); end;

-- All tests in a package
begin ut.run('test_uc_ai_anthropic'); end;
```

Test packages follow the naming pattern `test_uc_ai_<feature>`. Shared utilities are in `uc_ai_test_utils`.

## Documentation Site

```bash
cd docs && bun install && bun run dev    # Local dev server
cd docs && bun run build                 # Production build
```

Content lives in `docs/src/content/docs/` as MDX files. Provider setup guides are in `docs/src/content/docs/providers/`.

## Key Reference Files

- Main API spec: `src/packages/uc_ai.pks` (provider constants, type definitions, `generate_text` signatures)
- Provider constants and model lists: each provider `.pks` file
- Agent types and workflow definitions: `src/packages/uc_ai_agents_api.pks:13-37`
- Error codes: `src/packages/uc_ai.pks:60-69` (custom exceptions -20301 to -20305)
- Agent error codes: `src/packages/uc_ai_agents_api.pkb` (-20011 to -20023)
- Table schema: `src/tables/install.sql`
- Input mapping syntax: `docs/input-mapping-guide.md`
- Multi-agent architecture: `docs/multi-agent-systems-proposal.md`

## Additional Documentation

Check these files for context on specific topics:

| Topic | File |
|-------|------|
| Architectural patterns & conventions | `.claude/docs/architectural_patterns.md` |
| Multi-agent system design | `docs/multi-agent-systems-proposal.md` |
| Input mapping syntax for workflows | `docs/input-mapping-guide.md` |
| Provider setup guides | `docs/src/content/docs/providers/*.mdx` |
| API reference (generate_text) | `docs/src/content/docs/api/generate_text.mdx` |
| Tools / function calling guide | `docs/src/content/docs/guides/tools.mdx` |
| Prompt profiles guide | `docs/src/content/docs/guides/prompt-profiles.mdx` |
| Agentic AI guide | `docs/src/content/docs/guides/agentic-ai.mdx` |
| Structured output guide | `docs/src/content/docs/guides/structured_output.mdx` |
| Release history | `docs/src/content/docs/other/relase-history.mdx` |
