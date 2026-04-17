# Agents

本插件包含 8 个 Agent，分为两类：

## 设计类（Design）

| Agent | 文件 | 职责 | 被谁调用 |
|-------|------|------|---------|
| analyst | `agents/design/analyst.md` | 设计报告生成 — 11 步流程产出 design.md | `rc:feature-design` |
| decomposer | `agents/design/decomposer.md` | 任务拆解 — 6 步流程产出 tasks.md | `rc:feature-implement` Phase 1 |
| coherence-reviewer | `agents/design/coherence-reviewer.md` | 内部一致性审查 — 术语统一、模型与接口匹配 | `rc:feature-design` Step 3 |
| feasibility-reviewer | `agents/design/feasibility-reviewer.md` | 可行性审查 — 基础设施就绪、技术兼容性 | `rc:feature-design` Step 3 |
| scope-guardian | `agents/design/scope-guardian.md` | 范围守卫 — 防止需求蔓延和过度设计 | `rc:feature-design` Step 3 |

## 工作流类（Workflow）

| Agent | 文件 | 职责 | 被谁调用 |
|-------|------|------|---------|
| task-runner | `agents/workflow/task-runner.md` | 任务执行 — 逐任务实现代码变更 + 门控验证 | `rc:feature-implement` Phase 2 |
| pr-reviewer | `agents/workflow/pr-reviewer.md` | PR 审查 — 审查 diff、分级修复、推送更新 | `rc:review-pr` 首轮 + 跟踪 Cron |
| diff-reviewer | `agents/workflow/diff-reviewer.md` | Diff 审查 — Codex 首选 + Agent 降级 + 多视角并行 | `rc:diff-review` Step 3 |
