# 0005. Two workers run at once only on declared, disjoint footprints, under strict required checks

Date: 2026-11-11 · Status: proposed

## Context
Running two workers at once has two failure modes. **Overlap:** two workers editing the same files conflict, or
produce two changes that each pass alone and break together; the pick must know what an issue will touch before its
worker starts. **Stale green:** with `strict_required_status_checks_policy: false`, each of two open PRs is tested
against the `main` it branched from, so the second merges without ever being tested on top of the first.

## Decision
- An issue body line `Footprint: <path>, <path>...` declares what it will touch. An issue with no such line runs
  alone. CLAUDE.md's `Footprint areas` key paths by coarse area; two keys overlap when equal or one is a directory
  prefix of the other.
- At most one hard-path item runs at a time (a path matching `HARD_PATHS`, or a PR labelled lane 3).
- `dispatch-next.sh` picks the first Now item compatible with the ones in flight.
- With `max_workers` above 1 the ruleset must set `strict_required_status_checks_policy: true`; the dispatcher
  reads the live rules once per session and runs one at a time if strict checks are off or `Footprint areas` is
  missing. When a green PR with auto-merge queued is behind, it runs `gh pr update-branch`.
- Deploys run in the foreground, one at a time.
- **This repo sets `max_workers: 1`.** Nothing here needs two at once; the machinery ships for projects that do.

## Consequences
- Good: a project that needs throughput can raise `max_workers` safely, and one that doesn't pays nothing.
- Cost / risk: issues need a `Footprint:` line to run in parallel, and a footprint is a promise, not enforced (a
  stray is caught only by strict `ci`). Each second PR costs a merge commit and a `ci` re-run. Strict checks void a
  lane-3 approval when the PR falls behind (new commits remove it, 0002). Coarse areas over-serialise.
- Revisit if: a merge queue becomes cheaper than strict checks plus update-branch.

## Links
Ported from job-search ADR-0013 (commit 01dc4ad). The ruleset in `.github/ruleset-main.json` is the owner's to
apply (a GitHub setting). Related: 0001, 0002.
