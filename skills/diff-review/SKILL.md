---
name: rc:diff-review
description: 对比目标分支进行代码审查并产出结构化报告。当用户说"review diff"、"帮我 review"、"review 这个分支"时触发。
argument-hint: "[target-branch] [--depth quick|standard|deep] [--focus security,performance] [--since commit] [--path filter] [--no-compound] [--no-commit]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
---

# Diff Review — 分支对比代码审查

对比当前分支与目标分支，调用 `diff-reviewer` agent 执行审查，对发现的 P1/P2 分级修复，最多循环 3 轮，可选知识沉淀。

具体审查逻辑在 `agents/workflow/diff-reviewer.md`。本 Skill 负责编排：参数解析、diff 收集、修复执行、报告生成、知识沉淀。

## 参数

| 参数 | 默认 | 说明 |
|------|------|------|
| 目标分支 | `main` | 对比基准 |
| `--depth` | `standard` | `quick`（跳过多视角和沉淀）/ `standard` / `deep`（全部视角） |
| `--focus` | 全部 | `security` / `performance` / `logic` / `style` / `agent-native`，可组合 |
| `--since` | 无 | 增量审查起点 commit |
| `--path` | 全部 | 路径过滤，如 `backend/` |
| `--compound` | `on` | 知识沉淀。`--no-compound` 关闭 |
| `--commit` | `on` | 每条修复独立 commit。`--no-commit` 仅改文件 |

## 工作流程

### Step 1: 收集 diff + 上下文

1. **预处理脚本**（优先）：定位 `skills/diff-review/scripts/preprocess-diff.sh`（插件缓存或本地），传入 `target_branch` / `--since` / `--path`，获取 diff 范围、改动文件、模块列表
2. **降级手动**：脚本不可用时用 `git diff <base>...HEAD --stat` 和 `--name-only`
3. **无改动** → 结束："当前分支与目标分支无差异"
4. **模块覆盖检测**：Monorepo 仅改部分模块时，在报告开头注明
5. **噪音过滤**：排除 `*.lock`、`*.generated.*`、`*/migrations/*`、`*.min.*`、`*.pbxproj`
6. **上下文理解**：读 CLAUDE.md、`docs/solutions/` 相关条目、`skills/shared/known-issues.md`、commit 历史

### Step 2: 准备输出目录

```bash
REVIEW_DIR="docs/develop/reviews/$(date +%Y-%m-%d)"
if ! mkdir -p "$REVIEW_DIR"; then
  echo "ERROR: cannot create $REVIEW_DIR (cwd=$PWD, exit=$?). Aborting review." >&2
  exit 1
fi
[ -w "$REVIEW_DIR" ] || { echo "ERROR: $REVIEW_DIR is not writable."; exit 1; }
```

报告文件名：`<current-branch>-vs-<target-branch>.md`（`/` 替换为 `-`）。

### Step 3: 执行审查（循环，最多 3 轮）

`ROUND=1` 起，每轮执行：

1. 调用 `ai-dev-workflow:workflow:diff-reviewer` agent，传入：
   - `diff_range`：`<base>...HEAD`（base 为 `--since` 或目标分支）
   - `output_dir`：`$REVIEW_DIR`
   - `round`：当前轮次
   - `path_filter` / `focus` / `depth`：按参数透传
2. Agent 返回结构化 findings 清单（P1/P2/P3 + file + line + autofix_class + source）
3. 将分析结论写入 `$REVIEW_DIR/analysis-round-$ROUND.md`（供报告引用）

### Step 4: 分级修复

对 Agent 返回的 P1 + 用户显式要求的 P2：

| `autofix_class` | 处理 |
|----------------|------|
| `safe_auto` | 直接修复 |
| `gated_auto` | 修复后用 `AskUserQuestion` 请求确认 |
| `manual` | 仅报告问题和建议方案，不改代码 |
| `advisory` | 仅记录到报告 |

每条修复：
- 修改后运行 lint/typecheck（若项目配置）
- `--commit on`：每条独立 commit，格式 `fix(review): P1 <问题简述>`
- `--commit off`：仅改文件

修复记录写入 `$REVIEW_DIR/fixes-round-$ROUND.md`。

### Step 5: 判断是否继续

三条结束条件：
1. Agent 返回空 findings 或无 P1 → 输出总结，结束
2. `ROUND >= 3` → 输出总结（未修复项列出原因），结束
3. Agent 报错（`review-error.md` 存在）→ 记录错误，结束

否则 `ROUND++`，回到 Step 3（新一轮针对完整 diff 重新审查，覆盖已修复代码）。

### Step 6: 生成最终报告

写入 `$REVIEW_DIR/<current-branch>-vs-<target-branch>.md`：

- **元数据**：分支、时间、改动范围、技术栈、审查模式、总轮次、结束原因
- **总评**：1-3 句概括
- **轮次概览表**：每轮 P1/P2/P3 数 + 已修复数
- **最终状态**：已修复（含 commit hash）、已跳过 P2/P3（附原因）、需人工确认、未修复 P1（附原因）
- **问题清单**：P1/P2/P3 分组，每条含位置、来源、描述、影响、建议、关联 solution、状态
- **亮点**（可选）：做得好的地方，没有就省略
- **维度评分表**：逻辑/实践/简洁/安全/性能/复用/一致/Agent 友好度，各 /5

### Step 7: 任务清单（未修复 P1/P2 存在时追加）

报告末尾追加：

```markdown
## 任务清单
- [ ] P1 **<简明标题>** — `<文件:行号>` — <做什么> `[<来源>]`
- [ ] P2 **<简明标题>** — `<文件:行号>` — <做什么> `[<来源>]`
```

若 ≥ 5 条，额外写入 `<report-name>-tasks.md`。

### Step 8: 知识沉淀（`--compound on`）

`--depth quick` 跳过。

扫描所有轮次的 P1/P2 发现，识别**模式级问题**（同类错误 ≥ 2 次，或违反潜规则，或新反模式）。

对每个模式：
1. 按 `skills/shared/compound-schema.md` 的双轨 Schema 和 category 映射生成 solution doc
2. 写入 `docs/solutions/<category>/<date>-<slug>.md`
3. 在 CLAUDE.md 相应 section 追加一行规则引用
4. 在审查报告末尾追加"知识沉淀"摘要

沉淀原则详见共享 Schema 文档。

### Step 9: 遥测

流程结束时（任意结束条件），按 CLAUDE.md "Execution Telemetry" 章节调用 `record-outcome.sh`。状态映射：

| 场景 | status |
|------|--------|
| Codex 主路径成功 / 无 P1 | `success` |
| Codex 失败但降级成功 | `partial`（fallback: `agent`） |
| 全部引擎不可用 | `failed` |

## 核心约束

1. **审查原始输出不修改** — `review-round-N.md` 保持原样
2. **修复分级必须遵守** — `safe_auto` 直接做，`gated_auto` 必须确认，`manual/advisory` 不改代码
3. **每轮针对完整 diff** — 修复后的代码也要被新一轮覆盖
4. **没有模式就不沉淀** — 宁缺毋滥
5. **任务清单仅在有未修复 P1/P2 时生成** — 代码质量好时不硬凑
