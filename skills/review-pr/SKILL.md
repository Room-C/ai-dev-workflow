---
name: rc:review-pr
description: 自动化 PR Code Review — 先立即审查，仅在发现问题时启动后续跟踪循环。
argument-hint: "[PR-number] [--model sonnet|opus|haiku]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion, CronCreate, CronDelete
---

# Auto PR Review Agent

先立即执行一次完整审查。如果 PR 没有问题，直接通过，不创建定时任务。仅在发现问题并修复后，才启动后续跟踪循环（最多 5 轮），直到所有问题解决。

## 使用方式

```
rc:review-pr                       # 最新 PR，默认模型
rc:review-pr 42                    # 指定 PR #42
rc:review-pr --model sonnet        # 用 Sonnet 模型
rc:review-pr 42 --model haiku      # 指定 PR + 指定模型
```

支持的模型：`sonnet`（默认）、`opus`、`haiku`

---

## Section 1: 启动指令

解析 `$ARGUMENTS` 中的参数：
1. 提取 PR 号（纯数字部分），如果没有则留空
2. 提取 `--model <model>` 参数，支持 `opus`/`sonnet`/`haiku`，默认 `sonnet`

获取 PR 信息：
- 如果指定了 PR 号，直接使用
- 否则运行 `gh pr list --state open --limit 1 --json number,title,headRefName,baseRefName,url` 获取最新 open PR
- 如果没有 open PR，输出 "No open PR found." 然后结束

获取 Repo 信息：`gh repo view --json nameWithOwner -q '.nameWithOwner'`

记录：PR number、head branch、base branch、repo owner/name。

---

## Section 2: 首轮审查（立即执行，不经过 Cron）

使用 Agent 工具派发 subagent，设置 `model` 参数为用户指定的模型。将下方「Review 流程」完整传入 Agent prompt。

### 首轮 Agent 完成后的判定门控

根据 Agent 返回的结果判断：

1. **PR 无问题**（没有发现 🔴/🟡 问题）：
   - 使用 `gh api` 提交 PR review comment：`✅ 自动审查通过 — 未发现需要修复的问题，可以合并。`
   - 发送 macOS 通知：`osascript -e 'display notification "PR #<NUMBER> 审查通过，可以合并" with title "Review Agent" sound name "Glass"'`
   - **结束，不创建定时任务**

2. **PR 有问题且已自动修复**（所有 🔴/🟡 已被 safe_auto/gated_auto 修复并推送）：
   - 创建状态文件：`echo '{"pr":<NUMBER>,"round":1,"maxRounds":6}' > /tmp/.review-state-<PR_NUMBER>.json`
   - 进入 Section 3，启动后续跟踪循环（验证修复是否充分）

3. **PR 有问题且存在 manual 项**（需要人工处理的问题）：
   - 创建状态文件
   - 进入 Section 3，启动后续跟踪循环（等待人工修复后 re-review）

---

## Section 3: 后续跟踪循环（仅在 Section 2 发现问题时启动）

创建 CronCreate 定时任务（每 5 分钟），将以下 Loop Prompt 作为 CronCreate 的 prompt 参数。

**关键：** 在 prompt 中传入 PR 号、repo 信息、状态文件路径、model 参数。

---

## Review 流程（首轮 Agent 和 Loop Prompt 共用）

以下流程被两处使用：
- Section 2 的首轮 Agent（完整执行 Step 1 ~ Step 5）
- Section 3 的 CronCreate prompt（每轮执行 Step 0 ~ Step 6）

```
你是一个自动化 PR Code Review Agent。严格按以下流程执行。
所有 PR Review Comment 必须使用**简体中文**书写。

## 环境信息
- Repo: {REPO}（调用方传入，或通过 `gh repo view --json nameWithOwner -q '.nameWithOwner'` 获取）
- PR: #{PR_NUMBER}，head branch: {HEAD_BRANCH}，base branch: {BASE_BRANCH}
- 状态文件: /tmp/.review-state-{PR_NUMBER}.json
- 验证命令: 从项目 CLAUDE.md 的 Verification 章节读取
- 参考 CLAUDE.md 中的 Architecture Boundaries 和 Code Conventions

## Step 0: 轮次管理（仅 CronCreate 模式）
1. **检查 PR 状态（最先执行）：**
   ```bash
   PR_STATE=$(gh pr view {PR_NUMBER} --json state -q '.state')
   ```
   如果 `PR_STATE` 不是 `OPEN`（即已 MERGED 或 CLOSED）：
   - 发送 macOS 通知：`"PR #{PR_NUMBER} 已合并/关闭，自动审查停止"`
   - CronDelete 取消定时任务
   - 删除状态文件
   - 结束（不执行后续任何步骤）
2. 读取状态文件 `/tmp/.review-state-{PR_NUMBER}.json`
3. round += 1，写回状态文件
4. 如果 round > maxRounds：
   - 发送 macOS 通知："PR #{PR_NUMBER} 已达最大审查轮次（{maxRounds} 轮），请人工检查"
   - CronDelete 取消定时任务
   - 删除状态文件
   - 结束

## Step 1: 增量变更检测 + 已有 Review 汇总
1. 运行 `gh pr diff {PR_NUMBER}` 获取 diff
2. 获取所有反馈来源：
   a. **PR Review Comments：** `gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments --paginate` 获取所有 reviewer（包括 bot）的 inline comment
   b. **PR Reviews：** `gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews --paginate` 获取 review 级别的反馈（如 "Request Changes" 附带的 body）
   c. **Check Run Annotations：** 获取 GitHub Actions 等 CI 产生的 lint/type/test 错误：
      ```bash
      # 获取 PR head commit 的 check runs
      gh api repos/{owner}/{repo}/commits/{HEAD_SHA}/check-runs --paginate \
        -q '.check_runs[] | select(.conclusion == "failure" or .conclusion == "action_required") | {name: .name, id: .id}'
      # 对每个失败的 check run，获取具体 annotations
      gh api repos/{owner}/{repo}/check-runs/{CHECK_RUN_ID}/annotations --paginate
      ```
      将 `warning` 和 `failure` 级别的 annotation 纳入待处理清单（`notice` 级别忽略）。
3. **如果不是首轮且自上次 push 以来没有新 commit**（对比 HEAD SHA），输出 "No new changes since last review, skipping." 然后结束本轮（不取消 loop）
4. **汇总外部反馈：** 逐条阅读其他 reviewer（如 Gemini、人类 reviewer、GitHub Actions）的未解决 comment 和 annotation，判断其合理性，纳入本轮待处理清单。不要忽略其他 reviewer 的有效发现。
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

如果未发现任何 🔴/🟡 问题，**返回 REVIEW_CLEAN 信号**并跳过后续步骤。

## Step 3: 读取待修复 Comments + Annotations
获取所有反馈（复用 Step 1 的数据）：PR review comments、PR reviews、Check run annotations。

合并以下来源的待修复项到统一清单：
- **自己发出的** 🔴 和 🟡 comment
- **其他 reviewer（Gemini、人类等）发出的**合理 comment（在 Step 1 中已评估过合理性）
- **GitHub Actions 等 CI 的** warning/failure annotation
- **人工明确要求修复的** comment

对每条外部反馈进行状态判定：

| 状态 | 判定依据 | 处理方式 |
|------|---------|---------|
| **待修复** | 问题在当前 diff 中仍然存在 | 纳入修复清单 |
| **已修复** | 问题涉及的代码已在后续 commit 中改正 | 用 `gh api` 回复确认：`✅ 已修复：<简述修复内容和对应 commit>` |
| **不适用** | 经评估不合理（误报、过时、不符合项目规范） | 用 `gh api` 回复说明原因（简体中文） |
| **讨论性质** | 非具体代码问题，属于设计讨论 | 用 `gh api` 回复说明原因（简体中文） |

跳过以下（不纳入修复清单但仍需回复）：
- 🟢 可选优化 → 跳过，不回复
- 已有自己的回复（避免重复回复同一条 comment）→ 跳过

## Step 4: 分级修复

对每个待修复 comment 先分级，再处理：

| 修复类型 | 适用场景 | 处理方式 |
|---------|---------|---------|
| `safe_auto` | 格式修正、import 排序、命名规范、死代码删除、简单类型标注 | 直接修复，无需确认 |
| `gated_auto` | 行为变更、API 契约修改、认证/授权相关、数据模型变更 | 修复 + PR comment 请求用户确认 |
| `manual` | 需要设计决策、多种合理方案、涉及业务逻辑判断 | 不修复，用 `gh api` 回复说明问题和建议方案（简体中文） |
| `advisory` | 信息性发现、风格偏好 | 不修复，不回复 |

执行修复：
1. 确保当前在 PR 的 head branch 上：`git checkout {HEAD_BRANCH} && git pull origin {HEAD_BRANCH}`
2. 逐个修复 `safe_auto` 和 `gated_auto` 标记的问题
3. 每个修复保持最小化，不做额外重构
4. **修复后必须回复对应的 comment/annotation**：
   - `safe_auto` 修复后 → 回复：`✅ 已自动修复：<简述修改内容>`
   - `gated_auto` 修复后 → 回复：`⚠️ 已修复，请确认：<简述修改内容及理由>`
   - `manual` 问题 → 回复：`🔍 需要人工决策：<问题分析 + 建议方案>`
   - 来自 Check Run Annotation 的问题修复后 → 在 PR 上发一条总结 comment，按 check run 分组列出修复内容

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
   - `git push origin {HEAD_BRANCH}`
4. **返回 REVIEW_FIXED 信号**，附带修复摘要

## Step 6: 完成判定（仅 CronCreate 模式）
当所有 🔴🟡 问题已解决，re-review 无新问题时：
1. 提交一条最终 PR review comment（简体中文）：`✅ 自动审查完成 — 所有问题已修复，可以合并。`
2. 发送 macOS 通知：
   `osascript -e 'display notification "PR #{PR_NUMBER} Review 完成，所有问题已修复，可以合并了" with title "Review Agent" sound name "Glass"'`
3. CronDelete 取消定时任务
4. 删除状态文件
```

---

## 重要约束
- 不要 force push
- 不要修改 .env、lockfile、CI 配置
- 每次 push 前确保当前 branch 是最新的（先 pull）
- 如果遇到 merge conflict，不要自动解决，发通知告知用户手动处理，然后取消 loop
- 首轮 + 后续合计最多 6 轮，超过则通知用户并停止
- 测试修复最多尝试 3 次，超过则回滚并通知
