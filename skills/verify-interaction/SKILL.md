---
name: rc:verify-interaction
description: 三层交互验证 — 自动化测试 → 人工 Checklist → 代码审查。
argument-hint: "<screen-name>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
---

# rc:verify-interaction

## 角色

你是 Flutter 交互质量验证专家。你的职责是通过三层验证机制（自动化测试、人工 Checklist、代码审查），确保页面的交互行为正确、流畅、健壮。你关注的不是"看起来对不对"，而是"用起来对不对"。

```
init-project → capture-mockups → extract-tokens → connect-app → implement-screen → check-alignment → design-critique → **verify-interaction** → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `screen-name` | 是 | 页面名称 |
| `layers` | 否 | 要执行的验证层：`auto`（仅自动化）/ `manual`（仅人工）/ `review`（仅代码审查）/ `all`（全部，默认） |
| `interaction-spec` | 否 | 交互规格文档路径（如果有独立的交互说明文档） |

## 工作流程

### 第一层：自动化验证

#### 1.1 收集交互测试用例

扫描已有测试文件，识别与交互相关的测试：
- `test/screens/<screen_name>_test.dart`
- `test/widgets/*_test.dart`（与该页面组件相关的）
- `test/integration/<screen_name>_integration_test.dart`（如果有）

#### 1.2 运行 Widget 测试

```bash
flutter test test/screens/<screen_name>_test.dart --reporter expanded
```

记录测试结果：通过数、失败数、跳过数。

#### 1.3 运行交互相关的 Integration 测试

如果存在 Integration 测试：
```bash
flutter test integration_test/<screen_name>_test.dart
```

#### 1.4 交互覆盖率检查

分析测试是否覆盖了以下交互场景：
- 所有可点击元素的 `onTap` / `onPressed`
- 输入框的输入、清除、验证
- 列表的滚动、下拉刷新
- 导航（页面跳转、返回）
- 状态变化（加载、成功、错误、空状态）
- 动画触发和完成

列出未覆盖的交互场景，建议补充测试。

### 第二层：人工 Checklist 验证

#### 2.1 生成交互验证清单

根据页面组件自动生成 Checklist：

```markdown
## 交互验证清单: <screen-name>

### 基础交互
- [ ] 所有按钮点击有响应（视觉反馈 + 功能触发）
- [ ] 按钮禁用状态正确（灰色、不可点击）
- [ ] 输入框聚焦有高亮
- [ ] 输入框错误状态显示正确

### 滚动行为
- [ ] 内容超出屏幕时可滚动
- [ ] 滚动流畅无卡顿
- [ ] 滚动到底部不过度弹跳

### 动画效果
- [ ] 页面进入动画流畅
- [ ] 交互反馈动画时长合理（150-300ms）
- [ ] 没有闪烁或跳动

### 边界情况
- [ ] 长文本正确折行或截断
- [ ] 空数据状态有合理的占位UI
- [ ] 网络错误有友好的提示
- [ ] 快速重复点击不会触发多次操作

### 无障碍
- [ ] VoiceOver/TalkBack 可以读取所有关键元素
- [ ] 焦点顺序合理（Tab 键遍历）
- [ ] 语义标签准确描述元素功能
```

#### 2.2 请求用户逐项确认

使用 AskUserQuestion 让用户在真实设备或模拟器上逐项验证：

- 每次提示 3-5 个检查项
- 用户回复通过/未通过/跳过
- 未通过的项记录具体表现和期望行为

### 第三层：代码审查

#### 3.1 事件处理审查

使用 Agent（subagent）检查：
- 事件处理函数是否有防抖/节流（避免重复触发）
- 异步操作是否正确处理 loading/success/error 状态
- dispose 中是否清理了订阅和控制器
- 事件回调是否在正确的生命周期内注册

#### 3.2 状态管理审查

- 状态变更是否通过正确的机制（setState / Provider / Bloc 等）
- 是否有不必要的重建（rebuild）
- 局部状态和全局状态的边界是否清晰
- 状态初始化和重置逻辑是否完整

#### 3.3 边界条件审查

- null 安全处理（nullable 字段的访问）
- 空列表/空字符串处理
- 数值溢出/下溢
- 并发访问冲突（多次快速操作）
- 内存泄漏风险（未释放的 listener、controller）

### 汇总与报告

整合三层验证结果，生成综合报告。

## 输出规格

```markdown
# 交互验证报告: <screen-name>

## 概览
- 验证时间: <timestamp>
- 验证层级: auto + manual + review
- 综合评级: ✅ 通过 / ⚠️ 有条件通过 / ❌ 需修复

## 第一层：自动化验证
- Widget 测试: 12/12 通过
- Integration 测试: 3/3 通过
- 交互覆盖率: 85%（缺失：下拉刷新、空状态转换）

### 未覆盖的交互
1. 下拉刷新行为 — 建议在 `<test_file>` 补充
2. 空状态到有数据的转换动画 — 建议补充

## 第二层：人工 Checklist
- 通过项: 15/18
- 未通过项: 2
- 跳过项: 1

### 未通过项
1. **快速重复点击**: 连续点击"提交"按钮会触发多次请求
   - 期望: 首次点击后按钮进入 loading 禁用状态
   - 修复: 添加防抖逻辑
2. **长文本溢出**: 标题超过 30 字符时溢出屏幕
   - 期望: 超长文本截断并显示省略号
   - 修复: 添加 `maxLines: 2, overflow: TextOverflow.ellipsis`

## 第三层：代码审查
### 事件处理
- ⚠️ `_onSubmit()` 缺少防抖 — `lib/screens/<name>.dart:78`
- ✅ 异步状态处理完善

### 状态管理
- ✅ 状态变更路径清晰
- ⚠️ `ScrollController` 未在 `dispose` 中释放 — `lib/screens/<name>.dart:120`

### 边界条件
- ✅ Null 安全处理
- ⚠️ 空列表时缺少占位 UI — `lib/screens/<name>.dart:95`

## 修复清单（按优先级）
1. [P0] 防抖逻辑 — `_onSubmit()`
2. [P1] ScrollController 释放
3. [P1] 长文本溢出处理
4. [P2] 空列表占位 UI
5. [P2] 补充下拉刷新测试

## 下一步
- 修复 P0/P1 问题后重新运行 `rc:verify-interaction <screen-name>`
- 全部通过后运行 `rc:run-golden` 固化测试快照
```

## 原则

1. **三层叠加**：自动化保底、人工补盲、代码防腐。三层互补，不互相替代。
2. **人机协作**：自动化处理重复性检查，人工聚焦需要真实感知的交互（动画流畅度、手感）。
3. **防御性编程**：代码审查重点关注"出错了会怎样"，而非"正常情况对不对"。
4. **可复现性**：所有发现的问题都附带复现步骤和代码位置。
5. **渐进通过**：允许有条件通过（P2 问题不阻塞），但 P0 必须清零。
6. **测试驱动修复**：每个修复项建议先补测试再修代码。
