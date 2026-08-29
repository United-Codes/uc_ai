# Prepare Release

End-to-end checklist for cutting a new UC AI release (e.g. `v26.2`, `v26.3`, …). Captures the steps that turned out to matter — commit-to-changelog, code/docs/test audit, doc updates, verification.

## Trigger

When asked to "prepare release X", "cut a new release", "write release notes for vX", or "do a v26.X release pass".

## Inputs you need up front

- The **new version string** (e.g. `26.2`) and its numeric form (e.g. `20260200`).
- The **previous released tag** (usually the latest `vX` tag — verify with `git tag --sort=-creatordate | head -5`).

If the user doesn't give you the version, ask before doing anything else.

## Steps

### 1. Survey commits since the last tag

```bash
git log v<PREV>..HEAD --oneline
```

Spot-check any commit whose message is ambiguous with `git show <sha> --stat` (and look at the diff if needed). Group commits into these buckets — this structure matches existing entries in `docs/src/content/docs/other/release-history.mdx`:

- **Headline features** (new packages, new user-facing APIs, new provider features)
- **Existing feature enhancements** (defaults changed, new params, new helpers)
- **Fixes** (reference `#NN` GitHub issues where applicable)
- **New models** (usually grouped as one bullet)
- **Internal** (triggers, authid changes, refactors worth calling out)

### 2. Decide: migration script or package-only?

```bash
git diff v<PREV>..HEAD --stat -- src/tables/ src/triggers/ src/migrations/
```

- **No DDL changes** → package-only release. Users run `upgrade_packages.sql`.
- **DDL changes** (new/altered tables, new triggers, new columns):
  - Ask the user whether the DDL was a hotfix to the previous release (and thus already in users' schemas) or genuinely new.
  - If genuinely new, create `src/migrations/v<PREV>_to_v<NEW>.sql` with the DDL and reference it in the changelog as the first-run step before `upgrade_packages.sql`.
  - Confirm with `grep -n "trigger\|table" scripts/generate_upgrade_script.sh` that `upgrade_packages.sql` still skips DDL (it should).
  - Views are the exception: `src/views/views.sql` is `create or replace`, so
    `upgrade_packages.sql` ships it. A new view on a new table still needs the
    table in the migration script, which users run first.

### 2b. Register any new package with the generators

`scripts/package_utils.sh` drives every generator from three hardcoded arrays
(`API_PACKAGES`, `PROVIDER_PACKAGES`, `SANDBOX_PACKAGES`). A `.pks`/`.pkb` pair that
is in none of them is silently left out of `install_uc_ai.sql`,
`upgrade_packages.sql` and `uninstall.sql` — the generators only print
`WARNING: Unknown package found`, and nothing fails.

```bash
for f in src/packages/*.pks; do
  grep -q "$(basename "$f" .pks)" scripts/package_utils.sh || echo "NOT REGISTERED: $f"
done
```

Order inside `API_PACKAGES` is compile order, not taste: a spec that references
another package's type must come after it. `uc_ai_message_api` before
`uc_ai_prompt_profiles_api` is the case that already bit us (PLS-00302 on a fresh
install).

`SANDBOX_PACKAGES` (`uc_ai_ptc_api`, `uc_ai_ptc_runner`) is deliberately excluded
from the core installer — those need 23ai MLE JavaScript, while the rest of UC AI
runs on 12.2+.

### 3. Bump the version constants

Edit [src/packages/uc_ai.pks](src/packages/uc_ai.pks) (lines ~15–16):

```sql
c_version     constant varchar2(16 char) := '<NEW>';
c_version_num constant number := <NEW_NUMERIC>;
```

`c_version_num` format is `YYYYRR00` where `YYYY` is the major (year) and `RR` the minor (e.g. `v26.2` → `20260200`).

### 4. Audit `reset_globals` and `apply_model_config`

Every `g_*` in `uc_ai.pks` and every provider spec must be handled in both places. Easy way to cross-check:

```bash
for f in src/packages/uc_ai.pks src/packages/uc_ai_openai.pks src/packages/uc_ai_anthropic.pks src/packages/uc_ai_google.pks src/packages/uc_ai_ollama.pks src/packages/uc_ai_oci.pks src/packages/uc_ai_xai.pks src/packages/uc_ai_openrouter.pks; do
  echo "=== $(basename $f) ==="
  grep -nE "^\s*g_[a-z_]+\s" "$f"
done
```

Then open:

- `procedure reset_globals` in [src/packages/uc_ai.pkb](src/packages/uc_ai.pkb) — check each provider's globals is reset to its spec default.
- `procedure apply_model_config` in [src/packages/uc_ai_prompt_profiles_api.pkb](src/packages/uc_ai_prompt_profiles_api.pkb) — check each provider's case handles the globals that make sense to configure per-profile. User-facing settings (e.g. `g_use_responses_api`, region, compartment) should be supported; session-level registrations (`g_event_callback`, `g_callback_fatal`, `g_request_id`, `g_provider_override`) should be **omitted**.

Anything internal-only (like `g_request_id`, `g_provider_override`) should stay out of both dispatchers — but verify the reasoning is still correct for each new global.

### 5. Regenerate install/upgrade scripts

```bash
bash scripts/generate_install_script.sh > /dev/null
bash scripts/generate_upgrade_script.sh > /dev/null
bash scripts/generate_install_script_complete.sh > /dev/null
bash scripts/generate_uninstall_script.sh > /dev/null
bash scripts/generate_ptc_sandbox_script.sh > /dev/null
```

`install_ptc_sandbox_complete.sql` is the release-download path for code mode:
`scripts/install_ptc_sandbox.sql` pulls the PTC sources in with `@@../src/packages/`
relative includes, so it only runs from a checkout. `release.yml` attaches the
inlined variant and `scripts/uninstall_ptc_sandbox.sql`. If you add a file to the
sandbox installer, make sure the generator still resolves every `@@` include — it
fails rather than emitting a partial script.

If provider model constants changed, also run `bash scripts/generate_uc_ai_utils_body.sh` — or just use the `update-models` skill.

### 6. Run the test suite

Connection: `sql -name local-23ai-uc_ai`. Use `set serveroutput on size unlimited; set feedback off;` in each session.

There is **no full-suite runner and no LLM-free entry point**. `ut.run` with no
argument hits every live provider suite, and the `--%suitepath` coverage is partial
(16 of the 37 suites carry none), so `ut.run('uc_ai')` silently reaches about half.
Run the LLM-free suites by name.

**LLM-free suites** — verified: none of these calls `generate_text`,
`generate_embeddings`, `execute_agent` or `execute_profile` in a way that reaches a
provider. 416 tests, all of them fast and free:

```sql
begin ut.run('test_uc_ai_toon'); end;                    -- 22
/
begin ut.run('test_uc_ai_error'); end;                   -- 10
/
begin ut.run('test_uc_ai_utils'); end;                   --  6
/
begin ut.run('test_uc_ai_message_api'); end;             -- 17
/
begin ut.run('test_uc_ai_structured_output'); end;       -- 37
/
begin ut.run('test_uc_ai_tools_api'); end;               -- 12
/
begin ut.run('test_uc_ai_settings'); end;                -- 11
/
begin ut.run('test_uc_ai_reset_globals'); end;           --  3
/
begin ut.run('test_uc_ai_passthrough'); end;             --  8
/
begin ut.run('test_uc_ai_reasoning_replay'); end;        -- 14
/
begin ut.run('test_uc_ai_workflow_mapping'); end;        -- 33
/
begin ut.run('test_uc_ai_agent_session_meta'); end;      -- 28
/
begin ut.run('test_uc_ai_agent_validation'); end;        -- 41
/
begin ut.run('test_uc_ai_hook'); end;                    -- 12
/
begin ut.run('test_uc_ai_wire'); end;                    -- 24
/
begin ut.run('test_uc_ai_wire_2'); end;                  -- 22 (5 disabled: known bugs, see the spec)
/
begin ut.run('test_uc_ai_wire_3'); end;                  -- 17
/
begin ut.run('test_uc_ai_anthropic_wire'); end;          -- 13
/
begin ut.run('test_uc_ai_google_wire'); end;             -- 13
/
begin ut.run('test_uc_ai_openai_wire'); end;             --  7
/
begin ut.run('test_uc_ai_responses_wire'); end;          -- 13
/
begin ut.run('test_uc_ai_oci_wire'); end;                -- 14
/
begin ut.run('test_uc_ai_ollama_wire'); end;             --  8
/
begin ut.run('test_uc_ai_tools_wire'); end;              -- 11
/
begin ut.run('test_uc_ai_spec_wire'); end;               --  5
/
```

The last two do call `execute_agent`, but only on an agent that must fail first —
uncommitted, or pointing at a missing prompt profile — so no provider is reached.

**Do not** put these in the LLM-free set: `test_uc_ai_prompt_profiles_api` calls
`execute_profile` 25 times, and every `test_uc_ai_agent_*` suite not named above
(profile, orchestrator, conversation, handoff, integration, checkpoint, plsql_step)
runs real profiles. `test_uc_ai_ptc` needs 23ai plus an installed code-mode sandbox
and is LLM-backed too.

Then **cherry-pick a few LLM-backed tests** for spot coverage (do not run full provider suites — they're slow and expensive):

- `test_uc_ai_callback` — exercises the event callback system
- `test_uc_ai_openai_chat.basic_recipe` and `test_uc_ai_openai_responses.test_simple_string_input`
- `test_uc_ai_anthropic.basic_recipe` (or latest haiku model test)
- One test from each other provider you have keys for (google, xai, oci, ollama, openrouter)

For each failure, triage honestly:

| Failure type | Action |
|---|---|
| Test fixture mismatch (e.g. hardcoded error code, stale model name) | Update the test |
| Real code bug (fires wrong events, off-by-one check, state leak) | Fix in `src/`, rerun |
| Transient provider error ("high demand", 429, 5xx) | Retry once; if persistent, note in report and skip |
| Missing credential (APEX web credential not configured locally) | Skip and note — not a release blocker |
| Model retired by provider (404) | Update the test to a currently supported model and add the new one to the provider spec if missing |

Known recurring patterns worth remembering:

- **State leaks between tests**: `uc_ai.reset_globals` is **not** automatically called between tests. If a test suite changes something (reasoning on/off, `g_max_tokens`, `g_base_url`), later tests inherit it. Fix: change the suite's `%beforeall` to `%beforeeach` and call `uc_ai.reset_globals` there.
- **Responses API vs Chat API parity**: when adding events or new output processing, verify the feature fires/works on **both** paths. `uc_ai_responses_api.pkb` and each provider's chat path are separate code.
- **Provider base URL overrides**: the xAI/OpenRouter branches in `uc_ai.pkb` mutate `g_base_url` and `g_provider_override`. Any code there must save/restore both (including in `exception when others` blocks) or later provider calls leak to the wrong host.
- **Annotation spacing is fine, adjacency is not.** `-- %suite` with a space between `--` and `%` registers normally (verified on utPLSQL against 26ai). What does break a test is a comment **between** `--%test` and the procedure declaration — that detaches the annotation and utPLSQL skips the test silently. See the warning in `test/test_uc_ai_agent_workflow.pks`.

### 7. Update documentation

Walk through these doc locations for every release:

- **New feature → new guide page** under `docs/src/content/docs/guides/`. Pick a `sidebar: order:` that fits (existing guides are 1, 20, 30, 40, 50, 55, 60, 70, 900).
- **New API package → new reference page** under `docs/src/content/docs/api/`.
- **Default behavior changed in a provider** → add/update section in that provider's page under `docs/src/content/docs/providers/`.
- **New tool/function in an existing package** → update the relevant guide (e.g. tools, prompt-profiles).
- **New model constants** → add to the relevant `docs/src/content/docs/providers/<name>.mdx` models section.

Then the **release history** entry at the top of [docs/src/content/docs/other/release-history.mdx](docs/src/content/docs/other/release-history.mdx):

- Group using the buckets from step 1 (Features, Fixes, New models, …).
- **Link to the relevant doc page** from each bullet that introduces something new — the section headers themselves can be links (`[Tools API](/products/uc-ai/docs/guides/tools/#...)`). This is how v26.1 and v26.2 are structured.
- Use the `/products/uc-ai/docs/...` URL prefix (that's the deployed path).

### 7b. Sync the consumer skills in `skills/`

The top-level `skills/` directory ships Claude Code skills for library consumers (`uc-ai-quickstart`, `uc-ai-tools`, …). They quote real signatures and constants, so drift breaks them:

- For every guide page touched in step 7, update the corresponding skill (mapping is in `skills/README.md`).
- New/changed public signatures, globals, or error codes in `uc_ai*.pks` → update the skill that quotes them (`grep -rn "<identifier>" skills/`).
- New model constants → refresh example model constants in `skills/` (the update-models skill's checklist also covers this).
- New provider → add it to the provider table in `skills/uc-ai-quickstart/SKILL.md` and to frontmatter descriptions that enumerate providers.

### 8. Build the docs site

```bash
cd docs && bun run build 2>&1 | grep -iE "invalid|error" | head -30
```

Any link validator failures need to be fixed before release.

### 9. Final regen pass

Rerun all `generate_*.sh` scripts once more after any package changes made during test triage or audits. Commit the regenerated `install_uc_ai.sql`, `upgrade_packages.sql`, `install_uc_ai_complete*.sql`, `uninstall.sql`, and `src/packages/uc_ai_utils.pkb` alongside the code changes.

## Do not

- Do not create a git tag, draft a GitHub release, or push to `main` unless explicitly asked — the user does that separately.
- Do not skip failing tests without triage. If a test fails, figure out why before deciding it's "transient".
- Do not write release notes that just restate commit subjects. Explain *what changed for users* and *link to the docs*.
- Do not delete deprecated model constants even if they 404 on the provider side — users may still reference them. Update tests to use current models instead.
