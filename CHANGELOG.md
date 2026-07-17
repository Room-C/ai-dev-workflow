# Changelog

## 2.7.0 — 2026-07-17

### Removed
- **rc:read-design / rc:implement-screen / rc:verify-screen**: 移除 Pencil 设计稿转代码链路 — 遥测显示三者始终无使用记录（参见 `docs/workflow-improvement-analysis.md`）。
- **rc:skill-evolve**: 移除自进化分析技能。
- **Execution Telemetry**: 移除 `scripts/record-outcome.sh` 及各 Skill 里调用它的步骤（`feature-analyze`、`feature-archive`、`feature-implement`、`diff-review`、`review-pr`），以及 `CLAUDE.md` 中定义该约定的 Execution Telemetry 段落。唯一消费者 `rc:skill-evolve` 已移除，遥测记录不再有用途。
- 包内 Skill 数量由 13 降至 9；known-issues 注册表不再由 `rc:skill-evolve` 自动维护，改为手动编辑。
- **skills/shared/**: 移除整个目录 — 其中 `known-issues.md` 与 `compound-schema.md` 两份 master 副本自 `rc:skill-evolve` 移除后已无引用者，内容与各 Skill 的 bundled `references/shared/` 副本逐字节一致，不损失任何信息。bundled 副本现在是唯一事实来源，跨 Skill 同步需手动进行。

### Fixed
- 同步 legacy 镜像 `agents/workflow/diff-reviewer.md`、`agents/workflow/fix-runner.md` 至 bundled 最新版 — 此前二者停留在旧版本，缺少 Google 审查维度章节和 zsh `echo` 破坏 JSON 的 `printf` 修复。
- 清理 README / `CLAUDE.md` / `AGENTS.md` 中残留的 Pencil/XcodeBuildMCP/Dart MCP 可选能力描述（仅被已删除的 Design-to-Code 技能使用）。
- README Skill 清单补上此前遗漏的 `rc-branch-create`。

## 2.6.0 — 2026-07-13

### Changed
- **rc:review-pr**: 默认改为单次审查；只有显式 `--follow` 才允许跟踪，并且只能使用可去重的单次唤醒，不再创建 recurring Cron 或从运行中的任务删除自身。
- **rc:review-pr**: reviewer 改为只读状态，拆分 `REVIEW_WAITING_HUMAN`、`REVIEW_RETRY`、`REVIEW_TERMINAL`，避免人工等待和临时故障继续触发无效会话。

### Added
- **rc:review-pr lifecycle gate**: 新增自包含状态机脚本与测试，覆盖 PR 合并/关闭、TTL、tick、无变化、事件轮次、API/reviewer 重试、并发锁、reviewer lease、agent 评论过滤和 terminal tombstone。

## 2.3.0 — 2026-05-21

### Changed
- **Packaging**: 整改为通用 Agent Skills 包，主安装/升级路径切换为 `npx skills add/update`，Claude Code plugin 入口保留为 legacy compatibility。
- **Runtime resources**: 将复杂 Skill 依赖的 agent prompt、known issues、compound schema 和遥测脚本复制到对应 Skill 的 `references/` / `scripts/` 下，支持 `--copy` 单技能安装。
- **Compatibility**: 子代理、Cron、Pencil/Xcode/Dart MCP 改为可选能力；缺失时降级为 inline/manual fallback，不再把 Claude plugin cache 或 Codex companion 作为硬依赖。

## 2.2.5 — 2026-04-21

### Changed
- **pr-reviewer**: 收紧 Step 4 分级判据 — 以「答案数」为单一维度（`gated_auto` = 答案唯一，`manual` = ≥2 种合理方案），边界模糊时倾向 `gated_auto`。修正此前把"补校验 / 同步常量 / 空值守卫"这类单一答案的修复误判为 `manual`、导致 `rc:review-pr` 整流停摆的问题。

## 2.2.4 — 2026-04-21

### Added
- **rc:feature-implement / rc:feature-archive**: 执行完成后自动清理中间文件（analysis.md、design.md、tasks.md），保持工作目录整洁。

### Fixed
- **rc:feature-implement**: 修正 tasks.md 路径占位符规范化，避免路径拼接错误。

## 2.2.3 — 2026-04-20

### Added
- **rc:commit**: 新增独立提交技能 — 仅执行 Stage → Commit → Push，不创建 PR，提交到当前分支。

### Fixed
- **rc:commit-pr**: 修正 Skill 名称（`rc:commit` → `rc:commit-pr`），与目录名保持一致。

## 2.2.2 — 2026-04-20

### Fixed
- **rc:review-pr**: 新增 DONE 状态守卫，防止重复审查已完成的 PR；引入廉价早退门控，首轮无问题时直接返回；补充 post-push 验证，确认推送成功后再标记完成。

### Changed
- **Skills / Agents**: 进一步精调各技能与 Agent 的模型选择，匹配能力与开销平衡。

## 2.2.1 — 2026-04-20

### Changed
- **Skills**: 每个 Skill 明确指定使用模型，确保调度行为与模型能力匹配。

### Fixed
- **rc:diff-review**: 闭环审查工作流重构 — 四层弹性降级（Codex Skill → Codex Bash → Agent SubAgent → 原生内联），三 SubAgent 隔离（diff-reviewer、validation-reviewer、fix-runner）。
- **rc:diff-review / fix-runner**: 验证日志按 KIND 分文件写入，避免顺序覆写破坏失败归因。

## 2.2.0 — 2026-04-17

### Changed
- **架构重构**: 简化 Skill 结构并引入 Agent 分层 — Workflow Agent（task-runner、pr-reviewer、diff-reviewer）从 SKILL.md 中解耦为独立 `agents/` 文件，Skill 只负责调度，Agent 负责执行逻辑，职责边界更清晰。

### Fixed
- **rc:diff-review**: Critical — 修复 Codex 路径发现逻辑（`find .` 搜不到插件缓存），改为 `ls` 通配匹配；`sed` 解锁行错误正则导致注释未移除。
- **rc:review-pr**: High — `gh api` 调用未承接返回值、`git pull/push` 无错误捕获；`fetch_or_stop` 调用处承接返回值修复；`osascript` 通知消息静态化，避免变量注入破坏解析；Check Run annotations 循环中双处下标 bug。
- **rc:commit-pr**: 对 `xargs` 添加非空守卫，避免空列表时意外删除；secrets 检测逻辑覆盖已暂存变更（`git diff --cached`），防止带密钥的暂存文件漏检。
- **Skills 通用**: High — `mkdir -p` 缺失导致状态文件写入失败；Medium — secrets 验证路径与遥测记录静默失败。

### Docs
- **known-issues**: 沉淀 PR #6 三轮 review 教训 — 记录 Bash 静默失败的五类根因与防范模式。

## 2.1.3 — 2026-04-16

### Changed
- **Feature Pipeline**: 合并 `rc:feature-plan` + `rc:plan-executor` 为 `rc:feature-implement`，一条命令完成从任务拆解到代码实现的全流程（内部仍分 Phase 1: Plan → Phase 2: Execute）。支持断点续执行——重新调用时自动检测已有 tasks.md 并跳过 Phase 1。

### Removed
- **rc:feature-plan**: 已合并入 `rc:feature-implement` Phase 1。
- **rc:feature-execute**: 已合并入 `rc:feature-implement` Phase 2。
- **rc:plan-executor**: 已合并入 `rc:feature-implement` Phase 2。

## 2.1.0 — 2026-04-14

### Added
- **rc:skill-evolve**: 新增自进化分析技能 — 分析 Skill 执行遥测数据，识别反复失败模式，自动更新 known-issues 注册表，对严重模式提出 SKILL.md 补丁提案。
- **执行遥测协议**: 所有 Skill 执行结束时记录状态（success/partial/failed）到 `~/.ai-dev-workflow/telemetry.jsonl`，通过共享脚本 `record-outcome.sh` 实现。
- **已知问题注册表**: `skills/shared/known-issues.md` — Skill 执行前读取，主动规避已知问题。

### Changed
- **rc:diff-review**: Step 1 新增读取 known-issues.md；末尾新增 Step 10 遥测记录。
- **CLAUDE.md**: 新增 Execution Telemetry 协议节。

## 2.0.1 — 2026-04-14

### Fixed
- **rc:diff-review**: 修复预处理脚本 `preprocess-diff.sh` 路径查找失败 — `find .` 搜不到插件缓存目录，改为 `ls "$HOME/.claude/plugins/cache/"` 模式匹配。
- **rc:diff-review**: Step 3a Codex Companion 调用改为优先通过 `Skill("codex:review")` 嵌套调用（自动解锁 `disable-model-invocation` 标志），Bash 直调降为 fallback。

## 2.0.0 — 2026-04-13

### Changed
- Design-to-Code 流水线从 Flutter 专用链路切换为 Pencil MCP 驱动的跨平台链路，聚焦 `rc:read-design`、`rc:implement-screen`、`rc:verify-screen` 三个核心技能。
- Feature Pipeline 文档统一为 `rc:feature-design` 与 `rc:feature-plan` 的分步工作流，移除已废弃的 `rc:feature-designer` 组合技能。
- 插件元数据、README、CLAUDE 文档同步更新为 12 个 skills / 6 个 agents，并标记为 2.0.0 版本。

### Removed
- 移除旧的 Flutter Design-to-Code 辅助技能：`rc:init-project`、`rc:capture-mockups`、`rc:extract-tokens`、`rc:connect-app`、`rc:check-alignment`、`rc:design-critique`、`rc:verify-interaction`、`rc:run-golden`、`rc:sync-design`。

### Added
- `rc:read-design`：只读解析 `.pen` 设计稿并输出结构化设计信息。
- `rc:verify-screen`：对比 Pencil 设计稿与实现截图，输出视觉差异与修复建议。

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
- Combo Skills: `rc:plan-executor` (batch execute tasks.md)
- Quality Gates: `rc:diff-review` (local code review with confidence gating), `rc:commit` (conventional commit + PR), `rc:review-pr` (auto PR review loop)
- Flutter Design-to-Code: 10 skills from `rc:init-project` to `rc:sync-design` (historical in 1.0.0)
- 6 agents: analyst, decomposer, 3 design reviewers, task-runner
- Knowledge compounding via `docs/solutions/` with compound-engineering dual-track schema
- `preprocess-diff.sh` for token-efficient diff preprocessing
