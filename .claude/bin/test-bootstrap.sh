#!/usr/bin/env bash
# Self-test for bootstrap.sh's lock, --upgrade and --adopt (#452, ADR-0007). Run by kit-check.sh; not copied to new projects.
# Everything happens in a temp directory: the kit is copied twice (an old one to install from, a changed one to upgrade from).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-bootstrap.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

die() { echo "test-bootstrap: $*"; exit 1; }
tree() { (cd "$1" && find . -type f | sort | xargs cksum); }
has() { case "$2" in *"$3"*) ;; *) die "$1: output lacks '$3': $2" ;; esac; }
lacks() { case "$2" in *"$3"*) die "$1: output has '$3': $2" ;; esac; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

copy_kit() { # copy_kit <dir>: the kit's files, committed or not
  mkdir -p "$1"
  git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -xf - -C "$1"
}
copy_kit "$tmp/kit-old"; copy_kit "$tmp/kit-new"
old="$tmp/kit-old/bootstrap.sh"; new="$tmp/kit-new/bootstrap.sh"
version=$(tr -d '[:space:]' < VERSION)
case "$version" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "VERSION is not x.y.z: $version" ;; esac

# 1. A fresh install writes the lock: version, runner, and a sha256 per file; a second run changes nothing.
p="$tmp/proj"
"$old" "$p" hosted >/dev/null || die "fresh install failed"
lock="$p/.claude/kit.lock"
[ -f "$lock" ] || die "install wrote no .claude/kit.lock"
grep -qx "version $version" "$lock" || die "lock has no 'version $version' line"
grep -qx "runner hosted" "$lock" || die "lock has no 'runner hosted' line"
entries=$(grep -cE '^[0-9a-f]{64}  [^ ]+$' "$lock")
[ "$entries" -gt 30 ] || die "lock has only $entries hash lines"
grep -qE "^$(sha "$p/.claude/agents/reviewer.md")  .claude/agents/reviewer.md$" "$lock" || die "lock hash for reviewer.md is not the file's sha256"
grep -qE "^$(sha "$p/CLAUDE.md")  CLAUDE.md$" "$lock" || die "lock has no correct hash for CLAUDE.md"
[ "$(grep -c . "$lock")" -eq $((entries + 3)) ] || die "lock has lines other than header, version, runner and hashes"
tree "$p" > "$tmp/tree.1"
"$old" "$p" hosted >/dev/null || die "second install run failed"
tree "$p" > "$tmp/tree.2"
cmp -s "$tmp/tree.1" "$tmp/tree.2" || die "a second bootstrap.sh run changed the project"

# 2. Right after an install, upgrade has nothing to do, for either runner.
out=$("$new" --upgrade "$p") || die "upgrade of a fresh install failed"
has "fresh dry run" "$out" "Dry run"; has "fresh dry run" "$out" "0 to add, 0 to replace, 0 kept as edited"
s="$tmp/proj-self"
"$old" "$s" self-hosted >/dev/null || die "self-hosted install failed"
grep -qx "runner self-hosted" "$s/.claude/kit.lock" || die "self-hosted lock lacks its runner line"
out=$("$new" --upgrade "$s") || die "upgrade of a self-hosted install failed"
has "self-hosted fresh" "$out" "0 to add, 0 to replace, 0 kept as edited"

# 3. Set up the five cases. In the project: one file missing, one edited (and changed in the kit), one edited
#    (kit unchanged), a lock line for a file the kit no longer lists, CLAUDE.md edited. In the new kit: a replaced
#    file, the edited one, a changed template, a bumped version.
rm "$p/.claude/agents/researcher.md"
echo "local edit" >> "$p/.claude/agents/reviewer.md"
echo "local edit" >> "$p/docs/RISKS.md"
echo "local edit" >> "$p/CLAUDE.md"
echo "old kit file" > "$p/docs/old-file.md"
echo "$(sha "$p/docs/old-file.md")  docs/old-file.md" >> "$lock"
echo "# kit change" >> "$tmp/kit-new/.claude/bin/scope-check.sh"
echo "# kit change" >> "$tmp/kit-new/.claude/agents/reviewer.md"
echo "# kit change" >> "$tmp/kit-new/CLAUDE.template.md"
echo "9.9.9" > "$tmp/kit-new/VERSION"
cp -p "$p/CLAUDE.md" "$tmp/CLAUDE.before"; cp "$lock" "$tmp/lock.before"

# 4. Dry run: changes nothing on disk, prints the plan.
tree "$p" > "$tmp/tree.before"
out=$("$new" --upgrade "$p") || die "upgrade dry run failed"
tree "$p" > "$tmp/tree.after"
cmp -s "$tmp/tree.before" "$tmp/tree.after" || die "upgrade without --apply changed the project"
has "dry run" "$out" "would add: .claude/agents/researcher.md"
has "dry run" "$out" "would replace (never edited): .claude/bin/scope-check.sh"
has "dry run" "$out" "keep (edited here, kit changed): .claude/agents/reviewer.md"
has "dry run" "$out" "keep (edited here, kit unchanged): docs/RISKS.md"
has "dry run" "$out" "dropped from the kit"; has "dry run" "$out" "docs/old-file.md"
has "dry run" "$out" "CLAUDE.md is never touched"
has "dry run" "$out" "+# kit change"

# 5. --apply: adds, replaces, leaves edits alone and writes .kit-new, reports the dropped file, never touches CLAUDE.md.
out=$("$new" --upgrade "$p" --apply) || die "upgrade --apply failed"
cmp -s "$tmp/kit-new/.claude/agents/researcher.md" "$p/.claude/agents/researcher.md" || die "missing file was not added"
[ -x "$p/.claude/agents/researcher.md" ] || [ ! -x "$tmp/kit-new/.claude/agents/researcher.md" ] || die "added file lost its mode"
cmp -s "$tmp/kit-new/.claude/bin/scope-check.sh" "$p/.claude/bin/scope-check.sh" || die "unedited file was not replaced"
[ -x "$p/.claude/bin/scope-check.sh" ] || die "replaced script lost its executable bit"
grep -q "local edit" "$p/.claude/agents/reviewer.md" || die "an edited file was overwritten"
[ "$(tail -n 1 "$p/.claude/agents/reviewer.md")" = "local edit" ] || die "an edited file was changed"
cmp -s "$tmp/kit-new/.claude/agents/reviewer.md" "$p/.claude/agents/reviewer.md.kit-new" || die "reviewer.md.kit-new is not the kit's copy"
[ ! -e "$p/docs/RISKS.md.kit-new" ] || die "wrote .kit-new for a file whose kit copy did not change"
cmp -s "$tmp/CLAUDE.before" "$p/CLAUDE.md" || die "upgrade modified CLAUDE.md"
[ ! -e "$p/CLAUDE.md.kit-new" ] || die "upgrade wrote CLAUDE.md.kit-new"
[ -f "$p/docs/old-file.md" ] || die "upgrade deleted a file dropped from the kit"
has "apply" "$out" "dropped from the kit"
# The lock: changed files carry the new hash, everything else is as it was, the version moves.
grep -qE "^$(sha "$p/.claude/bin/scope-check.sh")  .claude/bin/scope-check.sh$" "$lock" || die "lock lacks the new hash for the replaced file"
grep -qE "^$(sha "$p/.claude/agents/researcher.md")  .claude/agents/researcher.md$" "$lock" || die "lock lacks the added file's hash"
grep -qx "version 9.9.9" "$lock" || die "lock version did not move to 9.9.9"
sort "$tmp/lock.before" > "$tmp/lock.before.sorted"; sort "$lock" > "$tmp/lock.after.sorted"   # the hand-appended line was out of order
changed=$(diff "$tmp/lock.before.sorted" "$tmp/lock.after.sorted" | grep -c '^[<>] [0-9a-f]\{64\}' || true)
[ "$changed" -eq 2 ] || die "lock changed $changed hash lines, wanted 2 (the replaced file out and in; the re-added file keeps its hash)"
grep -q "  docs/old-file.md$" "$lock" || die "lock lost the dropped file's line"
# A second apply finds the edits still edited and does nothing more.
tree "$p" > "$tmp/tree.before"
"$new" --upgrade "$p" --apply >/dev/null || die "second upgrade --apply failed"
tree "$p" > "$tmp/tree.after"
cmp -s "$tmp/tree.before" "$tmp/tree.after" || die "a second upgrade --apply changed the project"

# 6. A project with no lock: upgrade fails with a clear message and writes nothing; --adopt writes a lock.
q="$tmp/proj-old"
"$old" "$q" hosted >/dev/null; rm "$q/.claude/kit.lock"
echo "local edit" >> "$q/docs/RISKS.md"
tree "$q" > "$tmp/tree.before"
rc=0; out=$("$new" --upgrade "$q" --apply 2>&1) || rc=$?
[ "$rc" -ne 0 ] || die "upgrade of a project with no lock exited 0"
has "no lock" "$out" "no .claude/kit.lock"; has "no lock" "$out" "--adopt"
tree "$q" > "$tmp/tree.after"
cmp -s "$tmp/tree.before" "$tmp/tree.after" || die "upgrade with no lock wrote something"
out=$("$old" --adopt "$q") || die "adopt failed"
has "adopt" "$out" "docs/RISKS.md"
grep -qx -e "-  docs/RISKS.md" "$q/.claude/kit.lock" || die "adopt did not record an edited file as -"
grep -qE "^$(sha "$q/.claude/bin/session.sh")  .claude/bin/session.sh$" "$q/.claude/kit.lock" || die "adopt did not hash a matching file"
rc=0; "$old" --adopt "$q" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || die "adopt overwrote an existing lock"
out=$("$new" --upgrade "$q") || die "upgrade after adopt failed"
# An adopted edit has no recorded baseline ("-"), so the kit's copy always lands beside it; matching files upgrade normally.
has "after adopt" "$out" "keep (edited here, kit changed): docs/RISKS.md"
has "after adopt" "$out" "would replace (never edited): .claude/bin/scope-check.sh"
lacks "after adopt" "$out" "would add"

# 7. Bad calls are refused without writing.
for bad in "--upgrade" "--upgrade $tmp/nope" "--upgrade $p --bogus" "--adopt" "--adopt $tmp/nope"; do
  # shellcheck disable=SC2086  # the words are the arguments
  if "$new" $bad >/dev/null 2>&1; then die "bootstrap.sh accepted: $bad"; fi
done
# 8. Kit dependencies (#460): .claude/kit.deps lists which kit files need which. Every path in it is a kit file.
deps=.claude/kit.deps
[ -f "$deps" ] || die "no $deps"
n_deps=0
while IFS=: read -r df needs; do
  case "$df" in "#"*|"") continue ;; esac
  n_deps=$((n_deps + 1))
  for f in $df $needs; do
    [ -e "$f" ] || die "$deps names $f, which is not in the kit"
    grep -qE "(^|[ (])$f([ )]|\$)" bootstrap.sh || die "$deps names $f, which is not in bootstrap.sh's file list"
  done
done < "$deps"
grep -qx ".claude/bin/scope-check.sh: .claude/bin/dispatch-next.sh" "$deps" || die "$deps lacks scope-check.sh -> dispatch-next.sh"
[ "$n_deps" -ge 1 ] || die "$deps has no entries"
# A kit script that calls another by path must be listed with it (flags like --footprint-of live in the callee).
grep -q 'here/dispatch-next.sh' .claude/bin/scope-check.sh || die "scope-check.sh no longer calls dispatch-next.sh: update $deps"

# 9. A project whose dispatch-next.sh was edited and lacks scope-check.sh: the add warns, naming the .kit-new to merge.
r="$tmp/proj-deps"
"$old" "$r" hosted >/dev/null
rm "$r/.claude/bin/scope-check.sh"
echo "local edit" >> "$r/.claude/bin/dispatch-next.sh"
echo "# kit change" >> "$tmp/kit-new/.claude/bin/dispatch-next.sh"
tree "$r" > "$tmp/tree.before"
out=$("$new" --upgrade "$r") || die "deps dry run failed"
tree "$r" > "$tmp/tree.after"
cmp -s "$tmp/tree.before" "$tmp/tree.after" || die "deps dry run changed the project"
has "deps dry run" "$out" "would add: .claude/bin/scope-check.sh"
has "deps dry run" "$out" "WARNING: .claude/bin/scope-check.sh needs .claude/bin/dispatch-next.sh"
has "deps dry run" "$out" ".claude/bin/dispatch-next.sh.kit-new"
out=$("$new" --upgrade "$r" --apply) || die "deps --apply failed"
has "deps apply" "$out" "WARNING: .claude/bin/scope-check.sh needs .claude/bin/dispatch-next.sh"
has "deps apply" "$out" "Merge .claude/bin/dispatch-next.sh.kit-new"
tail -n 1 "$r/.claude/bin/dispatch-next.sh" | grep -qx "local edit" || die "deps apply changed the edited file"
cmp -s "$tmp/kit-new/.claude/bin/dispatch-next.sh" "$r/.claude/bin/dispatch-next.sh.kit-new" || die "deps apply: dispatch-next.sh.kit-new is not the kit's copy"
cmp -s "$tmp/kit-new/.claude/bin/scope-check.sh" "$r/.claude/bin/scope-check.sh" || die "deps apply did not add scope-check.sh"
# 9b. A kept file whose kit copy did not change warns too, without naming a .kit-new (the old kit is the same kit).
r2="$tmp/proj-deps2"
"$old" "$r2" hosted >/dev/null
rm "$r2/.claude/bin/scope-check.sh"
echo "local edit" >> "$r2/.claude/bin/dispatch-next.sh"
out=$("$old" --upgrade "$r2") || die "deps unchanged dry run failed"
has "unchanged kept file" "$out" "WARNING: .claude/bin/scope-check.sh needs .claude/bin/dispatch-next.sh"
lacks "unchanged kept file" "$out" "kit-new into"

# 10. No warning when the needed file is current in the project.
t="$tmp/proj-nowarn"
"$old" "$t" hosted >/dev/null
rm "$t/.claude/bin/scope-check.sh"
out=$("$new" --upgrade "$t") || die "nowarn dry run failed"
has "nowarn" "$out" "would add: .claude/bin/scope-check.sh"
lacks "nowarn" "$out" "WARNING"
out=$("$new" --upgrade "$t" --apply) || die "nowarn --apply failed"
lacks "nowarn apply" "$out" "WARNING"
echo "test-bootstrap: ok"
