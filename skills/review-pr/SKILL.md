---
name: rc:review-pr
description: 自动化 PR Code Review — 先立即审查，仅在发现问题时启动后续跟踪循环。
argument-hint: "[PR-number] [--model sonnet|opus|haiku]"
allowed-tools: Bash, Read, Agent, CronCreate, CronDelete
model: sonnet
---

# Auto PR Review

先立即执行一次审查。若无问题直接通过；若发现问题，或当前 open PR 上已经有未闭环反馈，启动定时跟踪循环（最多 5 轮）直到全部解决。

具体审查逻辑由 bundled `references/agents/pr-reviewer.md` 实现。本 Skill 只负责**编排**：解析参数、首轮调用、判断是否启动跟踪、创建/取消 scheduler 任务。首轮不再假设 PR 一定是"刚建、无历史评论"。

## Portable Runtime

本 Skill 必须能通过 `npx skills add --copy` 单独安装后运行。运行时资源优先从当前 Skill 目录读取：

- `references/agents/pr-reviewer.md`

宿主支持子代理时，按 bundled prompt 委派；没有子代理能力时，主上下文按该 reference inline 执行。Cron/scheduler 是可选能力：没有 `CronCreate` / `CronDelete` 时，首轮照常执行，后续跟踪改为写状态文件并提示用户稍后手动重跑 `rc:review-pr <PR-number>`。

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

读取 `references/agents/pr-reviewer.md`。使用宿主 Agent 工具时按该 prompt 调用 pr-reviewer，设置 `model` 为 `first_review_model`；没有 Agent 工具时，主上下文按该 reference inline 执行。传入参数：

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
| `REVIEW_FIXED` | 创建状态文件（含 baseline）+ 如果有 scheduler 则创建跟踪任务，否则提示手动重跑 |
| `REVIEW_MANUAL` | 创建状态文件（含 baseline）+ 如果有 scheduler 则创建跟踪任务，否则提示手动重跑 |

**状态文件必须包含变更门控基线**，避免第一次 Cron tick 做重复工作：

```bash
STATE_FILE="/tmp/.review-state-<N>.json"

# 捕获 baseline：首轮审查时的 HEAD SHA + 三种 comment/review 计数
# 关键：gh pr view --json comments 只返回 issue-level（时间线），
# 必须另外拉 inline review comments（代码行内评论）以避免 gating 盲区
META=$(gh pr view <N> --json headRefOid,comments,reviews) || {
  echo "ERROR: cannot fetch baseline for Cron gating"; exit 1;
}
HEAD_SHA=$(echo "$META" | jq -r '.headRefOid')
COMMENT_COUNT=$(echo "$META" | jq -r '.comments | length')
REVIEW_COUNT=$(echo "$META" | jq -r '.reviews | length')
INLINE_COUNT=$(gh api "repos/<repo>/pulls/<N>/comments" --jq 'length') || {
  echo "ERROR: cannot fetch inline comment baseline"; exit 1;
}

STATE_JSON=$(jq -n \
  --argjson pr <N> \
  --argjson max 6 \
  --arg sha "$HEAD_SHA" \
  --argjson c "$COMMENT_COUNT" \
  --argjson v "$REVIEW_COUNT" \
  --argjson ic "$INLINE_COUNT" \
  '{pr:$pr, round:1, maxRounds:$max, lastSha:$sha, lastCommentCount:$c, lastReviewCount:$v, lastInlineCommentCount:$ic}')

if ! printf '%s' "$STATE_JSON" > "$STATE_FILE"; then
  echo "ERROR: cannot write $STATE_FILE — refusing to schedule Cron without durable state." >&2
  exit 1
fi
[ -s "$STATE_FILE" ] || { echo "ERROR: state file empty after write."; exit 1; }
```

## Step 4: 创建跟踪任务（仅 Step 3 需要时，可选）

如果宿主提供 `CronCreate` / scheduler，创建 5 分钟间隔任务，prompt 为：

```
按 references/agents/pr-reviewer.md（model: opus）执行后续跟踪审查。
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

如果宿主没有 scheduler，**不要失败**。保留 `/tmp/.review-state-<N>.json`，向用户输出：

```
当前宿主没有 scheduler/Cron 能力。已写入跟踪状态：
/tmp/.review-state-<N>.json

请在有新 commit、CI 结果或评论变化后手动重跑：
rc:review-pr <N>
```

---

## 边界

- **首轮永远直接执行**，不经过 Cron（用户等待反馈的常见路径）
- **Scheduler 仅在发现 agent 可推进的问题时创建**（FIXED / MANUAL 混合），manual-only 不启动；不可用时降级为手动重跑
- **follow_up 固定用 opus**，修复质量优先；配合 Step 0.4 的 cheap gating，成本可控
- 所有具体审查/修复逻辑在 bundled `pr-reviewer` reference 中，本 Skill 不做审查判断
