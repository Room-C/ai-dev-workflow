#!/usr/bin/env bash
#
# record-outcome.sh — 记录 Skill 执行结果到遥测日志
#
# 用法:
#   record-outcome.sh <skill-name> <status> [failure-step] [failure-reason] [fallback-used]
#
# 参数:
#   skill-name      技能名称，如 diff-review、feature-execute
#   status          执行状态: success | partial | failed
#   failure-step    (可选) 失败发生在哪一步，如 3a、Step4
#   failure-reason  (可选) 失败原因简述，如 codex_stream_disconnected
#   fallback-used   (可选) 使用了哪个降级方案，如 3b_agent
#
# 输出:
#   追加一行 JSON 到 ~/.ai-dev-workflow/telemetry.jsonl
#
# 示例:
#   record-outcome.sh diff-review success
#   record-outcome.sh diff-review partial 3a codex_stream_disconnected 3b_agent
#   record-outcome.sh feature-execute failed Step4 lint_verification_failed

set -euo pipefail

SKILL_NAME="${1:?Usage: record-outcome.sh <skill-name> <status> [failure-step] [failure-reason] [fallback-used]}"
STATUS="${2:?Usage: record-outcome.sh <skill-name> <status> [failure-step] [failure-reason] [fallback-used]}"
FAILURE_STEP="${3:-}"
FAILURE_REASON="${4:-}"
FALLBACK_USED="${5:-}"

# 验证 status
case "$STATUS" in
  success|partial|failed) ;;
  *) echo "Error: status must be success|partial|failed, got: $STATUS" >&2; exit 1 ;;
esac

# 推断项目名称（git repo 根目录名）
PROJECT_NAME=""
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$REPO_ROOT" ]; then
  PROJECT_NAME=$(basename "$REPO_ROOT")
fi

# 确保目录存在
TELEMETRY_DIR="$HOME/.ai-dev-workflow"
mkdir -p "$TELEMETRY_DIR"
TELEMETRY_FILE="$TELEMETRY_DIR/telemetry.jsonl"

# 生成 ISO 8601 时间戳
TS=$(date +"%Y-%m-%dT%H:%M:%S%z")

# 构建 JSON（用 printf 避免依赖 jq）
JSON="{"
JSON+="\"ts\":\"${TS}\""
JSON+=",\"skill\":\"${SKILL_NAME}\""
JSON+=",\"project\":\"${PROJECT_NAME}\""
JSON+=",\"status\":\"${STATUS}\""
[ -n "$FAILURE_STEP" ]  && JSON+=",\"failure_step\":\"${FAILURE_STEP}\""
[ -n "$FAILURE_REASON" ] && JSON+=",\"failure_reason\":\"${FAILURE_REASON}\""
[ -n "$FALLBACK_USED" ]  && JSON+=",\"fallback_used\":\"${FALLBACK_USED}\""
JSON+="}"

# 追加到日志
echo "$JSON" >> "$TELEMETRY_FILE"
echo "Telemetry recorded: $SKILL_NAME ($STATUS)"
