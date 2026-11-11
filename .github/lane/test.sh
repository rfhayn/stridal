#!/usr/bin/env bash
# Self-test for lane.sh. Run: sh .github/lane/test.sh (from any cwd).
# `sh` is dash on Linux, which has no [[ ]]; run under bash whatever started us.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lane="$here/lane.sh"
total=0; fail=0
HP='^(src/db/migrate|\.env[^/]*$|\.github/)'
# [out=TEXT] case_ NAME EXPECT_EXIT SUBCOMMAND [VAR=value ...]   (out: the output must also contain TEXT)
case_() {
  local name=$1 want=$2 sub=$3 need=${out:-}; shift 3
  out=   # a prefix assignment persists when sh runs bash in POSIX mode, so clear it here
  total=$((total+1))
  local o; o=$(env -i PATH="$PATH" "$@" bash "$lane" "$sub" 2>&1)
  local got=$?
  if [ "$got" != "$want" ]; then fail=$((fail+1)); echo "FAIL $name: want exit $want, got $got"
  elif [[ "$o" != *"$need"* ]]; then fail=$((fail+1)); echo "FAIL $name: output lacks '$need'"; fi
}
NL=$'\n'
CR=$'\r'
case_ "body ok" 0 body "PR_BODY=Why: x"
case_ "body why placeholder" 1 body "PR_BODY=Why: <one line>"
case_ "body no why" 1 body "PR_BODY=nothing here"
case_ "body crlf" 0 body "PR_BODY=Why: x${CR}${NL}"
L3="LABELS=lane:3-hard${NL}merge-ok"
case_ "lane no labels" 1 lane "LABELS=" "FILES=src/a.ts" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 1 plain" 0 lane "LABELS=lane:1-contained" "FILES=src/a.ts" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 1 hard file" 1 lane "LABELS=lane:1-contained" "FILES=.github/workflows/lane.yml" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 3 no merge-ok" 1 lane "LABELS=lane:3-hard" "FILES=.github/x" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 3 merge-ok by the approver" 0 lane "$L3" "FILES=.github/x" "MERGE_OK_BY=owner" "HARD_PATHS=$HP" "APPROVER=owner"
out="not owner" case_ "lane 3 merge-ok by actions bot" 1 lane "$L3" "FILES=.github/x" "MERGE_OK_BY=github-actions[bot]" "HARD_PATHS=$HP" "APPROVER=owner"
out="not owner" case_ "lane 3 merge-ok empty actor" 1 lane "$L3" "FILES=.github/x" "MERGE_OK_BY=" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 3 label 'x merge-ok' is not merge-ok" 1 lane "LABELS=lane:3-hard${NL}x merge-ok" "FILES=.github/x" "MERGE_OK_BY=owner" "HARD_PATHS=$HP" "APPROVER=owner"
# ADR-0004: the agents' machine user is a write collaborator; its label must never count as the approver's.
out="not owner" case_ "lane 3 merge-ok by the agent identity" 1 lane "$L3" "FILES=.github/x" "MERGE_OK_BY=owner-bot" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 3 merge-ok app actor" 1 lane "$L3" "FILES=.github/x" "MERGE_OK_BY=app:some-app" "HARD_PATHS=$HP" "APPROVER=owner"
case_ "lane 1 rename out of hard" 1 lane "LABELS=lane:1-contained" "FILES=src/db/migrate/a.sql${NL}src/renamed.sql" "HARD_PATHS=$HP" "APPROVER=owner"
out="APPROVER is empty" case_ "lane fails closed with no approver" 1 lane "$L3" "FILES=.github/x" "MERGE_OK_BY=" "HARD_PATHS=$HP"
out="HARD_PATHS is empty" case_ "lane fails closed with no hard paths" 1 lane "LABELS=lane:1-contained" "FILES=src/a.ts" "APPROVER=owner"
echo "$((total-fail))/$total passed"
[ "$fail" = 0 ]
