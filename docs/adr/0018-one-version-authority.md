# ADR 0018: One version authority: the plugin release carries the engine, and the repo pins it

- **Status**: Accepted (the owner, 2026-10-31)
- **Date**: 2026-10-31
- **Tags**: plugin, framework, hooks, supply-chain
- **Source**: S19. The owner asked that binary drift be solved in the architecture. The first draft
  (a repo lock beside plugin-registered hooks) was corrected by the S19 researcher (finding 3).
  Amends ADR-0007 and ADR-0011.

## Context
**Hook drift, today.** A hook runs the files of the checkout it fires in, so an agent in an old
worktree is guarded by old rules. `worktree-hook-drift.sh` detects that and refuses, but it cannot
prevent it.

**Binary drift, under ADR-0017.** The guards live in a binary that is versioned apart from the repo:
- A binary that is **older** than the repo silently lacks a rule the repo relies on. This is the
  dangerous direction.
- A binary that is **newer** enforces rules, or reads formats, the repo has not adopted.

The first draft added a repo lock pinning the engine. But under ADR-0011 the plugin's `hooks.json`
decides which hooks fire, at the plugin's version. A lock beside it creates **two version
authorities**:
- Plugin v0.3 registers `stridal hook catch-up`, and the lock pins a v0.2 engine that lacks it.
- Failing closed then exits 2 on every Bash call, including the `git fetch` that would fix it.

## Decision
1. **One release.** A plugin release carries `hooks.json`, the skills and agents, and the engine
   for that same version. That is either the binaries themselves, or their manifest, under option
   (b) of decision 3:
   - one binary per supported GOOS/GOARCH;
   - built reproducibly (`-trimpath`, no cgo);
   - with their sha256s and a signature or provenance attestation.
   Registration and implementation cannot disagree, because they are one version. The plugin's MCP
   server is the same binary (`stridal mcp`), so the tools the model calls and the guards that hold
   it share that version too. Claude Code has no documented per-platform selection, so the plugin's
   hooks and its `.mcp.json` call the bootstrap launcher (decision 7). The launcher picks the
   binary for the running GOOS/GOARCH.
2. **The repo pins the release.** `.claude/stridal.lock` names the release and its sha256s. The pin
   is read from `origin/<main>`, so every worktree of a repo is guarded by the same release: main's.
   A repo with no `origin` (a fork, or a new project not yet pushed) reads its own `<main>`.
3. **Resolve once, never on the hot path.**
   - **Where the binaries live: option (b), the owner's decision of 2026-11-02** (see the amendment
     below; OPS-218 builds it). The plugin is served from this
     repo (`.claude-plugin/marketplace.json`, `"source": "./plugin"`), so binaries inside the plugin
     are binaries committed to git: about 5 platforms × ~10 MB on every release. The options:
     - **(a) Committed in `plugin/engine/`.** No download, but the repo grows by about 50 MB per
       release.
     - **(b) Fetched at SessionStart** into `CLAUDE_PLUGIN_DATA/engine/<sha256>/` from the release
       the lock names, verified against the lock's sha256 (and, from OPS-213, its signature) before the first exec. The
       repo stays small; the first session after an update needs network access.
     - **(c) Git LFS.**
     **Chosen: (b).** A missing or unverified binary then blocks through decision 5, and a
     cached one works offline.
   - A pin that differs from the installed plugin is a mismatch (decision 5), and its fix line names
     the plugin update.
   - A SessionStart hook verifies that binary against the lock and records its path. OPS-218 settles
     where: `CLAUDE_ENV_FILE` reaches the session's Bash (S5d, S5j), and no spike shows it reaching a
     hook. Hooks run outside the Bash sandbox (Claude Code's sandboxing docs), so the
     hook can write a build or cache directory where one is needed (the framework repo, decision 4).
     That directory goes under `CLAUDE_PLUGIN_DATA`, which survives plugin updates, unlike
     `CLAUDE_PLUGIN_ROOT`. S5a confirmed this on the Mac, and OPS-218 builds on it.
   - Each tool call's dispatcher reads only that path: no hashing and no `git` per call.
   - A lock that changes mid-session (a `git pull` of main) is re-resolved at the next SessionStart
     or by `stridal doctor`. Until then the session runs the version it verified.
4. **Two resolution modes, by subject.**
   - **Hooks** run the pinned engine.
   - **The gate** runs the engine **built from the tree under test**, so a change to a control is
     proven by the code it ships.
   - **This repo**, which builds the engine, has its hooks run the engine built from `origin/<main>`'s
     tree at SessionStart, with `GOCACHE` under `$TMPDIR`. Main only ever holds a tree that passed
     the gate. If that build still fails, SessionStart runs the last engine that verified and says so
     in context. A broken build therefore never disables the guards that protect its fix.
5. **Stand aside, or fail closed with a recovery allowlist.**
   - **A repository with no model marker** (`.claude/stridal-plugin` or `.claude/stridal-template`):
     the dispatcher stands aside (exit 0, payload unread), as `if-project.sh` does today. An enabled
     plugin's hooks fire in every repo the user opens, and unrelated repos must not break. The owner
     chose on 2026-11-02 that a marker on main's tree also counts; the wording lands with OPS-218,
     with the marker read.
   - **Every control hook entry carries `"onFailure": "block"`** and a stated timeout. Claude Code
     blocks only on exit 2 by default: a missing engine (exit 126 or 127) and a hung engine (a
     timeout) both let the call through (S1a, S1c). With `onFailure: "block"`, both block (S1d,
     S1e). The launcher therefore exits 2 for every failure it can see, and `onFailure` covers the
     ones it cannot (a crash, a hang).
   - **A marked repo** whose lock is missing, unverified or mismatched, or whose engine is missing:
     every guarded decision is refused, with one line naming the fix. The commands that repair it
     are still allowed: `git fetch`, the plugin update and `stridal doctor`.
   - **Both registration paths read the same lock:** the plugin's `hooks.json`, and, until OPS-145
     retires the copy install, a `stridal install` project's `settings.json`.
   - **A disabled plugin:** a plugin-installed repo's `.claude/settings.json` sets `enabledPlugins`
     true for the plugin. Nothing sets it today: OPS-218 builds it, through `/stridal:init` and its
     scaffold. A `stridal install` repo keeps today's `false` (`plugin/scaffold.sh`,
     `plugin-session.sh`) until OPS-145 retires that path, so the two installs never both fire.
     Project settings outrank a user's `false`, so only a deliberate opt-out in
     `settings.local.json`, or a managed setting, can turn it off. A one-line SessionStart canary,
     registered by the project rather than by the plugin, says so in context when that happens.
   - **This fail-closed rule covers controls and the dispatcher.** A judgment gate fails open
     (ADR-0020), because its subject is different. The control beside it is the floor, and this rule
     holds that floor.
6. **A fenced test override.** `STRIDAL_ENGINE=<path>` exists for fixtures. The engine ignores it
   unless HOME is a check's fixture HOME, so an agent cannot use it to pick its own guard.
7. **A bootstrap launcher stays in sh.** Something reads the lock before an engine exists. It does
   only that (read, verify, exec) and holds no rule.

## Consequences
### Positive
- Worktree drift goes away for hooks: all worktrees share main's release. `worktree-hook-drift.sh`
  retires.
- "Which version guards me" is a fact in git, as with the `toolchain` line in `go.mod`.

### Negative / trade-offs
- **A deliberately disabled plugin turns the local guards off.** That takes `settings.local.json` or
  a managed setting, because the project enables the plugin. This is an accepted loss, stated
  plainly. The canary only says so in context; it cannot block. The server-side required check (OPS-165) still
  holds the merge, and the rewrite, stash and `cd` guards are simply off until the plugin is
  re-enabled.
- **A shipped binary executes on every tool call**, a much larger trust surface than readable shell.
  Two steps, both mandatory, at different times:
  - **Integrity, from OPS-184:** every binary is verified against the lock's sha256 before its
    first exec.
  - **Authenticity, from OPS-213:** a signature or provenance attestation shows who built it.
    Whether OPS-213 lands before the launch (REL-1) or in v0.1.1, as the old roadmap
    planned for the panel's binary, is the owner's decision at Gate G. Recommended: before the
    launch, because this binary runs on every tool call of every adopter. Until it lands, a repo
    trusts the sha256s committed in its own lock, and the launch notes say so.
- **Installing or updating the plugin needs network access.** After that, nothing does.
- **A release for every change that touches a control**, in adopting projects. This repo is exempt
  through build-from-tree.
- **Windows stays WSL2** while the launcher is sh and the settings' `cmd.exe` denies remain.

## Enforcement
Built by OPS-183, OPS-184 and OPS-218, each shown failing first:
- **Engine tests**, one per case: a repo with no marker stands aside, payload unread; a missing engine, a mismatched sha256 and an unsigned engine each
  refuse a guarded decision and allow a recovery command; `STRIDAL_ENGINE` is ignored outside a
  fixture HOME; a worktree whose own lock differs from `origin/<main>`'s still resolves main's.
- **A release check:** rebuilding a tagged release reproduces its sha256s.
- **The per-call budget:** a dispatcher latency test with a 10 ms ceiling, built in OPS-185. S4
  measured the launcher plus the engine at 3.87 ms median, against 3.64 ms for a bare `sh -c`.
  A reading of OPS-184's resolved path measured more; the owner accepted that on 2026-11-02 until
  OPS-218 re-measures it, when the ceiling comes back to the owner (see the amendment below).
- **Every control hook carries `onFailure: "block"`:** the OPS-185 registration check, with S1's
  cases as its fixtures (a missing, a hung and an exit-2 engine).

## Rests on
These are the assumptions; each is accepted only on the cited result (PRAC-0023).
- A failed or hung hook blocks only with `onFailure: "block"`: S1a to S1e, **passed**.
- Latency: S4, **passed**.
- The launcher's resolved path within the 10 ms ceiling: **pending** — accepted at risk by the owner
  (2026-11-02); tested by OPS-218 (a reading of about 11 ms over a bare control on OPS-184's branch).
- Hooks can write `CLAUDE_PLUGIN_DATA` and a `GOCACHE` outside the sandbox: S5a, **passed**.
- A SessionStart command hook's `CLAUDE_ENV_FILE` reaches the session's Bash, headless and
  interactive, as decision 3's engine path needs: S5d and S5j, **passed**.
- Project `enabledPlugins` outranks a user's `false`: S5c, **passed**.
- Binaries committed under the plugin's `engine/` keep their mode and run, installed from a git
  marketplace or loaded from a release-style zip: S5f, **passed**.

## Amendment — 2026-11-02: where the binaries live, and the latency accepted

**Decision 3: option (b).** The owner chose (b): the engine is fetched at SessionStart into
`CLAUDE_PLUGIN_DATA/engine/<sha256>/`. That replaces leaving the place open as the owner's choice.

**The row split.** The owner split the work the same day: OPS-184 lands the release workflow.
OPS-218 builds the marker read, resolve-once and the trust roots, packages and fetches the engines,
and builds the `enabledPlugins` setting and the canary. OPS-224 switches both registration paths to
the launcher.

**Decision 7 stands.** The launcher stays a verify-and-exec shim (the owner, 2026-11-02). OPS-184's
branch grew it to about 470 lines of trust logic, so OPS-218's design moves that logic out.

**The per-call budget.** The owner accepted about 11 ms of launcher overhead against the 10 ms
ceiling and S4's 3.87 ms. The figures are a reading, not a final number: 14.68 ms median, 21.61 ms
p95, 11.28 ms over a bare control, over 40 runs outside the sandbox (`TestLauncherLatency`). The
acceptance holds until OPS-218 re-measures it on an idle machine, when the ceiling comes back to
the owner (the owner, 2026-11-02).

## Related
- ADR-0016, ADR-0017, ADR-0019. Amends ADR-0007 and ADR-0011. OPS-165 (server-side check).
