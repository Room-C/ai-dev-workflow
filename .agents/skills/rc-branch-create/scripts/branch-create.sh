#!/usr/bin/env bash
set -euo pipefail

DELETE_EXISTING_LOCAL=0
ORIGIN_BRANCH=""
NEW_BRANCH=""
ROOT=""
REPOS=()

usage() {
  cat >&2 <<'USAGE'
Usage:
  branch-create.sh <newBranch>
  branch-create.sh <originBranch> <newBranch>
  branch-create.sh --delete-existing-local <originBranch> <newBranch>

Examples:
  branch-create.sh feature/demo
  branch-create.sh develop feature/demo
  branch-create.sh release/1.0.0 feature/demo
USAGE
}

die() {
  local code="$1"
  shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "$code"
}

repo_label() {
  local repo="$1"

  if [ "$repo" = "." ]; then
    printf '.\n'
    return
  fi

  case "$repo" in
    "$ROOT"/*)
      printf '%s\n' "${repo#$ROOT/}"
      ;;
    *)
      printf '%s\n' "$repo"
      ;;
  esac
}

run_git() {
  local repo="$1"
  shift
  git -C "$repo" "$@"
}

collect_repos() {
  local submodules
  local repo_path

  REPOS=(".")
  submodules="$(git submodule foreach --recursive --quiet 'pwd' 2>/dev/null)" || {
    die 1 "failed to enumerate git submodules"
  }

  while IFS= read -r repo_path; do
    [ -n "$repo_path" ] || continue
    REPOS+=("$repo_path")
  done <<EOF
$submodules
EOF
}

ensure_clean() {
  local repo="$1"
  local status

  status="$(run_git "$repo" status --porcelain --untracked-files=all)" || {
    die 1 "failed to inspect worktree status in $(repo_label "$repo")"
  }

  if [ -n "$status" ]; then
    printf 'ERROR: dirty workspace in %s\n' "$(repo_label "$repo")" >&2
    printf '%s\n' "$status" >&2
    exit 2
  fi
}

branch_exists_local() {
  local repo="$1"
  local branch="$2"

  run_git "$repo" show-ref --verify --quiet "refs/heads/$branch"
}

branch_exists_remote() {
  local repo="$1"
  local branch="$2"

  run_git "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"
}

refresh_remote_refs() {
  local repo="$1"

  run_git "$repo" fetch --prune origin || {
    die 1 "failed to refresh origin refs in $(repo_label "$repo")"
  }
}

ensure_origin_branch_exists() {
  local repo="$1"

  if branch_exists_local "$repo" "$ORIGIN_BRANCH" || branch_exists_remote "$repo" "$ORIGIN_BRANCH"; then
    return 0
  fi

  die 3 "origin branch '$ORIGIN_BRANCH' was not found in $(repo_label "$repo")"
}

checkout_origin_branch() {
  local repo="$1"

  if branch_exists_local "$repo" "$ORIGIN_BRANCH"; then
    run_git "$repo" checkout "$ORIGIN_BRANCH" || {
      die 1 "failed to checkout '$ORIGIN_BRANCH' in $(repo_label "$repo")"
    }
    return 0
  fi

  if branch_exists_remote "$repo" "$ORIGIN_BRANCH"; then
    run_git "$repo" checkout -b "$ORIGIN_BRANCH" --track "origin/$ORIGIN_BRANCH" || {
      die 1 "failed to create local tracking branch '$ORIGIN_BRANCH' in $(repo_label "$repo")"
    }
    return 0
  fi

  die 3 "origin branch '$ORIGIN_BRANCH' was not found in $(repo_label "$repo")"
}

pull_origin_branch() {
  local repo="$1"

  run_git "$repo" pull --ff-only origin "$ORIGIN_BRANCH" || {
    die 4 "failed to fast-forward '$ORIGIN_BRANCH' in $(repo_label "$repo")"
  }
}

check_new_branch_conflict() {
  local repo="$1"

  if branch_exists_remote "$repo" "$NEW_BRANCH"; then
    die 5 "new branch '$NEW_BRANCH' already exists on origin in $(repo_label "$repo"); remote branches are never deleted automatically"
  fi

  if branch_exists_local "$repo" "$NEW_BRANCH" && [ "$DELETE_EXISTING_LOCAL" -ne 1 ]; then
    die 5 "new branch '$NEW_BRANCH' already exists locally in $(repo_label "$repo"); rerun with --delete-existing-local only after explicit confirmation"
  fi
}

ensure_not_on_new_branch() {
  local repo="$1"
  local current_branch

  current_branch="$(run_git "$repo" rev-parse --abbrev-ref HEAD)" || {
    die 1 "failed to read current branch in $(repo_label "$repo")"
  }

  if [ "$current_branch" = "$NEW_BRANCH" ]; then
    die 5 "new branch '$NEW_BRANCH' is currently checked out in $(repo_label "$repo"); checkout another branch before deleting it"
  fi
}

delete_existing_local_branch() {
  local repo="$1"

  if branch_exists_local "$repo" "$NEW_BRANCH"; then
    run_git "$repo" branch -D "$NEW_BRANCH" || {
      die 1 "failed to delete local branch '$NEW_BRANCH' in $(repo_label "$repo")"
    }
  fi
}

create_new_branch() {
  local repo="$1"

  run_git "$repo" checkout -b "$NEW_BRANCH" || {
    die 1 "failed to create branch '$NEW_BRANCH' in $(repo_label "$repo")"
  }
}

print_summary() {
  local repo
  local current_branch

  printf '\nCreated branch %s in:\n' "$NEW_BRANCH"
  for repo in "${REPOS[@]}"; do
    current_branch="$(run_git "$repo" rev-parse --abbrev-ref HEAD)" || {
      die 1 "failed to read current branch in $(repo_label "$repo")"
    }
    printf '  %s -> %s\n' "$(repo_label "$repo")" "$current_branch"
  done
}

validate_branch_name() {
  local label="$1"
  local branch="$2"

  [ -n "$branch" ] || die 64 "$label cannot be empty"

  case "$branch" in
    *[[:space:]]*)
      die 64 "$label cannot contain whitespace: $branch"
      ;;
  esac

  git check-ref-format --branch "$branch" >/dev/null 2>&1 || {
    die 64 "$label is not a valid git branch name: $branch"
  }
}

parse_args() {
  if [ "${1:-}" = "--delete-existing-local" ]; then
    DELETE_EXISTING_LOCAL=1
    shift
    [ "$#" -eq 2 ] || {
      usage
      exit 64
    }
    ORIGIN_BRANCH="$1"
    NEW_BRANCH="$2"
  else
    case "$#" in
    1)
      ORIGIN_BRANCH="develop"
      NEW_BRANCH="$1"
      ;;
    2)
      ORIGIN_BRANCH="$1"
      NEW_BRANCH="$2"
      ;;
    *)
      usage
      exit 64
      ;;
    esac
  fi

  validate_branch_name "originBranch" "$ORIGIN_BRANCH"
  validate_branch_name "newBranch" "$NEW_BRANCH"

  if [ "$ORIGIN_BRANCH" = "$NEW_BRANCH" ]; then
    die 64 "originBranch and newBranch must be different"
  fi
}

main() {
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    die 1 "not inside a git repository"
  }
  cd "$ROOT"

  collect_repos

  for repo in "${REPOS[@]}"; do
    ensure_clean "$repo"
  done

  parse_args "$@"

  for repo in "${REPOS[@]}"; do
    refresh_remote_refs "$repo"
  done

  for repo in "${REPOS[@]}"; do
    ensure_origin_branch_exists "$repo"
  done

  for repo in "${REPOS[@]}"; do
    check_new_branch_conflict "$repo"
  done

  if [ "$DELETE_EXISTING_LOCAL" -eq 1 ]; then
    for repo in "${REPOS[@]}"; do
      ensure_not_on_new_branch "$repo"
    done
  fi

  for repo in "${REPOS[@]}"; do
    checkout_origin_branch "$repo"
    pull_origin_branch "$repo"
  done

  if [ "$DELETE_EXISTING_LOCAL" -eq 1 ]; then
    for repo in "${REPOS[@]}"; do
      delete_existing_local_branch "$repo"
    done
  fi

  for repo in "${REPOS[@]}"; do
    create_new_branch "$repo"
  done

  print_summary
}

main "$@"
