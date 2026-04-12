---
name: rc:review-pr
description: 自动化 PR Code Review 循环 — 每 5 分钟检查，最多 6 轮，分级修复。
argument-hint: "[PR-number] [--model sonnet|opus|haiku]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion, CronCreate, CronDelete
---

# Auto PR Review Agent

配置一个自动化 PR Code Review 循环，每 5 分钟检查一次，最多 6 轮，直到所有问题修复完毕。

## 使用方式

```
rc:review-pr                       # 最新 PR，默认模型
rc:review-pr 42                    # 指定 PR #42
rc:review-pr --model sonnet        # 用 Sonnet 模型
rc:review-pr 42 --model haiku      # 指定 PR + 指定模型
```

支持的模型：`sonnet`（默认）、`opus`、`haiku`

---

## 启动指令

解析 `$ARGUMENTS` 中的参数：
1. 提取 PR 号（纯数字部分），如果没有则留空（后续自动获取最新 PR）
2. 提取 `--model <model>` 参数，支持 `opus`/`sonnet`/`haiku`，默认 `sonnet`

配置并启动一个 CronCreate 定时任务（每 5 分钟，**最多 6 轮**）。

**关键：** 每轮 loop 触发时，必须使用 Agent 工具将实际 review 工作派发给 subagent，并在 Agent 调用中设置 `model` 参数为用户指定的模型（默认 `sonnet`）。

**轮次管理：** 在首轮 CronCreate 之前创建一个轮次计数变量 `round=0`，每轮开始时 `round += 1`。当 `round > 6` 时，发送 macOS 通知告知用户已达最大轮次，然后 CronDelete 取消定时任务。

---

## Loop Prompt（以下内容作为 CronCreate 的 prompt）

```
你是一个自动化 PR Code Review Agent。严格按以下流程执行。
所有 PR Review Comment 必须使用**简体中文**书写。

## 环境信息
- Repo: 通过 `gh repo view --json nameWithOwner -q '.nameWithOwner'` 动态获取
- 验证命令: 从 CLAUDE.md Verification 章节读取
- 参考 CLAUDE.md 中的 Architecture Boundaries 和 Code Conventions

## Step 0: 获取目标 PR
如果用户指定了 PR 号，使用该 PR 号。
否则运行 `gh pr list --state open --limit 1 --json number,title,headRefName,baseRefName,url` 获取最新 open PR。

如果没有 open PR，输出 "No open PR found, skipping this round." 然后结束本轮（不取消 loop）。

记录 PR number、head branch name、base branch name。

## Step 1: 增量变更检测 + 已有 Review 汇总
1. 运行 `gh pr diff <PR_NUMBER>` 获取 diff
2. 运行 `gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --paginate` 获取**所有 reviewer（包括 bot）**的已有 comment
3. **如果本轮不是首轮且自上次 push 以来没有新 commit**（对比 HEAD SHA），输出 "No new changes since last review, skipping." 然后结束本轮
4. **汇总外部 reviewer 的发现：** 逐条阅读其他 reviewer（如 Gemini、人类 reviewer）的未解决 comment，判断其合理性，纳入本轮待处理清单。不要忽略其他 reviewer 的有效发现。
5. 以 senior engineer 标准 review diff，重点关注：
   - Bug 和逻辑错误
   - 安全漏洞（SQL 注入、XSS、PII 泄露、密钥硬编码等）
   - 架构违规（参考 CLAUDE.md Architecture Boundaries）
   - 未处理的错误/异常路径
   - 明显的性能问题
   - 类型安全问题
   - **Markdown/YAML/配置文件中嵌入的脚本逻辑**（如 bash 代码块中的变量、循环、条件判断）
6. **忽略（不提 comment）：** 纯风格偏好、注释措辞、import 顺序、空行数量

## Step 2: 提交 Review Comments（简体中文）
如果发现问题，使用 `gh api` 提交 PR review，带 inline comments 标注具体文件和行号。

每条 comment body 必须使用简体中文，并标注严重级别：
- `🔴 必须修复:` — Bug、安全漏洞、会导致崩溃/数据丢失的问题
- `🟡 建议修复:` — 逻辑不严谨、缺少错误处理、性能问题
- `🟢 可选优化:` — 可以改进但不阻塞合并

## Step 3: 读取待修复 Comments
运行 `gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --paginate` 获取所有 review comments。

合并以下来源的待修复项到统一清单：
- **自己发出的** 🔴 和 🟡 comment
- **其他 reviewer（Gemini、人类等）发出的**合理 comment（在 Step 1 中已评估过合理性）
- **人工明确要求修复的** comment

跳过以下 comment：
- 🟢 可选优化 → 跳过
- 已有回复标记 resolved → 跳过
- 经评估不合理的外部 reviewer comment → 跳过，但用 `gh api` 回复说明原因（简体中文）
- 人工讨论性质的 comment → 跳过，回复说明原因（用简体中文）

## Step 4: 分级修复

对每个待修复 comment 先分级，再处理：

| 修复类型 | 适用场景 | 处理方式 |
|---------|---------|---------|
| `safe_auto` | 格式修正、import 排序、命名规范、死代码删除、简单类型标注 | 直接修复，无需确认 |
| `gated_auto` | 行为变更、API 契约修改、认证/授权相关、数据模型变更 | 修复 + PR comment 请求用户确认 |
| `manual` | 需要设计决策、多种合理方案、涉及业务逻辑判断 | 不修复，用 `gh api` 回复说明问题和建议方案（简体中文） |
| `advisory` | 信息性发现、风格偏好 | 不修复，不回复 |

执行修复：
1. 确保当前在 PR 的 head branch 上：`git checkout <head_branch> && git pull origin <head_branch>`
2. 逐个修复 `safe_auto` 和 `gated_auto` 标记的问题
3. 每个修复保持最小化，不做额外重构
4. `gated_auto` 修复提交后，用 `gh api` 在对应 comment 回复请求用户确认
5. `manual` 问题用 `gh api` 回复说明问题和建议方案（简体中文）

## Step 5: 测试 + 验证 + 提交 + 推送

修复完成后，**必须所有测试通过才能提交**。流程如下：

1. 从项目 CLAUDE.md 的 Verification 章节读取对应变更类型的验证命令。根据 diff 涉及的模块自动选择正确的验证套件。
2. **如果测试失败**：
   - 分析失败原因，判断是修复引入的回归还是已有问题
   - 如果是修复引入的：立即修复，重新运行测试，循环直到全部通过（最多 3 次尝试）
   - 如果是已有问题（修复前就存在的 flaky test）：记录但不阻塞，在 commit message 中注明
   - 如果 3 次仍未通过：回滚本轮修改，发通知告知用户，结束本轮
3. **所有测试通过后**才执行：
   - `git add <具体文件>` （不用 git add -A）
   - `git commit -m "fix(review): <描述修复内容>"`
   - `git push origin <head_branch>`
4. 本轮结束，下一轮循环会 re-review

## Step 6: 完成判定
当所有 🔴🟡 问题已解决，re-review 无新问题时：
1. 提交一条最终 PR review comment（简体中文）：`✅ 自动审查完成 — 所有问题已修复，可以合并。`
2. 发送 macOS 通知：
   `osascript -e 'display notification "PR #<NUMBER> Review 完成，所有问题已修复，可以合并了" with title "Review Agent" sound name "Glass"'`
3. 取消这个定时任务（调用 CronDelete）

## 重要约束
- 不要 force push
- 不要修改 .env、lockfile、CI 配置
- 每次 push 前确保当前 branch 是最新的（先 pull）
- 如果遇到 merge conflict，不要自动解决，发通知告知用户手动处理，然后取消 loop
- 最多 6 轮，超过则通知用户并停止
- 测试修复最多尝试 3 次，超过则回滚并通知
```
