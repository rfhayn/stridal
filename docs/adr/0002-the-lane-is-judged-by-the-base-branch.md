# 0002. The lane is judged by the base branch's rules

Date: 2026-11-11 · Status: proposed

## Context
`lane` is a required check on `main`. Run on `pull_request`, it runs the PR's own copy of `lane.yml`, so a PR could
edit the check that decides whether the owner must look: drop `.github/` from `HARD_PATHS`, or add a workflow that
adds the approval label itself. Since 2025-12-08 `pull_request_target` takes the workflow file and the checkout
commit from the default branch, whatever the PR's base. The repo this was ported from proved the hole and the fix with probes on its
own PRs.

## Decision
- The rules live in `.github/lane/lane.sh`, a pure function of env (labels, changed files, the actor of the latest
  approval-label event, `HARD_PATHS`, `APPROVER`), with a self-test in `.github/lane/test.sh`.
- `.github/workflows/lane.yml` runs on `pull_request_target`, so main's copy judges every PR, **and also on
  `pull_request`**, with the same event types. The second trigger is the transition: on a repo's first PR (a new
  project's kit PR, or the PR that adds this file) main has no copy, `pull_request_target` never runs, and the
  required `lane` check would never report; with no bypass actors the PR could not merge. The source repo solved that with
  a two-PR transition (a second workflow file, retired in a follow-up); one file with both triggers needs no second
  PR and also fixes a new project's first PR. Once the file is on main both runs happen. The ruleset requires every
  run named `lane` to pass, so the PR's own copy can add a failure but never mask main's. Only main's run is the
  judge: the `pull_request` run reads the PR's own CLAUDE.md and `lane.sh`. `kit-check.sh` asserts both triggers and
  their types. It never checks out or runs the PR's head in the `pull_request_target` run; it reads facts about the PR through the API. It runs main's `test.sh` first, so broken rules
  fail closed.
- The approval label counts only when its latest `labeled` actor is the `Approver:` login read from CLAUDE.md's
  `## Dispatcher` block on main, and no GitHub App performed it. An empty approver fails lane 3 closed (lanes 1 and 2 never use it, so a project that has not filled in its
  Dispatcher block still passes them); an empty `HARD_PATHS` fails every lane.
- New commits remove the approval label; that step runs first and the workflow has no concurrency group.

## Consequences
- Good: a PR cannot weaken the check that judges it. A PR-added job named `lane` cannot mask main's: the ruleset
  requires every check run with that name (observed in the source repo's probes).
- Cost / risk: two `lane` runs per PR event (hosted minutes double). A rule change takes effect one PR late. The token in a `pull_request_target` job can write, so the job
  must never run head code. GitHub blocks `pull_request_target` by default in public repos from 2026-12-02, so a
  public repo needs an Actions event policy that allows it. A PR with no changed files, or 3000 or more, fails.
- Revisit if: GitHub changes `pull_request_target`'s checkout rule, or the ruleset starts to accept a bypass actor.

## Links
Ported from the repo this kit came from, with the transition changed: one `lane.yml` listening to both events instead of the source's two-PR transition
(owner ruling 2026-11-11, after review found the PR and every new project's first PR would get no `lane` check).
Related: 0003, 0004.
