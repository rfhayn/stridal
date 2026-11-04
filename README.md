Formerly Stridal; the old project is preserved at tag stridal-final.
# Lean kit: building with Claude Code, without the process tax

A copy-in template for a solo developer (plus the odd collaborator) building with Claude Code.
It replaces Stridal's operating model with native Claude Code features, GitHub's own merge controls,
and two short skills. About 17 files, ~600 lines in total, nothing to maintain between projects.

## Principles
1. **GitHub enforces, Claude follows.** main is protected by a ruleset (required checks, squash only,
   no force push, no bypass). No local merge guards, wrappers or receipts.
2. **Write the check first.** Done-criteria are machine-checkable: tests exit 0, the diff touches only
   the files in the brief (`scope-check.sh`), every PR claim cites a source line. "Looks good",
   "the model is confident" and "no errors raised" are not checks.
3. **Merge lanes by blast radius, not confidence.**
   | Lane | What | Gate |
   |---|---|---|
   | `lane:1-contained` | reversible and contained: copy, tests, isolated covered code | CI green, auto-merge |
   | `lane:2-wide` | reversible but wide: shared utilities, schema additions, config | CI + one reviewer round, auto-merge |
   | `lane:3-hard` | hard to reverse: migrations, deletions, production data, money | never auto-merges; Rich adds `merge-ok` and merges |
   The `lane` CI check is code: it forces lane 3 for `HARD_PATHS` and fails lane 3 until `merge-ok` is on the PR.
   New commits after `merge-ok` remove the label. Claude is denied any command containing `merge-ok`.
4. **One review round, blocking findings only, with evidence.** No severity-convergence loops.
5. **Return the unit, not the batch.** A failed check goes back as "fix this file only". After 3 failed
   attempts on one unit, stop and re-brief.
6. **Guards.** A one-way failure (a commit or push of personal data or secrets, a sent message, a production
   write, a deletion) gets its guard in the first design: a deny rule, a blocking check or a dry-run default,
   before it can happen once. Anything reversible follows the learning edge: when it fails the same way
   twice, its confirmed cause becomes one guard (a CLAUDE.md line, a permissions rule, or a test).
7. **Deterministic work is code, not a model call**: merging, ranking, dedup, comparisons, scope and
   lane checks.
8. **Sonnet builds, Opus plans and reviews lane 3.** Medium effort by default.
9. **One change at a time per builder.** Each builder works in its own worktree, which `/brief` creates;
   the main checkout stays on `main`. Run at most 2-3 builders at once, fewer if the check suite slows or
   flakes under load. Never "several in parallel".
10. **Rich's human steps:** choosing what ships (saying "go" on a brief), typing `/ship`, which Claude can't
   start itself, and approving lane-3 merges. He does not review intermediate output.

## Files
| Path | What it does |
|---|---|
| `CLAUDE.template.md` | ~48-line template, installed as `CLAUDE.md`: commands, how we work, merge lanes, ask-first list, guards (one-way + learned), extension point |
| `CLAUDE.md` | This repo's own, filled in. Not copied to new projects |
| `.claude/settings.json` | Sonnet + medium effort; `acceptEdits`; deny list (secrets, `--admin` merges, pushes to main, ruleset edits, `merge-ok`); unsandboxed retries always ask; Bash sandbox with GitHub/npm network |
| `.claude/hooks/one-way-guard.sh` | OPTIONAL, not wired by default. The one hook slot, for a blocking guard on the project's one-way failure (example: blocks `git add/commit/push` of personal-data or secret paths) |
| `.claude/bin/scope-check.sh` | Deterministic check that the branch touches only the brief's files |
| `.claude/bin/kit-check.sh` | This repo's own check: shellcheck, JSON, and `bootstrap.sh` in copy-only mode. Not copied to new projects |
| `.claude/agents/reviewer.md` | Fresh-context reviewer with no shell: one round, blocking findings with file:line evidence, lane check, decisions and assumptions check. Sonnet by default, Opus for lane 3 |
| `.claude/agents/researcher.md` | Read-only research agent (no Edit, Write or Bash); answers with sources |
| `.claude/skills/brief/SKILL.md` | `/brief <task>`: Opus writes goal, machine-checkable done-when, Files, lane, plan, decisions, assumptions. Waits for "go" |
| `.claude/skills/ship/SKILL.md` | `/ship`: run the checks, review by lane, rebase, labeled PR with evidence, auto-merge for lanes 1-2 |
| `.claude/rules/EXAMPLE-migrations.md.example` | Example path-scoped domain rule (inactive until renamed to `.md`) |
| `.github/ci.template.yml` | Installed as `.github/workflows/ci.yml`, the required `ci` check: one job, 10-minute timeout, cancels superseded runs, gitleaks secret scan, then your stack's check |
| `.github/workflows/ci.yml` | This repo's own `ci`: gitleaks, then `kit-check.sh`. Not copied to new projects |
| `.github/workflows/lane.yml` | The required `lane` check (merge-lane gate, ~10 s) |
| `.github/ruleset-main.json` | Ruleset for the default branch: PR required (0 approvals), squash only, checks `ci` + `lane`, no deletion, no force push, no bypass actors |
| `.github/pull_request_template.md` | What/why, lane, done-when evidence, decisions & assumptions with sources, review, guard |
| `docs/ROADMAP.md` | One checklist: Now (max 3), Next, Before launch, fixed dates, Done |
| `docs/adr/0000-template.md` | Short ADR, only for decisions expensive to reverse |
| `gitignore.append` | Ignores `.claude/worktrees/`, `.claude/review/`, local settings, `.env*`, `PERSONAL_DATA/` |
| `.gitattributes` | LF line endings on every OS, for this repo. Not copied to new projects |
| `bootstrap.sh` | Copies the files (never overwrites), applies the runner choice, sets squash commits to carry the PR title and body, posts the ruleset first (rolls back on failure), labels; enables auto-merge only after a red PR was refused |

Not in the kit on purpose: session numbers, journals, session-close PRs, local CI receipts, merge-guard
wrappers, a review loop, a worktree launcher, a roadmap queue engine, practice records, bot fleets.
Claude Code already ships worktrees (`claude --worktree`), `/plan` mode, `/code-review`, subagents,
permissions and a sandbox. GitHub already ships rulesets and auto-merge.

## Install into a new project (under 30 minutes)
`bootstrap.sh` is the only real install route. GitHub's "Use this template" skips the ruleset, runner choice and
labels, and copies this repo's own `CLAUDE.md` and `ci.yml` instead of the templates.

1. **Choose the runner.** `hosted` bills Actions minutes (`lane` ~1 minute per run, 2-4 runs per PR, plus every
   `ci` run). If this account has ever run out of minutes or paused `pull_request` CI, choose `self-hosted`
   (a machine you own that is on while you work; never a production box).
2. `./bootstrap.sh ~/code/myproject <hosted|self-hosted> owner/myproject` (needs `gh auth login` as a repo admin;
   without `owner/repo` it copies files only). It posts the ruleset first, restores your previous merge
   settings if that fails, and leaves auto-merge OFF. Rulesets on a **private** repo need GitHub Pro or Team.
3. Fill the `{{placeholders}}`: `CLAUDE.md` (stack, check command, lane-3 paths, personal-data paths), `ci.yml`
   (the same check command, including the format check), `HARD_PATHS` in `lane.yml` (every one-way path: schema,
   outbound email/messages, production-data writers, credential handling, deploy), and `PERSONAL_DATA` in
   `.claude/settings.json` and `.gitignore`. Add package registries to `sandbox.network.allowedDomains`.
4. If the project's one-way failure is a git command, wire the optional hook (below) now, not after it happens.
5. Open one PR with the kit, label `lane:2-wide`, merge it by hand when `ci` and `lane` are green. Time `ci`; over
   10 minutes, move slow suites to a nightly workflow.
6. **Prove a red PR can't merge**: open a PR with a deliberately failing test; when `ci` is red run
   `./bootstrap.sh --enable-auto-merge owner/myproject <PR>`. It checks the PR is BLOCKED with `ci` failing, then
   turns auto-merge on. Close that PR.
7. `/doctor` in Claude Code, then `/permissions` to confirm the deny rules loaded.

The ruleset is strict: a PR must be up to date with main to merge (`/ship` rebases first).
The check names `ci` and `lane` are the job names. The ruleset requires exactly those names, so rename both or neither.
Do not add `paths:` filters to required workflows: a skipped required check stays pending and blocks the merge.

## The daily loop
```
claude                                   # in the main checkout (stays on main)
/brief weekly standings email to league members
   ... Rich says "go"; /brief creates .claude/worktrees/<slug> and stops
cd .claude/worktrees/<slug> && claude    # one change in this worktree; at most 2-3 builders at once
   ... Rich reads the brief (goal, checks, files, lane) and says "go"
   ... Claude writes the failing test, builds on Sonnet, commits
/ship
   ... checks -> review by lane -> PR with evidence -> auto-merge (lanes 1-2) or "Rich: merge-ok?" (lane 3)
```
Rich's day: pick the next items from `docs/ROADMAP.md`, say "go" on briefs, add `merge-ok` to lane-3 PRs
after reading the one thing `/ship` flagged. Everything else merges itself or stops and asks.

## Extension point: project-specific add-ons
The kit core stays identical across projects. A project adds domain knowledge in three places, smallest first:
1. **A path-scoped rule** (`.claude/rules/<domain>.md` with `paths:` frontmatter), for rules that apply only when
   certain files are touched: migrations, tenancy, money ledger, auth. It loads only when Claude reads or edits a
   matching file, so it costs nothing elsewhere. The `reviewer` reads matching rule files as its checklist.
   Mark steps that need Rich as "ask first", and list lane-3 paths there and in `HARD_PATHS`.
2. **A project skill** (`.claude/skills/<name>/SKILL.md`), for a repeatable procedure: a deploy runbook,
   a release, a data import. Set `disable-model-invocation: true` for anything outward or irreversible,
   so it runs only when Rich types `/<name>`. Keep long reference material in files next to `SKILL.md`.
3. **A CLAUDE.md line or import**, only for facts every task needs (a glossary, the tenant model in two lines).
   Use `@path` imports sparingly: they load every session.
Rule of thumb: if it applies to under half the tasks, it is a rule file or a skill, not CLAUDE.md.
Lane-3 additions must also go into `lane.yml`'s `HARD_PATHS`, because the gate is code, not prose.

## The optional hook (one slot)
The kit ships with no hook. Formatting is a `ci` check, not an edit hook. The one slot is for a **blocking guard**
on the project's one-way failure. `.claude/hooks/one-way-guard.sh` is an example that blocks `git add/commit/push`
of personal-data or secret paths (set `GUARD`). To wire it, add to `.claude/settings.json`:
```json
"hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/one-way-guard.sh", "timeout": 10, "onFailure": "block" } ] } ] }
```
Exit code 2 blocks the call and tells Claude why. `onFailure: block` (Claude Code v2.1.295+) makes a crash or a
timeout block too; without it the guard fails open. Use the slot for whatever your project's one-way action is.

## Optional, when a project needs it
- A weekly dependency audit workflow (`pnpm audit --prod --audit-level high`) and grouped Dependabot config.
- A local runner script that calls the same steps file as CI, for the inner loop when Actions minutes are scarce. It never writes a receipt a merge trusts.

## Costs and limits to know
- On hosted runners each `lane` run bills one rounded-up minute (2-4 runs per PR). The runner choice is install step 1.
- `bypass_actors` is empty, so even admins merge through PRs. To pause the ruleset, set `enforcement` to
  `disabled` in Settings → Rules; it can't be deleted from a Claude session (denied).
- Permission rules evaluate deny, then ask, then allow; a deny always wins. They match command text, so `git -C . push` or
  `sh -c` gets past them. The ruleset is what protects `main`.
- The sandbox protects `.claude/` settings, `skills`, `agents`, `commands` and `hooks`. Updating the main checkout across
  a change to those is Rich's step; `/ship` retries a blocked rebase once, and that retry always asks.
- A session in `.claude/worktrees/<slug>` also loads the main checkout's `CLAUDE.md`, so an older copy can appear beside
  the branch's own.
- The old Stridal plugin marketplace entry is gone from this repo; it is preserved at tag `stridal-final`.
