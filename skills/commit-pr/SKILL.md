---
name: rc:commit-pr
description: 提交所有变更、推送并创建 PR 到目标分支。Use when the user asks to 创建 PR / 提交并创建 PR / 提交代码并开 PR / 发起 Pull Request / commit and create a PR / open a pull request, or runs rc:commit-pr.
argument-hint: "[target-branch]"
allowed-tools: Bash, Read, Glob, Grep
model: haiku
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
| 目标分支 | `main` | PR 的 base branch，如 `rc:commit-pr develop` |

## 工作流程

严格按步骤执行。

Before Step 0, resolve and refresh the remote base:

1. Set `<remote-target-branch>` to `origin/<target-branch>`.
2. Fetch the latest remote target branch before any branch diff checks:
   ```bash
   git fetch origin +refs/heads/<target-branch>:refs/remotes/origin/<target-branch>
   git rev-parse --verify <remote-target-branch>
   ```
3. If fetch or verification fails, report the error and **STOP**.
4. Use `<remote-target-branch>` for all `git diff` / merge-base checks. Keep using the plain `<target-branch>` for `gh pr list --base` and `gh pr create --base`.

### Step 0 — Early Exit Check

Check the context above:

1. **No uncommitted changes AND current branch has no diff vs target branch:**
   - Run `git diff <remote-target-branch>...HEAD --stat` to check.
   - If both are empty, report: "No uncommitted changes and no diff vs `<remote-target-branch>`. Nothing to do." then **STOP**.

2. **No uncommitted changes BUT branch has commits not in target:**
   - Skip to Step 3 (push + PR only).

3. **Has uncommitted changes:**
   - Continue to Step 1.

### Step 1 — Stage Changes

1. Detect secret files in the diff (`HEAD` 覆盖已暂存 + 未暂存，避免用户预先 `git add` 过 secrets 导致漏检)：
   ```bash
   SECRETS=$(git diff HEAD --name-only | grep -E '(^|/)(\.env|.*\.pem|.*credentials.*|.*token.*)$' || true)
   ```
2. Run `git add -A` to stage all changes.
3. If `$SECRETS` is non-empty, unstage them and **verify**:
   ```bash
   [ -n "$SECRETS" ] && echo "$SECRETS" | xargs -I{} git reset HEAD -- {} 2>/dev/null
   STILL_STAGED=$(git diff --cached --name-only | grep -E '(^|/)(\.env|.*\.pem|.*credentials.*|.*token.*)$' || true)
   if [ -n "$STILL_STAGED" ]; then
     echo "ABORT: secret files still staged after reset: $STILL_STAGED" >&2
     exit 1
   fi
   ```
   Warn the user about the excluded files before committing.

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
gh pr list --head <current-branch> --base <target-branch> --state open --json number,url,isDraft
```

- If a PR already exists and `isDraft` is false, report: "PR already open: <URL>，已 push 到该 PR。" then **STOP**.
- If a PR already exists but `isDraft` is true（多为其他工具创建的草稿），run `gh pr ready <number>` 转为 Ready for review，report: "PR already open: <URL>，已 push 并从 Draft 转为 Ready。" then **STOP**. 仅当用户明确要求保持草稿时跳过转正。
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
- **禁止使用 `--draft`**：本 skill 必须产出 Ready for review 的正式 PR，除非用户明确要求草稿。

Then verify the new PR is not a draft（防御性校验，部分宿主/插件默认建草稿）：

```bash
IS_DRAFT=$(gh pr view --json isDraft --jq '.isDraft')
if [ "$IS_DRAFT" = "true" ]; then
  gh pr ready
fi
```

If `gh pr ready` fails, report the PR URL and ask the user to mark it ready manually.

### Output

After completion, report:
1. Commit hash and message
2. Push result
3. PR URL
4. PR 状态：Ready for review（如发生过 Draft 转正，说明一下）
