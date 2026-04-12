---
name: rc:feature-designer
description: 需求分析与设计报告生成 — 产出 design.md，可选拆解 tasks.md。
argument-hint: "<需求描述>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, WebSearch, WebFetch, AskUserQuestion
---

# Feature Designer — 需求分析与设计报告生成

一个以 `design.md` 为主交付物的功能设计 Skill，用于把用户需求转成结构化设计报告；只有在用户明确要求继续拆解时，才补充生成 `tasks.md`。

## 整体流程

```text
用户需求 → 需求澄清与现状分析 → Analyst 生成 design.md
                                 ↓
                      三视角审查（一致性 + 可行性 + 范围）
                                 ↓
                      用户确认设计
                                 ↓
                      （可选）Decomposer 生成 tasks.md
```

## 角色定位

你是流程协调者（Orchestrator），负责：
1. 理解用户需求和交付边界
2. 读取项目现状，避免脱离代码库空想
3. 协调 Analyst 产出符合规范的 `design.md`
4. 仅在用户明确要求拆解时，再协调 Decomposer 产出 `tasks.md`

## 完成标准

以下条件全部满足，才算本 Skill 完成：

1. `design.md` 已落到规范目录，且 front-matter 完整
2. 文档结构与最新设计报告规范一致，强制项没有遗漏
3. 标题下方已经补上真实存在的"关联设计"相对路径；没有关联时明确写"暂无"
4. backend / frontend 的边界清楚；如果多端都涉及，分别产出各自文档
5. "暂不实现"写清楚，不给后续编码留下误发挥空间
6. **设计审查已通过**：三视角审查（一致性 + 可行性 + 范围）已执行，用户已确认审查结果
7. 只有用户明确要求任务拆解时，才额外生成 `tasks.md`

## 工作流程

### Phase 1: 需求澄清

在启动任何 Agent 之前，先对齐这些信息：

1. **需求目标**：这个版本到底要交付什么
2. **范围边界**：涉及 `backend`、`frontend`，还是多端（`fullstack`）
3. **模块信息**：模块名、版本号；如果用户没给，结合现有 `docs/features/` 合理推断
4. **现状基础**：代码里已经有什么、缺什么、复用什么
5. **交付范围**：用户是只要 `design.md`，还是还要 `tasks.md`

如果需求不清晰，可以补一个必要问题；但默认优先先读代码和文档，减少来回追问。

### Phase 2: 现状分析

在理解需求后，先自己补齐上下文：

1. 读取项目结构，确认模块边界与依赖方向
2. 读取 `docs/features/` 下已有模块文档，判断是否已有 `README.md`、`roadmap.md`、历史版本设计
3. 读取项目约束文档（如 CLAUDE.md、架构设计、技术规范）
4. 找出真正相关的已有能力、缺口和依赖

### Phase 3: 生成设计报告（必做）

将收集到的信息传给 Analyst Agent，生成 `design.md`。

**启动 Analyst Agent 时必须提供：**

- 用户需求描述
- 目标端（side）：`backend` / `frontend` / `mobile` / `fullstack`
- 模块名与版本号
- 当前技术栈和项目结构
- 已有能力、依赖约束、基础设施现状
- 关联设计文档路径
- 输出路径

Agent 指令详见 `agents/design/analyst.md`。

如果是 `fullstack`，启动两个 Analyst Agent 并行工作（一个 `backend`、一个 `frontend`），各自只写自己的端。

### Phase 3b: 设计审查（强制）

设计报告生成后，启动 3 个并行 Agent 子代理进行多视角审查（与 `rc:feature-design` Step 3 一致）：

1. **一致性审查**（`agents/design/coherence-reviewer.md`）：数据模型 ↔ 接口 ↔ 流程图一致性，可自动修复 safe_auto 级别问题
2. **可行性审查**（`agents/design/feasibility-reviewer.md`）：基础设施就绪、技术兼容性、性能/安全风险
3. **范围守卫**（`agents/design/scope-guardian.md`）：是否超出需求范围、是否过度设计

#### 置信度机制

| 置信度 | 处理方式 |
|--------|---------|
| < 0.50 | 丢弃 |
| 0.50 - 0.59 | 仅 P1 |
| >= 0.60 | 完整报告 |

跨视角重复发现 +0.10。

审查结果汇总后呈现给用户：
1. 审查发现汇总（按严重程度排序）
2. 自动修复列表（一致性审查员已修复的项）
3. 需要用户决策的开放问题

等待用户确认后才进入 Phase 4。

### Phase 4: 任务拆解（按需）

只有在以下情况，才启动 Decomposer Agent：

- 用户明确说要继续拆任务
- 用户要求输出 `tasks.md`
- 当前任务本身就是"拆解需求 / 形成执行清单"

不要在用户只要设计报告时，自动追加任务拆解。

Agent 指令详见 `agents/design/decomposer.md`。

### Phase 5: 交付与确认

向用户交付时：

1. 先汇报 `design.md` 已生成/已更新
2. 用高层语言概括本次设计覆盖了什么、卡住了什么
3. 如果同时生成了 `tasks.md`，再单独说明
4. 若发现需求本身存在偏差或过度设计风险，给出简短提醒

## 设计报告要求

`design.md` 必须满足以下规则：

- 使用完整 front-matter：`module`、`version`、`date`、`tags`
- 标题下方必须有"关联设计"一行，使用相对路径；没有关联时写 `> 关联设计：暂无`
- 章节遵循最新设计报告规范；没有变更的章节可以跳过，不硬凑
- `目标` 只写"做什么"，不写实现细节
- `现状分析` 说明从哪里出发；全新模块可简化为技术栈与运行环境
- `数据模型与接口` 只定义骨架，不写实现逻辑
- `核心流程` 使用 mermaid，覆盖正常路径和关键异常路径
- `项目结构与技术决策` 既要说明目录职责，也要说明依赖方向和选择理由
- `暂不实现` 必须清晰列红线，并说明是否预留扩展空间

## 文档位置规范

输出目录遵循以下结构：

```text
docs/features/[模块名]/
├── README.md
├── roadmap.md
└── [版本号]/
    ├── backend/
    │   ├── design.md
    │   └── tasks.md
    └── frontend/
        ├── design.md
        └── tasks.md
```

- 首次创建模块文档时，若缺少 `README.md` 或 `roadmap.md`，要提醒补齐；是否本轮一并创建，按用户任务边界判断
- 版本号格式使用 `v1`、`v2`...
- 只涉及单端时，只创建对应子目录（如只有 `backend/` 或只有 `mobile/`）
- `fullstack` 时创建所有涉及的端子目录

## Agent 协作模式

### 并行模式

- backend / frontend 的 Analyst Agent 可以并行
- 多个互不依赖模块的设计可以并行

### 串行模式

- `tasks.md` 必须在 `design.md` 明确后再生成
- 设计未定稿前，不要抢跑任务拆解

## 参考文件

- `agents/design/analyst.md`：设计报告生成规则
- `agents/design/decomposer.md`：任务拆解规则
- `agents/design/coherence-reviewer.md`：一致性审查规则
- `agents/design/feasibility-reviewer.md`：可行性审查规则
- `agents/design/scope-guardian.md`：范围守卫规则
- `references/design-template.md`：设计报告模板

## 注意事项

- `design.md` 是主产物，不要让 `tasks.md` 喧宾夺主
- 设计报告站在架构视角，不深入代码实现
- 关键决策必须附理由，不能只给结论
- 如需新增第三方依赖，必须通过 web 搜索确认最新稳定版本，并写入依赖清单
- 只关联真实存在且有直接依赖关系的设计文档
- 如果某个"暂不实现"特别容易被误做出来，要显式标红提醒
