---
name: rc:implement-screen
description: 实现单个页面 — TDD 驱动，从组件到页面，截图验证 + Golden 测试。
argument-hint: "<screen-name>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
---

# rc:implement-screen

## 角色

你是 Flutter 页面实现专家。你的职责是基于设计稿，采用 TDD 方式从原子组件到完整页面逐步构建 UI，通过截图验证实现与设计的一致性，并生成 Golden Test 快照防止回归。

```
init-project → capture-mockups → extract-tokens → connect-app → **implement-screen** → check-alignment → design-critique → verify-interaction → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `screen-name` | 是 | 页面名称，与 `docs/design/mockups/` 中的截图文件名对应 |
| `component-only` | 否 | 如果为 `true`，只实现组件不组合页面 |
| `skip-golden` | 否 | 跳过 Golden Test 生成（调试时使用） |
| `iteration` | 否 | 迭代轮次，默认 1（首次实现） |

## 工作流程

### 步骤 1：加载设计参考

- 读取 `docs/design/mockups/<screen-name>.png`（或同名文件）作为视觉参考
- 读取 `docs/design/mockups/index.md` 获取页面元信息
- 读取 `lib/design/tokens.dart` 获取 Design Tokens
- 如果参考文件缺失，提示先运行 `rc:capture-mockups`

### 步骤 2：分析设计稿结构

使用 Agent（subagent）分析设计截图：

- 识别页面组件层次结构
- 列出所有原子组件（按钮、输入框、图标、卡片等）
- 识别布局模式（Column / Row / Stack / Grid）
- 标注关键尺寸和间距
- 输出组件清单和布局树

### 步骤 3：TDD — 编写测试骨架

为每个需要实现的组件和页面创建测试文件：

```dart
// test/screens/<screen_name>_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

void main() {
  group('<ScreenName> Screen', () {
    testWidgets('renders correctly', (tester) async {
      // TODO: 实现后补充
    });

    testGoldens('<screen_name> golden', (tester) async {
      // Golden Test 骨架
    });
  });
}
```

### 步骤 4：实现原子组件

按从小到大的顺序实现组件：

1. **原子组件**（按钮、输入框、标签等）
   - 每个组件一个文件：`lib/widgets/<component_name>.dart`
   - 使用 Design Tokens，不硬编码任何视觉属性
   - 每实现一个组件运行一次对应测试

2. **组合组件**（卡片、列表项、表单区域等）
   - 组合原子组件
   - 处理组件间的间距和布局

3. **页面组件**
   - 组合所有子组件
   - 处理页面级布局（Scaffold, AppBar, SafeArea 等）
   - 处理滚动行为

每个组件实现后：
- 运行 Widget 测试验证
- 如果应用已连接（`rc:connect-app`），触发 Hot Reload 实时预览

### 步骤 5：截图验证

- 获取当前实现的截图
- 与设计稿参考图对比（调用 `rc:check-alignment` 的核心逻辑）
- 如果偏差明显：
  - 列出差异点
  - 自动调整并重试（最多 3 轮）
  - 超过 3 轮后使用 AskUserQuestion 征求用户意见

### 步骤 6：生成 Golden Test

- 为页面生成 Golden Test 快照
- 存储路径：`test/golden/<screen_name>/`
- 包含多个尺寸变体：
  - 默认尺寸（设计稿尺寸）
  - 小屏设备（375x667）
  - 大屏设备（428x926）

### 步骤 7：运行全部测试

- 运行 `flutter test test/screens/<screen_name>_test.dart`
- 确保所有测试通过
- 如有失败，修复后重新运行

## 输出规格

```markdown
# 页面实现报告: <screen-name>

## 设计参考
- 设计稿: docs/design/mockups/<screen-name>.png
- Tokens: lib/design/tokens.dart

## 实现文件
| 文件 | 类型 | 行数 |
|------|------|------|
| lib/screens/<name>_screen.dart | 页面 | 120 |
| lib/widgets/<component>.dart | 组件 | 45 |
| ... | ... | ... |

## 测试文件
| 文件 | 测试数 | 状态 |
|------|--------|------|
| test/screens/<name>_test.dart | 5 | ✅ 全部通过 |
| test/golden/<name>/ | 3 snapshots | ✅ 已生成 |

## 组件层次
```
<ScreenName>Screen
├── AppBar (title: "...")
├── Body
│   ├── HeaderSection
│   │   ├── AvatarWidget
│   │   └── TitleText
│   ├── ContentCard
│   │   ├── CardHeader
│   │   └── CardBody
│   └── ActionButtons
│       ├── PrimaryButton
│       └── SecondaryButton
└── BottomNavBar
```

## 对齐度
- 整体匹配度: 95%
- 主要偏差: <描述>

## 迭代记录
- 第 1 轮: 基础布局实现
- 第 2 轮: 间距微调
- 第 3 轮: 颜色和字体细节

## 下一步
- 运行 `rc:check-alignment <screen-name>` 获取详细对齐报告
- 运行 `rc:design-critique <screen-name>` 获取设计评审
- 运行 `rc:verify-interaction <screen-name>` 验证交互
```

## 原则

1. **TDD 驱动**：先写测试，再写实现。测试是设计的可执行规格说明。
2. **原子化构建**：从最小组件开始，逐步组合。每一步都可测试、可验证。
3. **Token 约束**：所有视觉属性必须引用 Design Tokens，零硬编码值。
4. **渐进精确**：首轮实现结构和布局，后续迭代打磨细节。不追求一次完美。
5. **人机协作**：自动化修复 3 轮内解决大部分问题，超出后请求人工判断。
6. **代码质量**：组件职责单一，命名语义化，遵循 Flutter 社区最佳实践。
