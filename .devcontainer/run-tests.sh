#!/usr/bin/env sh
# Run the index and zero-downtime e2e test flows locally (mirrors ci.yml).
# Usage: .devcontainer/run-tests.sh [index|zero_downtime]   (default: both)
set -eu
cd "$(dirname "$0")/.."

# CI runs each dbt step with a pristine environment containing only the one
# variable it declares. Locally the script inherits your shell, so a stale
# `export DBT_RW_*` from an earlier run would silently leak into a step that
# doesn't set it. Clear them up front, and again on exit so nothing is left
# behind (also covers the case where this script is sourced rather than run).
TEST_ENV_VARS="DBT_RW_INDEX_STAGE DBT_RW_INDEX_EXPECT_STAGE DBT_RW_ZERO_DOWNTIME_STAGE DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE DBT_RW_ZERO_DOWNTIME_EXPECT_TEMP_CLEANED"
cleanup_env() { unset $TEST_ENV_VARS 2>/dev/null || true; }

# Colours, only when stdout is a terminal (so piping to a file stays clean).
if [ -t 1 ]; then
	C_GREEN=$(printf '\033[32m'); C_RED=$(printf '\033[31m'); C_DIM=$(printf '\033[2m'); C_OFF=$(printf '\033[0m')
else
	C_GREEN=''; C_RED=''; C_DIM=''; C_OFF=''
fi

# Run one step with tidy output: capture its log, collapse to a single green
# line on success, and only dump the full log (indented) when it fails — so a
# failure stands out instead of being buried in a wall of dbt output. The step
# label is remembered so the exit banner can name whatever failed.
CURRENT_STEP=''
step() {
	CURRENT_STEP="$1"; shift
	step_out=$("$@" 2>&1) && step_rc=0 || step_rc=$?
	if [ "$step_rc" -eq 0 ]; then
		printf '  %s✓%s %s\n' "$C_GREEN" "$C_OFF" "$CURRENT_STEP"
	else
		printf '  %s✗ %s (exit %s)%s\n' "$C_RED" "$CURRENT_STEP" "$step_rc" "$C_OFF"
		# Strip dbt's own ANSI colours, then indent, so the dumped log reads cleanly.
		printf '%s\n' "$step_out" | sed "s/$(printf '\033')\[[0-9;]*m//g" | sed 's/^/      | /'
		return "$step_rc"
	fi
}

on_exit() {
	rc=$?
	cleanup_env
	if [ "$rc" -eq 0 ]; then
		printf '\n%s========== all steps passed ==========%s\n' "$C_GREEN" "$C_OFF"
	else
		printf '\n%s========== FAILED at: %s ==========%s\n' "$C_RED" "${CURRENT_STEP:-?}" "$C_OFF" >&2
	fi
}
trap on_exit EXIT
cleanup_env

# RisingWave connection, matching the profiles setup.sh writes and the
# DBT_HOST/DBT_PORT that docker-compose.yml sets for this container.
RW_HOST="${DBT_HOST:-risingwave}"
RW_PORT="${DBT_PORT:-4566}"
RW_USER="${DBT_USER:-root}"
RW_DBNAME="${DBT_DBNAME:-dev}"
RW_SCHEMA="${DBT_SCHEMA:-public}"

# Start each flow from an empty database, the way CI does (a fresh RisingWave
# container per job). Dropping the schema CASCADE clears every model, index and
# any leftover temp object from an interrupted run in one shot. Uses psycopg2,
# the adapter's own driver, since the image has no psql.
reset_risingwave() {
	RW_HOST="$RW_HOST" RW_PORT="$RW_PORT" RW_USER="$RW_USER" RW_DBNAME="$RW_DBNAME" RW_SCHEMA="$RW_SCHEMA" \
		python3 - <<'PY'
import os, sys
try:
    import psycopg2
    from psycopg2 import sql
except ImportError:
    sys.exit("psycopg2 not found; run inside the devcontainer (see .devcontainer/setup.sh)")
try:
    conn = psycopg2.connect(
        host=os.environ["RW_HOST"], port=int(os.environ["RW_PORT"]),
        user=os.environ["RW_USER"], password="", dbname=os.environ["RW_DBNAME"],
    )
    conn.autocommit = True
    schema = sql.Identifier(os.environ["RW_SCHEMA"])
    with conn.cursor() as cur:
        cur.execute(sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(schema))
        cur.execute(sql.SQL("CREATE SCHEMA {}").format(schema))
except Exception as e:
    sys.exit("failed to reset RisingWave: %s" % e)
PY
}

run_indexes() {
	echo "========== indexes =========="
	step "reset RisingWave" reset_risingwave
	cd tests/e2e/indexes
	step "initial run"  env DBT_RW_INDEX_STAGE=initial dbt run --full-refresh
	step "initial test" env DBT_RW_INDEX_EXPECT_STAGE=initial dbt test
	step "changed run"  env DBT_RW_INDEX_STAGE=changed dbt run
	step "changed test" env DBT_RW_INDEX_EXPECT_STAGE=changed dbt test
	cd - >/dev/null
}

run_zero_downtime() {
	echo "========== zero_downtime =========="
	step "reset RisingWave" reset_risingwave
	cd tests/e2e/zero_downtime
	step "initial run"         env DBT_RW_ZERO_DOWNTIME_STAGE=initial dbt run --full-refresh
	step "initial test"        env DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE=initial dbt test
	step "zero-downtime swap"  env DBT_RW_ZERO_DOWNTIME_STAGE=changed dbt run --vars '{zero_downtime: true}'
	step "cleanup temp objects" dbt run-operation cleanup_temp_objects
	step "changed test"        env DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE=changed DBT_RW_ZERO_DOWNTIME_EXPECT_TEMP_CLEANED=true dbt test
	cd - >/dev/null
}

case "${1:-both}" in
	index)         run_indexes ;;
	zero_downtime) run_zero_downtime ;;
	both)          run_indexes; run_zero_downtime ;;
	*) echo "Usage: $0 [index|zero_downtime|both]" >&2; exit 2 ;;
esac
