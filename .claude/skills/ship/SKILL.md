---
description: Finish a change - run the brief's checks, review by lane, open the labeled PR with decisions and assumptions, and queue auto-merge where the lane allows. Use when the brief's done-when items are met.
disable-model-invocation: true
---

Current branch and changes:
!`git status -sb`
!`git rev-parse --git-dir --git-common-dir`
!`git log --oneline origin/main..HEAD`
!`git diff --stat origin/main...HEAD`

Ship this change. Steps in order.

0. **Refuse on main.** If the branch above is `main` (or `master`), or the two git dirs above are the same (the main checkout), stop: say "run /brief to get a worktree" and do nothing else. If the branch is `worktree-<slug>`, first run `git switch -c <type>/<slug>` (type = feat, fix, chore, docs), so the PR has a real branch name.

1. **Run the checks, not opinions.** Run every done-when command from the brief, including the CLAUDE.md check command and `.claude/bin/scope-check.sh <Files globs>`. Record each result as evidence (exit code, test name, output line).
   - A stray file in scope-check: remove it from the diff, or stop and ask Rich to widen the brief. Do not widen it yourself.
   - **Return the unit, not the batch.** When a check fails, work on that one unit with a scope line, "fix <file/test> only", rerun that check alone, then the full check. Count attempts per unit. **After 3 failed attempts on the same unit, stop**: report what failed and why, and propose a re-brief. Do not keep looping.

2. **Review by lane** (lane from the brief; if the diff now looks wider than the brief said, move up a lane, never down).
   - Lane 1: no reviewer. CI is the check.
   - Lanes 2 and 3: the reviewer has no shell, so first write what it reads: `mkdir -p .claude/review && git diff origin/main...HEAD > .claude/review/diff.txt && git log --oneline origin/main..HEAD > .claude/review/log.txt`.
   - Lane 2: run the `reviewer` subagent once, passing the brief.
   - Lane 3: run the `reviewer` subagent once with the per-call `model: opus` parameter, passing the brief.
   - On FIX FIRST: fix each blocking finding you agree with as its own unit (step 1's scope-line rule and 3-attempt cap apply), and note any rejected finding with a one-line reason. **No second review round**, unless CLAUDE.md's project section allows one for this lane. If a fix needs a design change, stop and ask Rich.

3. **Rebase and push.** Commit everything first. Run `git fetch origin`, then check for paths the sandbox protects: `git diff --name-only HEAD origin/main | grep -E '^(\.mcp\.json$|\.claude/(settings|skills/|agents/|commands/|hooks/|workflows/))'`.
   - If `git merge-base --is-ancestor origin/main HEAD` succeeds, skip the rebase even when the grep matches: the match is this branch's own change, so a rebase is a no-op.
   - No match: `git rebase origin/main`.
   - A match (and origin/main is not an ancestor of HEAD): a sandboxed rebase would fail partway and leave the tree half-applied, so run `git rebase origin/main` unsandboxed from the start. That always asks Rich. If he declines, stop and report. Never add a standing allow rule for it.
   - If a rebase still stops with `Operation not permitted`: it leaves files changed and no rebase in progress, so `git rebase --abort` fails. Run `git restore .`, then retry once unsandboxed.
   Rerun the check if the rebase pulled in changes, then `git push origin HEAD` (`--force-with-lease` if the branch was already pushed). No `-u`: the sandbox cannot write upstream tracking to `.git/config`, so the push reports "could not lock config file". That is harmless; the push itself succeeds.

4. **Open the PR**: write the body to a file, then run `gh pr create --head <branch> --base main --label lane:<N>-<name> --title "<conventional title>" --body-file <path>` (the form the `Bash(gh pr create*)` allow rule matches; e.g. title `feat: weekly standings email`). `gh` fails in the sandbox with "x509: OSStatus -26276", so it needs an approved sandbox-off run; that is expected, not a guard. The body comes from `.github/pull_request_template.md`: goal; each done-when item ticked with its evidence; decisions and assumptions, each with a source line (file:line, test, command output, or the reviewer's check); review result; lane and reason. A claim without a source is removed or marked "unverified". Leave out the template's HTML comments: the body becomes the squash commit message.

5. **Merge by lane.**
   - Lane 1 and 2: run exactly `gh pr merge --auto --squash --delete-branch` (the allow rule matches this exact command). GitHub merges when `ci` and `lane` pass and the branch is up to date with main; if main moved, rebase, push, and let it re-run.
   - Lane 3: do not queue auto-merge, and never add the `merge-ok` label. Tell Rich the PR link and the one thing to look at. He adds `merge-ok` and merges.

6. **Report** in 3 lines: PR link, lane and merge state, anything left undone.
   **Learning edge:** a one-way failure (a pushed secret or personal data, a sent message, a production write) needs its guard now, the first time: propose it as a blocking check. Otherwise, if a failure in this change has happened before (the same cause twice, in this session or noted in a past PR or CLAUDE.md), propose exactly one guard in the PR body: a line for CLAUDE.md "Guards (learned)", a permissions rule, or a test. Prefer a test or permissions rule over prose. Do not add it unasked outside this PR.
