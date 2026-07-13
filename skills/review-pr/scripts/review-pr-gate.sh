#!/usr/bin/env bash
# Deterministic lifecycle gate for bounded PR follow-up runs.
set -euo pipefail

MODE="gate"
MANUAL_TRIGGER=0
INIT_PHASE="active"
TERMINAL_REASON=""
RETRY_REASON="reviewer_retry"
REPO=""
PR_NUMBER=""
STATE_FILE=""
TTL_SECONDS=7200
MAX_TICKS=12
MAX_EVENT_ROUNDS=6
MAX_NO_CHANGE_TICKS=6
MAX_RETRIES=3
REVIEW_LEASE_SECONDS=900

usage() {
  cat <<'EOF'
Usage:
  review-pr-gate.sh --repo owner/name --pr N --state FILE [--manual]
  review-pr-gate.sh --init [--init-phase active|waiting_human] --repo owner/name --pr N --state FILE
  review-pr-gate.sh --waiting-human --state FILE
  review-pr-gate.sh --reviewed --state FILE
  review-pr-gate.sh --retry REASON --state FILE
  review-pr-gate.sh --terminal REASON --state FILE

Options for --init:
  --ttl-seconds N          Tracking lifetime, default 7200.
  --max-ticks N            Maximum wakeups, default 12.
  --max-event-rounds N     Maximum full review rounds, default 6.
  --max-no-change-ticks N  Maximum unchanged wakeups, default 6.
  --max-retries N          Maximum consecutive gate/reviewer failures, default 3.
EOF
}

set_mode() {
  local next="$1"
  if [ "$MODE" != "gate" ] && [ "$MODE" != "$next" ]; then
    echo "ERROR: lifecycle modes are mutually exclusive" >&2
    exit 2
  fi
  MODE="$next"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR_NUMBER="${2:-}"; shift 2 ;;
    --state) STATE_FILE="${2:-}"; shift 2 ;;
    --manual) MANUAL_TRIGGER=1; shift ;;
    --init) set_mode init; shift ;;
    --init-phase) INIT_PHASE="${2:-}"; shift 2 ;;
    --waiting-human) set_mode waiting_human; shift ;;
    --reviewed) set_mode reviewed; shift ;;
    --retry) set_mode retry; RETRY_REASON="${2:-}"; shift 2 ;;
    --terminal) set_mode terminal; TERMINAL_REASON="${2:-}"; shift 2 ;;
    --ttl-seconds) TTL_SECONDS="${2:-}"; shift 2 ;;
    --max-ticks) MAX_TICKS="${2:-}"; shift 2 ;;
    --max-event-rounds) MAX_EVENT_ROUNDS="${2:-}"; shift 2 ;;
    --max-no-change-ticks) MAX_NO_CHANGE_TICKS="${2:-}"; shift 2 ;;
    --max-retries) MAX_RETRIES="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
[ -n "$STATE_FILE" ] || { echo "ERROR: --state is required" >&2; exit 2; }

case "$MODE" in
  gate|init)
    command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required" >&2; exit 2; }
    [ -n "$REPO" ] || { echo "ERROR: --repo is required" >&2; exit 2; }
    case "$PR_NUMBER" in ''|*[!0-9]*) echo "ERROR: --pr must be numeric" >&2; exit 2 ;; esac
    ;;
esac

case "$INIT_PHASE" in active|waiting_human) ;; *) echo "ERROR: invalid --init-phase" >&2; exit 2 ;; esac
for value in "$TTL_SECONDS" "$MAX_TICKS" "$MAX_EVENT_ROUNDS" "$MAX_NO_CHANGE_TICKS" "$MAX_RETRIES"; do
  case "$value" in ''|*[!0-9]*) echo "ERROR: numeric lifecycle option expected" >&2; exit 2 ;; esac
done

NOW="${RC_REVIEW_NOW:-$(date +%s)}"
case "$NOW" in ''|*[!0-9]*) echo "ERROR: RC_REVIEW_NOW must be epoch seconds" >&2; exit 2 ;; esac

emit() {
  local action="$1" reason="$2" next_after="${3:-0}" tick="${4:-0}" event_round="${5:-0}"
  jq -nc --arg action "$action" --arg reason "$reason" \
    --argjson nextAfter "$next_after" --argjson tickCount "$tick" --argjson eventRound "$event_round" \
    '{action:$action,reason:$reason,nextAfter:$nextAfter,tickCount:$tickCount,eventRound:$eventRound}'
}

if [ "$MODE" != "init" ]; then
  if [ ! -f "$STATE_FILE" ] || ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    emit terminal state_missing
    exit 0
  fi
  if ! jq -e '
    def nonnegint: type == "number" and . >= 0 and floor == .;
    ((.phase // "active") as $phase | ["active", "waiting_human", "terminal"] | index($phase) != null) and
    ((.tickCount // 0) | nonnegint) and
    ((.eventRound // .round // 1) | nonnegint) and
    ((.retryCount // 0) | nonnegint) and
    ((.noChangeTicks // 0) | nonnegint) and
    ((.reviewLeaseUntil // 0) | nonnegint) and
    ((.maxTicks // 12) | nonnegint) and
    ((.maxEventRounds // .maxRounds // 6) | nonnegint) and
    ((.maxNoChangeTicks // 6) | nonnegint) and
    ((.maxRetries // 3) | nonnegint) and
    ((.expiresAt // 0) | nonnegint)
  ' "$STATE_FILE" >/dev/null 2>&1; then
    emit terminal state_invalid
    exit 0
  fi
  if [ "$MODE" = "gate" ] && ! jq -e --arg repo "$REPO" --argjson pr "$PR_NUMBER" '
    (.repo == null or .repo == $repo) and (.pr == null or .pr == $pr)
  ' "$STATE_FILE" >/dev/null 2>&1; then
    emit terminal state_mismatch
    exit 0
  fi
else
  STATE_DIR=$(dirname "$STATE_FILE")
  mkdir -p "$STATE_DIR" || { echo "ERROR: cannot create state directory: $STATE_DIR" >&2; exit 1; }
  chmod 700 "$STATE_DIR" 2>/dev/null || true
fi

LOCK_DIR="${STATE_FILE}.lock"
LOCK_HELD=0
TMP_FILE="${STATE_FILE}.tmp.$$"
if mkdir "$LOCK_DIR" 2>/dev/null; then
  LOCK_HELD=1
elif find "$LOCK_DIR" -prune -mmin +15 -print -quit 2>/dev/null | grep -q .; then
  STALE_LOCK="${LOCK_DIR}.stale.$$"
  if mv "$LOCK_DIR" "$STALE_LOCK" 2>/dev/null && mkdir "$LOCK_DIR" 2>/dev/null; then
    rm -rf "$STALE_LOCK"
    LOCK_HELD=1
  else
    rm -rf "$STALE_LOCK" 2>/dev/null || true
    emit skip already_running 60
    exit 0
  fi
else
  emit skip already_running 60
  exit 0
fi

cleanup() {
  rm -f "$TMP_FILE"
  [ "$LOCK_HELD" = "1" ] && rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

state_update() {
  local filter="$1"
  shift
  jq "$@" "$filter" "$STATE_FILE" > "$TMP_FILE" \
    || { echo "ERROR: cannot update state: $STATE_FILE" >&2; exit 1; }
  mv "$TMP_FILE" "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
}

checks_signature() {
  printf '%s' "$1" | jq -c \
    '[.statusCheckRollup[]? | {n:(.name // .context // ""), c:(.conclusion // .state // "")}] | sort_by(.n)'
}

fetch_snapshot() {
  META=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
    --json state,headRefOid,comments,reviews,statusCheckRollup 2>&1) || return 1
  INLINE_RAW=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments?per_page=100" --paginate 2>&1) || return 1
  INLINE_COUNT=$(printf '%s\n' "$INLINE_RAW" | jq -s -r \
    '[.[][] | select(((.body // "") | contains("<!-- rc-review:")) == false)] | length') || return 1
  printf '%s' "$INLINE_COUNT" | jq -e 'tonumber >= 0' >/dev/null 2>&1 || return 1
  PR_STATE=$(printf '%s' "$META" | jq -r '.state')
  CURR_SHA=$(printf '%s' "$META" | jq -r '.headRefOid')
  CURR_COMMENTS=$(printf '%s' "$META" | jq -r \
    '[.comments[]? | select(((.body // "") | contains("<!-- rc-review:")) == false)] | length')
  CURR_REVIEWS=$(printf '%s' "$META" | jq -r '.reviews | length')
  CURR_CHECKS=$(checks_signature "$META")
}

if [ "$MODE" = "init" ]; then
  if ! fetch_snapshot; then
    emit retry init_api_failure 300
    exit 0
  fi
  EXPIRES_AT=$((NOW + TTL_SECONDS))
  PHASE="$INIT_PHASE"
  REASON="initialized"
  TERMINAL_AT=0
  if [ "$PR_STATE" != "OPEN" ]; then
    PHASE="terminal"
    REASON="pr_$(printf '%s' "$PR_STATE" | tr '[:upper:]' '[:lower:]')"
    TERMINAL_AT="$NOW"
  fi
  jq -nc --arg repo "$REPO" --argjson pr "$PR_NUMBER" --arg phase "$PHASE" \
    --arg reason "$REASON" --arg sha "$CURR_SHA" --argjson checks "$CURR_CHECKS" \
    --argjson created "$NOW" --argjson expires "$EXPIRES_AT" --argjson terminalAt "$TERMINAL_AT" \
    --argjson maxTicks "$MAX_TICKS" --argjson maxEvents "$MAX_EVENT_ROUNDS" \
    --argjson maxNoChange "$MAX_NO_CHANGE_TICKS" --argjson maxRetries "$MAX_RETRIES" \
    --argjson comments "$CURR_COMMENTS" --argjson reviews "$CURR_REVIEWS" --argjson inline "$INLINE_COUNT" \
    '{schemaVersion:2,repo:$repo,pr:$pr,phase:$phase,createdAt:$created,updatedAt:$created,
      expiresAt:$expires,tickCount:0,maxTicks:$maxTicks,eventRound:1,maxEventRounds:$maxEvents,
      noChangeTicks:0,maxNoChangeTicks:$maxNoChange,retryCount:0,maxRetries:$maxRetries,pendingReview:false,
      reviewLeaseUntil:null,
      lastSha:$sha,lastCommentCount:$comments,lastReviewCount:$reviews,lastInlineCommentCount:$inline,
      lastChecksSig:$checks,terminalReason:(if $phase == "terminal" then $reason else null end),
      terminalAt:(if $phase == "terminal" then $terminalAt else null end)}' > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
  if [ "$PHASE" = "terminal" ]; then
    emit terminal "$REASON" 0 0 1
  else
    emit initialized "$PHASE" 300 0 1
  fi
  exit 0
fi

TICK_COUNT=$(jq -r '.tickCount // 0' "$STATE_FILE")
EVENT_ROUND=$(jq -r '.eventRound // .round // 1' "$STATE_FILE")
MAX_RETRIES=$(jq -r '.maxRetries // 3' "$STATE_FILE")
PHASE=$(jq -r '.phase // "active"' "$STATE_FILE")

mark_terminal() {
  local reason="$1"
  state_update '.phase = "terminal" | .pendingReview = false | .reviewLeaseUntil = null
    | .terminalReason = $reason | .terminalAt = $now | .updatedAt = $now' \
    --arg reason "$reason" --argjson now "$NOW"
  emit terminal "$reason" 0 "$TICK_COUNT" "$EVENT_ROUND"
}

backoff_seconds() {
  case "$1" in 0|1) echo 300 ;; 2) echo 900 ;; *) echo 1800 ;; esac
}

record_retry() {
  local reason="$1" detail="$2" pending_review="${3:-preserve}" retry_count next_after
  retry_count=$(jq -r '.retryCount // 0' "$STATE_FILE")
  retry_count=$((retry_count + 1))
  if [ "$retry_count" -ge "$MAX_RETRIES" ]; then
    mark_terminal retry_limit
    return
  fi
  next_after=$(backoff_seconds "$retry_count")
  state_update '.retryCount = $retry | .lastError = $detail | .updatedAt = $now
    | if $pending == "true" then .phase = "active" | .pendingReview = true | .reviewLeaseUntil = null else . end' \
    --argjson retry "$retry_count" --arg pending "$pending_review" \
    --arg detail "$detail" --argjson now "$NOW"
  emit retry "$reason" "$next_after" "$TICK_COUNT" "$EVENT_ROUND"
}

if [ "$PHASE" = "terminal" ]; then
  TERMINAL_REASON=$(jq -r '.terminalReason // "terminal"' "$STATE_FILE")
  emit terminal "$TERMINAL_REASON" 0 "$TICK_COUNT" "$EVENT_ROUND"
  exit 0
fi

if [ "$PHASE" = "waiting_human" ] && [ "$MODE" = "retry" ]; then
  emit waiting_human manual_input_required 0 "$TICK_COUNT" "$EVENT_ROUND"
  exit 0
fi

if [ "$MODE" = "waiting_human" ]; then
  state_update '.phase = "waiting_human" | .pendingReview = false | .reviewLeaseUntil = null | .updatedAt = $now' \
    --argjson now "$NOW"
  emit waiting_human manual_input_required 0 "$TICK_COUNT" "$EVENT_ROUND"
  exit 0
fi

if [ "$MODE" = "reviewed" ]; then
  state_update '.pendingReview = false | .reviewLeaseUntil = null
    | .retryCount = 0 | .lastError = null | .updatedAt = $now' \
    --argjson now "$NOW"
  emit reviewed review_completed 0 "$TICK_COUNT" "$EVENT_ROUND"
  exit 0
fi

if [ "$MODE" = "retry" ]; then
  [ -n "$RETRY_REASON" ] || RETRY_REASON="reviewer_retry"
  record_retry reviewer_retry "$RETRY_REASON" true
  exit 0
fi

if [ "$MODE" = "terminal" ]; then
  [ -n "$TERMINAL_REASON" ] || TERMINAL_REASON="completed"
  state_update '.phase = "terminal" | .pendingReview = false | .reviewLeaseUntil = null
    | .terminalReason = $reason | .terminalAt = $now | .updatedAt = $now' \
    --arg reason "$TERMINAL_REASON" --argjson now "$NOW"
  emit terminal "$TERMINAL_REASON" 0 "$TICK_COUNT" "$EVENT_ROUND"
  exit 0
fi

if [ "$PHASE" = "waiting_human" ] && [ "$MANUAL_TRIGGER" != "1" ]; then
  emit waiting_human manual_input_required 0 "$TICK_COUNT" "$EVENT_ROUND"
  exit 0
fi

TICK_COUNT=$((TICK_COUNT + 1))
MAX_TICKS=$(jq -r '.maxTicks // 12' "$STATE_FILE")
MAX_EVENT_ROUNDS=$(jq -r '.maxEventRounds // .maxRounds // 6' "$STATE_FILE")
MAX_NO_CHANGE_TICKS=$(jq -r '.maxNoChangeTicks // 6' "$STATE_FILE")
EXPIRES_AT=$(jq -r '.expiresAt // 0' "$STATE_FILE")
state_update '.tickCount = $tick | .updatedAt = $now' --argjson tick "$TICK_COUNT" --argjson now "$NOW"

if [ "$TICK_COUNT" -gt "$MAX_TICKS" ]; then
  mark_terminal tick_limit
  exit 0
fi
if [ "$EXPIRES_AT" -gt 0 ] && [ "$NOW" -ge "$EXPIRES_AT" ]; then
  mark_terminal ttl_expired
  exit 0
fi

if ! fetch_snapshot; then
  record_retry api_failure "${META:-${INLINE_COUNT:-GitHub API failure}}" preserve
  exit 0
fi

if [ "$PR_STATE" != "OPEN" ]; then
  mark_terminal "pr_$(printf '%s' "$PR_STATE" | tr '[:upper:]' '[:lower:]')"
  exit 0
fi

PREV_SHA=$(jq -r '.lastSha // ""' "$STATE_FILE")
PREV_COMMENTS=$(jq -r '.lastCommentCount // 0' "$STATE_FILE")
PREV_REVIEWS=$(jq -r '.lastReviewCount // 0' "$STATE_FILE")
PREV_INLINE=$(jq -r '.lastInlineCommentCount // 0' "$STATE_FILE")
PREV_CHECKS=$(jq -c '
  (.lastChecksSig // []) as $checks
  | if ($checks | type) == "string" then ($checks | fromjson? // []) else $checks end
' "$STATE_FILE")
PENDING_REVIEW=$(jq -r '.pendingReview // false' "$STATE_FILE")

if [ "$CURR_SHA" = "$PREV_SHA" ] \
  && [ "$CURR_COMMENTS" = "$PREV_COMMENTS" ] \
  && [ "$CURR_REVIEWS" = "$PREV_REVIEWS" ] \
  && [ "$INLINE_COUNT" = "$PREV_INLINE" ] \
  && [ "$CURR_CHECKS" = "$PREV_CHECKS" ]; then
  if [ "$PENDING_REVIEW" = "true" ]; then
    REVIEW_LEASE_UNTIL=$(jq -r '.reviewLeaseUntil // 0' "$STATE_FILE")
    if [ "$REVIEW_LEASE_UNTIL" -gt "$NOW" ]; then
      emit skip reviewer_in_progress "$((REVIEW_LEASE_UNTIL - NOW))" "$TICK_COUNT" "$EVENT_ROUND"
      exit 0
    fi
    REVIEW_LEASE_UNTIL=$((NOW + REVIEW_LEASE_SECONDS))
    state_update '.reviewLeaseUntil = $lease | .updatedAt = $now' \
      --argjson lease "$REVIEW_LEASE_UNTIL" --argjson now "$NOW"
    emit review pending_review 0 "$TICK_COUNT" "$EVENT_ROUND"
    exit 0
  fi
  NO_CHANGE_TICKS=$(jq -r '.noChangeTicks // 0' "$STATE_FILE")
  NO_CHANGE_TICKS=$((NO_CHANGE_TICKS + 1))
  state_update '.noChangeTicks = $count | .retryCount = 0 | .lastError = null | .updatedAt = $now' \
    --argjson count "$NO_CHANGE_TICKS" --argjson now "$NOW"
  if [ "$NO_CHANGE_TICKS" -ge "$MAX_NO_CHANGE_TICKS" ]; then
    mark_terminal no_change_limit
  elif [ "$PHASE" = "waiting_human" ]; then
    emit waiting_human no_new_event 0 "$TICK_COUNT" "$EVENT_ROUND"
  else
    emit skip no_changes "$(backoff_seconds "$NO_CHANGE_TICKS")" "$TICK_COUNT" "$EVENT_ROUND"
  fi
  exit 0
fi

EVENT_ROUND=$((EVENT_ROUND + 1))
if [ "$EVENT_ROUND" -gt "$MAX_EVENT_ROUNDS" ]; then
  mark_terminal event_round_limit
  exit 0
fi

state_update '.phase = "active" | .pendingReview = true | .eventRound = $round | .round = $round
  | .reviewLeaseUntil = $lease
  | .lastSha = $sha | .lastCommentCount = $comments | .lastReviewCount = $reviews
  | .lastInlineCommentCount = $inline | .lastChecksSig = $checks
  | .noChangeTicks = 0 | .retryCount = 0 | .lastError = null | .updatedAt = $now' \
  --argjson round "$EVENT_ROUND" --argjson lease "$((NOW + REVIEW_LEASE_SECONDS))" \
  --arg sha "$CURR_SHA" --argjson comments "$CURR_COMMENTS" \
  --argjson reviews "$CURR_REVIEWS" --argjson inline "$INLINE_COUNT" --argjson checks "$CURR_CHECKS" \
  --argjson now "$NOW"
emit review event_changed 0 "$TICK_COUNT" "$EVENT_ROUND"
