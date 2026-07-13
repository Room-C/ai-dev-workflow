---
name: rc:review-pr
description: GitHub PR 自动审查、修复与有界跟踪。Use when the user asks to review a PR / 审查 PR / 回复 PR comment, or runs rc:review-pr on a PR number or URL. Fetches diff and comments via gh, triages feedback, applies safe fixes, replies, and optionally follows new events with --follow.
allowed-tools: Bash, Read, Agent
metadata:
  argument-hint: "[PR-number-or-url] [--quality fast|balanced|deep] [--follow]"
  quality-policy:
    first-review: balanced
    follow-up: deep
  optional-model-mapping:
    claude:
      fast: haiku
      balanced: sonnet
      deep: opus
---

# Auto PR Review

立即执行一次审查。默认完成本次审查后结束；只有用户显式传入 `--follow` 时，才尝试创建**有界、单次唤醒**的后续检查。不要创建永久轮询任务，也不要让运行中的调度任务删除自身。

具体审查逻辑放在 bundled `references/agents/pr-reviewer.md`。本文件只负责编排：环境预检、参数和 PR 解析、确定性 gate、调用 reviewer、状态迁移、可选续约和遥测。

## Portable Runtime

优先使用当前 Skill 内资源：

- `references/agents/pr-reviewer.md`：审查、修复和 GitHub 回复
- `scripts/review-pr-gate.sh`：终态、事件、TTL、tick、退避和并发锁
- `scripts/pr-diff-filter.sh`：diff 噪音过滤
- `scripts/notify.sh`：跨平台通知
- `scripts/record-outcome.sh`：best-effort 遥测

能力降级：

| 能力 | 可用 | 不可用 |
|---|---|---|
| 子代理 | 按 bundled prompt 委派 | 主上下文 inline 执行 |
| `gh` / GitHub API | 完整在线审查 | 本地 diff report-only，返回 `REVIEW_OFFLINE` |
| 安全单次唤醒 | `--follow` 时按结果续约一次 | 保留状态，提示手动重跑 |
| 只有 recurring Cron | **不要使用** | 按无 scheduler 处理 |
| 桌面通知 | 调 `notify.sh` | stdout |

硬依赖：`git`、`jq`、Bash。`gh` 不是硬依赖。Scheduler、Cron、heartbeat、子代理和 MCP 都是可选能力。

## 生命周期不变量

1. 默认不创建后台任务；`--follow` 才允许跟踪。
2. 只调度一个未来 wake；当前运行结束后，由结果决定是否再调度一个。gate 用可过期 reviewer lease 阻止并发重复审查。
3. 不创建 `FREQ=MINUTELY` 等永久任务，不从任务内部 delete/pause 自身。
4. reviewer 不删除状态文件；编排器通过 gate 写 `terminal` tombstone。
5. `waiting_human` 不续约。人工决策不会通过轮询自动解决。
6. 每次 wake 都增加 `tickCount`，并同时受 `maxTicks`、`expiresAt`、`maxNoChangeTicks`、`maxRetries` 和 `maxEventRounds` 限制；gate 与 reviewer 的临时失败共用 `maxRetries`。
7. gate 返回 `review` 前不加载 reviewer prompt；`skip`/`terminal` 路径保持确定性和低成本。

## 使用方式

```text
rc:review-pr
rc:review-pr 42
rc:review-pr 42 --quality deep
rc:review-pr 42 --follow
rc:review-pr https://github.com/owner/repo/pull/42 --quality fast --follow
```

## Step 0: 环境和资源预检

```bash
command -v git >/dev/null 2>&1 || { echo "ERROR: 需要 git。"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: 需要 jq。"; exit 1; }

GH_OFFLINE=0
command -v gh >/dev/null 2>&1 || GH_OFFLINE=1

SKILL_DIR=""
for root in "$PWD/skills/review-pr" "$HOME/.agents/skills/rc-review-pr" \
            "$HOME/.claude/skills/rc-review-pr" "$HOME/.codex/skills/rc-review-pr"; do
  [ -f "$root/SKILL.md" ] && SKILL_DIR="$root" && break
done
[ -n "$SKILL_DIR" ] || { echo "ERROR: 找不到 review-pr Skill 目录。"; exit 1; }

GATE_SCRIPT="$SKILL_DIR/scripts/review-pr-gate.sh"
[ -f "$GATE_SCRIPT" ] || { echo "ERROR: 缺少 bundled review-pr-gate.sh。"; exit 1; }
```

不要用 `gh auth status` 或 `gh api user` 预判离线。GitHub App installation token 可能只能访问 repo-scoped API；在线能力必须在解析目标 repo/PR 后探测。

## Step 1: 参数与 PR

从 `$ARGUMENTS` 提取：

- 第一个 PR 编号、`#N` 或 `https://github.com/owner/repo/pull/N`
- `--quality fast|balanced|deep`，默认 `balanced`
- `--base <ref>`，只用于离线模式
- `--follow`，默认 `FOLLOW=0`，出现时设 `FOLLOW=1`

未知参数或缺失的 option value 立即报错。链接里的 repo 优先于当前目录 repo。

### 离线分支

`GH_OFFLINE=1` 时只做一次本地审查，不写状态、不跟踪、不改代码：

```bash
git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "ERROR: gh 不可用且当前不在 git 仓库。"; exit 1; }
HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE_BRANCH="$BASE_OVERRIDE"
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
if [ -z "$BASE_BRANCH" ]; then
  for b in main master develop origin/main origin/master origin/develop; do
    git rev-parse --verify --quiet "$b" >/dev/null 2>&1 && BASE_BRANCH="$b" && break
  done
fi
[ -n "$BASE_BRANCH" ] || { echo "ERROR: 请用 --base <ref> 指定离线基线。"; exit 1; }
if git diff --quiet "$BASE_BRANCH"...HEAD; then
  echo "ERROR: $BASE_BRANCH...HEAD 无差异。"; exit 1
else
  diff_status=$?
  [ "$diff_status" -eq 1 ] || { echo "ERROR: 无法计算本地 diff。"; exit 1; }
fi
```

随后按 reviewer 的离线分支 inline 执行，传 `offline:true`、`mode:first_review`、`base_branch`、`head_branch`、`skill_dir`、`quality`。忽略 `--follow`。

### 在线分支

1. 未指定 PR：取最新 open PR；没有则输出 `No open PR found.` 并结束。
2. 确定 `repo` 和 `PR_NUMBER`。
3. 用目标端点探测：

   ```bash
   PR_API=$(gh api "repos/$repo/pulls/$PR_NUMBER" 2>&1) || {
     GH_OFFLINE=1
     echo "WARN: 无法读取 $repo#$PR_NUMBER，降级离线审查：$PR_API"
   }
   ```

4. 在线时从 `PR_API` 提取：

   ```bash
   PR_STATE=$(printf '%s' "$PR_API" | jq -r '.state')
   head_branch=$(printf '%s' "$PR_API" | jq -r '.head.ref')
   base_branch=$(printf '%s' "$PR_API" | jq -r '.base.ref')
   is_cross_repository=$(printf '%s' "$PR_API" | jq -r '(.head.repo.full_name != .base.repo.full_name)')
   maintainer_can_modify=$(printf '%s' "$PR_API" | jq -r '.maintainer_can_modify // false')
   head_repo=$(printf '%s' "$PR_API" | jq -r '.head.repo.full_name')
   ```

5. 使用持久状态目录。只有无法创建持久目录时才退回临时目录，并强制 `FOLLOW=0`：

   ```bash
   STATE_DURABLE=1
   STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/rc-review"
   if ! mkdir -p "$STATE_ROOT" 2>/dev/null; then
     STATE_DURABLE=0
     FOLLOW=0
     STATE_ROOT="${TMPDIR:-/tmp}/rc-review"
     mkdir -p "$STATE_ROOT" || { echo "ERROR: 无法创建状态目录。"; exit 1; }
     echo "WARN: 持久状态不可用，已禁用 --follow。"
   fi
   chmod 700 "$STATE_ROOT" 2>/dev/null || true
   REPO_SLUG=$(printf '%s' "$repo" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-')
   STATE_FILE="$STATE_ROOT/${REPO_SLUG}-${PR_NUMBER}.json"
   ```

6. `PR_STATE != open` 时立即终止。若状态文件存在，用 gate 写 tombstone；不要进入 reviewer，也不要创建/删除 scheduler：

   ```bash
   if [ "$PR_STATE" != "open" ]; then
     [ -f "$STATE_FILE" ] && bash "$GATE_SCRIPT" --terminal "pr_$PR_STATE" --state "$STATE_FILE" >/dev/null
     echo "PR $repo#$PR_NUMBER 已关闭或合并，审查结束。"
     exit 0
   fi
   ```

## Step 2: 模式与确定性 gate

初始设 `MODE=first_review`。仅当存在合法、非 terminal 的状态文件时，运行 gate；用户直接调用属于 manual trigger：

```bash
if [ -f "$STATE_FILE" ] && jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
  PHASE=$(jq -r '.phase // "active"' "$STATE_FILE")
  if [ "$PHASE" != "terminal" ]; then
    GATE_RESULT=$(bash "$GATE_SCRIPT" --manual --repo "$repo" --pr "$PR_NUMBER" --state "$STATE_FILE")
    GATE_ACTION=$(printf '%s' "$GATE_RESULT" | jq -r '.action')
    case "$GATE_ACTION" in
      review) MODE=follow_up ;;
      skip)
        if [ "$FOLLOW" = "1" ]; then MODE=gate_only
        else echo "PR 无新事件，本次无需重复审查。"; exit 0; fi ;;
      waiting_human) echo "PR 仍等待人工确认；不会启动后台轮询。"; exit 0 ;;
      retry)
        if [ "$FOLLOW" = "1" ]; then MODE=gate_only
        else echo "GitHub 暂时不可用，请稍后重跑。"; exit 0; fi ;;
      terminal) echo "跟踪已终止：$(printf '%s' "$GATE_RESULT" | jq -r '.reason')"; exit 0 ;;
      *) echo "ERROR: 未知 gate action: $GATE_ACTION"; exit 1 ;;
    esac
  fi
fi
```

`gate_only` 不读取 reviewer，只把 gate 的 `skip` / `retry` 交给 Step 4 决定是否安全续约。terminal tombstone 遇到新的用户调用时允许重新执行 `first_review`；若仍需状态，Step 3 会通过 `--init` 原子覆盖。

## Step 3: 调用 reviewer 与迁移状态

只有 `MODE=first_review` 或 gate 返回 `review` 时才读取 `references/agents/pr-reviewer.md`。有 Agent 工具时委派；否则 inline 执行。首轮使用请求的 quality，follow-up 使用 `deep`。

传入：

```text
mode, pr_number, repo, head_branch, base_branch, skill_dir
is_cross_repository, maintainer_can_modify, head_repo, quality
state_file  # 仅 follow_up，用于显示轮次；reviewer 不得改删
```

按返回信号执行：

| 信号 | 编排动作 |
|---|---|
| `REVIEW_OFFLINE` | 透传本地报告，结束 |
| `REVIEW_CLEAN` | first-review 且有 `--follow` 时 `--init --init-phase active` 并进入 Step 4；否则直接结束 |
| `REVIEW_DONE` | follow-up 先 `--reviewed`，再写 `--terminal completed`；结束 |
| `REVIEW_TERMINAL` | follow-up 写 `--terminal agent_terminal`；first-review 用 `--init` 获取真实 PR 终态并写 tombstone；结束 |
| `REVIEW_RETRY` | follow-up 用 `--retry reviewer_retry` 累计失败并保留 `pendingReview=true`；first-review 仅在有 `--follow` 时先 `--init` 再 `--retry`；按 Step 4 决定是否续约 |
| `REVIEW_FIXED` | first-review 仅在有 `--follow` 时用 gate `--init --init-phase active` 建基线；follow-up 用 `--reviewed`；按 Step 4 决定是否续约 |
| `REVIEW_WAITING_HUMAN` / `REVIEW_MANUAL` / `REVIEW_MANUAL_ONLY` | first-review 用 gate `--init --init-phase waiting_human`；follow-up 用 `--waiting-human`；通知并结束，不续约 |
| `REVIEW_SKIPPED` | 兼容旧 reviewer；不加载更多上下文，按 gate 的 `skip` 处理 |

示例状态操作：

```bash
# 首轮修复完成，建立两小时内有效的有界跟踪状态
bash "$GATE_SCRIPT" --init --init-phase active --repo "$repo" --pr "$PR_NUMBER" --state "$STATE_FILE"

# follow-up 已成功完成本轮 review
bash "$GATE_SCRIPT" --reviewed --state "$STATE_FILE"

# reviewer 临时失败；保留当前事件并累计有上限的 retryCount
bash "$GATE_SCRIPT" --retry reviewer_retry --state "$STATE_FILE"

# 等待人工或进入终态；保留 tombstone，不 rm 状态文件
bash "$GATE_SCRIPT" --waiting-human --state "$STATE_FILE"
bash "$GATE_SCRIPT" --terminal completed --state "$STATE_FILE"
```

若 `--init` 返回 `retry`，不要调度；提示用户稍后手动重跑。

## Step 4: `--follow` 的安全单次续约

仅当以下条件全部满足时预约一个未来 wake：

- 用户显式传入 `--follow`
- `STATE_DURABLE=1`
- 已存在 active 状态，且当前信号为 `REVIEW_CLEAN`、`REVIEW_FIXED`、`REVIEW_RETRY`，或 gate 为 `skip`/`retry`
- 宿主提供**单次** continuation/heartbeat，调用能立即返回，且本次运行结束后不会继续重复触发
- 能以 `review-pr:<repo>#<pr>` 查找现有 pending wake，确保同一 PR 最多一个

Codex 若提供附着当前 task 的 one-shot heartbeat，优先复用当前 task。若只提供 recurring automation/Cron，即使同时提供 delete API，也视为不安全：不要创建，降级手动重跑。Claude Code 或其他宿主同理。

future wake 的 prompt 必须先运行 gate，且不要先读取 reviewer：

```text
运行 <skill_dir>/scripts/review-pr-gate.sh，参数为 repo/pr/state_file。
- terminal / waiting_human：立即结束，不再预约；若宿主支持则归档本次 no-op task。
- skip / retry：读取 nextAfter；预算未耗尽时只预约一个 successor，然后结束。
- review：读取 bundled pr-reviewer.md，以 follow_up/deep 执行；成功后 --reviewed，
  临时失败时 --retry，等待人工时 --waiting-human，完成时 --terminal。
  只有状态仍为 active 且信号为 REVIEW_FIXED/REVIEW_RETRY 才预约一个 successor。
禁止创建 recurring Cron，禁止 delete/pause 当前运行所属 scheduler。
```

首次建议 `nextAfter=300` 秒；gate 会按 300、900、1800 秒退避，并在 12 ticks、6 次无变化、3 次 API 失败、6 个事件轮次或 2 小时任一上限到达时 terminal。

没有安全单次唤醒时输出：

```text
当前宿主没有可安全续约的一次性 scheduler。已保留跟踪状态：<STATE_FILE>
出现新 commit、CI 结果或评论后请手动重跑：rc:review-pr <N>
```

## Step 5: 遥测

任意结束点 best-effort 调用 bundled `scripts/record-outcome.sh`。失败只警告，不覆盖主结果。

| 场景 | status | fallback |
|---|---|---|
| CLEAN / DONE / TERMINAL(completed) | `success` | - |
| FIXED / WAITING_HUMAN | `partial` | - |
| OFFLINE | `partial` | `gh-offline` |
| 无安全 scheduler | `partial` | `manual-rerun` |
| 无 Agent 工具 | 继承主状态 | `native-inline` |
| RETRY / API 失败 | `failed` | - |

## 边界

- 所有 GitHub 回复和总结继续使用 `rc-review:*` 隐藏标记保证幂等。
- gate 的事件快照忽略带 `rc-review:*` 标记的 agent 评论，避免 reviewer 的输出触发自身。
- 所有运行时脚本和 prompt 必须来自当前 Skill 目录；根 `agents/` 只能作为 legacy fallback。
- 不依赖 scheduler、子代理、桌面通知或 macOS。
- recurring Cron 不属于可用降级能力；宁可手动重跑，也不要创建无法可靠终止的后台任务。
- state tombstone 可由后续首轮原子覆盖，不要在终态立即删除，以便诊断和阻止僵尸 wake。
