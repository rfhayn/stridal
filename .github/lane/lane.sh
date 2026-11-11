#!/usr/bin/env bash
# Merge-lane decision logic (lane judged by the base branch, ADR-0002).
# Runs from main's copy (a pull_request_target workflow checks out the default branch), so a PR cannot edit the
# rules that judge it. Pure function of env: no git, gh or network. The workflow fetches the facts.
#
#   lane.sh body   env PR_BODY
#   lane.sh lane   env LABELS (newline list, matched whole-line), FILES (newline list: every changed filename plus each
#                  previous_filename, so a move OUT of a hard path counts), HARD_PATHS (extended regex of this
#                  project's one-way paths; the workflow supplies it), MERGE_OK_BY (login on the latest `labeled`
#                  merge-ok event; empty if none), APPROVER (required: the `Approver:` login in CLAUDE.md's
#                  `## Dispatcher` block; empty fails closed)
set -euo pipefail

cmd=${1:-}

body() {
  local PR_BODY=${PR_BODY:-}
  local body why
  body=$(printf '%s\n' "$PR_BODY" | tr -d '\r')
  why=$(printf '%s\n' "$body" | sed -n 's/^Why:[[:space:]]*//p' | head -n1 | sed 's/[[:space:]]*$//')
  if [ -z "$why" ] || [ "$why" = "<one line>" ]; then
    echo "::error::PR body needs a real 'Why:' line (one line, not the <one line> placeholder). Edit the body to re-run."; exit 1
  fi
  echo "Why: $why"
}

lane() {
  local LABELS=${LABELS:-} FILES=${FILES:-} MERGE_OK_BY=${MERGE_OK_BY:-} APPROVER=${APPROVER:-} HARD_PATHS=${HARD_PATHS:-}
  local hard_files l lane=none
  [ -n "$HARD_PATHS" ] || { echo "::error::HARD_PATHS is empty; the workflow must supply this project's one-way paths."; exit 1; }
  hard_files=$(printf '%s\n' "$FILES" | grep -E "$HARD_PATHS" || true)
  has() { printf '%s\n' "$LABELS" | tr -d '\r' | grep -qxF "$1"; }   # whole label only: `x merge-ok` is not merge-ok
  for l in lane:1-contained lane:2-wide lane:3-hard; do
    if has "$l"; then lane=$l; fi
  done
  if [ -n "$hard_files" ]; then
    echo "Hard-to-reverse paths touched:"; echo "$hard_files"
    [ "$lane" = "lane:3-hard" ] || { echo "::error::Touches lane-3 paths; label the PR lane:3-hard."; exit 1; }
  fi
  [ "$lane" != none ] || { echo "::error::Add one lane label: lane:1-contained, lane:2-wide or lane:3-hard."; exit 1; }
  if [ "$lane" = "lane:3-hard" ]; then
    # Only lane 3 needs the approver, so a project that has not filled in its Dispatcher block still passes lanes 1
    # and 2 as it did before; lane 3 fails closed.
    [ -n "$APPROVER" ] || { echo "::error::APPROVER is empty; the workflow must read the Approver: login from CLAUDE.md, so lane 3 cannot be approved."; exit 1; }
    if ! has merge-ok; then
      echo "::error::Lane 3 waits for $APPROVER: they add the merge-ok label in GitHub, then the queued auto-merge lands it."; exit 1
    fi
    if [ "$MERGE_OK_BY" != "$APPROVER" ]; then
      echo "::error::merge-ok was added by '${MERGE_OK_BY}', not $APPROVER; only the approver's label counts."; exit 1
    fi
  fi
  echo "Lane OK: $lane"
}

case "$cmd" in
  body) body ;;
  lane) lane ;;
  *) echo "usage: lane.sh body|lane" >&2; exit 2 ;;
esac
