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

## OPS-199: the Mac spikes (queued for the owner's run)

The spikes the sandbox could not run are numbered S5a to S5j. They are listed here, not in the
table above, so no ADR can cite one before its result is recorded; each moves into a table with
its Claude Code version and a pass or a fail once the owner's run reports. The harness is a
throwaway under `$TMPDIR/ops199`, generated by a runner the owner starts outside the sandbox.
- S5a: a hook writes outside the sandbox, to `CLAUDE_PLUGIN_DATA` and to a `GOCACHE` directory
  (ADR-0018, OPS-184).
- S5b: a hook appends under the git common dir (ADR-0022).
- S5c: a project's `enabledPlugins` true outranks a user's false (ADR-0018).
- S5d: a SessionStart command hook runs at launch and writes `CLAUDE_ENV_FILE`, and the variable
  is seen later in the session (ADR-0018).
- S5e: a panel lane (`ENABLE_CLAUDEAI_MCP_SERVERS=false`) reaches a plugin MCP tool (ADR-0017).
- S5f: where the binaries can live: `engine/` committed in a plugin installed from a git
  marketplace, against a release (OPS-184, OPS-163).
- S5g: an agent's `tools:` line filters MCP tools (OPS-193).
- S5h: a subagent's Bash honours `sandbox.excludedCommands`.
- S5i: S3c again on this Claude Code version: an `agent` hook on PreToolUse with ok:false blocks
  only the call (ADR-0020's *Rests on* item 3; the owner, 2026-11-01).
- S5j: a cloud Claude Code session runs a local binary and a plugin hook (ADR-0016). Not from the
  Mac: a prompt the owner pastes into a cloud session.
