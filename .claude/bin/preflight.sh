#!/usr/bin/env bash
# Offline structural check of a brief, run by /ship before any review.
# Usage: .claude/bin/preflight.sh <brief-file> [--merged <PR#>]...
# Exits 0 if the brief has a Done-when list, a Files line and a Lane line, and every `Blocked by: #N`
# has a matching --merged N. Exits 1 and says why on stdout otherwise.
# It never calls gh: /ship looks up each blocker's state and passes the MERGED ones in, so a blocker
# nobody vouched for fails closed.
set -euo pipefail

usage() { echo "preflight: usage: preflight.sh <brief-file> [--merged <PR#>]..."; exit 1; }
[ $# -ge 1 ] || usage
brief=$1; shift
merged=" "
while [ $# -gt 0 ]; do
  case "$1" in
    --merged)
      [ $# -ge 2 ] || usage
      [[ $2 =~ ^[0-9]+$ ]] || { echo "preflight: --merged needs a PR number, got '$2'"; exit 1; }
      merged="$merged$2 "; shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$brief" ] && [ -s "$brief" ] || { echo "preflight: brief file '$brief' is missing or empty"; exit 1; }

bad=0
fail() { echo "preflight: $1"; bad=1; }

# Done when: a heading line followed by at least one checklist item.
awk '/^Done when/ {seen = 1; next} seen && /^- \[[ xX]\] +[^ ]/ {found = 1} END {exit !found}' "$brief" \
  || fail "the brief has no 'Done when' list with at least one '- [ ]' item"
grep -Eq '^Files:[[:space:]]*[^[:space:]]' "$brief" || fail "the brief has no non-empty 'Files:' line"
grep -Eq '^Lane:[[:space:]]*[123]' "$brief" || fail "the brief has no 'Lane:' line starting with 1, 2 or 3"

# Every blocker must have been vouched for as merged. Text after the Blocked by line's #N list is ignored.
while IFS= read -r n; do
  case "$merged" in
    *" $n "*) ;;
    *) fail "blocked by #$n, which is not merged (no --merged $n)" ;;
  esac
done < <(grep -E '^Blocked by:' "$brief" | grep -oE '#[0-9]+' | tr -d '#' | sort -un || true)

exit "$bad"
