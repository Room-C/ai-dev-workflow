# Changelog

## 1.0.0 — 2026-04-10

### Added
- Feature Pipeline: `rc:feature-analyze`, `rc:feature-design`, `rc:feature-plan`, `rc:feature-execute`, `rc:feature-archive`
- Combo Skills: `rc:feature-designer` (analyze+design+plan), `rc:plan-executor` (batch execute tasks.md)
- Quality Gates: `rc:diff-review` (local code review with confidence gating), `rc:commit` (conventional commit + PR), `rc:review-pr` (auto PR review loop)
- Flutter Design-to-Code: 10 skills from `rc:init-project` to `rc:sync-design`
- 6 agents: analyst, decomposer, 3 design reviewers, task-runner
- Knowledge compounding via `docs/solutions/` with compound-engineering dual-track schema
- `preprocess-diff.sh` for token-efficient diff preprocessing
