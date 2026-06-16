#!/usr/bin/env bash
# pr-diff-filter.sh — fetch a PR diff and strip review noise.
#
# Removes hunks for lockfiles, generated code, migrations, minified bundles,
# vendored/build output, and binary assets so the reviewer spends tokens only
# on human-authored changes. Mirrors the EXCLUDE_PATTERNS used by
# diff-review/scripts/preprocess-diff.sh.
#
# Outputs the filtered unified diff on stdout.
# Prints excluded file paths to stderr (prefixed "EXCLUDED: ").
#
# Usage: pr-diff-filter.sh <pr_number> [--repo <owner/name>]
#   With --repo, targets that repository (needed for PR links pointing elsewhere).
#   Without it, uses the gh-resolved repo for the current directory.
set -euo pipefail

PR="${1:?Usage: pr-diff-filter.sh <pr_number> [--repo <owner/name>]}"
shift || true

REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    *)      shift ;;
  esac
done

if [ -n "$REPO" ]; then
  DIFF=$(gh pr diff "$PR" --repo "$REPO" 2>&1) || { echo "ERROR: gh pr diff failed: $DIFF" >&2; exit 1; }
else
  DIFF=$(gh pr diff "$PR" 2>&1) || { echo "ERROR: gh pr diff failed: $DIFF" >&2; exit 1; }
fi

printf '%s\n' "$DIFF" | awk '
  BEGIN {
    # Each entry is an ERE matched against the b/ path of a file section.
    # Assigned explicitly (not split) because the patterns contain "|".
    pats[1]  = "\\.lock$";
    pats[2]  = "-lock\\.(json|yaml)$";
    pats[3]  = "\\.generated\\.";
    pats[4]  = "\\.g\\.dart$";
    pats[5]  = "\\.freezed\\.dart$";
    pats[6]  = "/migrations/";
    pats[7]  = "\\.min\\.(js|css)$";
    pats[8]  = "\\.pbxproj$";
    pats[9]  = "\\.(png|jpe?g|gif|webp|ico|svg|pdf|zip|gz|tgz|jar|woff2?|ttf|otf|eot|mp4|mov|mp3|wasm)$";
    pats[10] = "^(dist|build|vendor|node_modules|Pods|\\.next|coverage)/";
    n = 10;
    keep = 1;
  }
  /^diff --git / {
    path = $0;
    sub(/^diff --git a\/.* b\//, "", path);
    keep = 1;
    for (i = 1; i <= n; i++) {
      if (path ~ pats[i]) { keep = 0; print "EXCLUDED: " path > "/dev/stderr"; break; }
    }
  }
  { if (keep) print }
'
