# Agents

本仓库是一套通用 Agent Skills 包。它必须同时服务 Claude Code、Codex 以及其他通过 `npx skills` 安装 Skill 的宿主。

## 运行时约束

- 每个可安装 Skill 必须自包含。`SKILL.md` 需要的脚本、agent prompt、共享 schema 应放在该 Skill 目录下的 `scripts/`、`references/agents/` 或 `references/shared/`。
- 根目录 `agents/` 仅作为 Claude Code plugin legacy 入口和开发源文件保留；通用安装不能依赖它存在。
- 不要把 `$HOME/.claude/plugins/cache`、`$HOME/.codex` 或仓库绝对路径作为唯一运行路径。允许作为 legacy fallback，但优先使用当前 Skill 目录内资源。
- 宿主项目规则读取顺序为 `AGENTS.md` -> `CLAUDE.md` -> README/Makefile/package 配置。
- 子代理、Cron 等宿主能力都是可选的。Skill 必须说明不可用时的 inline/manual fallback。

## Design Agents

| Agent | Legacy 文件 | Runtime 位置 | 职责 | 被谁调用 |
|-------|-------------|--------------|------|----------|
| analyst | `agents/design/analyst.md` | `skills/feature-design/references/agents/analyst.md` | 设计报告生成 | `rc:feature-design` |
| decomposer | `agents/design/decomposer.md` | `skills/feature-implement/references/agents/decomposer.md` | 任务拆解 | `rc:feature-implement` Phase 1 |
| coherence-reviewer | `agents/design/coherence-reviewer.md` | `skills/feature-design/references/agents/coherence-reviewer.md` | 内部一致性审查 | `rc:feature-design` Step 3 |
| feasibility-reviewer | `agents/design/feasibility-reviewer.md` | `skills/feature-design/references/agents/feasibility-reviewer.md` | 可行性审查 | `rc:feature-design` Step 3 |
| scope-guardian | `agents/design/scope-guardian.md` | `skills/feature-design/references/agents/scope-guardian.md` | 范围守卫 | `rc:feature-design` Step 3 |

## Workflow Agents

| Agent | Legacy 文件 | Runtime 位置 | 职责 | 被谁调用 |
|-------|-------------|--------------|------|----------|
| task-runner | `agents/workflow/task-runner.md` | `skills/feature-implement/references/agents/task-runner.md` | 单任务实现与验证 | `rc:feature-implement` Phase 2 |
| pr-reviewer | `agents/workflow/pr-reviewer.md` | `skills/review-pr/references/agents/pr-reviewer.md` | PR 审查、分级修复、推送更新 | `rc:review-pr` |
| diff-reviewer | `agents/workflow/diff-reviewer.md` | `skills/diff-review/references/agents/diff-reviewer.md` | Diff 审查并产出 findings JSON | `rc:diff-review` Step 4.1 |
| validation-reviewer | `agents/workflow/validation-reviewer.md` | `skills/diff-review/references/agents/validation-reviewer.md` | Finding 裁决 | `rc:diff-review` Step 4.2 |
| fix-runner | `agents/workflow/fix-runner.md` | `skills/diff-review/references/agents/fix-runner.md` | 单条修复、验证、回滚/提交 | `rc:diff-review` Step 4.3 |
