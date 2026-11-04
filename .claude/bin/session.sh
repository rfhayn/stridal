#!/usr/bin/env bash
# Open and close worker Claude sessions in Ghostty tabs, so the main session needs no per-command prompt.
# Usage:
#   .claude/bin/session.sh open <type> <slug> --report-to <name> [--dry-run]
#   .claude/bin/session.sh close <slug> [--abandon] [--dry-run]
# The prompt is read only from .claude/review/spawn-<slug>.md in the main checkout (git-ignored): a regular
# file, not a symlink, at most 20 KB. There is no path argument, so no other file can be read as a prompt.
# Run from the main checkout, on Ghostty with one instance and an open window. This script is the only
# thing allowed to run outside the sandbox for this (settings.json); the tab command it builds holds
# only validated tokens and a fixed path, never raw user text. --dry-run prints what would run, and runs nothing.
set -euo pipefail

refuse() { echo "session.sh: refused: $*" >&2; exit 2; }

SLUG_RE='^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$'
NAME_RE='^[A-Za-z0-9_-]+$'
PATH_RE='^[A-Za-z0-9/._-]+$'

# AppleScript source. Every value arrives through argv, so none is ever parsed as AppleScript.
IFS= read -r -d '' APPLE_OPEN <<'OSA' || true
on run argv
  tell application "Ghostty"
    set cfg to new surface configuration
    set initial working directory of cfg to item 1 of argv
    set command of cfg to item 2 of argv
    set t to new tab in front window with configuration cfg
    return id of focused terminal of t
  end tell
end run
OSA
IFS= read -r -d '' APPLE_CLOSE <<'OSA' || true
on run argv
  tell application "Ghostty"
    set term to terminal id (item 1 of argv)
    input text "/exit" to term
    send key "enter" to term
  end tell
end run
OSA

cmd=${1:-}
[ $# -gt 0 ] && shift
type="" slug="" report="" dry=0 abandon=0 have_report=0
case "$cmd" in
  open)
    [ $# -ge 2 ] || refuse "usage: open <type> <slug> --report-to <name> [--dry-run]"
    type=$1 slug=$2
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run) dry=1 ;;
        --report-to) [ $# -ge 2 ] || refuse "--report-to needs a name"; report=$2; have_report=1; shift ;;
        *) refuse "unknown argument for open: $1" ;;
      esac
      shift
    done
    case "$type" in feat|fix|chore|docs) ;; *) refuse "type must be feat, fix, chore or docs" ;; esac
    ;;
  close)
    [ $# -ge 1 ] || refuse "usage: close <slug> [--abandon] [--dry-run]"
    slug=$1
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run) dry=1 ;;
        --abandon) abandon=1 ;;
        *) refuse "unknown argument for close: $1" ;;
      esac
      shift
    done
    ;;
  *) refuse "first argument must be open or close" ;;
esac

[[ $slug =~ $SLUG_RE ]] || refuse "slug must match $SLUG_RE"
if [ "$cmd" = open ]; then
  [ "$have_report" = 1 ] || refuse "open needs --report-to <name>"
  [[ $report =~ $NAME_RE ]] || refuse "--report-to must match $NAME_RE"
fi

# Everything below builds from validated values only.
top=$(git rev-parse --show-toplevel)
gcd=$(git rev-parse --path-format=absolute --git-common-dir)
[[ $top =~ $PATH_RE ]] || refuse "the repo path has a character outside A-Za-z0-9/._-, which the tab command cannot carry safely"
[[ $gcd =~ $PATH_RE ]] || refuse "the git directory path has a character outside A-Za-z0-9/._-, which the tab command cannot carry safely"
if [ "$cmd" = open ]; then
  # The one place a prompt can come from. The name is built from the validated slug, never from an argument.
  prompt="$top/.claude/review/spawn-$slug.md"
  [ ! -L "$top/.claude/review" ] || refuse "$top/.claude/review is a symlink"
  [ ! -L "$prompt" ] || refuse "the prompt file is a symlink: $prompt"
  [ -e "$prompt" ] || refuse "no prompt file: write the brief to $prompt first"
  [ -f "$prompt" ] || refuse "the prompt is not a regular file: $prompt"
  [ -r "$prompt" ] || refuse "the prompt file is not readable: $prompt"
  [ "$(wc -c < "$prompt")" -le 20480 ] || refuse "the prompt file is over 20 KB: $prompt"
fi
spawn="$gcd/spawn"
wt="$top/.claude/worktrees/$slug"
promptfile="$spawn/$slug.prompt"
termfile="$spawn/$slug.term"
# Ghostty runs the tab command with a minimal PATH that lacks ~/.local/bin, so claude goes in by absolute path.
# A dry-run on a machine without claude (CI) falls back to the bare name.
claude_bin=$(command -v claude || true)
if [ -z "$claude_bin" ]; then
  [ "$dry" = 1 ] || refuse "claude is not on PATH"
  claude_bin=claude
fi
[[ $claude_bin =~ $PATH_RE ]] || refuse "the claude path has a character outside A-Za-z0-9/._-"
tabcmd="$claude_bin --name $slug --permission-mode auto -- \"\$(cat $promptfile)\""

if [ "$dry" = 1 ]; then
  if [ "$cmd" = open ]; then
    echo "branch: $type/$slug (new, from origin/main)"
    echo "worktree: $wt"
    echo "tab command: $tabcmd"
    echo "AppleScript (arguments: worktree, tab command):"
    printf '%s\n' "$APPLE_OPEN"
  else
    echo "would type /exit into the terminal id in $termfile, wait for claude --name $slug to end,"
    echo "then git worktree remove $wt, git branch -D <type>/$slug, and delete $spawn/$slug.*"
    echo "AppleScript (argument: terminal id):"
    printf '%s\n' "$APPLE_CLOSE"
  fi
  exit 0
fi

# Real run: main checkout only, on Ghostty with one instance and a window.
[ "$(git rev-parse --absolute-git-dir)" = "$gcd" ] || refuse "run this from the main checkout, not a worktree"
# ps, not pgrep: pgrep did not list Ghostty on the tested Mac although ps did.
procs=$(ps -axo command=)
n=$(printf '%s\n' "$procs" | grep -c '^/Applications/Ghostty.app/Contents/MacOS/ghostty$' || true)
[ "$n" = 1 ] || refuse "need exactly one Ghostty instance, found $n"
w=$(osascript -e 'tell application "Ghostty" to count windows') || refuse "could not ask Ghostty for its windows"
[ "${w:-0}" -ge 1 ] || refuse "Ghostty has no open window"

claude_running() {
  local p
  p=$(ps -axo command=) || return 1
  grep -Eq "(^|/)claude --name $slug( |\$)" <<<"$p"
}

if [ "$cmd" = open ]; then
  branch="$type/$slug"
  [ ! -e "$wt" ] || refuse "worktree already exists: $wt"
  ! git show-ref --verify --quiet "refs/heads/$branch" || refuse "local branch already exists: $branch"
  [ -z "$(git ls-remote --heads origin "$branch")" ] || refuse "remote branch already exists: $branch"
  [ ! -e "$promptfile" ] && [ ! -e "$termfile" ] || refuse "spawn files for $slug already exist in $spawn"
  git fetch origin
  git worktree add --no-track "$wt" -b "$branch" origin/main
  mkdir -p "$spawn"
  {
    cat "$prompt"
    printf '\n\nWhen you finish, or stop for any reason, SendMessage the session named %s with your summary or the reason.\n' "$report"
  } > "$promptfile"
  termid=$(osascript -e "$APPLE_OPEN" "$wt" "$tabcmd") || refuse "Ghostty did not open the tab; clean up with: .claude/bin/session.sh close $slug --abandon"
  printf '%s\n' "$termid" > "$termfile"
  echo "opened $branch in terminal $termid (worktree $wt)"
  exit 0
fi

# close
branch=""
for t in feat fix chore docs; do
  git show-ref --verify --quiet "refs/heads/$t/$slug" && branch="$t/$slug"
done
[ -n "$branch" ] || refuse "no local branch feat|fix|chore|docs/$slug"
if [ "$abandon" = 0 ]; then
  # headRefOid too: an older merged PR from a reused branch name must not pass for this branch's work.
  pr=$(gh pr view "$branch" --json state,headRefOid --jq '.state + " " + .headRefOid') || refuse "GitHub shows no PR for $branch; pass --abandon to close without one"
  state=${pr%% *} head=${pr##* }
  [ "$state" = MERGED ] || refuse "the PR for $branch is $state, not MERGED; pass --abandon to close anyway"
  [ "$head" = "$(git rev-parse "$branch")" ] || refuse "the merged PR for $branch ended at $head, but the local branch is at $(git rev-parse "$branch"): unpushed or different commits; pass --abandon to discard them"
fi
if claude_running; then
  [ -s "$termfile" ] || refuse "claude --name $slug is running but $termfile has no terminal id"
  osascript -e "$APPLE_CLOSE" "$(cat "$termfile")" || refuse "could not type /exit into terminal $(cat "$termfile")"
  deadline=$(($(date +%s) + 20))
  while claude_running; do
    [ "$(date +%s)" -lt "$deadline" ] || refuse "claude --name $slug is still running 20 s after /exit; nothing was removed"
    sleep 1
  done
fi
git worktree remove "$wt" || refuse "git worktree remove refused (is $wt dirty?); nothing forced, branch kept"
git branch -D "$branch"
rm -f "$promptfile" "$termfile"
echo "closed $slug: worktree and $branch removed"
