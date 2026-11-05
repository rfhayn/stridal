# Roadmap

One list. The section is the status: Now / Next / Done. There is no in-progress section; an open PR whose body carries `Roadmap: <ID>` shows the item is in progress.
An item moves to Done in the PR that completes it (`/brief` lists this file in Files). Ideas go to GitHub issues, not here.

## Now (at most 3)
None yet: the owner picks the first item from Next.

## Next
### R-011 Terminal support beyond Ghostty
- Why: the README's one hard requirement is macOS and Ghostty; elsewhere /brief falls back to a manual `claude --worktree` and paste.
- Done when: `session.sh open` opens a worker in at least one more terminal, with kit-check dry-run tests.
- Links: README "How it works", #418.

### R-012 A kit-check test that runs the real `session.sh sync`
- Why: the #423 reviewer noted kit-check never runs the real `exec git pull --ff-only`, so a regression there passes CI.
- Done when: a test fast-forwards a scratch clone that is behind its origin and asserts the new tip.
- Links: #423.

### R-013 A status line test for the `↓behind` branch
- Why: the #425 reviewer noted it is untested.
- Done when: kit-check asserts `↓1` for a branch one commit behind its upstream.
- Links: #425.

### R-014 Say that a project-level `statusLine` overrides a personal one
- Why: the #425 reviewer noted any project that installs the kit overrides a user's own status line.
- Done when: the README says so in one sentence.
- Links: #425.

### R-015 Lane 1 and 2 PR bodies hold no pending claims
- Why: #427 auto-merged within a minute and its squash message froze "unverified until ci and lane pass" and "BLOCKED".
- Done when: /ship step 4 says lane 1 and 2 bodies state only what is true at merge time, and a grep finds no "pending"/"waiting on" lines in the next lane 1 or 2 squash message.
- Links: #427.

## Done (last 10; delete older)
- R-001 fix: say gh runs plain instead of needing a sandbox-off run (#416)
- R-002 docs: PR template Why/Roadmap lines, lane.yml Why check, /brief recent work (#417)
- R-003 feat: session.sh opens and closes worker sessions in Ghostty tabs (#418)
- R-004 feat: /brief and /land use session.sh, shipped to new projects (#419)
- R-005 feat: worker login-shell PATH, /ship <slug> from main, close cleanup (#421)
- R-006 docs: README says what Stridal is; /land pulls before it closes (#422)
- R-007 feat: session.sh sync for /land, /ship reports back (#423)
- R-008 chore: shipped files say the owner, not Rich; allow gh pr list (#424)
- R-009 feat: a lean status line that ships with the kit (#425)
- R-010 docs: CLAUDE.md says the owner, not Rich (#427)
