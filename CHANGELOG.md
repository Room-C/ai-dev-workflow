# Changelog

## 1.1.5 — 2026-04-13

### Improved
- **rc:review-pr**: 重构为「先审查再调度」架构 — 立即执行首轮审查，仅在发现问题时才启动后续定时循环（最多 5 轮跟踪），干净的 PR 零开销即时通过。
- **rc:review-pr**: 新增三通道反馈采集 — 除 PR review comments 外，增加 PR reviews（Request Changes body）和 GitHub Actions Check Run Annotations（CI lint/type/test 错误）。
- **rc:review-pr**: 外部评论闭环回复 — 修复后回复 `✅ 已自动修复`，不适用时回复具体原因，已修复的评论确认修复内容和对应 commit，避免评论悬而未决。
- **rc:review-pr**: 每个 PR 独立状态文件（`/tmp/.review-state-{PR}.json`），支持并发审查多个 PR。

## 1.1.4 — 2026-04-13

### Improved
- **rc:connect-app**: 使用 Marionette 协议替代 Flutter Driver 进行 UI 自动化。新增步骤 3（Marionette UI 自动化检查）：自动检测 `MarionetteBinding` 是否在 `lib/main.dart` 中启用，仅 Debug 模式生效（`kDebugMode` 编译期常量，Release 零开销）。无需创建单独的 `test_driver/main.dart` 入口文件。新增 `tap`、`enter_text`、`scroll`、`screenshot`、`get_text`、`wait_for` 等 MCP 工具权限。

## 1.1.3 — 2026-04-13

### Improved
- **rc:capture-mockups**: Mode C 录制流程自动化 — 自动启动 Codegen（`--output` + `--target javascript`），用户只需在浏览器中操作后关闭，脚本自动保存，无需手动运行命令或复制粘贴代码。

## 1.1.2 — 2026-04-13

### Improved
- **rc:capture-mockups**: 新增 `url` 参数，支持直接传入设计稿 Web URL，不再强制依赖 `.design-to-code.yaml` 配置文件。URL 来源三级回退：参数 > 配置文件 > 交互询问。
- **rc:capture-mockups**: 无参数调用时显示完整的参数引导（必填/可选参数说明 + 使用示例），提升首次使用体验。

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
