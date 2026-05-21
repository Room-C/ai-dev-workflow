# ai-dev-workflow

一套通用 Agent Skills 包，用结构化流程覆盖需求分析、架构设计、实现、代码审查、提交 PR、设计稿转代码和工作流自进化。

本仓库可以通过 `npx skills` 安装到 Claude Code、Codex、Cursor 等支持 Skills 的 AI Coding 工具。Claude Code 的插件安装方式仍保留为兼容入口，但主分发路径是标准 Agent Skills。

## 安装

推荐全量安装并复制文件，避免运行时依赖仓库原路径：

```bash
npx skills add Room-C/ai-dev-workflow -g -a claude-code -a codex --skill '*' --copy -y
```

安装到所有可检测的工具：

```bash
npx skills add Room-C/ai-dev-workflow --all --copy
```

升级：

```bash
npx skills update -g -y
```

本地开发验证：

```bash
npx skills add . --list
bash scripts/validate-package.sh
```

Claude Code legacy 插件入口仍可使用：

```bash
/plugin marketplace add Room-C/ai-dev-workflow
/plugin install ai-dev-workflow
```

## 兼容模型

每个核心 Skill 都按自包含目录设计：`SKILL.md` 旁边的 `scripts/`、`references/agents/`、`references/shared/` 是该 Skill 的运行时依赖。用 `--copy` 单独安装某个 Skill 时，也应能读取自己的脚本、agent prompt 和共享 schema。

宿主能力分三层：

| 层级 | 能力 | 行为 |
|------|------|------|
| Core | Bash、读写文件、grep、git、gh CLI | 所有核心工作流必须可运行 |
| Agent | 子代理 / task delegation | 可用时委派到 bundled agent prompt；不可用时主上下文 inline 执行 |
| Optional MCP | Pencil、XcodeBuildMCP、Dart、Cron/scheduler | 可用时启用自动化；不可用时降级为手动截图、手动重跑或报告待办 |

项目规则读取顺序：

1. `AGENTS.md`
2. `CLAUDE.md`
3. README、package/workspace 配置、Makefile

不要把宿主项目规则文件当作本包的运行时依赖；它们只是使用者项目的上下文来源。

## 工作流

```
Feature Pipeline:
  rc:feature-analyze -> rc:feature-design -> rc:feature-implement -> rc:feature-archive

Quality Gates:
  rc:diff-review -> rc:commit-pr -> rc:review-pr

Design-to-Code:
  rc:read-design -> rc:implement-screen -> rc:verify-screen

Self-Evolving:
  rc:skill-evolve
```

## 使用示例

Claude Code slash command：

```bash
/rc:feature-analyze "用户希望添加消息通知功能" --module notification --version v1
/rc:feature-design notification --version v1
/rc:feature-implement notification --version v1
/rc:diff-review main
/rc:commit-pr main
```

Codex 或其他 Skills 宿主：

```text
使用 rc:feature-analyze 分析这个需求：用户希望添加消息通知功能，module=notification，version=v1。
使用 rc:feature-design 为 notification v1 生成 design.md。
使用 rc:feature-implement 执行 notification v1。
使用 rc:diff-review 对比 main 审查当前分支。
使用 rc:commit-pr 提交并创建到 main 的 PR。
```

## Skill 清单

| Skill | 说明 |
|-------|------|
| `rc:feature-analyze` | 将模糊需求转化为 `analysis.md` |
| `rc:feature-design` | 基于分析文档产出 `design.md`，含多视角审查 |
| `rc:feature-implement` | 拆解 `tasks.md` 并逐任务实现代码变更 |
| `rc:feature-archive` | 更新特性索引并沉淀 `docs/solutions/` |
| `rc:diff-review` | 对比目标分支审查、裁决、修复、复审 |
| `rc:commit` | 提交所有变更并推送当前分支 |
| `rc:commit-pr` | 提交、推送并创建或复用 PR |
| `rc:review-pr` | 首轮 PR 审查；有 scheduler 时可跟踪闭环 |
| `rc:read-design` | 读取 Pencil `.pen` 设计稿 |
| `rc:implement-screen` | 从 Pencil 设计稿实现 iOS/Flutter 页面 |
| `rc:verify-screen` | 对比设计稿与实现截图 |
| `rc:skill-evolve` | 分析遥测并提出工作流改进 |

## 发布前验证

每次调整包结构前运行：

```bash
bash scripts/validate-package.sh
```

该脚本会检查：

- `npx skills add . --list` 能发现全部 Skill
- 单个复杂 Skill 用 `--copy` 安装后仍带有 bundled resources
- 全量安装到 Codex/Claude Code 目标目录可成功
- 关键文档不再依赖 `.claude/plugins/cache` 作为唯一路径

## License

MIT — Room C Studio
