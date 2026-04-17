---
name: rc:commit
description: 提交所有变更、推送并创建 PR 到目标分支。Conventional Commit 格式。
argument-hint: "[target-branch]"
allowed-tools: Bash, Read, Glob, Grep
---

# Commit & PR — 提交变更并创建 Pull Request

提交所有变更、推送到远程分支并创建 PR 到目标分支。默认值为 `main`，可通过参数覆盖。

## Context

- Current git diff (staged and unstaged): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits (for message style): !`git log --oneline -10`

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 目标分支 | `main` | PR 的 base branch，如 `rc:commit develop` |

## 工作流程

严格按步骤执行。

### Step 0 — Early Exit Check

Check the context above:

1. **No uncommitted changes AND current branch has no diff vs target branch:**
   - Run `git diff <target-branch>...HEAD --stat` to check.
   - If both are empty, report: "No uncommitted changes and no diff vs `<target-branch>`. Nothing to do." then **STOP**.

2. **No uncommitted changes BUT branch has commits not in target:**
   - Skip to Step 3 (push + PR only).

3. **Has uncommitted changes:**
   - Continue to Step 1.

### Step 1 — Stage Changes

- First check for secret files (`.env`, credentials, tokens) in the diff. If found, warn the user and exclude them via `git reset HEAD <file>` after staging.
- Run `git add -A` to stage all changes, then unstage any secret files identified above.

### Step 2 — Commit

Generate a commit message following **Conventional Commits** format:

```
<type>(<scope>): <short summary>

<optional body — what and why, not how>
```

**Type:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `ci`, `build`
**Scope:** infer from changed files (e.g., `auth`, `api`, `ios`, `agent`)
**Summary 和 Body 必须使用中文**，简洁明了，不超过 72 字符，无句号结尾

示例：
```
feat(auth): 添加 Apple 登录回调接口

实现 Apple Sign-in 的服务端验证逻辑，包含 identity token 解析和用户匹配
```

Use a HEREDOC to pass the message:
```bash
git commit -m "$(cat <<'EOF'
<message here>
EOF
)"
```

### Step 3 — Push

Push the current branch to origin:
```bash
git push -u origin <current-branch>
```

If the push fails due to upstream divergence, report the error and **STOP** — do not force push.

### Step 4 — Create PR

First check if a PR already exists for this branch -> target:
```bash
gh pr list --head <current-branch> --base <target-branch> --state open
```

- If a PR already exists, report: "PR already open: <URL>，已 push 到该 PR。" then **STOP**.
- Otherwise, create a pull request:

```bash
gh pr create --base <target-branch> --title "<PR title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points describing the changes>

## Changes
<list of key files changed and why>
EOF
)"
```

- PR title: reuse or expand the commit summary (under 72 chars).

### Output

After completion, report:
1. Commit hash and message
2. Push result
3. PR URL
