# ai-dev-workflow

Claude Code 插件 — 结构化 AI 辅助开发工作流。12 个技能、6 个 Agent，覆盖三条流水线。

## 安装

```bash
/plugin marketplace add Room-C/ai-dev-workflow
/plugin install ai-dev-workflow
```

或手动克隆：

```bash
git clone https://github.com/Room-C/ai-dev-workflow.git ~/.claude/plugins/ai-dev-workflow
```

## 前置要求

项目根目录需要一个 `CLAUDE.md`，至少包含以下内容，插件会动态读取（无硬编码命令）：

| 必备项 | 示例 |
|--------|------|
| 架构边界 | 技术栈、模块结构、导入规则 |
| 代码规范 | 包管理器、代码风格、命名约定 |
| 验证命令 | lint、typecheck、test 等各类变更的检查命令 |
| 安全护栏 | NEVER / ALWAYS 规则 |

## 三条流水线一览

```
┌─ Feature Pipeline ─────────────────────────────────────────────────┐
│  analyze → design → plan → execute → archive                      │
│  从模糊需求到代码落地，全链路文档驱动                                    │
└────────────────────────────────────────────────────────────────────┘

┌─ Quality Gates ────────────────────────────────────────────────────┐
│  diff-review → commit → review-pr                                 │
│  本地审查 → 提交 PR → 自动跟踪修复                                    │
└────────────────────────────────────────────────────────────────────┘

┌─ Design-to-Code (Pencil MCP) ──────────────────────────────────────┐
│  read-design → implement-screen → verify-screen                   │
│  读取 .pen 设计稿 → 生成原生 UI 代码 → 视觉对比验证                     │
└────────────────────────────────────────────────────────────────────┘
```

## 快速开始

```bash
# 1. 分析需求
/rc:feature-analyze "用户希望添加消息通知功能"

# 2. 设计架构（产出 design.md，含三视角自动审查）
/rc:feature-design notification

# 3. 拆解任务（产出 tasks.md，含依赖排序）
/rc:feature-plan notification

# 4. 逐任务执行（强制门控验证）
/rc:feature-execute notification

# 或一键批量执行
/rc:plan-executor docs/features/notification/v1/tasks.md

# 5. 合并前审查
/rc:diff-review main

# 6. 提交 + 创建 PR
/rc:commit main
```

## 技能清单

### Feature Pipeline — 功能开发全链路

| 技能 | 说明 | 产出 |
|------|------|------|
| `rc:feature-analyze` | 需求分析 — 将模糊需求转化为结构化分析文档 | `analysis.md` |
| `rc:feature-design` | 架构设计 — 含一致性、可行性、范围守卫三视角自动审查 | `design.md` |
| `rc:feature-plan` | 任务拆解 — 按依赖排序，每条任务可独立执行 | `tasks.md` |
| `rc:feature-execute` | 逐任务执行 — 每条任务完成后强制验证（lint/test/typecheck） | 代码变更 |
| `rc:feature-archive` | 归档 — 更新索引、沉淀模式到 `docs/solutions/` | 归档文档 |
| `rc:plan-executor` | 批量自动执行 — 读取 tasks.md，按依赖顺序逐条完成 | 代码变更 |

### Quality Gates — 质量门控

| 技能 | 说明 |
|------|------|
| `rc:diff-review` | 分支对比审查 — Codex Companion 优先 + Agent 多视角降级，多轮迭代修复，自动沉淀知识 |
| `rc:commit` | 提交 + 推送 + 创建 PR（Conventional Commits 格式） |
| `rc:review-pr` | PR 审查 — 先立即审查，仅在有问题时启动跟踪循环；采集 CI annotations + 外部评论并闭环回复 |

### Design-to-Code — Pencil 设计稿转代码

| 技能 | 说明 |
|------|------|
| `rc:read-design` | 读取 `.pen` 设计稿，输出结构化设计信息（节点树、样式、截图），纯探索不写代码 |
| `rc:implement-screen` | 从设计稿生成 UI 页面代码（默认 iOS/SwiftUI，支持 Flutter，支持多页面） |
| `rc:verify-screen` | 对比设计稿与模拟器实现截图，识别视觉差异并输出修复建议 |

## Agent 列表

6 个 Agent 分两类，详见 [AGENTS.md](AGENTS.md)：

| 类别 | Agent | 职责 | 调用方 |
|------|-------|------|--------|
| 设计类 | `analyst` | 生成设计报告（11 步流程） | `rc:feature-design` |
| 设计类 | `decomposer` | 任务拆解（6 步流程） | `rc:feature-plan` |
| 设计类 | `coherence-reviewer` | 内部一致性审查 | `rc:feature-design` Step 3 |
| 设计类 | `feasibility-reviewer` | 技术可行性审查 | `rc:feature-design` Step 3 |
| 设计类 | `scope-guardian` | 范围守卫 — 防过度设计 | `rc:feature-design` Step 3 |
| 工作流 | `task-runner` | 逐任务实现 + 门控验证 | `rc:plan-executor` |

## 核心原则

| 原则 | 说明 |
|------|------|
| 研究先行 | 写代码前先搜 `docs/solutions/` 和 codebase，不重复造轮子 |
| 文档链驱动 | analysis.md（做什么）→ design.md（怎么做）→ tasks.md（执行步骤） |
| 强制门控 | 每条任务验证通过才能标记完成 |
| 知识复利 | 审查/归档中发现的模式沉淀到 `docs/solutions/`，后续开发自动检索 |
| 置信度门控 | 审查发现 < 0.50 丢弃，0.50-0.59 仅保留 P1，>= 0.60 保留 |
| 修复分级 | `safe_auto`（直接修）/ `gated_auto`（修后确认）/ `manual`（仅报告）/ `advisory`（仅记录） |

## 知识沉淀

技能运行中发现的模式级问题自动沉淀到 `docs/solutions/`，使用双轨 schema：

| 轨道 | 适用场景 | 目录 |
|------|---------|------|
| Bug Track | 构建错误、运行时错误、配置错误、集成问题 | `docs/solutions/{category}/` |
| Knowledge Track | 最佳实践、工作流改进、架构决策、性能优化 | `docs/solutions/{category}/` |

## License

MIT — Room C Studio
