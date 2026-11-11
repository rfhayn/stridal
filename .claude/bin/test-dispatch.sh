#!/usr/bin/env bash
# Self-test for dispatch-next.sh. Run: bash .claude/bin/test-dispatch.sh (from any cwd).
# Fixtures (incl. a tiny git repo) are generated into a throwaway mktemp -d; gh is never called.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/test-dispatch.XXXXXX")   # macOS's bare mktemp -d ignores $TMPDIR
trap 'rm -rf "$T"' EXIT
total=0; fail=0
DISPATCH=${DISPATCH_UNDER_TEST:-$here/dispatch-next.sh}
mkdir -p "$T/issues" "$T/bin"
# A gh that always fails, first on PATH: a missing fixture hook can never reach the network.
# With FAKE_GH_PAGES set it records its argv to $FAKE_GH_ARGS and prints that file instead (the live board path).
cat > "$T/bin/gh" <<'EOF'
#!/bin/sh
if [ -n "${FAKE_GH_PAGES:-}" ]; then printf '%s\n' "$@" > "$FAKE_GH_ARGS"; cat "$FAKE_GH_PAGES"; exit 0; fi
echo "fake gh: no network in tests" >&2; exit 99
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
export DISPATCH_BOARD_JSON="$T/board.json" DISPATCH_ISSUE_DIR="$T/issues"

# item NUMBER STATUS TYPE  -> one board item (the board JSON gives order, status, type and number)
item() { printf '{"status":"%s","content":{"type":"%s","number":%s,"title":"t%s","body":"x"},"labels":null}' "$2" "$3" "$1" "$1"; }
# board ITEM...  -> {"items":[...],"totalCount":N}
board() { local IFS=,; printf '{"items":[%s],"totalCount":%s}\n' "$*" "$#" > "$T/board.json"; }
# issue NUMBER TITLE BODY STATE [LABEL...]  -> $T/issues/NUMBER.json as gh issue view would print it
issue() {
  local n=$1 title=$2 body=$3 state=$4; shift 4
  local labels
  labels=$(printf '%s\n' "$@" | jq -R 'select(length>0)|{name:.}' | jq -s .)
  jq -n --arg t "$title" --arg b "$body" --arg s "$state" --argjson l "$labels" \
    '{title:$t,body:$b,state:$s,labels:$l}' > "$T/issues/$n.json"
}

# case_ NAME WANT_EXIT WANT_REGEX ARGS...   (whole stdout must match the bash regex)
case_() {
  local name=$1 want=$2 re=$3; shift 3
  total=$((total+1))
  local o got
  o=$(bash "$DISPATCH" "$@" 2>"$T/err")
  got=$?
  if [ "$got" != "$want" ]; then fail=$((fail+1)); echo "FAIL $name: want exit $want, got $got ($o $(cat "$T/err"))"
  elif ! [[ "$o" =~ $re ]]; then fail=$((fail+1)); echo "FAIL $name: stdout '$o' does not match $re"; fi
}
# slug_ NAME  -> runs with ARGS and checks the slug (last field) is at most 42 chars, valid, no edge hyphen
slug_() {
  total=$((total+1))
  local o s
  o=$(bash "$DISPATCH" "${ARGS[@]}" 2>/dev/null); s=${o##* }
  if [ "${#s}" -gt 42 ] || ! [[ "$s" =~ ^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$ ]]; then
    fail=$((fail+1)); echo "FAIL $1: slug '$s' is too long or invalid"
  fi
}
ARGS=(--owner acme --project 2)
DW="Intro. Done when: it works."

issue 5 "Add the widget" "$DW" OPEN; issue 3 "Add the gadget" "$DW" OPEN
board "$(item 5 Now Issue)" "$(item 3 Now Issue)"
case_ "first eligible wins" 0 '^5 feat 5-add-the-widget$' "${ARGS[@]}"

issue 5 "Add the widget" "$DW" OPEN agent:working
case_ "skips agent label" 0 '^3 feat 3-add-the-gadget$' "${ARGS[@]}"

issue 5 "Add the widget" "No criteria here." OPEN
case_ "skips no Done when" 0 '^3 ' "${ARGS[@]}"

issue 5 "Add the widget" "$DW" CLOSED
case_ "skips closed" 0 '^3 ' "${ARGS[@]}"

issue 5 "Add the widget" "$DW" OPEN
board "$(item 9 Now PullRequest)" "$(item 8 Now DraftIssue)" "$(item 5 Now Issue)"
case_ "skips PR and draft" 0 '^5 ' "${ARGS[@]}"

board "$(item 5 Next Issue)" "$(item 3 Now Issue)"
case_ "skips other columns" 0 '^3 ' "${ARGS[@]}"

issue 5 "Add the widget" "No criteria." OPEN agent:working
issue 3 "Add the gadget" "No criteria." OPEN
board "$(item 5 Now Issue)" "$(item 3 Now Issue)"
case_ "none eligible" 0 '^$' "${ARGS[@]}"

issue 5 "Crash on start" "$DW" OPEN bug
board "$(item 5 Now Issue)"
case_ "fix type by bug label" 0 '^5 fix 5-crash-on-start$' "${ARGS[@]}"
issue 5 "fix the crash" "$DW" OPEN
case_ "fix type by title" 0 '^5 fix ' "${ARGS[@]}"
issue 5 "Add the widget" "$DW" OPEN enhancement
case_ "feat type otherwise" 0 '^5 feat ' "${ARGS[@]}"
issue 5 "Fixture cleanup" "$DW" OPEN
case_ "Fixture is not Fix" 0 '^5 feat 5-fixture-cleanup$' "${ARGS[@]}"
issue 5 "Fixes the crash" "$DW" OPEN
case_ "Fixes is not Fix" 0 '^5 feat ' "${ARGS[@]}"
issue 5 "Fix x" "$DW" OPEN
case_ "Fix x is fix" 0 '^5 fix 5-fix-x$' "${ARGS[@]}"
issue 5 "fix: x" "$DW" OPEN
case_ "fix: x is fix" 0 '^5 fix 5-fix-x$' "${ARGS[@]}"
issue 5 "Fix" "$DW" OPEN
case_ "bare Fix is fix" 0 '^5 fix 5-fix$' "${ARGS[@]}"

issue 5 "Done WHEN in caps" "DONE WHEN: yes" OPEN
case_ "Done when is case-insensitive" 0 '^5 ' "${ARGS[@]}"

long=$(printf 'word%.0s ' $(seq 1 50))
issue 5 "$long" "$DW" OPEN
case_ "long title: slug shape" 0 '^5 feat 5-word-word' "${ARGS[@]}"
slug_ "long title: slug at most 42 and valid"

issue 5 "!!! ???" "$DW" OPEN
case_ "punctuation title -> number alone" 0 '^5 feat 5$' "${ARGS[@]}"
slug_ "punctuation title: slug valid"

# "5-" is 2 chars, so 40 a's make 42 chars exactly, then the title goes on past the cut with a hyphen at char 42.
issue 5 "$(printf 'a%.0s' $(seq 1 39)) bbbbbb" "$DW" OPEN
case_ "trailing hyphen trimmed" 0 '^5 feat 5-a+$' "${ARGS[@]}"
slug_ "trailing hyphen trimmed: slug valid"

# The approval label's name never reaches a slug: a settings deny on it would block every command naming the branch.
issue 5 "Fix merge-ok voiding on update" "$DW" OPEN
case_ "approval label name in a title -> 'approval' in the slug" 0 '^5 fix 5-fix-approval-voiding-on-update$' "${ARGS[@]}"
slug_ "approval label name in a title: slug valid"

issue 5 "Add the widget" "No criteria." OPEN
board "$(item 5 Now Issue)" "$(item 6 Next Issue)" "$(item 7 Now PullRequest)" "$(item 8 Now Issue)"
issue 6 "x" "$DW" OPEN; issue 8 "x" "$DW" CLOSED
WHY=(--why 5 --owner acme --project 2)
case_ "--why no Done when" 0 '^no Done when$' "${WHY[@]}"
case_ "--why not in Now" 0 '^not in Now$' --why 6 --owner acme --project 2
case_ "--why not in Now (absent)" 0 '^not in Now$' --why 99 --owner acme --project 2
case_ "--why not an issue" 0 '^not an issue$' --why 7 --owner acme --project 2
case_ "--why closed" 0 '^closed$' --why 8 --owner acme --project 2
issue 5 "Add the widget" "No criteria." OPEN agent:working
case_ "--why labeled" 0 '^labeled agent:working$' "${WHY[@]}"
issue 5 "Add the widget" "$DW" OPEN
case_ "--why eligible" 0 '^eligible$' "${WHY[@]}"

case_ "bad args: no --owner" 2 '^$' --project 2
case_ "bad args: no --project" 2 '^$' --owner acme
case_ "bad args: non-numeric project" 2 '^$' --owner acme --project x
case_ "bad args: unknown flag" 2 '^$' --owner acme --project 2 --bogus
case_ "bad args: --why not a number" 2 '^$' --why x --owner acme --project 2
# A failed or garbled issue lookup is a refusal, never "eligible".
board "$(item 77 Now Issue)"
rm -f "$T/issues/77.json"
case_ "missing issue fixture -> refused" 2 '^$' "${ARGS[@]}"
case_ "--why missing issue fixture -> refused" 2 '^$' --why 77 --owner acme --project 2
echo '{not json' > "$T/issues/77.json"
case_ "malformed issue JSON -> refused" 2 '^$' "${ARGS[@]}"
case_ "--why malformed issue JSON -> refused" 2 '^$' --why 77 --owner acme --project 2
echo '[]' > "$T/issues/77.json"
case_ "non-object issue JSON -> refused" 2 '^$' "${ARGS[@]}"
echo '{"state":"OPEN","title":"t","body":5,"labels":[]}' > "$T/issues/77.json"
case_ "wrong-typed field -> refused" 2 '^$' "${ARGS[@]}"
case_ "--why wrong-typed field -> refused" 2 '^$' --why 77 --owner acme --project 2
echo '{"state":"OPEN","title":"t","body":"Done when","labels":5}' > "$T/issues/77.json"
case_ "labels not an array -> refused" 2 '^$' "${ARGS[@]}"
case_ "--why labels not an array -> refused" 2 '^$' --why 77 --owner acme --project 2
echo '{"state":"OPEN","title":"t","body":"Done when","labels":null}' > "$T/issues/77.json"
case_ "labels null -> refused" 2 '^$' "${ARGS[@]}"
case_ "--why labels null -> refused" 2 '^$' --why 77 --owner acme --project 2
echo '{"state":"OPEN","title":5,"body":"Done when","labels":[]}' > "$T/issues/77.json"
case_ "title not a string -> refused" 2 '^$' "${ARGS[@]}"
case_ "--why title not a string -> refused" 2 '^$' --why 77 --owner acme --project 2

# GraphQL board read: DISPATCH_GRAPHQL_PAGES holds pages as `gh api graphql --paginate` prints them (concatenated).
# gnode NUMBER STATUS TYPENAME -> one GraphQL item node. NUMBER "-" = no number (a draft); STATUS "-" = no Status set.
gnode() {
  local fv='null' c
  [ "$2" = "-" ] || fv=$(printf '{"name":"%s"}' "$2")
  if [ "$1" = "-" ]; then c=$(printf '{"__typename":"%s"}' "$3"); else c=$(printf '{"__typename":"%s","number":%s}' "$3" "$1"); fi
  printf '{"fieldValueByName":%s,"content":%s}' "$fv" "$c"
}
# gpage HAS_NEXT NODE...  -> appends one page response to $T/pages.json
gpage() {
  local next=$1; shift
  local IFS=,
  printf '{"data":{"user":{"projectV2":{"items":{"pageInfo":{"hasNextPage":%s,"endCursor":"c"},"nodes":[%s]}}}}}\n' "$next" "$*" >> "$T/pages.json"
}
# gql_ NAME WANT_EXIT WANT_REGEX ARGS...  -> case_ reading the board from $T/pages.json instead of DISPATCH_BOARD_JSON
gql_() { DISPATCH_BOARD_JSON="" DISPATCH_GRAPHQL_PAGES="$T/pages.json" case_ "$@"; }

issue 7 "Add the seven" "$DW" OPEN; issue 4 "Add the four" "$DW" OPEN; issue 9 "Add the nine" "$DW" OPEN
rm -f "$T/pages.json"
gpage true "$(gnode 7 Now Issue)" "$(gnode - Now DraftIssue)"
gpage false "$(gnode 4 Now Issue)" "$(gnode 9 Next Issue)"
gql_ "graphql pages normalise" 0 '^7 feat 7-add-the-seven$' "${ARGS[@]}"
issue 7 "Add the seven" "$DW" OPEN agent:working
gql_ "graphql page 2 seen after page 1" 0 '^4 feat 4-add-the-four$' "${ARGS[@]}"
gql_ "graphql --why page 2 item" 0 '^eligible$' --why 4 --owner acme --project 2
gql_ "graphql --why Next item" 0 '^not in Now$' --why 9 --owner acme --project 2
gql_ "list-now order" 0 $'^7\n4$' --list-now --owner acme --project 2

rm -f "$T/pages.json"
gpage false "$(gnode 7 - Issue)" "$(gnode 4 Now Issue)"
issue 7 "Add the seven" "$DW" OPEN
gql_ "null status skipped" 0 '^4 ' "${ARGS[@]}"
gql_ "list-now skips null status" 0 '^4$' --list-now --owner acme --project 2

rm -f "$T/pages.json"
gpage false "$(gnode 7 Now Issue)"
printf '{"data":{"user":{"projectV2":null}}}\n' >> "$T/pages.json"
gql_ "graphql page without items refuses" 2 '^$' "${ARGS[@]}"
gql_ "list-now: page without items refuses" 2 '^$' --list-now --owner acme --project 2
printf '{"errors":[{"message":"nope"}]}\n' > "$T/pages.json"
gql_ "graphql error page refuses" 2 '^$' "${ARGS[@]}"
: > "$T/pages.json"
gql_ "graphql no pages refuses" 2 '^$' "${ARGS[@]}"

# Live path (no hooks): gh failing is a refusal; gh's paginated pages get the same normalisation.
DISPATCH_BOARD_JSON="" DISPATCH_ISSUE_DIR="" case_ "live: gh failure refuses" 2 '^$' --list-now --owner acme --project 2
rm -f "$T/pages.json"
gpage true "$(gnode 7 Now Issue)"
gpage false "$(gnode 4 Now Issue)"
DISPATCH_BOARD_JSON="" FAKE_GH_PAGES="$T/pages.json" FAKE_GH_ARGS="$T/gh-args" \
  case_ "live: paginated graphql read" 0 $'^7\n4$' --list-now --owner acme --project 2
total=$((total+1))
if ! { grep -qx 'api' "$T/gh-args" && grep -qx 'graphql' "$T/gh-args" && grep -qx -- '--paginate' "$T/gh-args" \
  && grep -qx 'owner=acme' "$T/gh-args" && grep -qx 'number=2' "$T/gh-args" && grep -q 'endCursor' "$T/gh-args"; }; then
  fail=$((fail+1)); echo "FAIL live: gh api graphql args: $(tr '\n' ' ' < "$T/gh-args")"
fi

# list-now on the already-normalised board, and arg checks.
board "$(item 5 Now Issue)" "$(item 6 Next Issue)" "$(item 7 Now PullRequest)" "$(item 8 Now Issue)"
case_ "list-now on normalised board" 0 $'^5\n8$' --list-now --owner acme --project 2
board "$(item 6 Next Issue)"
case_ "list-now empty Now" 0 '^$' --list-now --owner acme --project 2
case_ "list-now with --why refused" 2 '^$' --list-now --why 5 --owner acme --project 2
case_ "list-now needs --owner" 2 '^$' --list-now --project 2

total=$((total+1))
bash "$DISPATCH" --project 2 2>&1 | grep -q 'dispatch-next.sh: refused:' || { fail=$((fail+1)); echo "FAIL refusal message format"; }

# Two workers: footprint-aware pick. Fixtures: --hard-file in $T, a tiny git repo as cwd for the directory case.
printf "%s\n" "  local HARD_PATHS='^(src/db/migrate|\\.github/)'" > "$T/hard.txt"
mkdir -p "$T/repo/src/db/migrate" "$T/repo/src/a"
: > "$T/repo/src/db/migrate/001.sql"; : > "$T/repo/src/a/x.ts"
git -C "$T/repo" init -q
git -C "$T/repo" add src/a/x.ts src/db/migrate/001.sql
git -C "$T/repo" -c user.name=t -c user.email=t@example.com commit -q -m init
fpissue() { issue "$1" "Task $1" "$(printf 'Intro\n%s\nDone when: ok.' "$2")" OPEN; }
TW=(--owner acme --project 2 --areas "src/a, src/b" --hard-file "$T/hard.txt")
board "$(item 1 Now Issue)" "$(item 2 Now Issue)" "$(item 3 Now Issue)"
fpissue 1 "Footprint: src/a/one.ts"; fpissue 2 "- **Footprint:** \`src/a/two.ts\`, src/c"; fpissue 3 "Footprint: src/b"
case_ "no --with: old behaviour" 0 '^1 ' "${TW[@]}"
case_ "same area skipped to next" 0 '^3 ' "${TW[@]}" --with 1
fpissue 3 "footprint: lib/q"
fpissue 2 "Footprint: src/a"
case_ "disjoint areas pick" 0 '^3 ' "${TW[@]}" --with 1
fpissue 1 "Footprint: src"; fpissue 2 "Footprint: src/zz/deep"; fpissue 3 "Footprint: docs"
case_ "prefix overlap skipped" 0 '^3 ' "${TW[@]}" --with 1
issue 2 "Task 2" "Done when: ok." OPEN
fpissue 1 "Footprint: src/a"
case_ "candidate without Footprint skipped" 0 '^3 ' "${TW[@]}" --with 1
fpissue 2 "Footprint: src/b"; fpissue 3 "Footprint: docs"
issue 9 "Inflight" "No footprint. Done when: ok." OPEN
case_ "in-flight without Footprint blocks all" 0 '^$' "${TW[@]}" --with 9
fpissue 2 "Footprint: src/db/migrate/002.sql"; fpissue 3 "Footprint: src/b"
board "$(item 2 Now Issue)" "$(item 3 Now Issue)"
fpissue 9 "Footprint: .github/ci.yml"
case_ "two hard skipped" 0 '^3 ' "${TW[@]}" --with 9
case_ "--with-hard blocks hard" 0 '^3 ' "${TW[@]}" --with-hard 9
fpissue 9 "Footprint: src/a"
case_ "--with-hard makes in-flight hard" 0 '^3 ' "${TW[@]}" --with-hard 9
issue 9 "Inflight" "No footprint. Done when: ok." OPEN
case_ "--with-hard in-flight without Footprint blocks" 0 '^$' "${TW[@]}" --with-hard 9
fpissue 9 "Footprint: src/a"
fpissue 2 "Footprint: src/db"
total=$((total+1))
o=$(cd "$T/repo" && bash "$DISPATCH" "${TW[@]}" --with-hard 9 2>/dev/null) || true
[[ "$o" =~ ^3\  ]] || { fail=$((fail+1)); echo "FAIL hard dir vs --with-hard: '$o'"; }
total=$((total+1))
o=$(cd "$T/repo" && bash "$DISPATCH" "${TW[@]}" --with 9 2>/dev/null) || true
[[ "$o" =~ ^2\  ]] || { fail=$((fail+1)); echo "FAIL hard dir beside non-hard in-flight: '$o'"; }
fpissue 9 "Footprint: .github/ci.yml"
total=$((total+1))
o=$(cd "$T/repo" && bash "$DISPATCH" "${TW[@]}" --with 9 2>/dev/null) || true
[[ "$o" =~ ^3\  ]] || { fail=$((fail+1)); echo "FAIL hard dir vs hard in-flight: '$o'"; }
total=$((total+1))
o=$(cd "$T" && bash "$DISPATCH" "${TW[@]}" --with 9 2>/dev/null) || true
[[ "$o" =~ ^2\  ]] || { fail=$((fail+1)); echo "FAIL outside a git repo the path itself is tested: '$o'"; }
fpissue 9 "Footprint: src/a"
fpissue 1 "Footprint: src/a/q"
board "$(item 1 Now Issue)" "$(item 2 Now Issue)" "$(item 3 Now Issue)"
WW=(--owner acme --project 2 --areas "src/a src/b" --hard-file "$T/hard.txt")
case_ "--why overlaps" 0 '^overlaps #9 \(src/a\)$' --why 1 "${WW[@]}" --with 9
case_ "--why eligible beside in-flight" 0 '^eligible$' --why 3 "${WW[@]}" --with 9
fpissue 9 "Footprint: .github/ci.yml"
fpissue 2 "Footprint: src/db/migrate"
case_ "--why hard while hard" 0 '^hard while #9 is hard$' --why 2 "${WW[@]}" --with 9
fpissue 9 "Footprint: src/a"
case_ "--why hard via --with-hard" 0 '^hard while #9 is hard$' --why 2 "${WW[@]}" --with-hard 9
issue 2 "Task 2" "Done when: ok." OPEN
case_ "--why no Footprint" 0 '^no Footprint \(runs alone\)$' --why 2 "${WW[@]}" --with 9
issue 9 "Inflight" "none. Done when: ok." OPEN
case_ "--why in-flight no Footprint" 0 '^in-flight #9 has no Footprint$' --why 3 "${WW[@]}" --with 9
fpissue 9 "Footprint: src/a"
issue 3 "Task 3" "Footprint: src/b" CLOSED
case_ "--why closed wins over compat" 0 '^closed$' --why 3 "${WW[@]}" --with 9
fpissue 3 "Footprint: src/b"
case_ "bad --hard-file refused" 2 '^$' "${TW[@]}" --hard-file "$T/nope"
printf 'x=1\n' > "$T/nohard.txt"
case_ "--hard-file without HARD_PATHS refused" 2 '^$' "${TW[@]}" --hard-file "$T/nohard.txt"
printf "HARD_PATHS='^zz/'\n" > "$T/hard2.txt"
case_ "--hard-file form without local" 0 '^1 ' "${TW[@]}" --hard-file "$T/hard2.txt" --with 3
case_ "--with not a number refused" 2 '^$' "${TW[@]}" --with x
case_ "--with-hard needs value" 2 '^$' "${TW[@]}" --with-hard
# Placeholder values and unsafe paths count as no Footprint (runs alone); a leading ./ is stripped.
fpissue 9 "Footprint: src/a"
# shellcheck disable=SC2016  # the backticks are literal text in an issue body
for v in none NONE tbd n/a '?' '`none`' ''; do
  fpissue 2 "Footprint: $v"
  case_ "--why Footprint '$v' runs alone" 0 '^no Footprint \(runs alone\)$' --why 2 "${WW[@]}" --with 9
done
# A glob character would be compared literally (src/* overlaps nothing), so a path with one is unsafe too.
for v in /etc/x src/b/../a '../src/b' 'src/b, /abs' '.' './' 'src/*' 'src/a?' 'src/[ab]' 'src/{a,b}' 'src/b, lib/*.ts'; do
  fpissue 2 "Footprint: $v"
  case_ "--why Footprint '$v' runs alone" 0 '^no Footprint \(runs alone\)$' --why 2 "${WW[@]}" --with 9
done
fpissue 2 "Footprint: ./src/a/z.ts"
case_ "--why ./ stripped, keyed by area" 0 '^overlaps #9 \(src/a\)$' --why 2 "${WW[@]}" --with 9
fpissue 2 "Footprint: ./src/b"
case_ "--why ./ stripped, disjoint" 0 '^eligible$' --why 2 "${WW[@]}" --with 9
fpissue 9 "Footprint: none"
case_ "--why in-flight 'none' has no Footprint" 0 '^in-flight #9 has no Footprint$' --why 2 "${WW[@]}" --with 9
fpissue 2 "Footprint: src/b"

# **Footprint**: (colon outside the bold) parses like Footprint:.
fpissue 9 "Footprint: src/a"
fpissue 2 "**Footprint**: src/a/z.ts"
case_ "--why **Footprint**: form overlaps" 0 '^overlaps #9 \(src/a\)$' --why 2 "${WW[@]}" --with 9
fpissue 2 "- **Footprint** : \`src/b\`"
case_ "--why - **Footprint** : form eligible" 0 '^eligible$' --why 2 "${WW[@]}" --with 9
fpissue 2 "**Footprint grew**: src/b"
case_ "--why Footprint grew in an issue body is not a Footprint" 0 '^no Footprint \(runs alone\)$' --why 2 "${WW[@]}" --with 9

# --with-paths N:PATHS: an in-flight item's PR-body "Footprint grew:" paths join its footprint.
fpissue 9 "Footprint: src/a"; fpissue 2 "Footprint: src/b"; fpissue 3 "Footprint: docs"
board "$(item 2 Now Issue)" "$(item 3 Now Issue)"
case_ "grew: without it, src/b is picked" 0 '^2 ' "${TW[@]}" --with 9
case_ "grew: into src/b skips it" 0 '^3 ' "${TW[@]}" --with 9 --with-paths "9:src/b/new.ts"
# shellcheck disable=SC2016  # the backticks are literal text in an issue body
case_ "--why grew overlap" 0 '^overlaps #9 \(src/b\)$' --why 2 "${WW[@]}" --with 9 --with-paths '9:`src/b/x.ts`, lib'
case_ "grew: order of flags does not matter" 0 '^3 ' "${TW[@]}" --with-paths "9:src/b" --with 9
case_ "grew: repeatable, accumulates" 0 '^$' "${TW[@]}" --with 9 --with-paths "9:src/b" --with-paths "9:docs"
case_ "grew: disjoint keeps the pick" 0 '^2 ' "${TW[@]}" --with 9 --with-paths "9:lib/z"
for v in none '' tbd; do
  case_ "grew: '$v' adds nothing" 0 '^2 ' "${TW[@]}" --with 9 --with-paths "9:$v"
done
case_ "grew: unsafe path -> in-flight runs alone" 0 '^in-flight #9 has no Footprint$' --why 2 "${WW[@]}" --with 9 --with-paths "9:../x"
case_ "grew: glob path -> in-flight runs alone" 0 '^in-flight #9 has no Footprint$' --why 2 "${WW[@]}" --with 9 --with-paths "9:src/*"
fpissue 2 "Footprint: src/db/migrate"
case_ "grew: hard via grew blocks a hard pick" 0 '^hard while #9 is hard$' --why 2 "${WW[@]}" --with 9 --with-paths "9:.github/x"
fpissue 2 "Footprint: src/b"
case_ "grew: with --with-hard" 0 '^overlaps #9 \(src/b\)$' --why 2 "${WW[@]}" --with-hard 9 --with-paths "9:src/b"
case_ "grew: item not in-flight refused" 2 '^$' "${TW[@]}" --with 9 --with-paths "8:src/b"
case_ "grew: no colon refused" 2 '^$' "${TW[@]}" --with 9 --with-paths "9"
case_ "grew: bad number refused" 2 '^$' "${TW[@]}" --with 9 --with-paths "x:src/b"
case_ "grew: needs value" 2 '^$' "${TW[@]}" --with 9 --with-paths

# --- --name-key: the repo's key from the ## Dispatcher block (dispatcher dispatch-<key>, workers <key>-<slug>) ---
# md FILE LINE...  -> a CLAUDE.md with an earlier section holding a decoy Name, the block, and a later section
md() {
  local f=$T/$1; shift
  { printf '# Repo\n\n## Other\n- Name: decoy · Project: x #1\n\n## Dispatcher\n'; printf '%s\n' "$@"; printf '\n## Later\n- Name: after\n'; } > "$f"
}
md ok.md "- Project: acme #2 · Approver: acme · max_workers: 1" "- Name: alpha · Deploy: make deploy"
case_ "name-key: read from the block, between pairs" 0 '^alpha$' --name-key --claude-md "$T/ok.md"
md first.md "- Name: beta-2 · Project: acme #2"
case_ "name-key: first pair of a bullet" 0 '^beta-2$' --name-key --claude-md "$T/first.md"
md none.md "- Project: acme #2 · Approver: acme"
case_ "name-key: no Name in the block refused (others' Name ignored)" 2 '^$' --name-key --claude-md "$T/none.md"
md two.md "- Name: alpha" "- Name: beta"
case_ "name-key: two Names refused" 2 '^$' --name-key --claude-md "$T/two.md"
md bad.md "- Name: Alpha"
case_ "name-key: uppercase refused" 2 '^$' --name-key --claude-md "$T/bad.md"
md digit.md "- Name: 1alpha"
case_ "name-key: digit first refused (a worker slug starts with a digit)" 2 '^$' --name-key --claude-md "$T/digit.md"
md meta.md '- Name: a;b'
case_ "name-key: metacharacter refused" 2 '^$' --name-key --claude-md "$T/meta.md"
md long.md "- Name: abcdefghijklmnopqrstu"
case_ "name-key: over 20 characters refused" 2 '^$' --name-key --claude-md "$T/long.md"
case_ "name-key: missing file refused" 2 '^$' --name-key --claude-md "$T/nope.md"
total=$((total+1))
o=$(cd "$T" && cp ok.md CLAUDE.md && bash "$DISPATCH" --name-key 2>&1)
[ "$o" = alpha ] || { fail=$((fail+1)); echo "FAIL name-key: default CLAUDE.md in the cwd: got '$o'"; }

# --- --field <Key>: one Key: value of the ## Dispatcher block (the launcher reads Agent, Agent keychain, Approver) ---
md fld.md "- Name: alpha · Approver: acme · max_workers: 1" "- Agent: acme-bot · Agent keychain: acme-token"
case_ "field: value" 0 '^acme-bot$' --field Agent --claude-md "$T/fld.md"
case_ "field: a key with a space, not confused with its prefix" 0 '^acme-token$' --field "Agent keychain" --claude-md "$T/fld.md"
case_ "field: missing key refused" 2 '^$' --field Deploy --claude-md "$T/fld.md"
md fph.md "- Agent: acme-bot · Agent keychain: {{Keychain service}}"
case_ "field: {{ placeholder refused" 2 '^$' --field "Agent keychain" --claude-md "$T/fph.md"
md oth.md "- Name: alpha"
case_ "field: a key only in another ## section is ignored (Project is in ## Other)" 2 '^$' --field Project --claude-md "$T/oth.md"
case_ "field: the decoy section's Name is not the block's" 0 '^alpha$' --field Name --claude-md "$T/oth.md"
case_ "field: missing file refused" 2 '^$' --field Agent --claude-md "$T/nope.md"
case_ "field: needs a value" 2 '^$' --field
case_ "field: bad key refused" 2 '^$' --field 'a;b' --claude-md "$T/fld.md"

echo "$((total-fail))/$total passed"
[ "$fail" = 0 ]
