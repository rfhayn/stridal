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
./bootstrap.sh "$d" hosted >/dev/null || { echo "kit-check: second bootstrap.sh run failed"; exit 1; }
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
pf="$tmp/spawn-prompt"
echo "SECRET-PROMPT-TEXT" > "$pf"
refuses() {
  local out
  if out=$("$sess" "$@" 2>&1); then echo "kit-check: session.sh accepted: $*"; exit 1; fi
  case "$out" in
    *"session.sh: refused"*) ;;
    *) echo "kit-check: session.sh failed without a refusal message for: $*"; exit 1 ;;
  esac
}
long43=$(printf 'a%.0s' $(seq 1 43))
long42=$(printf 'a%.0s' $(seq 1 42))
for bad in "bug" "feat/x" "FEAT" ""; do
  refuses open "$bad" zz-ok "$pf" --report-to main --dry-run
done
# "\$(" is literal text that must be refused, never expanded.
for bad in "a b" "Upper" 'a;b' "a\$(id)" "\$(id)" "-lead" "trail-" "a_b" "a/b" "$long43" ""; do
  refuses open feat "$bad" "$pf" --report-to main --dry-run
  refuses close "$bad" --dry-run
done
for bad in "a b" 'a;b' "a\$(id)" "x'y" ""; do
  refuses open feat zz-ok "$pf" --report-to "$bad" --dry-run
done
refuses open feat zz-ok "$pf" --dry-run
refuses open feat zz-ok "$tmp/no-such-prompt" --report-to main --dry-run
refuses open feat zz-ok "$pf" --report-to main --bogus --dry-run
refuses close zz-ok --bogus --dry-run
refuses frobnicate zz-ok --dry-run

gcd=$(git rev-parse --path-format=absolute --git-common-dir)
out=$("$sess" open feat zz-ok "$pf" --report-to main --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run open failed: $out"; exit 1; }
want="$(command -v claude || echo claude) --name zz-ok --permission-mode auto \"\$(cat $gcd/spawn/zz-ok.prompt)\""
[ "$(printf '%s\n' "$out" | grep '^tab command: ')" = "tab command: $want" ] \
  || { echo "kit-check: session.sh tab command is not exactly: $want"; printf '%s\n' "$out"; exit 1; }
case "$out" in *SECRET-PROMPT-TEXT*) echo "kit-check: session.sh dry-run printed the prompt text"; exit 1 ;; esac
case "$out" in *"tell application \"Ghostty\""*) ;; *) echo "kit-check: session.sh dry-run did not print the AppleScript"; exit 1 ;; esac
"$sess" open fix "$long42" "$pf" --report-to a_B-9 --dry-run >/dev/null \
  || { echo "kit-check: session.sh refused a 42-character slug"; exit 1; }
out=$("$sess" close zz-ok --abandon --dry-run 2>&1) \
  || { echo "kit-check: session.sh good dry-run close failed: $out"; exit 1; }
[ ! -e "$gcd/spawn/zz-ok.prompt" ] && [ ! -e "$gcd/spawn/zz-ok.term" ] \
  || { echo "kit-check: session.sh dry-run wrote files"; exit 1; }
git worktree list | grep -q 'zz-ok' && { echo "kit-check: session.sh dry-run created a worktree"; exit 1; }

echo "kit-check: all checks passed ($count shell scripts)"
