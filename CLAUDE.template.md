# {{PROJECT_NAME}}

{{ONE_LINE: what this is and who uses it.}}

## Stack and layout
- {{e.g. pnpm monorepo, Next.js app in apps/web, Postgres via packages/db}}
- {{where the important code lives; 3-6 lines max}}

## Commands
- Check (the one command CI runs; must exit 0 before /ship): `{{pnpm check}}`
- Single test: `{{pnpm test -- path/to/file}}` · Dev: `{{pnpm dev}}` · Install: `{{pnpm install}}`

## How we work
- Every change: `/brief` -> Rich says "go" -> build on a branch -> `/ship`. Rich chooses what ships; he does not review intermediate output.
- Write the check first. Done means: the tests exit 0, the diff touches only files listed in the brief (`.claude/bin/scope-check.sh`), and every claim in the PR cites a source (file:line, test name or command output). "Looks good", "I'm confident" and "no errors raised" are not checks.
- Return the unit, not the batch: when a check fails, fix only the failing file/test ("fix X only"), rerun only that check, then the full check. After 3 failed attempts on the same unit, stop and re-brief. Do not keep looping.
- Deterministic work is code, not a model call: merging, sorting, ranking, dedup, diffing, comparisons, counting. Write or use a script and cite its output.
- One change = one branch = one squash PR to main. Branches: `feat/`, `fix/`, `chore/`, `docs/`. Never push to main.
- One change at a time per builder, each in its own worktree (`claude --worktree <slug>`, which `/brief` tells Rich to run). On a `worktree-<slug>` branch, first run `git switch -c <type>/<slug>`. At most 2-3 builders at once, and fewer if the check suite slows or flakes under load. Never build in the main checkout; it stays on `main`.
- Do not script a rewrite of tracked source (`sed -i`, `perl -pi`, codemods); use the Edit tool.
- New logic gets a test. Fix the code, not the test, unless the test is wrong (say so in the PR).
- Architecture decisions: `docs/adr/NNNN-title.md` (copy 0000-template). Read an area's ADRs before changing it; supersede, don't contradict. There is no ADR index; list them and their status with `grep -HE '^(# |Date:)' docs/adr/*.md`.
- Next work: `docs/ROADMAP.md` (Now/Next/Done is the status). `/brief <ID>` reads the item; the PR body says `Roadmap: <ID>` and the same PR moves the item to Done.

## Merge lanes (by blast radius, not confidence)
Pick the lane in /brief; /ship labels the PR. CI's `lane` check forces lane 3 for the paths below.
1. `lane:1-contained`, reversible and contained (copy, tests, isolated covered code): auto-merge when CI is green.
2. `lane:2-wide`, reversible but wide (shared utilities, schema additions, config): CI + one `reviewer` round, then auto-merge.
3. `lane:3-hard`, hard to reverse (migrations, deletions, production data, money): never auto-merges. Reviewer runs on Opus; Rich adds `merge-ok` and merges. Claude never adds `merge-ok`.
- Lane 3 paths here: {{every one-way path: migrations/schema, outbound email/SMS/webhooks, production-data writers (import, export, sync, delete scripts), credential handling, money, deploy/infra}} (keep in sync with `HARD_PATHS` in `.github/workflows/lane.yml`)

## Ask Rich first
- Anything irreversible or outward: production deploys, production data, email/SMS to real users, DNS, billing.
- New runtime dependency, new external service, or a change to `.github/` or `.claude/`.
- {{project-specific}}

## Conventions
- {{style rules the formatter/linter does NOT already enforce; 3-5 lines max}}
- Never commit secrets. `.env*` is git-ignored. Claude's Read and Edit tools and sandboxed Bash can't read it; `git push` runs sandboxed, but `gh` needs an approved sandbox-off run, and any command run that way can read it, so keep production secrets out of a project checkout. Formatting is checked in `ci`, not by a hook.

## Guards
- One-way failures get a guard in the first design, not after a repeat: anything that cannot be undone (a commit or push of personal data or secrets, a sent message, a production write, a deletion) ships with a deny rule, a blocking check or a dry-run default before it can run once.
- Personal data lives in {{PERSONAL_DATA paths, e.g. data/resume.md, data/*.sqlite, *.xlsx}}: denied to Claude in `.claude/settings.json` and git-ignored. Never `git add -f`.
- Everything else: when the same failure happens twice, its confirmed cause becomes ONE guard: a line here, a permissions rule, or a test. Propose it in the PR that hits the repeat.
- {{YYYY-MM-DD: guard (PR #)}}

## Project rules (extension point)
Domain rules live in `.claude/rules/*.md`, path-scoped so they load only when matching files are touched.
{{Optional always-on imports, e.g. `@docs/glossary.md` (remove backticks to activate).}}
