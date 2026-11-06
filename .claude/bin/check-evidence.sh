#!/usr/bin/env bash
# Checks that every reviewer "met" cites a line that exists.
# Usage: .claude/bin/check-evidence.sh <review-output> <diff.txt> <log.txt>
# Reads each `- [met] <item> | evidence: <path:line>[, <path:line>]` line of the review. A citation passes when
# path is a file in the diff and line falls inside one of its `+` hunks, or path is log.txt and line is within
# its length. A met item with no citation, or a citation that does not pass, is named on stdout and exits 1.
# Other statuses (not met, can't tell, n/a) are not checked. A missing or empty diff or log is a failure.
set -euo pipefail

[ $# -eq 3 ] || { echo "check-evidence: usage: check-evidence.sh <review-output> <diff.txt> <log.txt>"; exit 1; }
review=$1; diff=$2; log=$3
[ -s "$review" ] || { echo "check-evidence: review output '$review' is missing or empty"; exit 1; }
[ -s "$diff" ] || { echo "check-evidence: diff '$diff' is missing or empty"; exit 1; }
[ -s "$log" ] || { echo "check-evidence: log '$log' is missing or empty"; exit 1; }
loglines=$(wc -l < "$log" | tr -d ' ')

# One "path start end" row per added range; a deleted file (+++ /dev/null) has none.
ranges=$(awk '
  /^\+\+\+ / { f = ($2 ~ /^b\//) ? substr($2, 3) : ""; next }
  /^@@ / && f != "" {
    plus = $3; sub(/^\+/, "", plus)
    n = split(plus, p, ",")
    start = p[1]; len = (n > 1) ? p[2] : 1
    if (len > 0) print f, start, start + len - 1
  }' "$diff")

bad=0
fail() { echo "check-evidence: $1"; bad=1; }

while IFS= read -r line; do
  item=${line#*] }
  case "$line" in
    *"| evidence:"*) cites=${line#*| evidence:} ;;
    *) cites="" ;;
  esac
  cites=$(printf '%s' "$cites" | tr ',' ' ')
  # shellcheck disable=SC2086  # split the citations on whitespace
  set -- $cites
  if [ $# -eq 0 ]; then fail "no evidence cited for met item: $item"; continue; fi
  # The citations are the leading run of path:line or path:start-end tokens; prose after them, such as
  # "(by inspection)", is ignored. The first token must be a citation.
  first=1
  for c in "$@"; do
    if [[ ! $c =~ ^(.+):([0-9]+)(-([0-9]+))?$ ]]; then
      [ "$first" -eq 0 ] || fail "evidence '$c' is not path:line (met item: $item)"
      break
    fi
    first=0
    path=${BASH_REMATCH[1]}; num=${BASH_REMATCH[2]}; end=${BASH_REMATCH[4]:-${BASH_REMATCH[2]}}
    if [ "$path" = log.txt ]; then
      { [ "$num" -ge 1 ] && [ "$end" -le "$loglines" ]; } || fail "evidence $c is outside log.txt (it has $loglines lines)"
      continue
    fi
    if ! printf '%s\n' "$ranges" | awk -v p="$path" -v a="$num" -v b="$end" '$1 == p && a >= $2 && b <= $3 {ok = 1} END {exit !ok}'; then
      if printf '%s\n' "$ranges" | awk -v p="$path" '$1 == p {ok = 1} END {exit !ok}'; then
        fail "evidence $c is outside the added lines of $path in the diff"
      else
        fail "evidence $c: $path is not in the diff"
      fi
    fi
  done
done < <(grep -E '^[[:space:]]*- \[met\]' "$review" || true)

exit "$bad"
