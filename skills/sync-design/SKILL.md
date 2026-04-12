---
name: rc:sync-design
description: 设计稿更新后重新捕获截图、对比差异、更新代码。
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
---

# rc:sync-design

## 角色

你是设计-代码同步协调者。你的职责是在设计稿发生变更后，协调整条流水线重新同步：截取新截图、识别变更、评估影响、更新代码、刷新测试快照。你是设计迭代的"变更管理器"。

```
init-project → capture-mockups → extract-tokens → connect-app → implement-screen → check-alignment → design-critique → verify-interaction → run-golden → **sync-design**
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `module` | 否 | 模块名称。指定后只同步该模块的设计稿和代码。不指定则同步全部模块 |
| `scope` | 否 | 同步范围：`all`（全部页面，默认）/ `<screen-name>`（指定页面） |
| `flow-changed` | 否 | 如果为 `true`，表示交互流程有变（新增/删除页面、交互路径变化），需要重新录制采集脚本。默认 `false`（仅 UI 内容变化） |
| `dry-run` | 否 | 如果为 `true`，只分析不修改代码（默认 `false`） |
| `auto-approve` | 否 | 如果为 `true`，跳过人工确认直接更新（默认 `false`，建议保持 false） |

## 工作流程

### 步骤 1：判断变更类型并重新截取

> 如果指定了 `module`，以下所有操作都限定在该模块范围内。
> 脚本路径：`scripts/capture-<module>.mjs`（无 module 时为 `scripts/capture-mockups.mjs`）。

设计稿更新分为两种情况，采集策略不同：

#### 情况 A：UI 内容变但交互流程不变

> 例如：颜色修改、字号调整、间距变化、文案替换、图标更换——页面和交互路径没有增减。

- 检测条件：对应的录制脚本存在，且 `flow-changed` 未指定
- 操作：调用 `rc:capture-mockups <module>`（自动走 Mode A 脚本回放），重跑现有脚本即可
- 新截图覆盖当前版本，旧截图保留为 `.prev.png`

#### 情况 B：交互流程也变了

> 例如：新增页面、删除页面、按钮位置移动导致点击路径变化、新增弹窗/Tab/抽屉等交互状态。

- 检测条件：以下任一成立
  - 用户指定了 `flow-changed` 参数
  - 用户明确告知交互流程有变
  - 脚本回放失败（元素找不到、点击超时、导航异常）
- 操作：调用 `rc:capture-mockups <module> --mode record`，触发重新录制流程

#### 情况 C：无录制脚本

- 检测条件：对应的录制脚本不存在
- 操作：调用 `rc:capture-mockups <module>`（自动走 Mode C 引导录制）

### 步骤 2：对比新旧截图

对每个页面，对比新截图和旧截图（`.prev.png`）：

**变更识别：**
- 无变化：新旧截图完全一致（像素级对比）
- 微调：小范围变化（间距、颜色微调）
- 重构：大范围变化（布局调整、组件重新设计）
- 新增：设计稿中出现了新页面（仅情况 B 可能出现）
- 删除：设计稿中移除了页面（仅情况 B 可能出现）

**生成变更摘要：**

```markdown
## 设计稿变更摘要

| 页面 | 变更类型 | 变更描述 | 影响评估 |
|------|----------|----------|----------|
| home | 微调 | 标题字号增大、卡片间距减小 | 低 |
| profile | 重构 | 整体布局从列表改为卡片网格 | 高 |
| settings | 无变化 | — | — |
| onboarding | 新增 | 新增引导页 | 中（需全新实现） |

> 采集方式: 脚本回放 / 重新录制
```

### 步骤 3：评估代码影响范围

对每个有变更的页面，分析受影响的代码：

- 使用 Grep 搜索页面相关的所有代码文件
- 识别需要修改的组件和样式
- 评估修改工作量（文件数、预估行数）
- 检查是否涉及共享组件（修改可能影响其他页面）

### 步骤 4：用户确认

如果 `auto-approve` 为 `false`：

使用 AskUserQuestion 逐页面确认：

```
页面 "profile" 发生了重构级变更：
- 布局从列表改为卡片网格
- 预计影响 3 个文件，约 80 行代码
- 共享组件 ContentCard 需要修改（还被 home 页面使用）

是否更新此页面的实现？[Y/n/skip]
```

用户可以：
- 确认更新
- 跳过此页面
- 全部跳过（退出同步）

### 步骤 5：更新 Design Tokens

- 调用 `rc:extract-tokens --merge-mode diff-only` 检查 Token 变化
- 如果 Token 有变化：
  - 展示 Token diff
  - 确认后调用 `rc:extract-tokens --merge-mode merge` 更新
  - Token 变化可能影响所有页面，需要额外提醒

### 步骤 6：更新页面实现

对每个确认更新的页面：

- 调用 `rc:implement-screen <screen-name> --iteration <n+1>` 更新实现
- 根据变更类型采取不同策略：
  - **微调**：在现有代码上局部修改
  - **重构**：可能需要重写部分组件
  - **新增**：全新实现

### 步骤 7：验证更新结果

对每个更新的页面：

- 调用 `rc:check-alignment <screen-name>` 验证对齐
- 如果偏差超过阈值，迭代修复

### 步骤 8：更新 Golden 快照

- 调用 `rc:run-golden --mode update` 更新所有受影响页面的 Golden 快照
- 验证更新后的快照正确

### 步骤 9：生成同步报告

## 输出规格

```markdown
# 设计同步报告

## 概览
- 同步时间: <timestamp>
- 同步范围: all / <specific-screens>
- 设计稿变更页面数: N
- 代码更新页面数: M

## 变更总结

### 已更新的页面
| 页面 | 变更类型 | 修改文件数 | 修改行数 | 对齐度 |
|------|----------|-----------|----------|--------|
| home | 微调 | 2 | 15 | 97% |
| profile | 重构 | 5 | 120 | 93% |
| onboarding | 新增 | 3 | 180 | 95% |

### 跳过的页面
| 页面 | 变更类型 | 跳过原因 |
|------|----------|----------|
| dashboard | 微调 | 用户选择跳过 |

### 无变化的页面
- settings
- about
- login

## Design Token 变更
| Token | 旧值 | 新值 | 影响范围 |
|-------|------|------|----------|
| color.primary | #2563EB | #3B82F6 | 全局 |
| spacing.md | 16px | 20px | home, profile, login |

## Golden 快照更新
- 更新文件数: 9
- 新增文件数: 3（onboarding）
- 删除文件数: 0

## 注意事项
- ⚠️ 共享组件 `ContentCard` 已修改，请检查未同步的页面是否受影响
- ⚠️ Token `spacing.md` 变更影响 3 个页面，其中 `login` 未在本次同步中更新

## 下一步
1. 对跳过的页面重新运行 `rc:sync-design --scope <name>`
2. 对所有更新的页面运行 `rc:design-critique` 做质量评审
3. 运行 `rc:verify-interaction` 验证交互是否受影响
4. 提交代码并推送
```

## 原则

1. **变更可控**：每个变更都需要明确确认，不做静默大规模修改。`dry-run` 模式让用户先看到影响再决定。
2. **增量同步**：只更新有变化的页面，不重新生成没有变化的内容。
3. **影响追踪**：共享组件的变更需要追踪所有受影响的页面，即使本次只更新了部分。
4. **原子操作**：每个页面的更新是独立的，单个页面更新失败不影响其他页面。
5. **版本对比**：保留旧截图（`.prev.png`）支持 before/after 对比，便于回溯。
6. **协调者角色**：sync-design 自身不做实现工作，而是协调调用其他 skill 完成各环节。
