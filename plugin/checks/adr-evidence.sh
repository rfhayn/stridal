#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# An ADR rests on evidence before it is accepted (PRAC-0023's practices 1 and 2). An ADR numbered
# ADR_EVIDENCE_FROM or later, written since RECORDS_BASELINE, is held: its Status line must read
# exactly one of Proposed, Accepted or Superseded (an unreadable Status, another word, or two of
# them, as in "Proposed → Accepted", fails: the check fails closed), and an Accepted one must have
# a `## Rests on` section, read by an ALLOW-LIST twice: only the line shapes below are read, and an
# item passes only when the WHOLE item, from its first character to its last, is one of two forms.
#
# LINES. In the section a line is one of: a column-0 `- ` (an item starts); a line indented two
# spaces or a tab that continues the current item and is not itself a list marker, a quote (`>`),
# a fence (``` or ~~~), a table row (`|`), HTML (`<`) or a heading; a blank line; or, before the
# first item, column-0 prose (not an item). Any other line fails by its line number, and a fenced
# block fails as a whole: its lines are never read as items.
#
# ITEMS, each its lines joined by a space (trailing blanks and CRs dropped):
#   - CITED: `<assumption>: <cites>, **passed**`, then nothing, `.`, or ` (<detail>)` and an
#     optional `.`. The assumption holds no sentence end (`.`, `;`, `!` or `?` before a space;
#     `e.g.` and `i.e.` excepted), no `: ` outside a code span and no `<!`. The cites are joined by
#     ` and ` or ` to `; each is a spike id from a table in an ADR_EVIDENCE_SPIKES file (a row whose
#     first cell is the id, `| S1a |`), a PR `#N` (N from 1: a PR number cannot be checked offline,
#     so only its form is read) or `receipt <commit>` (7 to 40 hex digits), which must name a commit
#     in the git repository the check runs in (`git cat-file -e`; outside a git checkout it fails,
#     naming why). <detail> points at the result and never qualifies it: `as recorded above`,
#     `as recorded below`, or one of both/all/each/every and then run(s) or case(s).
#   - AT RISK (PRAC-0023's exception: the owner accepts it with the assumption named):
#     `<assumption>: …` holding a bold **…untested…** or **…pending…**, then `— accepted at risk by
#     the owner (YYYY-MM-DD)` with a date that exists, then nothing, `.`, or `; tested by <ROW-N>`
#     and after that nothing, `.`, ` (<text>)` and an optional `.`, or `, <text>`. The item names
#     **passed** nowhere (it re-asserts no evidence), reads `accepted at risk` once, holds no `<!`.
# A negation ("not accepted at risk") fails. An item marked **untested** or **pending** that is not
# AT RISK fails. Proposed and Superseded ADRs are not judged: drafting one with untested items is
# the point of the section. Practice records are not judged either. ADR_EVIDENCE_FROM empty:
# nothing is held.
#
# ADR_EVIDENCE_KNOWN lists Accepted ADRs found with items that cite nothing, as NNNN:COUNT, so
# the check can land on a history that predates it: each is printed on every run as KNOWN (waived,
# not passed, with OWNER_QUEUE as its addressee: the entry's owner-queue item closes it), an ADR
# whose count rises fails, and one whose count falls fails until the entry is lowered. Only "cites
# nothing" is waived this way; a missing section, an untested or pending item not at risk, a
# negated acceptance, a date that does not exist, a receipt that names no commit, an unreadable
# line and an unreadable Status always fail. Falsified on fixtures below.
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
  # mkg NAME: mke, and the fixture is a git repository with one commit, $sha (for receipts).
  mkg() { mke "$1"; new_repo "$F"; git -C "$F" commit -q --allow-empty -m fixture; sha=$(git -C "$F" rev-parse --short=8 HEAD); }
  # The ceiling keeps a fixture that is no repository from finding one above the scratch dir.
  erun() { (ROOT="$F" ADR_EVIDENCE_SELFTEST=1 GIT_CEILING_DIRECTORIES="$(scratch)" sh "$F/.claude/checks/adr-evidence.sh") > "$(scratch)/e.out" 2>&1; }
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
  ebad "a column-0 paragraph after the items" "Rests on line 12 is a column-0 line after the items begin"
  # Round 2's probes: the at-risk date is a date; only the bold markers mean untested or pending.
  notdate="Rests on item 1 dates its acceptance at risk"
  mke baddate; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2026-99-99).'
  ebad "an acceptance at risk dated 2026-99-99" "$notdate 2026-99-99, a date that does not exist"
  mke notadate; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (0000-00-00).'
  ebad "an acceptance at risk dated 0000-00-00" "$notdate 0000-00-00, a date that does not exist"
  # Round 3's probes: the WHOLE item is the form; text before or after it is not read past.
  mke eg; adr 0010 Accepted '- The hook (e.g. pr-merge-guard) blocks: S1a, **passed**.
- One reader (i.e. the gate) reads it: S2, **passed**.'
  eok "an assumption with 'e.g.' and 'i.e.' in it"
  mke two-sent; adr 0010 Accepted '- X: unverified. Y: S1a, **passed**.'
  ebad "'X: unverified. Y: S1a, **passed**.'" "$uncited"
  mke two-semi; adr 0010 Accepted '- Y: unverified; X: S1a, **passed**.'
  ebad "'Y: unverified; X: S1a, **passed**.'" "$uncited"
  mke two-comma; adr 0010 Accepted '- X: unverified, Y: S1a, **passed**.'
  ebad "'X: unverified, Y: S1a, **passed**.' (a second ': ' outside a code span)" "$uncited"
  mke code-colon; adr 0010 Accepted '- A hook blocks only with `onFailure: "block"`: S1a, **passed**.'
  eok "a ': ' inside a code span in the assumption"
  mke after-sent; adr 0010 Accepted '- X: S1a, **passed**. Not really.'
  ebad "'X: S1a, **passed**. Not really.'" "$uncited"
  mke after-linux; adr 0010 Accepted '- X: S1a, **passed**. It did not pass on Linux.'
  ebad "'X: S1a, **passed**. It did not pass on Linux.'" "$uncited"
  mke after-paren; adr 0010 Accepted '- X: S1a, **passed** (but Y is unverified).'
  ebad "'X: S1a, **passed** (but Y is unverified).' (a detail that qualifies the result)" "$uncited"
  mke after-comment; adr 0010 Accepted '- X: S1a, **passed**. <!-- Y: unverified -->'
  ebad "'X: S1a, **passed**. <!-- Y: unverified -->'" "$uncited"
  mke after-indent; adr 0010 Accepted '- X: S1a, **passed**.
  Not really.'
  ebad "an indented sentence continuing a cited item" "$uncited"
  mke after-blank; adr 0010 Accepted '- X: S1a, **passed**.

Not really.'
  ebad "a column-0 line after a blank line under a cited item" "Rests on line 12 is a column-0 line after the items begin"
  mke after-col0; adr 0010 Accepted '- X: S1a, **passed**.
Not really.'
  ebad "a column-0 line directly under a cited item" "Rests on line 11 is a column-0 line after the items begin"
  mke pr-zero; adr 0010 Accepted '- X: #0, **passed**.'
  ebad "a PR '#0'" "$uncited"
  # Round 3's probes: only the line shapes the section allows are read; every other line fails.
  mke quote-after; adr 0010 Accepted '- X: S1a, **passed**.
> - Y: nothing.'
  ebad "a quoted item after a cited one" "Rests on line 11 is a quote"
  mke quote-before; adr 0010 Accepted '> - Y: nothing.
- X: S1a, **passed**.'
  ebad "a quoted item before the first item" "Rests on line 10 is a quote"
  mke fence; adr 0010 Accepted '```
- X: S1a, **passed**.
```'
  ebad "a fenced '- X: S1a, **passed**.'" "Rests on line 10 opens a fenced block"
  mke fence-tilde; adr 0010 Accepted '- X: S1a, **passed**.
  ~~~
  - Y: S1a, **passed**.
  ~~~'
  ebad "an indented ~~~ fence under a cited item" "Rests on line 11 opens a fenced block"
  mke table; adr 0010 Accepted '- X: S1a, **passed**.
| Y | nothing |'
  ebad "a table row after a cited item" "Rests on line 11 is a table row"
  mke html; adr 0010 Accepted '- X: S1a, **passed**.
<!-- - Y: nothing. -->'
  ebad "an HTML comment line after a cited item" "Rests on line 11 is HTML"
  mke html-indent; adr 0010 Accepted '- X: S1a, **passed**.
  <!-- Y: nothing. -->'
  ebad "an indented HTML comment continuing a cited item" "Rests on line 11 is HTML"
  # Round 3's probes: the at-risk date exists, and the item is the at-risk form as a whole.
  mke feb31; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2099-02-31).'
  ebad "an acceptance at risk dated 2099-02-31" "$notdate 2099-02-31, a date that does not exist"
  mke feb29-2027; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2027-02-29).'
  ebad "an acceptance at risk dated 2027-02-29 (no leap year)" "$notdate 2027-02-29, a date that does not exist"
  mke feb29-2028; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2028-02-29).'
  eok "an acceptance at risk dated 2028-02-29 (a leap year)"
  mke risk-passed; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2026-10-31); tested by OPS-9, and Y: S1a, **passed**.'
  ebad "an at-risk item that re-asserts **passed**" "Rests on item 1 is untested"
  mke risk-tail; adr 0010 Accepted '- X: **untested** — accepted at risk by the owner (2026-10-31). Y: nothing.'
  ebad "text after the at-risk date that is not '; tested by <row>'" "Rests on item 1 is untested"
  mke risk-shapes; adr 0010 Accepted '- A: **untested** — accepted at risk by the owner (2026-10-31).
- B: documented, **untested** — accepted at risk by the owner (2026-10-31); tested by OPS-9 (Gate A, on the Mac).
- C: S3b showed it. **The parser is untested** — accepted at risk by the owner (2026-10-31); tested by OPS-9, which builds it. A port past 5 rounds is re-estimated.'
  eok "the at-risk shapes ADR-0016 to ADR-0020 write"
  # Round 3's probes: a receipt names a commit in the repository the check runs in.
  mkg receipt-unknown; adr 0010 Accepted '- The gate ran: receipt deadbee, **passed**.'
  ebad "a receipt 'deadbee' that names no commit" "Rests on item 1 names receipt deadbee, which is no commit in this repository"
  mkg receipt-word; adr 0010 Accepted '- The gate ran: receipt acceded, **passed**.'
  ebad "a receipt 'acceded' (a hex word)" "Rests on item 1 names receipt acceded, which is no commit in this repository"
  mke receipt-nogit; adr 0010 Accepted '- The gate ran: receipt 75c86686, **passed**.'
  ebad "a receipt where the check runs outside a git checkout" "Rests on item 1 names receipt 75c86686, which cannot be resolved: $F is not a git checkout"
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
  mkg cited; adr 0010 Accepted 'These are the assumptions (PRAC-0023).

- A hook blocks: S1a to S1e, **passed**.
- A server starts: S2, **passed**.
- A hang ends: S1a and S1e, **passed** (both runs).
- Gate semantics: S2, **passed** (as recorded above).
- The port measured it: #371, **passed**.
- The gate ran: receipt '"$sha"', **passed**.'
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
# continuation lines, trailing blanks and CRs dropped) or `b WHY` (a line whose shape the section
# does not allow, so the ADR fails: closed, never a shorter list). The allow-list is the rules
# that end in `next` without calling bad(); every line that reaches none of them is bad.
items() {
  awk 'function flush() { if (it != "") print "i " it; it = "" }
       function bad(why) { flush(); print "b line " NR " " why ": " $0 }
       { sub(/[[:space:]]+$/, "") }
       fence { if ($0 ~ /^[[:space:]]*(```|~~~)/) fence = 0; next }
       /^## Rests on$/ { p = 1; next }
       p && /^## / { flush(); p = 0 }
       !p { next }
       /^[[:space:]]*(```|~~~)/ { bad("opens a fenced block, which a Rests on section does not hold (none of its lines is read as an item)"); fence = 1; next }
       /^$/ { next }
       /^- / { flush(); it = substr($0, 3); seen = 1; next }
       { s = $0; sub(/^[[:space:]]+/, "", s) }
       s ~ /^([-*+]|[0-9]+[.)])([[:space:]]|$)/ { bad("is a list line but not a column-0 `- ` item (write each assumption as a `- ` item)"); next }
       s ~ /^>/ { bad("is a quote, which a Rests on section does not hold"); next }
       s ~ /^\|/ { bad("is a table row, which a Rests on section does not hold"); next }
       s ~ /^</ { bad("is HTML, which a Rests on section does not hold"); next }
       s ~ /^#+([[:space:]]|$)/ { bad("is a heading inside the Rests on section"); next }
       /^(  |\t)/ && it != "" { it = it " " s; next }
       /^[[:space:]]/ { bad("is indented but continues no item (an item starts with a column-0 `- `)"); next }
       seen { bad("is a column-0 line after the items begin (continue an item on lines indented two spaces, or start one with `- `)"); next }
       /^[[A-Za-z0-9_*(`]/ { next }
       { bad("is neither prose before the first item nor an item") }
       END { flush() }' "$1"
}
# has ITEM ERE: 0 when ITEM matches the extended regular expression.
has() { printf '%s' "$1" | grep -qE -- "$2"; }
# The CITED form, the whole item (the header gives it in words). The assumption: no sentence end,
# no `: ` outside a code span, no `<!` (a punctuation mark's partner is never `<` or a backtick, so
# neither slips past as one). A cite is a spike id from the tables (letters, digits, letters: safe
# in an ERE as written), a PR from #1, or a receipt's commit. The detail is a closed list.
pre='([^.;!?:`<]|[.;!?:][^[:space:]<`]|<[^!]|`[^`]*`|e\.g\.|i\.e\.)*'
cite='#[1-9][0-9]*|receipt [0-9a-f]{7,40}'
for i in $ids; do cite="$cite|$i"; done
detail='as recorded (above|below)|(both|all|each|every) (runs?|cases?)'
cited_form="^$pre:[[:space:]]+($cite)([[:space:]]+(and|to)[[:space:]]+($cite))*,[[:space:]]*\*\*passed\*\*(\.?|[[:space:]]+\(($detail)\)\.?)\$"
# The AT RISK form, the whole item, as ADR-0016 to ADR-0020 write it; `**passed**`, a second
# `accepted at risk` and `<!` are refused beside it. The date is read by real_date.
row='[A-Z][A-Z0-9]*-[0-9]+'
at_risk_form="^.*:[[:space:]].*\*\*[^*]*([Uu]ntested|[Pp]ending)[^*]*\*\*.* — accepted at risk by the owner \([0-9]{4}-[0-9]{2}-[0-9]{2}\)(\.?|;[[:space:]]+tested by $row(\.?|[[:space:]]+\([^()]*\)\.?|,[[:space:]].*))\$"
negated="(not|never|n't|no longer)[[:space:]]+(yet[[:space:]]+)?accepted at risk"
at_risk() {  # at_risk ITEM: 0 when the whole ITEM is the AT RISK form
  has "$1" "$at_risk_form" && ! has "$1" '\*\*passed\*\*|<!' &&
    [ "$(printf '%s' "$1" | grep -o 'accepted at risk' | wc -l)" -eq 1 ]
}
# real_date YYYY-MM-DD: 0 when the day exists in its month, leap years counted (awk: portable).
real_date() {
  printf '%s\n' "$1" | awk -F- '{ y = $1 + 0; m = $2 + 0; d = $3 + 0
    split("31 28 31 30 31 30 31 31 30 31 30 31", L, " ")
    if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) L[2] = 29
    exit !(y >= 1 && m >= 1 && m <= 12 && d >= 1 && d <= L[m]) }'
}
# receipts ITEM: for a CITED item, why its first `receipt <commit>` cite names no commit in the
# repository the check runs in; nothing when every receipt does. Only the cites are read: the
# text between the item's last `: ` and its `, **passed**`.
receipts() {
  for h in $(printf '%s' "$1" | sed -E 's/.*:[[:space:]]+(.*),[[:space:]]*\*\*passed\*\*.*$/\1/' | grep -oE 'receipt [0-9a-f]{7,40}' | sed 's/^receipt //'); do
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "names receipt $h, which cannot be resolved: $ROOT is not a git checkout"; return; }
    git -C "$ROOT" cat-file -e "$h^{commit}" 2>/dev/null || { echo "names receipt $h, which is no commit in this repository"; return; }
  done
}
form="'<assumption>: <spike id, #N or receipt <commit>>, **passed**.', the whole item"

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
    word=$(printf '%s' "$it" | grep -oiE '\*\*(untested|pending)\*\*' | head -1 | tr -d '*' | tr 'A-Z' 'a-z')
    if printf '%s' "$it" | grep -qiE -- "$negated"; then
      fail "$f, Rests on item $k negates the owner's acceptance at risk: only the owner accepts it, as '— accepted at risk by the owner (YYYY-MM-DD)'"; bad=1
    elif at_risk "$it"; then
      d=$(printf '%s' "$it" | sed -E 's/.* — accepted at risk by the owner \(([0-9-]{10})\).*/\1/')
      real_date "$d" || { fail "$f, Rests on item $k dates its acceptance at risk $d, a date that does not exist"; bad=1; }
    elif [ -n "$word" ]; then
      fail "$f, Rests on item $k is $word (not yet evidence) and not accepted at risk by the owner: the whole item reads '<assumption>: **$word** — accepted at risk by the owner (YYYY-MM-DD)', then nothing or '; tested by <row>'"; bad=1
    elif has "$it" "$cited_form"; then
      why=$(receipts "$it")
      [ -z "$why" ] || { fail "$f, Rests on item $k $why: a receipt is the commit a gate receipt names"; bad=1; }
    else
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
      fail "$f has $uncited item(s) that cite no result; ADR_EVIDENCE_KNOWN acknowledges $want: write $form, or have the owner accept it at risk"
    elif [ "$uncited" -lt "$want" ]; then
      fail "ADR_EVIDENCE_KNOWN acknowledges $want uncited item(s) in ADR-$n, which has $uncited: lower the entry (or remove it at 0)"
    else
      echo "KNOWN ADR-$n: $uncited Rests on item(s) cite no result: WAIVED by ADR_EVIDENCE_KNOWN, not passed; its addressee is $queue (the owner cites each or accepts it at risk, then the entry goes)"
    fi
  elif [ "$uncited" -gt 0 ]; then
    j=0; while [ "$j" -lt "$k" ]; do j=$((j + 1)); eval "[ -n \"\${u_$j:-}\" ]" && fail "$f, Rests on item $j cites no result in the template's form: write $form (ending '.' or ' (as recorded above).'), or have the owner write '— accepted at risk by the owner (YYYY-MM-DD)'"; done
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
