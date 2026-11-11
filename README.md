# Stridal

A copy-in kit for building with Claude Code, without the process tax.

## What it is
Stridal is a copy-in kit for building with Claude Code: skills, agents, a permissions and sandbox config, GitHub CI and
merge controls, and doc templates. `bootstrap.sh` installs it into a project. A new project gets 38 files plus a
`.gitignore` addition (this repo tracks 55; `bootstrap.sh` in copy-only mode prints one `added:` line per file), and there is nothing to maintain between projects.

## What it does
- **One change per worktree.** The main session opens each change in its own worktree and Ghostty tab; the main checkout stays on `main`.
- **Done is a command.** Each brief lists machine-checkable done-when items, and `scope-check.sh` proves the diff touches only the files in the brief.
- **Merge lanes by blast radius.** Reversible, contained changes auto-merge; hard-to-reverse ones wait for the owner.
- **GitHub enforces the merge.** A ruleset on `main` requires a PR, squash only, and the `ci` and `lane` checks.
- **Lessons become guards.** When something fails the same way twice, its confirmed cause becomes one rule, line or test.

## How it works
```
claude                                   # in the main checkout (stays on main)
/brief weekly standings email to league members
   ... no second "go": with no open questions /brief writes the brief to .claude/review/spawn-<slug>.md and runs
       session.sh open ("/brief plan only ..." stops at the brief until you say "go")
   ... a worker opens in a new Ghostty tab on feat/<slug> (at most 2-3 builders at once), starts in auto mode,
       writes the failing test, builds on Sonnet, commits, and reports back to the main session
/ship <slug>                             # you type this in the main window; session.sh send types /ship into the worker's tab
/ship                                    # or you type this in the worker's tab
   ... checks -> review by lane -> PR with evidence -> auto-merge (lanes 1-2) or "merge-ok?" (lane 3)
/merge <PR#>                             # lane 3 only; works from the main window
/land <slug>                             # back in the main session: syncs main, then closes the tab and removes worktree and branch
```
Every session shows a one-line status bar (`.claude/statusline.sh`): `<project> · <branch> <●|✓> <↑a↓b> · <N>% ctx · <model>`, plus `workers: N` in the main checkout while worker tabs are open. Claude Code picks it up in a fresh session.

Requirement: macOS, and Ghostty running with exactly one instance and a window. Without it `session.sh` refuses and
`/brief` falls back to the older route: it fetches, then you run `claude --worktree <slug>` and paste the brief.
Workers started by `session.sh` run in auto mode (`--permission-mode auto`). If a worker never reports and
`ListAgents` shows it stuck, look for a trust or permission prompt in its tab.

Your day: pick the next items from `docs/ROADMAP.md`, run `/brief` on them, type `/ship <slug>` in the main window (or `/ship` in the worker's tab), type
`/merge <PR#>` for lane-3 PRs after reading the one thing `/ship` flagged, and `/land <slug>` once merged.
Everything else merges itself or stops and asks.

## Install into a new project (under 30 minutes)
`bootstrap.sh` is the only real install route. GitHub's "Use this template" skips the ruleset, runner choice and
labels, and copies this repo's own `CLAUDE.md` and `ci.yml` instead of the templates.

1. **Choose the runner.** `hosted` bills Actions minutes (`lane` ~1 minute per run, 4-8 runs per PR since it listens to two events (ADR-0002), plus every
   `ci` run). If this account has ever run out of minutes or paused `pull_request` CI, choose `self-hosted`
   (a machine you own that is on while you work; never a production box).
2. `./bootstrap.sh ~/code/myproject <hosted|self-hosted> owner/myproject` (needs `gh auth login` as a repo admin;
   without `owner/repo` it copies files only). It posts the ruleset first, restores your previous merge
   settings if that fails, and leaves auto-merge OFF. Rulesets on a **private** repo need GitHub Pro or Team.
3. Fill the `{{placeholders}}`: `CLAUDE.md` (stack, check command, lane-3 paths, personal-data paths, and `Approver:` in
   the `## Dispatcher` block, which the kit PR needs because it touches `.github/`; the rest of that block waits for the
   first `/dispatch`), `ci.yml`
   (the same check command, including the format check), `HARD_PATHS` in `lane.yml` (every one-way path: schema,
   outbound email/messages, production-data writers, credential handling, deploy), and `PERSONAL_DATA` in
   `.claude/settings.json` and `.gitignore`. Add package registries to `sandbox.network.allowedDomains`.
   For a pnpm project, add `"packageManager": "pnpm@9.15.4"` to `package.json` and commit `pnpm-lock.yaml`, because the
   CI template's `pnpm/action-setup@v6` has no `version` input.
4. If the project's one-way failure is a git command, wire the optional hook (below) now, not after it happens.
5. Open one PR with the kit and label it `lane:3-hard` (it touches `.github/` and `.claude/settings.json`). `lane` runs
   from the PR's own copy this once, since main has none yet (ADR-0002). Add `merge-ok` yourself in GitHub's web UI
   (the `Approver:` in `CLAUDE.md` must be your login) and merge by hand when `ci` and `lane` are green. Time `ci`; over
   10 minutes, move slow suites to a nightly workflow.
6. **Prove a red PR can't merge**: open a PR with a deliberately failing test; when `ci` is red run
   `./bootstrap.sh --enable-auto-merge owner/myproject <PR>`. It checks the PR is BLOCKED with `ci` failing, then
   turns auto-merge on. Close that PR.
7. `/doctor` in Claude Code, then `/permissions` to confirm the deny rules loaded.

The ruleset is strict: a PR must be up to date with main to merge (`/ship` rebases first).
The check names `ci` and `lane` are the job names. The ruleset requires exactly those names, so rename both or neither.
Do not add `paths:` filters to required workflows: a skipped required check stays pending and blocks the merge.

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
   | `lane:3-hard` | hard to reverse: migrations, deletions, production data, money | never auto-merges; the owner adds `merge-ok` and merges, by hand or with `/merge <PR#>` |
   The `lane` CI check is code: it forces lane 3 for `HARD_PATHS` and fails lane 3 until `merge-ok` is on the PR.
   New commits after `merge-ok` remove the label. Any Claude command containing `merge-ok` stops at a permission prompt; `/merge` is the intended way to add it, and outside it the prompt is the owner's chance to say no.
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
9. **One change at a time per builder.** Each builder works in its own worktree (`/brief` opens it in a Ghostty tab
   with `session.sh`, or you run `claude --worktree <slug>`); the main checkout stays on `main`. Run at most 2-3 builders at once, fewer if the check suite slows or
   flakes under load. Never "several in parallel".
10. **The owner's human steps:** choosing what ships (running `/brief` is the go; `plan only` stops at the brief), typing `/ship`, which Claude can't
   start itself, and approving lane-3 merges. The owner does not review intermediate output.

## Files
| Path | What it does |
|---|---|
| `CLAUDE.template.md` | ~60-line template, installed as `CLAUDE.md`: commands, how we work, the `## Dispatcher` block, merge lanes, ask-first list, guards (one-way + learned), extension point |
| `CLAUDE.md` | This repo's own, filled in. Not copied to new projects |
| `.claude/settings.json` | Sonnet + medium effort; `acceptEdits`; deny list (secrets, `--admin` merges, pushes to main, ruleset edits); ask list (`merge-ok`, `gh label`, unsandboxed retries); Bash sandbox with GitHub/npm network |
| `.claude/hooks/one-way-guard.sh` | OPTIONAL, not wired by default. The one hook slot, for a blocking guard on the project's one-way failure (example: blocks `git add/commit/push` of personal-data or secret paths) |
| `.claude/bin/scope-check.sh`, `.claude/bin/test-scope-check.sh` | Deterministic check that the branch touches only the brief's files, or, with `--footprint <issue-body-file>`, the issue's `Footprint:` paths (read through `dispatch-next.sh --footprint-of`; no Footprint means no scope check). A dispatcher worker runs it, the lane's reviewer and `check-evidence.sh` before it opens its PR (`worker-contract.md`) |
| `.claude/bin/session.sh` | `open <type> <slug> --report-to <name>` makes `.claude/worktrees/<slug>` on `<type>/<slug>` from `origin/main` and opens a Ghostty tab running Claude on `.claude/review/spawn-<slug>.md`; `send <slug> ship` types `/ship` into that worker's tab (the only text it can type); `sync` runs `git pull --ff-only` in the main checkout and nothing else; `close <slug>` ends it, and still finishes if the worktree and branch are already gone. Workers start through a login shell (`/bin/zsh -lc`) so they get `gh` and `shellcheck` on PATH. `/brief`, `/ship <slug>` and `/land` call it. macOS and Ghostty only |
| `.claude/statusline.sh` | The status line, wired by `statusLine` in `settings.json`: project, branch, `●` dirty or `✓` clean, `↑a↓b` against upstream, context %, model, and `workers: N` (open `spawn/*.term` records) in the main checkout. POSIX sh, `jq` and `git` only, no network; prints something and exits 0 on bad input |
| `.claude/bin/kit-check.sh` | This repo's own check: shellcheck, JSON, and `bootstrap.sh` in copy-only mode. Not copied to new projects |
| `.claude/agents/reviewer.md` | Fresh-context reviewer with no shell: one round, blocking findings with file:line evidence, lane check, decisions and assumptions check. Sonnet by default, Opus for lane 3 |
| `.claude/agents/researcher.md` | Read-only research agent (no Edit, Write or Bash); answers with sources |
| `.claude/skills/brief/SKILL.md` | `/brief <task>`: Opus writes goal, machine-checkable done-when, Files, lane, plan, decisions, assumptions, then opens a worker tab with `session.sh` itself when there are no open questions (or falls back to `claude --worktree`). `plan only` stops at the brief |
| `.claude/skills/land/SKILL.md` | `/land <slug> [--abandon]`: after the merge, syncs main with `session.sh sync` (so the `session.sh` it runs is current), then closes the worker tab and removes its worktree and branch. User-only |
| `.claude/skills/ship/SKILL.md` | `/ship` (or `/ship <slug>` from the main window, which sends it to that worker): run the checks, review by lane, rebase, labeled PR with evidence, auto-merge for lanes 1-2 |
| `.claude/skills/merge/SKILL.md` | `/merge <PR#>`: the owner's lane 3 green light. Adds `merge-ok` (one permission prompt), waits for `lane`, squash-merges. User-only |
| `.claude/rules/EXAMPLE-migrations.md.example` | Example path-scoped domain rule (inactive until renamed to `.md`) |
| `.github/ci.template.yml` | Installed as `.github/workflows/ci.yml`, the required `ci` check: one job, 10-minute timeout, cancels superseded runs, gitleaks secret scan, then your stack's check |
| `.github/workflows/ci.yml` | This repo's own `ci`: gitleaks, then `kit-check.sh`. Not copied to new projects |
| `.github/workflows/lane.yml` | The required `lane` check (merge-lane gate, ~10 s). A `pull_request_target` workflow, so main's rules judge every PR (ADR-0002); calls `.github/lane/lane.sh` |
| `.github/lane/lane.sh`, `.github/lane/test.sh` | The lane decision as a pure function of env, and its self-test. `merge-ok` counts only when the latest label event's actor is the `Approver:` in `CLAUDE.md`'s `## Dispatcher` block, so the agents' machine user can never approve (ADR-0003, ADR-0004) |
| `.claude/skills/dispatch/SKILL.md`, `worker-contract.md` | `/dispatch`: works the GitHub Project's Now column up to `max_workers` issues, one worker session each (ADR-0001, ADR-0005, ADR-0006); the contract is what each worker is told. Needs the machine user set up first (`docs/runbooks/agent-token.md`) |
| `.claude/bin/dispatch.sh`, `.claude/bin/test-launcher.sh` | One command to start the dispatcher: from the main checkout or a worktree it checks `main`, the `Name:`, that `dispatch-<key>` isn't already running, and that Agent isn't Approver, then runs `as-agent.sh <Agent keychain> claude --name dispatch-<key> -- "/loop /dispatch"`. `bootstrap.sh` prints (never writes) an alias for it |
| `docs/runbooks/agent-token.md` | The machine user and its token: account and 2FA, least access, classic-token scopes and why, Keychain, the `Agent:` lines, expiry warning and rotation |
| `.claude/bin/dispatch-next.sh`, `as-agent.sh`, `token-expiry.sh` | Pick the next Now item (and a footprint-safe second), start a command with the machine user's token from the Keychain, and warn before that token expires |
| `.claude/bin/test-session.sh`, `test-dispatch.sh`, `test-token-expiry.sh` | Self-tests for `session.sh` and the three dispatcher scripts. A new project's `ci` runs them, with `test-launcher.sh`, `test-scope-check.sh` and `.github/lane/test.sh` |
| `.claude/hooks/notify-waiting.sh` | Wired to the `permission_prompt` notification: marks a worker as waiting on a prompt so the dispatcher can tell the owner |
| `.github/ruleset-main.json` | Ruleset for the default branch: PR required (0 approvals), squash only, checks `ci` + `lane`, no deletion, no force push, no bypass actors |
| `.github/pull_request_template.md` | `Why:` and `Roadmap:` lines (lane.yml fails a PR with no real `Why:`), then what/why, lane, done-when evidence, decisions & assumptions with sources, review, guard |
| `docs/ROADMAP.template.md` | Blank roadmap, installed as `docs/ROADMAP.md`: items with ID, Why, Done when and Links, in three sections: Now (max 3), Next, Done (last 10) |
| `docs/ROADMAP.md` | This repo's own roadmap. Not copied to new projects |
| `docs/adr/0000-template.md` | Short ADR, only for decisions expensive to reverse |
| `docs/adr/0001-*.md` to `0006-*.md` | This repo's decisions for the dispatcher: backlog is the Project's Now column, lane judged by the base branch, `merge-ok` withheld from Claude, agents act as a machine user, two workers on declared footprints, session names carry a repo key. Not copied to new projects |
| `docs/ARCHITECTURE.md` | Live doc, installed unfilled: components, data flow, constraints. First line marks it a template until filled in |
| `docs/RISKS.md` | Live doc, installed unfilled: risk table (ID, Risk, Impact, Likelihood, Mitigation, Owner, Status) with one example row |
| `docs/templates/DATA-MODEL.md` | Template: entity-relationship diagram as a mermaid block |
| `docs/templates/API.md` | Template: conventions and an endpoint table |
| `docs/templates/INVENTORY.md` | Template: secret names and services/infra, names and locations only. Keep out of public repos |
| `docs/templates/runbook.md` | Template: Purpose, When to use, Prereqs, Steps, Verify, Rollback, Last checked |
| `docs/templates/spec.md` | Template: Feature, Problem, Must do, Must not do, Acceptance checks, Roadmap IDs, Related ADRs |
| `gitignore.append` | Ignores `.claude/worktrees/`, `.claude/review/`, local settings, `.env*`, `PERSONAL_DATA/` |
| `.gitattributes` | LF line endings on every OS, for this repo. Not copied to new projects |
| `bootstrap.sh` | Copies the files (never overwrites), applies the runner choice, sets squash commits to carry the PR title and body, posts the ruleset first (rolls back on failure), labels; enables auto-merge only after a red PR was refused |

Not in the kit on purpose: session numbers, journals, session-close PRs, local CI receipts, merge-guard
wrappers, a review loop, a roadmap queue engine, practice records, bot fleets.
Claude Code already ships worktrees (`claude --worktree`), `/plan` mode, `/code-review`, subagents,
permissions and a sandbox. GitHub already ships rulesets and auto-merge.

## Extension point: project-specific add-ons
The kit core stays identical across projects. A project adds domain knowledge in three places, smallest first:
1. **A path-scoped rule** (`.claude/rules/<domain>.md` with `paths:` frontmatter), for rules that apply only when
   certain files are touched: migrations, tenancy, money ledger, auth. It loads only when Claude reads or edits a
   matching file, so it costs nothing elsewhere. The `reviewer` reads matching rule files as its checklist.
   Mark steps that need the owner as "ask first", and list lane-3 paths there and in `HARD_PATHS`.
2. **A project skill** (`.claude/skills/<name>/SKILL.md`), for a repeatable procedure: a deploy runbook,
   a release, a data import. Set `disable-model-invocation: true` for anything outward or irreversible,
   so it runs only when you type `/<name>`. Keep long reference material in files next to `SKILL.md`.
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
- On hosted runners each `lane` run bills one rounded-up minute (4-8 runs per PR: it runs on both `pull_request` and `pull_request_target`, ADR-0002). The runner choice is install step 1.
- `bypass_actors` is empty, so even admins merge through PRs. To pause the ruleset, set `enforcement` to
  `disabled` in Settings → Rules; it can't be deleted from a Claude session (denied).
- Permission rules evaluate deny, then ask, then allow; a deny always wins. They match command text, so `git -C . push` or
  `sh -c` gets past them. The ruleset is what protects `main`.
- The sandbox protects `.claude/` settings, `skills`, `agents`, `commands` and `hooks`, and `.git/config`. That is why
  `/brief` opens workers with `session.sh` (or `claude --worktree`): `git worktree add` fails under the sandbox. A `worktree-<slug>` branch stays behind
  locally after `git switch -c`; it is never pushed. Updating the main checkout across a change to protected paths is
  the owner's step, and `/ship` runs a rebase over them unsandboxed, which always asks.
- A session in `.claude/worktrees/<slug>` also loads the main checkout's `CLAUDE.md`, so an older copy can appear beside
  the branch's own.

## History
The earlier project is preserved at tag `stridal-final`.
