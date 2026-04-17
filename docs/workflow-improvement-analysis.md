# ai-dev-workflow 改进分析报告

> 基于 2026-04-04 至 2026-04-16 使用数据（138 会话 / 973 消息 / 11 活跃天）、执行遥测日志和 Skill 定义的交叉分析。

---

## 一、现状总结

### 1.1 核心指标

| 指标 | 数值 | 解读 |
|------|------|------|
| 任务完全达成率 | 72% (50/69) | 高于多数 AI 辅助开发场景，但仍有 28% 需返工 |
| 方法错误（最大摩擦源） | 15 次 | 占全部摩擦的 42%，是排名第一的效率杀手 |
| 代码有 Bug | 10 次 | 第二大摩擦源，集中在 Xcode 集成和跨栈数据管道 |
| `feature-implement` partial 率 | 5/6 (83%) | 遥测显示 6 次 plan-executor 执行中仅 1 次不是 partial |
| `diff-review` 降级率 | 1/3 (33%) | Codex Companion 超时导致回退到 Agent 审查 |
| 深夜工作占比 | 28% (271/973) | 0-6 点消息量甚至超过上午，暗示长会话跨时段运行 |

### 1.2 三大流水线健康度

| 流水线 | 状态 | 主要瓶颈 |
|--------|------|---------|
| Feature Pipeline | 🟡 功能完整但断点多 | plan-executor 频繁 partial；阶段间需手动触发 |
| Quality Gates | 🟢 基本健康 | Codex Companion 偶尔超时；diff 覆盖面曾遗漏未暂存变更 |
| Design-to-Code | 🔴 使用率低 | known-issues 中 implement-screen 为空，实际遥测无记录 |

---

## 二、改进方向（按投入产出比排序）

### 2.1 [高优] feature-implement 的 partial 问题根治

**现象**：遥测中 6 次 `rc:plan-executor` / `feature-implement` 执行，5 次以 `partial` 结束。失败原因高度一致：

```
"full verification blocked by existing repo-wide ruff/mypy/pytest failures"
"full repo ruff/mypy blocked by pre-existing baseline issues"
"staging validation is still pending"
```

**根因**：Skill 的验证门控（Step 2.3）要求"全量测试通过"，但项目存在预置的 lint/type 基线错误。这些错误不是当前任务引入的，却阻断了任务标记为 `✅`。

**改进方案**：

1. **引入基线快照机制**：在 Phase 2 开始前记录当前 lint/type 错误数量，验证时只检查"是否引入了新错误"（delta 模式），而非要求全量通过
2. **在 SKILL.md 中增加 `--baseline-tolerant` 参数**：允许用户显式声明项目有预存问题，验证逻辑切换为增量模式
3. **在 tasks.md 元数据中记录基线状态**：断点续执行时也能正确判断

**预期效果**：将 partial 率从 83% 降到 ~20%（仅真正由当前任务引入的失败才触发 partial）。

---

### 2.2 [高优] Xcode 项目集成的系统性防护

**现象**：报告中反复出现：
- 新 Swift 文件未添加到 .xcodeproj
- 文件被加到错误的 build phase（Tests 而非 App）
- 子串匹配导致重复 group 引用

**改进方案**（分层防御）：

| 层级 | 措施 | 实现位置 |
|------|------|---------|
| L1 规则层 | 在 CLAUDE.md 中添加 iOS Development 规则（报告已建议） | 项目 CLAUDE.md |
| L2 Hook 层 | 创建 `afterWrite` hook：当新建 `.swift` 文件时自动运行 pbxproj 成员检查脚本 | `.claude/settings.json` |
| L3 验证层 | 在 `feature-implement` 的 Step 2.3 验证中，对 iOS 项目追加 `xcodebuild -project ... -list` 检查 | SKILL.md 或 CLAUDE.md Verification |

**L2 的 Hook 脚本草案**：

```bash
#!/bin/bash
# scripts/verify_xcodeproj_membership.sh
SWIFT_FILE="$1"
PBXPROJ=$(find . -name "*.xcodeproj" -maxdepth 2 | head -1)/project.pbxproj
FILENAME=$(basename "$SWIFT_FILE")
if [ -f "$PBXPROJ" ]; then
  COUNT=$(grep -c "$FILENAME" "$PBXPROJ")
  if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: $FILENAME not found in xcodeproj. Add it to the correct target."
    exit 1
  elif [ "$COUNT" -gt 2 ]; then
    echo "WARNING: $FILENAME appears $COUNT times in xcodeproj. Possible duplicate group reference."
    exit 1
  fi
fi
```

---

### 2.3 [高优] 上下文漂移的自动检测

**现象**：Claude 多次在错误的 worktree/分支/目录中操作，15 次"方法错误"中约 1/3 与此相关。

**改进方案**：

1. **Session Start Hook**：在 `.claude/settings.json` 中配置 `PreToolUse` hook，在每次会话首次编辑前自动运行：
   ```bash
   echo "CWD: $(pwd)"
   echo "Branch: $(git branch --show-current)"
   echo "Worktree: $(git worktree list 2>/dev/null | head -5)"
   ```

2. **在 feature-implement Step 2.0 增强**：当前只检查"工作区干净"和"不在主分支"，应追加：
   - 检查 `pwd` 是否与 design.md 所在项目一致
   - 检查当前 worktree 是否为预期的工作分支
   - 如果检测到不匹配，阻断执行并提示用户

3. **在 diff-review Step 1 增强**：在收集 diff 前先确认当前分支确实是期望审查的分支，特别是当使用 worktree 时

---

### 2.4 [中优] 流水线阶段自动衔接

**现象**：feature-analyze → feature-design → feature-implement 三阶段每次都需要手动触发，用户需要分别调用 3 个 skill。报告指出"有些会话在阶段之间被中断或达到使用限制"。

**改进方案**：创建一个 `/rc:feature-pipeline` 元 Skill：

```
用户输入: /rc:feature-pipeline <module> <需求描述>

自动流程:
1. 调用 rc:feature-analyze → 产出 analysis.md
2. 检查点: 显示分析摘要，询问"继续设计？"
3. 调用 rc:feature-design → 产出 design.md
4. 检查点: 显示设计摘要 + 审查结论，询问"继续实现？"
5. 调用 rc:feature-implement → 产出 tasks.md + 代码
```

**关键设计决策**：
- 每个检查点默认自动继续（5 秒无响应则进入下一阶段），通过 `--auto` 参数控制
- 每个阶段完成后都将关键文件路径写入 `.pipeline-state.json`，支持中断恢复
- 如果触发上下文限制，保存状态并提示用户用 `/rc:feature-pipeline --resume <module>` 恢复

---

### 2.5 [中优] Codex Companion 超时的优雅降级

**现象**：遥测显示 `diff-review` 有 33% 的降级率，原因是 `codex companion timeout after 9min`。

**改进方案**：

1. **在 SKILL.md Step 3a 增加超时控制**：给 Codex Companion 调用设置 5 分钟硬超时（当前无超时限制）
2. **并行预热**：在等待 Codex Companion 的同时，提前准备 Agent 审查所需的上下文（diff 预处理、CLAUDE.md 摘要），降级时无需重复准备
3. **在 known-issues.md 中记录**：Codex Companion 超时阈值和降级路径，让后续执行的 Step 1 能主动预判

---

### 2.6 [中优] 遥测数据的可观测性提升

**现象**：当前遥测仅记录 skill 名、状态和失败原因，缺少以下关键维度：

- 执行耗时（无法判断是超时还是正常完成）
- 涉及文件数/行数（无法衡量 Skill 处理规模）
- 降级链路（`fallback_used` 字段不够结构化）
- 上下文限制是否触发

**改进方案**：

1. 在 `record-outcome.sh` 中增加字段：

```json
{
  "ts": "...",
  "skill": "...",
  "status": "...",
  "duration_seconds": 180,
  "files_changed": 12,
  "lines_changed": "+340/-28",
  "context_limit_hit": false,
  "degradation_chain": ["3a_skill", "3a_bash", "3b_agent"],
  "failure_step": "...",
  "failure_reason": "..."
}
```

2. 创建 `skill-evolve` 的分析模板，定期（每周）从 `telemetry.jsonl` 生成趋势报告

---

### 2.7 [中优] PR 审查循环的效率优化

**现象**：报告显示 18 个会话用于代码审查，PR #25-29 经历了多轮审查循环。当前 `review-pr` 最多 6 轮，每轮间隔 5 分钟。

**改进方案**：

1. **首轮快速通道**：如果首轮只发现 P3 级问题，直接通过，不进入循环
2. **智能间隔**：首轮修复后立即触发第二轮（不等 5 分钟），之后再按 5 分钟间隔
3. **修复验证前置**：在推送修复前先在本地运行完整测试套件，避免推送后 CI 失败又需要一轮
4. **与 diff-review 去重**：如果同一分支已经运行过 `diff-review`，`review-pr` 应复用已有的审查结果，只增量审查新变更

---

### 2.8 [低优] Design-to-Code 流水线激活

**现象**：`read-design`、`implement-screen`、`verify-screen` 三个 Skill 在遥测中无记录，known-issues 中标注"暂无"。但报告显示约 18 个会话用于 iOS 功能开发，涉及从 Pencil 设计文件集成设计系统。

**推测**：用户可能直接手动完成了设计到代码的转换，未使用这三个自动化 Skill。

**改进方案**：

1. **收集反馈**：了解为何 Design-to-Code Skill 未被使用——是不知道存在、不信任质量、还是流程不匹配
2. **在 feature-implement 中集成设计参照**：当任务涉及 UI 变更时，自动检查是否存在 `.pen` 设计文件，并在实现时参照
3. **在 README / Skill 描述中强化可发现性**

---

### 2.9 [低优] 会话启动上下文模板

**现象**：报告指出"会话启动时往往缺乏足够的上下文说明目标 worktree 或分支"。

**改进方案**：创建一个轻量的 Session Start Skill 或 Hook，在会话开始时自动输出：

```
📍 环境快照
   目录: /Users/bob/Work/MyProject/PactPilot-Backend
   分支: feature/chat-streaming
   Worktree: backend/claude (非主 worktree)
   最近 3 次 commit: ...
   未提交变更: 2 files modified

⚠️ 注意：当前在 worktree 'backend/claude' 中，主仓库在 ../PactPilot-Backend
```

这让 Claude 和用户双方都能在会话开始时对齐上下文。

---

## 三、改进优先级矩阵

```
影响力 ↑
  高  │ 2.1 基线容忍   2.4 流水线衔接
      │ 2.2 Xcode 防护  
      │ 2.3 上下文检测  
  中  │ 2.5 Codex 降级  2.7 PR 审查优化
      │ 2.6 遥测增强    
  低  │ 2.8 D2C 激活    2.9 会话模板
      └──────────────────────────────→ 实现成本
           低              中            高
```

**建议执行顺序**：

| 批次 | 改进项 | 预计工作量 | 预期效果 |
|------|--------|-----------|---------|
| 第一批（立即） | 2.1 基线容忍 + 2.2 Xcode L1 规则 + 2.3 上下文检测 | 2-3 小时 | 消除最常见的 partial 和构建失败 |
| 第二批（本周） | 2.2 Xcode L2 Hook + 2.5 Codex 降级 + 2.7 PR 审查 | 3-4 小时 | 减少人工干预轮次 |
| 第三批（下周） | 2.4 流水线衔接 + 2.6 遥测增强 | 1-2 天 | 释放更多自治能力 |
| 第四批（待定） | 2.8 D2C 激活 + 2.9 会话模板 | 半天 | 补全流水线覆盖 |

---

## 四、数据附录

### 4.1 遥测执行记录（2026-04-14 ~ 2026-04-16）

| 时间 | Skill | 项目 | 状态 | 失败点 | 原因 |
|------|-------|------|------|--------|------|
| 04-14 19:30 | plan-executor | Backend | partial | T16 | 全量验证被 repo 预存错误阻断 |
| 04-14 20:27 | diff-review | Backend | success | - | - |
| 04-15 10:59 | diff-review | Backend | partial | 3a_skill | Codex Companion 9 分钟超时 |
| 04-15 11:03 | plan-executor | Backend | partial | T06 | ruff/mypy 预存问题 |
| 04-15 11:08 | diff-review | Backend | success | - | - |
| 04-15 13:34 | feature-analyze | Backend | success | - | - |
| 04-15 13:55 | feature-design | Backend | success | - | - |
| 04-15 14:21 | feature-plan | Backend | success | - | - |
| 04-15 16:17 | feature-analyze | Backend | success | - | - |
| 04-15 16:33 | feature-design | Backend | success | - | - |
| 04-15 16:56 | feature-plan | Backend | success | - | - |
| 04-16 02:25 | feature-analyze | Backend | success | - | - |
| 04-16 02:38 | feature-design | Backend | success | - | - |
| 04-16 11:04 | plan-executor | Backend | partial | T04 | staging 验证未完成 |
| 04-16 11:28 | plan-executor | Backend | partial | T13 | 用户未合并变更冲突 |
| 04-16 11:45 | plan-executor | Backend | partial | T15 | checkpoint before T15 |

### 4.2 Skill 健康度评分

| Skill | 执行次数 | 成功率 | 主要风险 | 健康评分 |
|-------|---------|--------|---------|---------|
| feature-analyze | 3 | 100% | 无 | A |
| feature-design | 3 | 100% | 无 | A |
| feature-plan | 3 | 100% | 无 | A |
| feature-implement | 6 | 17% | 基线验证阻断 | D |
| diff-review | 3 | 67% | Codex 超时降级 | B |
| review-pr | 0* | - | 无遥测记录 | ? |
| commit-pr | 0* | - | 无遥测记录 | ? |
| implement-screen | 0 | - | 未被使用 | - |
| read-design | 0 | - | 未被使用 | - |
| verify-screen | 0 | - | 未被使用 | - |

> *review-pr 和 commit-pr 在报告中有大量使用记录（18 个会话），但遥测日志中无记录。可能是这两个 Skill 的遥测步骤未正确触发，需排查 Step 10 / Step 末的 record-outcome 调用是否生效。

### 4.3 摩擦类型与改进项映射

| 摩擦类型 | 频次 | 对应改进项 |
|----------|------|-----------|
| 方法错误 | 15 | 2.3 上下文检测 / 2.7 PR 审查优化 |
| 代码有 Bug | 10 | 2.2 Xcode 防护 / 2.1 基线容忍 |
| 误解需求 | 6 | 2.4 流水线衔接（阶段间上下文传递） |
| 改动过多 | 2 | 2.4 流水线衔接（红线传递） |
| API 错误 | 2 | 2.2 L3 验证层（版本号验证） |

---

## 五、结论

当前 ai-dev-workflow 的 Feature Pipeline 前三阶段（analyze → design → plan）已经相当成熟，成功率 100%。**核心瓶颈集中在 feature-implement 的验证门控过于严格**，导致 83% 的执行以 partial 结束。这不是 Skill 逻辑错误，而是验证策略未适配项目现实（预存基线错误）。

第二大改进点是 **Xcode 集成的系统性防护**——这是一个已知的、反复发生的、可通过分层防御完全消除的问题。

第三大改进点是 **上下文漂移检测**——这类错误单次代价高（需要撤销和重做），但通过简单的 Hook 即可预防。

这三项改进的总工作量约 2-3 小时，但预期可以将任务完全达成率从 72% 提升到 85%+。
