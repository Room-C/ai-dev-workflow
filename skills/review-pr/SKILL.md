---
name: rc:review-pr
description: 自动化 PR Code Review — 先立即审查，仅在发现问题时启动后续跟踪循环。
argument-hint: "[PR-number] [--model sonnet|opus|haiku]"
allowed-tools: Bash, Read, Agent, CronCreate, CronDelete
model: sonnet
---

# Auto PR Review

先立即执行一次审查。若无问题直接通过；若发现问题，启动定时跟踪循环（最多 5 轮）直到全部解决。

具体审查逻辑由 `agents/workflow/pr-reviewer.md` 实现。本 Skill 只负责**编排**：解析参数、首轮调用、判断是否启动循环、创建/取消 Cron 任务。

## 模型策略

- **首轮审查 (`first_review`)**：使用 `--model` 指定（默认 sonnet）。产出首次 inline comments，用户等待反馈，控制成本。
- **跟踪循环 (`follow_up`)**：**固定 opus**。修复阶段涉及代码变更，质量敏感，值得高模型。配合变更门控（见 Agent Step 0.4），大多数 tick 是 <1k token 的廉价 SKIP，只有真需要改代码时才触发昂贵路径。

## 使用方式

```
rc:review-pr                       # 最新 open PR，首轮 sonnet
rc:review-pr 42                    # 指定 PR #42
rc:review-pr 42 --model opus       # 首轮也用 opus
```

---

## Step 1: 解析参数 + 获取 PR 信息

1. 从 `$ARGUMENTS` 提取 PR 号（纯数字）和 `--model <model>` 参数
2. 若未指定 PR 号：`gh pr list --state open --limit 1 --json number,headRefName,baseRefName`
   - 无 open PR → 输出 "No open PR found." 并结束
3. 获取 repo：`gh repo view --json nameWithOwner -q '.nameWithOwner'`
4. 记录：`pr_number`、`head_branch`、`base_branch`、`repo`、`first_review_model`

## Step 2: 首轮审查

使用 Agent 工具调用 `ai-dev-workflow:workflow:pr-reviewer`，设置 `model` 为 `first_review_model`，传入参数：

```
mode: first_review
pr_number, repo, head_branch, base_branch
```

不传 `state_file`（首轮不需要）。

## Step 3: 根据返回信号决定下一步

| Agent 返回 | 处理 |
|-----------|------|
| `REVIEW_CLEAN` | `gh api` 提交 `✅ 自动审查通过` comment + macOS 通知 + **结束**（不创建 Cron） |
| `REVIEW_MANUAL_ONLY` | 提交"⏸️ 全部为人工决策项，等您处理完后手动重跑 rc:review-pr"总结 comment + 通知 + **结束**（不创建 Cron，轮询无法推进 manual 项） |
| `REVIEW_FIXED` | 创建状态文件（含 baseline）+ 创建 Cron 任务（见 Step 4） |
| `REVIEW_MANUAL` | 创建状态文件（含 baseline）+ 创建 Cron 任务 |

**状态文件必须包含变更门控基线**，避免第一次 Cron tick 做重复工作：

```bash
STATE_FILE="/tmp/.review-state-<N>.json"

# 捕获 baseline：首轮审查时的 HEAD SHA + comment/review 计数
META=$(gh pr view <N> --json headRefOid,comments,reviews) || {
  echo "ERROR: cannot fetch baseline for Cron gating"; exit 1;
}
HEAD_SHA=$(echo "$META" | jq -r '.headRefOid')
COMMENT_COUNT=$(echo "$META" | jq -r '.comments | length')
REVIEW_COUNT=$(echo "$META" | jq -r '.reviews | length')

STATE_JSON=$(jq -n \
  --argjson pr <N> \
  --argjson max 6 \
  --arg sha "$HEAD_SHA" \
  --argjson c "$COMMENT_COUNT" \
  --argjson v "$REVIEW_COUNT" \
  '{pr:$pr, round:1, maxRounds:$max, lastSha:$sha, lastCommentCount:$c, lastReviewCount:$v}')

if ! printf '%s' "$STATE_JSON" > "$STATE_FILE"; then
  echo "ERROR: cannot write $STATE_FILE — refusing to schedule Cron without durable state." >&2
  exit 1
fi
[ -s "$STATE_FILE" ] || { echo "ERROR: state file empty after write."; exit 1; }
```

## Step 4: 创建跟踪 Cron（仅 Step 3 需要时）

使用 `CronCreate` 创建 5 分钟间隔任务，prompt 为：

```
调用 ai-dev-workflow:workflow:pr-reviewer agent（model: opus）执行后续跟踪审查。
参数：
  mode: follow_up
  pr_number: <N>
  repo: <owner/name>
  head_branch: <...>
  base_branch: <...>
  state_file: /tmp/.review-state-<N>.json

根据 agent 返回信号处理：
- REVIEW_DONE / REVIEW_STOPPED → CronDelete 取消本任务 + 删除状态文件
- REVIEW_SKIPPED → 本轮无任何变更（便宜路径已执行），保留 Cron 等下一轮
- REVIEW_FIXED / REVIEW_MANUAL → 保留 Cron 等下一轮验证
```

---

## 边界

- **首轮永远直接执行**，不经过 Cron（用户等待反馈的常见路径）
- **Cron 仅在发现 agent 可推进的问题时创建**（FIXED / MANUAL 混合），manual-only 不启动
- **follow_up 固定用 opus**，修复质量优先；配合 Step 0.4 的 cheap gating，成本可控
- 所有具体审查/修复逻辑在 `pr-reviewer` Agent 中，本 Skill 不做审查判断
