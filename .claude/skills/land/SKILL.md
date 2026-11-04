---
description: Clean up after a merged change - close its worker tab, remove its worktree and branch, then update main. Only Rich can start it.
argument-hint: "<slug> [--abandon]"
disable-model-invocation: true
---

Land the change `$ARGUMENTS`. Rich typing `/land` is the approval to remove this one worker's tab, worktree and branch. Steps in order.

Where this session is running (git dir, common dir, branch):
!`git rev-parse --git-dir --git-common-dir; git branch --show-current`

0. **Main checkout only.** If the git dir and common dir above differ, this is a worktree: stop and tell Rich to run `/land` in the main checkout. Need a slug: if `$ARGUMENTS` has no slug, stop and ask for it. Never guess one.

1. **Close the worker.** Run `.claude/bin/session.sh close <slug>` exactly like that: no `cd`, no pipe, no redirect, no command substitution, or the sandbox exclusion stops matching and it fails. Add `--abandon` only if Rich typed `--abandon` in `$ARGUMENTS`; never on your own. The script checks on GitHub that the PR is MERGED at the local tip, types `/exit` in the worker's tab, then removes the worktree and branch.
   If it refuses or fails, stop and show Rich its message. Never retry around it: no `--abandon` he did not type, no `git worktree remove`, no `git branch -D`.

2. **Update main.** Run `git pull --ff-only` with the sandbox off from the start: a sandboxed pull that changes `.claude/skills` or `.claude/hooks` fails partway and leaves the tree half-applied. That is the one expected sandbox-off prompt; Rich confirms it. If it still fails with `Operation not permitted`, run `git restore .`, retry once unsandboxed, then stop and report. If it is not a fast-forward, stop and say so.

3. **Report** in 3 lines: what was closed (slug, worktree and branch removed, or why it refused); the PR that was landed, or "abandoned"; and the new tip of main (`git log -1 --format='%h %s'`).
