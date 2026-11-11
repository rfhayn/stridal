#!/usr/bin/env bash
# Self-test for dispatch.sh, the one-command dispatcher launcher. Run: bash .claude/bin/test-launcher.sh (from any cwd).
# Everything is generated in a throwaway mktemp -d: a tiny git repo on main with a CLAUDE.md, a stub ps (DISPATCH_PS)
# and a stub exec (DISPATCH_EXEC) that records its argv and cwd. Nothing real is started and gh is never called.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAUNCH=${LAUNCHER_UNDER_TEST:-$here/dispatch.sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-launcher.XXXXXX")   # macOS's bare mktemp -d ignores $TMPDIR
trap 'rm -rf "$T"' EXIT
total=0; fail=0
bad() { fail=$((fail+1)); echo "FAIL $1"; }

# The stubs. exec stub: argv one per line to $STUB_DIR/argv, cwd to $STUB_DIR/cwd. ps stub: prints $STUB_DIR/ps.txt.
cat > "$T/exec-stub" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$STUB_DIR/argv"
pwd -P > "$STUB_DIR/cwd"
STUB
cat > "$T/ps-stub" <<'STUB'
#!/bin/sh
cat "$STUB_DIR/ps.txt"
STUB
chmod +x "$T/exec-stub" "$T/ps-stub"
export STUB_DIR="$T" DISPATCH_EXEC="$T/exec-stub" DISPATCH_PS="$T/ps-stub"
: > "$T/ps.txt"

# repo NAME LINE... -> $T/NAME, a git repo on main holding a CLAUDE.md with that ## Dispatcher block and the real parser
repo() {
  local r=$T/$1; shift
  mkdir -p "$r/.claude/bin"
  { printf '# Repo\n\n## Dispatcher\n'; printf '%s\n' "$@"; } > "$r/CLAUDE.md"
  cp "$here/dispatch-next.sh" "$r/.claude/bin/dispatch-next.sh"
  git -C "$r" init -q -b main
  git -C "$r" -c user.name=t -c user.email=t@t add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -q -m init
}
# run DIR -> runs the launcher from DIR; sets rc; stdout in $T/out, stderr in $T/err; clears the stub records first
run() {
  rm -f "$T/argv" "$T/cwd"
  (cd "$1" && bash "$LAUNCH") >"$T/out" 2>"$T/err"; rc=$?
}
# expect_refuse NAME DIR PATTERN -> exit 2, nothing exec'd, stderr matches PATTERN
expect_refuse() {
  total=$((total+1)); run "$2"
  [ "$rc" = 2 ] || bad "$1: exit $rc, want 2"
  [ ! -e "$T/argv" ] || bad "$1: it started claude anyway"
  grep -qiE "$3" "$T/err" || bad "$1: stderr lacks /$3/: $(cat "$T/err")"
}

GOOD=("- Name: alpha · Project: acme #2 · Approver: acme · max_workers: 1"
      "- Agent: acme-bot · Agent keychain: acme-bot-token")

# 1. refuses off main
repo offmain "${GOOD[@]}"
git -C "$T/offmain" switch -q -c feat/x
expect_refuse "off main" "$T/offmain" 'main'

# 2. refuses when dispatch-<key> already runs (the match ends at a space or the line's end)
repo running "${GOOD[@]}"
printf '%s\n' "/usr/bin/node /x/claude --name dispatch-alpha --foo" > "$T/ps.txt"
expect_refuse "already running (followed by a space)" "$T/running" 'already'
printf '%s\n' "claude --name dispatch-alpha" > "$T/ps.txt"
expect_refuse "already running (line end)" "$T/running" 'already'
printf '%s\n' "claude --name dispatch-alpha-2 --x" "claude --name dispatch-alphabet" > "$T/ps.txt"
total=$((total+1)); run "$T/running"
[ "$rc" = 0 ] || bad "a longer name (dispatch-alpha-2) must not count as running: exit $rc: $(cat "$T/err")"
# grep -q stops at the first match; a long ps listing after it must not turn that match into "not running" (SIGPIPE + pipefail)
{ echo "claude --name dispatch-alpha"; head -c 300000 /dev/zero | tr '\0' 'x' | fold -w 100; } > "$T/ps.txt"
expect_refuse "already running (match first, 300 KB of ps after it)" "$T/running" 'already'
: > "$T/ps.txt"

# 3. refuses with no Name:
repo noname "- Project: acme #2 · Approver: acme" "- Agent: acme-bot · Agent keychain: k"
expect_refuse "no Name" "$T/noname" 'name'

# 4. refuses with Agent: but no, or a placeholder, Agent keychain:
repo nokc "- Name: alpha · Approver: acme" "- Agent: acme-bot"
expect_refuse "Agent without Agent keychain" "$T/nokc" 'keychain'
repo phkc "- Name: alpha · Approver: acme" "- Agent: acme-bot · Agent keychain: {{Keychain service}}"
expect_refuse "placeholder Agent keychain" "$T/phkc" 'keychain'

# 5. refuses when Agent equals Approver (a login compares without regard to case)
repo same "- Name: alpha · Approver: Acme" "- Agent: acme · Agent keychain: k"
expect_refuse "Agent equals Approver" "$T/same" 'approver'

# 6. from a worktree: finds the main checkout and cds there
repo wt "${GOOD[@]}"
git -C "$T/wt" worktree add -q "$T/wt-tree" -b feat/wt
mkdir -p "$T/wt-tree/sub"
total=$((total+1)); run "$T/wt-tree/sub"
[ "$rc" = 0 ] || bad "worktree: exit $rc: $(cat "$T/err")"
[ "$(cat "$T/cwd" 2>/dev/null)" = "$(cd "$T/wt" && pwd -P)" ] || bad "worktree: cwd is '$(cat "$T/cwd" 2>/dev/null)', not the main checkout"

# 7. no Agent: line -> a warning on stderr and claude with no as-agent.sh
repo noagent "- Name: alpha · Approver: acme"
total=$((total+1)); run "$T/noagent"
[ "$rc" = 0 ] || bad "no Agent: exit $rc: $(cat "$T/err")"
grep -qi 'agent' "$T/err" || bad "no Agent: no warning on stderr"
[ "$(cat "$T/argv" 2>/dev/null)" = "$(printf '%s\n' claude --name dispatch-alpha -- '/loop /dispatch')" ] \
  || bad "no Agent: argv was: $(tr '\n' ' ' < "$T/argv" 2>/dev/null)"

# 8. happy path: exactly <main>/.claude/bin/as-agent.sh <keychain> claude --name dispatch-<key> -- "/loop /dispatch"
total=$((total+1)); run "$T/running"
main=$(cd "$T/running" && pwd -P)
want=$(printf '%s\n' "$main/.claude/bin/as-agent.sh" acme-bot-token claude --name dispatch-alpha -- '/loop /dispatch')
[ "$rc" = 0 ] || bad "happy path: exit $rc: $(cat "$T/err")"
[ "$(cat "$T/argv" 2>/dev/null)" = "$want" ] || bad "happy path: argv was: $(tr '\n' ' ' < "$T/argv" 2>/dev/null)"
[ ! -s "$T/err" ] || bad "happy path: wrote to stderr: $(cat "$T/err")"

echo "$((total-fail))/$total passed"
[ "$fail" = 0 ]
