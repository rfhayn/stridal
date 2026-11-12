# 0007. The kit lock and the three-way upgrade rule

Date: 2026-11-12 · Status: proposed

## Context
`bootstrap.sh` never overwrites, so a fix to the kit reached new projects only. A project that adopted the kit could
not tell which version it had or take later fixes, and there was no release to pin to. A plugin was considered and
dropped: it cannot ship `CLAUDE.md`, permissions, the sandbox config, workflows or the ruleset, which are the guards.

## Decision
**The lock.** Install writes `.claude/kit.lock`, only when none exists. Plain text:
```
# stridal kit.lock 1: ...
version 0.1.0
runner hosted
<sha256>  <path>        one line per file, two spaces, sorted by path
-  <path>               a file that was already there and differed from the kit: "edited", never equal to a hash
```
The hash is of the file as the kit installed it, after the runner choice was applied to the two workflows. `version` is
the `VERSION` of the last kit that wrote the lock. A second `bootstrap.sh` run leaves the lock and the project as they were.

**`--upgrade <dest> [--apply]`.** A dry run unless `--apply`. It never calls `gh` and never deletes. With no lock it
fails and writes nothing; `--adopt <dest>` writes a lock from the project's current files (a file equal to the kit's gets
its hash, one that differs gets `-`). For each file in the kit's list except `CLAUDE.md`, compare three hashes: the
project's (P), the lock's (L) and the new kit copy's (K):
- missing in the project: add it.
- P = K: nothing to do.
- P = L (never edited), K differs: replace it with the kit copy.
- P differs from L (edited locally): leave it. If K differs from L, write the kit copy beside it as `<file>.kit-new` and
  say so; if K = L the kit has nothing new for that file, so no `.kit-new`.
- in the lock but not in the kit's list: report it, never delete.
- `CLAUDE.md` is never compared with the lock and never written: upgrade prints `diff -u` of it against the template.
The lock is rewritten only for files upgrade added or replaced, plus its `version` line when it changed any. A kept
file keeps its old lock line, so the next upgrade still offers it.

## Consequences
- Good: a project can see its kit version, take unedited fixes unattended, and see exactly what it must merge by hand.
- Cost / risk: P = L cannot tell "edited then reverted" from "never edited", which is fine, and it cannot detect a kit
  file that moved. A file adopted as `-` always gets a `.kit-new` when the kit differs from it at all, since its baseline
  is unknown. `kit.lock` is a file the owner could edit; a wrong hash makes upgrade overwrite or keep a file wrongly.
  Upgrade replaces only when P = L, so a hand-edited lock is the only way to lose an edit.
- Revisit if: kit files are renamed (upgrade would add the new name and report the old as dropped).

## Links
Issue #452. Related: 0001 (the dispatcher is how it was built).
