#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# An ADR rests on evidence before it is accepted (PRAC-0023's practices 1 and 2). An ADR numbered
# ADR_EVIDENCE_FROM or later, written since RECORDS_BASELINE, is held: its Status line must read
# Proposed, Accepted or Superseded (an unreadable or other Status fails: the check fails closed),
# and an Accepted one must have a `## Rests on` section whose every item (a top-level `- ` bullet
# and its continuation lines) has one of two shapes, and nothing else passes:
#   - CITED: it carries **passed** and a result: a spike id from a table in an ADR_EVIDENCE_SPIKES
#     file (a row whose first cell is the id, such as `| S1a |`), a PR (`#371`), or a gate receipt
#     named by its commit (`receipt 75c86686`, 7 to 40 hex digits);
#   - AT RISK: it reads `— accepted at risk by the owner (YYYY-MM-DD)` (PRAC-0023's exception: the
#     owner accepts it with the assumption named). Any negation ("not accepted at risk") fails.
# An item marked **untested** or **pending** (both mean: not yet evidence) fails unless it is AT
# RISK. Proposed and Superseded ADRs are not judged: drafting one with untested items is the point
# of the section. Practice records are not judged either. ADR_EVIDENCE_FROM empty: nothing is held.
#
# ADR_EVIDENCE_KNOWN lists Accepted ADRs found with items that cite nothing, as NNNN:COUNT, so
# the check can land on a history that predates it: each is printed on every run as KNOWN (waived,
# not passed, with OWNER_QUEUE as its addressee: the entry's owner-queue item closes it), an ADR
# whose count rises fails, and one whose count falls fails until the entry is lowered. Only "cites
# nothing" is waived this way; a missing section, an untested or pending item not at risk, a
# negated acceptance and an unreadable Status always fail. Falsified on fixtures below.
. "$(dirname "$0")/lib.sh"
. "$STRIDAL_FW/lib/records.sh"

# ── Self-test ─────────────────────────────────────────────────────────────────────────────────────
if [ -z "${ADR_EVIDENCE_SELFTEST:-}" ]; then
  mke() {  # mke NAME: a fixture project with one spike table, held from ADR 0010
    F="$(scratch)/ev-$1"; A="$F/docs/adr"; mkdir -p "$F/.claude/checks" "$A" "$F/docs/plans"
    cp -R "$STRIDAL_FW/lib" "$F/.claude/"; cp "$STRIDAL_FW/checks/lib.sh" "$STRIDAL_FW/checks/adr-evidence.sh" "$F/.claude/checks/"
    printf '# Spikes\n\n| Id | Probe | Result |\n|---|---|---|\n| S1a | a hook | blocked |\n| S2 | a server | works |\n' > "$F/docs/plans/spikes.md"
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
  mke cited; adr 0010 Accepted 'These are the assumptions (PRAC-0023).
- A hook blocks: S1a to S1e, **passed**.
- A server starts: S2, **passed**.
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

# items FILE: the Rests on section's items, one per line (a `- ` bullet joined with its
# continuation lines); prose before the first bullet is not an item.
items() {
  awk '/^## Rests on[[:space:]]*$/ { p = 1; next }
       p && /^## / { p = 0 }
       !p { next }
       /^- / { if (it != "") print it; it = substr($0, 3); next }
       /^[[:space:]]*$/ { next }
       it != "" { sub(/^[[:space:]]+/, ""); it = it " " $0 }
       END { if (it != "") print it }' "$1"
}
# has ITEM ERE: 0 when ITEM matches the extended regular expression.
has() { printf '%s' "$1" | grep -qE -- "$2"; }
# cited ITEM: 0 only for the CITED shape: **passed** and a spike id, a PR or a receipt's commit.
cited() {
  has "$1" '\*\*passed\*\*' || return 1
  for i in $ids; do printf '%s' "$1" | grep -qw -- "$i" && return 0; done
  has "$1" '#[0-9]+' || has "$1" '(^|[^[:alnum:]])receipt (for |of )?[0-9a-f]{7,40}([^[:alnum:]]|$)'
}
at_risk='— accepted at risk by the owner \([0-9]{4}-[0-9]{2}-[0-9]{2}\)'
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
  [ -n "$list" ] || { fail "$f is Accepted but its '## Rests on' lists no assumption ('- ' items)"; continue; }
  k=0; uncited=0; bad=0
  while IFS= read -r it; do
    k=$((k + 1))
    risk=0; has "$it" "$at_risk" && risk=1
    word=$(printf '%s' "$it" | grep -oiwE 'untested|pending' | head -1 | tr 'A-Z' 'a-z')
    if printf '%s' "$it" | grep -qiE -- "$negated"; then
      fail "$f, Rests on item $k negates the owner's acceptance at risk: only the owner accepts it, as '— accepted at risk by the owner (YYYY-MM-DD)'"; bad=1
    elif [ -n "$word" ] && [ "$risk" -eq 0 ]; then
      fail "$f, Rests on item $k is $word (not yet evidence) and not accepted at risk by the owner as '— accepted at risk by the owner (YYYY-MM-DD)'"; bad=1
    elif [ "$risk" -eq 0 ] && ! cited "$it"; then
      uncited=$((uncited + 1)); eval "u_$k=1"
    fi
  done <<EOF
$list
EOF
  want=$(printf '%s\n' ${ADR_EVIDENCE_KNOWN:-} | sed -n "s/^$n:\([0-9][0-9]*\)$/\1/p" | head -1)
  if [ -n "$want" ]; then
    known_seen="$known_seen $n"
    if [ "$uncited" -gt "$want" ]; then
      fail "$f has $uncited item(s) that cite no result; ADR_EVIDENCE_KNOWN acknowledges $want: cite a spike, a PR or a receipt with **passed**, or have the owner accept it at risk"
    elif [ "$uncited" -lt "$want" ]; then
      fail "ADR_EVIDENCE_KNOWN acknowledges $want uncited item(s) in ADR-$n, which has $uncited: lower the entry (or remove it at 0)"
    else
      echo "KNOWN ADR-$n: $uncited Rests on item(s) cite no result: WAIVED by ADR_EVIDENCE_KNOWN, not passed; its addressee is $queue (the owner cites each or accepts it at risk, then the entry goes)"
    fi
  elif [ "$uncited" -gt 0 ]; then
    j=0; while [ "$j" -lt "$k" ]; do j=$((j + 1)); eval "[ -n \"\${u_$j:-}\" ]" && fail "$f, Rests on item $j cites no result: write **passed** with a spike id, a PR (#N) or a receipt (receipt <commit>), or have the owner write '— accepted at risk by the owner (YYYY-MM-DD)'"; done
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
