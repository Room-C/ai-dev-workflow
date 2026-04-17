# ai-dev-workflow Plugin

@AGENTS.md

## Overview

This plugin provides a structured AI-assisted development workflow with 11 skills across three pipelines:

1. **Feature Pipeline** (`rc:feature-*`) — Requirements → Design → Implement → Archive
2. **Quality Gates** (`rc:diff-review`, `rc:commit`, `rc:review-pr`) — Code review, commit, PR review (immediate first review + conditional follow-up loop)
3. **Design-to-Code** (`rc:read-design`, `rc:implement-screen`, `rc:verify-screen`) — Pencil MCP → Native UI implementation → Visual verification

## Core Principles

All skills follow these principles:

- **Research-First**: Before writing code or designs, search `docs/solutions/` for existing patterns, check git history, grep the codebase
- **Document Chain**: Each document has a single responsibility — analysis.md (what), design.md (how), tasks.md (steps)
- **Forced Gates**: Verification must pass before marking tasks complete
- **Knowledge Compounding**: Patterns discovered during review/archive are persisted to `docs/solutions/` using dual-track schema (Bug Track / Knowledge Track)
- **Confidence Gating**: Review findings below 0.60 confidence are discarded; ≥ 0.60 kept. Multi-perspective consensus (≥ 2 reviewers find the same issue) is treated as high confidence and always reported.
- **Autofix Classification**: safe_auto (direct fix) / gated_auto (fix + confirm) / manual (report only) / advisory (log only)

## Execution Telemetry

每个 Skill 执行结束时（无论成功、部分完成还是失败），必须追加一条遥测记录。

### 记录方式

```bash
# 定位遥测脚本
RECORD_SCRIPT=$(ls "$HOME/.claude/plugins/cache/ai-dev-workflow"/*/*/skills/shared/scripts/record-outcome.sh 2>/dev/null | sort -V | tail -1)
if [ -z "$RECORD_SCRIPT" ]; then
  # 本地开发 fallback
  for candidate in "skills/shared/scripts/record-outcome.sh" "dev_workflow/skills/shared/scripts/record-outcome.sh"; do
    [ -f "$candidate" ] && RECORD_SCRIPT="$candidate" && break
  done
fi

# 调用（必须检查脚本存在，否则 bash "" 会静默 no-op，skill-evolve 数据出现空洞）
if [ -z "$RECORD_SCRIPT" ] || [ ! -f "$RECORD_SCRIPT" ]; then
  echo "WARN: telemetry script not found in cache or local fallbacks; record skipped." >&2
else
  bash "$RECORD_SCRIPT" <skill-name> <status> [failure-step] [failure-reason] [fallback-used] || \
    echo "WARN: telemetry call exited non-zero — record may be incomplete." >&2
fi
```

### 状态定义

| 状态 | 含义 |
|------|------|
| `success` | 所有步骤按主路径完成 |
| `partial` | 触发了降级/fallback 但最终完成了核心目标 |
| `failed` | 未能完成核心目标 |

### 已知问题规避

每个 Skill 在 Step 1（上下文理解）阶段，应读取 `skills/shared/known-issues.md`（通过插件缓存路径或本地路径），检查是否有与当前执行场景匹配的已知问题，并主动规避。

## Prerequisites

For skills to work correctly, the host project should have a `CLAUDE.md` with at minimum:

- **Architecture Boundaries** — Tech stack, module structure, import rules
- **Code Conventions** — Package manager, code style, naming conventions
- **Verification** — Commands to run for each change type (lint, typecheck, test)
- **Safety Rails** — NEVER / ALWAYS rules

## Knowledge Compounding Schema

When skills compound knowledge to `docs/solutions/`, they use the compound-engineering dual-track schema:

| Track | Use Case | Directory |
|-------|----------|-----------|
| Bug Track | Build errors, runtime errors, config errors, integration issues | `docs/solutions/{category}/` |
| Knowledge Track | Best practices, workflow improvements, architecture decisions | `docs/solutions/{category}/` |

Category → directory mapping: `build_error` → `build/`, `runtime_error` → `runtime/`, `config_error` → `config/`, `integration_issue` → `integration/`, `best_practice` → `best-practices/`, `workflow_issue` → `workflow/`, `architecture` → `architecture/`, `performance` → `performance/`
