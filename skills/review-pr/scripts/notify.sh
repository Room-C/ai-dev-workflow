#!/usr/bin/env bash
# notify.sh — best-effort, cross-platform desktop notification.
#
# Never fails the caller: always exits 0. Falls back to stdout on headless
# or unknown hosts so the message is never lost.
#
# Usage: notify.sh "<message>" ["<title>"]
set -u

MSG="${1:-}"
TITLE="${2:-Review Agent}"
[ -z "$MSG" ] && exit 0

if command -v osascript >/dev/null 2>&1; then
  # macOS
  osascript -e "display notification \"${MSG//\"/\\\"}\" with title \"${TITLE//\"/\\\"}\" sound name \"Glass\"" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  # Linux (libnotify)
  notify-send "$TITLE" "$MSG" >/dev/null 2>&1 || true
elif command -v powershell.exe >/dev/null 2>&1; then
  # Windows / WSL
  powershell.exe -NoProfile -Command \
    "New-BurntToastNotification -Text '${TITLE//\'/}','${MSG//\'/}'" >/dev/null 2>&1 || true
fi

# Always echo too, so non-GUI hosts (Codex CLI, CI) still surface it.
echo "🔔 ${TITLE}: ${MSG}"
exit 0
