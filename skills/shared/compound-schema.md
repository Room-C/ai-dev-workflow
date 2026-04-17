# Compound Knowledge Schema

知识沉淀的共享 Schema。被 `rc:feature-archive` 和 `rc:diff-review` 引用，避免重复定义。

## 双轨分类

| 轨道 | 适用场景 | 典型文件 |
|------|---------|---------|
| **Bug Track** | 构建错误、运行时错误、配置错误、集成失败等具体问题 | 带 `symptoms` + `root_cause` + `resolution_type` 的文档 |
| **Knowledge Track** | 最佳实践、工作流改进、架构决策、性能优化等可泛化知识 | 带 `context` + `guidance` + `examples` 的文档 |

## Category → 目录映射

| `problem_type` / `category` | 目录 |
|----------------------------|------|
| `build_error` | `docs/solutions/build/` |
| `runtime_error` | `docs/solutions/runtime/` |
| `config_error` | `docs/solutions/config/` |
| `integration_issue` | `docs/solutions/integration/` |
| `best_practice` | `docs/solutions/best-practices/` |
| `workflow_issue` | `docs/solutions/workflow/` |
| `architecture` | `docs/solutions/architecture/` |
| `performance` | `docs/solutions/performance/` |

## YAML Frontmatter

```yaml
---
# 共享必填
module: <模块名>
date: YYYY-MM-DD
problem_type: <见上方映射>
component: <具体组件>
severity: <P0|P1|P2|P3>

# Bug Track 额外必填
symptoms: [症状列表]
root_cause: 根因描述
resolution_type: <code_fix|config_change|dependency_update|workaround|documentation>

# Knowledge Track 无额外必填

# 可选
tags: [tag1, tag2]
languages: [swift, python, ...]
source_review: <关联审查报告路径>
---
```

## 正文模板

**Bug Track**：
```
## Problem → Symptoms → What Didn't Work → Solution → Why This Works → Prevention → Related
```

**Knowledge Track**：
```
## Context → Guidance → Why This Matters → When to Apply → Examples → Related
```

## 文件命名

`{YYYY-MM-DD}-{kebab-case-title}.md`，例如：
- `2026-04-10-celery-task-timeout-fix.md`（Bug Track）
- `2026-04-10-ws-reconnect-race.md`（Knowledge Track）

## 沉淀门槛

只沉淀满足以下条件之一的内容：

- 花了超过 30 分钟排查的问题
- 需要搜索外部文档才解决的问题
- 违反直觉的行为或配置
- 未来大概率会再次遇到的模式
- 架构层面的设计决策及理由
- 同一类错误在本次或历史审查中出现 ≥ 2 次（模式级）

## 原则

- **只沉淀模式，不沉淀实例** — 描述一类问题，不是某一行代码
- **宁缺毋滥** — 没有模式级发现就跳过，不硬凑
- **增量更新** — 已有相似文档就更新，不创建新文档
- **可检索优先** — tags 和 category 要准确
