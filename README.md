# ai-dev-workflow

Claude Code 插件 — 把「随意对话式编程」变成**结构化 AI 工作流**。

一句 slash command 就能驱动完整的开发链路：需求分析 → 架构设计 → 实现 → 代码审查 → 提交 PR。11 个技能、6 个 Agent，即装即用。

## 安装

```bash
/plugin marketplace add Room-C/ai-dev-workflow
/plugin install ai-dev-workflow
```

或手动克隆：

```bash
git clone https://github.com/Room-C/ai-dev-workflow.git ~/.claude/plugins/ai-dev-workflow
```

## 它能做什么

三条流水线分别覆盖功能开发、质量门控和设计稿转代码。

```
┌─ Feature Pipeline ─────────────────────────────────────────────────┐
│  analyze → design → implement → archive                            │
│  需求分析到代码落地，文档驱动全链路                                      │
└────────────────────────────────────────────────────────────────────┘

┌─ Quality Gates ────────────────────────────────────────────────────┐
│  diff-review → commit → review-pr                                 │
│  多视角审查 → 规范提交 → PR 闭环跟踪                                  │
└────────────────────────────────────────────────────────────────────┘

┌─ Design-to-Code (Pencil MCP) ──────────────────────────────────────┐
│  read-design → implement-screen → verify-screen                   │
│  设计稿直出原生代码，截图对比验证还原度                                   │
└────────────────────────────────────────────────────────────────────┘
```

## 快速开始

```bash
# 1. 分析需求
/rc:feature-analyze "用户希望添加消息通知功能"

# 2. 设计架构（产出 design.md，含三视角自动审查）
/rc:feature-design notification

# 3. 拆解任务 + 逐任务执行（一步到位）
/rc:feature-implement notification

# 4. 合并前审查
/rc:diff-review main

# 5. 提交 + 创建 PR
/rc:commit main
```

## 技能清单

### Feature Pipeline — 功能开发全链路

| 技能 | 说明 | 产出 |
|------|------|------|
| `rc:feature-analyze` | 需求分析 — 将模糊需求转化为结构化分析文档 | `analysis.md` |
| `rc:feature-design` | 架构设计 — 含一致性、可行性、范围守卫三视角自动审查 | `design.md` |
| `rc:feature-implement` | 功能实现 — 拆解任务 + 逐任务执行，一条命令完成 plan → code | `tasks.md` + 代码变更 |
| `rc:feature-archive` | 归档 — 更新索引、沉淀模式到 `docs/solutions/` | 归档文档 |

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

### Self-Evolving — 自进化

| 技能 | 说明 |
|------|------|
| `rc:skill-evolve` | 分析执行遥测数据，识别反复失败模式，自动更新 known-issues 注册表，对严重模式提出 SKILL.md 补丁 |

所有 Skill 执行后自动记录遥测到 `~/.ai-dev-workflow/telemetry.jsonl`，`rc:skill-evolve` 基于此数据闭环改进：

```
Skill 执行 → 遥测记录 → skill-evolve 分析 → known-issues 更新 / SKILL.md 补丁
                                                    ↓
                                    下次执行自动规避已知问题
```

## Agent 列表

6 个 Agent 分两类，详见 [AGENTS.md](AGENTS.md)：

| 类别 | Agent | 职责 | 调用方 |
|------|-------|------|--------|
| 设计类 | `analyst` | 生成设计报告（11 步流程） | `rc:feature-design` |
| 设计类 | `decomposer` | 任务拆解（6 步流程） | `rc:feature-implement` Phase 1 |
| 设计类 | `coherence-reviewer` | 内部一致性审查 | `rc:feature-design` Step 3 |
| 设计类 | `feasibility-reviewer` | 技术可行性审查 | `rc:feature-design` Step 3 |
| 设计类 | `scope-guardian` | 范围守卫 — 防过度设计 | `rc:feature-design` Step 3 |
| 工作流 | `task-runner` | 逐任务实现 + 门控验证 | `rc:feature-implement` Phase 2 |

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
