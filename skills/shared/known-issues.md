# Known Issues

所有 Skill 在执行 Step 1（上下文理解）时应读取此文件，遇到匹配场景时主动规避。

本文件由 `rc:skill-evolve` 自动维护，也可手动编辑。

---

## 通用 Skill 设计原则

- **[2026-04-17]** **Skill 里的 bash 片段必须可直接执行，不接受隐性约定。** LLM 会按字面执行示例代码，不会像人类那样脑补"调用处应该检查返回值"或"prose 里说了条件所以这里就不加守卫"。PR #6 的三轮 review 分别命中三种同类反模式：
  - **prose 条件 vs 代码守卫脱节** — 文字说"If X, do Y"，bash 块里却无条件执行 Y。✘ `echo "$X" | xargs cmd` ✓ `[ -n "$X" ] && echo "$X" | xargs cmd`
  - **跨语言转义假设** — `osascript -e "...\"$VAR\"..."` 在 `$VAR` 含引号/元字符时破坏 AppleScript 解析。✘ 嵌入外部输出 ✓ 通知消息静态化，详情走 stderr
  - **函数封装但调用不承接** — 定义了 `fetch_or_stop() { ...; return 1; }`，调用写成 `fetch_or_stop <args>` 而非 `VAR=$(fetch_or_stop <args>) \|\| return REVIEW_STOPPED`。✘ 示意性调用 ✓ 可直接运行的完整形式
  - **循环内捕获变量覆盖** — `for x in ...; do VAR=$(cmd $x); done` 每次迭代都覆盖 VAR，循环结束后只剩最后一次的结果。✘ 捕获供后续处理 ✓ 让命令直接输出让上层 Agent 读累积流
  - **规避方式**：写 bash 时问自己"LLM 把这行原样执行会不会出问题"，而非"读者会理解我的意图"。

---

## diff-review

- **[2026-04-14]** 预处理脚本路径查找必须用 `ls "$HOME/.claude/plugins/cache/ai-dev-workflow"/*/*/...`，不能用 `find .`。`find .` 只搜项目目录，搜不到插件缓存中的脚本。（v2.0.1 fix）
- **[2026-04-14]** Codex Companion stream 可能断开（exit code 1），确保 Bash 直调 `codex-companion.mjs` 作为 fallback，Agent 审查作为二级 fallback。
- **[2026-04-14]** `codex:review` 默认有 `disable-model-invocation: true` 限制。调用前需 `sed` 解锁，或直接 Bash 调底层脚本。
- **[2026-04-17]** `ls ... | tail -1` 选版本存在风险：词典序不等于版本序，可能选到旧版。用 `sort -V | tail -1` 保证确定性。（PR #6）
- **[2026-04-17]** `sed -i ''` 是 BSD 专属语法，跨平台失败。统一用 `sed -i.bak ... && rm -f *.bak` 形式。（PR #6）

## feature-implement

（暂无）

## feature-analyze

- **[2026-04-15]** 表格深度有上限约束：事件流表 ≤10 行、状态转换表 ≤8 行、方案对比 ≤3×5。这是刻意设计，不是 bug — 目的是控制上下文消耗，细节留给设计阶段展开。
- **[2026-04-15]** `.context-snapshot.md` 是必需输出（Step 7）。如果跳过生成，下游 `rc:feature-design` 将回退到完整研究模式（Path B），失去上下文节省效果。

## review-pr

- **[2026-04-17]** `gh api` 空返回 ≠ "0 条结果"。rate limit / token 过期时也返回空。必须用 `VAR=$(fetch_or_stop ...) \|\| return REVIEW_STOPPED` 区分，否则会在有未解决 🔴 的 PR 上错误地发"审查通过"通知。（PR #6）
- **[2026-04-17]** 状态文件 `/tmp/.review-state-<N>.json` 写入失败会导致 Cron 死循环（读空 JSON，round 永远为 1，maxRounds 守卫失效）。写入后必须 `[ -s ]` 校验，失败拒绝创建 Cron。（PR #6）
- **[2026-04-17]** `osascript -e "...$VAR..."` 有三层嵌套引号（bash → osascript → AppleScript 字符串）。嵌入包含引号的 `$VAR` 会破坏解析。通知消息保持静态，详情走 stderr。（PR #6）

## feature-design

- **[2026-04-15]** Step 1 有双路径：路径 A（增量模式，读取 `.context-snapshot.md`）和路径 B（完整模式）。仅当 analysis.md 和 `.context-snapshot.md` 同时存在时才走路径 A。
- **[2026-04-15]** Step 3 审查员可被条件跳过：纯 UI 变更可跳过一致性审查，单模块无新依赖可跳过可行性审查，≤3 文件可跳过范围守卫。不确定时必须启用。
- **[2026-04-15]** 审查报告写入 `reviews/` 子目录，主上下文仅接收一行摘要。如果审查员返回了完整报告内容到主上下文，说明 Agent 指令未被遵循，应检查 Agent 定义中的 `⚠️ 严禁` 警告。

## implement-screen

（暂无）

## commit-pr

- **[2026-04-17]** `echo "$VAR" | xargs cmd` 在 `$VAR` 为空时仍会执行 `cmd ""`（BSD xargs 尤其明显），导致非预期行为。必须加前置守卫 `[ -n "$VAR" ] && echo "$VAR" | xargs ...`。（PR #6）
- **[2026-04-17]** `git reset HEAD -- <file>` 对 secrets 取消暂存后必须再次 `git diff --cached --name-only | grep` 验证，reset 可能因路径转义/case mismatch 静默失败。（PR #6）
- **[2026-04-17]** 检测"即将提交的文件"要用 `git diff HEAD --name-only`，不能用 `git diff --name-only`（后者只含未暂存）。否则用户预先 `git add` 过的 secrets 会漏检。（PR #6）
