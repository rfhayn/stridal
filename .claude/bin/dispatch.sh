#!/usr/bin/env bash
# Start this repo's dispatcher with one command: a correctly named, agent-identity session already running
# `/loop /dispatch`. Run it from the main checkout or any worktree of the repo.
# Usage: .claude/bin/dispatch.sh      (or the alias bootstrap.sh prints)
# It checks, in order, and refuses with exit 2 (starting nothing) when:
#   - the main checkout is not on main;
#   - the CLAUDE.md `## Dispatcher` block has no valid `Name:` (the session is dispatch-<key>, ADR-0006);
#   - a session `claude --name dispatch-<key>` already runs (`ps`; the name must end at a space or the line's end);
#   - `Agent:` is set but `Agent keychain:` is missing or a placeholder, or Agent equals Approver (ADR-0004).
# With no `Agent:` line it warns on stderr and starts claude under the user's own identity.
# The launcher only wraps as-agent.sh: it never reads the token (ADR-0004). It reads the block through
# dispatch-next.sh --name-key and --field, so there is one parser.
# Test hooks: DISPATCH_PS names a command used in place of `ps -axo command=`; DISPATCH_EXEC names a command exec'd
# with the argv in place of the real one.
set -euo pipefail

refuse() { echo "dispatch.sh: refused: $*" >&2; exit 2; }

# The main checkout is the parent of the git common dir, whether this is it or one of its worktrees.
gcd=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || refuse "not inside a git repository"
main=$(dirname "$gcd")
cd "$main" || refuse "cannot enter the main checkout $main"

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
[ "$branch" = main ] || refuse "the main checkout $main is on '${branch:-?}', not main; switch it to main first"

next=$main/.claude/bin/dispatch-next.sh
[ -f "$next" ] || refuse "$next is missing"
key=$(bash "$next" --name-key) || refuse "CLAUDE.md has no valid Name: in its ## Dispatcher block (see the message above)"

# A hint only (a /rename leaves no trace in ps), as in the dispatch skill's preconditions.
ps_ok=1
if [ -n "${DISPATCH_PS:-}" ]; then ps_out=$("$DISPATCH_PS") || ps_ok=0; else ps_out=$(ps -axo command=) || ps_ok=0; fi
[ "$ps_ok" = 1 ] || echo "dispatch.sh: warning: could not list processes, so a running dispatch-$key is not ruled out" >&2
# A here-string, not a pipe: grep -q stops at its first match, and a pipe's writer then dies of SIGPIPE, which
# pipefail turns into "no match" and lets a second dispatcher start.
if grep -Eq "claude --name dispatch-$key( |\$)" <<<"$ps_out"; then
  refuse "dispatch-$key already runs; switch to that tab (two dispatchers would take the same issues)"
fi

cmd=(claude --name "dispatch-$key" -- "/loop /dispatch")
if agent=$(bash "$next" --field Agent 2>/dev/null); then
  keychain=$(bash "$next" --field "Agent keychain" 2>/dev/null) \
    || refuse "Agent: is $agent but 'Agent keychain:' is missing or a placeholder in the ## Dispatcher block"
  if approver=$(bash "$next" --field Approver 2>/dev/null); then
    [ "$(printf '%s' "$agent" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$approver" | tr '[:upper:]' '[:lower:]')" ] \
      || refuse "Agent and Approver are both $agent; the approver is never the agent (ADR-0004)"
  fi
  cmd=("$main/.claude/bin/as-agent.sh" "$keychain" "${cmd[@]}")
else
  echo "dispatch.sh: warning: no Agent: line in the ## Dispatcher block, so this dispatcher runs as you, not a machine user (see docs/runbooks/agent-token.md)" >&2
fi

if [ -n "${DISPATCH_EXEC:-}" ]; then exec "$DISPATCH_EXEC" "${cmd[@]}"; fi
exec "${cmd[@]}"
