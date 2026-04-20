#!/usr/bin/env bash
# baseline-verify.sh — Run lint/typecheck/test on base commit to establish pre-existing failure baseline.
#
# Usage:
#   baseline-verify.sh <base-ref> <output-json> [--lint CMD] [--typecheck CMD] [--test CMD]
#
# Behavior:
#   1. Stash current working tree (including untracked).
#   2. Checkout <base-ref> in detached HEAD mode.
#   3. Run each provided command, capturing failures.
#   4. Restore original HEAD and pop stash.
#   5. Write failures to <output-json>.
#
# Output JSON shape:
#   {
#     "base_ref": "abc123",
#     "timestamp": "2026-04-20T12:00:00+0800",
#     "missing": false,
#     "failures": {
#       "lint":      ["rule X at file:line", ...],
#       "typecheck": ["error at file:line: ...", ...],
#       "test":      ["test_name failed", ...]
#     },
#     "raw_logs_dir": ".rounds/baseline-logs"
#   }
#
# If no commands are provided, writes {"missing": true, "failures": {}} so the caller knows
# to treat all post-fix failures as "introduced by this round".
#
# Exit codes:
#   0 — baseline established (including missing=true case)
#   1 — fatal: cannot stash / cannot checkout / cannot restore

set -euo pipefail

BASE_REF="${1:?Usage: baseline-verify.sh <base-ref> <output-json> [--lint CMD] [--typecheck CMD] [--test CMD]}"
OUTPUT_JSON="${2:?output-json path required}"
shift 2

LINT_CMD=""
TYPECHECK_CMD=""
TEST_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lint)      LINT_CMD="$2"; shift 2 ;;
    --typecheck) TYPECHECK_CMD="$2"; shift 2 ;;
    --test)      TEST_CMD="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

# If no commands provided, write "missing" baseline and exit success
if [[ -z "$LINT_CMD" && -z "$TYPECHECK_CMD" && -z "$TEST_CMD" ]]; then
  cat > "$OUTPUT_JSON" <<EOF
{"base_ref":"$BASE_REF","missing":true,"failures":{},"raw_logs_dir":""}
EOF
  echo "baseline-verify: no commands provided — marking baseline.missing = true" >&2
  exit 0
fi

# Ensure we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: not in a git repository" >&2
  exit 1
fi

# Resolve base ref to a SHA (fail fast on typos)
BASE_SHA=$(git rev-parse --verify "$BASE_REF" 2>/dev/null) || {
  echo "ERROR: cannot resolve base ref: $BASE_REF" >&2
  exit 1
}

# Remember where we are
ORIG_REF=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse HEAD)

# Prepare logs dir next to output json
LOGS_DIR="$(dirname "$OUTPUT_JSON")/baseline-logs"
mkdir -p "$LOGS_DIR"

# Stash everything (including untracked) so checkout is clean.
# Use a marker message so we can find our stash reliably even if others exist.
STASH_MSG="baseline-verify-$$-$(date +%s)"
STASH_CREATED=0
if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  if git stash push --include-untracked -m "$STASH_MSG" > /dev/null 2>&1; then
    STASH_CREATED=1
  else
    echo "ERROR: failed to stash working tree; aborting baseline" >&2
    exit 1
  fi
fi

# Ensure restoration happens on any exit path
restore_state() {
  local rc=$?
  # Return to original ref (branch if possible)
  if ! git checkout --quiet "$ORIG_REF" 2>/dev/null; then
    echo "ERROR: failed to restore original ref $ORIG_REF. Manual recovery needed." >&2
    rc=1
  fi
  # Pop stash if we created one
  if [ "$STASH_CREATED" = "1" ]; then
    local stash_ref
    stash_ref=$(git stash list | grep -F "$STASH_MSG" | head -1 | cut -d: -f1 || true)
    if [ -n "$stash_ref" ]; then
      if ! git stash pop --quiet "$stash_ref" 2>/dev/null; then
        echo "WARN: failed to pop stash $stash_ref ($STASH_MSG). Run 'git stash list' to recover." >&2
      fi
    fi
  fi
  exit "$rc"
}
trap restore_state EXIT INT TERM

# Checkout base (detached HEAD)
if ! git checkout --quiet --detach "$BASE_SHA"; then
  echo "ERROR: failed to checkout $BASE_SHA" >&2
  exit 1
fi

run_cmd() {
  local name="$1"; shift
  local cmd="$1"; shift
  local log="$LOGS_DIR/${name}.log"
  if [ -z "$cmd" ]; then
    echo "[]"
    return 0
  fi
  # Run, capture output, DO NOT fail the script if command exits non-zero (that's the signal)
  set +e
  eval "$cmd" > "$log" 2>&1
  set -e
  # Extract failure lines heuristically (tool-specific parsing left to caller for now).
  # We emit the full log path; caller (Skill) reads and diffs against post-fix run.
  # For JSON we just record whether this step had failures (non-empty last ~50 error lines).
  # Simpler: emit every non-empty line; caller does set-diff.
  jq -R -s 'split("\n") | map(select(length > 0))' "$log"
}

LINT_OUT=$(run_cmd "lint" "$LINT_CMD")
TYPECHECK_OUT=$(run_cmd "typecheck" "$TYPECHECK_CMD")
TEST_OUT=$(run_cmd "test" "$TEST_CMD")

TS=$(date +"%Y-%m-%dT%H:%M:%S%z")

# Build final JSON
jq -n \
  --arg base_ref "$BASE_SHA" \
  --arg ts "$TS" \
  --arg logs_dir "$LOGS_DIR" \
  --argjson lint "$LINT_OUT" \
  --argjson typecheck "$TYPECHECK_OUT" \
  --argjson test "$TEST_OUT" \
  '{base_ref: $base_ref, timestamp: $ts, missing: false, failures: {lint: $lint, typecheck: $typecheck, test: $test}, raw_logs_dir: $logs_dir}' \
  > "$OUTPUT_JSON"

echo "baseline-verify: wrote baseline to $OUTPUT_JSON" >&2
# trap will restore state and exit 0
