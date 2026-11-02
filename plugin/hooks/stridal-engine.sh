#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# stridal-engine.sh HOOK: the bootstrap launcher (ADR-0018 decision 7). It reads the repository's
# pin, verifies the engine against it, and runs the engine on HOOK, a control script beside it.
# It holds no control of its own: it decides only whether the engine may be trusted to judge.
#
#   no model marker                        exit 0 with the payload unread (stand aside)
#   no lock on origin/<main>, or a bad one  refused
#   no engine pinned for this platform     refused
#   no plugin, or not the pinned release   refused
#   engine missing, unrunnable, or another refused
#   all of it verified                     the engine's own exit status
#
# Refused is exit 2 with one line naming the fix, unless the call is a recovery command (git
# fetch, the plugin's update, stridal doctor), which is allowed: a refusal must never stop the
# command that clears it. That allowlist is here, not in the engine, because it must run when no
# engine can be trusted; engine.IsRecovery is its Go twin (framework/internal/engine).
#
# The pin is read through git from origin's main (or, with no origin, the main worktree's
# branch), never from the working tree: every worktree of a repository shares its refs, so each
# is guarded by main's pin. Which branch is main comes from git's own record, never from the
# lane's project.conf, which the lane can edit. Both registration paths call this one file (the
# plugin's hooks.json, and a `stridal install` project's settings.json, until OPS-145), so both
# read the one lock.
#
# Not yet registered: no release carries an engine until OPS-184, and a marked repository with
# no engine refuses every guarded call, so OPS-184 switches both paths to it. STRIDAL_ENGINE
# names an engine only under a check's fixture HOME (decision 6). Known limits (refs and remote
# config a lane can rewrite; hash then exec by path) are OPS-184's: docs/journal.d/OPS-183.md.
set -f

proj=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
[ -f "$proj/.claude/stridal-plugin" ] || [ -f "$proj/.claude/stridal-template" ] || exit 0
hook=${1:-}
case $hook in
  "" | *[!A-Za-z0-9_.-]* | .*) printf 'stridal: refused: the launcher was registered without a control name (%s)\nfix: claude plugin update stridal@stridal\n' "$hook" >&2; exit 2 ;;
esac
dir=$(cd "$(dirname "$0")" && pwd)

# recovery: the payload ($1) is a Bash call to one command that repairs a refusal, and nothing
# that could repoint what the launcher trusts. Only these characters, so no operator, quote,
# substitution, refspec (: +) or transport (::) can appear; git fetch takes only the listed
# flags and the one operand origin, so it can neither run a program (--upload-pack, -c) nor
# write a ref of its choosing (git fetch . +HEAD:refs/remotes/origin/main).
recovery() {
  command -v jq >/dev/null 2>&1 || { nojq=1; return 1; }
  cmd=$(printf '%s' "$1" | jq -r 'if .tool_name == "Bash" and (.tool_input.command | type) == "string" then .tool_input.command else empty end' 2>/dev/null) || return 1
  case $cmd in "" | *[!A-Za-z0-9@._\ -]*) return 1 ;; esac
  # shellcheck disable=SC2086 # split on purpose; -f is set
  set -- $cmd
  case "$*" in
    "stridal doctor" | "git remote set-head origin --auto" | "claude plugin update stridal@stridal" | "claude plugin install stridal@stridal" | "claude plugin marketplace update stridal") return 0 ;;
  esac
  [ $# -ge 2 ] && [ "$1 $2" = "git fetch" ] || return 1
  shift 2
  operand=
  for a; do
    case $a in
      --prune | -p | --quiet | -q | --tags | --no-tags) ;;
      origin) [ -z "$operand" ] || return 1; operand=1 ;;
      *) return 1 ;;
    esac
  done
  return 0
}

refuse() {
  payload=$(cat)
  recovery "$payload" && exit 0
  printf 'stridal: refused: %s\nfix: %s\n' "$1" "$2" >&2
  [ -z "${nojq:-}" ] || printf 'stridal: jq is not on PATH, so no recovery command is recognized, the fix above included: install jq\n' >&2
  exit 2
}

# good_branch: a plain branch name, no revision expression (main~1, main^{/x}, @{-1}) and nothing
# git would read as an option or another ref. Every alternative is reachable: stridal.mainBranch
# is a free string, and refs/remotes/origin/-x is a valid refname. It is stricter than git
# check-ref-format --branch, which would cost a process and could never refuse what this passes.
good_branch() {
  case $1 in "" | -* | /* | */ | *..* | *.lock | *[!A-Za-z0-9/._-]*) return 1 ;; esac
}

# verified_engine: resolve main's pin and verify this platform's engine against it. On success,
# $engine is the verified path and $release the pinned release; on failure, $why and $fix say
# why. It reads no payload and refuses nothing itself, so it is the one seam a SessionStart hook
# can call once per session to cache the verified path (resolve once, ADR-0018 decision 3: OPS-184,
# once OPS-199's spike decides the mechanism).
unverified() { why=$1 fix=$2; }
verified_engine() {
  # Which branch is main: origin's HEAD (set by clone; git remote set-head origin --auto sets it
  # again), or with no origin stridal.mainBranch in git's config, else main. Never a checkout's
  # HEAD and never a working-tree file (the lane's project.conf): those are what a lane changes in
  # its normal work. Full ref names, so a local branch named origin/main cannot stand in for the
  # remote's. The trust root is the git common dir and the plugin root: a lane that can write
  # those can choose its pin (docs/journal.d/OPS-183.md; OPS-184 makes them not lane-writable).
  if head=$(git -C "$proj" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); then
    main=${head#refs/remotes/origin/}
    [ "$main" != "$head" ] && good_branch "$main" ||
      { unverified "origin's HEAD names $head, not a branch of origin" "git remote set-head origin --auto"; return 1; }
    ref=refs/remotes/origin/$main
    lock=$(read_lock "$ref") || { unverified "no .claude/stridal.lock at $ref" "git fetch origin"; return 1; }
  elif git -C "$proj" config --get remote.origin.url >/dev/null 2>&1; then
    unverified "origin has no HEAD, so which of its branches is main is unknown" "git remote set-head origin --auto"; return 1
  else
    # No origin (a fork, a project not yet pushed): stridal.mainBranch, else main. --local reads
    # only the common dir's config, not a worktree's own config.worktree or the user's.
    main=$(git -C "$proj" config --local --get stridal.mainBranch 2>/dev/null) || main=main
    good_branch "$main" || { unverified "stridal.mainBranch names $main, not a plain branch name" "stridal doctor"; return 1; }
    ref=refs/heads/$main
    lock=$(read_lock "$ref") || { unverified "no .claude/stridal.lock at $ref" "stridal doctor"; return 1; }
  fi

  um=$(uname -sm)
  case ${um%% *} in
    Darwin) os=darwin ;; Linux) os=linux ;; *) os=unknown ;;
  esac
  case ${um##* } in
    x86_64 | amd64) arch=amd64 ;; arm64 | aarch64) arch=arm64 ;; *) arch=unknown ;;
  esac
  platform=$os/$arch

  # The lock's format is engine.Parse's: one release line, engine lines, nothing else.
  pin=$(printf '%s\n' "$lock" | awk -v want="$platform" '
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    $1 == "release" { if (NF != 2 || $2 !~ /^[0-9A-Za-z][0-9A-Za-z.+-]*$/ || rel != "") bad = 1; rel = $2; next }
    $1 == "engine" {
      if (NF != 3 || $2 !~ /^[a-z0-9]+\/[a-z0-9]+$/ || $3 !~ /^[0-9a-f]+$/ || length($3) != 64 || ($2 in sum)) bad = 1
      sum[$2] = $3; n++; next
    }
    { bad = 1 }
    END {
      if (bad || rel == "" || n == 0) { print "bad"; exit }
      print rel " " ((want in sum) ? sum[want] : "-")
    }')
  case $pin in
    "" | bad) unverified ".claude/stridal.lock at $ref does not parse (stridal doctor names the line)" "stridal doctor"; return 1 ;;
  esac
  release=${pin% *} want=${pin#* }
  [ "$want" != - ] || { unverified "the lock at $ref pins no engine for $platform" "stridal doctor"; return 1; }

  root=${CLAUDE_PLUGIN_ROOT:-}
  if [ -z "$root" ]; then
    f="${CLAUDE_CODE_PLUGIN_CACHE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins}/data/stridal-stridal/root"
    [ -f "$f" ] && IFS= read -r root < "$f"
  fi
  [ -n "$root" ] || { unverified "no stridal plugin root (CLAUDE_PLUGIN_ROOT is unset and the plugin has recorded none)" "claude plugin install stridal@stridal"; return 1; }
  version=$(sed -n '/^[ 	]*"version":/{s/^[ 	]*"version":[ 	]*"\([^"]*\)".*/\1/p;q;}' "$root/.claude-plugin/plugin.json" 2>/dev/null)
  [ "$version" = "$release" ] ||
    { unverified "the lock at $ref pins release $release, and the plugin is ${version:-unknown}" "claude plugin update stridal@stridal"; return 1; }

  engine=$root/engine/$os-$arch/stridal
  if [ -n "${STRIDAL_ENGINE:-}" ] && [ -f "$HOME/.stridal-fixture-home" ]; then
    h=$(cd -P "$HOME" 2>/dev/null && pwd) t=$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd)
    case $h in "${t%/}"/?*) [ -n "$t" ] && engine=$STRIDAL_ENGINE ;; esac
  fi
  [ -f "$engine" ] && [ -x "$engine" ] || { unverified "no executable engine at $engine" "claude plugin update stridal@stridal"; return 1; }

  # STRIDAL_SHA256 picks the tool, for the latency measurement only: whichever runs, the sum must
  # still equal the pin, so it can choose how to hash, never what passes.
  case ${STRIDAL_SHA256:-} in
    openssl) got=$(openssl dgst -sha256 -r "$engine" 2>/dev/null) ;;
    shasum) got=$(shasum -a 256 "$engine" 2>/dev/null) ;;
    *)
      if command -v sha256sum >/dev/null 2>&1; then
        got=$(sha256sum "$engine" 2>/dev/null)
      elif command -v shasum >/dev/null 2>&1; then
        got=$(shasum -a 256 "$engine" 2>/dev/null)
      else
        got=$(openssl dgst -sha256 -r "$engine" 2>/dev/null)
      fi ;;
  esac
  got=${got%% *}
  [ "$got" = "$want" ] ||
    { unverified "the engine at $engine is not the one the lock pins (sha256 ${got:-unreadable}, pinned $want)" "claude plugin update stridal@stridal"; return 1; }
}
read_lock() { git -C "$proj" cat-file blob "$1:.claude/stridal.lock" 2>/dev/null; }

verified_engine || refuse "$why" "$fix"

# Not exec: a verified engine that still cannot start (exit 126 or 127) must refuse, not fail
# open, and only this shell is left to say so. Its stdin is the payload, still unread.
"$engine" hook "$dir/$hook"
rc=$?
case $rc in
  126 | 127) refuse "the engine at $engine did not start (exit $rc)" "claude plugin update stridal@stridal" ;;
esac
exit "$rc"
