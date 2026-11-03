#!/bin/sh
# The team-queue merge rule (OPS-227, .claude/local/guard.d/team-queue.sh) against a stand-in `gh`, in a
# scratch project with a local origin. No GitHub login is needed (CI has none). Most cases ask the rule
# alone, with the facts the guard hands it (GUARD_*): the guard costs a second a run. The last ones go
# through the real guard, to show a block and an advisory reach Claude and a broken rule blocks.
. "${CHECKS_LIB:?}"
need jq git

RULE="$ROOT/.claude/local/guard.d/team-queue.sh"
[ -f "$RULE" ] || { fail "the rule is missing: $RULE"; finish; }
# The rule leaves two forms to the guard's rule 15 (its is_squash comment), which runs only while
# attribution is off, so turning attribution on must fail here rather than reopen them unseen.
if jq -e '.attribution.enabled != true' "$ROOT/.claude/model-roles.json" >/dev/null 2>&1; then
  ok "attribution is off, so the guard's rule 15 holds what .claude/local/guard.d/team-queue.sh leaves it"
else
  fail "attribution.enabled is on, or .claude/model-roles.json cannot be read: the guard's rule 15 may not run, and .claude/local/guard.d/team-queue.sh leaves it a method word hidden by quoting and a merge commit that sets a subject and no body. Give that rule its own reader of the method first (its is_squash comment)."
fi

d=$(scratch)
G="$d/app"; new_repo "$G"
mkdir -p "$G/.claude/hooks/lib" "$G/.claude/lib" "$G/.claude/local/guard.d" "$G/docs" "$d/bin"
cp "$ROOT/.claude/hooks/pr-merge-guard.sh" "$G/.claude/hooks/"
cp "$ROOT/.claude/hooks/lib/"* "$G/.claude/hooks/lib/"
cp "$ROOT/.claude/lib/conf.sh" "$ROOT/.claude/lib/change.sh" "$ROOT/.claude/lib/evals.sh" "$ROOT/.claude/lib/modules.sh" "$G/.claude/lib/"
cp "$ROOT/.claude/scenario-trace.sh" "$G/.claude/"
cp "$RULE" "$G/.claude/local/guard.d/team-queue.sh"
printf 'MODULES=""\n' > "$G/.claude/project.conf"
# As this repo holds it, so the guard's rule 15 is in play through the guard.
printf '{"attribution": {"enabled": false}, "provenance": {"enabled": false}}\n' > "$G/.claude/model-roles.json"
printf '# Journal\n\n## Session 1 — 2026-01-01 — a — start\n' > "$G/docs/development-journal.md"
git -C "$G" add -A && git -C "$G" commit -qm base
git init -q --bare "$G/acme/app.git"; echo "acme/" >> "$G/.git/info/exclude"
git -C "$G" remote add origin acme/app.git
(cd "$G" && git push -q origin HEAD:main 2>/dev/null && git fetch -q origin && git remote set-head origin main)
BASE=$(git -C "$G" rev-parse HEAD)
printf '%s\tfull\tclean\tall\n' "$BASE" > "$G/.git/ci-receipt"

cat > "$d/bin/gh" <<'EOF'
#!/bin/sh
# GH_QUEUE: the open team-queue issues a read naming the repo lists. GH_QUEUE_DEFAULT: what a read
# naming none lists instead. GH_QUEUE_ERR: gh itself fails. GH_QUEUE_RAW: what gh prints instead. A
# read missing a filter answers nothing: gh's own default is 30, of every label.
# PR_JSON: the PR. GH_PR_ERR: gh itself fails. GH_NOISE: gh writes to stderr beside a valid answer.
# GH_CANON: `<asked>=<answer>` words for gh api repos/<asked>. GH_API_HTTP: an HTTP error, which gh
# prints as real gh does: the response's body on stdout, the status on stderr, exit 1; GH_API_HTTP_ON:
# only for that name. GH_API_OUT: what gh api prints instead; GH_API_RC: the status it exits with then.
[ -n "${GH_NOISE:-}" ] && echo "$GH_NOISE" >&2
case "$3 $*" in *" -R "*) named=1 ;; *) named="" ;; esac
case "$1 $2" in
  "issue list")
    [ -n "${GH_QUEUE_ERR:-}" ] && { echo "$GH_QUEUE_ERR" >&2; exit 1; }
    case "$*" in *"--label team-queue --state open --limit 1000 "*) ;; *) echo "stub: a list with no filter: $*" >&2; exit 1 ;; esac
    [ -n "${GH_QUEUE_RAW+x}" ] && { printf '%s\n' "$GH_QUEUE_RAW"; exit 0; }
    queue=${GH_QUEUE:-}
    [ -n "$named" ] || queue=${GH_QUEUE_DEFAULT-$queue}
    # shellcheck disable=SC2086
    printf '%s\n' $queue | grep . | jq -R 'tonumber | {number: .}' | jq -cs . ;;
  "pr checks") echo '[]' ;;
  "pr view")
    case "$*" in
      *closingIssuesReferences*)
        [ -n "${GH_PR_ERR:-}" ] && { echo "$GH_PR_ERR" >&2; exit 1; }
        printf '%s\n' "${PR_JSON-}" ;;
      *"--json state "*) echo OPEN ;;
      *headRefName*) printf '{"headRefName":"ops/x","headRefOid":"%s"}\n' "$GH_HEAD" ;;
      *headRefOid*) echo "$GH_HEAD" ;;
    esac ;;
  "api repos/"*)
    case "$*" in *.default_branch) git symbolic-ref -q refs/remotes/origin/HEAD | sed 's|^refs/remotes/origin/||; s/^conf-on-main$/conf-forge/'; exit 0 ;; esac
    if [ -n "${GH_API_HTTP:-}" ] && { [ -z "${GH_API_HTTP_ON:-}" ] || [ "$2" = "repos/$GH_API_HTTP_ON" ]; }; then
      printf '{"message":"an error","status":"%s"}\n' "$GH_API_HTTP"
      echo "gh: an error (HTTP $GH_API_HTTP)" >&2
      exit 1
    fi
    [ -n "${GH_API_OUT+x}" ] && { printf '%s\n' "$GH_API_OUT"; exit "${GH_API_RC:-0}"; }
    asked=${2#repos/}
    for pair in ${GH_CANON:-}; do case $pair in "$asked="*) echo "${pair#*=}"; exit 0 ;; esac; done
    echo "$asked" ;;
  "run list") echo 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$d/bin/gh"

# prjson TITLE BODY [CLOSING: N or owner/name#N words] [BASE]: the PR as gh returns it.
prjson() {
  jq -cn --arg t "$1" --arg b "$2" --arg c "${3:-}" --arg base "${4:-main}" '{title: $t, body: $b, baseRefName: $base, closingIssuesReferences: ($c | split(" ") | map(select(. != "")
    | if test("#") then (split("#") as $p | ($p[0] | split("/")) as $r | {number: ($p[1] | tonumber), repository: {name: $r[1], owner: {login: $r[0]}}})
      else {number: tonumber} end))}'
}
QUEUE="374 8"
HEADSHA=$BASE
# ask WANT LABEL COMMAND [env...]: the rule alone, as the guard runs it. TITLE, BODY, CLOSES and PRBASE
# are the PR, unless the env names a PR_JSON. Its stdout lands in $out, stderr in $d/err.
ask() {
  _w=$1 _l=$2 _c=$3; shift 3
  payload "$_c" "${PCWD:-$G}" > "$d/payload"
  rc=0
  out=$(cd "$G" && env PATH="$d/bin:$PATH" GH_QUEUE="$QUEUE" PR_JSON="$(prjson "${TITLE:-A title}" "${BODY:-}" "${CLOSES:-}" "${PRBASE:-main}")" \
    ROOT="$G" GUARD_PR=5 GUARD_PR_REF="${PREF-5}" GUARD_PR_REPO="${PREPO-acme/app}" GUARD_BRANCH=ops/x GUARD_REPO=acme/app GUARD_BASE="$BASE" GUARD_HEAD="$HEADSHA" \
    GUARD_COMMAND="$_c" GUARD_PAYLOAD="$d/payload" MAIN_BRANCH=main "$@" sh "$G/.claude/local/guard.d/team-queue.sh" 2>"$d/err") || rc=$?
  expect_rc "$_w" "$rc" "$( [ "$_w" = 2 ] && echo blocks || echo allows ): $_l"
  [ "$rc" = "$_w" ] || sed 's/^/       /' "$d/err" | head -3
  # An assignment before a function call outlives it in some shells (sh on macOS): end them all here.
  TITLE="" BODY="" CLOSES="" PRBASE="" QUEUE="374 8" PCWD=""; unset PREF PREPO
}
says() {
  for _s in "$@"; do
    grep -qF -- "$_s" "$d/err" && ok "...naming $_s" || fail "the block does not name '$_s': $(head -2 "$d/err")"
  done
}
M="gh pr merge 5 --squash"
printf 'Adds x.\n' > "$G/clean.md"
F="--body-file clean.md"

# --- What a keyword looks like, in the title that closed #374 and the PR body ----------------------
TITLE="Fix #374: Land the CI fixes" ask 2 "the title that closed #374" "$M"
says "#374" "the PR title" "a title with no keyword, naming #374 if needed" "squash body line 'Delivers team-queue #374'" "docs/conventions.md" "once a squash merge sets"
grep -q Development "$d/err" && fail "the block names a sidebar link no one made: $(head -1 "$d/err")" || ok "...and no sidebar link it did not read"
TITLE="CLOSES #374" ask 2 "another keyword, another case" "$M"
BODY="This fixes: #374." ask 2 "a keyword with a colon, in the PR body" "$M $F"
says "the PR body"
BODY="Resolved acme/app#374" ask 2 "this repository named in full" "$M $F"
BODY="Fixes https://github.com/acme/app/issues/374" ask 2 "the issue's URL" "$M $F"
CLOSES=374 ask 2 "only GitHub's closing list (a sidebar link) names it" "$M $F"
says "GitHub's closing list" "Development"
TITLE="Fix #8: x" ask 2 "the second of two open team-queue issues" "$M"
# Each of GitHub's nine keywords, by each road to an issue; then in the PR body, which is read as Markdown.
for w in close closes closed fix fixes fixed resolve resolves resolved; do for r in '#374' 'gh-374' 'acme/app#374' 'https://github.com/acme/app/issues/374'; do TITLE="$w $r: x" ask 2 "'$w $r' in the title" "$M $F"; done; BODY="$w #374" ask 2 "'$w #374' in the PR body" "$M $F"; done
BODY="Fixes https://www.github.com/acme/app/issues/374" ask 2 "the issue's URL with www." "$M $F"
BODY="Fixes http://github.com/acme/app/issues/374" ask 2 "the issue's URL over http" "$M $F"
# The word boundary: a keyword inside a word closes nothing.
for w in hotfix prefix unresolved; do TITLE="$w #374" ask 0 "'$w #374' holds a keyword only inside a word" "$M $F"; done
# Finding: the gh-N form, any case, in each text.
TITLE="Fix gh-374: x" ask 2 "gh-N in the title" "$M"
BODY="Closes GH-374" ask 2 "GH-N in the PR body" "$M $F"
ask 2 "GH-N in the merge's --subject" "$M $F --subject 'Closes GH-374'"
ask 2 "gh-N in the merge's --body" "$M --body 'Fixes gh-374'"
TITLE="Fix gh-37: x" ask 0 "gh-N that is only a part of an open number" "$M $F"
TITLE="See gh-374 for why" ask 0 "gh-N with no keyword" "$M $F"

# --- The merge's own words ---------------------------------------------------------------------------
ask 2 "the merge's --subject" "$M $F --subject 'Fix #374: x'"
says "the squash subject"
ask 2 "the merge's -t, glued" "$M $F -t'Closes #374'"
TITLE="Fix #374: x" ask 0 "a --subject replaces a title that would close it" "$M $F --subject 'OPS-1: x'"
# Finding: an empty subject is no subject, so the title still lands.
TITLE="Fix #374: x" ask 2 "--subject '' hides nothing: gh sends none" "$M $F --subject ''"
says "the PR title"
TITLE="Fix #374: x" ask 2 "--subject of blanks hides nothing" "$M $F --subject '  '"
TITLE="Fix #374: x" ask 2 "an API merge's empty commit_title hides nothing" "gh api -X PUT repos/acme/app/pulls/5/merge -f merge_method=squash -f commit_title= -F commit_message=@clean.md"
ask 2 "the merge's literal --body" "$M --body 'Fixes #374'"
says "the squash body"
printf 'Adds x.\n\nCloses #374\n' > "$G/k.md"
ask 2 "the merge's --body-file" "$M --body-file k.md"
says "the squash body"
ask 2 "a gh api merge's commit_title" "gh api -X PUT repos/acme/app/pulls/5/merge -f merge_method=squash -f commit_title='Fix #374' -F commit_message=@clean.md"
# A commit message is plain text, so a code span shelters nothing; a PR body is Markdown.
printf 'Names `Fix #374` in passing.\n' > "$G/span.md"
ask 2 "a code span in the squash body" "$M --body-file span.md"
BODY='Names `Fix #374` in passing.' ask 0 "a code span in the PR body, the merge setting a body" "$M $F"
# Finding: with no body set, the PR body may land as commit text.
BODY='Names `Fix #374` in passing.' ask 2 "a code span in the PR body, the merge setting none" "$M"
says "as the squash may copy it"
# Finding: an HTML comment links nothing, on one line or several.
BODY='Template. <!-- Fixes #374 --> Done.' ask 0 "a keyword in an HTML comment in the PR body" "$M $F"
BODY='<!-- a template
Fixes #374
-->
Done.' ask 0 "a keyword in a comment over several lines" "$M $F"
BODY='<!-- a note --> Fixes #374' ask 2 "a keyword after a comment closes" "$M $F"
# A fenced sample links nothing, under either fence, and what follows the fence still does.
BODY='A sample:
```
Fixes #374
```
Done.' ask 0 "a keyword in a backtick fence in the PR body" "$M $F"
BODY='A sample:
~~~
Fixes #374
~~~
Done.' ask 0 "a keyword in a tilde fence in the PR body" "$M $F"
BODY='```
a sample
```
Fixes #374' ask 2 "a keyword after a fence closes" "$M $F"
# A relative --body-file is read from the payload's directory, as gh would.
mkdir -p "$G/sub"; printf 'Fixes #374\n' > "$G/sub/here.md"; printf 'Adds x.\n' > "$G/here.md"
PCWD="$G/sub" ask 2 "a relative --body-file from the payload's subdirectory" "$M --body-file here.md"
says "the squash body"
ask 0 "...and the same name from the root is another file" "$M --body-file here.md"

# --- What passes -------------------------------------------------------------------------------------
TITLE="OPS-1: Land the fixes for #374" BODY="Names #374." ask 0 "a title with no keyword, naming the issue" "$M --body 'Delivers team-queue #374'"
TITLE="Fix #5: x" BODY="Closes #6" ask 0 "a keyword on any number the list does not hold" "$M $F"
case "$out" in *'#5'*) case "$out" in *'#6'*) ok "...and says which issues it read" ;; *) fail "no advisory names #6: $out" ;; esac ;; *) fail "no advisory names #5: $out" ;; esac
# A sidebar link in GitHub's closing list is no keyword, so the advisory does not call it one.
case "$out" in 'a closing reference names '*) ok "...as closing references, which a sidebar link also is" ;; *) fail "the advisory does not say 'a closing reference names': $out" ;; esac
BODY="See #374" ask 0 "a mention with no keyword" "$M $F"
TITLE="Fix #37: x" ask 0 "a number that is only a part of an open one's" "$M $F"
BODY="Closes owner/other#374" ask 0 "another repository's issue, in a body" "$M $F"
# Finding: the advisory is true while this repository's #374 is open: it names the other repository.
case "$out" in *'owner/other#374'*) ok "...and the advisory names that repository's issue" ;; *) fail "the advisory does not name owner/other#374: $out" ;; esac
case "$out" in *' #374'*) fail "the advisory says #374 is no open team-queue issue, and it is: $out" ;; *) ok "...and does not say #374 is not open" ;; esac
# Finding: the repo filter on the closing list has a case of its own.
CLOSES="owner/other#374" ask 0 "another repository's issue, in the closing list" "$M $F"
# Finding: a PR that does not target the default branch closes nothing.
TITLE="Fix #374: x" PRBASE=release ask 0 "a PR that targets another branch" "$M"
case "$out" in *'targets release'*) ok "...and says so" ;; *) fail "no advisory names the base: $out" ;; esac

# --- A stale origin name: GitHub says the two are one repository ------------------------------------
STALE="acme/app=acme/Renamed acme/renamed=acme/Renamed acme/Renamed=acme/Renamed"
CLOSES="acme/Renamed#374" ask 2 "a closing list naming the repository's new name" "$M $F" GH_CANON="$STALE"
TITLE="Fix acme/renamed#374: x" ask 2 "a title naming the repository's new name" "$M $F" GH_CANON="$STALE"
BODY="Closes acme/renamed#374" ask 2 "a body naming the repository's new name" "$M $F" GH_CANON="$STALE"
# GitHub cannot say what the name is. Real gh prints an error's body on stdout and exits 1, so neither
# the pipe's status nor an empty answer shows it. A 404 blocks too, as the guard's same_repo does.
for code in 502 403 404; do
  CLOSES="owner/other#374" ask 2 "HTTP $code on the name a closing list holds (fails closed)" "$M $F" GH_API_HTTP="$code" GH_API_HTTP_ON=owner/other
  says "did not say" "GitHub's closing list" "gh api repos/owner/other" "gh auth status"
  TITLE="Fix owner/other#374: x" ask 2 "HTTP $code on the name a title holds (fails closed)" "$M $F" GH_API_HTTP="$code" GH_API_HTTP_ON=owner/other
  says "did not say" "the PR title" "gh api repos/owner/other" "gh auth status"
  CLOSES="owner/other#374" ask 2 "HTTP $code on this repository's own name (fails closed)" "$M $F" GH_API_HTTP="$code" GH_API_HTTP_ON=acme/app
  says "did not say" "gh api repos/acme/app" "gh auth status"
done
CLOSES="acme/renamed#374" ask 2 "gh exits 1 with a name on stdout" "$M $F" GH_API_OUT=acme/other GH_API_RC=1
says "did not say"
CLOSES="acme/renamed#374" ask 2 "gh exits 0 with what is not a name" "$M $F" GH_API_OUT='{"full_name":"acme/other"}'
says "did not say"

# --- With none open, nothing else is read -----------------------------------------------------------
QUEUE="" ask 0 "with no open team-queue issue it reads no PR" "$M" GH_PR_ERR="HTTP 401: Bad credentials"
QUEUE="" ask 0 "...and refuses no body it cannot read" "$M --body-file /dev/stdin"
[ -z "$out" ] && ok "...and says nothing" || fail "an advisory with no queue: $out"

# --- The branch's commits ------------------------------------------------------------------------------
branch() {  # branch MESSAGEFILE: a commit on a branch; HEADSHA is it, and main is checked out again
  git -C "$G" checkout -q -B lane "$BASE"
  echo "$RANDOM$$" >> "$G/docs/note.txt"; git -C "$G" add docs/note.txt
  git -C "$G" commit -q -F "$1"
  HEADSHA=$(git -C "$G" rev-parse HEAD)
  git -C "$G" checkout -q main
}
printf 'Tidy the card\n\nFixes #374\n' > "$d/m"; branch "$d/m"
ask 2 "a branch commit's body, with no squash body" "$M"
says "the branch's commit messages"
ask 0 "...and a body that replaces them" "$M $F"
# Finding: only a squash replaces them. A merge commit or a rebase lands them past both flags.
SET="--subject 'OPS-1: x' $F"
ask 0 "a squash that sets both drops the branch's words" "$M $SET"
for how in --merge --rebase -r -m -rd; do
  ask 2 "$how lands the branch's words past both flags" "gh pr merge 5 $how $SET"
  says "which this merge lands"
done
ask 2 "--squash=false, --rebase" "gh pr merge 5 --squash=false --rebase $SET"
API="gh api -X PUT repos/acme/app/pulls/5/merge -f commit_title=OPS-1 -F commit_message=@clean.md"
ask 2 "an API merge with merge_method=rebase" "$API -f merge_method=rebase"
ask 2 "an API merge with merge_method=merge" "$API -f merge_method=merge"
ask 2 "an API merge with no method: a merge commit" "$API"
ask 0 "an API squash that sets both" "$API -f merge_method=squash"
printf 'Fix #374: tidy the card\n' > "$d/m"; branch "$d/m"
ask 2 "a branch commit's subject, with no squash subject" "$M $F"
says "a branch commit's subject"
ask 0 "...and a subject that replaces it" "$M $SET"
printf 'Closes GH-374\n' > "$d/m"; branch "$d/m"
ask 2 "gh-N in a branch commit" "$M"

# --- Bytes that are not UTF-8, and a parser that fails ------------------------------------------------
# Under a UTF-8 locale, one such byte made tr and awk fail, and the pipe read as no reference at all.
U8=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1)
U8=${U8:-en_US.UTF-8}
printf 'caf\351 Fixes #374\n' > "$G/bad.md"
HEADSHA=$BASE
ask 2 "a non-UTF-8 byte in the --body-file ($U8)" "$M --body-file bad.md" LC_ALL="$U8"
says "#374" "the squash body"
printf 'caf\351\n\nFixes #374\n' > "$d/m"; branch "$d/m"
ask 2 "a non-UTF-8 byte in git log --format=%B ($U8)" "$M" LC_ALL="$U8"
says "#374" "the branch's commit messages"
# git cleans that byte on its way out here; this setting makes %B print one, whatever the message holds.
printf 'caf\303\251 Fixes #374\n' > "$d/m"; branch "$d/m"
git -C "$G" config i18n.logOutputEncoding ISO-8859-1
ask 2 "a byte git log --format=%B prints as ISO-8859-1 ($U8)" "$M" LC_ALL="$U8"
says "#374" "the branch's commit messages"
git -C "$G" config --unset i18n.logOutputEncoding
HEADSHA=$BASE
REAL_AWK=$(command -v awk)
mkdir -p "$d/awkdies" "$d/awkshort"
printf '#!/bin/sh\ncase "$*" in *md=*) exit 1 ;; esac\nexec %s "$@"\n' "$REAL_AWK" > "$d/awkdies/awk"
printf '#!/bin/sh\ncase "$*" in *md=*) exit 0 ;; esac\nexec %s "$@"\n' "$REAL_AWK" > "$d/awkshort/awk"
chmod +x "$d/awkdies/awk" "$d/awkshort/awk"
ask 2 "a parser that fails" "$M $F" PATH="$d/awkdies:$d/bin:$PATH"
says "parser failed"
ask 2 "a parser that exits 0 having said nothing" "$M $F" PATH="$d/awkshort:$d/bin:$PATH"
says "ended short"

# --- Fails closed: what cannot be read has told us nothing ---------------------------------------------
ask 2 "gh cannot list the open team-queue issues" "$M $F" GH_QUEUE_ERR="HTTP 502: list"
says "HTTP 502"
ask 2 "gh answers the list with nothing" "$M $F" GH_QUEUE_RAW=
ask 2 "gh answers the list with what is not an array" "$M $F" GH_QUEUE_RAW='{}'
ask 2 "a list as long as its limit may be cut short" "$M $F" GH_QUEUE_RAW="$(jq -cn '[range(1000) | {number: .}]')"
ask 2 "gh cannot read the PR" "$M $F" GH_PR_ERR="HTTP 401: Bad credentials"
says "HTTP 401"
ask 2 "gh answers the PR with nothing" "$M $F" PR_JSON=
ask 2 "gh answers the PR with what is not an object" "$M $F" PR_JSON='[]'
TITLE="Fix #374: x" ask 2 "gh's noise on stderr does not hide the answer" "$M $F" GH_NOISE="A new release of gh is available"
says "#374"
ask 2 "a subject it cannot read (an API merge's --input)" "gh api -X PUT repos/acme/app/pulls/5/merge --input clean.md"
says "cannot read this merge's --subject"
ask 2 "a --body-file it cannot read" "$M --body-file /dev/stdin"
says "cannot read this merge's body"
# Finding: the two blocks where another command may have moved or written the body file.
ask 2 "a relative --body-file after cd" "cd sub && $M --body-file clean.md"
says "relative --body-file"
ask 2 "a --body-file after another command that may write it" "cp k.md clean2.md && $M --body-file clean2.md"
says "other than cd <path>"
ask 2 "the guard passes no PR reference" "$M $F" GUARD_PR_REF=
mv "$G/.claude/hooks/lib/change-guard.sh" "$d/cg"
ask 2 "the guard's library is missing" "$M $F"
mv "$d/cg" "$G/.claude/hooks/lib/change-guard.sh"
# ...and the list comes from the repository the merge names, not gh's default one.
TITLE="Fix #374: x" PREF=https://github.com/acme/app/pull/5 PREPO="" ask 2 "a URL merge lists that URL's repository" "gh pr merge https://github.com/acme/app/pull/5 --squash $F" GH_QUEUE_DEFAULT=""
TITLE="Fix #374: x" ask 2 "an -R merge lists that repository" "gh pr merge 5 -R acme/app --squash $F" GH_QUEUE_DEFAULT=""

# --- Through the real guard ---------------------------------------------------------------------------
conf_on_main "$G"
through() {  # through WANT LABEL TITLE [COMMAND]: a merge through pr-merge-guard.sh, by default a plain one
  rc=0
  out=$(payload "${4:-$M $F}" "$G" | (cd "$G" && env PATH="$d/bin:$PATH" GH_HEAD="$BASE" GH_QUEUE="$QUEUE" PR_JSON="$(prjson "$3" "")" sh "$G/.claude/hooks/pr-merge-guard.sh" 2>"$d/err")) || rc=$?
  expect_rc "$1" "$rc" "through the guard: $( [ "$1" = 2 ] && echo blocks || echo allows ) $2"
  [ "$rc" = "$1" ] || sed 's/^/       /' "$d/err" | head -3
}
through 2 "the title that closed #374" "Fix #374: x"
says "BLOCKED by pr-merge-guard" "#374" "the PR title"
# What this rule leaves to the guard's rule 15, which refuses all but a squash with a body it can read
# while attribution is off, as here: a merge commit that sets a subject and no body lands the PR's title
# in its message, and the rule alone does not read it there.
TITLE="Fix #374: x" ask 0 "alone, a merge commit that sets a subject and no body" "gh pr merge 5 --merge --subject 'OPS-1: x'"
through 2 "the same merge commit: rule 15 holds it" "Fix #374: x" "gh pr merge 5 --merge --subject 'OPS-1: x'"
says "rule 15"
through 2 "a method word hidden by quoting: rule 15 holds it" "OPS-1: x" "gh pr merge 5 --squash '--merge' --subject 'OPS-1: x' --body-file clean.md"
says "rule 15"
through 0 "a keyword on another issue" "Fix #5: x"
case "$out" in *additionalContext*'#5'*) ok "through the guard: the advisory reaches Claude" ;; *) fail "through the guard: no advisory: $out" ;; esac
land_rule() {  # land_rule FILE: FILE is the rule on origin's main, and here
  cp "$1" "$G/.claude/local/guard.d/team-queue.sh"
  git -C "$G" add -A .claude/local/guard.d; git -C "$G" commit -qm "the rule"
  (cd "$G" && git push -q origin HEAD:main 2>/dev/null && git fetch -q origin)
  BASE=$(git -C "$G" rev-parse HEAD)
  printf '%s\tfull\tclean\tall\n' "$BASE" > "$G/.git/ci-receipt"
  conf_on_main "$G"
}
{ cat "$RULE"; printf 'broken() { "\n'; } > "$d/rule.broken"
land_rule "$d/rule.broken"
through 2 "a rule that does not parse (fails closed)" "OPS-1: x"
says "does not parse"
{ printf '#!/bin/sh\nexit 1\n'; cat "$RULE"; } > "$d/rule.crash"
land_rule "$d/rule.crash"
through 2 "a rule that exits 1 (fails closed)" "OPS-1: x"
says "refuses rather than allow"
land_rule "$RULE"
through 0 "the rule restored" "OPS-1: x"
echo '# a branch edit' >> "$G/.claude/local/guard.d/team-queue.sh"
through 2 "a checkout's copy of the rule that is not main's" "OPS-1: x"
says "they are refused and not run"
git -C "$G" checkout -q -- .claude/local/guard.d/team-queue.sh
finish
