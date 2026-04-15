# Known Issues

所有 Skill 在执行 Step 1（上下文理解）时应读取此文件，遇到匹配场景时主动规避。

本文件由 `rc:skill-evolve` 自动维护，也可手动编辑。

---

## diff-review

- **[2026-04-14]** 预处理脚本路径查找必须用 `ls "$HOME/.claude/plugins/cache/ai-dev-workflow"/*/*/...`，不能用 `find .`。`find .` 只搜项目目录，搜不到插件缓存中的脚本。（v2.0.1 fix）
- **[2026-04-14]** Codex Companion stream 可能断开（exit code 1），确保 Bash 直调 `codex-companion.mjs` 作为 fallback，Agent 审查作为二级 fallback。
- **[2026-04-14]** `codex:review` 默认有 `disable-model-invocation: true` 限制。调用前需 `sed` 解锁，或直接 Bash 调底层脚本。

## feature-execute

（暂无）

## feature-analyze

- **[2026-04-15]** 表格深度有上限约束：事件流表 ≤10 行、状态转换表 ≤8 行、方案对比 ≤3×5。这是刻意设计，不是 bug — 目的是控制上下文消耗，细节留给设计阶段展开。
- **[2026-04-15]** `.context-snapshot.md` 是必需输出（Step 7）。如果跳过生成，下游 `rc:feature-design` 将回退到完整研究模式（Path B），失去上下文节省效果。

## review-pr

（暂无）

## feature-design

- **[2026-04-15]** Step 1 有双路径：路径 A（增量模式，读取 `.context-snapshot.md`）和路径 B（完整模式）。仅当 analysis.md 和 `.context-snapshot.md` 同时存在时才走路径 A。
- **[2026-04-15]** Step 3 审查员可被条件跳过：纯 UI 变更可跳过一致性审查，单模块无新依赖可跳过可行性审查，≤3 文件可跳过范围守卫。不确定时必须启用。
- **[2026-04-15]** 审查报告写入 `reviews/` 子目录，主上下文仅接收一行摘要。如果审查员返回了完整报告内容到主上下文，说明 Agent 指令未被遵循，应检查 Agent 定义中的 `⚠️ 严禁` 警告。

## implement-screen

（暂无）
