---
name: rc:capture-mockups
description: 使用 Playwright 自动截取设计稿页面，保存为参考图片。支持 Codegen 录制脚本回放（推荐）和 AI 自动探索两种模式。按模块管理脚本和截图。
argument-hint: "<module> [--mode record|script|explore]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
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
| `module` | 否 | 模块名称。指定后脚本和截图按模块隔离（见下方路径规则）。不指定时作为整体项目处理 |
| `mode` | 否 | `record`：启动 Codegen 录制（即使已有脚本也重新录制）；`script`：强制脚本回放；`explore`：AI 自动探索。不指定则自动判断 |
| `page-filter` | 否 | 页面名称过滤器（支持通配符），不指定则截取全部页面 |
| `config-path` | 否 | `.design-to-code.yaml` 路径，默认当前项目根目录 |
| `viewport` | 否 | 截图视口大小，默认 `393x852`（iPhone 15 Pro 逻辑分辨率） |
| `scale` | 否 | 设备缩放比例，默认 `2`（Retina） |

## 路径规则

脚本和截图路径根据是否指定 `module` 参数而不同：

| 资源 | 无 module | 有 module（如 `home`） |
|------|-----------|------------------------|
| 录制脚本 | `scripts/capture-mockups.mjs` | `scripts/capture-home.mjs` |
| 页面截图 | `docs/design/mockups/screens/` | `docs/design/mockups/home/screens/` |
| 交互截图 | `docs/design/mockups/interactions/` | `docs/design/mockups/home/interactions/` |
| 数据状态截图 | `docs/design/mockups/states/` | `docs/design/mockups/home/states/` |
| 截图索引 | `docs/design/mockups/index.md` | `docs/design/mockups/home/index.md` |

> **模块化的好处**：大型项目可以按功能模块独立录制、独立回放、独立更新。
> 例如 `rc:capture-mockups home`、`rc:capture-mockups chat`、`rc:capture-mockups settings` 各自有独立的录制脚本和截图目录。

## 工作流程

### 步骤 0：判断采集模式

```
用户指定了 mode=record？
  └── YES → Mode C（引导录制 / 重新录制）

用户指定了 mode=explore？
  └── YES → Mode B（AI 探索）

用户指定了 mode=script？
  └── YES → 脚本存在？
              ├── YES → Mode A（脚本回放）
              └── NO → 报错：脚本不存在，请先用 mode=record 录制

未指定 mode → 自动判断：
  脚本存在？
    ├── YES → Mode A（脚本回放）
    └── NO → Mode C（引导录制）
```

> **设计决策**：没有脚本时默认走录制（Mode C），不自动走 AI 探索。
> 原因：AI 探索对 DOM 结构不规则的设计稿（hash class name、嵌套路由、自定义动画）不可靠，
> 人工录制一次确定路径比每次让 AI 猜测可靠得多。
> 如果用户确认设计稿足够简单，可以通过 `mode=explore` 显式选择 AI 探索。

---

## Mode A：脚本回放（推荐）

> 适用场景：已有录制脚本。
> 这是最可靠的模式——人工录制一次确定路径，后续自动回放。

### A1. 读取并验证脚本

- 根据路径规则定位脚本文件
- 检查脚本存在且包含 `screenshot` 调用
- 如果脚本存在但**没有** `screenshot` 调用，说明是 Codegen 原始录制脚本，跳转到 **步骤 P（脚本后处理）**
- 从脚本中解析将要生成的截图路径列表

### A2. 执行脚本

```bash
# 无 module
node scripts/capture-mockups.mjs

# 有 module
node scripts/capture-<module>.mjs
```

- 监控执行输出，确认每个截图成功生成
- 如果某个步骤超时或报错，记录失败原因但继续执行后续步骤

### A3. 验证截图产物

- 检查所有预期截图文件都已生成
- 验证截图非空（文件大小 > 1KB）
- 如有缺失，报告缺失列表

→ 跳转到**步骤 5（生成截图索引）**

---

## Mode B：AI 探索（需显式 opt-in：`mode=explore`）

> 仅当用户通过 `mode=explore` 显式指定时才使用。
> 适用场景：设计稿结构简单（≤ 5 页面、DOM 语义清晰），无需录制。

### B1. 读取项目配置

- 从 `.design-to-code.yaml` 读取设计稿 URL 和工具类型
- 如果配置文件不存在，提示先运行 `rc:init-project`
- 验证设计稿 URL 可访问

### B2. 准备截图环境

- 确认 Playwright 已安装（如未安装，`npx playwright install chromium`）
- 设置截图参数（视口、像素比、等待策略）

### B3. 探索并截取

根据设计工具类型选择截图策略：

**Figma：**
- 解析 Figma URL 中的文件和页面 ID
- 导航到 Figma 页面，等待加载完成
- 逐页面截图，支持滚动长页面

**通用 Web 设计稿：**
- 使用 `browser_snapshot` 探索页面结构
- 识别导航元素，逐页点击并截图
- 对每个页面等待渲染完成后全页截图

**注意**：如果探索过程中发现 DOM 结构不可靠（hash class name、点击无响应、找不到导航元素），提示用户切换到 `mode=record` 录制模式。

截图保存到对应的模块目录（按路径规则）。

→ 跳转到**步骤 5（生成截图索引）**

---

## Mode C：引导录制

> 适用场景：首次采集、重新录制、或设计稿交互流程变更后。
> 核心原则：人工录制一次确定路径，比每次让 AI 猜测可靠得多。

### C1. 读取设计稿 URL

- 从 `.design-to-code.yaml` 读取设计稿 URL
- 从配置中读取 viewport 设置

### C2. 引导用户启动 Codegen

使用 AskUserQuestion 告知用户：

```
请使用 Playwright Codegen 录制设计稿的交互路径。

在终端中运行：

  npx playwright codegen --viewport-size=<width>,<height> <design-url>

这会打开两个窗口：
  • 浏览器窗口 — 在这里按设计稿顺序操作每个页面和交互状态
  • 代码生成面板 — Playwright 实时将操作转为 JS 代码

操作要点：
  1. 按页面顺序，把每个页面、每个交互状态都点一遍
  2. 需要截图的状态停留 1-2 秒
  3. 录完后把生成的代码复制粘贴给我，或保存为 scripts/capture-<module>.mjs

录制完成后请告诉我，或直接把代码粘贴过来。
```

> 如果指定了 `module`，提示中的文件名为 `scripts/capture-<module>.mjs`。
> 如果未指定 `module`，文件名为 `scripts/capture-mockups.mjs`。
> 如果是重新录制（`mode=record` + 脚本已存在），额外提示旧脚本将被备份为 `.bak`。

### C3. 接收并保存原始脚本

- 用户粘贴代码或告知已保存文件
- 如果用户粘贴了代码，保存为对应的脚本文件（按路径规则）
- 如果是重新录制，先将旧脚本备份为 `<script>.bak`
- 跳转到**步骤 P（脚本后处理）**

---

## 步骤 P：脚本后处理（插入截图命令）

> 当拿到 Codegen 生成的原始录制脚本后，自动插入截图命令。

### P1. 分析录制脚本

读取脚本文件，识别：
- 每个 `page.goto()` 调用（页面导航）
- 每个 `page.getByXxx().click()` 或类似交互操作（状态变化）
- 每个 `page.waitForXxx()` 调用（等待动画/加载）

### P2. 规划截图插入点

为每个"到达新页面或新交互状态"的位置规划截图，路径根据模块确定：
- **页面导航后** → `<mockup_dir>/screens/<page_name>.png`
- **交互状态变化后**（展开/折叠/弹窗/Tab 切换）→ `<mockup_dir>/interactions/<interaction_name>.png`
- **数据状态变化后**（空/加载/错误/不同风险等级）→ `<mockup_dir>/states/<state_name>.png`

其中 `<mockup_dir>` 按路径规则：
- 无 module → `docs/design/mockups`
- 有 module → `docs/design/mockups/<module>`

### P3. 插入截图命令

在每个截图点插入两行：

```javascript
await page.waitForTimeout(500);  // 等待动画/渲染完成
await page.screenshot({ path: '<mockup_dir>/screens/<name>.png', fullPage: true });
```

### P4. 确保脚本结构完整

验证修改后的脚本：
- 有正确的 `import` 语句（`playwright`）
- `browser.newContext()` 中包含 viewport 设置
- 脚本末尾有 `await browser.close()`
- 截图目录结构在脚本开头创建：

```javascript
import { mkdirSync } from 'fs';
['screens', 'interactions', 'states'].forEach(
  sub => mkdirSync(`<mockup_dir>/${sub}`, { recursive: true })
);
```

### P5. 展示修改摘要并确认

向用户展示：
- 插入了多少个截图点
- 每个截图的路径和对应的操作步骤
- 让用户确认后执行脚本

确认后 → 跳转到 **Mode A（A2. 执行脚本）**

---

## 步骤 5：生成截图索引

创建或更新截图索引文件（按路径规则定位 `index.md`）：

```markdown
# 设计稿截图索引<: module>

> 自动生成于 <timestamp>，请勿手动编辑。
> 采集模式: script / explore
> 录制脚本: scripts/capture-<module>.mjs

## 页面截图 (screens/)
| 页面名称 | 文件 | 尺寸 | 截取时间 |
|----------|------|------|----------|
| Home Screen | screens/home.png | 393x852 | 2026-04-13 |
| ... | ... | ... | ... |

## 交互状态 (interactions/)
| 状态名称 | 文件 | 触发操作 | 截取时间 |
|----------|------|----------|----------|
| File Upload Sheet | interactions/file_upload_sheet.png | 点击"上传"按钮 | 2026-04-13 |
| ... | ... | ... | ... |

## 数据状态 (states/)
| 状态名称 | 文件 | 说明 | 截取时间 |
|----------|------|------|----------|
| Chat Empty | states/chat_empty.png | 聊天页空状态 | 2026-04-13 |
| ... | ... | ... | ... |
```

## 步骤 6：保存截图

- 文件命名规则：小写、空格替换为 `_`、去除特殊字符
- 如果文件已存在：保留旧文件为 `<name>.prev.png`，写入新文件
- 更新 `.design-to-code.yaml` 中的 `design.last_captured` 时间戳
- 如果有 `module`，同时更新 `design.modules.<module>.last_captured`

## 输出规格

```markdown
# 截图采集报告

## 采集结果
- 模块: <module> / （整体项目）
- 设计稿 URL: <url>
- 采集模式: script / explore / record（首次录制）
- 录制脚本: <script_path>
- 截取时间: <timestamp>
- 视口: <viewport>
- 缩放: <scale>

## 截取的页面
### screens/ (共 N 个)
| 页面 | 文件 | 大小 | 状态 |
|------|------|------|------|
| Home Screen | screens/home.png | 245KB | ✅ 新增 |
| Login | screens/login.png | 128KB | 🔄 更新 |

### interactions/ (共 N 个)
| 状态 | 文件 | 大小 | 状态 |
|------|------|------|------|
| File Upload | interactions/file_upload_sheet.png | 89KB | ✅ 新增 |

### states/ (共 N 个)
| 状态 | 文件 | 大小 | 状态 |
|------|------|------|------|
| Chat Empty | states/chat_empty.png | 56KB | ✅ 新增 |

## 跳过 / 失败的截图
- <name>: <原因>

## 下一步
- 运行 `rc:extract-tokens` 从截图中提取 Design Tokens
```

## 使用示例

```bash
# 首次采集整个项目（自动引导录制）
rc:capture-mockups

# 按模块首次录制
rc:capture-mockups home
rc:capture-mockups chat
rc:capture-mockups settings

# 设计稿 UI 更新后重新截图（自动回放已有脚本）
rc:capture-mockups home

# 交互流程变了，强制重新录制
rc:capture-mockups home --mode record

# 简单设计稿，跳过录制直接 AI 探索
rc:capture-mockups landing --mode explore
```

## 原则

1. **脚本优先**：有录制脚本时一律走脚本回放，保证路径确定性。AI 探索仅作为简单场景的便捷通道。
2. **一次录制，反复回放**：人工操作一次的成本远低于 AI 每次猜路径的不确定性。录制脚本是核心资产，提交到版本控制。
3. **模块隔离**：每个模块独立管理脚本和截图，互不干扰，支持独立更新。
4. **渐进引导**：不要求用户一开始就理解 Codegen，而是在需要时自然引导。
5. **可重复性**：相同脚本 + 相同设计稿 = 相同截图，截图参数固定不随环境变化。
6. **增量更新**：保留旧截图为 `.prev.png`，支持新旧对比。
7. **容错处理**：单个截图失败不影响整体流程，失败项记录在报告中。
8. **分类存储**：截图按 `screens/`、`interactions/`、`states/` 分类，便于后续流水线按类型使用。
