#!/usr/bin/env bash
# Deterministic scope check: does the branch touch only the files the brief (or the issue's Footprint) listed?
# Usage: .claude/bin/scope-check.sh 'apps/web/src/standings/**' 'packages/engine/src/score.ts' ...
#        .claude/bin/scope-check.sh --footprint <issue-body-file> [glob...]
# Globs use bash pattern matching (** behaves like *). Exits 0 if in scope, 1 and lists strays otherwise.
# --footprint: each path on the issue body's Footprint line, read by `dispatch-next.sh --footprint-of` (the one
# Footprint parser, Stridal's ADR-0005), is in scope as itself and as a directory (<path>/*). Extra globs (the PR's
# "Footprint grew:" paths) count too. No Footprint line, a placeholder (none) or an unsafe value = nothing to check
# against (Stridal's ADR-0005 runs such an item alone): prints a notice and exits 0, unless extra globs were given.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
globs=()
if [ "${1:-}" = "--footprint" ]; then
  [ $# -ge 2 ] || { echo "usage: scope-check.sh --footprint <issue-body-file> [glob...]"; exit 2; }
  [ -r "$2" ] && [ -f "$2" ] || { echo "scope-check: cannot read $2"; exit 2; }
  fp=$("$here/dispatch-next.sh" --footprint-of "$2") || { echo "scope-check: cannot read the Footprint of $2"; exit 2; }
  shift 2
  while IFS= read -r p; do [ -n "$p" ] && globs+=("$p" "$p/*"); done <<<"$fp"
  if [ ${#globs[@]} -eq 0 ] && [ $# -eq 0 ]; then
    echo "scope-check: no Footprint, scope not checked"
    exit 0
  fi
fi
globs+=("$@")
[ ${#globs[@]} -gt 0 ] || { echo "usage: scope-check.sh <glob>... | --footprint <issue-body-file> [glob...]"; exit 2; }
base=$(git merge-base origin/main HEAD) || exit 2
stray=0
# shellcheck disable=SC2053  # $g stays unquoted on purpose: quoting it would stop every glob matching.
while IFS= read -r f; do
  ok=0; for g in "${globs[@]}"; do [[ "$f" == $g ]] && { ok=1; break; }; done
  [ $ok -eq 1 ] || { echo "OUT OF SCOPE: $f"; stray=1; }
done < <({ git diff --name-only "$base" HEAD; git diff --name-only; git ls-files --others --exclude-standard; } | sort -u)
[ $stray -eq 0 ] && echo "scope-check: all changed files are in the brief"
exit $stray
