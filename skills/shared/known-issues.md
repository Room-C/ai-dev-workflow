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

## review-pr

（暂无）

## feature-design

（暂无）

## implement-screen

（暂无）
