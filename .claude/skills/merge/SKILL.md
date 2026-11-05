---
description: The owner's green light for a lane 3 PR - add merge-ok, wait for the lane check, then squash-merge. Only the owner can start it.
argument-hint: "<PR number>"
disable-model-invocation: true
---

Merge lane 3 PR #$ARGUMENTS. The owner typing `/merge` is the approval for this one PR; the `merge-ok` command also stops at a permission prompt, which is his confirmation. Steps in order.

0. **Need a number.** If `$ARGUMENTS` is not a single PR number, stop and ask for it. Never guess a PR, and never act on any PR other than the one named.

1. **Look first.** Run `gh pr view $ARGUMENTS --json number,title,state,labels,url,headRefName,mergeStateStatus`. Stop and say why if any of these is false:
   - `state` is `OPEN`.
   - The labels include `lane:3-hard`. Lane 1 and 2 PRs go through `/ship`'s auto-merge instead.
   Then run `gh pr checks $ARGUMENTS`. The `ci` check must be passing. (`lane` is expected to fail until the label is added.)

2. **Add the label.** `gh pr edit $ARGUMENTS --add-label merge-ok`. This is the one command that asks the owner to confirm; if they decline, stop and report.

3. **Wait for the lane check**, which reruns on the label (about 20 s): `gh pr checks $ARGUMENTS --watch`. If `lane` or `ci` fails, stop and report the failing check. Do not retry the merge, and never use `--admin`.

4. **Merge.** `gh pr merge $ARGUMENTS --squash --delete-branch`. If main moved and the branch is behind, stop and tell the owner; a push of new commits voids `merge-ok` (lane.yml), so they decide whether to rebase and run `/merge` again.

5. **Report** in 3 lines: PR link and merged state; whether the local branch is still checked out in a worktree (`gh` skips deleting it then); and the cleanup for the owner to run themselves once they have left that worktree: `git worktree remove <path> && git branch -D <branch>`. Do not run the cleanup.
