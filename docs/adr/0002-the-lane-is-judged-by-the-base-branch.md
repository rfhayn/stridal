# 0002. The lane is judged by the base branch's rules

Date: 2026-11-11 · Status: proposed

## Context
`lane` is a required check on `main`. Run on `pull_request`, it runs the PR's own copy of `lane.yml`, so a PR could
edit the check that decides whether the owner must look: drop `.github/` from `HARD_PATHS`, or add a workflow that
adds the approval label itself. Since 2025-12-08 `pull_request_target` takes the workflow file and the checkout
commit from the default branch, whatever the PR's base. job-search proved the hole and the fix with probes on its
own PRs (job-search ADR-0009).

## Decision
- The rules live in `.github/lane/lane.sh`, a pure function of env (labels, changed files, the actor of the latest
  approval-label event, `HARD_PATHS`, `APPROVER`), with a self-test in `.github/lane/test.sh`.
- `.github/workflows/lane.yml` runs on `pull_request_target`, so main's copy judges every PR. It never checks out or
  runs the PR's head; it reads facts about the PR through the API. It runs main's `test.sh` first, so broken rules
  fail closed.
- The approval label counts only when its latest `labeled` actor is the `Approver:` login read from CLAUDE.md's
  `## Dispatcher` block on main, and no GitHub App performed it. An empty approver fails lane 3 closed (lanes 1 and 2 never use it, so a project that has not filled in its
  Dispatcher block still passes them); an empty `HARD_PATHS` fails every lane.
- New commits remove the approval label; that step runs first and the workflow has no concurrency group.

## Consequences
- Good: a PR cannot weaken the check that judges it. A PR-added job named `lane` cannot mask main's: the ruleset
  requires every check run with that name (observed in job-search probes #144 and #218).
- Cost / risk: a rule change takes effect one PR late. The token in a `pull_request_target` job can write, so the job
  must never run head code. GitHub blocks `pull_request_target` by default in public repos from 2026-12-02, so a
  public repo needs an Actions event policy that allows it. A PR with no changed files, or 3000 or more, fails.
- Revisit if: GitHub changes `pull_request_target`'s checkout rule, or the ruleset starts to accept a bypass actor.

## Links
Ported from job-search ADR-0009 (commit 01dc4ad), without its two-PR transition (this repo has one `lane.yml`).
Related: 0003, 0004.
