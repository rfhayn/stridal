---
description: Clean up after a merged change - sync main, then close its worker tab and remove its worktree and branch. Only the owner can start it.
argument-hint: "<slug> [--abandon]"
disable-model-invocation: true
---

Land the change `$ARGUMENTS`. The owner typing `/land` is the approval to remove this one worker's tab, worktree and branch. Steps in order.

Where this session is running (git dir, common dir, branch):
!`git rev-parse --git-dir --git-common-dir; git branch --show-current`

0. **Main checkout only.** If the git dir and common dir above differ, this is a worktree: stop and tell the owner to run `/land` in the main checkout. Need a slug: if `$ARGUMENTS` has no slug, stop and ask for it. Never guess one.

1. **Update main first.** Run `.claude/bin/session.sh sync` exactly like that: no `cd`, no pipe, no redirect, no command substitution. It fast-forwards main outside the sandbox and needs no prompt. Sync before closing, as its own call, because step 2 runs the `session.sh` in this checkout, which the pull may rewrite. If sync fails or refuses (not a fast-forward, a conflicting local change), stop before closing and show the owner its message.

2. **Close the worker.** Run `.claude/bin/session.sh close <slug>` exactly like that: no `cd`, no pipe, no redirect, no command substitution, or the sandbox exclusion stops matching and it fails. Add `--abandon` only if the owner typed `--abandon` in `$ARGUMENTS`; never on your own. The script checks on GitHub that the PR is MERGED at the local tip, types `/exit` in the worker's tab, then removes the worktree and branch.
   If it refuses or fails, stop and show the owner its message. Never retry around it: no `--abandon` they did not type, no `git worktree remove`, no `git branch -D`.

3. **Report** in 3 lines: what was closed (slug, worktree and branch removed, or why it refused); the PR that was landed, or "abandoned"; and the new tip of main (`git log -1 --format='%h %s'`).
