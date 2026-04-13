# ai-dev-workflow

Structured AI-assisted development workflow plugin for [Claude Code](https://claude.ai/claude-code). 12 skills, 6 agents, covering three pipelines.

## Install

```bash
/plugin marketplace add Room-C/ai-dev-workflow
/plugin install ai-dev-workflow
```

Or clone manually:

```bash
git clone https://github.com/Room-C/ai-dev-workflow.git ~/.claude/plugins/ai-dev-workflow
```

## Prerequisites

Your project's `CLAUDE.md` should define:

- **Architecture Boundaries** — Tech stack, module structure, import rules
- **Code Conventions** — Package manager, code style, naming conventions
- **Verification** — Commands for each change type (lint, typecheck, test)
- **Safety Rails** — NEVER / ALWAYS rules

The plugin reads these dynamically — no hardcoded commands.

## Quick Start

```
# Analyze a feature requirement
/rc:feature-analyze "用户希望添加消息通知功能"

# Design the architecture
/rc:feature-design notification

# Break down into tasks
/rc:feature-plan notification

# Execute tasks one by one
/rc:feature-execute notification

# Or batch-execute all tasks automatically
/rc:plan-executor docs/features/notification/v1/tasks.md

# Review your branch diff before merging
/rc:diff-review main

# Commit and create PR
/rc:commit main
```

## Pipelines

### 1. Feature Pipeline

End-to-end feature development, from fuzzy requirements to archived knowledge.

```
rc:feature-analyze → rc:feature-design → rc:feature-plan → rc:feature-execute → rc:feature-archive
```

| Skill | Description |
|-------|-------------|
| `rc:feature-analyze` | 需求分析 — 将模糊需求转化为 analysis.md |
| `rc:feature-design` | 架构设计 — 产出 design.md，含三视角自动审查 |
| `rc:feature-plan` | 任务拆解 — 产出 tasks.md，含依赖排序 |
| `rc:feature-execute` | 逐任务执行 — 强制门控验证 |
| `rc:feature-archive` | 归档 — 更新索引、知识沉淀到 docs/solutions/ |

**Batch execution:**

| Skill | Description |
|-------|-------------|
| `rc:plan-executor` | 批量自动执行 tasks.md 中的所有任务 |

### 2. Quality Gates

Code review, commit management, and PR review loops.

| Skill | Description |
|-------|-------------|
| `rc:diff-review` | 分支对比 Code Review — 多轮迭代 + 自动修复 + 知识沉淀 |
| `rc:commit` | 提交变更 + 推送 + 创建 PR（Conventional Commits） |
| `rc:review-pr` | PR 审查 — 先立即审查，仅在有问题时启动跟踪循环，采集 CI annotations + 外部评论并闭环回复 |

### 3. Design-to-Code (Pencil MCP)

Read `.pen` design files via Pencil MCP, implement native UI code, and verify visual alignment.

```
rc:read-design → rc:implement-screen → rc:verify-screen
```

| Skill | Description |
|-------|-------------|
| `rc:read-design` | 通过 Pencil MCP 读取 .pen 设计稿，输出结构化设计信息（纯探索，不写代码） |
| `rc:implement-screen` | 从 .pen 设计稿实现 UI 页面（默认 iOS/SwiftUI，支持 Flutter，支持多页面） |
| `rc:verify-screen` | 对比设计稿与实现截图，识别视觉差异并提供修复建议 |

## Agents

See [AGENTS.md](AGENTS.md) for the full agent index.

## Core Principles

1. **Research-First** — Search `docs/solutions/` and codebase before writing code
2. **Document Chain** — analysis.md (what) → design.md (how) → tasks.md (steps)
3. **Forced Gates** — Verification must pass before marking tasks complete
4. **Knowledge Compounding** — Patterns discovered during review/archive persist to `docs/solutions/`
5. **Confidence Gating** — Findings below 0.50 discarded; 0.50-0.59 P1 only; >= 0.60 kept
6. **Autofix Classification** — safe_auto / gated_auto / manual / advisory

## Knowledge Compounding

Skills compound knowledge using the dual-track schema:

| Track | Use Case | Directory |
|-------|----------|-----------|
| Bug Track | Build, runtime, config, integration errors | `docs/solutions/{category}/` |
| Knowledge Track | Best practices, workflow, architecture, performance | `docs/solutions/{category}/` |

## License

MIT — Room C Studio
