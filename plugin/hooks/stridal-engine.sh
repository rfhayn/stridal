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
# The pin is read from origin/<main> (or <main> with no origin), through git, never from the
# working tree: every worktree of a repository shares its refs, so each is guarded by main's pin.
# Both registration paths call this one file (the plugin's hooks.json, and a `stridal install`
# project's settings.json, until OPS-145), so both read the one lock.
#
# Not yet registered: no release carries an engine until OPS-184, and a marked repository with
# no engine refuses every guarded call, so OPS-184 registers it when it ships the first one.
# STRIDAL_ENGINE names an engine only under a check's fixture HOME (decision 6).
set -f

proj=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
[ -f "$proj/.claude/stridal-plugin" ] || [ -f "$proj/.claude/stridal-template" ] || exit 0
hook=${1:-}
case $hook in
  "" | *[!A-Za-z0-9_.-]* | .*) printf 'stridal: refused: the launcher was registered without a control name (%s)\nfix: claude plugin update stridal@stridal\n' "$hook" >&2; exit 2 ;;
esac
dir=$(cd "$(dirname "$0")" && pwd)

# recovery: the payload ($1) is a Bash call to one command that repairs a refusal. Only these
# characters, so no operator, quote, substitution or newline can carry a second command; git
# fetch takes operands and a few flags, so no option (--upload-pack, -c) can run a program.
recovery() {
  command -v jq >/dev/null 2>&1 || return 1
  cmd=$(printf '%s' "$1" | jq -r 'if .tool_name == "Bash" and (.tool_input.command | type) == "string" then .tool_input.command else empty end' 2>/dev/null) || return 1
  [ -n "$cmd" ] || return 1
  case $cmd in *[!A-Za-z0-9@:/._=+,\ -]*) return 1 ;; esac
  # shellcheck disable=SC2086 # split on purpose; -f is set
  set -- $cmd
  case "$*" in
    "claude plugin update stridal@stridal" | "claude plugin install stridal@stridal" | "claude plugin marketplace update stridal") return 0 ;;
  esac
  [ $# -ge 2 ] || return 1
  case "$1 $2" in
    "git fetch")
      shift 2
      for a; do
        case $a in --prune | -p | --all | --quiet | -q | --tags | --no-tags) ;; -*) return 1 ;; esac
      done
      return 0 ;;
    "stridal doctor") return 0 ;;
  esac
  return 1
}

refuse() {
  payload=$(cat)
  recovery "$payload" && exit 0
  printf 'stridal: refused: %s\nfix: %s\n' "$1" "$2" >&2
  exit 2
}

# Each process costs a few milliseconds on every guarded call, so the common path forks as few
# as it can: one sed for MAIN_BRANCH (the last assignment wins), one git for the lock.
nl='
'
main=$(sed -n 's/^MAIN_BRANCH="\{0,1\}\([^" 	]*\)"\{0,1\}[ 	]*$/\1/p' "$proj/.claude/project.conf" 2>/dev/null)
main=${main##*"$nl"}
main=${main:-main}
# Full ref names, so a local branch named origin/main cannot stand in for the remote's.
read_lock() { git -C "$proj" cat-file blob "$1:.claude/stridal.lock" 2>/dev/null; }
ref=refs/remotes/origin/$main
if ! lock=$(read_lock "$ref"); then
  # Only a repository with no origin at all reads its own main (a fork, a project not yet pushed).
  if git -C "$proj" config --get remote.origin.url >/dev/null 2>&1; then
    refuse "no .claude/stridal.lock at $ref" "git fetch origin"
  fi
  ref=refs/heads/$main
  lock=$(read_lock "$ref") || refuse "no .claude/stridal.lock at $ref" "stridal doctor"
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
  "" | bad) refuse ".claude/stridal.lock at $ref does not parse (stridal doctor names the line)" "stridal doctor" ;;
esac
release=${pin% *} want=${pin#* }
[ "$want" != - ] || refuse "the lock at $ref pins no engine for $platform" "stridal doctor"

root=${CLAUDE_PLUGIN_ROOT:-}
if [ -z "$root" ]; then
  f="${CLAUDE_CODE_PLUGIN_CACHE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins}/data/stridal-stridal/root"
  [ -f "$f" ] && IFS= read -r root < "$f"
fi
[ -n "$root" ] || refuse "no stridal plugin root (CLAUDE_PLUGIN_ROOT is unset and the plugin has recorded none)" "claude plugin install stridal@stridal"
version=$(sed -n '/^[ 	]*"version":/{s/^[ 	]*"version":[ 	]*"\([^"]*\)".*/\1/p;q;}' "$root/.claude-plugin/plugin.json" 2>/dev/null)
[ "$version" = "$release" ] ||
  refuse "the lock at $ref pins release $release, and the plugin is ${version:-unknown}" "claude plugin update stridal@stridal"

engine=$root/engine/$os-$arch/stridal
if [ -n "${STRIDAL_ENGINE:-}" ] && [ -f "$HOME/.stridal-fixture-home" ]; then
  h=$(cd -P "$HOME" 2>/dev/null && pwd) t=$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd)
  case $h in "${t%/}"/?*) [ -n "$t" ] && engine=$STRIDAL_ENGINE ;; esac
fi
[ -f "$engine" ] && [ -x "$engine" ] || refuse "no executable engine at $engine" "claude plugin update stridal@stridal"

if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$engine" 2>/dev/null)
elif command -v shasum >/dev/null 2>&1; then
  got=$(shasum -a 256 "$engine" 2>/dev/null)
else
  got=$(openssl dgst -sha256 -r "$engine" 2>/dev/null)
fi
got=${got%% *}
[ "$got" = "$want" ] ||
  refuse "the engine at $engine is not the one the lock pins (sha256 ${got:-unreadable}, pinned $want)" "claude plugin update stridal@stridal"

# Not exec: a verified engine that still cannot start (exit 126 or 127) must refuse, not fail
# open, and only this shell is left to say so. Its stdin is the payload, still unread.
"$engine" hook "$dir/$hook"
rc=$?
case $rc in
  126 | 127) refuse "the engine at $engine did not start (exit $rc)" "claude plugin update stridal@stridal" ;;
esac
exit "$rc"
