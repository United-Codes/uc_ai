# Upgrade script

`scripts/generate_upgrade_script.sh` writes `upgrade_uc_ai.sql`. The script upgrades any
release from **v25.7** on to the working tree. It is safe to run more than once: a second run
prints `Nothing to change`. It stops at the first failed schema step.

```bash
bash scripts/generate_upgrade_script.sh   # or: make upgrade_uc_ai.sql
make test-upgrade                         # every baseline tag in scripts/test_upgrade.sh
make test-upgrade TAGS="v26.3"            # one baseline
```

## What the generated file does

| Phase | What | Source |
| --- | --- | --- |
| schema | entry check (installed, v25.7 or later), then the guarded steps of each release | [upgrade_schema.sql](upgrade_schema.sql), hand-written |
| comments | every `comment on` line | `src/tables/install.sql` |
| code | triggers, package specs and bodies, views | same files and order as the install script |
| post-scripts | built-in tool registration | `src/post-scripts/` |
| verify | every table, column, sequence, index and named constraint of a fresh install exists; fails with `WARNING missing ...` lines when not | [verify_schema.sql](verify_schema.sql), filled from `install.sql` by `scripts/list_install_objects.awk` |

The verify phase also runs at a customer site. It finds a DDL change that has no guarded step,
and a schema that a step could not bring into shape.

## Does a change need a step in `upgrade_schema.sql`?

| Change in `src/tables/install.sql` | Step needed? |
| --- | --- |
| New or changed comment | No, the comments phase runs every comment |
| Trigger, package, view, post-script | No, the code phase replaces it |
| New table or sequence | **Yes**, `ensure_table` / `ensure_sequence` |
| New column on an existing table | **Yes**, `ensure_column`, one column per call |
| New or changed constraint | **Yes**, `ensure_constraint` / `ensure_check` |
| New or changed index | **Yes**, `ensure_index` (drop and recreate for a changed definition) |
| Data backfill | **Yes**, through `execute immediate`, inside `if g_changed then` of its structural change |

Put the steps of the release that is being prepared into its `release_vYY_N` procedure, and call
the procedure at the end of the main block. The rules are in the header of `upgrade_schema.sql`.
`make test-upgrade` fails when `install.sql` and the steps disagree.

## Calling the script from another script

APEX Document Management runs `upgrade_uc_ai.sql` from its own upgrade. So the script:

- has no `exit`,
- leaves `whenever sqlerror exit failure rollback` on (a caller that wants other behavior sets
  it again after the call),
- leaves `serveroutput` and `sqlblanklines` on,
- is self-contained: it calls no other file.

Keep it that way.
