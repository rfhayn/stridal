#!/usr/bin/env bash
# Self-test for scope-check.sh. Run: bash .claude/bin/test-scope-check.sh (from any cwd).
# Builds a throwaway git repo with an origin/main ref; the real repo is never touched.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/test-scope-check.XXXXXX")
trap 'rm -rf "$T"' EXIT
total=0; fail=0
SC=$here/scope-check.sh
R=$T/repo
mkdir -p "$R/.claude/bin" "$R/src/a" "$R/docs"
cp "$here/scope-check.sh" "$here/dispatch-next.sh" "$R/.claude/bin/"
cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo x > README.md && git add -A && git commit -qm base
git update-ref refs/remotes/origin/main HEAD
git checkout -q -b feat/x
echo 1 > src/a/one.txt; echo 2 > docs/two.md; echo 3 > top.txt
git add -A && git commit -qm change
SC=$R/.claude/bin/scope-check.sh

# case_ NAME WANT_EXIT WANT_REGEX ARGS...   (stdout must match the bash regex; the body files are in $T)
case_() {
  local name=$1 want=$2 re=$3; shift 3
  total=$((total+1))
  local o got
  o=$(bash "$SC" "$@" 2>&1); got=$?
  if [ "$got" != "$want" ]; then fail=$((fail+1)); echo "FAIL $name: want exit $want, got $got ($o)"
  elif ! [[ "$o" =~ $re ]]; then fail=$((fail+1)); echo "FAIL $name: output '$o' does not match $re"; fi
}
body() { printf '%s\n' "$2" > "$T/$1"; }

case_ "globs only: all in scope" 0 'all changed files are in the brief' 'src/a/*' 'docs/*' 'top.txt'
case_ "globs only: a stray is reported" 1 'OUT OF SCOPE: top.txt' 'src/a/*' 'docs/*'
case_ "no arguments is a usage error" 2 'usage'

body all.md 'Footprint: src/a, docs, top.txt'
case_ "footprint: files under a directory path are in scope" 0 'all changed files are in the brief' --footprint "$T/all.md"
# shellcheck disable=SC2016  # backticks are literal Footprint text
body part.md 'Footprint: `src/a/`, docs'
case_ "footprint: a file outside is OUT OF SCOPE" 1 'OUT OF SCOPE: top.txt' --footprint "$T/part.md"
body prefix.md 'Footprint: src/a/on, docs, top.txt'
case_ "footprint: a name prefix is not a directory" 1 'OUT OF SCOPE: src/a/one.txt' --footprint "$T/prefix.md"
body nofp.md 'No footprint here.'
case_ "footprint: no line, scope not checked" 0 '^scope-check: no Footprint, scope not checked$' --footprint "$T/nofp.md"
body none.md 'Footprint: none'
case_ "footprint: placeholder, scope not checked" 0 '^scope-check: no Footprint, scope not checked$' --footprint "$T/none.md"
body unsafe.md 'Footprint: src/*, docs'
case_ "footprint: unsafe value, scope not checked" 0 '^scope-check: no Footprint, scope not checked$' --footprint "$T/unsafe.md"
case_ "footprint plus extra globs: both count" 0 'all changed files are in the brief' --footprint "$T/part.md" 'top.txt'
case_ "footprint plus extra globs: still a stray" 1 'OUT OF SCOPE: top.txt' --footprint "$T/part.md" 'nothing/*'
case_ "footprint: missing file refused" 2 'cannot read' --footprint "$T/nope.md"
case_ "no footprint but extra globs: the globs still apply" 1 'OUT OF SCOPE' --footprint "$T/nofp.md" 'docs/*'

echo "$((total-fail))/$total passed"
[ "$fail" = 0 ]
