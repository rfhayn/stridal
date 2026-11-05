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

# The worker-session files ship, and session.sh keeps its executable bit in the install.
for f in .claude/bin/session.sh .claude/skills/land/SKILL.md; do
  [ -f "$d/$f" ] || { echo "kit-check: $f is missing from a new project"; exit 1; }
  cmp -s "$f" "$d/$f" || { echo "kit-check: installed $f differs from the kit's"; exit 1; }
done
[ -x "$d/.claude/bin/session.sh" ] || { echo "kit-check: installed session.sh is not executable"; exit 1; }

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
trap 'rm -rf "$tmp" "$rev"/spawn-zz-* "$rev/spawn-$long42.md" "${gcd:-/nonexistent}"/spawn/zz-*' EXIT
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
  refuses open "$bad" zz-ok --report-to main --dry-run
done
# "\$(" is literal text that must be refused, never expanded.
for bad in "a b" "Upper" 'a;b' "a\$(id)" "\$(id)" "-lead" "trail-" "a_b" "a/b" "$long43" ""; do
  refuses open feat "$bad" --report-to main --dry-run
  refuses close "$bad" --dry-run
done
for bad in "a b" 'a;b' "a\$(id)" "x'y" "" "-x" "--dry-run"; do
  refuses open feat zz-ok --report-to "$bad" --dry-run
done
refuses open feat zz-ok --dry-run
refuses open feat zz-ok --report-to main --bogus --dry-run
# There is no path argument: a path, .env included, is refused and never read.
echo "SECRET-ENV-TEXT" > "$tmp/.env"
refuses open feat zz-ok "$tmp/.env" --report-to main --dry-run
refuses open feat zz-ok .env --report-to main --dry-run
refuses open feat zz-ok "$rev/spawn-zz-ok.md" --report-to main --dry-run
refuses open feat .env --report-to main --dry-run
# The prompt file: missing, a symlink (even to a real file), a directory, over 20 KB.
refuses open feat zz-none --report-to main --dry-run
ln -s "$tmp/.env" "$rev/spawn-zz-link.md"
refuses open feat zz-link --report-to main --dry-run
mkdir "$rev/spawn-zz-dir.md"
refuses open feat zz-dir --report-to main --dry-run
head -c 20481 /dev/zero > "$rev/spawn-zz-big.md"
refuses open feat zz-big --report-to main --dry-run
head -c 20480 /dev/zero > "$rev/spawn-zz-edge.md"
"$sess" open feat zz-edge --report-to main --dry-run >/dev/null \
  || { echo "kit-check: session.sh refused a 20480-byte prompt"; exit 1; }
refuses close zz-ok --bogus --dry-run
refuses frobnicate zz-ok --dry-run

gcd=$(git rev-parse --path-format=absolute --git-common-dir)
out=$("$sess" open feat zz-ok --report-to main --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run open failed: $out"; exit 1; }
# The tab runs through the login shell so a worker gets the user's PATH (gh, shellcheck); only validated tokens go in.
want="/bin/zsh -lc 'exec $(command -v claude || echo claude) --name zz-ok --permission-mode auto -- \"\$(cat $gcd/spawn/zz-ok.prompt)\"'"
[ "$(printf '%s\n' "$out" | grep '^tab command: ')" = "tab command: $want" ] \
  || { echo "kit-check: session.sh tab command is not exactly: $want"; printf '%s\n' "$out"; exit 1; }
case "$out" in *SECRET-ENV-TEXT*) echo "kit-check: session.sh dry-run printed .env text"; exit 1 ;; esac
case "$out" in *SECRET-PROMPT-TEXT*) echo "kit-check: session.sh dry-run printed the prompt text"; exit 1 ;; esac
case "$out" in *"tell application \"Ghostty\""*) ;; *) echo "kit-check: session.sh dry-run did not print the AppleScript"; exit 1 ;; esac
"$sess" open fix "$long42" --report-to a_B-9 --dry-run >/dev/null \
  || { echo "kit-check: session.sh refused a 42-character slug"; exit 1; }
out=$("$sess" close zz-ok --abandon --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run close failed: $out"; exit 1; }
[ ! -e "$gcd/spawn/zz-ok.prompt" ] && [ ! -e "$gcd/spawn/zz-ok.term" ] \
  || { echo "kit-check: session.sh dry-run wrote files"; exit 1; }
git worktree list | grep -q 'zz-ok' && { echo "kit-check: session.sh dry-run created a worktree"; exit 1; }

# send types one fixed command, /ship, into a worker's recorded terminal. Everything else is refused.
refuses send zz-ok ship --dry-run   # no .term record yet
mkdir -p "$gcd/spawn"
echo "FAKE-TERM-ID-1" > "$gcd/spawn/zz-ok.term"
for bad in "merge" "exit" "/ship" "ship x" "ship;id" "ship\$(id)" ""; do
  refuses send zz-ok "$bad" --dry-run
done
refuses send zz-ok --dry-run
refuses send zz-ok ship x --dry-run
refuses send zz-ok ship --bogus --dry-run
refuses send zz-none ship --dry-run
for bad in "a b" 'a;b' "a\$(id)" "Upper" "-lead" "$long43" ""; do
  refuses send "$bad" ship --dry-run
done
out=$("$sess" send zz-ok ship --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run send failed: $out"; exit 1; }
case "$out" in *'input text "/ship" to term'*'send key "enter" to term'*) ;; *) echo "kit-check: send dry-run did not print the /ship AppleScript"; printf '%s\n' "$out"; exit 1 ;; esac
case "$out" in *'input text "/exit"'*) echo "kit-check: send dry-run printed the /exit AppleScript"; exit 1 ;; esac

# The open tab command starts with the login shell and holds only validated tokens.
out=$("$sess" open feat zz-ok --report-to main --dry-run 2>&1)
tabline=$(printf '%s\n' "$out" | grep '^tab command: ')
case "$tabline" in "tab command: /bin/zsh -lc '"*) ;; *) echo "kit-check: tab command does not start with /bin/zsh -lc: $tabline"; exit 1 ;; esac
rest=${tabline#"tab command: /bin/zsh -lc '"}
[[ $rest =~ ^exec\ [A-Za-z0-9/._-]+\ --name\ zz-ok\ --permission-mode\ auto\ --\ \"\$\(cat\ [A-Za-z0-9/._-]+\)\"\'$ ]] \
  || { echo "kit-check: tab command holds something other than validated tokens: $tabline"; exit 1; }

# close when the worktree and the recorded branch are already gone: a cleanup plan, not a refusal.
echo "feat/zz-ok" > "$gcd/spawn/zz-ok.branch"
out=$("$sess" close zz-ok --dry-run 2>&1) \
  || { echo "kit-check: close --dry-run refused when worktree and branch are gone: $out"; exit 1; }
case "$out" in *"already gone"*"delete $gcd/spawn/zz-ok."*) ;; *) echo "kit-check: close --dry-run did not print the cleanup plan"; printf '%s\n' "$out"; exit 1 ;; esac
case "$out" in *"git worktree remove"*|*"git branch -D"*) echo "kit-check: cleanup plan removes a branch or worktree"; exit 1 ;; esac
[ -e "$gcd/spawn/zz-ok.term" ] || { echo "kit-check: close --dry-run deleted records"; exit 1; }
rm -f "$gcd/spawn/zz-ok.term" "$gcd/spawn/zz-ok.branch"

# sync runs the one fixed command git pull --ff-only in the main checkout. It takes no slug and no other argument.
out=$("$sess" sync --dry-run 2>&1) \
  || { echo "kit-check: sync --dry-run failed: $out"; exit 1; }
[ "$out" = "git pull --ff-only" ] \
  || { echo "kit-check: sync --dry-run did not print exactly: git pull --ff-only"; printf '%s\n' "$out"; exit 1; }
for bad in x "x --dry-run" "--dry-run x" "--bogus" "--abandon" "zz-ok" ".env"; do
  # shellcheck disable=SC2086  # $bad is deliberately split into words
  refuses sync $bad
done
# A real sync from a worktree is refused before anything runs. The scratch repo has no remote, so even a
# script that wrongly ran the pull would only fail.
sr="$tmp/syncrepo"
git init -q "$sr"
git -C "$sr" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
git -C "$sr" worktree add -q "$sr/wt" -b zz-sync-wt
if out=$(cd "$sr/wt" && "$OLDPWD/$sess" sync 2>&1); then echo "kit-check: sync ran from a worktree"; exit 1; fi
case "$out" in *"session.sh: refused"*"main checkout"*) ;; *) echo "kit-check: sync from a worktree gave no refusal: $out"; exit 1 ;; esac

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
# Claude Code runs statusline.sh outside the sandbox, so it is guarded like session.sh: ask on Edit/Write, no sandboxed writes.
jq -e '(.permissions.ask | index("Edit(./**/.claude/statusline.sh)") != null) and (.permissions.ask | index("Write(./**/.claude/statusline.sh)") != null)
       and (.sandbox.filesystem.denyWrite | index("./.claude/statusline.sh") != null) and (.sandbox.filesystem.denyWrite | index("./**/.claude/statusline.sh") != null)' \
  .claude/settings.json >/dev/null || { echo "kit-check: statusline.sh is not guarded in settings.json (ask Edit/Write, sandbox denyWrite)"; exit 1; }
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

echo "kit-check: all checks passed ($count shell scripts)"
