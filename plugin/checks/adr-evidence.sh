#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# An ADR rests on evidence before it is accepted (PRAC-0023's practices 1 and 2). An ADR numbered
# ADR_EVIDENCE_FROM or later, written since RECORDS_BASELINE, whose Status is Accepted must have a
# `## Rests on` section whose every item (a top-level `- ` bullet and its continuation lines):
#   - cites a result: a spike id from a table in an ADR_EVIDENCE_SPIKES file (a row whose first
#     cell is the id, such as `| S1a |`), a PR (`#371`) or a receipt; or reads "accepted at risk by
#     the owner" (PRAC-0023's exception: the owner accepts it with the assumption named);
#   - and is not marked pending, nor untested without "accepted at risk by the owner".
# Proposed and Superseded ADRs are not judged: drafting one with untested items is the point of
# the section. Practice records are not judged either. ADR_EVIDENCE_FROM empty: nothing is held.
#
# ADR_EVIDENCE_KNOWN lists Accepted ADRs found with items that cite nothing, as NNNN:COUNT, so
# the check can land on a history that predates it: each is printed on every run as KNOWN, an ADR
# whose count rises fails, and one whose count falls fails until the entry is lowered. Only "cites
# nothing" is acknowledged this way; a missing section, a pending item and an untested item
# without the owner's acceptance always fail. Falsified on fixtures below.
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
  erun() { (ROOT="$F" ADR_EVIDENCE_SELFTEST=1 sh "$F/.claude/checks/adr-evidence.sh") > "$(scratch)/e.out" 2>&1; }
  eok() { if erun; then ok "adr-evidence: $1 passes"; else fail "adr-evidence: $1 FAILED:"; grep '^FAIL' "$(scratch)/e.out" | sed 's/^/       /'; fi; }
  ebad() {
    if erun; then fail "adr-evidence: $1 passed"
    elif grep '^FAIL' "$(scratch)/e.out" | grep -qF -- "$2"; then ok "adr-evidence: $1 fails ($2)"
    else fail "adr-evidence: $1 fails, but not for '$2':"; grep '^FAIL' "$(scratch)/e.out" | sed 's/^/       /'; fi
  }

  mke none; adr 0010 Accepted
  ebad "an Accepted ADR with no Rests on section" "0010-a-decision.md is Accepted but has no '## Rests on' section"
  mke pending; adr 0010 'Accepted (the owner, 2026-10-31)' '- A hook blocks: S1a, **passed**.
- The server starts in time: **pending**, its PR #9 open.'
  ebad "an Accepted ADR with a pending assumption" "0010-a-decision.md, Rests on item 2 is marked pending"
  mke empty; adr 0010 Accepted 'Nothing is assumed.'
  ebad "an Accepted ADR whose Rests on lists no item" "0010-a-decision.md is Accepted but its '## Rests on' lists no assumption"
  mke untested; adr 0010 Accepted '- A lane reaches the tools: **untested**; tested by OPS-9.'
  ebad "an untested assumption the owner did not accept at risk" "0010-a-decision.md, Rests on item 1 is untested and not accepted at risk by the owner"
  mke uncited; adr 0010 Accepted '- Every reader is known: the classification, section E.'
  ebad "an assumption that cites no result" "0010-a-decision.md, Rests on item 1 cites no result"
  mke unknown-id; adr 0010 Accepted '- A hook blocks: S9z, **passed**.'
  ebad "a spike id no spike table holds" "0010-a-decision.md, Rests on item 1 cites no result"
  mke cited; adr 0010 Accepted 'These are the assumptions (PRAC-0023).
- A hook blocks: S1a to S1e, **passed**.
- A server starts: S2, **passed**.
- The port measured it: #371.
- The gate ran: its receipt, 2026-10-31.'
  eok "an Accepted ADR whose every assumption cites a spike, a PR or a receipt"
  mke at-risk; adr 0010 Accepted '- A hook blocks: S1a, **passed**.
- Hooks write outside the sandbox: **untested** — accepted at risk by the owner
  (2026-10-31); tested by OPS-9.'
  eok "an Accepted ADR with an untested item accepted at risk by the owner"
  mke proposed; adr 0010 'Proposed. The owner decides at Gate C.' '- A hook appends: **untested**. Gate A.
- Polling is fast: **pending**.'
  eok "a Proposed ADR with untested and pending items (not judged)"
  mke superseded; adr 0010 'Superseded by ADR-0011'; eok "a Superseded ADR with no section (not judged)"
  mke off; adr 0010 Accepted; printf 'ADR_EVIDENCE_FROM=""\n' > "$F/.claude/project.conf"
  if erun && grep -q 'ADR_EVIDENCE_FROM is empty' "$(scratch)/e.out"; then ok "adr-evidence: ADR_EVIDENCE_FROM empty holds nothing, and says so"
  else fail "adr-evidence: ADR_EVIDENCE_FROM empty did not pass with its notice:"; sed 's/^/       /' "$(scratch)/e.out"; fi
  mke known; adr 0010 Accepted '- Every reader is known: the classification.
- A hook blocks: S1a.'
  printf 'ADR_EVIDENCE_KNOWN="0010:1"\n' >> "$F/.claude/project.conf"
  if erun && grep -q 'KNOWN ADR-0010' "$(scratch)/e.out"; then ok "adr-evidence: an uncited item acknowledged in ADR_EVIDENCE_KNOWN passes, printed KNOWN"
  else fail "adr-evidence: an acknowledged uncited item did not pass with its KNOWN line:"; sed 's/^/       /' "$(scratch)/e.out"; fi
  adr 0010 Accepted '- Every reader is known: the classification.
- A hook blocks: by reading.'
  ebad "a known ADR whose uncited count rises" "0010-a-decision.md has 2 item(s) that cite no result; ADR_EVIDENCE_KNOWN acknowledges 1"
  adr 0010 Accepted '- A hook blocks: S1a.'
  ebad "a known ADR whose uncited count falls (the entry goes stale)" "ADR_EVIDENCE_KNOWN acknowledges 1 uncited item(s) in ADR-0010, which has 0"
  mke known-pending; adr 0010 Accepted '- Polling is fast: **pending** (#9).'; printf 'ADR_EVIDENCE_KNOWN="0010:1"\n' >> "$F/.claude/project.conf"
  ebad "ADR_EVIDENCE_KNOWN never excuses a pending item" "Rests on item 1 is marked pending"
  mke nospikes; adr 0010 Accepted '- A hook blocks: S1a.'; printf 'ADR_EVIDENCE_SPIKES="docs/plans/gone.md"\n' >> "$F/.claude/project.conf"
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
# cites ITEM: 0 when ITEM names a spike id, a PR or a receipt.
cites() {
  for i in $ids; do printf '%s' "$1" | grep -qw -- "$i" && return 0; done
  printf '%s' "$1" | grep -qE '#[0-9]+|[Rr]eceipt'
}

held=0; known_seen=""
for f in $(ls "$dir" 2>/dev/null | grep -E '^[0-9]{4}-.*\.md$'); do
  n=$(printf '%s' "$f" | cut -c1-4)
  [ "$(num "$n")" -ge "$from" ] || continue
  record_is_legacy "$ADR_DIR" "$f" && continue
  status=$(sed -n -E 's/^- \*\*Status(\*\*:|:\*\*)[[:space:]]*//p' "$dir/$f" | head -1)
  case "$status" in Accepted*) ;; *) continue ;; esac
  held=$((held + 1))
  if ! grep -qE '^## Rests on[[:space:]]*$' "$dir/$f"; then
    fail "$f is Accepted but has no '## Rests on' section: list each assumption with the result it rests on (PRAC-0023)"; continue
  fi
  list=$(items "$dir/$f")
  [ -n "$list" ] || { fail "$f is Accepted but its '## Rests on' lists no assumption ('- ' items)"; continue; }
  k=0; uncited=0; bad=0
  while IFS= read -r it; do
    k=$((k + 1))
    risk=0; printf '%s' "$it" | grep -qi 'accepted at risk by the owner' && risk=1
    if printf '%s' "$it" | grep -qiw 'pending'; then
      fail "$f, Rests on item $k is marked pending: an Accepted ADR rests on results, not on work still to run"; bad=1
    elif printf '%s' "$it" | grep -qiw 'untested' && [ "$risk" -eq 0 ]; then
      fail "$f, Rests on item $k is untested and not accepted at risk by the owner"; bad=1
    elif [ "$risk" -eq 0 ] && ! cites "$it"; then
      uncited=$((uncited + 1)); eval "u_$k=1"
    fi
  done <<EOF
$list
EOF
  want=$(printf '%s\n' ${ADR_EVIDENCE_KNOWN:-} | sed -n "s/^$n:\([0-9][0-9]*\)$/\1/p" | head -1)
  if [ -n "$want" ]; then
    known_seen="$known_seen $n"
    if [ "$uncited" -gt "$want" ]; then
      fail "$f has $uncited item(s) that cite no result; ADR_EVIDENCE_KNOWN acknowledges $want: cite a spike, a PR or a receipt, or have the owner accept it at risk"
    elif [ "$uncited" -lt "$want" ]; then
      fail "ADR_EVIDENCE_KNOWN acknowledges $want uncited item(s) in ADR-$n, which has $uncited: lower the entry (or remove it at 0)"
    else
      echo "KNOWN ADR-$n: $uncited Rests on item(s) cite no result (ADR_EVIDENCE_KNOWN); the owner cites each or accepts it at risk"
    fi
  elif [ "$uncited" -gt 0 ]; then
    j=0; while [ "$j" -lt "$k" ]; do j=$((j + 1)); eval "[ -n \"\${u_$j:-}\" ]" && fail "$f, Rests on item $j cites no result: name a spike id, a PR (#N) or a receipt, or 'accepted at risk by the owner'"; done
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
