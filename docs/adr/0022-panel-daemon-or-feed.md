# ADR 0022: Live session state comes from a feed in files, or from the panel daemon

- **Status**: Accepted (the owner, 2026-11-02): option B, the feed in files, display-only (see the acceptance below).
- **Date**: 2026-10-31
- **Tags**: panel, terminal-ui, engine, hooks
- **Source**: the S19 remap (finding 4 and the FEED row); ADR-0017's "no state outside files"

## Context
The panel daemon keeps live session state in a process: which sessions run, which are idle, and
their subagents. It learns it from `curl` hooks that `stridal panel install` writes into the
user's `~/.claude/settings.json` (`framework/internal/panel/install/hooks.go`, `hookkeeper.go`).
That creates three problems for the new design:
- **A third registration path.** It sits beside the plugin's `hooks.json` and a `stridal install`
  repo's `settings.json`, so OPS-185's "every registration is the dispatcher" check fails on it.
- **Edits to the user's own settings**, outside any repo.
- **A third version authority.** The daemon's binary is a copy at `~/.stridal/panel/bin`, apart
  from the plugin and the repo's lock.

The terminal UI (PRD-tui, PANEL-61 and PANEL-62) and the session watcher (ST-17) both need live
state.

## Options
- **A. Keep the daemon.** The dispatcher forwards events to it over its socket, in place of the
  `curl` hooks. The daemon's binary is the plugin's engine, run as `stridal panel`. PANEL-25 (idle
  cost) stays. Live state stays in memory, and the UI asks the daemon for it.
- **B. Daemonless: a feed in files.** The dispatcher appends each session event to an append-only
  feed under the git common dir (`stridal/feed/<session>.jsonl`). `sessions.list`, `sessions.counts`
  and `sessions.subagents` are engine queries over the feed. The terminal UI and the watcher read
  it.
  - Cancels: PANEL-25, launchd install, the `~/.claude/settings.json` edits and OPS-118's
    leftovers.
  - ST-17's watcher becomes a reader of the same feed, plus a process check.
- **C. Both.** The feed is the authority, and an optional daemon caches it for a fast UI.

## Decision
To be taken by the owner at Gate C, after Gate A shows how a hook outside the sandbox writes under
the git common dir.

The recommendation is **B**:
- It satisfies ADR-0017's "no state outside files".
- It removes the third registration path and the third version authority.
- It cancels about 2 sessions of panel work.
- A dead UI loses nothing, because the feed outlives it.

On 2026-10-31 (S20) the owner chose **B**, the feed in files, as recommended. The status stays
Proposed (PRAC-0023: a decision is accepted only on the evidence its assumptions name, and neither
item under *Rests on* is tested yet). It is accepted at OPS-203 once OPS-199 has tested the
hook-write assumption, and amended there if a spike fails it. Until then PANEL-25 stays on the plan
unchanged.

## Consequences
- **For B:** feed files need rotation and a size cap (an engine action at session close); a reader
  polls or watches the file; there is no push without a process.
- **For A:** the daemon must be versioned by the repo's lock like the engine; PANEL-25 and the
  launchd lifecycle stay on the plan.

## Enforcement
- **One registration path:** OPS-185's registration check, which, once FEED lands, also fails on a
  `curl` hook in `~/.claude/settings.json` written by stridal.
- **The feed's schema and rotation:** engine tests (FEED row).
- **The feed is display-only:** nothing yet, since no code reads a feed: **Nothing. You.** until
  OPS-204, whose row carries the rule.

## Rests on
- A hook can append under the git common dir outside the sandbox: S5b, **passed**.
- A sandboxed Bash can write `<common dir>/stridal/` in a real checkout, so the feed can be forged and stays display-only: S23a, **passed**.
- Polling a feed file is fast enough for the terminal UI: **untested** — accepted at risk by the owner (2026-11-02); tested by OPS-204.

## Amendment — 2026-11-02: PANEL-25 is cancelled now
- **Source**: the three reviews of 2026-11-02 (`docs/plans/s22-review-mapping.md`); the owner's decision.

The owner cancelled PANEL-25 and removed `changes/panel-25-idle-cost/`, without waiting for OPS-203.
This replaces "Until then PANEL-25 stays on the plan unchanged" above: the row is only worth doing
under option A, and the owner has chosen B. If OPS-203 finds B fails, it re-opens the question with
a new row. The status stays Proposed until OPS-203.

**Enforcement** (in addition to the above): `checks/changes.sh` fails a directory whose row is
cancelled.

## Acceptance — 2026-11-02: option B, and the feed is display-only
- **Source**: the owner, 2026-11-02 (OPS-203); S23a in `docs/plans/s19-spikes.md`.

The owner accepts option B, on the test OPS-203 asked for and with the conditions it led to:
- **The feed is display-only.** S23a shows a sandboxed Bash can write under the common dir, so an
  agent can forge the feed. No guard, gate or merge decision may read it. ST-17's watcher may
  report from it, and may decide nothing that a control would rely on.
- **Polling speed is accepted at risk**, measured by OPS-204's 250 ms ceiling.

This replaces "To be taken by the owner at Gate C" above, and both statements above that the status
stays Proposed, which are kept as history. If OPS-204's measurement fails, the question reopens with
a new row.

## Related
- ADR-0003 (one panel for many repositories), ADR-0005 (never kill a tmux server), ADR-0017,
  ADR-0018. PRD-tui. PANEL-25, PANEL-61, PANEL-62, ST-17.
