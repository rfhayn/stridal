#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# An ADR rests on evidence before it is accepted (PRAC-0023's practices 1 and 2). An ADR numbered
# ADR_EVIDENCE_FROM or later, written since RECORDS_BASELINE, is held: its Status line must read
# exactly one of Proposed, Accepted or Superseded (an unreadable Status, another word, or two of
# them, as in "Proposed → Accepted", fails: the check fails closed), and an Accepted one must have
# a `## Rests on` section whose every item has one of two FORMS (the template's), and nothing else
# passes. A form is matched in its position, never as words found anywhere in the item:
#   - CITED: `<assumption>: <cite>, **passed**` and then `.`, ` (` or the item's end, where the
#     cites follow the colon, joined by ` and ` or ` to `, and each is a spike id from a table in
#     an ADR_EVIDENCE_SPIKES file (a row whose first cell is the id, such as `| S1a |`), a PR
#     (`#371`) or a gate receipt named by its commit (`receipt 75c86686`, 7 to 40 hex digits);
#   - AT RISK: it reads `— accepted at risk by the owner (YYYY-MM-DD)`, a real date (PRAC-0023's
#     exception: the owner accepts it with the assumption named). A negation ("not accepted at
#     risk") fails.
# An item marked **untested** or **pending** (bold: both mean not yet evidence) fails unless it is
# AT RISK. An item is a column-0 `- ` line and its continuation lines (indented, or directly under
# it); any other list line (`* `, `+ `, `1. `, an indented `- `) or a column-0 paragraph after a
# blank line, once the items have begun, is text the check cannot read, and fails. Prose before
# the first item is not an item. Proposed and Superseded ADRs are not judged: drafting one with
# untested items is the point of the section. Practice records are not judged either.
# ADR_EVIDENCE_FROM empty: nothing is held.
#
# ADR_EVIDENCE_KNOWN lists Accepted ADRs found with items that cite nothing, as NNNN:COUNT, so
# the check can land on a history that predates it: each is printed on every run as KNOWN (waived,
# not passed, with OWNER_QUEUE as its addressee: the entry's owner-queue item closes it), an ADR
# whose count rises fails, and one whose count falls fails until the entry is lowered. Only "cites
# nothing" is waived this way; a missing section, an untested or pending item not at risk, a
# negated acceptance, an unreadable line and an unreadable Status always fail. Falsified on
# fixtures below.
. "$(dirname "$0")/lib.sh"
. "$STRIDAL_FW/lib/records.sh"

# ── Self-test ─────────────────────────────────────────────────────────────────────────────────────
if [ -z "${ADR_EVIDENCE_SELFTEST:-}" ]; then
  mke() {  # mke NAME: a fixture project with one spike table, held from ADR 0010
    F="$(scratch)/ev-$1"; A="$F/docs/adr"; mkdir -p "$F/.claude/checks" "$A" "$F/docs/plans"
    cp -R "$STRIDAL_FW/lib" "$F/.claude/"; cp "$STRIDAL_FW/checks/lib.sh" "$STRIDAL_FW/checks/adr-evidence.sh" "$F/.claude/checks/"
    printf '# Spikes\n\n| Id | Probe | Result |\n|---|---|---|\n| S1a | a hook | blocked |\n| S1e | a hang | blocked |\n| S2 | a server | works |\n' > "$F/docs/plans/spikes.md"
    printf 'ADR_EVIDENCE_FROM="0010"\nADR_EVIDENCE_SPIKES="docs/plans/spikes.md"\n' > "$F/.claude/project.conf"
    # An old Accepted ADR below the floor, with no section: history, never judged.
    printf '# ADR 0003: Old\n\n- **Status**: Accepted\n- **Date**: 2026-01-01\n\n## Decision\nx\n' > "$A/0003-old.md"
  }
  adr() {  # adr NUM STATUS [RESTS-ON-BODY]: ADR NUM; no third argument = no Rests on section
    { printf '# ADR %s: A decision\n\n- **Status**: %s\n- **Date**: 2026-10-31\n\n## Decision\nx\n' "$1" "$2"
      [ $# -ge 3 ] && printf '\n## Rests on\n%s\n' "$3"
      printf '\n## Enforcement\nchecks/x.sh\n'; } > "$A/$1-a-decision.md"
  }
  raw() { printf '# ADR 0010: A decision\n\n%s\n\n## Rests on\n- A hook blocks: **pending**.\n' "$1" > "$A/0010-a-decision.md"; }
  erun() { (ROOT="$F" ADR_EVIDENCE_SELFTEST=1 sh "$F/.claude/checks/adr-evidence.sh") > "$(scratch)/e.out" 2>&1; }
  eok() { if erun; then ok "adr-evidence: $1 passes"; else fail "adr-evidence: $1 FAILED:"; grep '^FAIL' "$(scratch)/e.out" | sed 's/^/       /'; fi; }
  ebad() {
    if erun; then fail "adr-evidence: $1 passed"
    elif grep '^FAIL' "$(scratch)/e.out" | grep -qF -- "$2"; then ok "adr-evidence: $1 fails ($2)"
    else fail "adr-evidence: $1 fails, but not for '$2':"; grep '^FAIL' "$(scratch)/e.out" | sed 's/^/       /'; fi
  }
  uncited="Rests on item 1 cites no result"

  mke none; adr 0010 Accepted
  ebad "an Accepted ADR with no Rests on section" "0010-a-decision.md is Accepted but has no '## Rests on' section"
  mke pending; adr 0010 'Accepted (the owner, 2026-10-31)' '- A hook blocks: S1a, **passed**.
- The server starts in time: **pending**, its PR #9 open.'
  ebad "an Accepted ADR with a pending assumption" "0010-a-decision.md, Rests on item 2 is pending (not yet evidence)"
  mke empty; adr 0010 Accepted 'Nothing is assumed.'
  ebad "an Accepted ADR whose Rests on lists no item" "0010-a-decision.md is Accepted but its '## Rests on' lists no assumption"
  mke untested; adr 0010 Accepted '- A lane reaches the tools: **untested**; tested by OPS-9.'
  ebad "an untested assumption the owner did not accept at risk" "0010-a-decision.md, Rests on item 1 is untested (not yet evidence)"
  mke uncited; adr 0010 Accepted '- Every reader is known: the classification, section E.'
  ebad "an assumption that cites no result" "0010-a-decision.md, $uncited"
  mke unknown-id; adr 0010 Accepted '- A hook blocks: S9z, **passed**.'
  ebad "a spike id no spike table holds" "$uncited"
  mke no-passed; adr 0010 Accepted '- A hook blocks: S1a.'
  ebad "a spike id without **passed**" "$uncited"
  # The allow-list: a word near a citation is not one (the review's probes, round 1).
  mke no-receipt; adr 0010 Accepted '- The gate passes: no receipt yet.'
  ebad "'no receipt yet'" "$uncited"
  mke tbd; adr 0010 Accepted '- The server starts: TBD, see #400.'
  ebad "'TBD, see #400'" "$uncited"
  mke not-yet; adr 0010 Accepted '- The server starts: **not yet tested** (to be tested by OPS-199, PR #400 open).'
  ebad "'**not yet tested** (... PR #400 open)'" "$uncited"
  mke would; adr 0010 Accepted '- X: S1a would show it, not run yet.'
  ebad "'S1a would show it, not run yet'" "$uncited"
  mke bare-receipt; adr 0010 Accepted '- The gate ran: its receipt, **passed**.'
  ebad "a receipt not named by its commit" "$uncited"
  # Round 2's probes: **passed** and a citation each present, but not in the template's form.
  mke negpassed; adr 0010 Accepted '- X: has not **passed** yet; see #400.'
  ebad "'has not **passed** yet; see #400'" "$uncited"
  mke negpassed2; adr 0010 Accepted '- X: S1a, never **passed**.'
  ebad "'S1a, never **passed**'" "$uncited"
  mke failed; adr 0010 Accepted '- X: **passed**? No, it failed in #400.'
  ebad "'**passed**? No, it failed in #400'" "$uncited"
  mke passed-question; adr 0010 Accepted '- X: S1a, **passed**? No, it failed.'
  ebad "'S1a, **passed**? No, it failed' (only '.', ' (' or the end follows **passed**)" "$uncited"
  mke url; adr 0010 Accepted '- X: **passed** (https://example.com/doc#3).'
  ebad "'**passed** (https://example.com/doc#3)'" "$uncited"
  mke codespan; adr 0010 Accepted '- X: **passed**, see `#1` in the notes.'
  ebad "'**passed**, see \`#1\` in the notes'" "$uncited"
  mke itemref; adr 0010 Accepted '- X: same as item #2, **passed** there.'
  ebad "'same as item #2, **passed** there'" "$uncited"
  mke itemref-end; adr 0010 Accepted '- X: same as item #2, **passed**.'
  ebad "'same as item #2, **passed**.' (the cites follow the colon)" "$uncited"
  mke receiptword; adr 0010 Accepted '- X: **passed**, no receipt for defaced runs.'
  ebad "'**passed**, no receipt for defaced runs'" "$uncited"
  mke deadbeef; adr 0010 Accepted '- X: **passed**, the receipt deadbeef is a placeholder.'
  ebad "'**passed**, the receipt deadbeef is a placeholder'" "$uncited"
  mke s1a-like; adr 0010 Accepted '- X: S1a-like, **passed**.'
  ebad "'S1a-like, **passed**' (an id inside a word)" "$uncited"
  mke range-unknown; adr 0010 Accepted '- X: S1a to S9z, **passed**.'
  ebad "a range whose end no spike table holds" "$uncited"
  # Round 2's probes: a line the item parser cannot read fails, never joins or drops silently.
  mke starbullet; adr 0010 Accepted '- X: S1a, **passed**.
* Y: nothing at all.'
  ebad "a '* ' item after a cited one" "Rests on line 11 is a list line but not a column-0 \`- \` item"
  mke numbered; adr 0010 Accepted '- X: S1a, **passed**.
2. Y: nothing at all.'
  ebad "a numbered item after a cited one" "Rests on line 11 is a list line but not a column-0 \`- \` item"
  mke nested; adr 0010 Accepted '- X: S1a, **passed**.
  - Y: nothing at all.'
  ebad "an indented '- ' item under a cited one" "Rests on line 11 is a list line but not a column-0 \`- \` item"
  mke indented-only; adr 0010 Accepted '  - X: nothing.'
  ebad "an indented '- ' item and no column-0 one" "Rests on line 10 is a list line but not a column-0 \`- \` item"
  mke proseafter; adr 0010 Accepted '- X: S1a, **passed**.

Also assumed: Y, which nothing has shown.'
  ebad "a column-0 paragraph after the items" "Rests on line 12 is text after a blank line that belongs to no item"
  # Round 2's probes: the at-risk date is a date; only the bold markers mean untested or pending.
  mke baddate; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2026-99-99).'
  ebad "an acceptance at risk dated 2026-99-99" "Rests on item 1 is untested"
  mke notadate; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (0000-00-00).'
  ebad "an acceptance at risk dated 0000-00-00" "Rests on item 1 is untested"
  mke passed-untested; adr 0010 Accepted '- X: S1a, **passed**; the hang case is **untested**.'
  ebad "a cited item that marks a case **untested**" "Rests on item 1 is untested"
  mke words; adr 0010 Accepted '- A pending tool call is cancelled on timeout: S1a, **passed**.
- Untested hooks fail open: S2, **passed**.'
  eok "a cited item that says 'pending' or 'untested' without the bold marker"
  # Round 2's probe: a Status naming two states is read by neither.
  mke st-arrow; raw '- **Status**: Proposed → Accepted (the owner, 2026-10-31)'
  ebad "a Status 'Proposed → Accepted'" "names more than one of Proposed, Accepted and Superseded"
  # Shapes the parser reads: wrapped lines (a trailing blank too), and CRLF line ends.
  mke wrapped; adr 0010 Accepted '- X: S1a,
  **passed**.
- Y: **untested** —
  accepted at risk by the owner (2026-10-31).
'"$(printf -- '- Z: **untested** — accepted at risk by the \n  owner (2026-10-31).')"
  eok "items wrapped across lines, one with a trailing blank"
  mke crlf; adr 0010 Accepted '- X: S1a, **passed**.
- Y: **pending**.'
  awk '{ printf "%s\r\n", $0 }' "$A/0010-a-decision.md" > "$A/x" && mv "$A/x" "$A/0010-a-decision.md"
  ebad "a pending item in a CRLF file" "Rests on item 2 is pending"
  adr 0010 Accepted '- X: S1a, **passed**.'
  awk '{ printf "%s\r\n", $0 }' "$A/0010-a-decision.md" > "$A/x" && mv "$A/x" "$A/0010-a-decision.md"
  eok "a cited item in a CRLF file"
  mke cited; adr 0010 Accepted 'These are the assumptions (PRAC-0023).
- A hook blocks: S1a to S1e, **passed**.
- A server starts: S2, **passed**.
- A hang ends: S1a and S1e, **passed** (both runs).
- The port measured it: #371, **passed**.
- The gate ran: receipt 75c86686, **passed**.'
  eok "an Accepted ADR whose every assumption is **passed** on a spike, a PR or a receipt"
  mke at-risk; adr 0010 Accepted '- A hook blocks: S1a, **passed**.
- Hooks write outside the sandbox: **untested** — accepted at risk by the owner
  (2026-10-31); tested by OPS-9.
- Polling is fast: **pending** — accepted at risk by the owner (2026-10-31); tested by OPS-9.'
  eok "an Accepted ADR with untested and pending items accepted at risk by the owner"
  mke risk-negated; adr 0010 Accepted '- Hooks write: **untested**, not accepted at risk by the owner yet.'
  ebad "'not accepted at risk by the owner yet'" "Rests on item 1 negates the owner's acceptance at risk"
  mke risk-negated-form; adr 0010 Accepted '- Hooks write: **untested** — accepted at risk by the owner (2026-10-31)? No: not yet accepted at risk.'
  ebad "the at-risk form beside its negation" "Rests on item 1 negates the owner's acceptance at risk"
  mke risk-loose; adr 0010 Accepted '- Hooks write: **untested**, accepted at risk by the owner.'
  ebad "an acceptance at risk not in the template form" "Rests on item 1 is untested (not yet evidence)"
  mke proposed; adr 0010 'Proposed. The owner decides at Gate C.' '- A hook appends: **untested**. Gate A.
- Polling is fast: **pending**.'
  eok "a Proposed ADR with untested and pending items (not judged)"
  mke superseded; adr 0010 'Superseded by ADR-0011'; eok "a Superseded ADR with no section (not judged)"
  # The Status line, read in each form a writer uses; anything else fails closed.
  mke st-bold; adr 0010 '**Accepted**' '- X: **pending**.'
  ebad "a bold **Accepted** Status" "Rests on item 1 is pending"
  mke st-lower; adr 0010 'accepted' '- X: **pending**.'
  ebad "a lower-case accepted Status" "Rests on item 1 is pending"
  mke st-nobullet; raw '**Status**: Accepted'
  ebad "a Status line without its '- '" "Rests on item 1 is pending"
  mke st-colon-in-bold; raw '- **Status:** Accepted'
  ebad "a '**Status:**' line" "Rests on item 1 is pending"
  mke st-other; raw '- **Status**: Approved'
  ebad "a Status that is not Proposed, Accepted or Superseded" "0010-a-decision.md has Status 'Approved'"
  mke st-none; raw '- **State**: Accepted'
  ebad "an ADR with no Status line" "0010-a-decision.md has no readable Status line"
  mke off; adr 0010 Accepted; printf 'ADR_EVIDENCE_FROM=""\n' > "$F/.claude/project.conf"
  if erun && grep -q 'ADR_EVIDENCE_FROM is empty' "$(scratch)/e.out"; then ok "adr-evidence: ADR_EVIDENCE_FROM empty holds nothing, and says so"
  else fail "adr-evidence: ADR_EVIDENCE_FROM empty did not pass with its notice:"; sed 's/^/       /' "$(scratch)/e.out"; fi
  mke known; adr 0010 Accepted '- Every reader is known: the classification.
- A hook blocks: S1a, **passed**.'
  printf 'ADR_EVIDENCE_KNOWN="0010:1"\n' >> "$F/.claude/project.conf"
  if erun && grep -q 'KNOWN ADR-0010: 1 Rests on item(s) cite no result: WAIVED by ADR_EVIDENCE_KNOWN, not passed; its addressee is docs/owner-queue.md' "$(scratch)/e.out"; then ok "adr-evidence: an uncited item waived in ADR_EVIDENCE_KNOWN passes, printed KNOWN, waived and addressed"
  else fail "adr-evidence: a waived uncited item did not pass with its KNOWN line:"; sed 's/^/       /' "$(scratch)/e.out"; fi
  adr 0010 Accepted '- Every reader is known: the classification.
- A hook blocks: by reading.'
  ebad "a known ADR whose uncited count rises" "0010-a-decision.md has 2 item(s) that cite no result; ADR_EVIDENCE_KNOWN acknowledges 1"
  adr 0010 Accepted '- A hook blocks: S1a, **passed**.'
  ebad "a known ADR whose uncited count falls (the entry goes stale)" "ADR_EVIDENCE_KNOWN acknowledges 1 uncited item(s) in ADR-0010, which has 0"
  mke known-pending; adr 0010 Accepted '- Polling is fast: **pending** (#9).'; printf 'ADR_EVIDENCE_KNOWN="0010:1"\n' >> "$F/.claude/project.conf"
  ebad "ADR_EVIDENCE_KNOWN never excuses a pending item" "Rests on item 1 is pending"
  mke nospikes; adr 0010 Accepted '- A hook blocks: S1a, **passed**.'; printf 'ADR_EVIDENCE_SPIKES="docs/plans/gone.md"\n' >> "$F/.claude/project.conf"
  ebad "an ADR_EVIDENCE_SPIKES file that does not exist" "ADR_EVIDENCE_SPIKES names docs/plans/gone.md, which does not exist"
fi

if [ -z "${ADR_EVIDENCE_FROM:-}" ]; then
  ok "ADR_EVIDENCE_FROM is empty: no ADR is held to its evidence (set it to the first ADR number to hold, PRAC-0023)"
  finish
fi
dir="$ROOT/$ADR_DIR"
[ -d "$dir" ] || { fail "ADR_DIR $ADR_DIR does not exist"; finish; }
[ "$(records_baseline_kind)" = bad ] && { fail "$(records_baseline_bad)"; finish; }
num() { printf '%s' "$1" | sed 's/^0*//; s/^$/0/'; }
from=$(num "$ADR_EVIDENCE_FROM")
queue=${OWNER_QUEUE:-docs/owner-queue.md}

# The spike ids: the first cell of each table row in the named files.
ids=""
for s in ${ADR_EVIDENCE_SPIKES:-}; do
  if [ -f "$ROOT/$s" ]; then
    ids="$ids $(sed -n -E 's/^\|[[:space:]]*([A-Z][A-Za-z]*[0-9]+[a-z]*)[[:space:]]*\|.*/\1/p' "$ROOT/$s" | tr '\n' ' ')"
  else fail "ADR_EVIDENCE_SPIKES names $s, which does not exist"; fi
done

# items FILE: the Rests on section, one line each: `i ITEM` (a column-0 `- ` line joined with its
# continuation lines, trailing blanks and CRs dropped) or `b WHY` (a line the check cannot read,
# so the ADR fails: closed, never a shorter list). Prose before the first item is not an item.
items() {
  awk 'function flush() { if (it != "") print "i " it; it = "" }
       { sub(/[[:space:]]+$/, "") }
       /^## Rests on$/ { p = 1; next }
       p && /^## / { flush(); p = 0 }
       !p { next }
       /^- / { flush(); it = substr($0, 3); seen = 1; gap = 0; next }
       /^[[:space:]]*([-*+]|[0-9]+[.)])([[:space:]]|$)/ {
         print "b line " NR " is a list line but not a column-0 `- ` item (write each assumption as a `- ` item): " $0; gap = 0; next }
       /^$/ { gap = 1; next }
       !seen { next }
       gap && /^[^[:space:]]/ {
         flush(); print "b line " NR " is text after a blank line that belongs to no item (continue an item on indented lines): " $0; gap = 0; next }
       it != "" { sub(/^[[:space:]]+/, ""); it = it " " $0 }
       END { flush() }' "$1"
}
# has ITEM ERE: 0 when ITEM matches the extended regular expression.
has() { printf '%s' "$1" | grep -qE -- "$2"; }
# The CITED form, in its position: after a colon, cites joined by `and` or `to`, then
# `, **passed**` and a full stop, ` (` or the item's end. A cite is a spike id from the tables
# (letters, digits, letters: safe in an ERE as written), a PR or a receipt's commit.
cite='#[0-9]+|receipt [0-9a-f]{7,40}'
for i in $ids; do cite="$cite|$i"; done
cited_form=":[[:space:]]+($cite)([[:space:]]+(and|to)[[:space:]]+($cite))*,[[:space:]]*\*\*passed\*\*(\.|[[:space:]]+\(|$)"
at_risk='— accepted at risk by the owner \(20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])\)'
negated="(not|never|n't|no longer)[[:space:]]+(yet[[:space:]]+)?accepted at risk"

held=0; known_seen=""
for f in $(ls "$dir" 2>/dev/null | grep -E '^[0-9]{4}-.*\.md$'); do
  n=$(printf '%s' "$f" | cut -c1-4)
  [ "$(num "$n")" -ge "$from" ] || continue
  record_is_legacy "$ADR_DIR" "$f" && continue
  # The Status line: `- **Status**: X`, `**Status:** X`, any case, the value bold or not.
  line=$(grep -i -m1 -E '^(- )?(\*\*)?status(\*\*)?:' "$dir/$f")
  if [ -z "$line" ]; then
    fail "$f has no readable Status line ('- **Status**: Proposed | Accepted | Superseded …'): a held ADR's Status is read, never skipped"; continue
  fi
  status=$(printf '%s' "$line" | sed -E 's/^(- )?(\*\*)?[Ss][Tt][Aa][Tt][Uu][Ss](\*\*)?:(\*\*)?[[:space:]]*//; s/^[*_[:space:]]+//')
  if [ "$(printf '%s' "$status" | grep -oiwE 'proposed|accepted|superseded' | tr 'A-Z' 'a-z' | sort -u | wc -l)" -gt 1 ]; then
    fail "$f has Status '$status', which names more than one of Proposed, Accepted and Superseded: a held ADR's Status is exactly one"; continue
  fi
  case "$(printf '%s' "$status" | sed -E 's/^([A-Za-z]*).*/\1/' | tr 'A-Z' 'a-z')" in
    accepted) ;;
    proposed|superseded) continue ;;
    *) fail "$f has Status '$status': a held ADR is Proposed, Accepted or Superseded"; continue ;;
  esac
  held=$((held + 1))
  if ! grep -qE '^## Rests on[[:space:]]*$' "$dir/$f"; then
    fail "$f is Accepted but has no '## Rests on' section: list each assumption with the result it rests on (PRAC-0023)"; continue
  fi
  list=$(items "$dir/$f")
  k=0; uncited=0; bad=0
  while IFS= read -r ln; do
    case $ln in
      "b "*) fail "$f, Rests on ${ln#b }"; bad=1; continue ;;
      "i "*) it=${ln#i } ;;
      *) continue ;;
    esac
    k=$((k + 1))
    risk=0; has "$it" "$at_risk" && risk=1
    word=$(printf '%s' "$it" | grep -oiE '\*\*(untested|pending)\*\*' | head -1 | tr -d '*' | tr 'A-Z' 'a-z')
    if printf '%s' "$it" | grep -qiE -- "$negated"; then
      fail "$f, Rests on item $k negates the owner's acceptance at risk: only the owner accepts it, as '— accepted at risk by the owner (YYYY-MM-DD)'"; bad=1
    elif [ -n "$word" ] && [ "$risk" -eq 0 ]; then
      fail "$f, Rests on item $k is $word (not yet evidence) and not accepted at risk by the owner as '— accepted at risk by the owner (YYYY-MM-DD)'"; bad=1
    elif [ "$risk" -eq 0 ] && ! has "$it" "$cited_form"; then
      uncited=$((uncited + 1)); eval "u_$k=1"
    fi
  done <<EOF
$list
EOF
  [ "$k" -gt 0 ] || { fail "$f is Accepted but its '## Rests on' lists no assumption ('- ' items)"; bad=1; }
  want=$(printf '%s\n' ${ADR_EVIDENCE_KNOWN:-} | sed -n "s/^$n:\([0-9][0-9]*\)$/\1/p" | head -1)
  if [ -n "$want" ]; then
    known_seen="$known_seen $n"
    if [ "$uncited" -gt "$want" ]; then
      fail "$f has $uncited item(s) that cite no result; ADR_EVIDENCE_KNOWN acknowledges $want: write '<assumption>: <spike id, #N or receipt <commit>>, **passed**.', or have the owner accept it at risk"
    elif [ "$uncited" -lt "$want" ]; then
      fail "ADR_EVIDENCE_KNOWN acknowledges $want uncited item(s) in ADR-$n, which has $uncited: lower the entry (or remove it at 0)"
    else
      echo "KNOWN ADR-$n: $uncited Rests on item(s) cite no result: WAIVED by ADR_EVIDENCE_KNOWN, not passed; its addressee is $queue (the owner cites each or accepts it at risk, then the entry goes)"
    fi
  elif [ "$uncited" -gt 0 ]; then
    j=0; while [ "$j" -lt "$k" ]; do j=$((j + 1)); eval "[ -n \"\${u_$j:-}\" ]" && fail "$f, Rests on item $j cites no result in the template's form: write '<assumption>: <spike id, #N or receipt <commit>>, **passed**.', or have the owner write '— accepted at risk by the owner (YYYY-MM-DD)'"; done
  elif [ "$bad" -eq 0 ]; then
    ok "$f rests on cited results ($k item(s))"
  fi
  j=0; while [ "$j" -lt "$k" ]; do j=$((j + 1)); unset "u_$j"; done
done
for e in ${ADR_EVIDENCE_KNOWN:-}; do
  case " $known_seen " in *" ${e%%:*} "*) ;; *) fail "ADR_EVIDENCE_KNOWN names $e, but ADR-${e%%:*} is not an Accepted ADR this check holds: remove the entry" ;; esac
done
[ "$_fails" -eq 0 ] && ok "every Accepted ADR from ADR-$ADR_EVIDENCE_FROM rests on evidence ($held held)"
finish
