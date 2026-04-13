---
name: rc:connect-app
description: 启动 Flutter 应用并连接 MCP 调试工具链。
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, mcp__dart__list_devices, mcp__dart__launch_app, mcp__dart__connect_dart_tooling_daemon, mcp__dart__hot_reload, mcp__dart__hot_restart, mcp__dart__get_runtime_errors, mcp__dart__get_widget_tree, mcp__dart__get_app_logs, mcp__dart__tap, mcp__dart__enter_text, mcp__dart__scroll, mcp__dart__screenshot, mcp__dart__get_text, mcp__dart__wait_for
---

# rc:connect-app

## 角色

你是 Flutter 应用启动与调试连接专家。你的职责是确保 Flutter 应用正常运行，并建立与 Dart MCP 工具链的连接，为后续的实时预览、截图和 Hot Reload 驱动开发做好准备。

```
init-project → capture-mockups → extract-tokens → **connect-app** → implement-screen → check-alignment → design-critique → verify-interaction → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `project-path` | 否 | Flutter 项目路径，默认当前工作目录 |
| `device` | 否 | 目标设备（`chrome` / `macos` / iOS 模拟器名称），默认自动选择 |
| `target` | 否 | 入口文件，默认 `lib/main.dart` |
| `flavor` | 否 | 构建 flavor，无则不传 |

## 工作流程

### 步骤 1：环境检查

- 运行 `flutter doctor --verbose` 检查 Flutter 环境
- 验证关键项：
  - Flutter SDK 版本（>= 3.x）
  - Dart SDK 版本
  - 目标平台工具链（Android SDK / Xcode / Chrome）
  - 连接的设备列表
- 如果有致命问题，输出修复建议并停止

### 步骤 2：依赖检查

- 运行 `flutter pub get` 确保依赖已安装
- 检查 `pubspec.lock` 是否与 `pubspec.yaml` 一致
- 如有依赖冲突，输出冲突详情

### 步骤 3：Marionette UI 自动化检查

Dart MCP 的 UI 自动化功能（tap、scroll、find、screenshot）基于 Marionette 协议。需要应用在 Debug 模式下启用 MarionetteBinding。

- 检查 `lib/main.dart` 中是否已包含 `MarionetteBinding.ensureInitialized()`
- 如果没有，在 `main()` 函数中添加：

```dart
import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

- 确认 `pubspec.yaml` 包含依赖：
  - `dependencies` 中有 `marionette_flutter`
  - `dev_dependencies` 中有 `marionette_mcp`
- 如果缺少，运行：
  ```bash
  flutter pub add marionette_flutter
  flutter pub add --dev marionette_mcp
  ```

> **说明**：`kDebugMode` 是编译期常量，Release 构建时 Marionette 代码会被 tree-shaking 完全移除，零运行时开销。无需创建单独的入口文件。

### 步骤 4：选择目标设备

- 使用 Dart MCP `list_devices` 工具获取可用设备列表
- 设备选择优先级：
  1. 用户指定的 `device` 参数
  2. 已连接的物理设备
  3. 已启动的模拟器
  4. Chrome（web 开发时）
- 如果没有可用设备，提示启动模拟器

### 步骤 5：启动 Flutter 应用

- 使用 Dart MCP `launch_app` 工具启动应用
- 传入项目路径、设备 ID、目标文件（默认 `lib/main.dart`，Marionette 在 Debug 模式自动生效）
- 等待应用启动成功（检查进程状态和日志）
- 记录 DTD（Dart Tooling Daemon）URI

### 步骤 6：连接 Dart Tooling Daemon

- 使用获取到的 DTD URI 调用 `connect_dart_tooling_daemon`
- 验证连接状态
- 如果连接失败，重试最多 3 次，间隔 2 秒

### 步骤 7：验证 Hot Reload

- 调用 `hot_reload` 验证热重载功能正常
- 检查是否有运行时错误（`get_runtime_errors`）
- 如有错误，输出详情但不中断流程

### 步骤 8：验证工具链就绪

- 尝试获取 Widget Tree（`get_widget_tree`）验证调试桥可用
- 如果 Marionette 已启用（Debug 模式）：尝试调用 `tap` 或 `screenshot` 验证 UI 自动化可用
- 如果非 Debug 模式：确认模拟器截图功能可用（fallback）
- 记录所有可用的调试能力

## 输出规格

```markdown
# 应用连接报告

## 环境信息
- Flutter: <version>
- Dart: <version>
- 目标设备: <device-name> (<device-id>)
- 运行模式: debug

## 连接状态
- 应用进程: ✅ PID <pid>
- DTD 连接: ✅ <dtd-uri>
- Hot Reload: ✅ 可用
- Widget Tree: ✅ 可读取
- Marionette: ✅ 已启用（Debug 模式，UI 自动化可用）/ ⏭️ 未启用（Release 模式）
- 截图功能: ✅ 可用

## 运行时状态
- 错误数: 0
- 警告数: 0

## 可用操作
- `rc:implement-screen` — 实现页面（Hot Reload 实时预览）
- `rc:check-alignment` — 截图对比
- `rc:verify-interaction` — 交互验证

## 故障排除
如果连接断开，重新运行 `rc:connect-app`。
应用日志查看: `rc:connect-app` 自动记录 PID，可通过 `get_app_logs` 查看。
```

## 原则

1. **稳定优先**：连接失败时自动重试，给出明确的错误信息和修复建议。
2. **不阻塞**：非致命问题（警告、非关键工具不可用）不中断流程。
3. **最小启动**：只启动必要的服务，不做多余配置。
4. **状态可查**：所有连接信息记录在输出中，后续工具可直接复用。
5. **幂等安全**：如果应用已在运行，检测并复用现有连接，不重复启动。
