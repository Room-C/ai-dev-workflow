# Changelog

## 1.1.0 — 2026-04-13

### Changed
- **rc:capture-mockups**: 支持三种采集模式 — Mode A（Codegen 录制脚本回放，推荐）、Mode B（AI 自动探索，需 opt-in）、Mode C（引导用户 Codegen 录制）。新增步骤 P（脚本后处理：自动在录制脚本中插入截图命令）。截图按 `screens/`、`interactions/`、`states/` 分类存储。`module` 参数强制按模块隔离脚本和截图（未提供时交互选择已有模块或创建新模块）。`mode=record` 参数强制触发重新录制。
- **rc:sync-design**: 区分两种设计稿更新场景 — UI 内容变但交互流程不变（直接重跑脚本）vs 交互流程也变了（`--flow-changed`，触发重新录制）。`module` 参数同样强制模块化，未提供时交互选择。

## 1.0.0 — 2026-04-10

### Added
- Feature Pipeline: `rc:feature-analyze`, `rc:feature-design`, `rc:feature-plan`, `rc:feature-execute`, `rc:feature-archive`
- Combo Skills: `rc:feature-designer` (analyze+design+plan), `rc:plan-executor` (batch execute tasks.md)
- Quality Gates: `rc:diff-review` (local code review with confidence gating), `rc:commit` (conventional commit + PR), `rc:review-pr` (auto PR review loop)
- Flutter Design-to-Code: 10 skills from `rc:init-project` to `rc:sync-design`
- 6 agents: analyst, decomposer, 3 design reviewers, task-runner
- Knowledge compounding via `docs/solutions/` with compound-engineering dual-track schema
- `preprocess-diff.sh` for token-efficient diff preprocessing
