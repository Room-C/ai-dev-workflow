# ai-dev-workflow Plugin

@AGENTS.md

## Overview

This plugin provides a structured AI-assisted development workflow with 20 skills across three pipelines:

1. **Feature Pipeline** (`rc:feature-*`) — Requirements → Design → Plan → Execute → Archive
2. **Quality Gates** (`rc:diff-review`, `rc:commit`, `rc:review-pr`) — Code review, commit, PR review (immediate first review + conditional follow-up loop)
3. **Flutter Design-to-Code** (`rc:init-project` ... `rc:sync-design`) — Design mockup → Implementation → Verification

## Core Principles

All skills follow these principles:

- **Research-First**: Before writing code or designs, search `docs/solutions/` for existing patterns, check git history, grep the codebase
- **Document Chain**: Each document has a single responsibility — analysis.md (what), design.md (how), tasks.md (steps)
- **Forced Gates**: Verification must pass before marking tasks complete
- **Knowledge Compounding**: Patterns discovered during review/archive are persisted to `docs/solutions/` using dual-track schema (Bug Track / Knowledge Track)
- **Confidence Gating**: Review findings below 0.50 confidence are discarded; 0.50-0.59 only P1; ≥ 0.60 kept
- **Autofix Classification**: safe_auto (direct fix) / gated_auto (fix + confirm) / manual (report only) / advisory (log only)

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
