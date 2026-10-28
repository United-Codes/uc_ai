#!/bin/bash

# Tests upgrade_uc_ai.sql against the throwaway schema of local-26ai.sh.
#
# For every baseline tag the script installs that release into a clean schema,
# runs the upgrade, and then checks three things:
#   1. the schema equals the schema of a fresh install of the working tree,
#   2. a second run changes nothing ("Nothing to change"),
#   3. no object is invalid.
# A backfill case seeds runs into a v26.2 schema and checks the one-time data
# steps. A last case damages a freshly installed schema (drops columns, a constraint, an
# index) and checks that the upgrade heals it. The verify phase must pass on every
# run, and must report the objects of a damaged schema when it runs on its own.
#
# Usage: scripts/test_upgrade.sh [tag ...]     (make test-upgrade TAGS="v26.3")
# Default tags: v25.7 v26.1 v26.2 v26.3 v26.4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONN="${TEST_CONN:-local-23ai-uc_testinstall_1}"
WORK_DIR="$(mktemp -d /tmp/uc_ai_upgrade_test.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ $# -gt 0 ]; then
    TAGS=("$@")
else
    TAGS=(v25.7 v26.1 v26.2 v26.3 v26.4)
fi

cd "$ROOT_DIR"

fail() {
    echo "FAIL: $*"
    exit 1
}

# Run a SQL file in the test schema and print its output.
run_sql() {
    sql -name "$CONN" "@$1" < /dev/null
}

snapshot() {
    # $1 = output file
    # SQLcl pads each line to the width of the widest value, which differs per run
    run_sql "$SCRIPT_DIR/test_upgrade_snapshot.sql" | grep -E '^[A-Z_]+\|' \
        | sed 's/[[:space:]]*$//' | sort > "$1"
}

install_into_clean_schema() {
    # $1 = install script (absolute path)
    local-26ai.sh test-script-install "$1" -y > "$WORK_DIR/install.log" 2>&1 \
        || { tail -30 "$WORK_DIR/install.log"; fail "install of $1"; }
}

run_upgrade() {
    # $1 = log file
    sql -name "$CONN" > "$1" 2>&1 <<SQL
set serveroutput on size unlimited
@$ROOT_DIR/upgrade_uc_ai.sql
exit
SQL
    if grep -q 'UPGRADE STOPPED' "$1"; then
        grep -B2 -A4 'UPGRADE STOPPED' "$1"
        fail "upgrade stopped ($1)"
    fi
    if ! grep -q '^Verified: ' "$1"; then
        grep -E 'WARNING|ORA-' "$1" | head -20
        fail "verify phase did not pass ($1)"
    fi
    grep -q 'UC AI upgrade complete' "$1" || fail "upgrade did not reach its end ($1)"
}

check_invalid() {
    # $1 = label
    local out
    out=$(sql -name "$CONN" <<SQL
set pagesize 0 feedback off heading off
select object_type || ' ' || object_name from user_objects where status = 'INVALID';
exit
SQL
    )
    if echo "$out" | grep -qE '^[A-Z ]+ [A-Z_0-9$]+$'; then
        echo "$out"
        fail "$1: invalid objects"
    fi
}

compare() {
    # $1 = label, $2 = expected snapshot, $3 = actual snapshot
    if ! diff "$2" "$3" > "$WORK_DIR/diff.txt"; then
        echo "---- $1: snapshot differs (< fresh install, > upgraded schema)"
        head -60 "$WORK_DIR/diff.txt"
        fail "$1: schema differs from a fresh install"
    fi
}

echo "== Generating scripts from the working tree"
bash scripts/generate_install_script_complete.sh > /dev/null
bash scripts/generate_upgrade_script.sh > /dev/null

echo "== Fresh install of the working tree (reference)"
install_into_clean_schema "$ROOT_DIR/install_uc_ai_complete_with_logger.sql"
snapshot "$WORK_DIR/fresh.snap"
[ -s "$WORK_DIR/fresh.snap" ] || fail "reference snapshot is empty"

echo "== Upgrade on an up-to-date schema changes nothing"
run_upgrade "$WORK_DIR/noop.log"
grep -q 'Nothing to change' "$WORK_DIR/noop.log" || fail "up-to-date schema: expected 'Nothing to change'"
snapshot "$WORK_DIR/noop.snap"
compare "up-to-date schema" "$WORK_DIR/fresh.snap" "$WORK_DIR/noop.snap"
check_invalid "up-to-date schema"

for tag in "${TAGS[@]}"; do
    echo "== Upgrade from $tag"
    tag_dir="$WORK_DIR/src_$tag"
    mkdir -p "$tag_dir"
    git archive "$tag" | tar -x -C "$tag_dir"
    (cd "$tag_dir" && bash scripts/generate_install_script_complete.sh > /dev/null)
    install_into_clean_schema "$tag_dir/install_uc_ai_complete_with_logger.sql"

    run_upgrade "$WORK_DIR/upgrade_$tag.log"
    grep -E '^(  |v2)' "$WORK_DIR/upgrade_$tag.log" | head -40 || true
    snapshot "$WORK_DIR/after_$tag.snap"
    compare "from $tag" "$WORK_DIR/fresh.snap" "$WORK_DIR/after_$tag.snap"
    check_invalid "from $tag"

    run_upgrade "$WORK_DIR/second_$tag.log"
    grep -q 'Nothing to change' "$WORK_DIR/second_$tag.log" \
        || { grep -E '^  ' "$WORK_DIR/second_$tag.log"; fail "from $tag: second run changed the schema"; }
    snapshot "$WORK_DIR/second_$tag.snap"
    compare "from $tag, second run" "$WORK_DIR/fresh.snap" "$WORK_DIR/second_$tag.snap"
    echo "   ok: $tag"
done

echo "== Backfill: existing runs get sessions and messages, exactly once"
backfill_tag="v26.2"
tag_dir="$WORK_DIR/src_$backfill_tag"
if [ ! -d "$tag_dir" ]; then
    mkdir -p "$tag_dir"
    git archive "$backfill_tag" | tar -x -C "$tag_dir"
    (cd "$tag_dir" && bash scripts/generate_install_script_complete.sh > /dev/null)
fi
install_into_clean_schema "$tag_dir/install_uc_ai_complete_with_logger.sql"
sql -name "$CONN" > "$WORK_DIR/seed.log" 2>&1 <<SQL
insert into uc_ai_agents (code, description, agent_type, workflow_definition, status)
values ('UPGRADE_TEST_WF', 'seed', 'workflow', '{}', 'active');
insert into uc_ai_agents (code, description, agent_type, prompt_profile_code, status)
values ('UPGRADE_TEST_PROFILE', 'seed', 'profile', 'SEED', 'active');
insert into uc_ai_agent_executions (id, agent_id, session_id, status, total_input_tokens, total_output_tokens, completed_at, output_result)
select 9001, id, 'UPGRADE_S1', 'completed', 100, 50, systimestamp,
       '{"messages":[{"role":"user","content":"hi"},{"role":"assistant","content":[{"type":"text","text":"hello"}]}]}'
  from uc_ai_agents where code = 'UPGRADE_TEST_WF';
insert into uc_ai_agent_executions (id, agent_id, parent_execution_id, session_id, status, total_input_tokens, total_output_tokens, completed_at)
select 9002, id, 9001, 'UPGRADE_S1', 'completed', 100, 50, systimestamp
  from uc_ai_agents where code = 'UPGRADE_TEST_PROFILE';
commit;
exit
SQL
grep -qE 'ORA-|SP2-' "$WORK_DIR/seed.log" && { cat "$WORK_DIR/seed.log"; fail "could not seed the $backfill_tag schema"; }

run_upgrade "$WORK_DIR/backfill.log"
backfill_result() {
    sql -name "$CONN" <<SQL | grep -E '^RESULT' | sed 's/[[:space:]]*$//'
set pagesize 0 feedback off heading off linesize 200
select 'RESULT|' || s.turn_count || '|' || s.message_count || '|' || s.total_input_tokens
       || '|' || (select count(*) from uc_ai_agent_messages m where m.session_id = s.session_id)
       || '|' || (select total_input_tokens from uc_ai_agent_executions where id = 9001)
       || '|' || (select turn_index from uc_ai_agent_executions where id = 9001)
  from uc_ai_agent_sessions s where s.session_id = 'UPGRADE_S1';
exit
SQL
}
# turns | message_count | session input tokens | message rows | parent tokens | parent turn_index
[ "$(backfill_result)" = "RESULT|1|2|100|2|0|1" ] \
    || fail "backfill: expected RESULT|1|2|100|2|0|1, got $(backfill_result)"

# The parent now holds its own tokens. A second run must not zero them again.
sql -name "$CONN" > /dev/null 2>&1 <<SQL
update uc_ai_agent_executions set total_input_tokens = 7 where id = 9001;
commit;
exit
SQL
run_upgrade "$WORK_DIR/backfill_second.log"
grep -q 'Nothing to change' "$WORK_DIR/backfill_second.log" || fail "backfill: second run changed the schema"
[ "$(backfill_result)" = "RESULT|1|2|100|2|7|1" ] \
    || fail "backfill: second run touched the data, got $(backfill_result)"
echo "   ok: backfill"

echo "== Upgrade heals a damaged schema"
install_into_clean_schema "$ROOT_DIR/install_uc_ai_complete_with_logger.sql"
sql -name "$CONN" > "$WORK_DIR/damage.log" 2>&1 <<SQL
alter table uc_ai_agent_executions drop column audience;
alter table uc_ai_agent_executions drop column updated_at;
alter table uc_ai_agent_sessions drop column feedback_rating cascade constraints;
alter table uc_ai_agent_messages drop column tool_call_id;
alter table uc_ai_agents drop column decision_config cascade constraints;
alter table uc_ai_memory_config drop constraint uc_ai_memory_config_ctx_ck;
alter table uc_ai_tools drop constraint uc_ai_tools_cma_ck;
drop index uc_ai_agent_exec_apex_sess_idx;
drop trigger uc_ai_agent_executions_biu;
exit
SQL
grep -qE 'ORA-|SP2-' "$WORK_DIR/damage.log" && { cat "$WORK_DIR/damage.log"; fail "could not damage the schema"; }
run_upgrade "$WORK_DIR/heal.log"
snapshot "$WORK_DIR/heal.snap"
compare "damaged schema" "$WORK_DIR/fresh.snap" "$WORK_DIR/heal.snap"
check_invalid "damaged schema"
echo "   ok: damaged schema"

echo "== Verify phase reports what an upgrade step missed"
# Only the verify phase runs here, so nothing heals the damage.
sed -n '/^-- VERIFY START$/,/^-- VERIFY END$/p' "$ROOT_DIR/upgrade_uc_ai.sql" > "$WORK_DIR/verify.sql"
[ -s "$WORK_DIR/verify.sql" ] || fail "upgrade_uc_ai.sql has no verify phase"
sql -name "$CONN" > "$WORK_DIR/verify.log" 2>&1 <<SQL
alter table uc_ai_agent_messages drop column tool_call_id;
drop index uc_ai_agent_exec_apex_sess_idx;
alter table uc_ai_tools drop constraint uc_ai_tools_cma_ck;
set serveroutput on size unlimited
@$WORK_DIR/verify.sql
exit
SQL
for expected in 'WARNING missing column uc_ai_agent_messages.tool_call_id' \
                'WARNING missing index uc_ai_agent_exec_apex_sess_idx' \
                'WARNING missing constraint uc_ai_tools_cma_ck' \
                'ORA-20000: 3 object(s) of a fresh install are missing'; do
    grep -qF "$expected" "$WORK_DIR/verify.log" || { cat "$WORK_DIR/verify.log"; fail "verify phase: expected '$expected'"; }
done
echo "   ok: verify phase"

echo ""
echo "All upgrade tests passed."
