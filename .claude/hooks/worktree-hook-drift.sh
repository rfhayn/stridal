#!/bin/sh
# PreToolUse hook (matcher: Agent|Task). Refuses to spawn a WORKTREE agent while the guard code that
# will guard it lags origin/<main>, or while it cannot show that it does not.
#
# WHY. Every hook is registered as `"$CLAUDE_PROJECT_DIR"/.claude/hooks/…`, and that directory is
# the MAIN checkout. A worktree agent is cut from origin/<main>, but every Bash call it makes is
# judged by the hook code on whatever branch the main checkout has checked out. With the main
# checkout on an old branch, an agent's commit was blocked by a hook version its own branch had
# already replaced. The silent half is worse: a guard rule merged to main is simply NOT IN FORCE
# for the agent, and nothing says so.
#
# THE AUTHORITY is the copy that is actually executing: this file's own checkout. Its
# `.claude/hooks/`, `.claude/lib/` (conf.sh and the rest run inside the guards) and
# `.claude/settings.json` are compared, working tree included, with origin/<main>:
#   - identical: allowed, silently, whatever its commits say (a checkout that cherry-picked the
#     fix is guarded correctly);
#   - an index flag on a compared file: refused, as assume-unchanged and skip-worktree hide an edit
#     from status and from diff alike;
#   - differing and DIRTY (an edit, staged or not, a conflict, or an untracked file a diff never
#     sees): refused: no commit vouches for that code, and a half-applied pull looks just like this;
#   - differing with hook COMMITS from origin/<main> missing: refused;
#   - differing and only AHEAD of main, committed: on main itself refused, as no review has seen
#     them; on a lane's own branch someone developing a hook on purpose: noted, not blocked.
#
# IT FAILS CLOSED (OPS-222). What it cannot compare refuses, naming a fix only where one is known to
# work: no git, a checkout that is no repository or not the top of one, an origin whose main git does
# not know, a command that fails. The one thing it allows unverified is a repository with NO remote called origin, with
# a note: there is no main for its hooks to lag. A remote under another name is exempt here, while
# conf_keys_from_main (lib/conf.sh) takes any remote to mean a main exists, reads origin's and
# says it could not: the two disagree on such a repository, and this one allows.
#
# WHAT A REFUSAL NAMES. Commands, each on a line of its own starting `  $ ` under a heading, which
# checks/hooks.sh runs as printed in the common states. A discard takes uncommitted work from HEAD
# and leaves commits alone. They are a start, not a promise for every state: KNOWN LIMITS says where
# one stops or clears nothing, and spawning the agent without worktree isolation stays the way out.
#
# WHO RECEIVES IT: the session spawning the agent, at the moment it spawns it, the one place
# both the cause and the remedy are in reach.
#
# KNOWN LIMITS, by construction:
#   - this file is itself read from the main checkout, so a main checkout on a branch cut before
#     this hook existed runs no check at all;
#   - it compares with origin/<main> as of the last fetch;
#   - a gitignored file among these paths is seen by neither git command;
#   - a printed command can stop, loudly: a pull on a file outside these paths that a half-applied pull
#     wrote, a merge on a conflict, a push with no access, a switch or pull under a cherry-pick or a
#     revert; catch-up or the sandbox can refuse any of them;
#   - one can exit 0 and clear nothing: the clean skips a nested git repository among these paths, and
#     a keep road from a checkout behind main leads to the refusal for what it lacks;
#   - of lib/conf.sh it tests the parse: one that parses and then dies still ends this hook, closed;
#   - of what is under way it reads MERGE_HEAD and rebase-merge, not rebase-apply (`rebase --apply`,
#     `git am`), and a rebase reads as a detached HEAD: stopped with nothing dirty or missing, it gets
#     the note;
#   - remote config and local refs, origin's HEAD and main included, are writable by what they
#     judge: an agent that can write the repository's config or refs can change the answer. This
#     cannot be closed locally; OPS-235 builds the authority lanes cannot write.
#
# Protocol: exit 2 = block (stderr reaches Claude); exit 0 = allow, with
# hookSpecificOutput.additionalContext on stdout as the only exit-0 channel that reaches Claude.
# Checked by .claude/checks/hooks.sh.

nl='
'
root=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || root=""
dir=.claude

# Direct, and needing nothing from lib/conf.sh: the no-origin note must reach Claude without it.
note() {
  echo "worktree-hook-drift: $1" >&2
  _esc=$(printf '%s' "worktree-hook-drift: $1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\t' '  ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$_esc"
  exit 0
}

refuse() {
  {
    echo "BLOCKED by worktree-hook-drift: $1"
    echo "A worktree agent's every hook is read from ${root:-this checkout}, so a merged guard rule may not be in force"
    echo "for it, and this check refuses what it cannot compare. Fix the above, or spawn the agent without worktree isolation."
  } >&2
  exit 2
}

# git's own words for a command that just failed. Run again for them, and only then: on success its
# stderr stays out of the answer, where a sandbox's or a shim's complaint would read as the output.
git_says() { git -C "$root" "$@" 2>&1 >/dev/null | tr '\n' ' '; }

payload=$(cat) || refuse "the payload could not be read, so this check cannot tell whether this is a worktree spawn."

# A worktree spawn only: a non-isolated agent works in this checkout, on the same code its guards
# come from. Matched on the raw JSON: a prompt that merely MENTIONS the key arrives with its quotes
# escaped (\"isolation\"), which this pattern cannot match. A grep that fails is not "no match".
printf '%s\n' "$payload" | grep -Eq '"isolation"[[:space:]]*:[[:space:]]*"worktree"'
case $? in
  0) ;;
  1) exit 0 ;;
  *) refuse "grep failed on the payload, so this check cannot tell whether this is a worktree spawn." ;;
esac

# An inherited variable must not answer for this checkout: git's own list of what locates a repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars 2>/dev/null)

ROOT=$root
# A `.` of a missing or broken file is fatal with a shell-dependent status: test first. A repository
# with no origin needs nothing from it; one with an origin refuses below, saying why.
if [ -f "$(dirname "$0")/../lib/conf.sh" ] && sh -n "$(dirname "$0")/../lib/conf.sh" 2>/dev/null; then
  # shellcheck disable=SC1091
  . "$(dirname "$0")/../lib/conf.sh"
fi

# The checkout itself must answer: not a parent repository, not one core.worktree names. -ef, not a
# comparison of spellings: a symlink, a path's case or its Unicode form makes the same directory read
# differently from git's answer, on a clean checkout.
[ -n "$root" ] || refuse "this hook's own checkout cannot be found."
top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) \
  || refuse "git cannot read a repository at $root, so its hooks cannot be compared with origin's main: $(git_says rev-parse --show-toplevel)"
[ "$top" -ef "$root" ] \
  || refuse "$root is not the top of its repository (git says $top), so git's answers there would be about another checkout."

remotes=$(git -C "$root" remote 2>/dev/null) \
  || refuse "git remote failed in $root, so this check cannot tell whether it has an origin: $(git_says remote)"
case "$nl$remotes$nl" in
  *"${nl}origin$nl"*) ;;
  *) note "CANNOT CHECK whether the hooks guarding this worktree agent match origin's main: ${root} has no remote called origin, so it has no main to lag. Allowed; UNKNOWN, not verified." ;;
esac

# No command: this runs before the status listing and the merge block, so a restore printed here could
# resolve a merge to our side or drop an edit nothing listed.
command -v conf_main_ref >/dev/null 2>&1 \
  || refuse "$root/$dir/lib/conf.sh is missing or does not parse, so this check cannot read origin's main."
# Main is git's own record, origin's HEAD: a branch can edit MAIN_BRANCH (lib/conf.sh).
_ref=$(conf_main_ref) || refuse "$(conf_main_fix)"
base=${_ref#refs/remotes/}
main=${base#origin/}
paths="$dir/hooks $dir/lib $dir/settings.json"

# A failure here would read as a detached HEAD, which the ahead path allows.
branch=$(git -C "$root" branch --show-current 2>/dev/null) \
  || refuse "git branch failed in $root: $(git_says branch --show-current)"

# $paths unquoted on purpose: three pathspecs, none containing a space.
# shellcheck disable=SC2086
indexed=$(git --no-optional-locks -C "$root" ls-files -v -- $paths 2>/dev/null) \
  || refuse "git ls-files failed in $root, so its hook files cannot be compared with $base: $(git_says ls-files -v)"
# `H ` is a plain entry and `M ` a conflict, which status reports as dirty below. Anything else
# (lowercase for assume-unchanged, S for skip-worktree) is one that status and diff cannot be trusted on.
git -C "$root" rev-parse -q --verify HEAD >/dev/null 2>&1 \
  || refuse "$root has no commit yet, so nothing there can be compared with $base."
flagged=""
clear=""
conflict=""
_ifs=$IFS; IFS=$nl; set -f
for _line in $indexed; do
  case $_line in
    "H "*) ;;
    "M "*) conflict=1 ;;
    *)
      flagged="$flagged$nl    $_line"
      clear="$clear$nl  \$ git -C \"$root\" update-index --no-assume-unchanged -- \"${_line#? }\""
      clear="$clear$nl  \$ git -C \"$root\" update-index --no-skip-worktree -- \"${_line#? }\""
      ;;
  esac
done
IFS=$_ifs; set +f
[ -z "$flagged" ] || refuse "git's index marks these hook files in $root, and an assume-unchanged or skip-worktree flag hides an edit from every comparison:$flagged
Clear both flags, then see what they hid:$clear"

# shellcheck disable=SC2086
dirty=$(git --no-optional-locks -C "$root" status --porcelain --untracked-files=all -- $paths 2>/dev/null) \
  || refuse "git status failed in $root, so its hook files cannot be compared with $base: $(git_says status --porcelain)"
# shellcheck disable=SC2086
git -C "$root" diff --quiet "$base" -- $paths 2>/dev/null
rc=$?
[ "$rc" -le 1 ] || refuse "git diff against $base failed (exit $rc) in $root, so its hook files cannot be compared: $(git_says diff --quiet "$base")"
# The diff reads tracked files only: an untracked one is outside what "identical" just said.
untracked=""
case "$nl$dirty" in *"$nl??"*) untracked=1 ;; esac
[ "$rc" -ne 0 ] || [ -n "$untracked" ] || exit 0

# shellcheck disable=SC2086
missing=$(git -C "$root" log --format='    %h %s' "HEAD..$base" -- $paths 2>/dev/null) \
  || refuse "git log against $base failed in $root, so it cannot say which hook commits that checkout lacks: $(git_says log -1 "HEAD..$base")"

# Only the words change: each of these three states refuses below anyway, with commands git would stop
# during a merge or a rebase. No command here: an abort drops work the refusal never listed.
gitdir=$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)
op=""
[ ! -f "$gitdir/MERGE_HEAD" ] || op=merge
[ ! -d "$gitdir/rebase-merge" ] || op=rebase
if [ -n "$op" ] && { [ -n "$dirty" ] || [ -n "$missing" ] || [ "$branch" = "$main" ]; }; then
  refuse "a $op is in progress in $root, so no commit says its hook files are what $base holds. Finishing it by hand and spawning again keeps the work; an abort drops its resolutions and can drop edits made since the stop."
fi

# Name only what each command can take: git refuses a whole pathspec list for one its source lacks.
ours=""
heads=""
same=1
for _p in $paths; do
  _inhead=""
  git -C "$root" cat-file -e "HEAD:$_p" 2>/dev/null && _inhead=1
  if git -C "$root" cat-file -e "$base:$_p" 2>/dev/null; then [ -n "$_inhead" ] || same=""
  else [ -z "$_inhead" ] || same=""
  fi
  [ -z "$_inhead" ] || heads="$heads $_p"
  if [ -e "$root/$_p" ] || [ -n "$_inhead" ]; then ours="$ours $_p"; fi
done

if [ -n "$dirty" ]; then
  # From HEAD, not from main: a discard takes what is uncommitted and leaves committed work alone.
  # None where HEAD holds none of these paths: on an uncommitted install it would delete the guards.
  discard=""
  if [ -n "$heads" ]; then
    discard="To discard them, leaving commits alone:$nl  \$ git -C \"$root\" restore --source=HEAD --staged --worktree --$heads"
    [ -z "$untracked" ] || discard="$discard$nl  \$ git -C \"$root\" clean -f -- $paths"
    discard="$discard$nl"
  fi
  keep="$nl  \$ git -C \"$root\" add --$ours$nl  \$ git -C \"$root\" commit -m <message>"
  if [ "$branch" = "$main" ]; then
    keep="To keep them (a stridal update lands here), move them to a branch and commit there, as $main takes no commit no review has seen:$nl  \$ git -C \"$root\" switch -c <branch>$keep"
    # Only strictly behind: ahead, a fast-forward pull has nothing to do or cannot run.
    if [ -n "$discard" ] && [ -z "$conflict" ] && [ -z "$(git -C "$root" rev-list -1 "$base..HEAD" 2>/dev/null)" ] && [ -n "$(git -C "$root" rev-list -1 "HEAD..$base" 2>/dev/null)" ]; then
      discard="${discard}Then pull (it stops on any other file a half-applied pull wrote, which is yours to clear):$nl  \$ git -C \"$root\" pull --ff-only origin $main$nl"
    fi
  else
    keep="To keep them:$keep"
  fi
  # A commit from here would commit the conflict markers into a guard.
  [ -z "$conflict" ] || keep=""
  refuse "these hook files in $root are uncommitted, so no commit says they are what $base holds:
$(printf '%s\n' "$dirty" | sed 's/^/    /')
$discard$keep"
fi

if [ -z "$missing" ]; then
  run_main=""
  [ -z "$same" ] || run_main="${nl}To run $base's code here instead, restore its files. The commits stay on $main, so a commit from here would reverse them:$nl  \$ git -C \"$root\" restore --source=$base --staged --worktree --$heads"
  [ "$branch" != "$main" ] || refuse "$root is on $main and holds hook commits $base does not, so no review has seen the code that would judge the agent.
To keep them, move them to a branch and push it for a PR:
  \$ git -C \"$root\" switch -c <branch>
  \$ git -C \"$root\" push -u origin <branch>$run_main"
  note "the hooks that will guard this worktree agent are read from $root on '${branch:-detached HEAD}', whose .claude/hooks, .claude/lib or settings.json differ from $base without lacking any merged commit: that checkout's OWN unmerged hook code will judge the agent's commands. Allowed."
fi

# shellcheck disable=SC2086
files=$(git -C "$root" diff --name-only "$base" -- $paths 2>/dev/null | sed 's/^/    /')
{
  echo "BLOCKED by worktree-hook-drift: a worktree agent is cut from $base, but every hook that guards it is"
  echo "read from $root, which is on '${branch:-detached HEAD}' and lacks these hook commits from $base:"
  echo "$missing"
  echo "Differing files:"
  echo "$files"
  echo "Until that checkout carries them, the agent is guarded by the OLD hook code: a merged guard rule is"
  echo "not in force for it. Or spawn the agent without worktree isolation."
  echo "To bring it up to date:"
  echo "  \$ git -C \"$root\" merge $base"
} >&2
exit 2
