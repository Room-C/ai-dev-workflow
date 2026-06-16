#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
LOG_DIR="$TMP_HOME/logs"

cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$LOG_DIR"

echo "== skills discovery"
LIST_OUTPUT="$(npx --yes skills add "$ROOT" --list)"
printf '%s\n' "$LIST_OUTPUT"
printf '%s\n' "$LIST_OUTPUT" | grep -q "Found 13 skills"

echo "== copy install: codex / single complex skills"
HOME="$TMP_HOME" npx --yes skills add "$ROOT" -g -a codex --skill rc:feature-design --copy -y >"$LOG_DIR/install-feature-design.log"
test -f "$TMP_HOME/.agents/skills/rc-feature-design/SKILL.md"
test -f "$TMP_HOME/.agents/skills/rc-feature-design/references/agents/analyst.md"
test -f "$TMP_HOME/.agents/skills/rc-feature-design/references/agents/coherence-reviewer.md"

HOME="$TMP_HOME" npx --yes skills add "$ROOT" -g -a codex --skill rc:diff-review --copy -y >"$LOG_DIR/install-diff-review.log"
test -f "$TMP_HOME/.agents/skills/rc-diff-review/SKILL.md"
test -f "$TMP_HOME/.agents/skills/rc-diff-review/scripts/preprocess-diff.sh"
test -f "$TMP_HOME/.agents/skills/rc-diff-review/scripts/baseline-verify.sh"
test -f "$TMP_HOME/.agents/skills/rc-diff-review/scripts/record-outcome.sh"
test -f "$TMP_HOME/.agents/skills/rc-diff-review/references/agents/diff-reviewer.md"
test -f "$TMP_HOME/.agents/skills/rc-diff-review/references/shared/compound-schema.md"

echo "== copy install: claude-code / single complex skill"
HOME="$TMP_HOME" npx --yes skills add "$ROOT" -g -a claude-code --skill rc:review-pr --copy -y >"$LOG_DIR/install-review-pr.log"
find "$TMP_HOME" -path "*/rc-review-pr/SKILL.md" -print -quit | grep -q .
find "$TMP_HOME" -path "*/rc-review-pr/references/agents/pr-reviewer.md" -print -quit | grep -q .
find "$TMP_HOME" -path "*/rc-review-pr/scripts/pr-diff-filter.sh" -print -quit | grep -q .
find "$TMP_HOME" -path "*/rc-review-pr/scripts/notify.sh" -print -quit | grep -q .
find "$TMP_HOME" -path "*/rc-review-pr/scripts/record-outcome.sh" -print -quit | grep -q .

echo "== copy install: codex / branch-create"
HOME="$TMP_HOME" npx --yes skills add "$ROOT" -g -a codex --skill rc-branch-create --copy -y >"$LOG_DIR/install-branch-create.log"
test -f "$TMP_HOME/.agents/skills/rc-branch-create/SKILL.md"
test -x "$TMP_HOME/.agents/skills/rc-branch-create/scripts/branch-create.sh"

echo "== copy install: codex / all skills"
HOME="$TMP_HOME" npx --yes skills add "$ROOT" -g -a codex --skill '*' --copy -y >"$LOG_DIR/install-all.log"
INSTALLED_COUNT="$(find "$TMP_HOME/.agents/skills" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
test "$INSTALLED_COUNT" = "13"

echo "== portability grep"
if grep -rE '\.claude/plugins/cache|codex-companion|disable-model-invocation' skills/*/SKILL.md skills/*/references skills/*/scripts agents; then
  echo "ERROR: hard-coded legacy host dependency found in runtime docs." >&2
  exit 1
fi

echo "Package validation passed."
