---
name: rc:diff-review
description: 对比目标分支进行代码审查并自动化修复，直到无 P1/P2 问题。Codex Review → Validation → Auto-fix → 重审，最多 5 轮。当用户说"review diff"、"帮我 review"、"review 这个分支"时触发。
argument-hint: "[target-branch] [--depth quick|standard|deep] [--focus security,performance] [--since commit] [--path filter] [--no-compound] [--no-commit] [--keep-intermediates]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
model: sonnet
---

# Diff Review — 分支对比审查 + 自动化闭环修复

对比当前分支与目标分支，以 **Codex Review → Validation → Auto-fix → 重审** 的闭环运行，直到无 P1/P2 或达到 5 轮上限。

三个 Agent 协作：
- `diff-reviewer`（SubAgent）：调用 Codex 产出结构化 findings JSON；Codex 不可用时降级 Agent 审查
- `validation-reviewer`（SubAgent）：对每条 finding 判定 `to_fix / dismissed / deferred`，附 evidence 和 confidence
- `fix-runner`（SubAgent）：串行执行每条 `to_fix` 的修复 + 验证 + 回滚/提交，隔离文件内容与测试日志不污染主上下文

本 Skill 负责编排：参数解析、diff 收集、baseline 准备、循环控制、用户交互（`needs_confirm` 审批）、报告生成、知识沉淀、清理。

## 参数

| 参数 | 默认 | 说明 |
|------|------|------|
| 目标分支 | `main` | 对比基准 |
| `--depth` | `standard` | `quick` / `standard` / `deep`，传给 Codex 控制审查深度 |
| `--focus` | 全部 | `security` / `performance` / `logic` / `style` / `agent-native`，可组合 |
| `--since` | 无 | 增量审查起点 commit |
| `--path` | 全部 | 路径过滤，如 `backend/` |
| `--compound` | `on` | 知识沉淀。`--no-compound` 关闭 |
| `--commit` | `on` | 每条修复独立 commit。`--no-commit` 仅改文件 |
| `--keep-intermediates` | `off` | 默认清理中间轮次产物，仅保留最终报告 |

## 工作流程

### Step 1: 收集 diff + 上下文

1. **预处理脚本**（优先）：定位 `skills/diff-review/scripts/preprocess-diff.sh`（插件缓存或本地），传入 `target_branch` / `--since` / `--path`，获取 diff 范围、改动文件、模块列表
2. **错误处理**：脚本若因 `target_branch` / `--since` 非法而 exit non-zero，直接向用户报告"比较基线无效"，**不要**当作"无改动"
3. **降级手动**：仅当脚本缺失或不可执行时，才回退到 `git diff <base>...HEAD --stat` 和 `--name-only`
4. **无改动** → 结束："当前分支与目标分支无差异"
5. **模块覆盖检测**：Monorepo 仅改部分模块时，在报告开头注明
6. **噪音过滤**：预处理脚本已内置（`*.lock`、`*.generated.*`、`*/migrations/*`、`*.min.*`、`*.pbxproj`）
7. **上下文理解**：读 CLAUDE.md、`docs/solutions/` 相关条目、`skills/shared/known-issues.md`、commit 历史

### Step 2: 准备输出目录

```bash
REVIEW_DIR="docs/develop/reviews/$(date +%Y-%m-%d)"
ROUNDS_DIR="$REVIEW_DIR/.rounds"
if ! mkdir -p "$ROUNDS_DIR"; then
  echo "ERROR: cannot create $ROUNDS_DIR (cwd=$PWD, exit=$?). Aborting review." >&2
  exit 1
fi
[ -w "$REVIEW_DIR" ] || { echo "ERROR: $REVIEW_DIR is not writable."; exit 1; }
```

报告文件名：`<current-branch>-vs-<target-branch>.md`（`/` 替换为 `-`）。
中间产物（round/baseline JSON、每轮 review/validation 文件）全部落在 `$ROUNDS_DIR`。

### Step 3: Baseline 准备（惰性）

**不立即执行**。记录命令即可，待 Step 4.3 首次验证失败时才执行：

1. 探测项目验证命令（CLAUDE.md "Verification" 章节 / `package.json` scripts / `Makefile` targets）
2. 写入 `$ROUNDS_DIR/baseline-cmds.json`：`{lint, typecheck, test}` 可用命令数组
3. 若项目无任何可用验证命令 → 标记 `baseline.missing = true`，Step 4.3 任何新增失败一律归为"本轮引入"

### Step 4: 循环审查（ROUND=1..5）

`ROUND=1` 起，每轮执行 4.1 → 4.5。

#### 4.1 Codex Review（SubAgent: `diff-reviewer`）

调用 `ai-dev-workflow:workflow:diff-reviewer`，传入：

| 参数 | 说明 |
|------|------|
| `diff_range` | `<base>...HEAD`（base 为 `--since` 或目标分支） |
| `output_dir` | `$ROUNDS_DIR` |
| `round` | 当前轮次 |
| `path_filter` / `focus` / `depth` | 按参数透传 |
| `dismissed_context` | 之前所有轮次被 Validation 判为 `dismissed` 的清单 + 理由，要求 Codex 不重复标注（除非发现新证据） |
| `fixes_context` | 之前所有轮次已修复的 commit hash / diff 摘要，让 Codex 对最新代码状态复审 |

Agent 输出契约（严格 JSON）写入 `$ROUNDS_DIR/review-round-$ROUND.json`：

```json
{
  "engine": "codex|codex-bash|agent-fallback|native-inline|failed",
  "raw_output_path": "$ROUNDS_DIR/review-round-$ROUND.md",
  "round": 1,
  "issues": [
    {
      "id": "ISSUE-001",
      "severity": "P1|P2|P3",
      "location": "path:line",
      "description": "...",
      "suggestion": "..."
    }
  ]
}
```

**四层弹性**（`diff-reviewer` 内部自动降级，**仓库可读就不会失败**）：
1. Codex Skill → 2. Codex Bash 直调 → 3. 通用代码审查子代理 → 4. 原生内联审查（仅用 Read/Grep/git）

每层失败自动尝试下一层。`engine` 字段标明最终走到了哪层。仅当 `engine = "failed"` 时上层 Skill 终止循环（此时通常意味着 git 仓库不可读）。

#### 4.2 Validation（SubAgent: `validation-reviewer`）

调用 `ai-dev-workflow:workflow:validation-reviewer`，传入：

| 参数 | 说明 |
|------|------|
| `findings_json_path` | `$ROUNDS_DIR/review-round-$ROUND.json`（4.1 产物） |
| `diff_range` | 与 4.1 相同 |
| `output_dir` | `$ROUNDS_DIR` |
| `round` | 当前轮次 |
| `fixes_context` | 之前所有轮次已修复的 commit hash / diff 摘要，避免 Validation 对旧问题重复裁决 |

输出契约写入 `$ROUNDS_DIR/validation-round-$ROUND.json`：

```json
{
  "round": 1,
  "items": [
    {
      "id": "ISSUE-001",
      "class": "to_fix|dismissed|deferred",
      "confidence": 0.85,
      "evidence": "引用代码并说明判断依据（2-3 句）",
      "reason": "为什么此分类",
      "autofix_strategy": "direct|needs_confirm|manual_only"
    }
  ]
}
```

硬约束（由本 Skill 再校验一次，防止 agent 遗漏）：
- `confidence < 0.60` → 强制降为 `dismissed`，`reason` 追加 `[confidence-gate]`
- 缺 `evidence` 或 `evidence` 少于 20 字符 → 强制降为 `deferred`，`reason` 追加 `[missing-evidence]`
- `autofix_strategy = manual_only` → 仅允许 `deferred` 或 `dismissed`（不能 `to_fix`）

#### 4.3 Auto-fix（SubAgent: `fix-runner`，串行）

遍历 Validation 结果中所有 `class = to_fix` 的项（含 P1/P2/P3）。**主 Skill 不亲自改代码、不读测试日志**——全部委托 `fix-runner`，自己仅做编排。

**1. 预处理 needs_confirm**（本步留在主 Skill，因为涉及用户交互）：

对每条 `autofix_strategy = needs_confirm` 的项，用 `AskUserQuestion` 展示 `{id, severity, location, description, suggestion}`。
- 用户选 "approve" → 转交 fix-runner（按 direct 执行）
- 用户选 "reject" → 本条降为 `deferred`，`reason=user-rejected`，不再调 fix-runner
- 为节省轮次，可将同一轮的多条 `needs_confirm` 合并为一次 `AskUserQuestion`（multiSelect）

**2. 串行调用 fix-runner**：

按 `severity P1 → P2 → P3` 顺序，**逐条**调用 `ai-dev-workflow:workflow:fix-runner`，传入：

| 参数 | 说明 |
|------|------|
| `to_fix_item` | 单条 validation item + 对应 finding 的 description/suggestion |
| `verification_cmds_json` | `$ROUNDS_DIR/baseline-cmds.json` |
| `baseline_json` | `$ROUNDS_DIR/baseline.json`（可能尚不存在，由 fix-runner 首次失败时自行调用 `baseline-verify.sh` 建立） |
| `baseline_verify_script` | `skills/diff-review/scripts/baseline-verify.sh` 绝对路径 |
| `output_dir` | `$ROUNDS_DIR` |
| `round` | 当前轮次 |
| `commit_enabled` | `--commit` 参数的值（`true`/`false`） |
| `base_ref` | 目标分支或 `--since` commit |

**硬约束**：
- **串行不并行**：git 工作树 + baseline 建立都是共享资源，并行会竞态
- **主 Skill 只看 JSON 返回**：每次 fix-runner 返回 `{status, commit_hash, patch_summary, verification, rollback_reason, pre_existing_failures_observed}` 结构化摘要；**不读 patch 内容、不读验证日志**
- **文件边界隔离**：fix-runner 只允许提交/回滚本条 finding 显式触达的文件，**禁止**用 repo 级 `git diff --name-only` 推断边界
- **异常处理**：fix-runner 抛错或 JSON 不合法 → 视为本条 `status=rolled_back`, `rollback_reason=agent-error`，继续下一条

**3. 汇总本轮修复**：

收集所有 fix-runner 返回的 JSON，合成 `$ROUNDS_DIR/fixes-round-$ROUND.json`：

```json
{
  "round": 1,
  "applied": [ { "id": "...", "commit_hash": "...", "patch_summary": "..." } ],
  "rolled_back": [ { "id": "...", "rollback_reason": "..." } ],
  "skipped": [ { "id": "...", "reason": "..." } ],
  "pre_existing_failures_observed": ["..."]
}
```

`rolled_back` 项在 Validation 状态上也要降级：本轮 validation JSON 中对应 item `class` 改为 `deferred`，`reason` 追加 `[rolled-back:<rollback_reason>]`，便于 Step 4.4 轮次报告和 Step 5 最终报告追溯。

**4. 预存在问题合并**：

聚合所有 fix-runner 的 `pre_existing_failures_observed` 去重后写入 `$ROUNDS_DIR/pre-existing.json`，Step 5 最终报告直接引用。

#### 4.4 轮次报告

写 `$ROUNDS_DIR/round-$ROUND.md`：
- 本轮 Codex findings 原始清单
- Validation 分类结果（to_fix / dismissed / deferred）
- 本轮实际修复的条目（含 commit hash）
- 回滚的条目（含失败原因）
- 本轮 dismissed 清单 + 理由（下一轮 Codex 必须看到）

#### 4.5 终止判定

顺序检查：

1. **成功终止**：本轮 Codex findings 中无 P1 且无 P2 → 终止（P3 无论是否修复都结束）
2. **达到上限**：`ROUND >= 5` → 终止，剩余 P1/P2 列入最终报告"未解决"段
3. **引擎完全失败**：`diff-reviewer` 返回 `engine = "failed"`（四层降级全部不可用，通常是 git 仓库损坏）→ 终止，记录错误
4. **本轮零修复且新一轮 findings 与上一轮指纹完全重合**（`location + description hash` 相同）→ 终止，避免死锁

否则 `ROUND++`，回到 4.1。

### Step 5: 生成最终报告

写 `$REVIEW_DIR/<current-branch>-vs-<target-branch>.md`：

- **元数据**：分支、时间、改动范围、技术栈、审查模式、总轮次、结束原因、各轮引擎（codex / agent-fallback）
- **总评**：1-3 句概括
- **轮次概览表**：每轮 `Codex P1/P2/P3 总数 · to_fix · dismissed · deferred · 已修复 · 回滚`
- **最终状态**：
  - 已修复（含 commit hash）
  - Dismissed（附 Validation 理由和 confidence）
  - 未解决 P1/P2（附原因：deferred / 达上限 / 死锁终止）
  - P3 总结（修了哪些、留了哪些）
- **预存在问题**：从 `baseline.json` 读取、在本次修复过程中被观察到但非本 PR 引入的问题（仅告知不修）
- **亮点**（可选）：做得好的地方，没有就省略
- **维度评分表**：逻辑/实践/简洁/安全/性能/复用/一致/Agent 友好度，各 /5

### Step 6: 任务清单（未解决 P1/P2 存在时追加）

报告末尾追加：

```markdown
## 任务清单
- [ ] P1 **<简明标题>** — `<文件:行号>` — <做什么>（原因：<deferred/round-limit/deadlock>）
- [ ] P2 **<简明标题>** — `<文件:行号>` — <做什么>（原因：...）
```

若 ≥ 5 条，额外写入 `<report-name>-tasks.md`。

### Step 7: 知识沉淀（`--compound on`）

`--depth quick` 跳过。

扫描所有轮次的 Codex findings + Validation 结果，识别**模式级问题**（同类错误 ≥ 2 次，或违反潜规则，或新反模式）。

对每个模式：
1. 按 `skills/shared/compound-schema.md` 的双轨 Schema 和 category 映射生成 solution doc
2. 写入 `docs/solutions/<category>/<date>-<slug>.md`
3. 在最终报告末尾追加"知识沉淀"摘要；如确实需要同步宿主规则，只在报告里给出**建议补丁**，不自动改 `CLAUDE.md` / `AGENTS.md`

沉淀原则详见共享 Schema 文档。**没有模式就不沉淀**——宁缺毋滥。

### Step 8: 清理中间产物

默认行为（`--keep-intermediates` off）：

```bash
rm -rf "$ROUNDS_DIR"
```

仅在 `--keep-intermediates` on 时保留 `.rounds/` 目录。

**永远保留**（不受清理影响）：
- 最终报告 `<current-branch>-vs-<target-branch>.md`
- 任务清单文件（如有）
- `docs/solutions/` 下的 solution docs
- 已修复的 commits

### Step 9: 遥测

流程结束时（任意结束条件），按 CLAUDE.md "Execution Telemetry" 章节调用 `record-outcome.sh`：

| 场景 | status | fallback_used |
|------|--------|---------------|
| 全部轮次 Codex（Skill 或 Bash）成功且所有 P1/P2 解决 | `success` | - |
| 任意轮次走到 `agent-fallback` 且最终完成 | `partial` | `agent-fallback` |
| 任意轮次走到 `native-inline` 且最终完成 | `partial` | `native-inline` |
| 达 5 轮上限仍有未解决 P1/P2 | `partial` | `round-limit` |
| 死锁终止（4.5 条件 4） | `partial` | `deadlock` |
| 全部引擎失败（`engine = failed`） | `failed` | - |

## 核心约束

1. **JSON 契约强制** — `diff-reviewer` 和 `validation-reviewer` 必须产出合法 JSON，格式错误一律视为引擎失败
2. **Dismissed 必须回喂** — 下一轮 Codex 调用必须携带 `dismissed_context`，Codex 不得重复标注已 dismissed 项（除非给出新证据）
3. **Confidence < 0.60 强制 dismissed** — 对齐 CLAUDE.md Confidence Gating 规范
4. **Baseline 惰性** — 不主动跑；仅在首次验证失败时加载，避免无失败情况下的性能损耗
5. **本轮引入才回滚** — 预存在失败保留修复、记入报告，不污染 PR 作者
6. **循环上限 5** — 达到即终止，不再审查
7. **清理默认 on** — `.rounds/` 仅作临时存储，流程结束即删；需审计轨迹则加 `--keep-intermediates`
8. **宿主规则文件默认只读** — `CLAUDE.md` / `AGENTS.md` 不属于 `rc:diff-review` 的默认写入面；只在报告中给建议，不自动落盘
