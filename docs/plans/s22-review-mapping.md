# Mapping the three reviews of 2026-11-02 onto the roadmap

A proposal for the owner, not a decision. Three read-only reviews of `main` (architecture and plan,
security, code quality) ran on 2026-11-02, and the owner turned them into nine work items. This
page checks their claims against the repository, says where this session disagrees, and maps each
item onto roadmap rows. Nothing here changes a row. Rows and ADR amendments follow in a normal PR
once the owner has decided the questions below.

The reviews read `main` at `01571ef9`. S22's Batch B was unmerged at the time, so they did not see
it. Row ids from OPS-219 on assume `ops/s22-records` lands first (it adds OPS-217 and OPS-218).

## Verified

| Claim | Result |
|---|---|
| About 32-34k lines of shell plus 2k of awk | True: 34,494 lines under `template/`, 1,977 of them awk |
| Copied three times | True: `run-local.sh` is byte-identical in all three places; `plugin/` is generated |
| `framework/internal/engine` is about 540 lines of launcher and lock | True: 540 production lines |
| 56 checks, about 16k lines | True: 56 scripts, 16,148 lines |
| 57 queued and 9 planned rows | True |
| `project.conf` is run as shell by hooks and the status line | True: `lib/conf.sh:81`, reached by six hooks and `statusline.sh` |
| `FORMAT_CMD`, `ROADMAP_PARSER`, `ROADMAP_NORMALIZER`, `BATCH_REGENERATE` go through a shell | True: `format.sh`, `conf.sh:113-117`, `batch.sh:60` |
| A sandboxed session can write the files hooks then run | True, and wider than the review could show: a sandboxed Bash here wrote `.claude/project.conf` in the main checkout, and `project.conf`, `hooks/`, `settings.json` and `bin/` in a lane's worktree. `.claude/agents/` is refused |
| `excludedCommands` lists docker, git, gh, tmux, stridal | True (`template/.claude/settings.json`), and S5h shows the list is not honoured on 2.1.316 |
| `pattern-kill-path.sh` prepends a directory to `PATH` | True; the repository's own only on a copy install |
| `govulncheck@latest` | True: `dependency-audit.yml:37` |
| #375's cause | True: `git init --bare` leaves HEAD on the default branch, the fixture pushes `main`, then copies into the clone (`health-lines.sh:265,352-353`). Not yet shown failing here |
| Two `time.Sleep(2 * time.Second)` in `stall_integration_test.go` | True: lines 704 and 821 |
| README describes the old install, no `CONTRIBUTING.md`, `SECURITY.md` or changelog | True: `README.md:20-23,59` |
| `PRD-tui.md` still says S26-S28 | True |

## Stale or wrong

| Claim | What the repository says |
|---|---|
| The SIGPIPE flake is open | Fixed on `main` by #384: `run-local.sh` drains the pipe, and a check holds it. What remains is the class: any later early-exiting reader in a `pipefail` script. So OPS-187's reason is removing the class, not stopping a live flake |
| Ubuntu "hit closed #234 again on 11/1" because of unscaled sleeps | That failure was #382, in `TestStallMergedPRNotPushedOnAnOldNone`, a test-only race fixed in #384. The two sleeps are in other tests. Worth fixing, but nothing ties them to that failure |
| Stock macOS has no `readlink -f`, so `change-guard.sh:271-274` lets a link through | Not on this Mac: `/usr/bin/readlink -f` on 27.2 resolves the link, so the path is refused. macOS added it in 12.3 (from memory, not checked here). The fallback only matters on older systems. Keep the case for `stridal merge`, at low priority |
| The team-queue listing ships to adopters | It does not: it lives in `.claude/local/`. Only `.github/ISSUE_TEMPLATE/` and a check's mention remain |
| OPS-165's ruleset is ready and unticked; the marker question is open | Both done on 2026-11-02. The ticks are on `ops/s22-records` |
| Resolve-once, marker read from main and least-privilege release jobs are still to do | All built, on the unmerged `ops/ops-184-engine-release` |
| #25 is closed unmerged (REL-1's cell) | It is still open. The row is stale; closing it is the owner's |

## Where this session disagrees

1. **Item 7 cannot wait until after item 6.** The list puts the release last, but a Go lease, gate or merge needs a binary every project can reach. Today `checks/no-stridal.sh` proves the gate runs with no `stridal` on `PATH`, and the plugin carries no engine. So the delivery half of item 7 (release, fetch, plugin-only install) has to come before the ports, as the architecture review also orders it. The hook switch-on and signing can follow.
2. **Item 3 closes less than it reads on this repository.** Parsing `project.conf` as data closes the plugin path. On a copy install the hook scripts are the branch's own files, and a sandboxed lane can rewrite them, so this repo stays exposed until OPS-145. It is still the right next row. It should sit ahead of OPS-218, the switch-on: OPS-184 as now split registers nothing.
3. **Denying the gh credential file would break sandboxed `gh`.** `checks/settings.sh:14-16` keeps `~/.config/gh` readable because `gh` reads `hosts.yml` to find its keyring account. Deny `~/.git-credentials`, `~/.netrc` and `~/.npmrc` as asked. For gh, check that no token sits in `hosts.yml` instead, and deny only the Read tool.
4. **A sandbox write-deny on `.claude/hooks/` blocks this repo's own lanes until OPS-145.** Lanes sync through `stridal update`, which writes there. Either land the deny with OPS-145, or accept that the orchestrator applies those writes.
5. **Two of the security review's fixes do not work as written.** `allowUnsandboxedCommands: false` would leave nothing able to run a gate until OPS-216's code lands, so it must follow it. An `fexecve` of the hashed file is not available to a POSIX sh launcher; the content-addressed copy is the mitigation available there. `enableWeakerNetworkIsolation` has no recorded reason, but from memory it is what lets Go tools such as `gh` reach macOS's TLS trust service; test before removing it.
6. **"The 56 checks don't ship" is too broad.** Some are an adopter's own controls (`settings`, `hooks`, `scenarios`), and ADR-0019 makes them the oracle for each port. Decide each one through OPS-208's fate list rather than removing the set. The journal fold is the clear case.
7. **The shim claim collides with the launcher on OPS-184's branch.** Item 7 says the launcher stays a verify-and-exec shim, and ADR-0018 decision 7 says the same. It has grown from 192 to 475 lines of trust logic on that branch. Something must check the trust roots before any binary is trusted, so it cannot all move into the engine. That is the owner's first question below.
8. **Cancelling PANEL-25 needs ADR-0022's text changed.** The ADR says the row stays until the spike. Cancelling is reasonable, because option B is chosen and the row is only worth doing under option A. Amend the ADR in the same PR and archive `changes/panel-25-idle-cost/`.

## Mapping

| Item | Existing rows | New or changed |
|---|---|---|
| 1. Re-scope v0.1.0 | REL-1, session plan, Gates E-H; PANEL-25 cancelled | ADR-0011 and ADR-0022 amendments. Phases 5 and 7 and the terminal UI move to a v0.2 milestone (ST-15 to ST-19, PANEL-50, 56, 61, 62, 64, 66, OPS-211). Question 3 covers Phase 3 |
| 2. Trustworthy suite | OPS-28 loses its REL-1 dependency and moves up, after the fixes | **OPS-221** #375, #374 items 2 and 3, the two sleeps. macOS on PRs stays not required by the ruleset |
| 3. `project.conf` as data | None owns it | **OPS-219**, risk high, ahead of OPS-218: parse as data, argv with no shell, refuse a `guard.d` script that differs from `origin/main` |
| 4. Sandbox | OPS-216 splits; OPS-217 is the docs half; OPS-218's M2 moves here | **OPS-220**: drop the exclusions, deny credentials, the no-write test. OPS-216 keeps making the gate run sandboxed, moved up from Phase 8 |
| 5. Parity harness | OPS-185 | ADR-0019 amendment: reason codes, not byte-exact stderr (it says byte for byte today). OPS-185 no longer needs OPS-218 for the extraction |
| 6. Port order | OPS-187, OPS-209, OPS-162, OPS-163, OPS-188, OPS-190, OPS-195, OPS-207, OPS-208 | ADR-0017 amendment: lease, gate, merge. OPS-186's shims come only when a caller needs one, so OPS-162, 187, 188, 190 and 195 lose that dependency. OPS-164 is cancelled into OPS-162: `merge-reader.awk` is frozen, not ported, which ADR-0019 also has to allow. OPS-195 follows OPS-190. The SIGPIPE class folds into OPS-187, and that row gains the clean-room step from OPS-209 |
| 7. Only the pinned release runs | OPS-184, OPS-218, OPS-213 (Phase 9 to v0.1.0), OPS-145 (PATH, on a copy install) | **OPS-222**: drift check fails closed on dirty or uncomparable hook files, with no-origin still allowed; `govulncheck` pinned. Attestation joins OPS-184's workflow |
| 8. Fail-closed guards | OPS-214 (merged), OPS-185, OPS-202 | Docs: the ruleset is the boundary, and adopters get its exact payload. No new row |
| 9. Split tooling from product | OPS-202, OPS-208, OPS-191, OPS-113, OPS-117, REL-1 | **OPS-223**: browser-freeze check, `CONTRIBUTING.md`, the README line, the OPS-113 and OPS-117 cells, the no-`stridal` proof and double pass deleted once the launcher is live |

## Proposed order

1. This mapping, then the rows and ADR amendments (item 1 and the port-order amendments).
2. OPS-221, the suite. OPS-219, `project.conf` as data. OPS-220, the sandbox settings.
3. OPS-184 and OPS-201, shaped by question 1. OPS-213's attestation. OPS-218 as far as a release, a fetch and the first lock.
4. OPS-145 and OPS-202, one install. OPS-216, the gate in the sandbox. OPS-28.
5. OPS-185's harness. OPS-187, OPS-209, OPS-162.
6. Tag v0.1.0 (REL-1), with the hook switch-on complete. OPS-188, OPS-190, OPS-195 and the rest of the port go on to v0.2.

## Questions for the owner

1. **OPS-184's launcher.** It is 475 lines on an unmerged branch, and you want a shim. Hold the branch and move `--resolve` into OPS-218 with a design that keeps the launcher small; or land it inactive and shrink it later. Recommended: hold it. Land the release workflow, the `tar` fix and the marker change, and keep the branch for reference.
2. **Batch B while this is open.** You asked for no code changes until this merges. Recommended: land `ops/s22-records` and OPS-217 first, as one batch, because this page's ids and the corrected sandbox statements rest on them, and hold OPS-184 and OPS-201.
3. **Phase 3's MCP server and the JSON roadmap.** Your floor leaves them out, and items 1 and 6 do not say where they go. Recommended: v0.2, with OPS-195 after the libraries as item 6 says.
4. **Order.** Accept the release's delivery half ahead of the ports (disagreement 1), or say how the ports reach adopters without it.
5. **Lanes without the panel.** Moving the terminal UI leaves the browser panel frozen and shipped, and you do not run it. Recommended: v0.1.0 documents lanes through `stridal lane` and git worktrees, and leaves the browser panel undocumented.

## Publishing note

This repository is public, and several findings here are unfixed. This page names each class and its
owner, but leaves out the exact steps and the reviews' fixtures. The reviews themselves stay off the
repository until OPS-219 and OPS-220 land.
