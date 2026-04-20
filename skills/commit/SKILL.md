---
name: rc:commit
description: 提交所有变更并推送到当前分支。Conventional Commit 格式。
allowed-tools: Bash, Read, Glob, Grep
model: haiku
---

# Commit — 提交变更并推送到当前分支

提交所有变更并推送到当前远程分支。

## Context

- Current git diff (staged and unstaged): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits (for message style): !`git log --oneline -10`

## 工作流程

### Step 0 — Early Exit Check

如果没有任何未提交变更，报告 "No uncommitted changes. Nothing to do." 然后 **STOP**。

### Step 1 — Stage Changes

1. 检测敏感文件：
   ```bash
   SECRETS=$(git diff HEAD --name-only | grep -E '(^|/)(\.env|.*\.pem|.*credentials.*|.*token.*)$' || true)
   ```
2. 执行 `git add -A` 暂存所有变更。
3. 如果 `$SECRETS` 非空，取消暂存并验证：
   ```bash
   [ -n "$SECRETS" ] && echo "$SECRETS" | xargs -I{} git reset HEAD -- {} 2>/dev/null
   STILL_STAGED=$(git diff --cached --name-only | grep -E '(^|/)(\.env|.*\.pem|.*credentials.*|.*token.*)$' || true)
   if [ -n "$STILL_STAGED" ]; then
     echo "ABORT: secret files still staged after reset: $STILL_STAGED" >&2
     exit 1
   fi
   ```
   提交前告知用户哪些文件被排除。

### Step 2 — Commit

按 **Conventional Commits** 格式生成提交信息：

```
<type>(<scope>): <short summary>

<optional body — what and why, not how>
```

**Type:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `ci`, `build`  
**Scope:** 从变更文件推断（如 `auth`、`api`、`skill`）  
**Summary 和 Body 必须使用中文**，不超过 72 字符，无句号结尾

使用 HEREDOC 传递消息：
```bash
git commit -m "$(cat <<'EOF'
<message here>
EOF
)"
```

### Step 3 — Push

推送到当前分支的远程：
```bash
git push -u origin <current-branch>
```

如果推送失败（上游有分歧），报告错误并 **STOP**，不执行强推。

### Output

完成后报告：
1. Commit hash 和提交信息
2. Push 结果
