# 0009. A detached cap process stops a worker that runs too long

Date: 2026-11-14 · Status: proposed

## Context
- A worker that hangs or runs away is never stopped, and nothing records how long workers run (#3).
- A plain wall-clock cap would kill a worker that waits on the owner: it can sit about two hours at its first
  permission prompt while the owner is away. The dispatcher already tracks that state with the `<slug>.waiting` and
  `<slug>.notified` markers.
- `session.sh watch <slug> [--timeout]` already exists: the read-only watcher the dispatcher uses. The new process
  must not reuse or change that name.

## Decision
- A real `session.sh open` starts a detached `session.sh cap <slug>` (own process group, `nohup`, internal; not `watch`).
  It polls `ps` every 5 s.
- **Active time** is the sum of poll ticks during which none of `<slug>.waiting`, `<slug>.notified` or `<slug>.idle`
  exists. `.idle` (#7) is set by the Stop hook (`notify-waiting.sh idle`, which also clears the other two) and cleared
  by the next tool use or prompt (`notify-waiting.sh clear`), so a worker idle after `BLOCKED:` or `RESULT`, waiting
  for the owner's answer or for `merge-ok` on a lane-3 PR, is not on the clock. `.idle` never blocks `close`. One tick
  adds at most 300 s, so a suspended laptop does not count. Past `STRIDAL_WORKER_CAP_SECONDS` (a whole number 60 to
  86400, default 3600; a bad value refuses `open`) of active time, the cap sends `TERM` to the worker's process
  group, then `KILL` after 10 s if it still runs.
- It signals only a group it first saw as the worker's: every matching `ps` line (`claude --name <session>`) is in
  that group, a matching process leads it (pid = pgid), and the group is neither init's nor the cap's own.
  Otherwise it logs `cap-nokill` and signals nothing, keeps the lock and still alerts. A same-named `claude`
  started later in another group is never killed.
- Outcomes go to `.claude/review/runs.log` (git-ignored), one line each: `ended` (the worker exited by itself),
  `cap-kill`, `cap-nokill`, `no-worker` (none found within 120 s of the start). A `cap-kill` or `cap-nokill` also
  raises a macOS notification (`osascript`), off only with `STRIDAL_ALERT=0`.
- After a kill, only the lock is removed. The worktree, branch and spawn records stay, so the dispatcher's Reconcile sees
  an `agent:working` issue with no live worker and no PR and blocks it with its existing comment.

## Consequences
- Good: a runaway worker is stopped and recorded; a worker held at a permission prompt (marker present) is not
  counted against.
- Known gap: a worker idle after `BLOCKED:` or `RESULT` has no marker (the Stop hook clears both), so that time
  counts. Closing it needs an idle marker from the hooks, which are outside #3's footprint; filed as a follow-up.
- Cost / risk: a process that sends signals to a process group is a sharp tool; the group checks above exist so a
  wrong match logs `cap-nokill` instead of killing. The marker rule trusts the hook and the dispatcher to set and clear
  the markers; a marker left behind stops the clock (the worker then runs uncapped, as today). If the cap process
  itself dies, the cap is lost silently; `close` and the dispatcher do not depend on it.
- Revisit if: the dispatcher gains its own per-worker timer, or workers stop running as `claude --name <session>`.

## Links
- Issue #3; ADR-0006 (session names), ADR-0001 (the Now column). The earlier attempt, a closed PR on the old repo,
  collided with `watch` and used a wall-clock cap.
