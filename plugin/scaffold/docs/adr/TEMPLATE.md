# ADR NNNN: <Title>

- **Status**: Proposed | Accepted | Superseded by ADR-NNNN
- **Date**: YYYY-MM-DD
- **Tags**: <area>, <area>
- **Source**: <insights-log row / PR # / discussion>

## Context
The forces at play and the problem being solved. What made this a decision rather than an obvious
call?

## Decision
What we decided, in active voice. Specific enough that someone could act on it without
re-deriving it.

## Consequences
### Positive
- …

### Negative / trade-offs
- …

## Enforcement
What keeps this true over time: a hook, a check, a review step, a constraint. If nothing enforces
it, say so plainly; that is a finding, not a formality.

## Rests on
Each assumption the decision needs to be true (a platform behaviour, an implementation elsewhere,
the reason behind an earlier record, an estimate), one column-0 `- ` item each, wrapped on lines
indented two spaces. No other line belongs here once the items begin (no quote, fence, table,
HTML or nested list), and the WHOLE item is one of the forms below, with nothing before or after
it (PRAC-0023; `${CLAUDE_PLUGIN_ROOT}/checks/adr-evidence.sh` holds it from `ADR_EVIDENCE_FROM`).
A tested one is `<assumption>: <cites>, **passed**.` The assumption has no sentence end inside it
(`e.g.` and `i.e.` aside) and no `: ` outside a code span. The cites, right after its colon, are
spike ids from the project's spike table (`ADR_EVIDENCE_SPIKES`), PRs (`#N`) or `receipt <commit>`
(a commit in this repository), joined by ` and ` or ` to ` (`S1a to S1e`). It may end
` (as recorded above).` or ` (as recorded below).`, or name the runs: ` (both runs).` (both, all,
each or every, then run(s) or case(s)); no other text follows **passed**.
One not yet tested says **untested** and names the row that will test it. An ADR is Accepted only
when no item is untested: each cites its result, or the owner accepts it at risk, as
`<assumption>: **untested** — accepted at risk by the owner (YYYY-MM-DD); tested by <row>.`, a
date that exists; after the row, nothing, ` (<note>).` or `, <clause>`, and never **passed**.
- <assumption>: <spike id, #PR or receipt <commit>>, **passed**.
- <assumption>: **untested**; tested by <row>.

## Related
- ADR-NNNN, a change in `changes/`, a spec, an insights-log row
