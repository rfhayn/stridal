# S19 spikes: what the engine architecture rests on, measured (2026-10-31)

Claude Code 2.1.316 and Go 1.26.1, on the owner's Mac, inside the Seatbelt sandbox. Every run
used `--setting-sources project`. The scratch repos were under `$TMPDIR/spikes`. Landed in
`docs/plans/` with OPS-182; ADR-0016 to ADR-0022 cite these results by number.

| # | Question | Result | Consequence |
|---|---|---|---|
| S1a | A PreToolUse command hook execs a missing binary (exit 126 or 127) | **The call ran.** Logged as an error only | A broken engine fails open by default |
| S1b | The hook exits 2 | **Blocked**, with stderr shown to Claude | Exit 2 is the only default block |
| S1c | The hook hangs past `"timeout": 5` | **The call ran** after the timeout | A hung engine fails open by default |
| S1d | S1c plus `"onFailure": "block"` | **Blocked**: "timed out; blocking because onFailure is "block"" | Every control hook carries `onFailure: "block"` (ADR-0018) |
| S1e | S1a plus `"onFailure": "block"` | **Blocked** | as S1d |
| S2a | Plugin MCP tool, headless, no allow rule | **Denied**, with no prompt: listed in `permission_denials` | The template allows the engine's servers explicitly (ADR-0017) |
| S2b | Allow rule `mcp__plugin_<plugin>_<server>__*` | **Works**; the tool ran in 10 ms; the name is `mcp__plugin_spikeplug_engine-read__ping` | The wildcard per server is the allow rule |
| S2c | The server binary exits at once | **The tool silently disappears**; the run exits 0 | No control may live on MCP (ADR-0016) |
| S2d | An `mcp_tool` hook at SessionStart | **Refused**: "not available for the 'SessionStart' hook event (no MCP client context)" | No `mcp_tool` hooks in the design (ADR-0017) |
| S2e | An `mcp_tool` hook at UserPromptSubmit | It ran, but **its output never reached the model**; a command hook's output did | as S2d; context comes from command hooks |
| S2f | Binary under `engine/`, not `bin/` | **Works**; the server connects in 16–30 ms | `engine/` is the binary directory (claude.ai and Cowork refuse a top-level `bin/`) |
| S3a | `prompt` hook, PreToolUse, ok:false | The call was blocked, and **the whole session ended** (`terminal_reason: hook_stopped`) | No prompt hooks on PreToolUse in hands-off runs (ADR-0020) |
| S3b | `prompt` hook, Stop, ok:false | **The session continued**, with the reason as its next instruction; the second Stop saw `stop_hook_active` and ended | A Stop gate is a self-correction nudge, bounded to one loop |
| S3c | `agent` hook, PreToolUse, ok:false | **Only the call was blocked**; Claude went on; 2.2 s | Tool-call gates are agent hooks (ADR-0020) |
| S4 | Per-call cost: sh launcher exec'ing the Go engine | Median 3.87 ms, against 3.64 ms for a bare `sh -c`; Claude Code's own hook wall time was 19–26 ms | Latency is not a risk; one dispatcher per event is enough |

**Not tested here.** Nested sessions inherit this session's sandbox, so these wait for Gate A on
the Mac, outside the sandbox (OPS-199):
- whether hooks write outside the sandbox (`CLAUDE_PLUGIN_DATA`, a SessionStart command hook's
  session env);
- whether a panel lane reaches plugin MCP tools;
- whether a cloud Claude Code session runs the plugin's engine.

**Out of scope.** Other clients (Cursor): the design covers Claude Code only (the owner,
2026-10-31; ADR-0016's *Rests on*), so OPS-199 does not test them.

## OPS-199: records for ADR-0021 (2026-11-01)

Claude Code 2.1.316. These two are records, not sandbox-bound probes, so they were taken in the
session itself; ADR-0021's *Rests on* cites them (the owner chose "record and cite", 2026-11-01).

| # | Question | Result | Consequence |
|---|---|---|---|
| S6a | Is every reader and writer of `docs/roadmap.md` known? | **Yes**, by a grep over the tracked tree outside `docs/`, `plugin/` and archives (148 files name the roadmap; the `template/` copies and the checks mirror the list below). **Readers through `roadmap_queue`:** `change-approval.sh`, `lib/context.sh` (the session-start and session-close context), `metrics.sh`, `panel-suggest.sh`, `review-cap.sh`, `roadmap-plan.sh`, propose's `context.sh` (budgets), session-close's `context.sh` and `fold.sh`, session-start's `digests.sh` and `marker.sh`, and, local or in modules, team-queue's `--next-id` (`context.d/session-start/team-queue.sh`), `local/roadmap-tracker.sh`, the artifacts module's `currency.sh` and the people module's `people.sh`. **Run by `roadmap_queue` on every read:** `roadmap.d/*.sh` (`local/roadmap.d/history.sh`, the people module's `owners.sh`). **Reading the file itself:** `roadmap-plan.sh` (the Session plan; called by `marker.sh`, `panel-suggest.sh` and the tracker), `review-cap.sh` and `change-approval.sh` (the line `roadmap_queue` names), `hooks/lib/change-guard.sh` (greps main's file for an `ops/check-outcome-<id>` row: merge-guard rules 9 and 11), the tracker's session-start line (hashes the file) and `session-plan.sh` (through the tracker). **The panel:** the Change-queue card runs `roadmap-queue.sh --text` on `watch:docs/roadmap.md` (`.stridal/panel.json`, written by `framework/internal/panel/install/init.go`); no Go code parses the table. **Writers:** `fold.sh` (Status cells); archive-change step 3 (the outcome-check row); team-queue's new-row handling (a row, numbered by `--next-id`); propose, merge-pr, session-close and dev-journal steps that add a row for a deferral; start-project step 7 (the first rows); session-close's conflict rule (both sides' status edits) | Compared with ADR-0021's Context (S19's section E) and the round 3 review (team-queue `--next-id`, `roadmap-tracker.sh`, both found here): the grep adds `change-approval.sh`, `lib/context.sh`, `change-guard.sh`, `currency.sh`, `people.sh`, `digests.sh`, session-close's `context.sh` and the panel card as readers, and the add-a-row skill steps and start-project as writers. Each reads the render or calls `roadmap_queue`, which OPS-195 keeps parser-compatible; the writers become `roadmap.add_row` or `roadmap.set_status` calls in OPS-195 |
| S6b | Are the Claude Docs tools reachable from the main session? | **Yes**: on 2026-11-01 the main session's `guide(topic.index)` call returned the index, and so did the same call from the OPS-199 lane, a teammate session | ADR-0021's display (a Claude Docs doc) can be refreshed by the main session; panel lanes still cannot (`ENABLE_CLAUDEAI_MCP_SERVERS=false`), as the ADR says |

## OPS-199: the Gate A spikes outside the sandbox (2026-11-01 and 2026-11-02)

S5a to S5i ran on the owner's Mac on 2026-11-01, outside the sandbox, on Claude Code 2.1.316 and
Go 1.26.1, from a throwaway harness under `$TMPDIR/ops199` (a fixture `CLAUDE_CONFIG_DIR`, so
`~/.claude` held no plugin or session of it; headless `claude -p` on haiku, `--setting-sources
project` unless a row says otherwise). The second run is the one recorded. The first run's
INCONCLUSIVE rows were the harness's: the fixture never trusted the scratch repos, and 2.1.316
ignores a project's `permissions.allow` in an untrusted workspace, headless too ("this workspace
has not been trusted"), so every plugin MCP call was denied. S5j ran in a claude.ai cloud
session on 2026-11-02, on 2.1.316.

| # | Question | Result | Consequence |
|---|---|---|---|
| S5a | A plugin's SessionStart command hook writes outside the sandbox: `CLAUDE_PLUGIN_DATA`, and a Go build with `GOCACHE` there and with the default `GOCACHE` | **Passed**: the marker in `CLAUDE_PLUGIN_DATA`, a build with `GOCACHE` there (44 MB), and a build with the default `GOCACHE` under `~/Library/Caches` all succeeded, while a sandboxed Bash `touch` into the same data dir was refused ("Operation not permitted") | A hook may build or cache the engine under `CLAUDE_PLUGIN_DATA` (ADR-0018 decisions 3 and 4, OPS-184) |
| S5b | A plugin hook in a worktree session appends under the git common dir | **Passed**: the hook appended to `<common dir>/stridal/ops199-feed.log` from the worktree. Sandboxed Bash could write there too, but the common dir sat under `$TMPDIR`, which the sandbox allows, so this does not show the dir is protected | The feed can live under the git common dir (ADR-0022); whether a sandboxed Bash can forge it in a real checkout is not shown here |
| S5c | A project's `enabledPlugins` true outranks a user's false (`--setting-sources user,project`) | **Passed**: with the user tier's false alone, the plugin did not load; with the project's true added, it loaded and both servers connected | `/stridal:init` setting `enabledPlugins` true holds against a user's false (ADR-0018 decision 5, OPS-184) |
| S5d | A SessionStart command hook writes `CLAUDE_ENV_FILE`, and the session's Bash sees the variable | **Passed, headless**: `printenv OPS199_ENVFILE_VAR` printed `envfile-<nonce>`, which only the hook's line in `CLAUDE_ENV_FILE` set (the first run showed the same through another variable). Interactive: S5j's fourth case | The engine path ADR-0018 decision 3 writes to `CLAUDE_ENV_FILE` reaches headless lanes and interactive sessions alike |
| S5e | A panel lane's launch (`--settings` env `ENABLE_CLAUDEAI_MCP_SERVERS=false`, headless) reaches a plugin MCP tool | **Passed**: the ping call was served (`ping-ok:s5e-lane`); the run listed no claude.ai connector (13 without the variable) | Turning the connectors off leaves the plugin's own servers reachable (ADR-0017) |
| S5f | A binary committed under the plugin's `engine/` keeps its mode and runs, installed from a git marketplace (cloned over HTTP) and loaded from a release-style zip (`--plugin-dir X.zip`) | **Passed**. Git: committed as mode 100755, executable in the installed copy, the hook exec'd it, and both servers from it connected; its tool calls were answered in S5e and S5g, whose call logs name the git-installed copy (`config/plugins/cache/ops199/spikeplug/0.0.1/engine/spike-mcp`). The S5f run's own call was denied only because 2.1.316 keys a worktree's trust to its main repository, which the harness had not trusted. Zip: `-rwxr-xr-x` kept, hook exec ok, and a call answered from `/tmp/claude-plugin-session-…/inline-0-spikezip/engine/spike-mcp`. A release fetched by a marketplace `url` source was not testable without a host | `engine/` holds the binaries under ADR-0018 decision 3 option (a), and a zip release carries them too (OPS-184, OPS-163) |
| S5g | An agent's `tools:` line filters MCP tools | **Passed**: `probe-read` (`tools: Read, mcp__plugin_spikeplug_engine-read__ping`) called ping, and its server logged the call; it never called `engine-write`'s poke; `probe-none` (`tools: Read`) reached neither | A role is limited by naming each tool; a server name or a wildcard in `tools:` was not tested (OPS-193's read/write split) |
| S5h | `sandbox.excludedCommands` takes a command out of the sandbox, in the main session and in a subagent | **Failed, all three shapes**: `"git *"` in project settings with `allowUnsandboxedCommands` false, the same from `--settings`, and in project settings with `allowUnsandboxedCommands` true (this repo's shape). In each, `git init -q <abs path outside the sandbox>` failed with "fatal: cannot mkdir …: Operation not permitted" in the main session and in a subagent, with no `dangerouslyDisableSandbox` call, while the workspace was trusted. The same bare command failed in an interactive team session of this repo (the OPS-199 lane, 2026-11-01) | Not honoured on 2.1.316, so this repo's rule that `settings.json` lifts the sandbox for `scripts/ci/gate.sh` and `git` (OPS-161, merge-pr step 2, `gate.sh`'s header) is not in force: each sandbox need is removed in code (OPS-216) |
| S5i | S3c again: an `agent` hook on PreToolUse answering ok:false blocks only that call | **Passed**: "Agent hook condition was not met: OPS199 S5i block"; the next Bash call ran (`s5i-after-ok`) and the run ended `completed`, not `hook_stopped` | ADR-0020's tool-call gates hold on 2.1.316 |
| S5j | A cloud Claude Code session runs a local binary, a plugin hook and a plugin MCP server | **Passed, four cases** (the owner's cloud session, 2026-11-02). (a) The engine built (`CGO_ENABLED=0 go build -trimpath ./cmd/stridal`, go1.24.7 linux/amd64, toolchain go1.26.9 fetched) and ran (`stridal v0.1.0`). (b) A nested headless run's SessionStart and PreToolUse hooks each ran it. (c) `plugin:cloudspike:engine-read` connected and answered ping (a deferred tool, through ToolSearch). (d) The repository's own SessionStart hook ran ("pattern-kill-path: .claude/bin first"), its `CLAUDE_ENV_FILE` put `.claude/bin` first on Bash's PATH, and `no-pattern-kill.sh` blocked a `pkill` lookup | The engine runs in a cloud session (ADR-0016's scope), and `CLAUDE_ENV_FILE` takes effect in an interactive session |

**Seen beside the spikes.** During the S5f zip run, in both runs, `~/.claude/plugins/store/cc-plugin-diff_builtin-3903e77c01b1.json` (`{"open": false}`, a built-in plugin's state) was rewritten while the run ran (03:05:45Z and 03:20:00Z, against windows ending 03:05:48Z and 03:20:00Z), despite the fixture `CLAUDE_CONFIG_DIR`: most likely that run's write, a built-in's store that does not follow `CLAUDE_CONFIG_DIR`. No other harness write reached `~/.claude` (no session id of its runs, no project dir).
