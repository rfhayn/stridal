# 0001. The backlog is GitHub Issues plus the Project's Now column

Date: 2026-11-11 · Status: proposed

## Context
Stridal's process kept a markdown roadmap (`docs/ROADMAP.md`), and each item needed several human steps (`/brief`,
`/ship`, `/land`, `/merge`, a worker tab). Maintaining that process was becoming the work. GitHub already holds what
a roadmap file duplicates: Issues with a "Done when", one Project board (Now / Next / Later / Done), and the PRs that
close them. The job-search repo made this move on 2026-11-08 and ran a dispatcher on it
(job-search ADR-0007, spec `docs/specs/2026-11-09-dispatcher-design.md`).

## Decision
The backlog is Issues plus one Project: an issue in the Project's **Now** column, with a "Done when", is approved
work. `/dispatch` works Now in board order. The owner moves an item into Now; nothing else does (the machine user has
`read:project` only, ADR-0004). Follow-ups are filed as issues, which land in Later. The markdown roadmap template
is retired in part C of #436, not here.

## Consequences
- Good: one place for the backlog, next to the PRs that close it. "Moved to Now by the owner" is a trustworthy
  signal.
- Cost / risk: a repo adopting the dispatcher needs a user-owned Project board and an issue discipline ("Done when").
  The board is read with `gh api graphql`; an organisation-owned board needs a different query.
- Revisit if: the Project moves to an organisation, or GitHub changes what a token with `read:project` can read.

## Links
Ported from job-search ADR-0007 (commit 01dc4ad). Issue #436 (parts A to D). Related: 0004, 0005.
