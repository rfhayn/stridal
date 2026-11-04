---
description: Write a short brief with machine-checkable done-criteria and a merge lane before any code is written. Use at the start of every change.
argument-hint: "[what to build, or an issue/roadmap item]"
disable-model-invocation: true
model: opus
effort: high
---

Write a brief for: $ARGUMENTS

Where this session is running (git dir, common dir, branch):
!`git rev-parse --git-dir --git-common-dir; git branch --show-current`

Read only what you need: CLAUDE.md, the files you expect to touch, and the matching `.claude/rules/*.md`. Do not write or edit code in this step.

Read the code before believing the issue. If the task comes from an issue or a bug report, confirm the stated cause in the code and cite file:line in Decisions. If the code disagrees with the write-up, say so and brief what the code shows.

Write the check first. Every done-when item must be machine-checkable: a command that exits 0, a named test that passes, or an exact output. "Looks good", "the model is confident" and "no errors raised" are not checks; rewrite any item that reads like one.

Output exactly this shape, at most ~30 lines:

```
## Brief: <short title>
Goal: <one sentence, user-visible outcome>
Done when (each one machine-checkable):
- [ ] `<check command from CLAUDE.md>` exits 0
- [ ] `.claude/bin/scope-check.sh <the Files globs below>` exits 0
- [ ] <named test> passes: `<command>`  (write this test first, see it fail, then build)
- [ ] <...> (2-5 more; each a command, test name, or exact output)
- [ ] every claim in the PR cites a source (file:line, test name, or command output)
Files: <exact paths or globs this change may touch, space-separated>
Out of scope: <what this change will NOT do>
Lane: 1-contained | 2-wide | 3-hard  -- <one-line reason based on blast radius, not confidence>
Plan:
1. <step>  (at most 6 steps; if more, split into two briefs)
Decisions: <choices you are making, one line each, with the source that drove them>
Assumptions: <things you believe but did not verify, and how /ship will verify them>
Questions for Rich: <only if a wrong guess would waste the change; else "none">
```

Lanes (blast radius): 1 = reversible and contained (copy, tests, isolated covered code). 2 = reversible but wide (shared utilities, schema additions, config). 3 = hard to reverse (migrations, deletions, production data, money, plus anything CLAUDE.md or `.claude/rules` lists as lane 3). If unsure between two lanes, pick the higher one.

Then stop and wait. Rich replies "go" (or edits). On "go":
1. **Never build in the main checkout.** If the git dir and common dir above are the same, this is the main checkout (production checkouts stay on `main`). Do not switch branches here. Run
   `git fetch origin && git worktree add .claude/worktrees/<slug> -b <type>/<slug> origin/main` (type = feat, fix, chore, docs),
   then stop and tell Rich: "Worktree ready: `cd .claude/worktrees/<slug> && claude`, then paste the brief." Do not edit files in this session.
   If you are already in a worktree (the git dir differs from the common dir) and it is on a fresh branch from origin/main, continue there.
2. Write the failing test(s) first, then build on Sonnet (`/model sonnet` if this session is on Opus). Commit in small steps.
3. When every done-when item is checkable, tell Rich to run `/ship` (only he can start it). Keep the brief in the conversation; /ship puts it in the PR.

One-way actions: if the change can do something that cannot be undone (send a message, push personal data, write production data, delete, charge money), the brief must name its guard in the first design: a deny rule, a blocking check, a dry-run default, or a test that fails before the action. Do not wait for it to fail twice.

If the change is trivial (one file, obvious, lane 1), say "trivial: no brief" and give just the Files line and one check.
