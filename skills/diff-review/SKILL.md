---
name: rc:diff-review
description: 对比目标分支进行代码审查并产出结构化报告。当用户说"review diff"、"帮我 review"、"review 这个分支"时触发。
argument-hint: "[target-branch] [--depth quick|standard|deep] [--focus security,performance] [--since commit] [--path filter] [--no-compound] [--no-commit]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, Agent
---

# Diff Review — 分支对比代码审查

对比当前分支与目标分支的所有改动，调用 Codex Companion 执行审查（降级时使用 Agent 多视角审查），通过多视角补充分析，自动修复严重问题，沉淀模式级知识，最多循环 3 轮。

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 目标分支 | `main` | 对比基准，如 `/diff-review main` |
| `--path` | 全部 | 限定审查范围，如 `--path backend/` 只审查后端 |
| `--depth` | `standard` | 审查深度：`quick`（跳过多视角补充和知识沉淀）/ `standard`（标准）/ `deep`（启用全部并行专家视角补充） |
| `--focus` | 全部 | 聚焦维度：`security` / `performance` / `logic` / `style` / `agent-native`，可组合如 `--focus security,performance`。传递给 Step 3 审查及多视角补充分析 |
| `--since` | 无 | 增量审查起点 commit hash，仅审查该 commit 之后的改动 |
| `--compound` | `on` | 知识沉淀：审查完成后自动识别模式级问题，生成 solution doc 并更新 CLAUDE.md。`--no-compound` 关闭 |
| `--commit` | `on` | 修复后自动创建独立 commit（每条修复一个 commit，可单独 `git revert`）。`--no-commit` 关闭，仅修改文件不提交 |

## 工作流程

严格按步骤执行，不要跳步。

### Step 1: 收集 Diff 并检测改动范围

#### 预处理脚本（优先）

优先调用预处理脚本快速收集 diff 元数据，减少后续 AI 处理的 token 开销：

```bash
# 定位预处理脚本（与 Codex Companion 相同的插件缓存路径模式）
# 优先级：插件缓存目录（已安装） > 本地开发目录（dev_workflow/）
PREPROCESS_SCRIPT=$(ls "$HOME/.claude/plugins/cache/ai-dev-workflow"/*/*/skills/diff-review/scripts/preprocess-diff.sh 2>/dev/null | tail -1)
if [ -z "$PREPROCESS_SCRIPT" ]; then
  for candidate in \
    "dev_workflow/skills/diff-review/scripts/preprocess-diff.sh" \
    "skills/diff-review/scripts/preprocess-diff.sh"; do
    [ -f "$candidate" ] && PREPROCESS_SCRIPT="$candidate" && break
  done
fi
if [ -n "$PREPROCESS_SCRIPT" ] && [ -x "$PREPROCESS_SCRIPT" ]; then
  PREPROCESS_JSON=$("$PREPROCESS_SCRIPT" "$TARGET_BRANCH" ${SINCE_COMMIT:+--since "$SINCE_COMMIT"} ${PATH_FILTER:+--path "$PATH_FILTER"})
  # 从 JSON 中提取: has_changes, diff_range, filtered_files, stats, modules, file_types, commit_summary
fi
```

如果脚本不存在或执行失败，降级到以下手动命令：

```bash
# 获取基本信息
CURRENT_BRANCH=$(git branch --show-current)
TARGET_BRANCH=${1:-main}

# 如果指定了 --since，使用 commit 范围而非分支对比
if [ -n "$SINCE_COMMIT" ]; then
  DIFF_RANGE="$SINCE_COMMIT...HEAD"
else
  DIFF_RANGE="$TARGET_BRANCH...HEAD"
fi

# 获取改动统计
git diff $DIFF_RANGE --stat
```

#### 无改动检测

如果 `git diff $DIFF_RANGE --name-only` 没有输出 → 告知用户"当前分支与目标分支无差异，无需 Review"，**结束流程**。

#### 模块覆盖检测

在审查前，先识别改动涉及了项目的哪些模块，并主动告知用户：

```bash
# 列出改动涉及的顶层目录（模块）
git diff $DIFF_RANGE --name-only | awk -F/ '{print $1}' | sort -u
```

将检测到的模块列表与项目实际结构对比。如果项目是 Monorepo（包含多个子目录如 `backend/`、`ios/`、`web/`、`shared/` 等），但本次改动只涉及其中部分模块，应在报告开头注明：

> 本次改动仅涉及 `backend/` 模块。其他模块（`ios/`、`web/`）未包含在此次审查中。如需全量审查，请切换到包含所有改动的分支，或分别执行 `--path ios/` 等。

#### 噪音过滤

自动排除不需要人工审查的文件，减少噪音：

```bash
git diff $DIFF_RANGE --stat -- \
  ':!*.lock' ':!*-lock.json' ':!*-lock.yaml' \
  ':!*.generated.*' ':!*.g.dart' ':!*.freezed.dart' \
  ':!*/migrations/*' \
  ':!*.min.js' ':!*.min.css' \
  ':!*.pbxproj'
```

#### 上下文理解

在审查之前，先建立整体理解：

1. **读 commit 历史** — `git log $DIFF_RANGE --oneline` 了解改动意图
2. **识别改动类型** — 是新增功能、重构、bugfix、配置变更、还是混合改动
3. **检查项目规范** — 如果存在 `CLAUDE.md`、`.editorconfig`、`CONTRIBUTING.md` 等，回顾其中的架构边界和代码约定
4. **识别语言和技术栈** — 根据文件扩展名和项目结构判断涉及的语言/框架
5. **检索已有 solutions** — 如果存在 `docs/solutions/` 目录，检索与本次改动相关的已沉淀模式，在审查时对照检查是否重蹈覆辙

### Step 2: 准备 Review 输出目录

```bash
TODAY=$(date +%Y-%m-%d)
REVIEW_DIR="docs/develop/reviews/${TODAY}"
mkdir -p "${REVIEW_DIR}"
```

报告文件名格式：`<current-branch>-vs-<target-branch>.md`（分支名中的 `/` 替换为 `-`）。

### Step 3: 执行 Code Review

设置轮次计数：`ROUND=1`（首轮）。

#### 3a. 首选方案 — 通过 Skill 工具调用 Codex Companion

优先使用 `Skill` 工具直接调用 `codex:review`（或 `codex:adversarial-review`）。Skill 调用由 Claude Code 框架管理 `CLAUDE_PLUGIN_ROOT` 等环境变量，无需手动拼路径。

**兼容性约束：**
- `codex:review` 是原生审查模式，**不支持自定义 focus text**，也不支持 `--path` 路径级过滤
- 需要自定义聚焦说明时使用 `codex:adversarial-review`
- 命中 `--path` 时应直接跳到 **Step 3b 降级方案**

**调用方式：**

在调用前，先解锁 Codex 命令的嵌套调用限制（插件更新可能会重置此标志）：

```bash
# 解锁 codex:review 和 codex:adversarial-review 的嵌套调用
for cmd in review adversarial-review; do
  CMD_FILE="$HOME/.claude/plugins/marketplaces/openai-codex/plugins/codex/commands/${cmd}.md"
  [ -f "$CMD_FILE" ] && sed -i '' 's/disable-model-invocation: true/disable-model-invocation: false/' "$CMD_FILE"
done
```

然后通过 `Skill` 工具调用，其中 `REVIEW_BASE_REF="${SINCE_COMMIT:-$TARGET_BRANCH}"`：

```
# 无 --path 且无 --focus 时：原生 review
Skill("codex:review", "--wait --base ${REVIEW_BASE_REF}")

# 无 --path 但有 --focus 时：adversarial-review 支持额外聚焦说明
Skill("codex:adversarial-review", "--wait --base ${REVIEW_BASE_REF} Review branch changes. Focus on: ${FOCUS}.")
```

**降级到 Bash 直调：** 如果 `Skill` 调用失败（例如 Codex 插件未安装或命令不可用），降级为 Bash 直接调用底层脚本：

```bash
CODEX_SCRIPT=$(ls "$HOME/.claude/plugins/cache/openai-codex/codex"/*/scripts/codex-companion.mjs 2>/dev/null | tail -1)
REVIEW_BASE_REF="${SINCE_COMMIT:-$TARGET_BRANCH}"

if [ -n "$CODEX_SCRIPT" ]; then
  if [ -n "$FOCUS" ]; then
    FOCUS_TEXT="Review branch changes against ${REVIEW_BASE_REF}. Focus on: ${FOCUS}."
    node "$CODEX_SCRIPT" adversarial-review --wait --base "$REVIEW_BASE_REF" "$FOCUS_TEXT"
  else
    node "$CODEX_SCRIPT" review --wait --base "$REVIEW_BASE_REF"
  fi
fi
```

如果成功，将输出用 `Write` 工具保存到 `${REVIEW_DIR}/review-round-${ROUND}.md`，保持原始输出不做任何修改。

#### 3b. 降级方案 — Agent 多视角审查

如果出现以下任一情况，改用 `Agent` 工具进行审查：
- Codex Companion Skill 调用和 Bash 直调均失败
- 指定了 `--path`（需要精确路径级 diff 过滤）

1. 先用 `Bash` 获取完整 diff：`git diff $DIFF_RANGE`
2. 使用 `Agent` 工具，`subagent_type` 设为 `feature-dev:code-reviewer`
3. 在 prompt 中传入 diff 内容和项目上下文（CLAUDE.md 中的架构边界、代码约定等）
4. 如果指定了 `--path`，先生成 scoped diff：`git diff $DIFF_RANGE -- "$PATH_FILTER"`，只把该范围的 diff 传给 Agent
5. 要求 Agent 按照 P1（严重）/ P2（建议）/ P3（可选）分级输出审查结果
6. 如果指定了 `--focus` 参数，将聚焦维度传递给 Agent

将审查结果保存到 `${REVIEW_DIR}/review-round-${ROUND}.md`。

**异常处理：**
- 如果两种方案都失败 → 将错误信息记录到 `${REVIEW_DIR}/review-error.md`，告知用户并**结束流程**（结束条件 1）

### Step 4: 阅读、分析与多视角补充

#### 4a. 分析审查输出

仔细阅读 `${REVIEW_DIR}/review-round-${ROUND}.md` 的内容，对每个 Review 发现进行分类：

**P1 — 必须修复（Critical/Must-Fix）：**
- Bug / 逻辑错误
- 安全漏洞
- 数据丢失风险
- API 使用错误
- 严重的性能问题

**P2 — 建议优化（Should-Fix）：**
- 最佳实践违规
- 设计过度复杂
- 潜在性能问题
- 一致性问题

**P3 — 可选改进（Nice-to-Have）：**
- 代码风格 / 命名规范
- 轻微的代码重复
- 注释缺失
- 微小的性能优化
- 重构建议

#### 4b. 语言感知二次校验

根据 Step 1 检测到的技术栈，对照下方语言矩阵，检查 Step 3 的审查输出是否遗漏了该语言的关键维度。**不重新审查代码**，只检查审查输出的覆盖度，补充遗漏的发现。

| 文件类型 | 必须覆盖的关键维度 |
|----------|-------------------|
| `.swift` | 内存管理（循环引用、weak/unowned）、Swift Concurrency（actor 隔离、Sendable 合规）、值类型 vs 引用类型选择、@MainActor 使用、可选值链式处理 |
| `.m` / `.mm` | retain cycle、block 捕获语义、nullability 注解、ARC 下的内存模式 |
| `.kt` | 协程作用域管理（viewModelScope vs lifecycleScope vs GlobalScope）、空安全、data class 适用性、Flow 收集方式（stateIn vs shareIn）、Compose 重组优化 |
| `.java` | 资源泄漏（try-with-resources）、并发安全（synchronized vs concurrent 集合）、Optional 使用 |
| `.dart` | Widget 重建优化（const constructor、shouldRebuild）、State 管理模式、dispose 资源释放、BuildContext 跨异步使用 |
| `.py` | 类型标注完整性、async/await 模式、上下文管理器使用、可变默认参数陷阱、dataclass/Pydantic 选型 |
| `.ts` / `.tsx` | 类型收窄、any 滥用、React hooks 依赖数组、useEffect 清理、服务端/客户端边界（RSC） |
| `.js` / `.jsx` | 同 `.ts` 但额外关注缺少类型检查带来的运行时风险 |
| `.go` | error 处理是否遗漏、goroutine 泄漏、context 传播、defer 使用、race condition（-race flag） |
| `.rs` | 所有权和借用、生命周期标注、unwrap 滥用、unsafe 块审查、clippy lint 合规 |
| `.rb` | N+1 查询（Rails）、Strong Parameters、回调链复杂度、eager loading |
| `.sql` | 注入风险、索引使用、事务边界、死锁风险 |

如果遇到上表未列出的语言，基于该语言社区公认的最佳实践进行校验。

#### 4c. 多视角补充分析 — 并行置信度门控（`--depth standard` 及以上）

在 Step 3 审查输出的基础上，用以下专项视角扫描是否有遗漏。`--depth quick` 跳过此步。`--depth deep` 执行全部视角；`--depth standard` 仅执行前三个核心视角。

如果指定了 `--focus` 参数，只执行与聚焦维度相关的视角。

**并行派发**：每个视角作为独立 `Agent` 子代理并行执行（使用对应的 `subagent_type`）。每个子代理接收 Step 3 审查输出 + diff 全文 + 项目上下文，独立产出发现列表。

| 视角 | 代号 | subagent_type | 补充检查范围 | depth 级别 |
|------|------|---------------|-------------|-----------|
| **安全哨兵** | `security-sentinel` | `compound-engineering:review:security-reviewer` | OWASP Top 10、注入攻击、认证/授权缺陷、硬编码密钥、敏感数据泄露 | standard+ |
| **性能探针** | `performance-oracle` | `compound-engineering:review:performance-reviewer` | N+1 查询、缺失索引、O(n^2)+ 算法、不必要的同步阻塞、缓存机会 | standard+ |
| **架构守卫** | `architecture-strategist` | `compound-engineering:review:maintainability-reviewer` | 依赖方向、分层边界违规、接口向后兼容性、组件职责单一性、跨模块影响 | standard+ |
| **Agent 友好度** | `agent-native-reviewer` | `compound-engineering:review:agent-native-reviewer` | AI agent 可访问性——日志结构化、配置可编程读取、操作可 CLI/API 完成 | deep |
| **数据完整性** | `data-integrity-guardian` | `compound-engineering:review:data-integrity-guardian` | 事务边界、引用完整性、迁移安全性、生产数据验证 | deep |

**置信度门控**：每个子代理对其发现标注 confidence（0.0-1.0）：

| 置信度范围 | 处理 |
|-----------|------|
| < 0.50 | 丢弃 |
| 0.50-0.59 | 仅保留 P1 级别 |
| >= 0.60 | 保留 |

**指纹去重**：使用 `normalize(file) + line_bucket(+/-3) + normalize(title)` 生成指纹。同一指纹的发现只保留最高优先级。

**跨视角一致性加成**：如果 2+ 个视角独立标记同一指纹，置信度 +0.10（上限 1.0）。

**修复分级合并**：同一发现被多视角标记不同 autofix_class 时，取最保守级别。

#### 4d. 保存分析结论

将分析结论保存到 `${REVIEW_DIR}/analysis-round-${ROUND}.md`，内容包含：
- 本轮审查发现汇总
- 语言感知校验补充（如有）
- 多视角补充发现（如有，标注来源 `[<代号>]`）
- P1 问题列表（含文件路径和行号）
- P2 问题列表
- P3 问题列表
- 决策说明（为什么某些问题必须修，某些可以跳过）
- 关联的已有 solution（如果 `docs/solutions/` 中有相关记录）

### Step 5: 分级修复

#### 5a. 修复分级

对每个 P1 问题（以及用户显式要求修复的 P2），先分级再处理：

| 修复类型 | 适用场景 | 处理方式 |
|---------|---------|---------|
| `safe_auto` | 格式修正、import 排序、命名规范、死代码删除、简单类型标注 | 直接修复，无需确认 |
| `gated_auto` | 行为变更、API 契约修改、认证/授权相关、数据模型变更 | 修复后用 `AskUserQuestion` 请求用户确认 |
| `manual` | 需要设计决策、多种合理方案、涉及业务逻辑判断 | 仅报告问题和建议方案，不修改代码 |
| `advisory` | 信息性发现、风格偏好、可选优化 | 仅记录到报告，不修改代码 |

#### 5b. 执行修复

- 逐个修复 `safe_auto` 和 `gated_auto` 问题
- 每个修复后简要说明修复方案
- 如果 `--commit` 为 `on`（默认），每条修复创建独立 git commit，commit message 格式：`fix(review): P1 <问题简述>`
- 如果 `--no-commit`，仅修改文件不提交
- `gated_auto` 修复在提交前须经用户确认
- 每条修复后运行 lint/typecheck（如果项目配置了的话），确保不引入新问题
- 将修复记录保存到 `${REVIEW_DIR}/fixes-round-${ROUND}.md`，格式如下：

```markdown
# Round ${ROUND} 修复记录

## 修复项 1: [问题简述]
- **优先级**: P1
- **修复类型**: safe_auto / gated_auto
- **文件**: path/to/file.py
- **问题**: 具体问题描述
- **来源**: Codex Companion / Agent Review / [补充视角代号]
- **方案**: 修复方案说明
- **变更**: 具体改了什么
- **Commit**: `abc1234`（如 --no-commit 则标注"未提交"）
- **状态**: 已修复 / 用户已确认 / 待用户确认

## 未修复项: [问题简述]
- **优先级**: P1
- **修复类型**: manual
- **文件**: path/to/file.py
- **问题**: 具体问题描述
- **建议方案**: ...
- **状态**: 需人工处理
```

### Step 6: 判断是否继续循环

检查以下结束条件：

1. **结束条件 1 - 服务异常**: 审查引擎不可用或报错 → 记录错误并结束
2. **结束条件 2 - 全部修复**: 上一轮没有 P1 问题 → 输出总结并结束
3. **结束条件 3 - 达到轮次上限**: ROUND >= 3 → 输出总结并结束（如有未修复的问题，列出并说明原因）

如果不满足任何结束条件：
- `ROUND = ROUND + 1`
- 回到 **Step 3**，重新执行审查（每轮都对完整 diff `TARGET_BRANCH...HEAD` 重新审查，确保修复后的代码也被覆盖）

### Step 7: 输出最终报告

在所有轮次结束后，生成结构化报告 `${REVIEW_DIR}/<current-branch>-vs-<target-branch>.md`：

```markdown
# Code Review Report

**分支**: `<current-branch>` vs `<target-branch>`
**审查时间**: <YYYY-MM-DD HH:mm>
**改动范围**: <N> 个文件, +<additions> / -<deletions>
**改动类型**: <新功能 / Bugfix / 重构 / 配置变更 / 混合>
**涉及模块**: <backend, ios, web 等>
**技术栈**: <Python, Swift, TypeScript 等>
**审查模式**: Codex Companion / Agent 多视角审查 + 迭代修复（depth: <quick/standard/deep>）
**总轮次**: <N>
**结束原因**: [全部修复 / 达到轮次上限 / 服务异常]

> [仅当适用时] 本次审查仅涉及 `<module>/` 模块，其他模块未包含在审查范围内。

## 总评

<1-3 句话概括改动质量和整体评价>

## 各轮次概览

| 轮次 | 发现问题数 | P1 | P2 | P3 | 已修复 | 补充发现 |
|------|-----------|----|----|-----|--------|---------|
| 1    | X         | Y  | Z  | W   | N      | M       |
| ...  | ...       | ...| ...| ... | ...    | ...     |

## 最终状态

- 已修复的问题列表（含 commit hash）
- 跳过的 P2/P3 问题列表（附原因）
- 需人工确认的修复（附原因）
- 未修复的 P1 问题（如有，附原因）

## 发现的问题

### P1 严重（必须修复）

<逻辑错误、安全漏洞、数据丢失风险、崩溃风险等>

**格式要求**：每个问题包含——
- 位置：`文件名:行号`
- 来源：`Codex Companion` / `Agent Review` / `[补充视角代号]`
- 描述：问题是什么，为什么是问题
- 影响：可能导致什么后果
- 建议：推荐的修复方式
- 关联：`docs/solutions/xxx.md`（如果已有相关 solution，引用之）
- 状态：已修复 Round N `<commit>` / 需人工确认 / 未修复（原因）

### P2 建议（强烈推荐修复）

<最佳实践违规、设计过度复杂、一致性问题、潜在性能问题等>

### P3 可选（改了更好）

<代码风格、微小优化、可读性提升等>

## 亮点

<改动中做得好的地方 — 好的审查不只找问题。如果确实没有值得称赞的地方，省略此节。>

## 总结

| 维度 | 评分 | 说明 |
|------|------|------|
| 逻辑正确性 | /5 | ... |
| 最佳实践 | /5 | ... |
| 设计简洁度 | /5 | ... |
| 安全性 | /5 | ... |
| 性能 | /5 | ... |
| 代码复用 | /5 | ... |
| 一致性 | /5 | ... |
| Agent 友好度 | /5 | ... |
```

### Step 8: 生成任务清单

审查完成后，如果仍有未修复的 P1 或 P2 级别的问题，在报告末尾追加可执行的任务清单。如果所有 P1/P2 问题都已修复或只剩 P3 级别，则跳过此步骤。

#### 任务清单规则

1. **只纳入未修复的 P1 和 P2 级别问题** — 已修复的不再列入，P3 问题不进入任务清单
2. **按优先级排序** — P1 排在前面，P2 排在后面
3. **每条任务可直接执行** — 包含具体的文件、位置和操作，开发者无需回溯上下文
4. **合并同类项** — 如果多个问题指向同一根因，合并为一条任务
5. **标注预估影响范围** — 帮助开发者判断修改的风险和关联
6. **标注来源** — 标注该任务由 Step 3 审查还是哪个补充视角发现

#### 任务清单追加到报告末尾

```markdown
## 任务清单

> 以下任务从审查中未修复的 P1 和 P2 问题中提取，按优先级排序。

- [ ] P1 **<简明任务标题>** — `<文件名:行号>` — <一句话说明要做什么> `[<来源>]`
- [ ] P2 **<简明任务标题>** — `<文件名:行号>` — <一句话说明要做什么> `[<来源>]`
```

#### 同时输出独立任务文件（可选）

如果任务数量 >= 5 条，额外生成独立任务文件：

- 路径：与报告同目录，文件名后缀 `-tasks.md`
- 示例：`docs/develop/reviews/2026-04-05/feature-auth-vs-main-tasks.md`

```markdown
# Review Tasks

**关联审查报告**: `<report-filename>.md`
**生成时间**: <YYYY-MM-DD HH:mm>
**待修复**: <N> 项（P1 <n1> 项, P2 <n2> 项）

---

- [ ] P1 ...
- [ ] P2 ...
```

### Step 9: 知识沉淀（默认执行，`--no-compound` 关闭）

审查全部轮次结束后，扫描所有轮次发现的 P1 和 P2 问题（含 Step 3 审查发现和多视角补充发现），识别是否存在 **模式级问题**。

`--depth quick` 时跳过此步。

#### 什么是模式级问题

- 同一类错误在本次审查或历史审查中出现 >= 2 次（跨轮次也算）
- 违反了未被显式记录的架构约定（发现了"潜规则"）
- 引入了新的反模式，值得作为团队知识沉淀
- 语言感知校验发现 Step 3 审查系统性遗漏某类维度（说明团队在这个维度缺少意识）

#### 沉淀流程

1. **识别模式**: 从全部轮次的发现中提取可泛化的模式（不是具体的某行代码错误，而是"这类错误"的本质）

2. **分轨判定**: 根据问题性质选择 Bug Track 或 Knowledge Track

| 轨道 | 适用场景 |
|------|---------|
| **Bug Track** | 构建错误、运行时错误、配置错误、集成失败等具体问题 |
| **Knowledge Track** | 最佳实践、工作流改进、架构约定、性能优化等可泛化知识 |

3. **生成 solution doc**: 写入 `docs/solutions/<category>/` 目录，使用 compound-engineering 双轨 schema

**category -> 目录映射**：

| problem_type | 目录 |
|-------------|------|
| `build_error` | `docs/solutions/build/` |
| `runtime_error` | `docs/solutions/runtime/` |
| `config_error` | `docs/solutions/config/` |
| `integration_issue` | `docs/solutions/integration/` |
| `best_practice` | `docs/solutions/best-practices/` |
| `workflow_issue` | `docs/solutions/workflow/` |
| `architecture` | `docs/solutions/architecture/` |
| `performance` | `docs/solutions/performance/` |

**YAML Frontmatter（必填字段）**：

```yaml
---
# 共享必填
module: <模块名>
date: YYYY-MM-DD
problem_type: <见上方 category 映射>
component: <具体组件>
severity: <P0|P1|P2|P3>

# Bug Track 额外必填
symptoms: [症状列表]
root_cause: 根因描述
resolution_type: <code_fix|config_change|dependency_update|workaround|documentation>

# Knowledge Track 无额外必填

# 可选（推荐填写）
tags: [tag1, tag2]
languages: [swift, python, ...]
source_review: <关联审查报告路径>
---
```

**正文模板**：

- **Bug Track**：Problem -> Symptoms -> What Didn't Work -> Solution -> Why This Works -> Prevention -> Related Issues
- **Knowledge Track**：Context -> Guidance -> Why This Matters -> When to Apply -> Examples -> Related

**文件命名**：`{date}-{slug}.md`（如 `2026-04-10-ws-reconnect-race.md`）

3. **更新 CLAUDE.md**: 在 CLAUDE.md 的相应 section 追加一行简要规则引用

```markdown
# CLAUDE.md 追加示例
## Code Patterns
- WebSocket 重连必须先检查连接状态再操作 shared state（详见 docs/solutions/concurrency/2026-04-05-ws-reconnect-race.md）
```

4. **报告标注**: 在审查报告末尾追加沉淀摘要

```markdown
## 知识沉淀

本次审查沉淀了以下模式：
- `docs/solutions/concurrency/2026-04-05-ws-reconnect-race.md` — WebSocket 断连竞态模式
- 已更新 CLAUDE.md: Code Patterns section
```

#### 沉淀原则

- **只沉淀模式，不沉淀实例。** solution doc 描述的是一类问题，不是某一行代码。
- **宁缺毋滥。** 如果本次审查没有发现模式级问题，不要硬凑 solution。跳过即可。
- **可检索优先。** YAML frontmatter 的 tags 和 category 要准确，方便未来 agent 在 Step 1 上下文理解中通过 `docs/solutions/` 检索命中。
- **增量更新。** 如果已有 solution doc 描述了相似问题，更新已有文档而非创建新文档。

## 重要提醒

1. **不要修改 Review 报告本身** — `review-round-N.md` 是审查引擎的原始输出，应该保持原样
2. **如果审查输出格式不确定**，先完整阅读输出，再做分析判断
3. **保持每轮报告独立** — 使用 round-N 后缀区分不同轮次的文件
4. 如果没有发现某个严重级别的问题，省略该级别（不要写"无"）
5. 增量审查（`--since`）时在报告标题注明是增量审查，并记录起始 commit hash，方便下次继续
6. **任务清单仅在存在未修复的 P1 或 P2 问题时生成** — 代码质量好时不要硬凑任务
7. **知识沉淀默认开启**，但仅在确实发现模式级问题时才生成 solution——不要硬凑。使用 `--no-compound` 关闭
8. **多视角补充只补充 Step 3 审查的遗漏** — 每个视角作为独立 Agent 并行执行，置信度 < 0.50 丢弃，0.50-0.59 仅保留 P1，>= 0.60 保留，跨视角一致 +0.10
9. **语言感知校验是 checklist 校验** — 对照矩阵检查 Step 3 审查输出的覆盖度，而非独立做一遍完整审查
10. **修复分级必须遵守** — `safe_auto` 直接修复，`gated_auto` 必须经用户确认，`manual`/`advisory` 不修改代码
11. **知识沉淀使用 compound-engineering 双轨 schema** — Bug Track / Knowledge Track，与 `ce:compound` 共享知识池
