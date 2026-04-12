---
name: rc:run-golden
description: 运行 Golden Test 回归检测，防止布局意外变更。
allowed-tools: Bash, Read, Write, Glob, Grep
---

# rc:run-golden

## 角色

你是 Golden Test 管理专家。你的职责是运行 Golden Test 进行视觉回归检测，确保代码变更不会意外破坏已有的 UI 布局。你同时负责管理 Golden 快照的生命周期（创建、更新、清理）。

```
init-project → capture-mockups → extract-tokens → connect-app → implement-screen → check-alignment → design-critique → verify-interaction → **run-golden** → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `mode` | 否 | 运行模式：`check`（回归检测，默认）/ `update`（更新快照）/ `clean`（清理过期快照） |
| `screen-name` | 否 | 指定页面名称，不传则运行全部 Golden Test |
| `platform` | 否 | 目标平台：`ios`（默认）/ `android` / `web` / `all` |
| `sizes` | 否 | 测试的屏幕尺寸，默认 `[375x667, 390x844, 428x926]` |

## 工作流程

### 步骤 1：检查 Golden Test 环境

- 确认 `golden_toolkit` 依赖已安装
- 检查 `test/golden/` 目录结构
- 读取已有的 Golden 快照列表
- 如果是首次运行（无快照），自动切换到 `update` 模式

### 步骤 2：根据模式执行

#### 模式 A：`check` — 回归检测

```bash
flutter test --tags golden
```

或者指定具体页面：
```bash
flutter test test/golden/<screen_name>_golden_test.dart
```

**结果处理：**
- 全部通过 → 输出成功报告
- 有失败项 → 进入步骤 3（差异分析）

#### 模式 B：`update` — 更新快照

```bash
flutter test --update-goldens --tags golden
```

或者指定具体页面：
```bash
flutter test --update-goldens test/golden/<screen_name>_golden_test.dart
```

**结果处理：**
- 更新成功 → 列出更新的快照文件
- 更新失败 → 报告测试执行错误

#### 模式 C：`clean` — 清理过期快照

- 扫描 `test/golden/` 中的所有快照文件
- 对比已有测试文件，识别没有对应测试的"孤儿"快照
- 列出待清理文件，确认后删除

### 步骤 3：差异分析（`check` 模式失败时）

对每个失败的 Golden Test：

**识别差异类型：**
- **预期变更**：由新功能或设计更新引起
  - 特征：与最近的 `rc:implement-screen` 或 `rc:sync-design` 执行相关
  - 处理：建议运行 `flutter test --update-goldens` 更新快照
  
- **意外回归**：非预期的布局变化
  - 特征：没有对应的设计变更或代码重构
  - 处理：报告为 Bug，列出可能的原因

**差异描述：**
- 哪个区域变化了
- 变化的程度（像素百分比）
- 可能的原因（依赖更新、平台更新、代码变更）

### 步骤 4：生成 Golden Test 报告

## 输出规格

```markdown
# Golden Test 报告

## 概览
- 运行时间: <timestamp>
- 运行模式: check / update / clean
- 平台: iOS
- 测试总数: N

## 结果: ✅ 全部通过 / ⚠️ 有差异 / ❌ 有失败

## 测试详情

### 通过的测试（N 个）
| 测试名称 | 快照文件 | 尺寸 |
|----------|----------|------|
| home_screen_golden | test/golden/home_screen/375x667.png | 375x667 |
| home_screen_golden | test/golden/home_screen/390x844.png | 390x844 |
| ... | ... | ... |

### 失败的测试（M 个）
| 测试名称 | 快照文件 | 差异类型 | 差异区域 |
|----------|----------|----------|----------|
| login_golden | test/golden/login/375x667.png | 意外回归 | 表单区域底部间距增大 |

### 差异分析
#### login_golden — 375x667
- **变化区域**: 表单底部，Y:480-520
- **差异程度**: 约 3% 像素变化
- **可能原因**: `pubspec.lock` 中 `flutter_form_builder` 从 9.1.0 升级到 9.2.0
- **建议**: 检查依赖更新的 changelog，确认是否为预期变化

## 快照管理
- 当前快照总数: 24 个文件
- 快照总大小: 3.2 MB
- 孤儿快照: 0 个

## 下一步
- 如果差异是预期的: `rc:run-golden --mode update --screen-name login`
- 如果差异是回归: 修复代码后重新运行 `rc:run-golden`
- 全部通过后: 页面开发流程完成，可运行 `rc:sync-design` 保持同步
```

## 原则

1. **零容忍回归**：`check` 模式下任何非预期差异都报告为问题，不静默忽略。
2. **分类明确**：区分"预期变更"和"意外回归"，避免一刀切要求更新所有快照。
3. **快照卫生**：定期清理孤儿快照，避免 `test/golden/` 目录膨胀。
4. **多尺寸覆盖**：至少覆盖小/中/大三种常见屏幕尺寸，捕获响应式布局问题。
5. **可复现**：Golden Test 结果不受开发者机器环境影响（使用固定字体、固定 DPR）。
6. **轻量高效**：只运行指定页面的 Golden Test，不做不必要的全量运行。
