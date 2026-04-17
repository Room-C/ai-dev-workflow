---
name: rc:review-pr
description: 自动化 PR Code Review — 先立即审查，仅在发现问题时启动后续跟踪循环。
argument-hint: "[PR-number] [--model sonnet|opus|haiku]"
allowed-tools: Bash, Read, Agent, CronCreate, CronDelete
---

# Auto PR Review

先立即执行一次审查。若无问题直接通过；若发现问题，启动定时跟踪循环（最多 5 轮）直到全部解决。

具体审查逻辑由 `agents/workflow/pr-reviewer.md` 实现。本 Skill 只负责**编排**：解析参数、首轮调用、判断是否启动循环、创建/取消 Cron 任务。

## 使用方式

```
rc:review-pr                       # 最新 open PR，Sonnet
rc:review-pr 42                    # 指定 PR #42
rc:review-pr 42 --model opus       # 指定 PR + 模型
```

支持模型：`sonnet`（默认）、`opus`、`haiku`

---

## Step 1: 解析参数 + 获取 PR 信息

1. 从 `$ARGUMENTS` 提取 PR 号（纯数字）和 `--model <model>` 参数
2. 若未指定 PR 号：`gh pr list --state open --limit 1 --json number,headRefName,baseRefName`
   - 无 open PR → 输出 "No open PR found." 并结束
3. 获取 repo：`gh repo view --json nameWithOwner -q '.nameWithOwner'`
4. 记录：`pr_number`、`head_branch`、`base_branch`、`repo`、`model`

## Step 2: 首轮审查

使用 Agent 工具调用 `ai-dev-workflow:workflow:pr-reviewer`，设置 `model` 为用户指定模型，传入参数：

```
mode: first_review
pr_number, repo, head_branch, base_branch
```

不传 `state_file`（首轮不需要）。

## Step 3: 根据返回信号决定下一步

| Agent 返回 | 处理 |
|-----------|------|
| `REVIEW_CLEAN` | `gh api` 提交 `✅ 自动审查通过` comment + macOS 通知 + **结束**（不创建 Cron） |
| `REVIEW_FIXED` | 创建状态文件 + 创建 Cron 任务（见 Step 4） |
| `REVIEW_MANUAL` | 创建状态文件 + 创建 Cron 任务 |

状态文件格式：

```bash
echo '{"pr":<N>,"round":1,"maxRounds":6}' > /tmp/.review-state-<N>.json
```

## Step 4: 创建跟踪 Cron（仅 Step 3 需要时）

使用 `CronCreate` 创建 5 分钟间隔任务，prompt 为：

```
调用 ai-dev-workflow:workflow:pr-reviewer agent（model: <用户指定>）执行后续跟踪审查。
参数：
  mode: follow_up
  pr_number: <N>
  repo: <owner/name>
  head_branch: <...>
  base_branch: <...>
  state_file: /tmp/.review-state-<N>.json

根据 agent 返回信号处理：
- REVIEW_DONE / REVIEW_STOPPED → CronDelete 取消本任务 + 删除状态文件
- REVIEW_SKIPPED → 本轮无新 commit，保留 Cron 等下一轮
- REVIEW_FIXED / REVIEW_MANUAL → 保留 Cron 等下一轮验证
```

---

## 边界

- **首轮永远直接执行**，不经过 Cron（用户等待反馈的常见路径）
- **Cron 仅在发现问题时创建**，避免干净 PR 也跑定时任务
- 所有具体审查/修复逻辑在 `pr-reviewer` Agent 中，本 Skill 不做审查判断
