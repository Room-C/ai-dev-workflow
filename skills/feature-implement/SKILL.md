---
name: rc:feature-implement
description: 功能实现 — 将设计报告拆解为任务清单并逐任务自主执行，一条命令完成从 plan 到 code 的全流程。
argument-hint: "<module> [design-path] [--skip N,M,...] [--start-from N] [--strict-verify]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
model: sonnet
---

# Feature Implement — 功能实现

将 `design.md` 拆解为可执行的任务清单（`tasks.md`），然后按依赖顺序逐任务自主实现。所有文档和状态报告使用中文。

## 输入

- **module**: 模块名称（必需）
- **design_path**: design.md 路径（可选，未提供时搜索 `docs/features/{module}/{version}/design.md`）
- **skip_tasks**: 要跳过的任务编号列表（可选）
- **start_from**: 从第 N 个任务开始（可选，断点续执行）
- **strict_verify**: 强制全量验证（可选）

## 整体流程

```
design.md → Phase 1: Plan (→ tasks.md) → Phase 2: Execute (→ 代码 + 验证) → Phase 3: 收尾
```

**状态标记**：⬜ 待处理 → 🔧 已实现待验证 → ✅ 已完成 / ⚠️ 验证未通过

---

## Phase 1: Plan — 任务拆解

### Step 1.1: 阅读设计

1. 读取项目 CLAUDE.md（架构边界、代码规范、验证命令）
2. 读取 `skills/shared/known-issues.md`，主动规避匹配场景
3. 读取 design.md（用户提供路径或搜索 `docs/features/{module}/{version}/design.md`）
4. 读取 analysis.md（如果存在）

### Step 1.2: 检查是否可跳过 Phase 1

如果 tasks.md 已存在且包含有效任务列表：

- **存在 ⬜ 任务** → 跳过 Phase 1，进入 Phase 2（断点续执行）
- **全部 ✅** → 提示用户是否需要重新规划
- **不存在** → 继续 Step 1.3

### Step 1.3: 拆解任务

派发 decomposer agent（`ai-dev-workflow:design:decomposer`），传入 design.md 内容、module 名称、项目目录结构、输出路径。

输出写入 `docs/features/{module}/{version}/tasks.md`（design.md 在 `{side}/` 子目录则写入同一子目录）。确认格式正确后进入 Phase 2。

---

## Phase 2: Execute — 逐任务实现

### Step 2.0: 环境检查

1. 读取 tasks.md，确认存在且格式正确
2. **从项目 CLAUDE.md 的 Verification 章节读取验证命令**（无此章节则提示用户补充）
3. 确保 git 工作区干净，当前分支不是主分支

### Step 2.0.5: 基线快照

在执行任务前，自动检测验证基线状态，决定使用**全量验证**还是**增量验证**。`--strict-verify` 时跳过此步，直接全量。

**流程**：

1. 已有 `.baseline-snapshot.json` 且 < 24 小时 → 复用，跳到第 4 步
2. 逐个运行 CLAUDE.md 验证命令，捕获输出，统计错误数（stderr 行数 + stdout 中 `error`/`Error`/`ERROR`/`FAILED` 行数去重；pytest 额外解析 `N failed`）
3. 写入 `.baseline-snapshot.json`（与 tasks.md 同目录）：`{ captured_at, baseline_mode, commands: { <id>: { command, exit_code, error_count, failed_tests, output_digest(前20行) } } }`
4. 判定：全部 exit_code==0 且 error_count==0 → `clean`，否则 → `delta`
5. 汇报：clean → `✅ 全量验证模式` / delta → `⚠️ 检测到 N 个预存错误，增量验证模式`

### Step 2.1: 解析任务清单

1. 解析"执行顺序"摘要表：任务编号、状态、依赖、并行标记
2. 解析每个任务详情：目标文件、改动类型、子任务、代码骨架
3. 提取红线（❌ 标记，绝对不实现）
4. 跳过 ✅ 任务；如有 `start_from` 则跳到对应任务
5. 向用户报告：共 N 个任务，M 个待执行，K 个已完成

### Step 2.2: 逐任务执行

#### 判断复杂度

| 条件 | 简单（主代理直接执行） | 复杂（派发 task-runner） |
|------|----------------------|------------------------|
| 文件数 | 1 个 | 多个 |
| 子任务数 | ≤ 3 | > 3 |
| 代码量 | < 100 行 | ≥ 100 行 |

**全部满足"简单"→ 主代理执行，否则 → 子代理。**

#### 主代理直接执行

读取目标文件 → 按代码骨架实现 → 确保 import 正确、风格一致、不越界。优势：已有前序任务完整上下文。

#### 派发 task-runner 子代理

```
Agent({ subagent_type: "ai-dev-workflow:workflow:task-runner", prompt: 任务详情 + design.md 路径 + 红线 + 项目约定 })
```

**并行**：无依赖且不操作同一文件的复杂任务可同时派发，全部完成后统一更新状态。

#### 更新状态

实现完成后 ⬜ → 🔧，同步更新子任务和摘要表。仅批量验证（Step 2.3）通过后才 🔧 → ✅。

### Step 2.3: 批量验证

按阶段批量验证，不逐任务验证。阶段：① 数据模型/Schema → ② 服务层/逻辑 → ③ 路由/UI → ④ 配置/收尾。无明显阶段时按每 3-5 个任务一批。

**验证命令来源**：项目 CLAUDE.md 的 Verification 章节，不硬编码。

#### 路径 A — 全量验证（clean 模式或 --strict-verify）

运行构建 + 测试验证 → 通过则 🔧 → ✅。

#### 路径 B — 增量验证（delta 模式）

1. 运行验证命令，提取当前错误计数
2. 对比 `.baseline-snapshot.json`：当前 ≤ 基线 → 通过；当前 > 基线 → 提取新增错误
3. 测试特殊处理：排除基线已失败的测试（如 `pytest --deselect`）
4. 全部通过 → 🔧 → ✅，汇报 `验证通过 (增量模式, 基线 N 个预存错误)`

#### 验证失败处理

1. 分析错误，尝试修复（最多 2 次）
2. 修复后通过 → 继续
3. 2 次仍失败 → 状态 → ⚠️，记录错误，**停止执行**（不跳过），向用户报告
4. 增量模式下区分"新引入"vs"基线恶化"

### Step 2.4: 报告进度

每阶段完成后：`✅ [N-M/Total] 阶段：[摘要] | 验证：构建 ✅ / 测试 ✅ | 变更文件：[列表]`

### Step 2.5: 提交（需用户确认）

默认不自动提交。所有任务完成后汇报结果，由用户决定。提交时：

- 将 tasks.md 状态更新一并提交
- Conventional commit 格式：新建 → `feat`，修改 → `refactor`/`fix`，配置 → `chore`
- 遵循项目已有的 git commit 约定

---

## Phase 3: 收尾

### Step 3.1: 生成实现报告

写入 tasks.md 同级 `implementation-report.md`，包含：概要（计划文件、日期、任务统计）、提交记录表、验证结果、备注。

### Step 3.2: 清理中间产物

删除 analyze → design 阶段的中间产物，这些文件在实现完成后不再有用：

```bash
FEATURE_DIR="$(dirname "{tasks_path}")"
rm -f "$FEATURE_DIR/.context-snapshot.md"
rm -f "$FEATURE_DIR/.baseline-snapshot.json"
rm -rf "$FEATURE_DIR/reviews/"
```

静默执行，文件不存在时跳过，不输出任何内容。

### Step 3.3: 提示用户

```
✅ 所有任务已完成并通过验证。

📋 后续可选操作：
   - 运行 /rc:commit-pr 提交代码并创建 PR
   - 运行 /rc:feature-archive {module} 归档关键决策和经验教训
```

### Step 3.4: 执行遥测

按 CLAUDE.md "Execution Telemetry" 章节记录遥测（status: success / partial / failed）。脚本不存在则跳过。

---

## 核心原则

1. **依赖顺序是铁律**：数据模型 → 服务层 → 路由/UI，不可跳跃
2. **代码骨架 ≠ 完整实现**：给出足够结构让执行器理解意图
3. **红线从 design.md 提取**：不自行增减"暂不实现"的范围
4. **简单任务直接做**：主代理有完整上下文，小任务不需要子代理
