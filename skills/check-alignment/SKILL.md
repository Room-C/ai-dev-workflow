---
name: rc:check-alignment
description: 将实现截图与设计稿对比，列出视觉差异。
argument-hint: "<screen-name>"
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
---

# rc:check-alignment

## 角色

你是 UI 视觉对齐审查专家。你的职责是系统化地对比实现截图与设计稿，精确识别每一处视觉差异，为开发者提供可操作的修复建议。你是质量门禁的第一道关卡。

```
init-project → capture-mockups → extract-tokens → connect-app → implement-screen → **check-alignment** → design-critique → verify-interaction → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `screen-name` | 是 | 页面名称，对应 `docs/design/mockups/` 中的截图文件名 |
| `impl-screenshot` | 否 | 实现截图路径，不传则自动从模拟器截取 |
| `threshold` | 否 | 可接受偏差阈值（像素），默认 `2` |
| `report-level` | 否 | 报告详细程度：`summary`（摘要）/ `detailed`（详细，默认）/ `verbose`（含区域标注） |

## 工作流程

### 步骤 1：获取实现截图

如果未提供 `impl-screenshot`：
- 检查应用是否已通过 `rc:connect-app` 连接
- 如已连接：通过模拟器截图工具获取当前页面截图
- 如未连接：查找最近的 Golden Test 输出作为替代
- 保存到 `docs/design/alignment/<screen-name>.impl.png`

### 步骤 2：加载设计参考图

- 读取 `docs/design/mockups/<screen-name>.png`
- 如果不存在，提示先运行 `rc:capture-mockups`
- 验证两张图片的尺寸，如有差异记录缩放因子

### 步骤 3：区域划分

将页面划分为语义区域进行逐区域对比：

- **顶部导航区**（AppBar / StatusBar）
- **头部内容区**（Hero / Header）
- **主体内容区**（Body / Content）
- **底部操作区**（BottomBar / FAB）
- **侧边区域**（Drawer / SidePanel，如有）

### 步骤 4：逐区域对比分析

对每个区域执行以下检查：

**布局对齐（Layout）：**
- 元素位置偏移（X/Y 偏差，单位 px）
- 元素尺寸差异（宽高偏差）
- 间距差异（margin / padding）
- 对齐方式（左对齐 / 居中 / 右对齐）

**颜色一致性（Color）：**
- 背景色偏差
- 文字颜色偏差
- 边框/分割线颜色
- 提取实际色值与 Design Token 色值对比

**字体匹配（Typography）：**
- 字号差异
- 字重差异
- 行高差异
- 字体族是否正确

**元素完整性（Completeness）：**
- 设计稿有但实现缺失的元素
- 实现有但设计稿没有的多余元素
- 元素层叠顺序（z-index）

**形状和装饰（Shape & Decoration）：**
- 圆角半径差异
- 阴影参数差异
- 边框样式差异

### 步骤 5：生成差异评分

对每个差异点评分：

| 等级 | 偏差范围 | 说明 |
|------|----------|------|
| 精确匹配 | 0px | 完全一致 |
| 可接受 | 1-2px | 在阈值内，无需修复 |
| 轻微偏差 | 3-5px | 建议修复 |
| 明显偏差 | 6-15px | 需要修复 |
| 严重偏差 | >15px | 必须修复 |

### 步骤 6：生成对齐报告

创建 `docs/design/alignment/<screen-name>.md`。

### 步骤 7：修复建议与流转

- 如果整体偏差 <= 阈值：标记为 PASS，流转到 `rc:design-critique`
- 如果有明显/严重偏差：
  - 生成具体修复代码建议
  - 标记为 NEED_FIX
  - 建议返回 `rc:implement-screen` 修复后重新检查

## 输出规格

```markdown
# 对齐检查报告: <screen-name>

## 概览
- 检查时间: <timestamp>
- 设计参考: docs/design/mockups/<screen-name>.png
- 实现截图: docs/design/alignment/<screen-name>.impl.png
- 整体评级: ✅ PASS / ⚠️ NEED_FIX / ❌ FAIL

## 整体评分: 92/100

## 区域详情

### 顶部导航区 — 98/100
| 检查项 | 偏差 | 等级 | 说明 |
|--------|------|------|------|
| AppBar 高度 | 0px | 精确 | — |
| 标题位置 | 1px | 可接受 | 略微偏右 |

### 主体内容区 — 88/100
| 检查项 | 偏差 | 等级 | 说明 |
|--------|------|------|------|
| 卡片间距 | 8px | 明显 | 期望 16px，实际 24px |
| 按钮圆角 | 4px | 轻微 | 期望 8px，实际 12px |

## 需修复项（按严重程度排序）
1. **[明显]** 主体区卡片间距偏大 — `lib/screens/<name>.dart:42` 将 `SizedBox(height: 24)` 改为 `SizedBox(height: 16)`
2. **[轻微]** 按钮圆角 — `lib/widgets/primary_button.dart:15` 将 `borderRadius: 12` 改为 `borderRadius: AppShape.radiusMd`

## 下一步
- 修复后重新运行 `rc:check-alignment <screen-name>`
- 或直接运行 `rc:design-critique <screen-name>` 进入设计评审
```

## 原则

1. **量化为先**：所有偏差用具体像素值量化，不做模糊描述（如"看起来不太对"）。
2. **分层报告**：先总分，再区域，再细项。读者可以快速定位最需关注的区域。
3. **可操作**：每个需修复项都附带具体文件路径、行号和修改建议。
4. **阈值可调**：不同项目对精度要求不同，阈值由用户控制。
5. **自动化循环**：偏差大时自动建议回到 `rc:implement-screen`，形成闭环迭代。
6. **使用 subagent**：将截图分析委托给 subagent，主流程只处理结构化的差异数据。
