#!/bin/sh
# Notification (matcher: permission_prompt) -- tell the dispatcher a spawned worker is stuck on a prompt.
#
# The one thing a worker cannot report itself: it is blocked waiting for a human to approve a tool call.
# When that happens in a worktree that session.sh open started (it records spawn/<slug>.term in the git
# common dir), this touches <git-common-dir>/spawn/<slug>.waiting. `session.sh watch <slug>` polls for that
# marker and prints "waiting <slug>". It also raises a desktop notification on macOS.
#
# Always exits 0 and prints nothing on stdout: a notification hook must never block or confuse the session.
# Set NOTIFY_WAITING_NO_DESKTOP=1 to skip the desktop notification (tests and CI do).

payload=$(cat)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
case "$top" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac
slug=${top##*/}
printf '%s' "$slug" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$' || exit 0

gcd=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$gcd" ] || exit 0
[ -f "$gcd/spawn/$slug.term" ] || exit 0

touch "$gcd/spawn/$slug.waiting" 2>/dev/null

if [ "${NOTIFY_WAITING_NO_DESKTOP:-}" != 1 ] && command -v osascript >/dev/null 2>&1; then
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Claude"' -e 'end run' \
    "$slug is waiting on a permission prompt" >/dev/null 2>&1
fi
exit 0
