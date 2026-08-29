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

Expected counts for UC_AI* objects (verified against a fresh v26.4 install):

| Object type | Count | Notes |
|---|---|---|
| PACKAGE | 24 | 26 specs exist; `uc_ai_ptc_api` and `uc_ai_ptc_runner` are installed by the code-mode sandbox script, not the core installer |
| PACKAGE BODY | 21 | 23 bodies exist, minus the same two sandbox packages |
| TABLE | 11 | tools, tool_parameters, tool_tags, prompt_profiles, agents, agent_executions, agent_sessions, agent_messages, memory_stores, memory_files, memory_config |
| SEQUENCE | 10 | one per table except `uc_ai_tool_tags` |
| TRIGGER | 10 | `_BIU` / `_BI` per table, all ENABLED, except `uc_ai_memory_files` (deliberate, see `src/triggers/triggers.sql`) |
| VIEW | 1 | `uc_ai_v_memory_files` from `src/views/views.sql` |
| FUNCTION | 1 | `UC_AI_GET_KEY` |
| INDEX | 31 | all named `UC_AI%`; none system-generated |

A fresh install also creates one tool row: `select count(*) from uc_ai_tools where code = 'MEMORY'` must return 1 (from `src/post-scripts/register_memory_tool.sql`).

A tool row that exists is not a tool that runs. Also call the registered handler
through the tool layer, because that is what binds the arguments:

```sql
select uc_ai_tools_api.execute_tool('MEMORY', json_object_t('{"command":"view","path":"/memories"}')) from dual;
```

The result must be a memory result string (without a store it is
`Error: the memory tool is not available here ...`). An ORA-06550 / PLS-00306 here
means the stored `function_call` does not match the signature of the handler.

Invalid objects must be 0. If counts drift, cross-check against `install_uc_ai.sql` and `src/tables/install.sql`.

Update this table whenever a release adds a table, a sequence, a trigger, or a
package. The counts went stale between v26.2 and v26.3 and then failed step 3.

## Important notes

- The install/uninstall wrapper command is `local-26ai.sh` (the script names contain `23ai` for historical reasons — the actual wrapper points at the 26ai instance). The created connection name is `local-23ai-uc_testinstall_1`.
- `scripts/test_uninstall_script.sh` strips the interactive `PAUSE` from `uninstall.sql` at runtime so the heredoc can drive it non-interactively. Do not remove that `sed` line.
- Both scripts use `set -e` and exit non-zero on any failure — a successful run means everything passed.
