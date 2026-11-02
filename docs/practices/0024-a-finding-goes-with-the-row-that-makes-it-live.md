# PRAC 0024: A finding that cannot fire yet goes with the row that makes it live

- **Status**: Proposed
- **Date**: 2026-11-02
- **Tags**: review, process, planning
- **Source**: S22, OPS-184's launcher; the insights-log row *hardening code that nothing runs*
  (2026-11-02)

## Context
OPS-184's launcher went through three review rounds, each finding new highs, in code no session
registers. Two of those findings came from the previous round's own fix. Each round was correct on
its terms, and none could change what any session did, because nothing ran the code. The owner
stopped it: the findings moved into OPS-218's design and the code stayed on its branch.

## Practice
1. **Ask what runs it.** Before another review round on code shipped inactive, name the process
   that runs it in production (AGENTS.md, rule 3).
2. **If nothing does, stop hardening it.** A finding that cannot fire yet moves to the row that
   makes the code live, as a condition of that row's design.
3. **Name that row in the deferral.** Rule 1 applies: the row must exist, be open and contain the
   work.

## Consequences
### Positive
- Review rounds go to code that can change an outcome, and fixes stop breeding findings in code
  that may be redesigned.

### Negative / trade-offs
- Known findings sit open for longer, so the row that switches the code on carries a heavier design.
- It needs a judgment of "cannot fire", which a wrong reading turns into a missed defect.

## Enforcement
**Nothing. You.** The review cap (`.claude/review-cap.sh`) limits the rounds, but nothing asks
whether the code runs.

## Related
- PRAC-0014 (converge review by deleting mechanism), PRAC-0010 (close the class). OPS-184, OPS-218,
  OPS-224.
