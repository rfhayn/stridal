# Lean Claude Code kit

A copy-in kit for building with Claude Code: `bootstrap.sh` installs it into a project. Formerly Stridal; the old project is at tag `stridal-final`.

## Stack and layout
- POSIX-style shell, JSON, Markdown and GitHub Actions. There is no application code.
- This repo is both the kit and a project using it. `CLAUDE.template.md` and `.github/ci.template.yml` are what new projects receive, as `CLAUDE.md` and `.github/workflows/ci.yml`. The `CLAUDE.md` and `ci.yml` here are this repo's own.
- Everything else in `bootstrap.sh`'s file list ships as it is here, so a change to it reaches every new project.

## Commands
- Check (the one command CI runs; must exit 0 before /ship): `.claude/bin/kit-check.sh`
- It needs `shellcheck` and `jq`. CI also runs the gitleaks scan.

## How we work
- Every change: `/brief` -> Rich says "go" -> build on a branch -> Rich runs `/ship`.
- Write the check first. Done means: the check exits 0, the diff touches only the files in the brief (`.claude/bin/scope-check.sh`), and every claim in the PR cites a source. "Looks good" is not a check.
- One change = one branch = one squash PR to main. Branches: `feat/`, `fix/`, `chore/`, `docs/`. Never push to main. Build in a worktree (`claude --worktree <slug>`); the main checkout stays on `main`. On a `worktree-<slug>` branch, first run `git switch -c <type>/<slug>`.
- Do not script a rewrite of tracked source (`sed -i`, `perl -pi`, codemods); use the Edit tool.

## Merge lanes
Almost every change here touches `.claude/settings.json` or `.github/`, which `lane.yml` forces to lane 3: Rich adds `merge-ok` and merges. Claude never adds `merge-ok`.

## Ask Rich first
- Anything irreversible or outward: GitHub settings, rulesets, releases.
- A new dependency in `ci`, or a change to what new projects receive that alters their behaviour.

## Guards
- Never commit secrets. `.env*` is git-ignored. Claude's Read and Edit tools and sandboxed Bash can't read it; commands excluded from the sandbox (`gh`, `git push`, `docker`) can, so keep production secrets out of a project checkout.
- gitleaks exits 0 on a commit range git can't resolve. `ci` verifies the range first; keep that check.
- The deny rules match command text, so they are not a boundary. The GitHub ruleset is what protects `main`.
