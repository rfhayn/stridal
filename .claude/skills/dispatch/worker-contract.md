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
- **Never put the approval label's name in a Bash command** (ADR-0003). If a lane-3 PR needs the user, say so in
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
- **The dispatcher may merge `main` into your PR branch** (`gh pr update-branch`). `git pull --no-rebase` before
  you push again; never force-push.
- **File follow-up issues as usual.** They land in Later; the dispatcher never picks them up on its own.
