---
name: rc:review-pr
description: GitHub PR 自动审查与闭环。Use when the user asks to review a PR / 审查 PR / 回复 PR comment, or runs rc:review-pr on a PR number or URL. Fetches diff and comments via gh, triages feedback, applies safe fixes, replies, and posts a summary.
allowed-tools: Bash, Read, Agent, CronCreate, CronDelete
metadata:
  argument-hint: "[PR-number-or-url] [--quality fast|balanced|deep]"
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

先立即执行一次审查。若无问题直接通过；若发现问题，或当前 open PR 上已有未闭环反馈，启动跟踪循环（最多 6 轮）直到全部解决。

具体审查逻辑由 bundled `references/agents/pr-reviewer.md` 实现。本 Skill 只负责**编排**：环境预检、解析参数、首轮调用、判断是否启动跟踪、创建/取消跟踪任务、记录遥测。首轮不假设 PR 一定是"刚建、无历史评论"。

## Portable Runtime（通用 Agent 兼容）

本 Skill 必须能通过 `npx skills add --copy` 单独安装后，在 **Claude Code、Codex 及其他通用 Agent** 上运行。运行时资源优先从当前 Skill 目录读取：

- `references/agents/pr-reviewer.md` — 审查逻辑
- `scripts/notify.sh` — 跨平台通知（macOS / Linux / Windows / 无头）
- `scripts/pr-diff-filter.sh` — 噪音过滤
- `scripts/record-outcome.sh` — 遥测（best-effort）

能力降级矩阵（缺任一都不应失败）：

| 宿主能力 | 有 | 无 |
|----------|----|----|
| 子代理（Agent 工具） | 按 bundled prompt 委派 pr-reviewer | 主上下文按该 reference **inline 执行** |
| `gh` / GitHub API（目标 PR 端点探针） | 完整在线流程：取 PR diff/评论、发 inline、回复、push、闭环跟踪 | **离线本地审查**：`git diff` 出报告，不读写 GitHub、不改代码、不跟踪（返回 `REVIEW_OFFLINE`） |
| Cron / scheduler | 发现可推进问题时创建跟踪任务 | 写状态文件，提示用户手动重跑 `rc:review-pr <N>` |
| 桌面通知 | `notify.sh` 调系统通道 | `notify.sh` 退回 stdout echo |
| macOS | osascript 通知 | 自动走 notify-send / BurntToast / echo |

**硬依赖**：`git`、`jq`、POSIX shell。**`gh` CLI 非硬依赖**——Step 0 只探测 `gh` 是否存在；解析出目标 PR 后再用 `repos/$repo/pulls/$PR_NUMBER` 端点判定能否走在线流程。探针失败（未装 / token 失效 / 网络不可达 / 目标 repo 不可读）即降级为离线本地审查（仅出报告，不读写 GitHub、不改代码）。

## Quality 策略

- **首轮审查 (`first_review`)**：使用 `--quality` 指定的质量档位，默认 `balanced`。产出首次 inline comments，控制成本。
- **跟踪循环 (`follow_up`)**：使用 `deep` 质量档位。修复阶段涉及代码变更，质量敏感。配合变更门控（Agent Step 0.4），多数 tick 是 <1k token 的廉价 SKIP，只有真要改代码才触发昂贵路径。
- **宿主映射**：若宿主支持显式模型选择，可将 `fast|balanced|deep` 映射到本宿主对应模型；例如 Claude 可映射为 `haiku|sonnet|opus`。若宿主不支持显式模型选择，使用当前宿主默认模型，不因模型名不可用而失败。

## 使用方式

```
rc:review-pr                       # 最新 open PR，首轮 balanced
rc:review-pr 42                    # 指定 PR #42
rc:review-pr 42 --quality deep     # 首轮也用 deep
rc:review-pr https://github.com/owner/repo/pull/42 --quality fast
```

---

## Step 0: 环境预检

```bash
# git / jq 是硬依赖（离线本地审查也要用），缺失即退出。
command -v git >/dev/null 2>&1 || { echo "ERROR: 需要 git，请先安装。"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: 需要 jq，请先安装。"; exit 1; }

# gh 不是硬依赖。这里只探测命令是否存在；不要用 gh auth status 或 gh api user
# 过早判定离线，因为 GitHub App installation token 可能无法访问 user 端点，
# 但仍可访问 repo-scoped PR/comment API。目标 PR 端点探针放在 Step 1。
GH_OFFLINE=0
if ! command -v gh >/dev/null 2>&1; then
  GH_OFFLINE=1
  echo "WARN: 未检测到 gh CLI —— 降级为【离线本地审查】：仅基于本地 git diff 出审查报告，"
  echo "      不读取/回复 PR 评论、不推送修复、不启动跟踪。"
  echo "      恢复完整闭环：安装 gh 并认证后重跑 rc:review-pr。"
fi
```

定位 Skill 目录（传给 agent，并用于 notify/telemetry）：

```bash
SKILL_DIR=""
for root in "$PWD/skills/review-pr" "$HOME/.agents/skills/rc-review-pr" \
            "$HOME/.claude/skills/rc-review-pr" "$HOME/.codex/skills/rc-review-pr"; do
  [ -f "$root/SKILL.md" ] && SKILL_DIR="$root" && break
done
```

## Step 1: 解析参数 + 获取 PR 信息

1. 从 `$ARGUMENTS` 提取 PR 标识、`--quality <fast|balanced|deep>`、`--base <branch>`（仅离线降级时用于指定对比基线）。**PR 标识同时支持编号和链接**：
   ```bash
   ARG="<第一个非 --quality/--base 参数>"
   FIRST_REVIEW_QUALITY="<--quality 的值，默认 balanced>"
   BASE_OVERRIDE="<--base 的值，默认空>"   # 仅 GH_OFFLINE=1 时生效
   case "$FIRST_REVIEW_QUALITY" in
     fast|balanced|deep) ;;
     *) echo "ERROR: --quality 仅支持 fast|balanced|deep"; exit 1 ;;
   esac
   case "$ARG" in
     "")                       PR_NUMBER="" ;;                                   # 未指定 → 取最新 open PR
     *github.com/*/pull/*)                                                       # 完整链接
       PR_NUMBER=$(printf '%s' "$ARG" | sed -E 's#.*/pull/([0-9]+).*#\1#')
       URL_REPO=$(printf '%s' "$ARG" | sed -E 's#https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#') ;;
     '#'[0-9]*)                PR_NUMBER="${ARG#\#}" ;;                           # #123
     [0-9]*)                   PR_NUMBER="$ARG" ;;                               # 123
     *)                        echo "ERROR: 无法识别的 PR 标识：$ARG"; exit 1 ;;
   esac
   ```
   链接形式解析出的 `URL_REPO` 优先作为目标仓库（支持跨仓库链接）。

**离线降级分支（`GH_OFFLINE=1`）**：跳过下面所有 `gh` PR 解析（2–7 全部依赖 gh），改为**纯本地**确定审查对象。处理完即进入 Step 2 的离线委派。

```bash
if [ "$GH_OFFLINE" = "1" ]; then
  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "ERROR: gh 不可用且当前不在 git 仓库内，离线审查无对象。请在仓库内运行，或恢复 gh 认证后重试。"; exit 1; }
  HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  # base 解析顺序：--base 显式参数 → origin/HEAD 指向 → local/remote 常见分支
  BASE_BRANCH="$BASE_OVERRIDE"
  [ -z "$BASE_BRANCH" ] && BASE_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$BASE_BRANCH" ]; then
    for b in main master develop origin/main origin/master origin/develop; do
      git rev-parse --verify --quiet "$b" >/dev/null 2>&1 && BASE_BRANCH="$b" && break
    done
  fi
  [ -n "$BASE_BRANCH" ] || { echo "ERROR: 无法确定 base 分支，请用 --base <branch> 指定。"; exit 1; }
  git rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null 2>&1 || {
    echo "ERROR: base 分支 '$BASE_BRANCH' 不可解析（本地无此 ref）。"; exit 1; }
  if git diff --quiet "$BASE_BRANCH"...HEAD; then
    echo "ERROR: $BASE_BRANCH...HEAD 无差异，离线审查无对象。"; exit 1
  else
    diff_status=$?
    [ "$diff_status" -eq 1 ] || { echo "ERROR: 无法计算 $BASE_BRANCH...HEAD diff。"; exit 1; }
  fi
  # pr_number 仅作展示（用户给了就显示，没给标 (offline)）；不计算/不写状态文件、不进 follow_up。
  echo "INFO: 离线本地审查 — base=$BASE_BRANCH head=$HEAD_BRANCH，进入 Step 2。"
fi
```

以下 **2–7 仅在线分支（`GH_OFFLINE=0`）执行**：

2. 未指定 PR 号：`gh pr list --state open --limit 1 --json number`，无 open PR → 输出 "No open PR found." 并结束
3. 确定 repo：有 `URL_REPO` 用之，否则 `gh repo view --json nameWithOwner -q '.nameWithOwner'`
4. 在禁用在线流程前，用目标 PR REST 端点做 repo-scoped 探针；不要用 `gh api user`，避免 GitHub App installation token 被误判为离线：
   ```bash
   PR_API=$(gh api "repos/$repo/pulls/$PR_NUMBER" 2>&1) || {
     GH_OFFLINE=1
     echo "WARN: gh 无法读取目标 PR API（$repo#$PR_NUMBER）——降级为【离线本地审查】：$PR_API"
   }
   ```
   若此处置 `GH_OFFLINE=1`，执行上面的离线降级分支并结束在线 PR 解析。
5. 从 `PR_API` 拉取 PR 元信息（含 **fork / 可写性**，供 agent 决定能否 push）：
   ```bash
   PR_META="$PR_API"
   # 用 printf 而非 echo：zsh 内置 echo 默认解释 \n/\t 等转义，会破坏 JSON 字符串
   head_branch=$(printf '%s' "$PR_META" | jq -r '.head.ref')
   base_branch=$(printf '%s' "$PR_META" | jq -r '.base.ref')
   is_cross_repository=$(printf '%s' "$PR_META" | jq -r '(.head.repo.full_name != .base.repo.full_name)')
   maintainer_can_modify=$(printf '%s' "$PR_META" | jq -r '.maintainer_can_modify // false')
   head_repo=$(printf '%s' "$PR_META" | jq -r '.head.repo.full_name')
   ```
6. 记录：`pr_number`、`head_branch`、`base_branch`、`repo`、`first_review_quality`、`is_cross_repository`、`maintainer_can_modify`、`head_repo`
7. 计算**跨平台 + 跨 repo 唯一**的状态文件路径（不写死 `/tmp`；文件名含 repo slug，避免 `repoA#42` 与 `repoB#42` 互相污染）：
   ```bash
   STATE_DIR="${TMPDIR:-/tmp}"; STATE_DIR="${STATE_DIR%/}"
   REPO_SLUG=$(printf '%s' "$repo" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-')
   STATE_FILE="$STATE_DIR/.rc-review-state-${REPO_SLUG}-${PR_NUMBER}.json"
   ```

## Step 2: 选择模式（首轮 or 接续跟踪）

**离线降级（`GH_OFFLINE=1`）**：跳过下面的模式选择——离线恒为**一次性** `first_review`，不读/不写状态文件、不进 `follow_up`。直接按下方委派 pr-reviewer，传 `offline: true`、`mode: first_review`、`base_branch`/`head_branch`/`skill_dir`/`quality`，**不传 `state_file`**。

**在线（`GH_OFFLINE=0`）先看是否存在该 PR 的状态文件**——无 scheduler 的宿主靠用户手动重跑接续，必须能从 state 切到 `follow_up`，否则永远重头 first_review，状态白存：

```bash
if [ -f "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  MODE=follow_up      # 接续已有跟踪状态（手动重跑路径）
else
  MODE=first_review
fi
```

读取 `references/agents/pr-reviewer.md`。有 Agent 工具时按该 prompt 委派 pr-reviewer；`first_review` 用 `first_review_quality`，`follow_up` 用 `deep`。无 Agent 工具时主上下文按该 reference **inline 执行**。若宿主不支持显式模型/质量选择，使用当前宿主默认执行能力，不失败。传入参数：

```
mode: <MODE>
pr_number, repo, head_branch, base_branch, skill_dir
is_cross_repository, maintainer_can_modify, head_repo
quality: <first_review_quality|deep>
state_file: <仅 follow_up 传，指向已存在的 STATE_FILE>
offline: <true 仅 GH_OFFLINE=1 时传；离线本地审查，agent 跳过所有 gh 读写>
```

> 离线分支：`mode: first_review` + `offline: true`，`repo`/`is_cross_repository` 等 gh 相关参数可省略或留空；agent 只用 `base_branch`/`head_branch`/`skill_dir`/`quality`。

- `first_review` 不传 `state_file`。
- `follow_up`（接续重跑）传 `state_file`，由 agent 走 Step 0 变更门控；若返回 `REVIEW_DONE`，删除状态文件。若返回 `REVIEW_STOPPED`，**编排器不要自行删除**——agent 已经区分了终态（PR 关闭/合并、达最大轮次，agent 内部已清理）和临时失败（`gh`/`git` 调用失败，状态文件需保留以便重试），由 agent 负责。

## Step 3: 根据返回信号决定下一步

> Agent 的对外回复/总结已由其内部幂等辅助函数处理（`upsert_summary` / `reply_to_comment`）。本步骤的 CLEAN / MANUAL_ONLY 总结也必须走幂等更新，避免重复运行刷屏。

| Agent 返回 | 处理 |
|-----------|------|
| `REVIEW_OFFLINE` | （仅 `GH_OFFLINE=1`）agent 已基于本地 diff 完成审查、报告写在返回里。**把报告原文透传给用户** + 打印重新认证指引（`gh auth login` / `gh auth refresh`，认证后重跑 `rc:review-pr` 恢复完整闭环）+ **不创建跟踪任务、不写状态文件、不发任何 PR 评论** + 结束 |
| `REVIEW_CLEAN` | 幂等更新总结为 `✅ 自动审查通过`（见下 `upsert_summary`）+ `notify` + 删除状态文件（若有）+ **结束**（不创建跟踪任务） |
| `REVIEW_MANUAL_ONLY` | 幂等更新总结为 `⏸️ 全部为人工决策项，处理完后手动重跑 rc:review-pr` + `notify` + **结束**（轮询无法推进 manual 项） |
| `REVIEW_DONE` | （follow_up 接续）`notify` + 删除状态文件 + **结束** |
| `REVIEW_STOPPED` | （follow_up 接续）`notify` + **结束**（状态文件是否删除由 agent 内部按终态/临时失败区分决定，编排器不重复删除） |
| `REVIEW_SKIPPED` | （follow_up 接续）本轮无变更，保留状态文件，提示稍后再重跑 / 等下一次 scheduler tick |
| `REVIEW_FIXED` | **仅 first_review** 需创建状态文件（含 baseline）；follow_up 时 agent 已就地更新。有 scheduler 则创建/保留跟踪任务，否则提示手动重跑 |
| `REVIEW_MANUAL` | 同上：first_review 创建 baseline；follow_up 保留。有 scheduler 则跟踪，否则提示手动重跑 |

> baseline 创建（下方代码块）**只在 first_review 首次发现可推进问题时执行**；follow_up 接续重跑不要重建 baseline（会抹掉已累积的轮次/计数）。

CLEAN / MANUAL_ONLY 的总结用同一条带标记的评论就地更新：

```bash
upsert_summary() {  # 与 pr-reviewer 中同源，全 PR 唯一总结
  local full="$1

<!-- rc-review:summary -->"
  local existing
  existing=$(gh api "repos/<repo>/issues/<N>/comments" --paginate \
    --jq '[.[] | select(.body | contains("rc-review:summary")) | .id] | last' 2>/dev/null) || existing=""
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    gh api -X PATCH "repos/<repo>/issues/comments/$existing" -f body="$full" >/dev/null
  else
    gh api -X POST "repos/<repo>/issues/<N>/comments" -f body="$full" >/dev/null
  fi
}
notify() {
  if [ -n "${SKILL_DIR:-}" ] && [ -f "$SKILL_DIR/scripts/notify.sh" ]; then
    bash "$SKILL_DIR/scripts/notify.sh" "$1" "Review Agent" || true
  else echo "🔔 Review Agent: $1"; fi
}
```

**状态文件必须包含变更门控基线**，避免第一次 tick 做重复工作：

```bash
# 捕获 baseline：HEAD SHA + comment/review 计数 + CI check 指纹
META=$(gh pr view <N> --repo "$repo" --json headRefOid,comments,reviews,statusCheckRollup) \
  || { echo "ERROR: cannot fetch baseline"; exit 1; }
# 用 printf 而非 echo：zsh 内置 echo 默认解释 \n/\t 等转义，会破坏 comments/reviews 正文里的 JSON
HEAD_SHA=$(printf '%s' "$META" | jq -r '.headRefOid')
COMMENT_COUNT=$(printf '%s' "$META" | jq -r '.comments | length')
REVIEW_COUNT=$(printf '%s' "$META" | jq -r '.reviews | length')
# CI/check-run 指纹，必须与 agent Step 0.1 的算法一致，否则首个 tick 必触发完整审查
CHECKS_SIG=$(printf '%s' "$META" | jq -r \
  '[.statusCheckRollup[]? | {n:(.name // .context // ""), c:(.conclusion // .state // "")}] | sort_by(.n) | tostring' \
  | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null || cksum; } | awk '{print $1}' | cut -c1-16)
# inline review comments 必须单独拉（gh pr view 不含）
INLINE_COUNT=$(gh api "repos/<repo>/pulls/<N>/comments" --jq 'length') || { echo "ERROR: cannot fetch inline baseline"; exit 1; }

STATE_JSON=$(jq -n --argjson pr <N> --argjson max 6 --arg sha "$HEAD_SHA" \
  --argjson c "$COMMENT_COUNT" --argjson v "$REVIEW_COUNT" --argjson ic "$INLINE_COUNT" --arg ck "$CHECKS_SIG" \
  '{pr:$pr, round:1, maxRounds:$max, lastSha:$sha, lastCommentCount:$c, lastReviewCount:$v, lastInlineCommentCount:$ic, lastChecksSig:$ck}')

if ! printf '%s' "$STATE_JSON" > "$STATE_FILE"; then
  echo "ERROR: cannot write $STATE_FILE — refusing to schedule without durable state." >&2; exit 1
fi
[ -s "$STATE_FILE" ] || { echo "ERROR: state file empty after write."; exit 1; }
```

## Step 4: 创建跟踪任务（仅 Step 3 需要时，可选）

如果宿主提供 `CronCreate` / scheduler，创建 5 分钟间隔任务，prompt 为：

```
按 references/agents/pr-reviewer.md 执行后续跟踪审查，quality: deep。
参数：
  mode: follow_up
  pr_number: <N>
  repo: <owner/name>
  head_branch: <...>
  base_branch: <...>
  state_file: <STATE_FILE>
  skill_dir: <SKILL_DIR>
  is_cross_repository: <true|false>
  maintainer_can_modify: <true|false>
  head_repo: <owner/name>

根据 agent 返回信号处理：
- REVIEW_DONE → CronDelete 取消本任务 + 删除状态文件 + 记录遥测
- REVIEW_STOPPED（终态：PR 已关闭/合并、达最大轮次，agent 已自行清理状态文件）→ CronDelete 取消本任务 + 记录遥测
- REVIEW_STOPPED（临时失败：gh/git 调用失败，状态文件仍存在）→ **保留任务**，等下一轮重试；不要取消 Cron，否则跟踪会永久丢失
- REVIEW_SKIPPED → 本轮无变更（便宜路径已执行），保留任务等下一轮
- REVIEW_FIXED / REVIEW_MANUAL → 保留任务等下一轮验证
```

如果宿主**没有** scheduler，不要失败。保留状态文件，向用户输出：

```
当前宿主没有 scheduler/Cron 能力。已写入跟踪状态：
<STATE_FILE>

请在有新 commit、CI 结果或评论变化后手动重跑：
rc:review-pr <N>
```

## Step 5: 遥测（best-effort，永不阻塞主流程）

流程任意结束点调用 `scripts/record-outcome.sh`（按 CLAUDE.md 解析顺序定位）：

```bash
RECORD_SCRIPT=""
for c in "$SKILL_DIR/scripts/record-outcome.sh" \
         "skills/review-pr/scripts/record-outcome.sh" \
         "skills/shared/scripts/record-outcome.sh"; do
  [ -f "$c" ] && RECORD_SCRIPT="$c" && break
done
if [ -n "$RECORD_SCRIPT" ]; then
  bash "$RECORD_SCRIPT" review-pr "$STATUS" "${FAIL_STEP:-}" "${FAIL_REASON:-}" "${FALLBACK:-}" \
    || echo "WARN: telemetry 调用非零退出，记录可能不完整。" >&2
fi
```

status 映射：

| 场景 | status | fallback_used |
|------|--------|---------------|
| `REVIEW_CLEAN` / `REVIEW_DONE` | `success` | - |
| `REVIEW_FIXED` / `REVIEW_MANUAL` / `REVIEW_MANUAL_ONLY` | `partial` | - |
| `REVIEW_OFFLINE`（gh 不可用，离线本地审查） | `partial` | `gh-offline` |
| 无 scheduler，降级为手动重跑 | `partial` | `manual-rerun` |
| 无 Agent 工具，inline 执行 | 在上述基础上附 | `native-inline` |
| `REVIEW_STOPPED`（gh/git 失败、达上限） | `partial`（上限）/ `failed`（调用失败） | - |

---

## 边界

- **首轮永远直接执行**，不经过跟踪任务（用户等待反馈的常见路径）
- **跟踪任务仅在发现 agent 可推进的问题时创建**（FIXED / MANUAL）；manual-only 不启动；不可用时降级为手动重跑
- **follow_up 固定 deep 质量档位**，修复质量优先；配合 Step 0.4 cheap gating 成本可控
- **所有对外回复/总结幂等**：带 `rc-review:*` 隐藏标记，重复运行只更新不新增
- 所有具体审查/修复逻辑在 bundled `pr-reviewer` reference 中，本 Skill 不做审查判断
- 不依赖 macOS / 子代理 / Cron / `gh` 任一存在；缺失即降级，绝不失败退出。`gh` 不可用/认证失效 → 降级**离线本地审查**（report-only，返回 `REVIEW_OFFLINE`）；**仅当**连 git 仓库都不在、或 base 不可解析、或 diff 为空时才硬失败（此时离线审查也无对象）。`git` / `jq` 仍是硬依赖
