#!/usr/bin/env bash
# OPTIONAL. The kit's one hook slot, for a project whose one-way failure is a git command
# (a commit or push of personal data or secrets cannot be taken back). Blocking: exit 2 stops the call.
# Wire it as a PreToolUse hook on Bash (see README "The optional hook"). Formatting is NOT done here; it runs in ci.
# Set GUARD to an extended regex of paths that must never be staged, committed or pushed.
GUARD='^(PERSONAL_DATA/|secrets/)|(^|/)\.env(\..*)?$|\.(pem|key|p12|sqlite|xlsx)$'

# Without jq the command below reads as empty and the guard would pass everything, so block instead.
command -v jq >/dev/null 2>&1 || { echo "one-way-guard: jq is not installed, so this guard cannot read the command. Install jq." >&2; exit 2; }
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
case "$cmd" in *"git add"*|*"git commit"*|*"git push"*|*"git stash"*) ;; *) exit 0 ;; esac

# Paths named on the command line, already staged, or in commits not yet on origin/main.
hits=$( { tr ' ' '\n' <<<"$cmd"; git diff --cached --name-only 2>/dev/null
          git log --name-only --format= origin/main..HEAD 2>/dev/null; } | grep -v '^\.env\.example$' | grep -E "$GUARD" | sort -u )
[ -z "$hits" ] && exit 0
echo "one-way-guard: blocked '$cmd'. These paths must never enter git history:" >&2
echo "$hits" >&2
echo "Unstage them (git restore --staged <path>) or ask Rich. Do not work around this guard." >&2
exit 2
