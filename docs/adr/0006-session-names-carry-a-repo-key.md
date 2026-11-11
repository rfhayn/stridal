# 0006. Dispatcher and worker session names carry a repo key

Date: 2026-11-11 · Status: proposed

## Context
Claude session names are machine-wide: SendMessage, idle subscriptions and `ps` liveness checks resolve a bare name
across every repo on the Mac. With two repos running the dispatcher, a worker's RESULT to `dispatch` fails or reaches
the other repo's dispatcher, which would act on a PR number it doesn't own, and two repos with the same issue number
collide on the worker name.

## Decision
- Each repo's CLAUDE.md `## Dispatcher` block has `Name: <key>`: a lowercase letter first, then `[a-z0-9-]`, at most
  20 characters, unique among the machine's dispatcher repos. `dispatch-next.sh --name-key` is the one reader.
- The dispatcher is `dispatch-<key>` and a worker is `<key>-<slug>`. A key starts with a letter and slugs with their
  issue number, so a dispatcher name never equals another repo's worker name.
- `session.sh open` takes `--key` and records the name in `<git-common-dir>/spawn/<slug>.session`; `watch`, `close`,
  the lock and `session.sh name <slug>` match the full recorded name. A record is validated as data. Branches,
  worktrees and spawn files keep the bare slug.
- With no record the name is the bare slug, so a worker opened before the record existed is still found.

## Consequences
- Good: two repos' dispatchers and workers cannot be confused.
- Cost / risk: uniqueness of `Name` is by hand; nothing checks across repos. Until part C of #436 retires the old
  skills, `session.sh open` accepts a call without `--key` (the old `/brief` makes one): that worker is named by its
  bare slug and gets no record, as before. Part C makes `--key` required.
- Revisit if: a multi-project dispatcher discovers keys and can check them.

## Links
Ported from job-search ADR-0014 (commit 01dc4ad). Related: 0001, 0004.
