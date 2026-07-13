#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$ROOT/review-pr-gate.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

gh() {
  if [ "${FAKE_GH_FAIL:-0}" = "1" ]; then
    echo "fake GitHub failure" >&2
    return 1
  fi
  case "${1:-} ${2:-}" in
    "pr view") printf '%s\n' "${FAKE_META:?}" ;;
    "api repos/test/repo/pulls/7/comments?per_page=100") printf '%s\n' "${FAKE_INLINE:-0}" ;;
    *) echo "unexpected gh call: $*" >&2; return 2 ;;
  esac
}
export -f gh

META_OPEN='{"state":"OPEN","headRefOid":"sha-1","comments":[],"reviews":[],"statusCheckRollup":[]}'
META_CHANGED='{"state":"OPEN","headRefOid":"sha-2","comments":[],"reviews":[],"statusCheckRollup":[]}'
META_MERGED='{"state":"MERGED","headRefOid":"sha-1","comments":[],"reviews":[],"statusCheckRollup":[]}'
META_AGENT_COMMENT='{"state":"OPEN","headRefOid":"sha-1","comments":[{"body":"summary <!-- rc-review:summary -->"}],"reviews":[],"statusCheckRollup":[]}'
META_HUMAN_COMMENT='{"state":"OPEN","headRefOid":"sha-1","comments":[{"body":"please revisit this"}],"reviews":[],"statusCheckRollup":[]}'

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $label: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

new_state() {
  local file="$1" phase="${2:-active}" max_ticks="${3:-12}"
  jq -nc --arg phase "$phase" --argjson maxTicks "$max_ticks" \
    '{schemaVersion:2,repo:"test/repo",pr:7,phase:$phase,createdAt:1000,updatedAt:1000,
      expiresAt:999999,tickCount:0,maxTicks:$maxTicks,eventRound:1,maxEventRounds:6,
      noChangeTicks:0,maxNoChangeTicks:6,retryCount:0,maxRetries:3,pendingReview:false,lastSha:"sha-1",
      reviewLeaseUntil:null,lastCommentCount:0,lastReviewCount:0,lastInlineCommentCount:0,lastChecksSig:[]}' > "$file"
}

STATE="$TMP_ROOT/init.json"
OUT=$(RC_REVIEW_NOW=1000 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" --init \
  --repo test/repo --pr 7 --state "$STATE" --ttl-seconds 3600)
assert_eq initialized "$(printf '%s' "$OUT" | jq -r .action)" "init action"
assert_eq 4600 "$(jq -r .expiresAt "$STATE")" "init expiry"

STATE="$TMP_ROOT/unchanged.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq skip "$(printf '%s' "$OUT" | jq -r .action)" "unchanged action"
assert_eq 1 "$(jq -r .tickCount "$STATE")" "unchanged tick"
assert_eq 1 "$(jq -r .noChangeTicks "$STATE")" "unchanged count"

STATE="$TMP_ROOT/agent-comment.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_AGENT_COMMENT" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq skip "$(printf '%s' "$OUT" | jq -r .action)" "agent comment ignored"

STATE="$TMP_ROOT/human-comment.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_HUMAN_COMMENT" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq review "$(printf '%s' "$OUT" | jq -r .action)" "human comment triggers review"

STATE="$TMP_ROOT/changed.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_CHANGED" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq review "$(printf '%s' "$OUT" | jq -r .action)" "changed action"
assert_eq 2 "$(jq -r .eventRound "$STATE")" "changed round"
assert_eq sha-2 "$(jq -r .lastSha "$STATE")" "changed sha"
assert_eq true "$(jq -r .pendingReview "$STATE")" "changed pending review"
OUT=$(RC_REVIEW_NOW=1200 FAKE_META="$META_CHANGED" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq skip "$(printf '%s' "$OUT" | jq -r .action)" "active lease action"
assert_eq reviewer_in_progress "$(printf '%s' "$OUT" | jq -r .reason)" "active lease reason"
OUT=$(RC_REVIEW_NOW=2100 FAKE_META="$META_CHANGED" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq review "$(printf '%s' "$OUT" | jq -r .action)" "expired lease review action"
assert_eq pending_review "$(printf '%s' "$OUT" | jq -r .reason)" "expired lease review reason"
OUT=$(RC_REVIEW_NOW=2200 "$GATE" --reviewed --state "$STATE")
assert_eq reviewed "$(printf '%s' "$OUT" | jq -r .action)" "reviewed action"
assert_eq false "$(jq -r .pendingReview "$STATE")" "reviewed pending flag"
assert_eq null "$(jq -r .reviewLeaseUntil "$STATE")" "reviewed lease cleared"

STATE="$TMP_ROOT/merged.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_MERGED" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq terminal "$(printf '%s' "$OUT" | jq -r .action)" "merged action"
assert_eq pr_merged "$(jq -r .terminalReason "$STATE")" "merged reason"
assert_eq terminal "$(jq -r .phase "$STATE")" "merged tombstone"

STATE="$TMP_ROOT/waiting.json"
new_state "$STATE" waiting_human
OUT=$(RC_REVIEW_NOW=1100 FAKE_GH_FAIL=1 "$GATE" --repo test/repo --pr 7 --state "$STATE")
assert_eq waiting_human "$(printf '%s' "$OUT" | jq -r .action)" "automatic waiting action"
assert_eq 0 "$(jq -r .tickCount "$STATE")" "automatic waiting tick"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --manual --repo test/repo --pr 7 --state "$STATE")
assert_eq waiting_human "$(printf '%s' "$OUT" | jq -r .action)" "manual unchanged waiting"
OUT=$(RC_REVIEW_NOW=1200 FAKE_META="$META_OPEN" FAKE_INLINE=1 "$GATE" \
  --manual --repo test/repo --pr 7 --state "$STATE")
assert_eq review "$(printf '%s' "$OUT" | jq -r .action)" "human reply resumes waiting review"

STATE="$TMP_ROOT/retry.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_GH_FAIL=1 "$GATE" --repo test/repo --pr 7 --state "$STATE")
assert_eq retry "$(printf '%s' "$OUT" | jq -r .action)" "retry action"
assert_eq 1 "$(jq -r .retryCount "$STATE")" "retry count"

STATE="$TMP_ROOT/reviewer-retry.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 "$GATE" --retry gh_comments_failed --state "$STATE")
assert_eq retry "$(printf '%s' "$OUT" | jq -r .action)" "reviewer retry action"
assert_eq true "$(jq -r .pendingReview "$STATE")" "reviewer retry pending"
assert_eq gh_comments_failed "$(jq -r .lastError "$STATE")" "reviewer retry detail"
jq '.maxRetries = 2' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
OUT=$(RC_REVIEW_NOW=1200 "$GATE" --retry gh_comments_failed --state "$STATE")
assert_eq terminal "$(printf '%s' "$OUT" | jq -r .action)" "reviewer retry limit action"
assert_eq retry_limit "$(jq -r .terminalReason "$STATE")" "reviewer retry limit reason"

STATE="$TMP_ROOT/mismatch.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo other/repo --pr 7 --state "$STATE")
assert_eq state_mismatch "$(printf '%s' "$OUT" | jq -r .reason)" "state identity mismatch"

STATE="$TMP_ROOT/no-change-limit.json"
new_state "$STATE"
jq '.maxNoChangeTicks = 1' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq terminal "$(printf '%s' "$OUT" | jq -r .action)" "no-change limit action"
assert_eq no_change_limit "$(jq -r .terminalReason "$STATE")" "no-change limit reason"

STATE="$TMP_ROOT/ttl-limit.json"
new_state "$STATE"
jq '.expiresAt = 1100' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq ttl_expired "$(printf '%s' "$OUT" | jq -r .reason)" "ttl limit reason"

STATE="$TMP_ROOT/event-limit.json"
new_state "$STATE"
jq '.maxEventRounds = 1' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_CHANGED" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq event_round_limit "$(printf '%s' "$OUT" | jq -r .reason)" "event limit reason"

STATE="$TMP_ROOT/invalid.json"
printf '%s\n' '{"phase":[],"tickCount":0}' > "$STATE"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq state_invalid "$(printf '%s' "$OUT" | jq -r .reason)" "invalid state reason"

STATE="$TMP_ROOT/tick-limit.json"
new_state "$STATE" active 0
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq terminal "$(printf '%s' "$OUT" | jq -r .action)" "tick limit action"
assert_eq tick_limit "$(jq -r .terminalReason "$STATE")" "tick limit reason"

STATE="$TMP_ROOT/lock.json"
new_state "$STATE"
mkdir "${STATE}.lock"
OUT=$(RC_REVIEW_NOW=1100 FAKE_META="$META_OPEN" FAKE_INLINE=0 "$GATE" \
  --repo test/repo --pr 7 --state "$STATE")
assert_eq already_running "$(printf '%s' "$OUT" | jq -r .reason)" "lock action"
rmdir "${STATE}.lock"

STATE="$TMP_ROOT/lifecycle.json"
new_state "$STATE"
OUT=$(RC_REVIEW_NOW=1100 "$GATE" --waiting-human --state "$STATE")
assert_eq waiting_human "$(printf '%s' "$OUT" | jq -r .action)" "mark waiting"
OUT=$(RC_REVIEW_NOW=1200 "$GATE" --terminal completed --state "$STATE")
assert_eq terminal "$(printf '%s' "$OUT" | jq -r .action)" "mark terminal"
assert_eq completed "$(jq -r .terminalReason "$STATE")" "terminal reason"

OUT=$(RC_REVIEW_NOW=1300 "$GATE" --retry late_reviewer_failure --state "$STATE")
assert_eq terminal "$(printf '%s' "$OUT" | jq -r .action)" "terminal absorbs late retry"
assert_eq completed "$(jq -r .terminalReason "$STATE")" "terminal reason preserved"

STATE="$TMP_ROOT/waiting-absorbs-retry.json"
new_state "$STATE" waiting_human
OUT=$(RC_REVIEW_NOW=1100 "$GATE" --retry late_reviewer_failure --state "$STATE")
assert_eq waiting_human "$(printf '%s' "$OUT" | jq -r .action)" "waiting absorbs late retry"
assert_eq waiting_human "$(jq -r .phase "$STATE")" "waiting phase preserved"

echo "review-pr gate tests passed"
