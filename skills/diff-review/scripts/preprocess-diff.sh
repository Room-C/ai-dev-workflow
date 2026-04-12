#!/usr/bin/env bash
# preprocess-diff.sh — Deterministic diff preprocessing for diff-review skill
# Outputs JSON with diff metadata, reducing AI token consumption.
#
# Usage: preprocess-diff.sh <target-branch> [--since <commit>] [--path <filter>]
#
# Output JSON fields:
#   has_changes, diff_range, filtered_files, stats, modules, file_types, commit_summary

set -euo pipefail

TARGET_BRANCH="${1:-main}"
SINCE_COMMIT=""
PATH_FILTER=""

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE_COMMIT="$2"; shift 2 ;;
    --path)  PATH_FILTER="$2"; shift 2 ;;
    *)       shift ;;
  esac
done

# Determine diff range
if [[ -n "$SINCE_COMMIT" ]]; then
  DIFF_RANGE="${SINCE_COMMIT}...HEAD"
else
  DIFF_RANGE="${TARGET_BRANCH}...HEAD"
fi

# Noise filter patterns (lockfiles, generated, migrations, minified, pbxproj)
EXCLUDE_PATTERNS=(
  ':!*.lock'
  ':!*-lock.json'
  ':!*-lock.yaml'
  ':!*.generated.*'
  ':!*.g.dart'
  ':!*.freezed.dart'
  ':!*/migrations/*'
  ':!*.min.js'
  ':!*.min.css'
  ':!*.pbxproj'
)

# Build path args
PATH_ARGS=("--")
if [[ -n "$PATH_FILTER" ]]; then
  PATH_ARGS+=("$PATH_FILTER")
fi
PATH_ARGS+=("${EXCLUDE_PATTERNS[@]}")

# Check for changes
CHANGED_FILES=$(git diff "$DIFF_RANGE" --name-only "${PATH_ARGS[@]}" 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
  cat <<EOF
{"has_changes":false,"diff_range":"$DIFF_RANGE","filtered_files":[],"stats":{"files":0,"additions":0,"deletions":0},"modules":[],"file_types":{},"commit_summary":[]}
EOF
  exit 0
fi

# Stats
STAT_LINE=$(git diff "$DIFF_RANGE" --shortstat "${PATH_ARGS[@]}" 2>/dev/null || echo "")
FILES_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
ADDITIONS=$(echo "$STAT_LINE" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
DELETIONS=$(echo "$STAT_LINE" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")

# Filtered files as JSON array
FILES_JSON=$(echo "$CHANGED_FILES" | jq -R -s 'split("\n") | map(select(length > 0))')

# Modules (top-level directories)
MODULES_JSON=$(echo "$CHANGED_FILES" | awk -F/ '{print $1}' | sort -u | jq -R -s 'split("\n") | map(select(length > 0))')

# File types
FILE_TYPES_JSON=$(echo "$CHANGED_FILES" | sed 's/.*\.//' | sort | uniq -c | sort -rn | awk '{printf "\"%s\":%d,", $2, $1}' | sed 's/,$//' | sed 's/^/{/' | sed 's/$/}/')
# Handle empty case
if [[ "$FILE_TYPES_JSON" == "{}" ]] || [[ -z "$FILE_TYPES_JSON" ]]; then
  FILE_TYPES_JSON="{}"
fi

# Commit summary (recent commits in range)
COMMIT_SUMMARY_JSON=$(git log "$DIFF_RANGE" --oneline --max-count=20 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')

cat <<EOF
{"has_changes":true,"diff_range":"$DIFF_RANGE","filtered_files":$FILES_JSON,"stats":{"files":$FILES_COUNT,"additions":$ADDITIONS,"deletions":$DELETIONS},"modules":$MODULES_JSON,"file_types":$FILE_TYPES_JSON,"commit_summary":$COMMIT_SUMMARY_JSON}
EOF
