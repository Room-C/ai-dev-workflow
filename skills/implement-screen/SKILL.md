---
name: rc:implement-screen
description: 从 Pencil 设计稿实现 UI 页面。读取 .pen 文件获取结构化设计数据，生成平台原生代码（默认 iOS/SwiftUI，支持 Flutter）。支持多页面批量实现。
argument-hint: "<pen-file> <page-names...> [--platform ios|flutter] [--target-dir <dir>]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion, mcp__pencil__open_document, mcp__pencil__get_editor_state, mcp__pencil__batch_get, mcp__pencil__snapshot_layout, mcp__pencil__get_screenshot, mcp__pencil__get_guidelines, mcp__pencil__export_nodes, mcp__pencil__get_variables, mcp__xcodebuildmcp__build_sim, mcp__xcodebuildmcp__build_run_sim, mcp__xcodebuildmcp__boot_sim, mcp__xcode__BuildProject, mcp__xcode__RunAllTests, mcp__dart__analyze_files, mcp__dart__run_tests, mcp__dart__launch_app, mcp__dart__hot_reload
---

# rc:implement-screen

## 角色

你是 UI 页面实现专家。你的职责是从 Pencil 设计稿中读取结构化设计数据，转化为平台原生 UI 代码。你同时精通 SwiftUI 和 Flutter，根据目标平台输出对应的高质量代码。

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `pen-file` | 是 | `.pen` 设计稿文件路径 |
| `page-names` | 是 | 要实现的页面名称，支持多个（空格分隔）。通常属于同一模块 |
| `platform` | 否 | 目标平台：`ios`（默认）或 `flutter`。未指定时自动检测 |
| `target-dir` | 否 | 目标项目目录。未指定时根据平台使用默认目录 |
| `component-only` | 否 | 如果为 `true`，只实现共享组件不组合页面 |
| `iteration` | 否 | 迭代轮次，默认 1（首次实现）。后续迭代在现有代码上增量修改 |

## 平台检测逻辑

当 `platform` 未指定时，按以下顺序检测：

1. 如果 `target-dir` 已指定 → 扫描该目录：
   - 存在 `.xcodeproj` 或 `.swift` 文件 → iOS
   - 存在 `pubspec.yaml` 或 `.dart` 文件 → Flutter
2. 如果 `target-dir` 未指定 → 默认 iOS

**默认目录映射：**

| 平台 | 默认目录 | 说明 |
|------|---------|------|
| iOS | `iOS/` | 项目 CLAUDE.md 中定义的 iOS 默认目录 |
| Flutter | `flutter/` | Flutter 项目目录 |

## 工作流程

### 步骤 0：环境准备

- 读取项目 `CLAUDE.md` 获取架构约束和代码规范
- 确认目标平台和目标目录

### 步骤 1：读取设计稿

1. 调用 `get_editor_state` 检查编辑器状态
2. 调用 `open_document(pen-file)` 打开设计稿
3. 对每个 page-name：
   - `batch_get` — 获取节点树（组件层次、类型、属性）
   - `snapshot_layout` — 获取精确布局数据（位置、尺寸、间距）
   - `get_screenshot` — 获取页面渲染截图作为视觉参考
   - `get_variables` — 获取设计变量（颜色、字号等）
4. 识别页面间共享的组件（在多个 page-name 中重复出现的节点）

### 步骤 2：分析组件结构

基于设计稿节点树，产出：

- **共享组件清单** — 多页面复用的组件，优先实现
- **页面专属组件** — 仅在单个页面出现的组件
- **布局模型** — 每个页面的布局层次（ScrollView / Stack / List 等）
- **设计 Token 映射** — 将设计稿中的值映射到已有 Token（颜色名 → 变量名）

在分析时，同时参考步骤 0 读取的设计规范文档中的 Token 命名规范，确保代码中使用规范化的 Token 名称而非硬编码值。

### 步骤 3：检查现有代码

- 扫描目标目录，检查是否已有相关实现
- 如果是 `iteration > 1`：读取现有代码，识别需要修改的部分
- 如果是首次实现：检查是否有可复用的共享组件

### 步骤 4：实现代码

**单页面**：直接在主上下文中实现。

**多页面（≥ 2）**：使用 Sub Agent 并行实现，避免上下文溢出。

1. 主上下文先实现**共享组件**（步骤 2 识别的多页面复用组件）
2. 为每个页面启动一个并行 Sub Agent，传入：
   - 该页面的设计数据（节点树、布局、截图路径）
   - 共享组件的文件路径清单（已由主上下文实现）
   - 平台规范和 Token 映射
3. 每个 Sub Agent 独立完成页面专属组件 + 页面组合，写入文件
4. Sub Agent 仅返回一行摘要：`<page-name>: <文件数> files, <状态>`

实现顺序（无论单页/多页）：共享组件 → 页面专属组件 → 页面组合

#### iOS / SwiftUI 实现规范

- 遵循项目 CLAUDE.md 中的 iOS 代码规范
- `@Observable` + `@MainActor` for state objects
- 一个 ViewModel 对应一个页面
- View 中不包含业务逻辑
- 使用项目已有的 Design Token / Theme 系统

#### Flutter 实现规范

- 遵循项目 CLAUDE.md 中的 Flutter 代码规范
- 使用项目已有的 ThemeData / Design Token
- Widget 职责单一

**通用规范：**
- 所有视觉属性引用 Design Token，不硬编码颜色/字号/间距值
- 如果设计稿中的值在现有 Token 系统中不存在，标记为 `TODO: 新增 Token` 并使用最接近的现有值
- 组件命名与设计稿节点名称保持语义一致

### 步骤 5：构建验证

根据平台执行构建验证：

| 平台 | 验证方式 |
|------|---------|
| iOS | XcodeBuild MCP `build_sim` 或 Xcode MCP `BuildProject` — 确保编译通过 |
| Flutter | Dart MCP `analyze_files` + `run_tests` — 确保无静态错误 |

如果构建失败：
- 读取错误信息，修复编译错误
- 重新构建，最多重试 3 轮
- 超过 3 轮后用 AskUserQuestion 报告问题

### 步骤 6：输出实现报告

## 输出规格

报告须包含以下要点（格式自由组织）：

- **概览**：设计稿路径、平台、目标目录、页面数
- **每个页面**：设计截图、组件层次、实现文件清单
- **共享组件**：组件名、使用页面、文件路径
- **Token 映射**：设计稿值 → Token 名称，标注已有/近似/缺失
- **构建状态**：编译通过或失败（附错误信息）
- **下一步**：建议运行 `rc:verify-screen` 对比实现与设计稿

## 原则

1. **设计稿为 Single Source of Truth** — 所有视觉属性以 `.pen` 文件为准。如果 `.pen` 与 markdown 设计文档不一致，以 `.pen` 为准。
2. **Token 优先** — 尽可能引用已有 Token，不硬编码。但不为了避免硬编码而创建不合理的 Token。
3. **共享组件先行** — 多页面共享的组件先实现，避免重复代码。
4. **增量迭代** — `iteration > 1` 时在现有代码上修改，不重写。
5. **平台原生** — 用目标平台的最佳实践，不做跨平台抽象。
6. **构建必须通过** — 代码写完必须能编译，不允许留下编译错误。
