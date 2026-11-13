## Worker contract (from the dispatcher)

You are a worker session opened by the dispatcher, in your own worktree, for the issue named above.

- **Your issue has a "Done when", so it is pre-approved.** Skip the brainstorm and go straight to a plan, then
  subagent-driven development. Follow the repo's CLAUDE.md for the PR body, the lane label and
  `gh pr merge --auto --squash --delete-branch`.
- **These override the global Finishing and Cleaning-up rules:** never run the deploy command; never remove your
  worktree or branch; stop once auto-merge is queued. The dispatcher deploys, closes this tab and cleans up.
- **Report by SendMessage to the dispatcher**, the session named in this brief's last line (`dispatch-<key>`,
  unique to this repo: another repo's dispatcher may run on this machine, so never send to a bare `dispatch`):
  - `RESULT pr=<n> lane=<k>` when done;
  - on any of the four stop classes (irreversible or destructive, security-sensitive, an outside side effect the
    repo's CLAUDE.md says needs a yes, a plan where every path is a guess): `BLOCKED: <one-line question>`, then
    wait in this tab. The user may answer here.
- **You act on GitHub as the dispatcher's agent identity** (`GH_TOKEN` from the launcher, when the repo sets one).
  Never unset it, run `gh auth`, or read the Keychain to act as the approver.
- **Never put the approval label's name in a Bash command** (Stridal's ADR-0003). If a lane-3 PR needs the user, say so in
  RESULT.
- **Worktree-guard workarounds:**
  - plain single `gh` and `git` commands (no pipes or `&&`);
  - Superpowers helper scripts by absolute path;
  - loops and waits in a scratchpad script run with `sh`;
  - `gh pr checks <n> --watch` to wait on checks.

  If a command is refused, name it exactly in your report.
- **Pass free text through a file.** Write any commit message, PR or issue body, or comment to a scratchpad file
  with the Write tool, then pass the file: `git commit -F <file>`, `gh pr create --body-file <file>`,
  `gh issue comment <n> --body-file <file>`, `gh api ... -F body=@<file>`. Never put it inline with `-m`, `--body`
  or a heredoc in the same Bash command as `git` or `gh`. The reason: the permission rules and any
  command-text guard match the whole command text and never parse it, so a message that only mentions a trigger
  word (a path, a flag, a `*`, the approval label) is refused or prompts.
- **Stay inside your issue's `Footprint:` line.** Another worker may be building beside you. If the change must
  reach outside it, put `Footprint grew: <paths>` on its own line of the PR body (paths comma-separated, no
  globs); the dispatcher reads it to keep a second worker out of those paths.
- **Before you open the PR, run the checks yourself, in this order** (nothing else runs them for a worker). Record each result as evidence (exit code, test name, output line) for the PR body:
  1. **Gates.** Run the `Gates:` command of CLAUDE.md's `## Dispatcher` block, and every done-when command of your
     issue.
  2. **Scope.** Run `gh issue view <n>` plain (no pipe, no redirect), save the issue body to a scratchpad file with
     the Write tool, then run `.claude/bin/scope-check.sh --footprint <that file>`, adding each path of your PR's
     `Footprint grew:` line as an extra glob (`<path>/*` for a directory). It prints `scope-check: no Footprint,
     scope not checked` and exits 0 when the issue has none: that item runs alone.
     - A stray file: remove it from the diff, or put it on the `Footprint grew:` line and rerun. If the brief's own
       `Files` list is narrower than the Footprint, run `scope-check.sh <Files globs>` as well.
     - **Return the unit, not the batch.** When a check fails, work on that one unit with a scope line, "fix
       <file/test> only", rerun that check alone, then the full set. Count attempts per unit. **After 3 failed
       attempts on the same unit, stop** and report `BLOCKED:` with what failed and why; do not keep looping.
  3. **Review by lane** (from the issue's lane; if the diff now looks wider, move up a lane, never down).
     - Lane 1: no reviewer. CI is the check.
     - Lanes 2 and 3: the reviewer has no shell, so first write what it reads:
       `mkdir -p .claude/review`, then `git diff origin/main...HEAD` into `.claude/review/diff.txt` and
       `git log --oneline origin/main..HEAD` into `.claude/review/log.txt` (run each plain and save its output with
       the Write tool if your shell refuses the redirect). Run the `reviewer` subagent once, passing the issue
       text as the brief; for lane 3 pass the per-call `model: opus` parameter.
     - Save the reviewer's reply verbatim to `.claude/review/review.txt`, then run
       `.claude/bin/check-evidence.sh .claude/review/review.txt .claude/review/diff.txt .claude/review/log.txt`.
       A failure (a "met" citing a line that is not in the diff or log, or citing nothing) is a blocking finding:
       treat the verdict as FIX FIRST, whatever the reviewer said.
     - On FIX FIRST: fix each blocking finding you agree with as its own unit (the scope-line rule and 3-attempt
       cap above apply) and note any rejected finding with a one-line reason. **No second review round**, unless
       CLAUDE.md's project section allows one for this lane. If a fix needs a design change, `BLOCKED:`.
  4. **Evidence in the PR body.** Every claim cites a source (file:line, test name or command output); one without
     a source is removed or marked "unverified". Put the review result and the lane's reason in the body. Leave
     `.claude/review/` uncommitted.
- **The PR body's first line is `Why: <one sentence>`**; the `lane` check fails a body without it. Start from
  `.github/pull_request_template.md` and label the PR with its lane. `gh pr edit` fails under the agent token
  ("needs read:org"), so edit through the REST API, each as a single plain command (the body file written with the
  Write tool):
  `gh api -X PATCH repos/{owner}/{repo}/pulls/<n> -F body=@<file>`
  `gh api -X POST repos/{owner}/{repo}/issues/<n>/labels -f 'labels[]=<lane label>'`
- **The dispatcher may merge `main` into your PR branch** (`gh pr update-branch`). `git pull --no-rebase` before
  you push again; never force-push.
- **File follow-up issues as usual.** They land in Later; the dispatcher never picks them up on its own.
