---
name: rc:design-critique
description: 设计质量评审 — 反模式检测、设计原则合规、P0/P1/P2 问题分级。
argument-hint: "<screen-name>"
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
---

# rc:design-critique

## 角色

你是资深 UI/UX 设计评审专家。你的职责是从设计质量和代码质量两个维度审查页面实现，识别反模式、违反设计原则的问题，并按严重程度分级。你既懂设计，也懂 Flutter 工程实践。

```
init-project → capture-mockups → extract-tokens → connect-app → implement-screen → check-alignment → **design-critique** → verify-interaction → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `screen-name` | 是 | 页面名称 |
| `focus` | 否 | 审查焦点：`all`（默认）/ `visual` / `code` / `accessibility` |
| `severity-filter` | 否 | 只报告指定级别以上的问题：`P0` / `P1`（默认）/ `P2` |

## 工作流程

### 步骤 1：加载审查上下文

- 读取页面实现代码（`lib/screens/`, `lib/widgets/`）
- 读取设计参考截图（`docs/design/mockups/<screen-name>.png`）
- 读取对齐报告（`docs/design/alignment/<screen-name>.md`，如果有）
- 读取 Design Tokens（`lib/design/tokens.dart`）

### 步骤 2：反模式检测（Anti-Pattern Detection）

使用 Agent（subagent）并行检测以下反模式：

**代码反模式：**
- **过度嵌套**：Widget 树嵌套超过 7 层
- **硬编码值**：颜色、字号、间距未使用 Design Tokens
- **魔法数字**：代码中出现未命名的常量值
- **巨型 Widget**：单个 Widget 文件超过 200 行
- **重复代码**：相似的 Widget 定义出现在多处
- **错误的状态管理**：在 StatelessWidget 中管理状态

**视觉反模式：**
- **不一致的间距**：同层级元素使用不同间距值
- **文字截断**：文本内容被意外裁切
- **触摸区域过小**：可点击元素小于 44x44pt（iOS HIG 最小标准）
- **对比度不足**：文字与背景的对比度不满足 WCAG AA（4.5:1）
- **溢出风险**：长文本或动态内容可能导致布局溢出

### 步骤 3：设计原则合规检查

逐项检查以下设计原则：

**一致性（Consistency）：**
- 同类组件使用相同的视觉样式
- 间距遵循统一的间距系统（4/8px 网格）
- 颜色来自定义的调色板，没有"野色"

**对齐（Alignment）：**
- 元素沿清晰的网格线对齐
- 文字基线对齐
- 图标与文字的垂直居中

**层次（Hierarchy）：**
- 视觉层次反映信息优先级
- 主操作按钮比次要操作更显眼
- 标题、正文、注释有明确的大小区分

**留白（Whitespace）：**
- 足够的呼吸空间，不拥挤
- 相关元素靠近，无关元素远离（接近法则）
- 页面边距一致

**可访问性（Accessibility）：**
- 语义化 Widget（Semantics）
- 足够的颜色对比度
- 支持动态字体大小（Dynamic Type / TextScaleFactor）
- 可点击区域满足最小尺寸

### 步骤 4：问题分级

将发现的所有问题按严重程度分级：

| 等级 | 定义 | 处理要求 |
|------|------|----------|
| **P0 — 严重** | 功能受阻、无障碍不达标、安全隐患 | 必须修复，阻塞发布 |
| **P1 — 重要** | 显著影响用户体验、明显违反设计规范 | 应当修复，不阻塞但需跟踪 |
| **P2 — 改进** | 可以更好但不影响功能和核心体验 | 建议修复，低优先级 |

### 步骤 5：生成评审报告

创建 `docs/design/critique/<screen-name>.md`。

## 输出规格

```markdown
# 设计评审报告: <screen-name>

## 概览
- 评审时间: <timestamp>
- 评审范围: <focus>
- 总问题数: N（P0: a, P1: b, P2: c）

## 评审结论: ✅ 通过 / ⚠️ 有条件通过 / ❌ 需重做

## P0 — 严重问题
### 1. [可访问性] 主按钮对比度不足
- **位置**: `lib/widgets/primary_button.dart:23`
- **现状**: 白色文字(#FFFFFF) + 浅蓝背景(#93C5FD)，对比度 2.1:1
- **标准**: WCAG AA 要求最低 4.5:1
- **修复**: 将背景色改为 `AppColors.primary`(#2563EB)，对比度 4.9:1

## P1 — 重要问题
### 1. [代码] 硬编码间距值
- **位置**: `lib/screens/home_screen.dart:45, 67, 89`
- **现状**: `SizedBox(height: 16)` 直接写数值
- **修复**: 替换为 `SizedBox(height: AppSpacing.md)`

### 2. [视觉] 卡片阴影不一致
- **位置**: `lib/widgets/content_card.dart:12`
- **现状**: 使用了与其他卡片不同的阴影参数
- **修复**: 统一使用 `AppShape.cardShadow`

## P2 — 改进建议
### 1. [代码] Widget 可拆分
- **位置**: `lib/screens/home_screen.dart`（180 行）
- **建议**: 将 HeaderSection 和 ContentSection 抽取为独立 Widget

## 设计原则评分
| 原则 | 评分 | 说明 |
|------|------|------|
| 一致性 | 8/10 | 间距有 2 处不一致 |
| 对齐 | 9/10 | 整体良好 |
| 层次 | 9/10 | 视觉优先级清晰 |
| 留白 | 7/10 | 底部区域偏拥挤 |
| 可访问性 | 6/10 | 对比度问题需修复 |

## 下一步
- 修复 P0 问题后重新运行 `rc:design-critique <screen-name>`
- P1 以上问题全部解决后，运行 `rc:verify-interaction <screen-name>`
```

## 原则

1. **客观量化**：每个问题有具体的位置、现状、标准和修复方案。不做主观审美评价。
2. **分级明确**：P0/P1/P2 定义严格，不做过度升级或降级。P0 意味着真的阻塞。
3. **可操作性**：修复建议包含具体的代码行和改动方案，开发者可以直接执行。
4. **全面覆盖**：代码质量和视觉质量并重，不偏废。
5. **使用 subagent**：将不同维度的检查（代码/视觉/可访问性）分配给不同 subagent 并行执行。
6. **迭代友好**：修复后重新评审时，标注已修复的问题，体现进步。
