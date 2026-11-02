**Mark the session done in the plan (local layer).** In the close PR, set this session's *When*
cell in `docs/roadmap.md`'s *Session plan* to its dates followed by `(done)` (`2026-10-17 to
2026-10-18 (done)`), and move any of its rows that did not land into the next session's *Rows*,
first, unless the owner reorders them. Moving a row REMOVES it from this session's *Rows*: a row is
planned once (a change's `(proposal)` and then its build are the one pair), and `checks/roadmap.sh`
fails the close PR otherwise. session-start's *session plan* line names the first session not marked
`(done)`, so a session left unmarked opens again as the next one.
