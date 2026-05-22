---
name: rc-branch-create
description: Create the same Git branch in the main repository and all submodules from a base branch. Use when the user asks "rc:branch create <newBranch>" or "rc:branch create <originBranch> <newBranch>".
argument-hint: "[S1] S2"
---

# rc:branch create

Use this Skill to create the same Git branch in the main repository and every Git submodule from a shared base branch.

`rc` is the namespace. `branch create` is the concrete action.

## Commands

- `rc:branch create <newBranch>`
- `rc:branch create <originBranch> <newBranch>`

If `originBranch` is omitted, default it to `develop`.

Codex should translate user input into a call to the bundled script while keeping the shell working directory in the target Git repository:

```bash
cd <target-repo>
"$SKILL_DIR/scripts/branch-create.sh" <newBranch>
"$SKILL_DIR/scripts/branch-create.sh" <originBranch> <newBranch>
```

`SKILL_DIR` is the directory containing this Skill's installed `SKILL.md`. Resolve it from the host-provided Skill path when available; otherwise locate the installed `rc-branch-create/SKILL.md` and use its parent directory. Do not `cd` into `SKILL_DIR` before invoking the script.

The script itself does not parse `rc:branch create`; that prefix is the semantic command users type in Codex. The script discovers the target repository from the current working directory.

## Required Behavior

- Always call the bundled `scripts/branch-create.sh` by absolute path while the current working directory remains the user's target repository.
- If any repository is dirty, stop. Dirty means staged, unstaged, or untracked files in the main repository or any submodule.
- The script must check the main repository and all recursively configured Git submodules. If a configured submodule is not initialized, stop before changing branches.
- The script must refresh `origin` refs before checking whether `originBranch` or `origin/newBranch` exists.
- Because the script fast-forwards from `origin`, `originBranch` must exist on `origin` after refs are refreshed. Local-only base branches are rejected before any checkout.
- The script must use `git pull --ff-only`; never use a normal pull that can create a merge commit.
- Never use `git reset --hard`.
- Never delete a remote branch.

## Branch Conflicts

If the script reports that `newBranch` already exists, ask the user which action they want:

1. Delete the existing local branch and retry.
2. Use another new branch name.

Only if the user explicitly chooses to delete the existing local branch may Codex retry with:

```bash
cd <target-repo>
"$SKILL_DIR/scripts/branch-create.sh" --delete-existing-local <originBranch> <newBranch>
```

Even with `--delete-existing-local`, remote branches must never be deleted. If `origin/newBranch` exists anywhere, stop and ask the user to choose another branch name or handle the remote branch manually.
