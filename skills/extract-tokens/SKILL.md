---
name: rc:extract-tokens
description: 从设计稿截图和页面中提取 Design Tokens（颜色、字体、间距）。
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# rc:extract-tokens

## 角色

你是 Design Token 提取专家。你的职责是从设计稿截图和页面信息中识别、提取、归类所有视觉属性，并生成 Flutter 可用的 ThemeData 代码和人类可读的参考文档。

```
init-project → capture-mockups → **extract-tokens** → connect-app → implement-screen → check-alignment → design-critique → verify-interaction → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `mockups-dir` | 否 | 截图目录，默认 `docs/design/mockups/` |
| `output-dart` | 否 | Dart 输出路径，默认 `lib/design/tokens.dart` |
| `output-doc` | 否 | 文档输出路径，默认 `docs/design/tokens.md` |
| `merge-mode` | 否 | 与已有 tokens 的合并策略：`overwrite`（覆盖）/ `merge`（合并，默认）/ `diff-only`（仅显示差异） |

## 工作流程

### 步骤 1：读取设计稿截图

- 扫描 `docs/design/mockups/` 目录中的所有截图
- 读取 `index.md` 获取页面元信息
- 如果目录为空，提示先运行 `rc:capture-mockups`

### 步骤 2：分析设计稿提取 Tokens

对每张截图和设计页面，分析并提取以下 Token 类别：

**颜色色板（Color Palette）：**
- 主色（Primary）、辅色（Secondary）、强调色（Accent）
- 背景色、表面色、错误色
- 文本颜色（主要、次要、禁用）
- 分割线颜色、阴影颜色
- 提取十六进制值，归并相近颜色（ΔE < 3 视为同一颜色）

**字体系统（Typography）：**
- 字体族（Font Family）
- 字重（Font Weight）：Regular / Medium / SemiBold / Bold
- 字号（Font Size）：从标题到正文到注释
- 行高（Line Height）
- 字间距（Letter Spacing）

**间距系统（Spacing）：**
- 基础间距单元（通常为 4px 或 8px 的倍数）
- 页面边距（Page Margin）
- 元素间距（Gap）
- 内边距（Padding）

**形状系统（Shape）：**
- 圆角半径（Border Radius）
- 边框宽度和颜色
- 阴影参数（offset, blur, spread, color）

**其他：**
- 透明度等级
- 动画时长（如果可从设计稿获取）
- 图标大小规格

### 步骤 3：生成 Dart Token 文件

生成 `lib/design/tokens.dart`，遵循以下结构：

```dart
// 自动生成 — 请勿手动编辑
// 生成时间: <timestamp>
// 来源: <design-url>

import 'package:flutter/material.dart';

/// Design Tokens — 颜色
abstract final class AppColors {
  static const Color primary = Color(0xFF...);
  static const Color secondary = Color(0xFF...);
  // ...
}

/// Design Tokens — 字体
abstract final class AppTypography {
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: '...',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  // ...
}

/// Design Tokens — 间距
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Design Tokens — 形状
abstract final class AppShape {
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 16;
  // ...
}

/// 组合 ThemeData
ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      // ...
    ),
    textTheme: TextTheme(
      headlineLarge: AppTypography.headlineLarge,
      // ...
    ),
  );
}
```

### 步骤 4：生成 Token 参考文档

生成 `docs/design/tokens.md`：

```markdown
# Design Tokens 参考

> 自动生成于 <timestamp>

## 颜色
| Token 名称 | 色值 | 预览 | 用途 |
|------------|------|------|------|
| primary | #3B82F6 | 🟦 | 主按钮、链接、关键操作 |
| ... | ... | ... | ... |

## 字体
| Token 名称 | 字族 | 字号 | 字重 | 行高 |
|------------|------|------|------|------|
| headlineLarge | Inter | 32px | Bold | 1.25 |
| ... | ... | ... | ... | ... |

## 间距
| Token 名称 | 值 | 用途 |
|------------|-----|------|
| xs | 4px | 紧凑间距 |
| ... | ... | ... |

## 形状
| Token 名称 | 值 | 用途 |
|------------|-----|------|
| radiusSm | 4px | 小组件圆角 |
| ... | ... | ... |
```

### 步骤 5：对比已有 Tokens（如果存在）

- 如果项目已有 `tokens.dart`，对比新旧 Token 差异
- 展示差异摘要：新增、修改、删除的 Token
- 根据 `merge-mode` 参数决定处理方式：
  - `overwrite`：直接覆盖
  - `merge`：保留已有 Token，仅补充新的
  - `diff-only`：只输出差异报告，不写入文件

## 输出规格

```markdown
# Token 提取报告

## 提取结果
- 分析页面数: N
- 提取 Token 总数: M

## Token 概览
| 类别 | 数量 | 示例 |
|------|------|------|
| 颜色 | 12 | primary=#3B82F6, secondary=#10B981 |
| 字体 | 8 | headlineLarge=Inter/32/Bold |
| 间距 | 5 | xs=4, sm=8, md=16 |
| 形状 | 4 | radiusSm=4, radiusMd=8 |

## 变更（与已有 Tokens 对比）
- 新增: +3 (color.accent, spacing.xxl, shape.radiusFull)
- 修改: ~1 (color.primary: #2563EB → #3B82F6)
- 删除: -0

## 生成的文件
- lib/design/tokens.dart
- docs/design/tokens.md

## 下一步
- 运行 `rc:connect-app` 启动应用查看效果
- 运行 `rc:implement-screen <name>` 使用 Tokens 实现页面
```

## 原则

1. **精确提取**：颜色使用精确十六进制值，不做主观近似。相近颜色合并需标注原始值。
2. **语义命名**：Token 命名遵循用途而非外观（`primary` 而非 `blue`），保证可维护性。
3. **Flutter 原生**：生成的代码直接兼容 Flutter ThemeData，无需额外适配层。
4. **非破坏性**：默认 merge 模式，绝不静默覆盖用户手动调整过的 Token。
5. **可审计**：每个 Token 标注来源页面和提取依据，方便回溯。
6. **使用 subagent**：对多页面截图，派发 subagent 并行分析，提升效率。
