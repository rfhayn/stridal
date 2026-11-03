#!/bin/sh
# This repo's merge-guard rule (OPS-227, BLOCKING): a merge is refused while a closing keyword it would
# land names an open issue labelled `team-queue`. Local, not in the shipped guard, by the owner's
# decision of 2026-11-03: the label exists only in this repo.
#
# WHY. #384's squash title, `Fix #374:`, closed #374 with only its first item fixed. Such an issue is
# an input that its session closes, so a keyword on one is an accident whatever its spelling.
# GitHub's closing list cannot decide this alone: #384's read empty, because a title is not in it.
#
# WHAT IT READS. The list of open team-queue issues comes first and is the authority: with none open
# nothing can be closed by accident, and nothing else is read. Then every text the merge can land:
#   - GitHub's closing list, and the PR body as Markdown (code and HTML comments link nothing);
#   - the subject the merge sets, else the PR title and the branch's commit subjects (GitHub's
#     COMMIT_OR_PR_TITLE gives a one-commit PR the commit's subject). An empty subject is no subject:
#     gh sends none;
#   - the body the merge sets, else the branch's commit messages and the PR body, both as plain text;
#   - the branch's commit messages whatever is set, unless the merge is a squash: a merge commit or a
#     rebase lands them past --subject and --body-file.
# Commit text is plain, so a code span shelters nothing there. Whether GitHub skips one in a commit
# message is not known, and the refusal costs a rewording.
#
# WHAT IT LEAVES. A PR that does not target MAIN_BRANCH closes nothing when it merges: GitHub closes
# only on the default branch.
#
# Fails CLOSED: a read that fails blocks, and so does a parser that fails or ends short. Under LC_ALL=C
# for the whole process, as one non-UTF-8 byte in a commit message made awk fail in a UTF-8 locale.
#
# Contract: .claude/local/README.md. Needs gh, jq, git and awk. What the guard's own same_repo and
# canon do is done again below, as they live inside a hook that cannot be sourced.
LC_ALL=C; export LC_ALL
no() { echo "$1" >&2; exit 2; }
for v in GUARD_PR GUARD_PR_REF GUARD_HEAD GUARD_BASE ROOT MAIN_BRANCH; do
  eval "[ -n \"\${$v:-}\" ]" || no "the merge guard did not pass $v, so whether this merge closes a team-queue issue cannot be checked."
done
pr=$GUARD_PR here=${GUARD_REPO:-}
# The repository the merge names, as gh would read it: a URL's host/owner/name, else its -R word.
case $GUARD_PR_REF in
  http://* | https://*) repo=$(printf '%s\n' "$GUARD_PR_REF" | sed -e 's|^[a-z]*://||' -e 's|/pull/.*$||') ;;
  *) repo=${GUARD_PR_REPO:-} ;;
esac

errf=$(mktemp "${TMPDIR:-/tmp}/guard-team-queue.XXXXXX") || no "cannot make a temp file to read gh's errors."
trap 'rm -f "$errf"' EXIT
gh_said() { grep . "$errf" | head -n 1; }

# The list first. As long as its limit, it may be cut short. This process stays in the guard's
# directory, so a read that names no repo resolves as the merge does.
list=$(gh issue list ${repo:+-R "$repo"} --label team-queue --state open --limit 1000 --json number 2>"$errf") \
  || no "cannot list the open team-queue issues (gh: $(gh_said)), so whether this merge closes one cannot be checked. Fix what gh reports (gh auth status), then retry."
printf '%s' "$list" | jq -e 'type == "array" and length < 1000' >/dev/null 2>&1 \
  || no "cannot read every open team-queue issue (gh answered: $(printf '%s' "$list" | head -c 80)), so whether this merge closes one cannot be checked."
queue=$(printf '%s' "$list" | jq -r '.[].number') || no "cannot parse the list of open team-queue issues."
[ -n "$queue" ] || exit 0

pr_json=$(gh pr view "$GUARD_PR_REF" ${GUARD_PR_REPO:+-R "$GUARD_PR_REPO"} --json title,body,baseRefName,closingIssuesReferences 2>"$errf") \
  || no "cannot read PR #$pr's title, body and closing issues (gh: $(gh_said)), so whether this merge closes a team-queue issue cannot be checked. Fix what gh reports, then retry."
printf '%s' "$pr_json" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || no "PR #$pr's details did not come back as JSON ($(printf '%s' "$pr_json" | head -c 80)), so whether this merge closes a team-queue issue cannot be checked."
base=$(printf '%s' "$pr_json" | jq -r '.baseRefName // empty')
if [ -n "$base" ] && [ "$base" != "$MAIN_BRANCH" ]; then
  echo "PR #$pr targets $base, not $MAIN_BRANCH: no closing keyword closes anything from there."
  exit 0
fi

# The merge's own words, read the way the guard's rules 12 and 15 read them.
cg="$ROOT/.claude/hooks/lib/change-guard.sh"
{ [ -f "$cg" ] && sh -n "$cg" 2>/dev/null; } || no "cannot read $cg, so the merge's own message cannot be checked for a closing keyword."
# shellcheck disable=SC1090
. "$cg"
for f in cg_body cg_subject cg_field; do
  command -v "$f" >/dev/null 2>&1 || no "$cg did not define $f, so the merge's own message cannot be checked."
done
cmd=${GUARD_COMMAND:-}
cwd=$(jq -r '.cwd // empty' "${GUARD_PAYLOAD:-/dev/null}" 2>/dev/null)
cwd=${cwd:-$ROOT}

# is_squash: 0 when the merge's plain words read as a squash. Any word that could be --merge or --rebase
# counts against it, and an API merge's default is a merge commit; a "no" reads more, so it may refuse.
# This is not the guard's reader of the method, which is inside the hook. Run alone it can allow two
# things: a method word hidden by shell quoting, and a merge commit that sets a subject and no body,
# whose message lands the PR title. The guard's rule 15 holds both while attribution is off, as it is
# here: only a squash with a body it can read reaches this rule. Turning attribution on reopens them.
is_squash() {
  _flat=$(printf '%s' "$cmd" | tr '\n\t' '  ')
  case $_flat in
    */pulls/*/merge*)
      _m=$(cg_field "$cmd" "$cwd" method) || return 1
      [ "$(printf '%s' "$_m" | tr -d '[:space:]')" = squash ]
      return ;;
  esac
  printf '%s\n' "$_flat" | grep -Eq '(^|[[:space:]])(--merge|--rebase|-[a-zA-Z]*[mr][a-zA-Z]*)([=[:space:]]|$)' && return 1
  printf '%s\n' "$_flat" | grep -Eq '(^|[[:space:]])(--squash(=true)?|-[a-zA-Z]*s[a-zA-Z]*)([[:space:]]|$)'
}

# scan MODE WHERE TEXT: add to $refs a line "<n><TAB><where><TAB><owner/name, lower case, or nothing>"
# per closing keyword TEXT holds. MODE md: Markdown, whose code and comments link nothing; plain: text
# GitHub does not render. The awk ends with a mark, so a parser that dies or ends short is seen.
TAB=$(printf '\t')
refs=""
scan() {
  _out=$(printf '%s\n' "$3" | awk -v md="$1" -v where="$2" '
    BEGIN {
      kw = "(close[sd]?|fix(e[sd])?|resolve[sd]?)"
      ref = "((https?://(www\\.)?github\\.com/)?[a-z0-9_.-]+/[a-z0-9_.-]+(#|/issues/)|#|gh-)[0-9]+"
      re = "(^|[^a-z0-9_])" kw "[ \t]*:?[ \t]*" ref
    }
    {
      line = $0
      if (md == "md") {
        if (cmt) { if ((i = index(line, "-->"))) { line = substr(line, i + 3); cmt = 0 } else next }
        while ((i = index(line, "<!--"))) {
          rest = substr(line, i + 4)
          if ((j = index(rest, "-->"))) line = substr(line, 1, i - 1) " " substr(rest, j + 3)
          else { line = substr(line, 1, i - 1); cmt = 1 }
        }
        if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
        if (fence) next
        gsub(/`[^`]*`/, "", line)
      }
      s = tolower(line)
      while (match(s, re)) {
        m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        n = m; sub(/.*[^0-9]/, "", n)
        r = ""
        if (match(m, /[a-z0-9_.-]+\/[a-z0-9_.-]+(#|\/issues\/)[0-9]+$/)) {
          r = substr(m, RSTART, RLENGTH); sub(/(#|\/issues\/)[0-9]+$/, "", r)
        }
        print (n + 0) "\t" where "\t" r
      }
    }
    END { print "end-of-scan" }') || no "the closing-keyword parser failed on $2, so whether it closes a team-queue issue cannot be checked."
  case $_out in
    end-of-scan) ;;
    *"
end-of-scan") refs="$refs${_out%"
end-of-scan"}
" ;;
    *) no "the closing-keyword parser ended short on $2, so whether it closes a team-queue issue cannot be checked." ;;
  esac
}

branch_messages() { git -C "$ROOT" log --format="$1" "$GUARD_BASE..$GUARD_HEAD" 2>/dev/null; }

closing=$(printf '%s' "$pr_json" | jq -r '.closingIssuesReferences[]?
    | "\(.number)\tGitHub'"'"'s closing list\t" + (if .repository == null then "" else (((.repository.owner.login // "") + "/" + (.repository.name // "")) | ascii_downcase) end)') \
  || no "cannot parse PR #$pr's closing issues."
[ -z "$closing" ] || refs="$closing
"
pr_body=$(printf '%s' "$pr_json" | jq -r '.body // ""')
scan md "the PR body" "$pr_body"

subject=$(cg_subject "$cmd" "$cwd"); rc=$?
[ "$rc" != 0 ] || [ -n "$(printf '%s' "$subject" | tr -d '[:space:]')" ] || rc=1
case $rc in
  0) scan plain "the squash subject" "$subject" ;;
  1) scan plain "the PR title" "$(printf '%s' "$pr_json" | jq -r '.title // ""')"
     subjects=$(branch_messages %s) || no "cannot read the commit subjects of $GUARD_BASE..$GUARD_HEAD, so whether the default subject closes a team-queue issue cannot be checked."
     scan plain "a branch commit's subject" "$subjects" ;;
  *) no "cannot read this merge's --subject (a substitution, or an API merge's --input), so whether it closes a team-queue issue cannot be checked. Pass the subject as plain text." ;;
esac
messages_read=""
body=$(cg_body "$cmd" "$cwd"); rc=$?
case $rc in
  0) scan plain "the squash body" "$body" ;;
  1) scan plain "the PR body, as the squash may copy it" "$pr_body"
     messages=$(branch_messages %B) || no "cannot read the commit messages of $GUARD_BASE..$GUARD_HEAD (the default body), so whether they close a team-queue issue cannot be checked."
     scan plain "the branch's commit messages" "$messages"; messages_read=1 ;;
  3) no "this merge names a relative --body-file after another command, which may have changed directory, so whether its body closes a team-queue issue cannot be checked. Write its path out in full, or run the merge on its own." ;;
  4) no "this merge names a --body-file after a command other than cd <path>, or beside a redirect, which may write the file after this check reads it, so whether its body closes a team-queue issue cannot be checked. Run the merge on its own (or after only cd <path> &&)." ;;
  *) no "cannot read this merge's body (a substitution, a --body-file that is not a readable regular file, or an API merge's --input), so whether it closes a team-queue issue cannot be checked. Write the body to a file and pass --body-file <file>." ;;
esac
if [ -z "$messages_read" ] && ! is_squash; then
  messages=$(branch_messages %B) || no "cannot read the commit messages of $GUARD_BASE..$GUARD_HEAD, which this merge lands as they are, so whether they close a team-queue issue cannot be checked."
  scan plain "the branch's commit messages, which this merge lands" "$messages"
fi

# full_name NAME: what GitHub calls NAME, lower case, or nothing. GitHub redirects a renamed
# repository's old name, so two names are one repository when their answers agree. gh prints an HTTP
# error's body on stdout and exits 1, so its status counts, and only an owner/name shape is an answer,
# as the guard's canon has it.
full_name() {
  _fn=$(gh api "repos/$1" --jq .full_name </dev/null 2>/dev/null) || return 0
  printf '%s\n' "$_fn" | tr '[:upper:]' '[:lower:]' | sed -n '1{/^[a-z0-9._-][a-z0-9._-]*\/[a-z0-9._-][a-z0-9._-]*$/p;}'
}
# is_here NAME: 0 this repository, 1 another. An answer it cannot get blocks, a 404 included, as the
# guard's same_repo does: the reference may be real.
is_here() {
  [ -z "$1" ] || [ -z "$here" ] || [ "$1" = "$here" ] && return 0
  _a=$(full_name "$here"); _b=$(full_name "$1")
  _asked=$1; [ -n "$_a" ] || _asked=$here
  [ -n "$_a" ] && [ -n "$_b" ] || no "a closing reference in $where names $1, and GitHub did not say whether that is this repository ($here): gh api repos/$_asked failed. So it may close an open team-queue issue. Check gh can reach GitHub (gh auth status), then merge again, or take the reference off."
  [ "$_a" = "$_b" ]
}

hit="" first="" seen=""
while IFS="$TAB" read -r n where name; do
  [ -n "$n" ] || continue
  # A reference naming a repository by another name says so: its number may be open here too.
  ref="#$n"; [ -z "$name" ] || [ "$name" = "$here" ] || ref="$name#$n"
  if printf '%s\n' "$queue" | grep -qx "$n" && is_here "$name"; then
    hit="$hit${hit:+; }#$n in $where"; first=${first:-$n}
    continue
  fi
  case " $seen " in *" $ref "*) ;; *) seen="${seen:+$seen }$ref" ;; esac
done <<EOF
$refs
EOF
if [ -n "$hit" ]; then
  link=""
  case $hit in *"GitHub's closing list"*) link=" GitHub's closing list also holds what the PR's Development sidebar links, which no keyword shows: where that is the road, remove the link there." ;; esac
  cat >&2 <<EOF
this merge would close an open team-queue issue: $hit. GitHub's closing keywords (close, fix, resolve and their forms) close an issue when the merge lands on the default branch, and an issue with this label is closed by its session. Take the keyword off: a title with no keyword, naming #$first if needed, and, if this PR delivers it, a squash body line 'Delivers team-queue #$first' (docs/conventions.md, Branching and PRs).$link A branch commit's words stop counting once a squash merge sets --subject and --body-file.
EOF
  exit 2
fi
[ -z "$seen" ] || echo "a closing reference names $seen, none of them an open team-queue issue of this repository."
exit 0
