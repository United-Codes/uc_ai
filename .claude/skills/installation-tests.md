# Installation Tests

Runs the install and uninstall test scripts against a local Oracle 23ai/26ai database, then verifies the resulting schema matches expectations. Use before tagging a release.

## Trigger

When asked to run installation tests, verify install/uninstall scripts, or check release readiness of the install pipeline.

## Steps

### 1. Run install tests

```bash
bash scripts/test_installs.sh
```

This regenerates all install scripts and runs each through the local SQLcl install wrapper. A passing run prints `✅ SUCCESS: Found expected output 'Invalid objects: no rows selected'` for each tested script:

- `install_with_logger.sql`
- `install_uc_ai_complete_with_logger.sql`

### 2. Run uninstall test

```bash
bash scripts/test_uninstall_script.sh
```

This installs `install_uc_ai_complete_with_logger.sql`, then runs the generated `uninstall.sql`. Look for `SUCCESS: All UC AI Framework objects have been removed.` Remaining objects (LOGGER package, logger_logs tables, etc.) belong to the Logger framework and are intentionally preserved.

### 3. Manual schema verification (optional but recommended for releases)

After step 1 leaves the schema installed, connect and verify counts:

```bash
sql -name local-23ai-uc_testinstall_1 << 'EOF'
set pagesize 200
SELECT object_type, COUNT(*) FROM user_objects
 WHERE object_name LIKE 'UC_AI%' GROUP BY object_type ORDER BY 1;
SELECT object_name, object_type FROM user_objects
 WHERE status <> 'VALID';
exit;
EOF
```

Expected counts for UC_AI* objects:

| Object type | Count | Notes |
|---|---|---|
| PACKAGE | 20 | all provider + API specs |
| PACKAGE BODY | 18 | `uc_ai_xai` and `uc_ai_openrouter` are spec-only |
| TABLE | 6 | agents, agent_executions, prompt_profiles, tools, tool_parameters, tool_tags |
| SEQUENCE | 6 | one per table |
| TRIGGER | 6 | `_BIU` / `_BI` per table, all ENABLED |
| FUNCTION | 1 | `UC_AI_GET_KEY` |
| INDEX | 14 named + system LOB indexes | PK/UK/IDX |

Invalid objects must be 0. If counts drift, cross-check against `install_uc_ai.sql` and `src/tables/install.sql`.

## Important notes

- The install/uninstall wrapper command is `local-26ai.sh` (the script names contain `23ai` for historical reasons — the actual wrapper points at the 26ai instance). The created connection name is `local-23ai-uc_testinstall_1`.
- `scripts/test_uninstall_script.sh` strips the interactive `PAUSE` from `uninstall.sql` at runtime so the heredoc can drive it non-interactively. Do not remove that `sed` line.
- Both scripts use `set -e` and exit non-zero on any failure — a successful run means everything passed.
