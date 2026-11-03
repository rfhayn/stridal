# Conventions

The detail `AGENTS.md` points to. `AGENTS.md` is loaded by every agent, so it keeps only the
rules; the reasoning and the edge cases live here, read by range when a task touches them. The
sections marked **(yours)** are for your project to fill; the rest describe the operating model
and hold for any project that adopts it.

## Branching and PRs

The unit is **one change = one branch = one PR = one squash commit to `main`**. One exception, the
owner's of 2026-10-21: rows that edit the same files may ship in one batched PR, titled with the
first row's id (`OPS-89: … (with OPS-103)`), whose body says "Also closes OPS-103"; both rows are
marked merged with it.

- **Branch names.** `change/<id>` for a capability change: one approved proposal in
  `changes/<id>/` (the test: *does it change what a user can do?* If not, it is not a change,
  however much work it is). `fix/<issue>-<slug>` for a defect, `ops/<name>` for tooling, docs and
  process, including the session-close PR. The prefixes are `BRANCH_*` in `.claude/project.conf`
  and the panel's `lanes` map; change them in both.
- **A title names an issue; a closing keyword closes it.** GitHub's keywords (close, fix, resolve
  and their forms: `Fix #<n>:`, `Closes GH-<n>`) close the issue when the merge lands on the default
  branch, from the title, the PR body, the squash message or a branch commit that message copies.
  Write one only when the PR finishes the issue; otherwise use a title with no keyword, naming `#<n>`
  if needed. An issue labelled `team-queue` is an input its session closes: while it is open
  `.claude/local/guard.d/team-queue.sh` refuses a keyword on it, and the PR that delivers it says so
  in its squash body, `Delivers team-queue #<n>`, which session-start reads from commit bodies on
  `origin/main`. A code span shelters a keyword in the PR body, once the merge sets a body of its
  own. Whether GitHub skips one in commit text is not known, so the rule refuses it there.
- **One PR carries the whole slice**: the change's artifacts, the implementation, and the spec
  promotion (archive), reviewed together.
- **Squash-merge only.** Rebase-merging rewrites SHAs and auto-closes stacked PRs.
- **No stacked PRs.** If B depends on A, merge A first, then branch B from `main`.
- **Merge only through `merge-pr`**, which wants gate evidence for the head commit and converged
  review before it runs `gh pr merge --squash`. `pr-merge-guard` refuses `--auto`, `--admin`,
  a merge of a PR that is not open, and a merge without evidence. A merge clicked on the website,
  run from another client or made by a Cursor lane runs no hook. Once the owner sets it (owner
  queue, 2026-11-01), a GitHub ruleset on `main` (OPS-165, ADR-0012's D7) requires the
  `test (ubuntu-latest)` check from GitHub Actions, with no bypass actor, so no merge by any road
  lands without that check green on the PR's head. Until then it does not exist, and nothing local
  checks that it is set or stays set. It judges nothing else (not the local gate receipt, not
  review, no other guard rule), and the rest stays an accepted residual, not a gap to paper over
  with branch protection rules the agents cannot satisfy. Only the Ubuntu leg is required, because
  a PR runs Ubuntu alone (`test.yml`): a macOS leg would never report and would block every merge.
  The bare `test` is never required: a draft's skipped run reports it, and GitHub counts a skipped
  check as passing. The settings and the `gh api` reads that verify them: `docs/playbook.md`,
  *A required check on the server*.
- **The main checkout stays on `main`.** Every hook is read from it; work happens in worktrees
  under `.claude/worktrees/<lane>`, one per lane, each cut from `origin/main`.
- **Propose just in time, at most ONE change proposed ahead** (`docs/principles.md`). To capture
  scope for later, write a roadmap row, not a change directory.
- **Every change states its slice**: `tasks.md` ends with a `Slice:` line.

## Commits

Imperative mood, one idea per commit. Commits written by the build-change workflow read
`<change>: task group N — <title>`. When `attribution.enabled` is true in
`.claude/model-roles.json`, every commit Claude writes ends with `attribution.trailer`, so the
history says which model wrote what; set it to false if your project keeps commits unattributed.

## The gate

`GATE_RUN` (`.claude/project.conf`, default `scripts/ci/run-local.sh`) is the full gate. It takes
the machine-wide gate lease first, so two worktrees never run it at once; runs every step in
`GATE_STEPS`; and only after a complete, clean run writes `<git-dir>/ci-receipt` naming the
commit. Agents run it through `GATE`, which keeps the full log in a file and prints only stage
markers, failure lines and a tail. `pr-merge-guard` accepts that receipt, or a named remote
workflow's success for the same SHA, as evidence. See `scripts/ci/README.md`.

## Review per task group, not per PR

Review when a task group is done, not when the PR is (*A review's blind spot is set by its
framing*). The build-change workflow does exactly that: it gates, reviews with a reviewer that is
not told what the builder intended, fixes, and re-reviews until no finding is medium or worse; it
stops for the owner if peak severity RISES between rounds or at the review cap without
converging. The cap is per risk (`.claude/review-cap.sh`: the proposal's `**Risk:**`, or an ops or
fix row's `Risk:` in its Change cell, against `REVIEW_CAPS`, low 2, normal 3, high 3). At the cap,
`REVIEW_AT_CAP` (`stop` by default) stops when the cap round still finds medium or worse; lows still
merge, each under `KNOWN LIMITS` with its owner. A change built by hand gets the same loop from the `apply-change` skill. A PR whose
diff is Markdown prose only gets the lighter `reviewer-docs` instead (`review-lane.sh`).

## Who decides, and what runs unattended

**The owner decides:** a change's proposal and every `design.md` decision, unless
`APPROVAL_DELEGATED="1"` delegates them and `/propose` step 3a finds nothing that keeps them; ADRs; a production
deploy and anything else irreversible; anything outward beyond this repo.
**Everything else runs without asking, merging included:** build, gate, review, fixes, commits, push, PRs, issues and
comments on this repo, and the squash-merge through `merge-pr`. A session runs `session-start` to
`session-close` hands-off and reaches the owner only by `PushNotification` (or your equivalent):
at an owner decision, an environment fault, a gate that stays red, or review not converging, once
per delegated approval, and once at the end, one line. Work that needs the owner at the computer goes in the owner queue.

**One row, one session, one PR.** A row's PR writes its records to one fragment,
`docs/journal.d/<row id>.md` (`JOURNAL_FRAGMENTS`; the shape is that directory's README), and never
edits the journal, the insights log or any row's Status. A daily close (`BRANCH_SESSION_CLOSE`, once
a day or every 3–4 rows) folds the fragments on main into one `## Session N` (`session-close`,
*Two forms*). `pr-merge-guard` rule 7 refuses a row PR that adds a session heading; rule 8 holds any
PR that changes the journal or the log, whatever its branch, on top of `origin/main`.

**Several people.** Each person has their own Claude and merges only their own PRs. Claude's
memory is per machine: what another person needs goes in the repo. Fragments never conflict (one
file per row); the close's shared files are resolved as `session-close` describes (the journal
renumbers, the insights log keeps both rows, ADRs take the next number).

**A public record states a finding's class, never its steps.** On a public repository, a row, a
fragment, a PR body or a journal entry names the class of an unfixed finding; the steps stay in a
local file. Nothing checks this: it is **Nothing. You.**, and text once merged stays in history.

## Testing (yours)

What a test must prove in this project, what runs against real services, and what a reviewer
grades on. The principles that apply whatever the language are in `docs/principles.md`: a test is
evidence only once it has failed, and a falsification can fail at any link.

## Architecture rules (yours)

The load-bearing constraints of your code base: layering, the data layer, error handling, what
must stay pure. Keep each rule checkable, and give it a row in AGENTS.md's table once something
executes it.
