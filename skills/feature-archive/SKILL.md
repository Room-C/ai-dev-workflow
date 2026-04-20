---
name: rc:feature-archive
description: 功能归档者 — 归档关键决策、更新全局索引、知识沉淀到 docs/solutions/。
argument-hint: "<module>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
model: sonnet
---

# Feature Archive — 功能归档者

功能开发完成后，归档关键决策、更新全局特性索引、将可复用知识沉淀到 `docs/solutions/`。

## 工作流程

### Step 1: 收集信息

1. **读取 CLAUDE.md**：了解项目结构和文档约定
2. **读取功能文档**：`docs/features/{module}/{version}/` 下的所有文档（analysis.md、design.md、tasks.md）
3. **读取 tasks.md 状态**：确认所有任务已完成（✅），如果有未完成任务，提醒用户先完成
4. **读取 git log**：获取本功能相关的提交历史（`git log --oneline --grep="{module}"`）
5. **读取 `docs/features/registry.md`**（如果存在）：了解现有索引格式

### Step 2: 更新全局特性索引

在 `docs/features/registry.md` 中添加或更新本功能的条目。

如果 `registry.md` 不存在，创建它：

```markdown
# 功能特性索引

| # | 模块 | 版本 | 状态 | 日期 | 说明 |
|---|------|------|------|------|------|
| 1 | [module] | [version] | ✅ 已完成 | [date] | [一句话描述] |
```

**索引规则**：
- 编号递增，已有编号不删除，只标 ❌ 表示废弃
- 同一模块多个版本各占一行
- 状态只有三种：✅ 已完成 / 🔧 进行中 / ❌ 已废弃

### Step 3: 在 tasks.md 头部添加完成摘要

在 tasks.md 的 front-matter 之后、正文之前，添加完成摘要块：

```markdown
> **完成摘要** (归档于 YYYY-MM-DD)
>
> - 总任务数：N，已完成：M，跳过：K
> - 关键提交：[commit-hash] [commit-message]
> - 耗时：[从第一个任务开始到最后一个任务完成的时间跨度]
> - 备注：[执行过程中的关键决策或需要后续关注的事项]
```

### Step 4: 知识沉淀

将开发过程中发现的可复用知识写入 `docs/solutions/`，使用 compound-engineering 双轨 Schema。

**Schema、category 映射、文件命名、沉淀门槛详见 `skills/shared/compound-schema.md`**（避免与 `rc:diff-review` 重复定义）。

本 Skill 只做额外强调：

- 归档阶段沉淀的典型素材是"本次开发过程中意外遇到的问题"和"验证后确认的最佳实践"
- **一次归档最多写 3 条 solution**，超出说明可能是把实例当模式，重新筛选

### Step 5: 报告归档结果

向用户输出归档摘要：

```
📦 归档完成

1. 特性索引：docs/features/registry.md — [新增/更新] #{编号} {模块} {版本}
2. 完成摘要：已添加到 tasks.md 头部
3. 知识沉淀：
   - [新增] docs/solutions/{category}/{filename}.md — {标题}
   - [跳过] 本次开发未发现需要沉淀的知识
```

## 原则

1. **registry.md 保持轻量**：每个功能只占一行，详情在各自的 design.md / tasks.md 中
2. **编号不删只标 ❌**：废弃的功能不从索引中删除，标记 ❌ 保留历史
3. **知识沉淀用 CE 双轨 Schema**：Bug Track 和 Knowledge Track 各有模板，不混用
4. **不修改已完成的 design.md / analysis.md**：归档阶段只添加元数据，不修改设计内容
5. **沉淀有门槛**：不是所有内容都值得沉淀，按判断标准筛选
6. **用中文输出**：所有文档内容使用中文
