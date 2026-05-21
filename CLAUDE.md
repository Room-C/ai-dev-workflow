# ai-dev-workflow Compatibility Notes

@AGENTS.md

This repository is a generic Agent Skills package. Claude Code plugin support is retained as a legacy compatibility path, but the primary installation and upgrade path is `npx skills add/update`.

## Package Contract

1. Every installable Skill must be self-contained under `skills/<skill>/`.
2. Runtime dependencies belong beside the Skill:
   - `scripts/` for deterministic commands
   - `references/agents/` for delegated agent prompts
   - `references/shared/` for shared schemas and known issues
3. Root `agents/` is a development/legacy mirror only. Do not make a Skill depend on it after `--copy` installation.
4. Hard-coded host paths are forbidden as primary paths. Use current Skill resources first, then project-local fallbacks, then legacy host cache fallbacks if needed.

## Host Context Resolution

When a Skill needs project rules, read these in order:

1. `AGENTS.md`
2. `CLAUDE.md`
3. README / Makefile / package manager config / workspace config

When a Skill needs its own bundled files, treat the directory containing its `SKILL.md` as `SKILL_DIR`. If the host does not expose that path, locate it by searching common installed Skill roots for a matching `SKILL.md` name.

Common roots:

```bash
for root in \
  "$PWD/skills" \
  "$HOME/.agents/skills" \
  "$HOME/.claude/skills" \
  "$HOME/.codex/skills"; do
  [ -d "$root" ] && find "$root" -maxdepth 2 -name SKILL.md
done
```

## Execution Telemetry

Telemetry is best-effort and must never block the user's main task.

Preferred script location:

```bash
RECORD_SCRIPT="$SKILL_DIR/scripts/record-outcome.sh"
```

Fallbacks:

```bash
for candidate in \
  "$SKILL_DIR/scripts/record-outcome.sh" \
  "skills/<skill>/scripts/record-outcome.sh" \
  "skills/shared/scripts/record-outcome.sh" \
  "dev_workflow/skills/shared/scripts/record-outcome.sh"; do
  [ -f "$candidate" ] && RECORD_SCRIPT="$candidate" && break
done
```

Call only when the script exists:

```bash
if [ -n "${RECORD_SCRIPT:-}" ] && [ -f "$RECORD_SCRIPT" ]; then
  bash "$RECORD_SCRIPT" <skill-name> <status> [failure-step] [failure-reason] [fallback-used] || \
    echo "WARN: telemetry call exited non-zero; record may be incomplete." >&2
fi
```

## Optional Capabilities

- Subagents: use bundled `references/agents/*.md` when available; otherwise run the same workflow inline.
- Scheduler/Cron: use only when the host exposes it. Without scheduler support, write durable state and tell the user to rerun the Skill.
- MCP tools: Pencil/Xcode/Dart automation may be used when installed. Without them, request a screenshot, path, or manual setup step rather than failing the whole workflow.

## Release Validation

Run:

```bash
bash scripts/validate-package.sh
```

This must pass before claiming the package is installable through `npx skills`.
