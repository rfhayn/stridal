#!/usr/bin/env bash
# Pick the next issue for a dispatcher to work: the first eligible item in a GitHub Project's "Now" column.
# Usage:
#   dispatch-next.sh --owner <login> --project <n>        prints "<number> <type> <slug>", or nothing if none is eligible
#   dispatch-next.sh --why <number> --owner <login> --project <n>
#                                                         prints why that item is ineligible, or "eligible"
#   dispatch-next.sh --list-now --owner <login> --project <n>
#                                                         prints the Now column's Issue numbers in board order, one per line
#   dispatch-next.sh --why-now --owner <login> --project <n>
#                                                         prints "<number> <reason>" for every Now Issue in board order, the
#                                                         reason exactly what --why <number> prints, from one board read;
#                                                         prints nothing if it refuses; not combinable with --why/--list-now
#   dispatch-next.sh --name-key [--claude-md <file>]       prints the repo's key, the Name: value of the ## Dispatcher
#                                                         block of CLAUDE.md (in the cwd by default). The dispatcher's
#                                                         session is dispatch-<key>, a worker's <key>-<slug>, so two
#                                                         repos' dispatchers on one machine never share a name.
#   dispatch-next.sh --field <Key> [--claude-md <file>]    prints that Key's value from the same block (e.g. Agent, "Agent keychain",
#                                                         Approver); exit 2 when it is missing, repeated, empty or a {{placeholder}}.
# Two workers at once (optional; without --with/--with-hard the pick is unchanged):
#   --with <n>          (repeatable) an in-flight issue; its body gives its footprint
#   --with-hard <n>     (repeatable) an in-flight issue known to be hard (its PR is labelled lane:3-hard); also in-flight
#   --areas "<a>, <b>"  the project's footprint areas (comma and/or space separated)
#   --hard-file <path>  a file holding a HARD_PATHS='<ERE>' line (with or without a leading "local "); refused if unreadable
#   dispatch-next.sh --footprint-of <body-file>            prints the Footprint paths of an issue body saved to a file, one
#                                                         normalised path per line; nothing (exit 0) when there is no Footprint,
#                                                         a placeholder or an unsafe value. scope-check.sh --footprint reads it.
#   --with-paths <n>:<paths>  (repeatable) paths in-flight item <n> grew into (its PR body's "Footprint grew:" value);
#                       they join its footprint (keys and hard). <n> must also be given by --with or --with-hard. A
#                       placeholder value adds nothing; an unsafe path makes <n> count as having no Footprint.
# With in-flight items the pick (and --why) also requires the item to be compatible with all of them. A footprint is a body
# line "Footprint: <path>, <path>" (backticks, a "- " prefix, "**Footprint:**" or "**Footprint**:" allowed), or a heading
# line "## Footprint" (any level, any case) with the paths on the following non-empty lines up to the next blank line or
# heading (a trailing "." is dropped); the "Footprint:" line wins when both appear. A placeholder
# value (none, tbd, n/a, ?) or any unsafe path (absolute, "..", or a glob character * ? [ ] { }) counts as no Footprint.
# Its key per path is the --areas entry the path
# falls under, else the path; keys overlap when equal or one is a directory prefix of the other. No Footprint = runs alone.
# A path is hard when it, or a file `git ls-files -- <path>` lists (run in the cwd), matches the --hard-file ERE. At most one
# hard item at a time. --why reasons after the usual ones: "no Footprint (runs alone)", "in-flight #<m> has no Footprint",
# "overlaps #<m> (<key>)", "hard while #<m> is hard", else "eligible".
# Eligible: status Now, an Issue (not a PR or draft), open, no label starting "agent:", and a body saying "Done when".
# type is fix (label "bug", or a title whose first word is Fix/fix) else feat. slug is <number>-<title>, lowercased,
# runs of non-[a-z0-9] as "-", the approval label's name replaced by "approval", at most 42 characters, no leading or
# trailing "-".
# Order, status, type and number come from the board; state, labels, title and body come from gh issue view,
# one call per Now issue, stopping at the first eligible one.
# The board is read with paginated `gh api graphql` (user-owned projects only), not `gh project item-list`, which
# fails with "unknown owner type" under a token without read:org. The pages are normalised to
# {items:[{status, content:{type, number}}]} in board order; an item with no Status or no number (a draft) never matches.
# Tests: DISPATCH_GRAPHQL_PAGES names a file of GraphQL page responses, concatenated as --paginate prints them, used in
# place of the live fetch (same normalisation); DISPATCH_BOARD_JSON names an already-normalised board;
# DISPATCH_ISSUE_DIR/<n>.json in place of gh issue view.
# Exit 2 = refused (bad args, or gh failed).
set -euo pipefail
export LC_ALL=C

refuse() { echo "dispatch-next.sh: refused: $*" >&2; exit 2; }

owner="" project="" why="" list_now="" why_now="" areas="" hard_file="" with_list="" with_hard_list="" grew_args=()
name_key="" claude_md="CLAUDE.md" field="" fp_of=""
while [ $# -gt 0 ]; do
  case $1 in
    --name-key) name_key=1; shift ;;
    --field)   [ $# -ge 2 ] || refuse "--field needs a value"; field=$2; shift 2 ;;
    --claude-md) [ $# -ge 2 ] || refuse "--claude-md needs a value"; claude_md=$2; shift 2 ;;
    --footprint-of) [ $# -ge 2 ] || refuse "--footprint-of needs a value"; fp_of=$2; shift 2 ;;
    --list-now) list_now=1; shift ;;
    --why-now) why_now=1; shift ;;
    --owner)  [ $# -ge 2 ] || refuse "--owner needs a value"; owner=$2; shift 2 ;;
    --project) [ $# -ge 2 ] || refuse "--project needs a value"; project=$2; shift 2 ;;
    --why)     [ $# -ge 2 ] || refuse "--why needs a value"; why=$2; shift 2 ;;
    --areas)   [ $# -ge 2 ] || refuse "--areas needs a value"; areas=$2; shift 2 ;;
    --hard-file) [ $# -ge 2 ] || refuse "--hard-file needs a value"; hard_file=$2; shift 2 ;;
    --with)    [ $# -ge 2 ] || refuse "--with needs a value"; [[ "$2" =~ ^[0-9]+$ ]] || refuse "--with must be an issue number"
               with_list="$with_list $2"; shift 2 ;;
    --with-hard) [ $# -ge 2 ] || refuse "--with-hard needs a value"; [[ "$2" =~ ^[0-9]+$ ]] || refuse "--with-hard must be an issue number"
               with_hard_list="$with_hard_list $2"; shift 2 ;;
    --with-paths) [ $# -ge 2 ] || refuse "--with-paths needs a value"
               [[ "$2" =~ ^[0-9]+: ]] || refuse "--with-paths must be <issue number>:<paths>"
               grew_args+=("$2"); shift 2 ;;
    *) refuse "unknown argument '$1'" ;;
  esac
done
# fpval: a footprint value (the text after the colon) -> "none" when it is none, tbd, n/a, ? or empty; "unsafe" when
# any path is absolute, ".", "./" alone, has a ".." segment, or has a glob character (* ? [ ] { }: key_of and
# keys_overlap compare paths literally, so src/* would overlap nothing); else the paths, one per line ("+" prefixed), leading
# "./" and trailing "/" stripped. Backticks and "**" are ignored. Shared by the issue Footprint, --with-paths and
# --footprint-of (so scope-check.sh reads the same rule as the dispatcher).
fpval_jq='def fpval: gsub("`|\\*\\*"; "") | gsub("^\\s+|\\s+$"; "")
  | if test("^(none|tbd|n/a|\\?)?$"; "i") then "none"
    else [split("[,\\s]+"; "g") | .[] | select(length > 0) | sub("^(\\./)+"; "")]
      | if all(.[]; startswith("/") or . == "" or . == "." or test("(^|/)\\.\\.(/|$)") or test("[*?\\[\\]{}]") | not)
        then .[] | sub("/+$"; "") | select(length > 0) | "+" + . else "unsafe" end end;'
# fp_paths JSON -> the declared footprint paths, one per line (nothing when there is no Footprint line, or its value
# is a placeholder or unsafe: runs alone).
fp_paths() {
  jq -r "$fpval_jq"'(.body // "") | split("\n") as $l
    | ($l | map(select(test("^\\s*(-\\s+)?(\\*\\*)?\\s*footprint\\s*(\\*\\*)?\\s*:"; "i"))) | .[0]) as $c
    | (if $c != null then $c | sub("^[^:]*:"; "")
       else
         ([range(0; $l | length) | select($l[.] | test("^\\s*#+\\s*footprint\\s*$"; "i"))] | .[0]) as $h
         | if $h == null then empty
           else $l[$h + 1:] | map(gsub("^\\s+|\\s+$"; "")) | until(length == 0 or .[0] != ""; .[1:])
             | . as $r | ([range(0; $r | length) | select($r[.] == "" or ($r[.] | test("^#")))] | .[0]) as $e
             | (if $e == null then $r else $r[:$e] end) | join(" ") | sub("\\.$"; "")
           end
       end)
    | fpval | select(startswith("+")) | .[1:]' <<<"$1"
}
if [ -n "$fp_of" ]; then
  # The issue body saved to a file: print its Footprint paths, one per line, through the same parser the dispatcher
  # uses. Nothing printed (exit 0) = no Footprint, a placeholder, or an unsafe value.
  [ -r "$fp_of" ] && [ -f "$fp_of" ] || refuse "cannot read $fp_of"
  fp_json=$(jq -n --rawfile b "$fp_of" '{body: $b}') || refuse "cannot read $fp_of as text"
  fp_paths "$fp_json"
  exit 0
fi
if [ -n "$field" ]; then
  # Any one `Key: value` pair of the ## Dispatcher block, by the same block rules as --name-key. Exactly one pair
  # with that key; an empty value or a {{placeholder}} counts as unset. The launcher reads Agent, Agent keychain
  # and Approver this way, so there is one parser of the block.
  [[ $field =~ ^[A-Za-z][A-Za-z\ ]*$ ]] || refuse "--field must be a key name (letters and spaces)"
  [ -r "$claude_md" ] && [ -f "$claude_md" ] || refuse "cannot read $claude_md"
  vals=$(awk -v key="$field" '
    /^## / { inblk = ($0 ~ /^## Dispatcher[[:space:]]*$/); next }
    inblk && /^- / {
      line = substr($0, 3); n = split(line, parts, / · /)
      for (i = 1; i <= n; i++) if (index(parts[i], key ":") == 1) { v = substr(parts[i], length(key) + 2); sub(/^[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); print v }
    }' "$claude_md") || refuse "cannot parse $claude_md"
  [ -n "$vals" ] || refuse "the ## Dispatcher block of $claude_md has no $field: value"
  [ "$(printf '%s\n' "$vals" | wc -l | tr -d ' ')" = 1 ] || refuse "the ## Dispatcher block of $claude_md has more than one $field: key"
  case $vals in *'{{'*) refuse "$field in $claude_md is still a {{placeholder}}" ;; esac
  printf '%s\n' "$vals"
  exit 0
fi
if [ -n "$name_key" ]; then
  # The repo's key from the `## Dispatcher` block: its bullets are `Key: value` pairs joined by " · ". Only that
  # block counts (it ends at the next "## " heading). Exactly one Name pair, matching KEY_RE.
  [ -r "$claude_md" ] && [ -f "$claude_md" ] || refuse "cannot read $claude_md"
  keys=$(awk '
    /^## / { inblk = ($0 ~ /^## Dispatcher[[:space:]]*$/); next }
    inblk && /^- / {
      line = substr($0, 3); n = split(line, parts, / · /)
      for (i = 1; i <= n; i++) if (parts[i] ~ /^Name:/) { v = parts[i]; sub(/^Name:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); print v }
    }' "$claude_md") || refuse "cannot parse $claude_md"
  [ -n "$keys" ] || refuse "the ## Dispatcher block of $claude_md has no Name: key"
  [ "$(printf '%s\n' "$keys" | wc -l | tr -d ' ')" = 1 ] || refuse "the ## Dispatcher block of $claude_md has more than one Name: key"
  KEY_RE='^[a-z][a-z0-9-]{0,18}[a-z0-9]$'
  [[ $keys =~ $KEY_RE ]] || refuse "Name must match $KEY_RE (a lowercase letter first, at most 20 characters)"
  printf '%s\n' "$keys"
  exit 0
fi
[ -n "$owner" ] || refuse "--owner <login> is required"
[ -n "$project" ] || refuse "--project <n> is required"
[[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || refuse "--owner must be a GitHub login"
[[ "$project" =~ ^[0-9]+$ ]] || refuse "--project must be a number"
if [ -n "$why" ]; then [[ "$why" =~ ^[0-9]+$ ]] || refuse "--why must be an issue number"; fi
if [ -n "$why" ] && [ -n "$list_now" ]; then refuse "--why and --list-now cannot be combined"; fi
if [ -n "$why_now" ] && [ -n "$why" ]; then refuse "--why-now and --why cannot be combined"; fi
if [ -n "$why_now" ] && [ -n "$list_now" ]; then refuse "--why-now and --list-now cannot be combined"; fi

# One page per item batch of 100, in board (POSITION) order; --paginate follows pageInfo.endCursor.
# shellcheck disable=SC2016 # $owner etc. are GraphQL variables, not shell ones
query='query($owner:String!,$number:Int!,$endCursor:String){ user(login:$owner){ projectV2(number:$number){
  items(first:100, after:$endCursor, orderBy:{field:POSITION,direction:ASC}){ pageInfo{hasNextPage endCursor}
  nodes{ fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue{name} }
  content{ __typename ... on Issue{number} ... on PullRequest{number} } } } } } }'

pages="" board=""
if [ -n "${DISPATCH_GRAPHQL_PAGES:-}" ]; then
  pages=$(cat "$DISPATCH_GRAPHQL_PAGES") || refuse "cannot read DISPATCH_GRAPHQL_PAGES"
elif [ -n "${DISPATCH_BOARD_JSON:-}" ]; then
  board=$(cat "$DISPATCH_BOARD_JSON") || refuse "cannot read DISPATCH_BOARD_JSON"
else
  pages=$(gh api graphql --paginate -f owner="$owner" -F number="$project" -f query="$query") || refuse "gh api graphql failed"
fi
if [ -z "${DISPATCH_BOARD_JSON:-}" ] || [ -n "${DISPATCH_GRAPHQL_PAGES:-}" ]; then
  jq -se 'length > 0 and all(.[]; (.data.user.projectV2.items.nodes | type) == "array")' >/dev/null 2>&1 <<<"$pages" \
    || refuse "board GraphQL page has no items.nodes array"
  board=$(jq -sc '{items: [.[].data.user.projectV2.items.nodes[]
    | {status: (.fieldValueByName.name // null),
       content: {type: (.content.__typename // null), number: (.content.number // null)}}]}' <<<"$pages") \
    || refuse "cannot normalise board GraphQL pages"
fi
jq -e '.items | type == "array"' >/dev/null 2>&1 <<<"$board" || refuse "board JSON has no items array"

now_issues() { jq -r '.items[] | select(.status == "Now" and .content.type == "Issue") | .content.number' <<<"$board"; }

if [ -n "$list_now" ]; then
  now_issues
  exit 0
fi

# issue_json NUMBER -> {title,body,state,labels} on stdout. Call it as its own statement (js=$(issue_json N)),
# never nested in another substitution, so a refusal here ends the script with exit 2.
issue_json() {
  local out
  if [ -n "${DISPATCH_ISSUE_DIR:-}" ]; then
    out=$(cat "$DISPATCH_ISSUE_DIR/$1.json") || refuse "no issue fixture for #$1"
  else
    out=$(gh issue view "$1" --json state,body,labels,title) || refuse "gh issue view $1 failed"
  fi
  jq -e 'type == "object" and (.labels | type) == "array" and (.title | type) == "string"' >/dev/null 2>&1 <<<"$out" || refuse "bad issue JSON for #$1"
  printf '%s\n' "$out"
}

hard_re=""
if [ -n "$hard_file" ]; then
  hard_re=$(sed -n "s/^[[:space:]]*\(local \)\{0,1\}HARD_PATHS='\(.*\)'[[:space:]]*\$/\2/p" "$hard_file" 2>/dev/null | head -n 1) \
    || refuse "cannot read --hard-file"
  [ -n "$hard_re" ] || refuse "--hard-file has no HARD_PATHS='...' line"
fi
areas_list=${areas//,/ }

# key_of PATH -> the --areas entry PATH falls under, else PATH.
key_of() {
  local a
  for a in $areas_list; do
    a=${a%/}
    case "$1" in "$a"|"$a"/*) echo "$a"; return 0 ;; esac
  done
  echo "$1"
}
# hard_path PATH -> 0 when PATH, or a tracked file under it, matches the hard ERE.
hard_path() {
  [ -n "$hard_re" ] || return 1
  if printf '%s\n' "$1" | grep -Eq -- "$hard_re"; then return 0; fi
  # Process substitution, not a pipe: under pipefail, grep -q exiting early could fail the pipe with SIGPIPE.
  grep -Eq -- "$hard_re" < <(git ls-files -- "$1" 2>/dev/null || true)
}
# fp_info JSON -> sets FP_HAS (0/1), FP_KEYS (newline list), FP_HARD (0/1)
fp_info() {
  local paths p
  FP_HAS=0 FP_KEYS="" FP_HARD=0
  paths=$(fp_paths "$1")
  [ -n "$paths" ] || return 0
  FP_HAS=1
  while IFS= read -r p; do
    FP_KEYS="$FP_KEYS$(key_of "$p")"$'\n'
    if [ "$FP_HARD" = 0 ] && hard_path "$p"; then FP_HARD=1; fi
  done <<<"$paths"
}
keys_overlap() { # A B -> 0 when equal or one is a directory prefix of the other
  case "$1/" in "$2"/*) return 0 ;; esac
  case "$2/" in "$1"/*) return 0 ;; esac
  return 1
}

# In-flight items: footprint from the issue body, hard from the footprint or --with-hard.
inflight=""
for m in $with_list $with_hard_list; do
  case " $inflight " in *" $m "*) continue ;; esac
  inflight="$inflight $m"
  ijs=$(issue_json "$m")
  fp_info "$ijs"
  printf -v "IF_HAS_$m" '%s' "$FP_HAS"
  printf -v "IF_KEYS_$m" '%s' "$FP_KEYS"
  printf -v "IF_HARD_$m" '%s' "$FP_HARD"
done
for m in $with_hard_list; do printf -v "IF_HARD_$m" '%s' 1; done
# Grown paths (--with-paths) join an in-flight item's keys and hard flag; an unsafe one makes it count as no Footprint.
for g in ${grew_args[@]+"${grew_args[@]}"}; do
  m=${g%%:*} val=${g#*:}
  case " $inflight " in *" $m "*) ;; *) refuse "--with-paths #$m is not given by --with or --with-hard" ;; esac
  gp=$(jq -rn --arg v "$val" "$fpval_jq"' $v | fpval') || refuse "cannot parse --with-paths for #$m"
  [ "$gp" != none ] || continue
  if [ "$gp" = unsafe ]; then printf -v "IF_HAS_$m" '%s' 0; continue; fi
  v=IF_KEYS_$m; keys=${!v}
  v=IF_HARD_$m; hard=${!v}
  while IFS= read -r p; do
    p=${p#+}
    keys="$keys$(key_of "$p")"$'\n'
    if [ "$hard" = 0 ] && hard_path "$p"; then hard=1; fi
  done <<<"$gp"
  printf -v "IF_KEYS_$m" '%s' "$keys"
  printf -v "IF_HARD_$m" '%s' "$hard"
done

# compat JSON -> the reason this issue cannot run beside the in-flight items, or nothing.
compat() {
  local m v k ik
  [ -n "$inflight" ] || return 0
  fp_info "$1"
  if [ "$FP_HAS" = 0 ]; then echo "no Footprint (runs alone)"; return 0; fi
  for m in $inflight; do
    v=IF_HAS_$m
    if [ "${!v}" = 0 ]; then echo "in-flight #$m has no Footprint"; return 0; fi
  done
  for m in $inflight; do
    v=IF_KEYS_$m
    while IFS= read -r ik; do
      [ -n "$ik" ] || continue
      while IFS= read -r k; do
        [ -n "$k" ] || continue
        if keys_overlap "$k" "$ik"; then echo "overlaps #$m ($k)"; return 0; fi
      done <<<"$FP_KEYS"
    done <<<"${!v}"
  done
  if [ "$FP_HARD" = 1 ]; then
    for m in $inflight; do
      v=IF_HARD_$m
      if [ "${!v}" = 1 ]; then echo "hard while #$m is hard"; return 0; fi
    done
  fi
  return 0
}

# problem JSON -> the first reason this issue is ineligible, or nothing. Reasons after the board checks, in order.
problem() {
  jq -r '
    if .state != "OPEN" then "closed"
    elif ([.labels[]?.name | select(startswith("agent:"))] | length) > 0
      then "labeled " + ([.labels[].name | select(startswith("agent:"))][0])
    elif ((.body // "") | test("done when"; "i") | not) then "no Done when"
    else empty end' <<<"$1"
}

if [ -n "$why" ]; then
  row=$(jq -c --argjson n "$why" '[.items[] | select(.content.number == $n)][0] // empty' <<<"$board")
  if [ -z "$row" ] || [ "$(jq -r '.status // ""' <<<"$row")" != "Now" ]; then echo "not in Now"; exit 0; fi
  if [ "$(jq -r '.content.type // ""' <<<"$row")" != "Issue" ]; then echo "not an issue"; exit 0; fi
  js=$(issue_json "$why")
  p=$(problem "$js") || refuse "bad issue JSON for #$why"
  [ -n "$p" ] || p=$(compat "$js")
  echo "${p:-eligible}"
  exit 0
fi

if [ -n "$why_now" ]; then
  # Every Now issue's --why reason from the one board read above: "<number> <reason>" in board order. Collect first and
  # print last, so a refusal part-way (issue_json refuses, exit 2) leaves stdout empty.
  out=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    js=$(issue_json "$n")
    p=$(problem "$js") || refuse "bad issue JSON for #$n"
    [ -n "$p" ] || p=$(compat "$js")
    out="$out$n ${p:-eligible}"$'\n'
  done < <(now_issues)
  printf '%s' "$out"
  exit 0
fi

fix_re='^[Ff]ix([^A-Za-z0-9]|$)'
while IFS= read -r n; do
  [ -n "$n" ] || continue
  js=$(issue_json "$n")
  p=$(problem "$js") || refuse "bad issue JSON for #$n"
  [ -z "$p" ] || continue
  c=$(compat "$js")
  [ -z "$c" ] || continue
  title=$(jq -r '.title // ""' <<<"$js")
  type=feat
  if jq -e '[.labels[]?.name] | index("bug")' >/dev/null 2>&1 <<<"$js" || [[ "$title" =~ $fix_re ]]; then type=fix; fi
  # The approval label's name never goes into a slug: the settings deny Bash(*merge-ok*) (Stridal's ADR-0003) would then stop every
  # session.sh, git and gh command naming the slug or its branch.
  rest=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//; s/merge-ok/approval/g')
  slug=$n
  [ -z "$rest" ] || slug="$n-$rest"
  slug=$(printf '%s' "$slug" | cut -c1-42 | sed 's/-*$//')
  echo "$n $type $slug"
  exit 0
done < <(now_issues)
exit 0
