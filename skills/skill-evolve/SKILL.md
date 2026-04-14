---
name: rc:skill-evolve
description: 分析 Skill 执行遥测数据，识别反复失败模式，提出改进方案并更新 known-issues。当用户说"分析技能健康度"、"skill 进化"、"为什么总是失败"时触发。
argument-hint: "[--apply] [--skill <name>]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Skill Evolve — 自进化分析与修补

分析 Skill 执行遥测数据，识别反复出现的失败模式，自动更新 known-issues 注册表，对严重模式提出 SKILL.md 补丁提案。

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--apply` | 关闭 | 自动应用 safe_auto 改进（known-issues 更新）。不带此参数则只生成报告 |
| `--skill` | 全部 | 聚焦分析某个 Skill，如 `--skill diff-review` |

## 工作流程

### Step 1: 加载数据源

```bash
TELEMETRY_FILE="$HOME/.ai-dev-workflow/telemetry.jsonl"
```

1. 读取 `$TELEMETRY_FILE`，如果文件不存在或为空 → 告知用户"尚无遥测数据，请先执行几次 Skill 后再运行"，**结束流程**
2. 读取 `skills/shared/known-issues.md`（通过插件缓存路径定位）
3. 读取 `CHANGELOG.md` 了解历史修复
4. 如果指定了 `--skill`，只保留该 Skill 的遥测记录

### Step 2: 统计概览

对遥测数据进行基础统计：

```bash
# 统计各 Skill 执行次数和状态分布
cat "$TELEMETRY_FILE" | python3 -c "
import sys, json
from collections import defaultdict

stats = defaultdict(lambda: {'total': 0, 'success': 0, 'partial': 0, 'failed': 0, 'reasons': defaultdict(int)})
skipped = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        r = json.loads(line)
    except json.JSONDecodeError:
        skipped += 1
        continue
    s = stats[r['skill']]
    s['total'] += 1
    s[r['status']] += 1
    if r.get('failure_reason'):
        s['reasons'][r['failure_reason']] += 1
if skipped:
    print(f'(skipped {skipped} malformed lines)', file=sys.stderr)

for skill, s in sorted(stats.items()):
    rate = s['success'] / s['total'] * 100 if s['total'] > 0 else 0
    print(f'{skill}: {s[\"total\"]} runs, {rate:.0f}% success, {s[\"partial\"]} partial, {s[\"failed\"]} failed')
    for reason, count in sorted(s['reasons'].items(), key=lambda x: -x[1]):
        print(f'  - {reason}: {count}x')
"
```

输出概览表：

| Skill | 总执行 | 成功率 | 降级次数 | 失败次数 | 最常见失败原因 |
|-------|--------|--------|----------|----------|---------------|

### Step 3: 模式识别

对每个 Skill 的失败记录进行聚类：

#### 3a. 反复失败检测

按 `failure_reason` 聚类，标记出现 **>= 2 次**的为「反复失败模式」。

#### 3b. 降级热点检测

按 `fallback_used` 聚类，识别哪些降级路径被频繁触发。如果某个主路径的降级率 > 50%，标记为「主路径不可靠」。

#### 3c. 跨项目关联

检查同一 `failure_reason` 是否出现在不同 `project` 中。如果是 → 这是插件级问题，而非项目特定问题。

#### 3d. 已知问题覆盖率

将识别到的模式与 `known-issues.md` 现有条目对比：
- 已覆盖 → 检查该条目是否有效（问题是否仍在发生）
- 未覆盖 → 标记为「新发现模式」

### Step 4: 根因分析

对每个「新发现模式」和「反复失败模式」：

1. **读取 SKILL.md** — 定位到 `failure_step` 对应的代码段
2. **分析根因** — 是路径问题？超时问题？API 变更？缺少 fallback？
3. **检查 CHANGELOG** — 是否是已修复但回归的问题？
4. **分类改进级别**：

| 改进级别 | 触发条件 | 动作 |
|---------|---------|------|
| `known_issue` | 出现 >= 2 次，尚无 known-issues 条目 | 新增 known-issues 条目 |
| `skill_patch` | 出现 >= 3 次，或降级率 > 50% | 生成 SKILL.md 补丁提案 |
| `architecture` | 跨 Skill 出现同类问题 | 提出架构级改进建议 |

### Step 5: 生成改进报告

```bash
mkdir -p "docs/develop/skill-evolution"
```

输出到 `docs/develop/skill-evolution/{YYYY-MM-DD}-report.md`：

```markdown
# Skill Evolution Report

**分析时间**: YYYY-MM-DD HH:mm
**数据范围**: 最早记录 ~ 最新记录
**遥测条目数**: N

## 统计概览

| Skill | 总执行 | 成功率 | 降级次数 | 失败次数 |
|-------|--------|--------|----------|----------|

## 识别到的模式

### 模式 1: <标题>
- **Skill**: <skill-name>
- **出现次数**: N
- **失败步骤**: <step>
- **失败原因**: <reason>
- **已有 known-issue**: 是/否
- **改进级别**: known_issue / skill_patch / architecture
- **建议**: <具体改进方案>

## 改进动作

### safe_auto（直接应用）
- [ ] known-issues.md: 新增 <N> 条

### gated_auto（需用户确认）
- [ ] <skill>/SKILL.md: <补丁描述>

### 建议（仅报告）
- <架构级改进建议>
```

### Step 6: 应用改进

#### 6a. known-issues 更新 — safe_auto

对所有新发现的模式，追加到 `skills/shared/known-issues.md` 对应 Skill 的 section。

格式：`- **[YYYY-MM-DD]** <问题描述>。出现 N 次，最近一次在 <project>。`

如果未指定 `--apply`，仅在报告中列出待追加的条目，不实际写入。

#### 6b. SKILL.md 补丁 — gated_auto

对需要修补的 SKILL.md：

1. 读取当前 SKILL.md 内容
2. 生成补丁说明（描述要改什么、为什么改）
3. 用 `AskUserQuestion` 展示补丁方案，请求用户确认
4. 用户确认后，用 `Edit` 工具应用补丁

如果未指定 `--apply`，仅在报告中列出补丁提案，不执行任何修改。

### Step 7: 遥测归档（可选）

如果 `$TELEMETRY_FILE` 超过 1000 行：

```bash
# 归档旧数据（兼容 macOS BSD head，不使用 GNU head -n -200）
ARCHIVE_FILE="$HOME/.ai-dev-workflow/telemetry-archive-$(date +%Y%m%d).jsonl"
TOTAL=$(wc -l < "$TELEMETRY_FILE")
KEEP=200
ARCHIVE_COUNT=$((TOTAL - KEEP))
if [ "$ARCHIVE_COUNT" -gt 0 ]; then
  head -n "$ARCHIVE_COUNT" "$TELEMETRY_FILE" >> "$ARCHIVE_FILE"
  tail -n "$KEEP" "$TELEMETRY_FILE" > "$TELEMETRY_FILE.tmp"
  mv "$TELEMETRY_FILE.tmp" "$TELEMETRY_FILE"
fi
```

保留最近 200 条用于日常分析，归档历史数据供深度分析。

### Step 8: 记录自身遥测

```bash
RECORD_SCRIPT=$(ls "$HOME/.claude/plugins/cache/ai-dev-workflow"/*/*/skills/shared/scripts/record-outcome.sh 2>/dev/null | tail -1)
if [ -z "$RECORD_SCRIPT" ]; then
  for candidate in "skills/shared/scripts/record-outcome.sh" "dev_workflow/skills/shared/scripts/record-outcome.sh"; do
    [ -f "$candidate" ] && RECORD_SCRIPT="$candidate" && break
  done
fi
[ -n "$RECORD_SCRIPT" ] && bash "$RECORD_SCRIPT" skill-evolve <status>
```

## 重要提醒

1. **只报告有数据支撑的模式** — 不要基于单次失败就提出 SKILL.md 补丁
2. **known-issues 条目要具体** — 包含日期、出现次数、规避方式
3. **SKILL.md 补丁必须 gated_auto** — 永远不自动修改 Skill 定义，必须用户确认
4. **遥测数据跨项目** — `~/.ai-dev-workflow/telemetry.jsonl` 是全局的，分析时注意区分项目
5. **不修改遥测数据** — telemetry.jsonl 是 append-only，除了归档操作不做任何修改
