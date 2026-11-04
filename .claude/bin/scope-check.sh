#!/usr/bin/env bash
# Deterministic scope check: does the branch touch only the files the brief listed?
# Usage: .claude/bin/scope-check.sh 'apps/web/src/standings/**' 'packages/engine/src/score.ts' ...
# Globs use bash pattern matching (** behaves like *). Exits 0 if in scope, 1 and lists strays otherwise.
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: scope-check.sh <glob>..."; exit 2; }
base=$(git merge-base origin/main HEAD) || exit 2
stray=0
while IFS= read -r f; do
  ok=0; for g in "$@"; do [[ "$f" == $g ]] && { ok=1; break; }; done
  [ $ok -eq 1 ] || { echo "OUT OF SCOPE: $f"; stray=1; }
done < <({ git diff --name-only "$base" HEAD; git diff --name-only; git ls-files --others --exclude-standard; } | sort -u)
[ $stray -eq 0 ] && echo "scope-check: all changed files are in the brief"
exit $stray
