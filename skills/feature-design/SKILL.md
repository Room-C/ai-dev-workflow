---
name: rc:feature-design
description: 架构设计师 — 基于分析文档产出设计报告（design.md），含自动多视角审查。
argument-hint: "<module> [需求描述]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, WebSearch, WebFetch, AskUserQuestion
---

# Feature Design — 架构设计师

基于 `analysis.md`（或直接从需求描述）产出结构化设计报告（`design.md`），并通过多视角自动审查确保设计质量。

## 工作流程

### Step 1: 收集上下文

#### 路径 A：增量模式（存在 analysis.md + .context-snapshot.md）

当 `docs/features/{module}/{version}/analysis.md` 和 `.context-snapshot.md` 都存在时，采用增量研究：

1. **读取 analysis.md**：作为主要输入，获取需求分析全貌
2. **读取 .context-snapshot.md**：获取 CLAUDE.md 关键约束、已有方案、代码引用、术语表
3. **补充性 Grep**（可选）：仅搜索 analysis.md 中提到但快照未覆盖的接口/模型/模块

⏭ 跳过以下操作（信息已包含在快照和 analysis.md 中）：
- 完整读取 CLAUDE.md
- 搜索 `docs/solutions/`
- 搜索 git log
- 全量 Grep 代码库

#### 路径 B：完整模式（无 analysis.md 或无快照）

当直接从需求描述出发，或 `.context-snapshot.md` 不存在时，执行完整研究：

1. **读取 CLAUDE.md**：了解项目架构边界、技术栈、代码规范、验证命令
2. **读取 analysis.md**：如果存在 `docs/features/{module}/{version}/analysis.md`，作为主要输入
3. **搜索 `docs/solutions/`**：查找相关的已有解决方案、设计模式、经验教训
4. **搜索 git log**：查看最近相关的变更历史
5. **Grep 代码库**：搜索与设计相关的现有代码、接口、模型，确认现有能力

如果没有 analysis.md，直接从用户需求描述出发，但需要补齐分析文档中缺失的关键信息（向用户确认）。

### Step 2: 撰写设计报告

输出路径：`docs/features/{module}/{version}/design.md`；如果指定了 `side`（如 `backend`、`frontend`），则输出到 `docs/features/{module}/{version}/{side}/design.md`

设计报告必须满足以下规则：

- **Front-matter 完整**：`module`、`version`、`date`、`tags` 四个字段缺一不可
- 标题下方必须有"关联设计"一行，使用相对路径；没有关联时写 `> 关联设计：暂无`
- 章节遵循标准设计报告规范（见下方输出格式）；没有变更的章节可以跳过，不硬凑
- `目标` 只写"做什么"，不写实现细节
- `现状分析` 说明从哪里出发；全新模块可简化为技术栈与运行环境
- `数据模型与接口` 只定义骨架，不写实现逻辑
- `核心流程` 使用 Mermaid，覆盖正常路径和关键异常路径
- `项目结构与技术决策` 既要说明目录职责，也要说明依赖方向和选择理由
- `暂不实现` 必须清晰列红线，并说明是否预留扩展空间
- 如需新增第三方依赖，必须通过 WebSearch 确认最新稳定版本，并写入依赖清单

### Step 3: 设计审查

设计报告撰写完成后，通过条件触发 + 文件驱动方式进行多视角审查。

#### Step 3.1: 评估审查触发条件

**默认全部启用**三个审查员（一致性、可行性、范围守卫）。

仅当变更极简（如只改配置值、单文件文案修改等无模型无接口无新依赖的场景）时可跳过全部审查，并在 Step 4 中告知用户"设计较简单，已跳过自动审查"。

#### Step 3.2: 执行审查（文件驱动）

为每个启用的审查员启动并行 Agent 子代理。传入参数包含：
- `design_path`：design.md 文件路径
- `output_dir`：与 design.md 同级的 `reviews/` 子目录（如 design.md 在 `{module}/{version}/{side}/design.md`，则为 `docs/features/{module}/{version}/{side}/reviews/`；无 side 时为 `docs/features/{module}/{version}/reviews/`）
- 其他审查员特定参数（`claude_md_path`、`requirement_path` 等）

每个审查员执行后：
1. 自行从文件读取 design.md（不依赖主上下文传递）
2. 将完整审查报告写入 `{output_dir}/{reviewer-name}.md`
3. **仅返回一行摘要给主上下文**（详见各审查员 Agent 的输出规范）

#### 审查置信度机制

每个审查员对每条发现自评置信度：**有把握（≥ 0.6）→ 报告，没把握（< 0.6）→ 丢弃**。

如果多个审查员独立发现同一问题，视为高置信，必须报告。

#### Step 3.3: 处理审查结果

收集所有审查员的一行摘要后：

1. **有发现**：在 Step 4 中呈现各审查员的摘要行，并告知用户完整报告位于 `reviews/{reviewer-name}.md`
2. **全部通过**：直接进入 Step 4

### Step 4: 与用户确认

向用户呈现：

1. 设计报告摘要（覆盖了什么、关键决策是什么）
2. 审查结果摘要（各审查员一行摘要；完整报告见 `reviews/`）
3. 自动修复列表（一致性审查员已修复的项，如有）
4. 需要用户决策的开放问题

等待用户确认后，最终定稿 design.md。

## 输出格式

```markdown
---
module: [模块名]
version: [版本号]
date: [YYYY-MM-DD]
tags: [design, ...]
---

# [模块名] 设计报告

> 关联设计：[关联文档](相对路径) 或 暂无

## 1. 目标

### 1.1 核心目标
[一句话描述]

### 1.2 约束与假设
- [约束] ...
- [假设] ...

## 2. 现状分析

### 2.1 已有能力
- [列出可复用的现有能力]

### 2.2 缺口分析
- [列出需要新增或修改的部分]

## 3. 数据模型与接口

### 3.1 数据模型
[表/类/结构体定义，含字段、类型、约束]

### 3.2 接口定义
[API 或模块接口，含路径、参数、响应、错误码]

## 4. 核心流程

[Mermaid 流程图 + 文字说明]

## 5. 项目结构与技术决策

### 5.1 文件变更清单
| 文件路径 | 变更类型 | 职责 |
|---------|---------|------|

### 5.2 技术决策
| 决策 | 选择 | 理由 | 替代方案 |
|------|------|------|---------|

## 6. 验收标准

- [ ] [可验证的验收条件]

## 7. 暂不实现

| 功能 | 原因 | 备注 |
|------|------|------|
```

## 边界规则（HARD STOP）

**本 Skill 的职责到 design.md 定稿为止。** 用户确认设计后，必须立即停止，不得继续执行以下任何操作：

- ❌ 不拆解任务、不写代码（那是 `rc:feature-implement` 的职责）
- ❌ 不添加依赖、不创建文件、不修改源代码
- ❌ 不启动子代理去实现任何代码变更

### 完成后提示用户

设计确认完成后，输出以下提示（替换 `{module}` 为实际模块名）：

```
✅ design.md 已定稿。

📋 下一步：运行 /feature-implement {module} 将设计拆解为任务清单并逐任务实现。
```

## 原则

1. **Front-matter 必须完整**：`module`、`version`、`date`、`tags` 四个字段缺一不可
2. **流程图用 Mermaid**：所有流程图使用 Mermaid 语法，节点标注使用中文
3. **关键决策附理由**：不能只给结论，必须说明为什么这么选、替代方案是什么
4. **研究先行**：先搜索 `docs/solutions/` 和代码库，避免重复设计已有能力
5. **审查是强制的**：Step 3 的多视角审查不可跳过（除非触发条件判定全部跳过），是设计质量的最后防线
6. **用中文输出**：所有文档内容使用中文
7. **上下文高效**：利用 `.context-snapshot.md` 避免重复研究；审查结果通过文件传递，主上下文只保留摘要行
