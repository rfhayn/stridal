# Stridal

A copy-in kit for building with Claude Code: `bootstrap.sh` installs it into a project. The previous project is at tag `stridal-final`.

## Stack and layout
- POSIX-style shell, JSON, Markdown and GitHub Actions. There is no application code.
- This repo is both the kit and a project using it. `CLAUDE.template.md` and `.github/ci.template.yml` are what new projects receive, as `CLAUDE.md` and `.github/workflows/ci.yml`. The `CLAUDE.md` and `ci.yml` here are this repo's own.
- Everything else in `bootstrap.sh`'s file list ships as it is here, so a change to it reaches every new project.

## Commands
- Check (the one command CI runs; must exit 0 before the PR): `.claude/bin/kit-check.sh`
- It needs `shellcheck` and `jq`. CI also runs the gitleaks scan.

## How we work
- Every change: a GitHub issue with a "Done when" -> the Now column -> `.claude/bin/dispatch.sh` -> a worker's PR (ADR-0001). The dispatcher is the one loop; there are no hand-run skills for it.
- Write the check first. Done means: the check exits 0, the diff touches only the files in the issue's Footprint or Files (`.claude/bin/scope-check.sh`), and every claim in the PR cites a source. "Looks good" is not a check.
- One change = one branch = one squash PR to main. Branches: `feat/`, `fix/`, `chore/`, `docs/`. Never push to main. Build in a worktree (`claude --worktree <slug>`); the main checkout stays on `main`. On a `worktree-<slug>` branch, first run `git switch -c <type>/<slug>`.
- Do not script a rewrite of tracked source (`sed -i`, `perl -pi`, codemods); use the Edit tool.

## Dispatcher
The Now column of the GitHub Project is the backlog (ADR-0001). `/dispatch` works it; the scripts read these lines.
- Name: stridal · Project: rfhayn #4 · Approver: rfhayn · max_workers: 1
- Deploy: true · Gates: .claude/bin/kit-check.sh
- Agent: rfhayn-bot · Agent keychain: stridal-github-bot
- Start: `.claude/bin/dispatch.sh` (checks, then runs `as-agent.sh <Agent keychain> claude --name dispatch-<Name> -- "/loop /dispatch"`)
- `Deploy: true` is a documented no-op: nothing here deploys. No `Footprint areas`, so one worker at a time (ADR-0005).

## Merge lanes
Almost every change here touches `.claude/settings.json` or `.github/`, which `lane.yml` forces to lane 3: the owner adds `merge-ok` in GitHub's web UI and merges. Claude never adds it: Bash commands containing it are denied (ADR-0003).

## Ask the owner first
- Anything irreversible or outward: GitHub settings, rulesets, releases.
- A new dependency in `ci`, or a change to what new projects receive that alters their behaviour.

## Guards
- Never commit secrets. `.env*` is git-ignored. Claude's Read and Edit tools and sandboxed Bash can't read it; `git push` runs sandboxed. `gh` is in `sandbox.excludedCommands`, so a plain `gh` call (no pipe, no redirect, no `cd`, no command substitution) runs unsandboxed under the allow rules and can read it, and so can any approved retry with the sandbox disabled; keep production secrets out of a project checkout.
- gitleaks exits 0 on a commit range git can't resolve. `ci` verifies the range first; keep that check.
- The deny rules match command text, so they are not a boundary. The GitHub ruleset is what protects `main`.
