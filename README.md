# ai-dev-workflow

Structured AI-assisted development workflow plugin for [Claude Code](https://claude.ai/claude-code). 20 skills, 6 agents, covering three pipelines.

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

# Or use the combo skill (analyze + design + plan in one go)
/rc:feature-designer "用户希望添加消息通知功能"

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

**Combo skills:**

| Skill | Description |
|-------|-------------|
| `rc:feature-designer` | 需求分析 + 设计报告生成（design.md），可选任务拆解（tasks.md） |
| `rc:plan-executor` | 批量自动执行 tasks.md 中的所有任务 |

### 2. Quality Gates

Code review, commit management, and PR review loops.

| Skill | Description |
|-------|-------------|
| `rc:diff-review` | 分支对比 Code Review — 多轮迭代 + 自动修复 + 知识沉淀 |
| `rc:commit` | 提交变更 + 推送 + 创建 PR（Conventional Commits） |
| `rc:review-pr` | PR 审查循环 — 自动 review → fix → verify，最多 6 轮 |

### 3. Flutter Design-to-Code

Full pipeline from design mockups to verified Flutter implementation.

```
rc:init-project → rc:capture-mockups → rc:extract-tokens → rc:connect-app
→ rc:implement-screen → rc:check-alignment → rc:design-critique
→ rc:verify-interaction → rc:run-golden → rc:sync-design
```

| Skill | Description |
|-------|-------------|
| `rc:init-project` | 初始化 Flutter D2C 项目结构 |
| `rc:capture-mockups` | Playwright 截取设计稿页面 |
| `rc:extract-tokens` | 提取 Design Tokens → Dart 代码 |
| `rc:connect-app` | 启动 Flutter 应用 + 连接 MCP 调试 |
| `rc:implement-screen` | TDD 驱动页面实现 |
| `rc:check-alignment` | 实现截图 vs 设计稿像素级对比 |
| `rc:design-critique` | 设计质量评审（反模式 + 原则合规） |
| `rc:verify-interaction` | 三层交互验证 |
| `rc:run-golden` | Golden Test 回归检测 |
| `rc:sync-design` | 设计稿更新后全链路同步 |

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
