# ai-dev-workflow

一套通用 Agent Skills 包，用结构化流程覆盖需求分析、架构设计、实现、代码审查和提交 PR。

本仓库可以通过 `npx skills` 安装到 Claude Code、Codex、Cursor 等支持 Skills 的 AI Coding 工具。Claude Code 的插件安装方式仍保留为兼容入口，但主分发路径是标准 Agent Skills。

每个 Skill 都是自包含目录（`SKILL.md` + `scripts/` + `references/`），可用 `--copy` 单独安装；核心工作流只依赖 Bash、git、gh 等命令行工具，子代理、Cron 等宿主能力缺失时自动降级为 inline / 手动流程。完整包契约见 `AGENTS.md` 与 `CLAUDE.md`。

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

Claude Code legacy 插件入口仍可使用：

```bash
/plugin marketplace add Room-C/ai-dev-workflow
/plugin install ai-dev-workflow
```

## 工作流

```
Feature Pipeline:
  rc:feature-analyze -> rc:feature-design -> rc:feature-implement -> rc:feature-archive

Quality Gates:
  rc:diff-review -> rc:commit-pr -> rc:review-pr
```

## 使用示例

```bash
/rc:feature-analyze "用户希望添加消息通知功能" --module notification --version v1
/rc:feature-design notification --version v1
/rc:feature-implement notification --version v1
/rc:diff-review main
/rc:commit-pr main
```

不支持 slash command 的宿主（如 Codex）直接用自然语言点名 Skill 即可，例如："使用 rc:diff-review 对比 main 审查当前分支"。

## Skill 清单

| Skill | 说明 |
|-------|------|
| `rc-branch-create` | 在主仓库和所有子模块中创建相同分支 |
| `rc:feature-analyze` | 将模糊需求转化为 `analysis.md` |
| `rc:feature-design` | 基于分析文档产出 `design.md`，含多视角审查 |
| `rc:feature-implement` | 拆解 `tasks.md` 并逐任务实现代码变更 |
| `rc:feature-archive` | 更新特性索引并沉淀 `docs/solutions/` |
| `rc:diff-review` | 对比目标分支审查、裁决、修复、复审 |
| `rc:commit` | 提交所有变更并推送当前分支 |
| `rc:commit-pr` | 提交、推送并创建或复用 PR |
| `rc:review-pr` | 默认单次 PR 审查；`--follow` 可启用有界、单次续约跟踪 |

## 开发与发布

```bash
npx skills add . --list          # 确认全部 Skill 可被发现
bash scripts/validate-package.sh # 发布前必须通过
```

## License

MIT — Room C Studio
