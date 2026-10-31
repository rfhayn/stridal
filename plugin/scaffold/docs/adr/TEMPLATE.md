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
the reason behind an earlier record, an estimate), one column-0 `- ` item each (wrap it on
indented lines), in one of the two forms below. A tested one names, right after its colon, the
result it rests on: a spike id from the project's spike table (`ADR_EVIDENCE_SPIKES`), a PR (`#N`)
or `receipt <commit>`, several joined by ` and ` or ` to ` (`S1a to S1e`), then `, **passed**.`
One not yet tested says **untested** and names the row that will test it. An ADR is Accepted only
when no item is untested: each cites its result in that form, or the owner adds
`— accepted at risk by the owner (YYYY-MM-DD)` (PRAC-0023; `${CLAUDE_PLUGIN_ROOT}/checks/adr-evidence.sh`
holds it from `ADR_EVIDENCE_FROM`, and reads the form, not words found elsewhere in the item).
- <assumption>: <spike id, #PR or receipt <commit>>, **passed**.
- <assumption>: **untested**; tested by <row>.

## Related
- ADR-NNNN, a change in `changes/`, a spec, an insights-log row
