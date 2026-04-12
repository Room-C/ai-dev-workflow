---
name: rc:capture-mockups
description: 使用 Playwright 自动截取设计稿页面，保存为参考图片。
argument-hint: "[page-filter]"
allowed-tools: Bash, Read, Write, Glob, Grep
---

# rc:capture-mockups

## 角色

你是设计稿截图采集专家。你的职责是自动化截取设计稿页面，生成高质量的参考图片，供后续流水线步骤使用（token 提取、页面实现、对齐检查等）。

```
init-project → **capture-mockups** → extract-tokens → connect-app → implement-screen → check-alignment → design-critique → verify-interaction → run-golden → sync-design
```

## 输入参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `page-filter` | 否 | 页面名称过滤器（支持通配符），不指定则截取全部页面 |
| `config-path` | 否 | `.design-to-code.yaml` 路径，默认当前项目根目录 |
| `viewport` | 否 | 截图视口大小，默认 `1440x900` |
| `scale` | 否 | 设备缩放比例，默认 `2`（Retina） |

## 工作流程

### 步骤 1：读取项目配置

- 从 `.design-to-code.yaml` 读取设计稿 URL 和工具类型
- 如果配置文件不存在，提示先运行 `rc:init-project`
- 验证设计稿 URL 可访问

### 步骤 2：准备截图环境

- 确认 Playwright 已安装（如果未安装，使用 `npx playwright install chromium`）
- 设置截图参数：
  - 视口尺寸（默认 1440x900）
  - 设备像素比（默认 2x）
  - 等待策略（networkidle + 额外 2s 等待渲染完成）

### 步骤 3：截取设计稿页面

根据设计工具类型选择截图策略：

**Figma：**
- 解析 Figma URL 中的文件和页面 ID
- 使用 Playwright 导航到 Figma 页面
- 等待设计稿完整加载（检测加载指示器消失）
- 逐页面截图，支持滚动长页面

**Sketch / Zeplin / 其他：**
- 使用 Playwright 直接导航到设计稿页面
- 识别页面导航结构
- 逐页面截图

**通用策略：**
- 如果指定了 `page-filter`，只截取名称匹配的页面
- 对每个页面：
  1. 导航到页面
  2. 等待渲染完成
  3. 全页截图（`fullPage: true`）
  4. 裁剪纯白/透明边距

### 步骤 4：保存截图

- 保存路径：`docs/design/mockups/<page-name>.png`
- 文件命名规则：
  - 小写字母
  - 空格替换为 `-`
  - 去除特殊字符
  - 示例：`Home Screen` → `home-screen.png`
- 如果文件已存在：
  - 保留旧文件为 `<page-name>.prev.png`
  - 写入新文件

### 步骤 5：生成截图索引

创建或更新 `docs/design/mockups/index.md`：

```markdown
# 设计稿截图索引

> 自动生成于 <timestamp>，请勿手动编辑。

| 页面名称 | 文件 | 尺寸 | 截取时间 |
|----------|------|------|----------|
| Home Screen | home-screen.png | 1440x2560 | 2026-04-10 |
| Login | login.png | 1440x900 | 2026-04-10 |
| ... | ... | ... | ... |

## 变更记录
- 2026-04-10: 首次截取，共 N 个页面
```

### 步骤 6：更新工作流配置

- 更新 `.design-to-code.yaml` 中的 `design.last_captured` 时间戳
- 记录截取的页面列表

## 输出规格

```markdown
# 截图采集报告

## 采集结果
- 设计稿 URL: <url>
- 截取时间: <timestamp>
- 视口: <viewport>
- 缩放: <scale>

## 截取的页面（共 N 个）
| 页面 | 文件 | 大小 | 状态 |
|------|------|------|------|
| Home Screen | home-screen.png | 245KB | ✅ 新增 |
| Login | login.png | 128KB | 🔄 更新 |

## 跳过的页面
- <page>: <原因>

## 下一步
- 运行 `rc:extract-tokens` 从截图中提取 Design Tokens
```

## 原则

1. **可重复性**：相同输入始终产生相同输出，截图参数固定不随环境变化。
2. **增量更新**：保留旧截图为 `.prev.png`，支持新旧对比。
3. **容错处理**：单页面截图失败不影响其他页面，失败页面记录在报告中。
4. **最小等待**：使用智能等待策略（网络空闲 + DOM 稳定），避免固定长时间 sleep。
5. **隐私安全**：不缓存设计稿登录凭证，每次截图使用独立浏览器上下文。
