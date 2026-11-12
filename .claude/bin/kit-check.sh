#!/usr/bin/env bash
# The kit repo's own check: what ci runs and what CLAUDE.md names as "Check". Not copied to new projects.
# Usage: .claude/bin/kit-check.sh   Exits 0 if the kit is sound, 1 and says why otherwise.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

command -v shellcheck >/dev/null 2>&1 || { echo "kit-check: shellcheck is not installed"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "kit-check: jq is not installed"; exit 1; }

# Every shell script, including one not committed yet.
count=0
while IFS= read -r f; do
  bash -n "$f" || { echo "kit-check: syntax error in $f"; exit 1; }
  shellcheck "$f" || { echo "kit-check: shellcheck failed on $f"; exit 1; }
  count=$((count + 1))
done < <(git ls-files --cached --others --exclude-standard '*.sh')
[ "$count" -gt 0 ] || { echo "kit-check: found no shell scripts to check"; exit 1; }

jq empty .claude/settings.json .github/ruleset-main.json

tmp=$(mktemp -d "${TMPDIR:-/tmp}/kit-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
d="$tmp/hosted"

# Copy-only mode: no third argument, so bootstrap.sh exits before any GitHub call.
./bootstrap.sh "$d" hosted >/dev/null || { echo "kit-check: bootstrap.sh failed in copy-only mode"; exit 1; }

cmp -s .github/ci.template.yml "$d/.github/workflows/ci.yml" \
  || { echo "kit-check: installed ci.yml differs from .github/ci.template.yml"; exit 1; }
cmp -s CLAUDE.template.md "$d/CLAUDE.md" \
  || { echo "kit-check: installed CLAUDE.md differs from CLAUDE.template.md"; exit 1; }
for f in .github/ci.template.yml CLAUDE.template.md .claude/bin/kit-check.sh; do
  [ ! -e "$d/$f" ] || { echo "kit-check: $f must not be copied to a new project"; exit 1; }
done
[ -s "$d/.gitignore" ] || { echo "kit-check: installed .gitignore is empty"; exit 1; }

# #438 C2: the hand-run loop is gone. A new project has none of its files and no markdown roadmap (ADR-0001: the
# backlog is Issues plus the Project's Now column), and nothing the kit ships still points at the retired commands.
for f in .claude/skills/brief .claude/skills/ship .claude/skills/merge .claude/skills/land \
         .claude/bin/preflight.sh docs/ROADMAP.md docs/ROADMAP.template.md; do
  [ ! -e "$d/$f" ] || { echo "kit-check: $f must not be in a new project (the hand-run loop is retired)"; exit 1; }
  [ ! -e "$f" ] || [ "$f" = docs/ROADMAP.md ] || { echo "kit-check: $f must be removed from the kit"; exit 1; }
done
if grep -nE '/(brief|ship|merge|land)\b|preflight' CLAUDE.md CLAUDE.template.md .claude/agents/reviewer.md \
    .claude/skills/dispatch/*.md .github/workflows/lane.yml; then
  echo "kit-check: a file still points at /brief, /ship, /merge, /land or preflight"; exit 1
fi

# The worker-session files ship, and session.sh keeps its executable bit in the install.
[ -f "$d/.claude/bin/session.sh" ] || { echo "kit-check: session.sh is missing from a new project"; exit 1; }
cmp -s .claude/bin/session.sh "$d/.claude/bin/session.sh" || { echo "kit-check: installed session.sh differs from the kit's"; exit 1; }
[ -x "$d/.claude/bin/session.sh" ] || { echo "kit-check: installed session.sh is not executable"; exit 1; }

# Dispatcher (#436 part A): the scripts, skill, hook and lane files ship, scripts keep their executable bit,
# the self-tests pass in the install, and nothing names the repo it was ported from.
disp_scripts=".claude/bin/dispatch-next.sh .claude/bin/as-agent.sh .claude/bin/token-expiry.sh \
  .claude/bin/test-session.sh .claude/bin/test-dispatch.sh .claude/bin/test-token-expiry.sh \
  .claude/hooks/notify-waiting.sh .github/lane/lane.sh .github/lane/test.sh \
  .claude/bin/dispatch.sh .claude/bin/test-launcher.sh .claude/bin/test-scope-check.sh"
for f in $disp_scripts .claude/skills/dispatch/SKILL.md .claude/skills/dispatch/worker-contract.md docs/runbooks/agent-token.md; do
  [ -f "$d/$f" ] || { echo "kit-check: $f is missing from a new project"; exit 1; }
  cmp -s "$f" "$d/$f" || { echo "kit-check: installed $f differs from the kit's"; exit 1; }
done
for f in $disp_scripts; do
  [ -x "$d/$f" ] || { echo "kit-check: installed $f is not executable"; exit 1; }
done
(cd "$d" && .claude/bin/test-session.sh && .claude/bin/test-dispatch.sh && .claude/bin/test-token-expiry.sh \
  && .claude/bin/test-launcher.sh && .claude/bin/test-scope-check.sh && sh .github/lane/test.sh) >"$tmp/selftests.out" 2>&1 \
  || { tail -n 20 "$tmp/selftests.out"; echo "kit-check: the dispatcher self-tests fail in a new project"; exit 1; }
if (cd "$d" && grep -nE 'job-search|job-radar|rfhayn|/Users/' .claude/bin/session.sh .claude/bin/dispatch-next.sh \
    .claude/bin/as-agent.sh .claude/bin/token-expiry.sh .claude/hooks/notify-waiting.sh \
    .claude/bin/dispatch.sh .claude/bin/test-launcher.sh docs/runbooks/agent-token.md \
    .claude/skills/dispatch/*.md .github/lane/*.sh); then
  echo "kit-check: a dispatcher file in a new project names job-search, a login or a home path"; exit 1
fi
# The runbook ships filled in, not as a template, and covers what an adopter must do.
if head -n 1 "$d/docs/runbooks/agent-token.md" | grep -q '^> TEMPLATE'; then
  echo "kit-check: docs/runbooks/agent-token.md carries the TEMPLATE marker"; exit 1
fi
# #437: the launcher test is part of what ci runs in a new project.
grep -q 'test-launcher.sh' .github/ci.template.yml || { echo "kit-check: ci.template.yml does not run test-launcher.sh"; exit 1; }
# #438 C1: workers run scope-check themselves, so its test runs in a new project's ci too.
grep -q 'test-scope-check.sh' .github/ci.template.yml || { echo "kit-check: ci.template.yml does not run test-scope-check.sh"; exit 1; }
# The alias is offered, never forced: copy-only bootstrap with an empty HOME prints it and writes nothing there.
mkdir "$tmp/home"
alias_out=$(HOME="$tmp/home" ./bootstrap.sh "$tmp/aliasdest" hosted) \
  || { echo "kit-check: bootstrap.sh failed with HOME=$tmp/home"; exit 1; }
[ -z "$(ls -A "$tmp/home")" ] || { echo "kit-check: bootstrap.sh wrote into HOME: $(ls -A "$tmp/home")"; exit 1; }
case "$alias_out" in *'alias dispatch='*) ;; *) echo "kit-check: bootstrap.sh did not print the dispatch alias"; exit 1 ;; esac
# lane.yml listens to BOTH events (ADR-0002): pull_request so the first PR of a repo that has no lane.yml on main yet
# still gets a `lane` check (else the ruleset's required check never reports), pull_request_target so main's copy judges.
for ev in pull_request pull_request_target; do
  grep -Eq "^  $ev:( |\$)" .github/workflows/lane.yml || { echo "kit-check: lane.yml does not trigger on $ev"; exit 1; }
done
# Each trigger needs the same types, or a run that is not re-run on a label change stays stale (and the ruleset
# requires every run named lane).
[ "$(grep -c '^    types: \[opened, synchronize, reopened, labeled, unlabeled, edited\]$' .github/workflows/lane.yml)" = 2 ] \
  || { echo "kit-check: lane.yml must give both triggers the types opened, synchronize, reopened, labeled, unlabeled, edited"; exit 1; }
grep -q 'test-dispatch.sh' .github/ci.template.yml || { echo "kit-check: ci.template.yml does not run the dispatcher self-tests"; exit 1; }
grep -q '^## Dispatcher' CLAUDE.template.md || { echo "kit-check: CLAUDE.template.md has no ## Dispatcher block"; exit 1; }

# Docs that ship unfilled must say so on their first line, in the repo and in what a new project receives.
marker='> TEMPLATE, not filled in. Do not treat as project fact.'
for f in docs/ARCHITECTURE.md docs/RISKS.md docs/templates/DATA-MODEL.md docs/templates/API.md \
         docs/templates/INVENTORY.md docs/templates/runbook.md docs/templates/spec.md; do
  for root in . "$d"; do
    [ -f "$root/$f" ] || { echo "kit-check: $f is missing from $root"; exit 1; }
    [ "$(head -n 1 "$root/$f")" = "$marker" ] || { echo "kit-check: first line of $root/$f is not the TEMPLATE marker"; exit 1; }
  done
done

# A second run must change nothing, and must leave an edited file alone.
echo "edited" >> "$d/CLAUDE.md"
cp "$d/CLAUDE.md" "$tmp/CLAUDE.edited"
cp "$d/.gitignore" "$tmp/gitignore.first"
(cd "$d" && find . -type f | sort | xargs cksum) > "$tmp/tree.first"
./bootstrap.sh "$d" hosted >/dev/null || { echo "kit-check: second bootstrap.sh run failed"; exit 1; }
(cd "$d" && find . -type f | sort | xargs cksum) > "$tmp/tree.second"
cmp -s "$tmp/tree.first" "$tmp/tree.second" || { echo "kit-check: second run changed the installed tree"; exit 1; }
[ -x "$d/.claude/bin/session.sh" ] || { echo "kit-check: second run lost the executable bit on session.sh"; exit 1; }
cmp -s "$tmp/CLAUDE.edited" "$d/CLAUDE.md" || { echo "kit-check: second run overwrote an edited file"; exit 1; }
cmp -s "$tmp/gitignore.first" "$d/.gitignore" || { echo "kit-check: second run changed .gitignore"; exit 1; }

# #452 (ADR-0007): the install records a lock, the kit has a VERSION and a changelog entry for it, and test-bootstrap.sh
# (lock, --upgrade, --adopt) passes. test-bootstrap.sh is the kit's own and is not copied to new projects.
[ -f "$d/.claude/kit.lock" ] || { echo "kit-check: the install wrote no .claude/kit.lock"; exit 1; }
ver=$(tr -d '[:space:]' < VERSION)
[[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "kit-check: VERSION is not x.y.z: $ver"; exit 1; }
grep -qx "version $ver" "$d/.claude/kit.lock" || { echo "kit-check: the installed lock does not carry VERSION $ver"; exit 1; }
grep -q "^## \[\?$ver" CHANGELOG.md || { echo "kit-check: CHANGELOG.md has no heading for $ver"; exit 1; }
[ ! -e "$d/.claude/bin/test-bootstrap.sh" ] || { echo "kit-check: test-bootstrap.sh must not be copied to a new project"; exit 1; }
bash .claude/bin/test-bootstrap.sh >"$tmp/test-bootstrap.out" 2>&1 \
  || { tail -n 20 "$tmp/test-bootstrap.out"; echo "kit-check: test-bootstrap.sh failed"; exit 1; }

# The runner choice reaches both required workflows.
s="$tmp/self-hosted"
./bootstrap.sh "$s" self-hosted >/dev/null || { echo "kit-check: bootstrap.sh failed with self-hosted"; exit 1; }
for f in ci lane; do
  grep -q 'runs-on: \[self-hosted\]' "$s/.github/workflows/$f.yml" \
    || { echo "kit-check: self-hosted did not reach $f.yml"; exit 1; }
  if grep -q 'runs-on: ubuntu-' "$s/.github/workflows/$f.yml"; then
    echo "kit-check: $f.yml still names a hosted runner under self-hosted"; exit 1
  fi
done

# session.sh drives Ghostty and git worktrees outside the sandbox, so its arguments are checked before
# anything runs. Every call here passes --dry-run, so even a script that wrongly accepted one starts nothing.
sess=.claude/bin/session.sh
[ -x "$sess" ] || { echo "kit-check: $sess is missing or not executable"; exit 1; }
long43=$(printf 'a%.0s' $(seq 1 43))
long42=$(printf 'a%.0s' $(seq 1 42))
# The prompt comes only from the git-ignored review folder; the test files are removed on exit.
rev=.claude/review
mkdir -p "$rev"
trap '[ -z "${stubpid:-}" ] || kill "$stubpid" 2>/dev/null || true; rm -rf "$tmp" "$rev"/spawn-zz-* "$rev/spawn-$long42.md" "${gcd:-/nonexistent}"/spawn/zz-* "${gcd:-/nonexistent}"/spawn/locks/zz-*' EXIT
echo "SECRET-PROMPT-TEXT" > "$rev/spawn-zz-ok.md"
cp "$rev/spawn-zz-ok.md" "$rev/spawn-$long42.md"
refuses() {
  local out
  if out=$("$sess" "$@" 2>&1); then echo "kit-check: session.sh accepted: $*"; exit 1; fi
  case "$out" in
    *"session.sh: refused"*) ;;
    *) echo "kit-check: session.sh failed without a refusal message for: $*"; exit 1 ;;
  esac
}
for bad in "bug" "feat/x" "FEAT" ""; do
  refuses open "$bad" zz-ok --key kit --report-to main --dry-run
done
# "\$(" is literal text that must be refused, never expanded.
for bad in "a b" "Upper" 'a;b' "a\$(id)" "\$(id)" "-lead" "trail-" "a_b" "a/b" "$long43" ""; do
  refuses open feat "$bad" --key kit --report-to main --dry-run
  refuses close "$bad" --dry-run
done
for bad in "a b" 'a;b' "a\$(id)" "x'y" "" "-x" "--dry-run"; do
  refuses open feat zz-ok --key kit --report-to "$bad" --dry-run
done
refuses open feat zz-ok --key kit --dry-run
refuses open feat zz-ok --report-to main --dry-run   # --key is required (ADR-0006)
for bad in "Kit" "1kit" 'k;t' "a b" ""; do
  refuses open feat zz-ok --key "$bad" --report-to main --dry-run
done
refuses open feat zz-ok --key kit --report-to main --bogus --dry-run
# There is no path argument: a path, .env included, is refused and never read.
echo "SECRET-ENV-TEXT" > "$tmp/.env"
refuses open feat zz-ok "$tmp/.env" --key kit --report-to main --dry-run
refuses open feat zz-ok .env --key kit --report-to main --dry-run
refuses open feat zz-ok "$rev/spawn-zz-ok.md" --key kit --report-to main --dry-run
refuses open feat .env --key kit --report-to main --dry-run
# The prompt file: missing, a symlink (even to a real file), a directory, over 20 KB.
refuses open feat zz-none --key kit --report-to main --dry-run
ln -s "$tmp/.env" "$rev/spawn-zz-link.md"
refuses open feat zz-link --key kit --report-to main --dry-run
mkdir "$rev/spawn-zz-dir.md"
refuses open feat zz-dir --key kit --report-to main --dry-run
head -c 20481 /dev/zero > "$rev/spawn-zz-big.md"
refuses open feat zz-big --key kit --report-to main --dry-run
head -c 20480 /dev/zero > "$rev/spawn-zz-edge.md"
"$sess" open feat zz-edge --key kit --report-to main --dry-run >/dev/null \
  || { echo "kit-check: session.sh refused a 20480-byte prompt"; exit 1; }
refuses close zz-ok --bogus --dry-run
refuses frobnicate zz-ok --dry-run

gcd=$(git rev-parse --path-format=absolute --git-common-dir)
out=$("$sess" open feat zz-ok --key kit --report-to main --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run open failed: $out"; exit 1; }
# The tab runs through the login shell so a worker gets the user's PATH (gh, shellcheck); only validated tokens go in.
want="/bin/zsh -lc 'exec $(command -v claude || echo claude) --name kit-zz-ok --permission-mode auto --strict-mcp-config -- \"\$(cat $gcd/spawn/zz-ok.prompt)\"'"
[ "$(printf '%s\n' "$out" | grep '^tab command: ')" = "tab command: $want" ] \
  || { echo "kit-check: session.sh tab command is not exactly: $want"; printf '%s\n' "$out"; exit 1; }
case "$out" in *SECRET-ENV-TEXT*) echo "kit-check: session.sh dry-run printed .env text"; exit 1 ;; esac
case "$out" in *SECRET-PROMPT-TEXT*) echo "kit-check: session.sh dry-run printed the prompt text"; exit 1 ;; esac
case "$out" in *"tell application \"Ghostty\""*) ;; *) echo "kit-check: session.sh dry-run did not print the AppleScript"; exit 1 ;; esac
"$sess" open fix "$long42" --key kit --report-to a_B-9 --dry-run >/dev/null \
  || { echo "kit-check: session.sh refused a 42-character slug"; exit 1; }
out=$("$sess" close zz-ok --abandon --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run close failed: $out"; exit 1; }
[ ! -e "$gcd/spawn/zz-ok.prompt" ] && [ ! -e "$gcd/spawn/zz-ok.term" ] \
  || { echo "kit-check: session.sh dry-run wrote files"; exit 1; }
git worktree list | grep -q 'zz-ok' && { echo "kit-check: session.sh dry-run created a worktree"; exit 1; }

mkdir -p "$gcd/spawn"
# send retired with /ship (#432, #438): an unknown command, whatever follows it. The only typing left is close's fixed /exit.
refuses send zz-ok ship --dry-run
refuses send zz-ok /exit --dry-run
refuses send zz-ok --dry-run
if grep -qE 'APPLE_SEND|input text "/ship"|cwd_guard' "$sess"; then echo "kit-check: session.sh still has the send machinery"; exit 1; fi

# Phase 1e: one worker per slug. A lock dir under spawn/locks holds the terminal id and start time.
# claude_running finds the worker with ps, so a stub named claude (a copy of sleep) stands in for a session.
lockd="$gcd/spawn/locks/zz-lock"
echo "SECRET-PROMPT-TEXT" > "$rev/spawn-zz-lock.md"
out=$("$sess" open feat zz-lock --key kit --report-to main --dry-run 2>&1) \
  || { echo "kit-check: open --dry-run with no lock failed: $out"; exit 1; }
case "$out" in *"would take lock"*) ;; *) echo "kit-check: open --dry-run with no lock did not say 'would take lock'"; printf '%s\n' "$out"; exit 1 ;; esac
mkdir -p "$lockd"
echo "HOLDER-TERM-7" > "$lockd/term"
echo "2026-11-09T10:00:00Z" > "$lockd/started"
# Not running: the refusal says stale, names the holder, and open does not remove the lock.
rc=0; out=$("$sess" open feat zz-lock --key kit --report-to main --dry-run 2>&1) || rc=$?
[ "$rc" = 2 ] || { echo "kit-check: open with a stale lock exited $rc, not 2"; printf '%s\n' "$out"; exit 1; }
case "$out" in *"session.sh: refused"*stale*HOLDER-TERM-7*2026-11-09T10:00:00Z*) ;; *) echo "kit-check: stale-lock refusal does not say stale and name the terminal and start time"; printf '%s\n' "$out"; exit 1 ;; esac
[ -d "$lockd" ] || { echo "kit-check: open removed a stale lock"; exit 1; }
# Running: the refusal says live.
# The stub is a script, not a copy of sleep (a copied system binary is killed on macOS). ps shows it as
# "sh <dir>/claude --name kit-zz-lock", which claude_running matches. The sandbox denies ps, so there the case is skipped.
if ps -axo command= >/dev/null 2>&1; then
  printf '#!/bin/sh\nsleep 30\n' > "$tmp/claude"
  chmod +x "$tmp/claude"
  "$tmp/claude" --name kit-zz-lock 600 >/dev/null 2>&1 &
  stubpid=$!
  sleep 1
  rc=0; out=$("$sess" open feat zz-lock --key kit --report-to main --dry-run 2>&1) || rc=$?
  [ "$rc" = 2 ] || { echo "kit-check: open with a live lock exited $rc, not 2"; printf '%s\n' "$out"; exit 1; }
  case "$out" in *"session.sh: refused"*live*HOLDER-TERM-7*2026-11-09T10:00:00Z*) ;; *) echo "kit-check: live-lock refusal does not say live and name the terminal and start time"; printf '%s\n' "$out"; exit 1 ;; esac
  kill "$stubpid"; wait "$stubpid" 2>/dev/null || true; stubpid=""
else
  echo "kit-check: skipped the live-lock case: ps is not permitted here (ci runs it)"
fi
# close says it would remove the lock, and the real code removes it on the gone, normal and abandon paths.
out=$("$sess" close zz-lock --abandon --dry-run 2>&1) \
  || { echo "kit-check: close --abandon --dry-run failed: $out"; exit 1; }
case "$out" in *"would remove the lock $lockd"*) ;; *) echo "kit-check: close --abandon --dry-run does not say it would remove the lock"; printf '%s\n' "$out"; exit 1 ;; esac
[ -d "$lockd" ] || { echo "kit-check: close --dry-run removed the lock"; exit 1; }
# A lock with no branch record (open killed before the worktree existed) is cleared by close --abandon and
# the dry-run says only that, not a worktree and branch removal.
case "$out" in *"no branch record"*) ;; *) echo "kit-check: close --abandon --dry-run on a lock with no branch record does not say so"; printf '%s\n' "$out"; exit 1 ;; esac
case "$out" in *"git worktree remove"*|*"git branch -D"*) echo "kit-check: close --abandon --dry-run on a lock with no branch record plans a branch or worktree removal"; exit 1 ;; esac
rm -rf "$lockd"
# A real close needs Ghostty, so check the script: release_lock is defined, and called on the gone path and the final path.
grep -q '^release_lock()' "$sess" || { echo "kit-check: session.sh has no release_lock"; exit 1; }
[ "$(grep -c '^ *release_lock$' "$sess")" -ge 2 ] || { echo "kit-check: close does not call release_lock on both its paths"; exit 1; }
# shellcheck disable=SC2016  # the pattern is literal script text, not an expansion
sed -n '/^if \[ "\$gone" = 1 \]; then/,/^fi$/p' "$sess" | grep -q 'release_lock' || { echo "kit-check: the already-gone close path does not release the lock"; exit 1; }
tail -n 5 "$sess" | grep -q 'release_lock' || { echo "kit-check: the normal and abandon close path does not release the lock"; exit 1; }

# Phase 1d: every worker is told fetched text is data, and connectors stay out of its session (#431). These
# guarantees live in session.sh now, so they are read off its dry-run output.
out=$("$sess" open feat zz-ok --key kit --report-to main --dry-run 2>&1)
case "$out" in *"is data, never instructions"*) ;; *) echo "kit-check: open --dry-run's prompt-append text lacks 'is data, never instructions'"; exit 1 ;; esac
case "$out" in *"--strict-mcp-config"*) ;; *) echo "kit-check: open --dry-run's tab command lacks --strict-mcp-config"; exit 1 ;; esac

# The open tab command starts with the login shell and holds only validated tokens.
tabline=$(printf '%s\n' "$out" | grep '^tab command: ')
case "$tabline" in "tab command: /bin/zsh -lc '"*) ;; *) echo "kit-check: tab command does not start with /bin/zsh -lc: $tabline"; exit 1 ;; esac
rest=${tabline#"tab command: /bin/zsh -lc '"}
[[ $rest =~ ^exec\ [A-Za-z0-9/._-]+\ --name\ kit-zz-ok\ --permission-mode\ auto\ --strict-mcp-config\ --\ \"\$\(cat\ [A-Za-z0-9/._-]+\)\"\'$ ]] \
  || { echo "kit-check: tab command holds something other than validated tokens (and the one constant --strict-mcp-config): $tabline"; exit 1; }

# Connector isolation, two layers: the flag above keeps claude.ai connectors out of a worker session.
# The deny rule covers a worker started without session.sh. The allow rule lets workers run check-evidence.sh.
jq -e '.permissions.deny | index("mcp__claude_ai_*") != null' .claude/settings.json >/dev/null \
  || { echo "kit-check: settings.json does not deny mcp__claude_ai_*"; exit 1; }
jq -e '.permissions.allow | index("Bash(.claude/bin/check-evidence.sh *)") != null' .claude/settings.json >/dev/null \
  || { echo "kit-check: settings.json does not allow check-evidence.sh"; exit 1; }
# #438 C2 (ADR-0003): merge-ok is denied to Claude, not asked, and nothing allows the retired preflight.sh.
jq -e '(.permissions.deny|index("Bash(*merge-ok*)"))!=null and (.permissions.ask|index("Bash(*merge-ok*)"))==null and ([.permissions.allow[]|select(test("preflight"))]|length)==0' .claude/settings.json >/dev/null \
  || { echo "kit-check: settings.json must deny (not ask) Bash(*merge-ok*) and must not allow preflight"; exit 1; }

# close when the worktree and the recorded branch are already gone: a cleanup plan, not a refusal.
echo "feat/zz-ok" > "$gcd/spawn/zz-ok.branch"
echo "FAKE-TERM-ID-1" > "$gcd/spawn/zz-ok.term"
out=$("$sess" close zz-ok --dry-run 2>&1) \
  || { echo "kit-check: close --dry-run refused when worktree and branch are gone: $out"; exit 1; }
case "$out" in *"already gone"*"delete $gcd/spawn/zz-ok."*) ;; *) echo "kit-check: close --dry-run did not print the cleanup plan"; printf '%s\n' "$out"; exit 1 ;; esac
case "$out" in *"git worktree remove"*|*"git branch -D"*) echo "kit-check: cleanup plan removes a branch or worktree"; exit 1 ;; esac
[ -e "$gcd/spawn/zz-ok.term" ] || { echo "kit-check: close --dry-run deleted records"; exit 1; }
rm -f "$gcd/spawn/zz-ok.term" "$gcd/spawn/zz-ok.branch"

# send and sync retired with the hand-run skills (#432, #438): unknown commands, refused whatever follows them.
refuses sync --dry-run
refuses sync

# The status line: one short line from the status JSON and git, fails soft, ships with the kit.
sl=.claude/statusline.sh
[ -f "$sl" ] || { echo "kit-check: $sl is missing"; exit 1; }
[ -f "$d/$sl" ] || { echo "kit-check: $sl is missing from a new project"; exit 1; }
cmp -s "$sl" "$d/$sl" || { echo "kit-check: installed $sl is missing or differs from the kit's"; exit 1; }
[ -x "$d/$sl" ] || { echo "kit-check: installed statusline.sh is not executable"; exit 1; }
jq -e '.statusLine.type == "command"' .claude/settings.json >/dev/null \
  || { echo "kit-check: settings.json has no statusLine command"; exit 1; }
grep -q 'statusline.sh' <<<"$(jq -r '.statusLine.command' .claude/settings.json)" \
  || { echo "kit-check: statusLine.command does not run statusline.sh"; exit 1; }
# Claude Code runs statusline.sh outside the sandbox, so it is guarded like session.sh: ask on Edit, no sandboxed writes.
# An Edit(...) rule also covers the Write tool; a Write(...) rule never matches and prints a warning at startup.
jq -e '(.permissions.ask | index("Edit(./**/.claude/statusline.sh)") != null) and (.permissions.ask | index("Edit(./**/.claude/bin/session.sh)") != null)
       and (.sandbox.filesystem.denyWrite | index("./.claude/statusline.sh") != null) and (.sandbox.filesystem.denyWrite | index("./**/.claude/statusline.sh") != null)
       and (.sandbox.filesystem.denyWrite | index("./.claude/bin/session.sh") != null) and (.sandbox.filesystem.denyWrite | index("./**/.claude/bin/session.sh") != null)' \
  .claude/settings.json >/dev/null || { echo "kit-check: statusline.sh or session.sh is not guarded in settings.json (ask Edit, sandbox denyWrite)"; exit 1; }
no_write_rules='[.permissions[]? | arrays | .[] | select(type == "string" and startswith("Write("))] | length == 0'
jq -e "$no_write_rules" .claude/settings.json >/dev/null \
  || { echo "kit-check: settings.json has a Write(...) permission rule; it never matches, use Edit(...)"; exit 1; }
# The check itself: a Write(...) rule added to a scratch copy must make it fail.
jq '.permissions.ask += ["Write(./**/.claude/statusline.sh)"]' .claude/settings.json > "$tmp/settings-with-write.json"
if jq -e "$no_write_rules" "$tmp/settings-with-write.json" >/dev/null; then echo "kit-check: the Write(...) rule check passes on a settings.json that has one"; exit 1; fi
git_c() { git -C "$1" -c user.name=t -c user.email=t@example.com "${@:2}"; }
slr="$tmp/slproj"
git init -q -b main "$slr"
git_c "$slr" commit -q --allow-empty -m init
git_c "$slr" worktree add -q "$tmp/slwt" -b feat/zz-sl
sj() { printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.7}}' "$1"; }
has() { # has <label> <output> <needle>
  case "$2" in *"$3"*) ;; *) echo "kit-check: statusline $1: missing '$3' in: $2"; exit 1 ;; esac
}
lacks() {
  case "$2" in *"$3"*) echo "kit-check: statusline $1: unexpected '$3' in: $2"; exit 1 ;; esac
}
out=$(sj "$slr" | sh "$sl")
has clean "$out" "slproj"; has clean "$out" "main"; has clean "$out" "42% ctx"; has clean "$out" "Opus"; has clean "$out" "✓"
lacks clean "$out" "●"; lacks clean "$out" "workers"
echo x > "$slr/f.txt"
out=$(sj "$slr" | sh "$sl")
has dirty "$out" "●"; lacks dirty "$out" "✓"
git_c "$slr" add f.txt; git_c "$slr" commit -q -m f
out=$(sj "$slr" | sh "$sl")
has committed "$out" "✓"; lacks committed "$out" "●"
# A worker's worktree shows the same project name and its own branch.
out=$(sj "$tmp/slwt" | sh "$sl")
has worktree "$out" "slproj"; has worktree "$out" "feat/zz-sl"
# Workers: counted from <common dir>/spawn/*.term, in the main checkout only.
mkdir -p "$slr/.git/spawn"; echo T > "$slr/.git/spawn/x.term"
out=$(sj "$slr" | sh "$sl"); has workers "$out" "workers: 1"
out=$(sj "$tmp/slwt" | sh "$sl"); lacks worker-worktree "$out" "workers"
# Ahead/behind appears only with an upstream.
git_c "$slr" clone -q "$slr" "$tmp/slclone"
git_c "$tmp/slclone" commit -q --allow-empty -m ahead
out=$(sj "$tmp/slclone" | sh "$sl"); has ahead "$out" "↑1"
# Soft failure: empty input, malformed JSON and a non-git directory print something and exit 0.
mkdir "$tmp/nogit"
for input in "" "not json {" "{}"; do
  out=$(cd "$slr" && printf '%s' "$input" | sh "$OLDPWD/$sl" 2>&1) || { echo "kit-check: statusline exited non-zero on input: $input"; exit 1; }
  [ -n "$out" ] || { echo "kit-check: statusline printed nothing on input: $input"; exit 1; }
  has soft "$out" "main"
done
out=$(sj "$tmp/nogit" | sh "$sl" 2>&1) || { echo "kit-check: statusline failed outside a git repo"; exit 1; }
has nogit "$out" "42% ctx"; has nogit "$out" "Opus"
out=$(cd "$tmp/nogit" && printf '' | sh "$OLDPWD/$sl" 2>&1) || { echo "kit-check: statusline failed on empty input outside git"; exit 1; }
[ -n "$out" ] || { echo "kit-check: statusline printed nothing outside git on empty input"; exit 1; }
out=$(sj "$slr" | PATH=/nonexistent /bin/sh "$PWD/$sl" 2>&1) || { echo "kit-check: statusline failed without jq or git on PATH"; exit 1; }

# check-evidence.sh: a reviewer "met" must cite a line the diff or log has. It ships, keeps its executable bit,
# and every exit 1 says why on stdout.
ev=.claude/bin/check-evidence.sh
[ -f "$ev" ] || { echo "kit-check: $ev is missing"; exit 1; }
[ -f "$d/$ev" ] || { echo "kit-check: $ev is missing from a new project"; exit 1; }
cmp -s "$ev" "$d/$ev" || { echo "kit-check: installed $ev differs from the kit's"; exit 1; }
[ -x "$d/$ev" ] || { echo "kit-check: installed $ev is not executable"; exit 1; }
[ -x "$ev" ] || { echo "kit-check: $ev is not executable"; exit 1; }
# expect <label> <exit code> <needle in stdout or ""> <command...>
expect() {
  local label=$1 want=$2 needle=$3 out rc=0
  shift 3
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -eq "$want" ] || { echo "kit-check: $label: exit $rc, wanted $want: $out"; exit 1; }
  case "$out" in *"$needle"*) ;; *) echo "kit-check: $label: output lacks '$needle': $out"; exit 1 ;; esac
}
fx="$tmp/fx"; mkdir -p "$fx"

cat > "$fx/diff.txt" <<'DIFF'
diff --git a/src/a.sh b/src/a.sh
--- a/src/a.sh
+++ b/src/a.sh
@@ -1,2 +10,3 @@
+one
+two
+three
@@ -30 +40 @@
+single
diff --git a/old.sh b/old.sh
--- a/old.sh
+++ /dev/null
@@ -1,2 +0,0 @@
-gone
-gone
DIFF
printf 'abc1 first\nabc2 second\n' > "$fx/log.txt"
rv() { printf 'VERDICT: SHIP\nDONE-WHEN:\n%s\n' "$1" > "$fx/review.txt"; }
cev() { "$ev" "$fx/review.txt" "$fx/diff.txt" "$fx/log.txt"; }
rv '- [met] item | evidence: src/a.sh:11';                   expect "evidence in range" 0 "" cev
rv '- [met] item | evidence: src/a.sh:10';                   expect "evidence first line of hunk" 0 "" cev
rv '- [met] item | evidence: src/a.sh:12';                   expect "evidence last line of hunk" 0 "" cev
rv '- [met] item | evidence: src/a.sh:13';                   expect "evidence past hunk" 1 "src/a.sh:13" cev
rv '- [met] item | evidence: src/a.sh:9';                    expect "evidence before hunk" 1 "src/a.sh:9" cev
rv '- [met] item | evidence: src/a.sh:40';                   expect "evidence in one-line hunk" 0 "" cev
rv '- [met] item | evidence: src/a.sh:41';                   expect "evidence past one-line hunk" 1 "src/a.sh:41" cev
rv '- [met] item | evidence: src/b.sh:1';                    expect "evidence file not in diff" 1 "src/b.sh" cev
rv '- [met] item | evidence: old.sh:1';                      expect "evidence in a deleted file" 1 "old.sh:1" cev
rv '- [met] item | evidence: log.txt:2';                     expect "evidence log.txt in range" 0 "" cev
rv '- [met] item | evidence: log.txt:3';                     expect "evidence log.txt past its length" 1 "log.txt:3" cev
rv '- [met] item | evidence: log.txt:0';                     expect "evidence log.txt line 0" 1 "log.txt:0" cev
rv '- [met] item';                                           expect "met with no citation" 1 "no evidence" cev
rv '- [met] item | evidence:';                               expect "met with empty citation" 1 "no evidence" cev
rv '- [met] item | evidence: looks fine';                    expect "met with prose citation" 1 "looks" cev
rv '- [met] item | evidence: src/a.sh:11, log.txt:1';        expect "two good citations" 0 "" cev
rv '- [met] item | evidence: src/a.sh:11 (by inspection, it is there)'; expect "prose after a good citation" 0 "" cev
rv '- [met] item | evidence: src/a.sh:11, log.txt:2 (checked)'; expect "prose after two good citations" 0 "" cev
rv '- [met] item | evidence: src/a.sh:11, src/a.sh:99 (but this one is wrong)'; expect "bad citation before prose" 1 "src/a.sh:99" cev
rv '- [met] item | evidence: (by inspection) src/a.sh:11';   expect "prose before the citation" 1 "(by" cev
rv '- [met] item | evidence: src/a.sh:10-12';                expect "evidence range in hunk" 0 "" cev
rv '- [met] item | evidence: src/a.sh:10-13';                expect "evidence range past hunk" 1 "src/a.sh:10-13" cev
rv '- [met] item | evidence: src/a.sh:11, log.txt:9';        expect "one bad of two citations" 1 "log.txt:9" cev
rv '- [not met] item
- [can'"'"'t tell] item
- [n/a] item';                                               expect "only non-met items need no citation" 0 "" cev
rv '- [met] ok | evidence: src/a.sh:11
- [met] bad | evidence: src/a.sh:99';                        expect "second item bad" 1 "src/a.sh:99" cev
printf 'VERDICT: SHIP\n' > "$fx/review.txt";                 expect "review with no met items" 0 "" cev
expect "evidence missing review" 1 "review" "$ev" "$fx/none.txt" "$fx/diff.txt" "$fx/log.txt"
rv '- [met] item | evidence: log.txt:1'
expect "evidence missing diff" 1 "diff" "$ev" "$fx/review.txt" "$fx/none.txt" "$fx/log.txt"
expect "evidence missing log" 1 "log" "$ev" "$fx/review.txt" "$fx/diff.txt" "$fx/none.txt"
: > "$fx/empty.txt"
expect "evidence empty diff" 1 "diff" "$ev" "$fx/review.txt" "$fx/empty.txt" "$fx/log.txt"
expect "evidence empty log" 1 "log" "$ev" "$fx/review.txt" "$fx/diff.txt" "$fx/empty.txt"
expect "evidence no arguments" 1 "usage" "$ev"

# The wiring: the worker contract runs check-evidence.sh, the reviewer treats missing input as FIX FIRST.
grep -q 'check-evidence.sh' .claude/skills/dispatch/worker-contract.md \
  || { echo "kit-check: worker-contract.md does not run check-evidence.sh"; exit 1; }
grep -qE 'missing or empty.*FIX FIRST' .claude/agents/reviewer.md \
  || { echo "kit-check: reviewer.md does not make a missing or empty diff.txt/log.txt FIX FIRST"; exit 1; }

echo "kit-check: all checks passed ($count shell scripts)"
