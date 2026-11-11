#!/usr/bin/env bash
# shellcheck disable=SC2016  # the hook cases pass single-quoted CHECK snippets that hook_case_ evals
# Self-test for session.sh. Run: bash .claude/bin/test-session.sh (from any cwd).
# Everything happens in a throwaway repo under mktemp -d; the real repo is never touched.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/test-session.XXXXXX")   # macOS's bare mktemp -d ignores $TMPDIR
LIVE="" LIVE2=""
trap 'rm -rf "$T"; [ -z "$LIVE$LIVE2" ] || kill $LIVE $LIVE2 2>/dev/null' EXIT
total=0; fail=0

# Setup, in one place: a repo with one empty commit and a copy of session.sh. Later cases append below.
git init -q "$T/repo"
git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$T/repo/.claude/bin" "$T/repo/.claude/review"
cp "$here/session.sh" "$T/repo/.claude/bin/session.sh" 2>/dev/null
cp "$here/as-agent.sh" "$T/repo/.claude/bin/as-agent.sh" 2>/dev/null
cd "$T/repo" || exit 1
SESSION="$T/repo/.claude/bin/session.sh"

# [out2=TEXT] case_ NAME WANT_EXIT WANT_OUTPUT_SUBSTRING ARGS...
# Runs session.sh ARGS in the throwaway repo; the output must contain the substring (and out2, if set).
case_() {
  local name=$1 want=$2 out=$3; shift 3
  total=$((total+1))
  local o; o=$(bash "$SESSION" "$@" 2>&1)
  local got=$?
  if [ "$got" != "$want" ]; then fail=$((fail+1)); echo "FAIL $name: want exit $want, got $got ($o)"
  elif [[ "$o" != *"$out"* ]]; then fail=$((fail+1)); echo "FAIL $name: output lacks '$out': $o"
  elif [[ "$o" != *"${out2:-}"* ]]; then fail=$((fail+1)); echo "FAIL $name: output lacks '$out2': $o"; fi
}

# Shims: ps passes through and appends one fake Ghostty line, and fails on its PS_FAIL_ON-th call;
# osascript answers "1 window"; claude exists. They let the real-run paths of open and close be reached.
SHIM=$T/shim; mkdir -p "$SHIM"
export REALPS PSCOUNT="$T/pscount"
REALPS=$(command -v ps)
cat > "$SHIM/ps" <<'EOS'
#!/bin/sh
n=0; [ -f "$PSCOUNT" ] && n=$(cat "$PSCOUNT"); n=$((n+1)); echo "$n" > "$PSCOUNT"
[ "$n" = "${PS_FAIL_ON:-0}" ] && exit 1
"$REALPS" "$@" | grep -v "Ghostty.app/Contents/MacOS/ghostty$"; echo /Applications/Ghostty.app/Contents/MacOS/ghostty
EOS
printf '#!/bin/sh\necho 1\n' > "$SHIM/osascript"
printf '#!/bin/sh\nexit 0\n' > "$SHIM/claude"
chmod +x "$SHIM/ps" "$SHIM/osascript" "$SHIM/claude"
git init -q --bare "$T/origin.git"
git -C "$T/repo" remote add origin "$T/origin.git"
echo hi > .claude/review/spawn-demo.md
echo hi > "$T/elsewhere.md"
ln -s "$T/elsewhere.md" .claude/review/spawn-ln.md
head -c 20481 /dev/zero | tr '\0' x > .claude/review/spawn-big.md

out2="--name acme-demo" case_ "open dry-run ok" 0 "branch: feat/demo (new, from origin/main)" open feat demo --key acme --report-to dispatch-acme --dry-run
case_ "open bad type" 2 "refused" open feature demo --key acme --report-to dispatch-acme --dry-run
case_ "open bad slug" 2 "slug must match" open feat ../x --key acme --report-to dispatch-acme --dry-run
case_ "open no prompt" 2 "no prompt file" open feat nope --key acme --report-to dispatch-acme --dry-run
case_ "open symlinked prompt" 2 "symlink" open feat ln --key acme --report-to dispatch-acme --dry-run
case_ "open oversize prompt" 2 "over 20 KB" open feat big --key acme --report-to dispatch-acme --dry-run
case_ "open no report-to" 2 "--report-to" open feat demo --key acme --dry-run
case_ "open without --key refused" 2 "open needs --key" open feat demo --report-to dispatch-acme --dry-run
case_ "open bad key" 2 "--key must match" open feat demo --key Acme --report-to dispatch-acme --dry-run
case_ "open key with a digit first refused" 2 "--key must match" open feat demo --key 1acme --report-to dispatch-acme --dry-run
case_ "open key with a metacharacter refused" 2 "--key must match" open feat demo --key 'a;b' --report-to dispatch-acme --dry-run
out2="(recorded in" case_ "open dry-run: names the session <key>-<slug>" 0 "session name: acme-demo" open feat demo --key acme --report-to dispatch-acme --dry-run
out2="BLOCKED:" case_ "open dry-run: report line names the contract formats" 0 "report line: When you finish, or stop for any reason, SendMessage the session named dispatch-acme. Start the message with RESULT pr=<n> lane=<k>" open feat demo --key acme --report-to dispatch-acme --dry-run
case_ "close dry-run" 0 "git worktree remove" close demo --dry-run
# The tab command is the same on every machine: a toolchain dir under HOME (here a bun install) never reaches it.
# (A project whose worker needs one adds it to its own login profile.)
mkdir -p "$T/hb/.bun/bin"
printf '#!/bin/sh\n' > "$T/hb/.bun/bin/bun"; chmod +x "$T/hb/.bun/bin/bun"
HOME="$T/hb" out2="-lc 'exec " case_ "open dry-run: a bun dir does not change the tab command" 0 "tab command: " open feat demo --key acme --report-to dispatch-acme --dry-run
total=$((total+1))
if HOME="$T/hb" bash "$SESSION" open feat demo --key acme --report-to dispatch-acme --dry-run 2>&1 | grep -q '\.bun'; then
  fail=$((fail+1)); echo "FAIL open dry-run: the tab command names .bun"
fi
# send and sync retired with the hand-run skills (#432, #438): they are unknown commands now.
case_ "send refused as an unknown command" 2 "first argument must be open, close, watch, notified, clear or name" send demo ship --dry-run
case_ "sync refused as an unknown command" 2 "first argument must be open, close, watch, notified, clear or name" sync --dry-run
mkdir -p .git/spawn
touch .git/spawn/demo.waiting
case_ "watch: marker present -> waiting" 0 "waiting demo" watch demo --timeout 5
case_ "watch: unknown slug -> exited" 0 "exited ghost" watch ghost --timeout 5
case_ "watch: bad slug refused" 2 "slug must match" watch ../x
case_ "watch: bad timeout refused" 2 "refused" watch demo --timeout abc
case_ "close dry-run: refuses while waiting" 0 ".waiting or .notified exists and claude --name demo is running" close demo --dry-run

# A live process whose argv reads "claude --name live" (bash exec -a works on macOS and Linux).
bash -c 'exec -a "claude --name live" sleep 60' &
LIVE=$!
sleep 1
# assert_ NAME CHECK   (CHECK is a shell snippet that must succeed)
assert_() {
  total=$((total+1))
  if ! eval "$2"; then fail=$((fail+1)); echo "FAIL $1: check failed: $2"; fi
}
case_ "watch: live worker, no marker -> timeout" 3 "timeout live" watch live --timeout 1
touch .git/spawn/live.waiting
case_ "watch: live worker with marker -> waiting wins" 0 "waiting live" watch live --timeout 1
# Real-path close refuses before any Ghostty check, so no osascript is reached.
echo t1 > .git/spawn/live.term
PATH="$SHIM:$PATH" case_ "close: live worker waiting on a prompt -> refused" 2 "waiting on a prompt" close live --abandon
rm -f .git/spawn/live.waiting .git/spawn/live.term

# notified/clear: the dispatcher swaps .waiting for .notified before it pushes, so close's guard never lapses.
touch .git/spawn/live.waiting
case_ "notified: moves .waiting to .notified" 0 "notified live" notified live
assert_ "notified: .waiting gone, .notified present" '[ ! -e .git/spawn/live.waiting ] && [ -e .git/spawn/live.notified ]'
case_ "notified: no .waiting -> creates .notified anyway" 0 "notified ghost" notified ghost
assert_ "notified: ghost.notified created" '[ -e .git/spawn/ghost.notified ]'
rm -f .git/spawn/ghost.notified
echo t1 > .git/spawn/live.term
PATH="$SHIM:$PATH" case_ "close: live worker with only .notified -> refused" 2 "waiting on a prompt" close live --abandon
rm -f .git/spawn/live.term
case_ "clear: removes .notified" 0 "cleared live" clear live
assert_ "clear: .notified gone" '[ ! -e .git/spawn/live.notified ]'
case_ "clear: nothing present -> exit 0" 0 "cleared live" clear live
case_ "notified: bad slug refused" 2 "slug must match" notified ../x
case_ "clear: bad slug refused" 2 "slug must match" clear ../x

# --- notify-waiting.sh hook cases ---
HOOK="$here/../hooks/notify-waiting.sh"
git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/demo" -b feat/demo
git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/plain" -b feat/plain
G=$T/repo/.git
mkdir -p "$G/spawn" "$T/repo/.claude/worktrees/demo/src"
echo t1 > "$G/spawn/demo.term"
rm -f "$G/spawn/demo.waiting"

# hook_case_ NAME STDIN CHECK   (CHECK is a shell snippet run after the hook; it must succeed)
hook_case_() {
  local name=$1 json=$2 check=$3 o got
  total=$((total+1))
  o=$(printf '%s' "$json" | NOTIFY_WAITING_NO_DESKTOP=1 sh "$HOOK" 2>&1)
  got=$?
  if [ "$got" != 0 ]; then fail=$((fail+1)); echo "FAIL $name: want exit 0, got $got ($o)"
  elif ! eval "$check"; then fail=$((fail+1)); echo "FAIL $name: check failed: $check"; fi
}

hook_case_ "hook: spawned worktree -> marker" "{\"cwd\":\"$T/repo/.claude/worktrees/demo\"}" '[ -f "$G/spawn/demo.waiting" ]'
rm -f "$G/spawn/demo.waiting"
hook_case_ "hook: subdir of spawned worktree -> marker" "{\"cwd\":\"$T/repo/.claude/worktrees/demo/src\"}" '[ -f "$G/spawn/demo.waiting" ]'
hook_case_ "hook: worktree without .term -> no marker" "{\"cwd\":\"$T/repo/.claude/worktrees/plain\"}" '[ ! -e "$G/spawn/plain.waiting" ]'
rm -f "$G/spawn/demo.waiting"
hook_case_ "hook: main checkout -> nothing" "{\"cwd\":\"$T/repo\"}" '[ -z "$(ls "$G/spawn" | grep waiting)" ]'
hook_case_ "hook: garbage stdin -> exit 0" 'not json' '[ "$(ls "$G/spawn")" = demo.term ]'
hook_case_ "hook: empty stdin -> exit 0" '' '[ "$(ls "$G/spawn")" = demo.term ]'
total=$((total+1))
o=$(printf '%s' "{\"cwd\":\"$T/repo/.claude/worktrees/demo\"}" | NOTIFY_WAITING_NO_DESKTOP=1 sh "$HOOK" 2>/dev/null)
if [ -n "$o" ]; then fail=$((fail+1)); echo "FAIL hook: stdout is empty: got '$o'"; fi

# --- ps failure, close cleanup of .waiting, open refusing a stale .waiting, hook path and slug checks ---
SP=$G/spawn

# ps failure is its own outcome, never "exited" or "not running".
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" PS_FAIL_ON=1 case_ "watch: ps failure -> exit 4" 4 "error ghost: ps failed" watch ghost --timeout 5
git -C "$T/repo" branch feat/pf
git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/pf" feat/pf
echo feat/pf > "$SP/pf.branch"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" PS_FAIL_ON=2 case_ "close: ps failure -> refused, nothing removed" 2 "cannot tell whether claude --name pf" close pf --abandon
assert_ "close: ps failure keeps the branch record" '[ -e "$SP/pf.branch" ] && [ -d "$T/repo/.claude/worktrees/pf" ]'
git -C "$T/repo" worktree remove "$T/repo/.claude/worktrees/pf"; git -C "$T/repo" branch -D feat/pf -q; rm -f "$SP/pf.branch"
git -C "$T/repo" branch feat/live
echo feat/live > "$SP/live.branch"; echo t1 > "$SP/live.term"; touch "$SP/live.waiting"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" PS_FAIL_ON=1 case_ "close: ps failure in the waiting check -> refused by is_running" 2 "cannot tell whether claude --name live" close live --abandon
rm -f "$SP"/live.*; git -C "$T/repo" branch -D feat/live -q
# The Ghostty-count step has its own message, so the cases above cannot pass on the wrong ps call.
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" PS_FAIL_ON=1 case_ "close: ps failure at the Ghostty count -> its own message" 2 "ps failed listing Ghostty" close nobody --abandon
# The gone path: no waiting marker, so ps call 1 is the Ghostty count and call 2 is the gone path's is_running.
echo feat/gonepf > "$SP/gonepf.branch"; echo t1 > "$SP/gonepf.term"; mkdir -p "$SP/locks/gonepf"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" PS_FAIL_ON=2 case_ "close (gone): ps failure -> refused, records kept" 2 "cannot tell whether claude --name gonepf" close gonepf
assert_ "close (gone): ps failure keeps the spawn records and lock" '[ -e "$SP/gonepf.branch" ] && [ -e "$SP/gonepf.term" ] && [ -d "$SP/locks/gonepf" ]'
rm -rf "$SP"/gonepf.* "$SP/locks/gonepf"

# Each close cleanup path removes .waiting and .notified along with the other spawn records.
echo feat/gone1 > "$SP/gone1.branch"; touch "$SP/gone1.waiting" "$SP/gone1.notified" "$SP/gone1.term"; mkdir -p "$SP/locks/gone1"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" case_ "close: worktree and branch gone" 0 "closed gone1" close gone1
assert_ "close (gone) removes .waiting and .notified" '[ ! -e "$SP/gone1.waiting" ] && [ ! -e "$SP/gone1.notified" ] && [ ! -e "$SP/gone1.branch" ] && [ ! -e "$SP/locks/gone1" ]'
touch "$SP/nore.waiting" "$SP/nore.notified" "$SP/nore.term"; mkdir -p "$SP/locks/nore"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" case_ "close --abandon: no branch record" 0 "closed nore" close nore --abandon
assert_ "close (no record) removes .waiting and .notified" '[ ! -e "$SP/nore.waiting" ] && [ ! -e "$SP/nore.notified" ] && [ ! -e "$SP/locks/nore" ]'
git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/full" -b feat/full
echo feat/full > "$SP/full.branch"; touch "$SP/full.waiting" "$SP/full.notified" "$SP/full.term"; mkdir -p "$SP/locks/full"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" case_ "close --abandon: full close" 0 "closed full" close full --abandon
assert_ "close (full) removes .waiting and .notified" '[ ! -e "$SP/full.waiting" ] && [ ! -e "$SP/full.notified" ] && [ ! -e "$SP/full.branch" ] && [ ! -e "$T/repo/.claude/worktrees/full" ]'

# open refuses a stale .waiting left by an earlier worker on the slug, before it takes a lock or fetches.
echo hi > .claude/review/spawn-stale.md
touch "$SP/stale.waiting"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" case_ "open: stale .waiting -> refused" 2 "spawn files for stale already exist" open feat stale --key acme --report-to dispatch-acme
assert_ "open: stale .waiting leaves no lock or branch" '[ ! -e "$SP/locks/stale" ] && ! git -C "$T/repo" show-ref --verify --quiet refs/heads/feat/stale'
rm -f "$SP/stale.waiting"
touch "$SP/stale.notified"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" case_ "open: stale .notified -> refused" 2 "spawn files for stale already exist" open feat stale --key acme --report-to dispatch-acme
assert_ "open: stale .notified leaves no lock or branch" '[ ! -e "$SP/locks/stale" ] && ! git -C "$T/repo" show-ref --verify --quiet refs/heads/feat/stale'
rm -f "$SP/stale.notified"

# Hook: path check (a .term for a repo outside .claude/worktrees) and slug check (a name that fails the regex).
mkdir -p "$T/outside" && git init -q "$T/outside/demo"
mkdir -p "$T/outside/demo/.git/spawn"; echo t1 > "$T/outside/demo/.git/spawn/demo.term"
hook_case_ "hook: repo outside .claude/worktrees -> no marker" "{\"cwd\":\"$T/outside/demo\"}" '[ ! -e "$T/outside/demo/.git/spawn/demo.waiting" ]'
git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/Bad_Name" -b feat/badname
echo t1 > "$G/spawn/Bad_Name.term"
hook_case_ "hook: worktree name failing the slug regex -> no marker" "{\"cwd\":\"$T/repo/.claude/worktrees/Bad_Name\"}" '[ ! -e "$G/spawn/Bad_Name.waiting" ]'

# --- as-agent.sh: the token comes from a fake security (AS_AGENT_SECURITY), never the real Keychain ---
AS="$here/as-agent.sh"
FS=$T/fakesec; mkdir -p "$FS"
printf '#!/bin/sh\necho tok123\n' > "$FS/ok"
printf '#!/bin/sh\nexit 44\n' > "$FS/fail"
printf '#!/bin/sh\nexit 0\n' > "$FS/empty"
chmod +x "$FS/ok" "$FS/fail" "$FS/empty"
export XDG_CONFIG_HOME="$T/xdg"
# as_case_ NAME SECURITY WANT_EXIT WANT_OUTPUT_SUBSTRING ARGS...
as_case_() {
  local name=$1 sec=$2 want=$3 out=$4; shift 4
  total=$((total+1))
  local o; o=$(AS_AGENT_SECURITY="$FS/$sec" bash "$AS" "$@" 2>&1)
  local got=$?
  if [ "$got" != "$want" ]; then fail=$((fail+1)); echo "FAIL $name: want exit $want, got $got ($o)"
  elif [[ "$o" != *"$out"* ]]; then fail=$((fail+1)); echo "FAIL $name: output lacks '$out': $o"; fi
}
as_case_ "as-agent: token and git helper in the env" ok 0 "tok123 !gh auth git-credential" svc sh -c 'echo $GH_TOKEN $GIT_CONFIG_VALUE_1'
as_case_ "as-agent: helper reset first" ok 0 "2 credential.https://github.com.helper [] 0" svc sh -c 'echo $GIT_CONFIG_COUNT $GIT_CONFIG_KEY_0 [$GIT_CONFIG_VALUE_0] $GIT_TERMINAL_PROMPT'
as_case_ "as-agent: own gh config dir" ok 0 "$T/xdg/gh-agent-svc" svc sh -c 'echo $GH_CONFIG_DIR'
assert_ "as-agent: gh config dir is mode 700" '[ "$(ls -ld "$T/xdg/gh-agent-svc" | cut -c1-10)" = drwx------ ]'
rm -f "$T/ran"
as_case_ "as-agent: Keychain read fails -> refused" fail 2 "refused" svc sh -c "touch $T/ran"
assert_ "as-agent: Keychain failure never runs the command" '[ ! -e "$T/ran" ]'
as_case_ "as-agent: empty token -> refused" empty 2 "refused" svc sh -c "touch $T/ran"
assert_ "as-agent: empty token never runs the command" '[ ! -e "$T/ran" ]'
as_case_ "as-agent: bad service refused" ok 2 "refused" 'a;b' sh -c "touch $T/ran"
assert_ "as-agent: bad service never runs the command" '[ ! -e "$T/ran" ]'
as_case_ "as-agent: no command refused" ok 2 "refused" svc
total=$((total+1))
if AS_AGENT_SECURITY="$FS/ok" bash "$AS" svc sh -c 'echo "$0 $*"' 2>&1 | grep -q tok123; then
  fail=$((fail+1)); echo "FAIL as-agent: the token reached the command's argv"
fi

# --- session.sh open --agent-keychain wraps the worker's claude in as-agent.sh ---
out2="--name acme-demo" case_ "open dry-run: --agent-keychain wraps claude" 0 "repo/.claude/bin/as-agent.sh svc " open feat demo --key acme --report-to dispatch-acme --agent-keychain svc --dry-run
total=$((total+1))
if bash "$SESSION" open feat demo --key acme --report-to dispatch-acme --agent-keychain svc --dry-run 2>&1 | grep -q 'GH_TOKEN'; then
  fail=$((fail+1)); echo "FAIL open dry-run: --agent-keychain tab command names GH_TOKEN"
fi
case_ "open: --agent-keychain with a space refused" 2 "--agent-keychain must match" open feat demo --key acme --report-to dispatch-acme --agent-keychain 'x y' --dry-run
case_ "open: --agent-keychain with a metacharacter refused" 2 "--agent-keychain must match" open feat demo --key acme --report-to dispatch-acme --agent-keychain 'x;y' --dry-run
case_ "open: --agent-keychain without a value refused" 2 "--agent-keychain needs" open feat demo --key acme --report-to dispatch-acme --agent-keychain
total=$((total+1))
if bash "$SESSION" open feat demo --key acme --report-to dispatch-acme --dry-run 2>&1 | grep -q 'as-agent.sh'; then
  fail=$((fail+1)); echo "FAIL open dry-run: without --agent-keychain the tab command names as-agent.sh"
fi

# --- close of a merged PR (no --abandon): a fake gh (GH_PR_OUT) and refs/pull/<n>/head in the local bare origin ---
printf '#!/bin/sh\nprintf "%%s\\n" "$GH_PR_OUT"\n' > "$SHIM/gh"; chmod +x "$SHIM/gh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# mk_merged_ SLUG: a worktree on feat/SLUG with one commit of its own, and its spawn record; prints that commit.
mk_merged_() {
  git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/$1" -b "feat/$1"
  git -C "$T/repo/.claude/worktrees/$1" commit -q --allow-empty -m "work $1"
  echo "feat/$1" > "$SP/$1.branch"
  git -C "$T/repo" rev-parse "feat/$1"
}
# Same head: closes as before.
h=$(mk_merged_ same)
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" GH_PR_OUT="MERGED $h 5" case_ "close: merged PR at the local head -> closed" 0 "closed same" close same
# update-branch: the PR head is a merge commit on top of the local branch, reachable as refs/pull/7/head.
h=$(mk_merged_ upd)
m=$(git -C "$T/repo" commit-tree "$h^{tree}" -p "$h" -p "$(git -C "$T/repo" rev-parse --verify HEAD)" -m "Merge main into feat/upd")
git -C "$T/repo" push -q origin "$m:refs/pull/7/head"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" GH_PR_OUT="MERGED $m 7" case_ "close: merged head contains the local branch (update-branch) -> closed" 0 "closed upd" close upd
assert_ "close (update-branch): worktree and branch removed" '[ ! -e "$T/repo/.claude/worktrees/upd" ] && ! git -C "$T/repo" show-ref --verify --quiet refs/heads/feat/upd'
# The merged head lacks the local commit: unpushed work, refused, nothing removed.
h=$(mk_merged_ lost)
o=$(git -C "$T/repo" commit-tree "$h^{tree}" -m "other work")
git -C "$T/repo" push -q origin "$o:refs/pull/8/head"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" GH_PR_OUT="MERGED $o 8" case_ "close: merged head lacks the local commit -> refused" 2 "unpushed or different commits" close lost
assert_ "close (lost): worktree and branch kept" '[ -d "$T/repo/.claude/worktrees/lost" ] && git -C "$T/repo" show-ref --verify --quiet refs/heads/feat/lost'
# The heads differ and refs/pull/<n>/head can't be fetched: refused.
h=$(mk_merged_ nofetch)
m=$(git -C "$T/repo" commit-tree "$h^{tree}" -p "$h" -m "Merge main into feat/nofetch")
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" GH_PR_OUT="MERGED $m 9" case_ "close: merged head can't be fetched -> refused" 2 "unpushed or different commits" close nofetch
assert_ "close (nofetch): worktree and branch kept" '[ -d "$T/repo/.claude/worktrees/nofetch" ] && git -C "$T/repo" show-ref --verify --quiet refs/heads/feat/nofetch'
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" GH_PR_OUT="OPEN $h 9" case_ "close: PR not merged -> refused" 2 "not MERGED" close nofetch

# --- session names: legacy fallback, a tampered record ---
case_ "name: no record -> the bare slug (a worker opened before records)" 0 "ghost" name ghost
printf 'acme-rec\n' > "$SP/rec.session"
case_ "name: the recorded name" 0 "acme-rec" name rec
printf 'acme-other\n' > "$SP/rec.session"
case_ "name: a record for another slug refused" 2 "does not hold a session name" name rec
case_ "watch: a bad record refused, never read as exited" 2 "does not hold a session name" watch rec --timeout 1
printf 'x;y-rec\n' > "$SP/rec.session"
case_ "name: a record with a metacharacter refused" 2 "does not hold a session name" name rec
rm -f "$SP/rec.session"; ln -s "$T/elsewhere.md" "$SP/rec.session"
case_ "name: a symlinked record refused" 2 "not a regular file" name rec
rm -f "$SP/rec.session"
case_ "name: bad slug refused" 2 "slug must match" name ../x

# --- two repos, the same issue number: names differ, and one repo's watch/close ignores the other's worker ---
# mkrepo_ DIR: a repo with main on a local bare origin, a copy of session.sh and a brief for slug 12-fix-x.
mkrepo_() {
  git init -q "$1"; git -C "$1" commit -q --allow-empty -m init
  git init -q --bare "$1.origin.git"; git -C "$1" remote add origin "$1.origin.git"
  git -C "$1" push -q origin HEAD:refs/heads/main
  mkdir -p "$1/.claude/bin" "$1/.claude/review"
  cp "$here/session.sh" "$1/.claude/bin/session.sh"
  echo brief > "$1/.claude/review/spawn-12-fix-x.md"
}
mkrepo_ "$T/ra"; mkrepo_ "$T/rb"
# in_ DIR case_ ARGS...: case_ run with DIR as the cwd and its own session.sh.
in_() { local d=$1; shift; (cd "$d" && SESSION="$d/.claude/bin/session.sh" && "$@"; echo "$total $fail" > "$T/counts"); read -r total fail < "$T/counts"; }
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" in_ "$T/ra" case_ "two repos: open in A" 0 "opened fix/12-fix-x" open fix 12-fix-x --key ra --report-to dispatch-ra
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" in_ "$T/rb" case_ "two repos: open in B" 0 "opened feat/12-fix-x" open feat 12-fix-x --key rb --report-to dispatch-rb
assert_ "two repos: A records ra-12-fix-x" '[ "$(cat "$T/ra/.git/spawn/12-fix-x.session")" = ra-12-fix-x ]'
assert_ "two repos: B records rb-12-fix-x" '[ "$(cat "$T/rb/.git/spawn/12-fix-x.session")" = rb-12-fix-x ]'
assert_ "two repos: each brief reports to its own dispatcher" 'grep -q "session named dispatch-ra\. Start the message with RESULT" "$T/ra/.git/spawn/12-fix-x.prompt" && grep -q "session named dispatch-rb\. Start the message with RESULT" "$T/rb/.git/spawn/12-fix-x.prompt"'
in_ "$T/ra" case_ "two repos: name in A" 0 "ra-12-fix-x" name 12-fix-x
# Only B's worker runs.
bash -c 'exec -a "claude --name rb-12-fix-x" sleep 60' &
LIVE2=$!
sleep 1
in_ "$T/rb" case_ "two repos: B's watch sees its worker" 3 "timeout 12-fix-x" watch 12-fix-x --timeout 1
in_ "$T/ra" case_ "two repos: A's watch ignores B's worker" 0 "exited 12-fix-x" watch 12-fix-x --timeout 1
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" in_ "$T/ra" case_ "two repos: A's close ignores B's worker" 0 "closed 12-fix-x" close 12-fix-x --abandon
assert_ "two repos: A's records gone, B's kept" '[ ! -e "$T/ra/.git/spawn/12-fix-x.session" ] && [ -e "$T/rb/.git/spawn/12-fix-x.session" ] && [ -d "$T/rb/.claude/worktrees/12-fix-x" ]'
# B's close sees its own live worker: it would type /exit (the osascript shim does nothing) and wait for it to end.
kill "$LIVE2" 2>/dev/null; wait "$LIVE2" 2>/dev/null
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" in_ "$T/rb" case_ "two repos: B's close after its worker ended" 0 "closed 12-fix-x" close 12-fix-x --abandon

# --- open fails after the prompt snapshot (git fetch fails): the lock and the prompt copy both go, so a retry works ---
mkrepo_ "$T/rc"
git -C "$T/rc" remote set-url origin "$T/no-such-origin.git"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" in_ "$T/rc" case_ "open: fetch fails -> non-zero exit" 128 "" open fix 12-fix-x --key rc --report-to dispatch-rc
assert_ "open: fetch fails -> no prompt copy and no lock left" '[ ! -e "$T/rc/.git/spawn/12-fix-x.prompt" ] && [ ! -e "$T/rc/.git/spawn/locks/12-fix-x" ]'
git -C "$T/rc" remote set-url origin "$T/rc.origin.git"
rm -f "$PSCOUNT"; PATH="$SHIM:$PATH" in_ "$T/rc" case_ "open: retry after the fetch failure -> opened" 0 "opened fix/12-fix-x" open fix 12-fix-x --key rc --report-to dispatch-rc

echo "$((total-fail))/$total passed"
[ "$fail" = 0 ]
