# OPS-218's design and its split

The owner read this design and took every recommendation on 2026-11-03. It splits OPS-218's row
into seven sequential PRs. The row's text stays the requirement; this file says which PR carries
what. The launcher stays on no control throughout, until OPS-224. Line counts in the split are
estimates, and no latency or test result here is measured: OPS-218's own PR states the number.

## Where the trust logic lives

Lock read, hash and fetch all come before any trusted binary, so Go cannot hold them under ADR-0018
decision 3, option (b).

- `hooks/stridal-engine.sh`, the shim, about 80 lines and held to that by a test: it reads the
  record with builtins and runs, refuses or stands aside, keeping the recovery allowlist. It runs no
  git, hash, awk or network, and 126 and 127 refuse.
- `hooks/stridal-resolve.sh`, registered directly on SessionStart: all pre-binary trust logic.
- `hooks/stridal-fetch.sh RELEASE SHA`: the one fetcher, for the resolver and `stridal lock update`.
- Go: doctor reads the record, `Decide` tables over it, and `stridal trust` serves a person's
  terminal.

**The resolver, in order:** scrub the git environment, `GIT_DIR` included; find the common dir and
check the `.git` pointer; read the recorded url, or seed it in a main checkout; `ls-remote` and fetch
in the mirror; read marker and lock at origin's tip and parse the lock; compare the plugin version;
fetch, hash and install the engine; rename the record into place.

**Per call:** read the record only. `run` executes that engine, `refuse` refuses unless it is a
recovery command, and `aside` exits 0. With no record, a marker (worktree, else one local read)
refuses with "start a new session"; otherwise the call stands aside.

**The record:** `$data/resolved/<proj>/record`, one atomically renamed file holding state, engine,
release, model, main, time, why and fix.

**The mirror:** `$data/trust/<common>/{origin-url,mirror.git}`. The recorded url is the authority,
and the repository's own url only produces a note, so one lane cannot refuse the others. A `mkdir`
lock serializes writes. Contention and unknown transport errors are outages, using the last verified
engine; only authentication and not-found mean origin said no.

**The fetcher:** a by-tag url, never `latest`, and a test base only under a fixture HOME. It downloads
a bare-engine release asset into `$data/engine/`, hashes it, then renames; nothing is unpacked or run
before the hash. OPS-213's attestation check goes between hash and rename.

**The manifest:** the source is `release/engines.sha256`, outside `framework/`, because `build.go`
embeds `all:assets` and a manifest there would change the sums it lists. The release PR bumps
`Version` and generates the file, and the builder copies it to `plugin/engine/` after `resetOut`.
`release-build.yml` requires equality while `Version` has no tag, so a stale one is caught before a
tag is used up, and `release.yml` refuses a draft unless the tag's manifest equals the built sums.

**The marker read:** `git ls-tree` should give three states, marked, unmarked and unknown, and a
protocol stop replaces a version floor for lazy fetch. Both still need testing.

**This repo:** the resolver recognizes the module path at the mirror's tip, builds with `GOCACHE`
under data, and falls back to the last verified engine, saying so.

## The split

| PR | Row | Scope | Closes |
|---|---|---|---|
| 1 | OPS-232 | Manifest source, builder, CI equality, bare assets, stale url text | The ordering gaps, `resetOut`, `latest` |
| 2 | OPS-233 | Bounded set-head, one-branch block, gh host retry, module-delete message | Those findings |
| 3 | OPS-234 | Shim and record; verification moves to the resolver on local refs; copy, then exec | Decision 7, hash-then-exec |
| 4 | OPS-235 | Mirror, recorded url, lane detection, config isolation, `stridal trust`, seeds | The trust roots, M1, M3, M4, round 3's, one lane refusing others |
| 5 | OPS-236 | Outage against refusal, fix lines, first push, last verified engine | M5, M6, M7 |
| 6 | OPS-237 | Fetcher, `EnginePath`, doctor's "not here yet", the pin read OPS-201 moves onto, this repo's build | The delivery gaps |
| 7 | OPS-218 | Marker everywhere, SessionStart registration, canary, hook tests, latency, other main-key readers, ADR and docs | The marker settlements |

The launcher stays on no control, but these PRs are not all inert: OPS-232 adds an equality failure to
`release-build.yml`, which runs on every PR; OPS-233 changes when the guard retries its default-branch
read, its messages and the scaffold's `set-head` bound; OPS-234 changes
doctor's line through `engine.Decide`; OPS-235 adds a shipped Edit deny; OPS-237 changes the gate's
engine; OPS-218 registers the resolver. After them: OPS-213 and OPS-201 rebuilt rather than merged, as
its branch merged an old OPS-184 head; the release (OPS-242, the owner's call); the first lock
(OPS-243); then OPS-224.

## The owner's decisions

1. Six new rows at Risk: high, cap 3, with OPS-218 last.
2. A session with no record refuses: the unresolved path reads what a lane can write.
3. M1: isolate all git config from the mirror except `credential.helper`, which a private HTTPS origin
   needs, and name that a trust root under an Edit deny. This relaxes the row's "config cannot run a
   program" by that one key.
4. While `allowUnsandboxedCommands` is true, "an authority lanes cannot write" holds only for
   sandboxed Bash. ADR-0018 states the limit, OPS-216 becomes a dependency of OPS-224, and the copy-install
   limit stands until OPS-145.
5. The marketplace serves main's `plugin/`, not the tag, so two installs of one version string can
   differ. The limit is recorded now, and OPS-238 pins the marketplace before REL-1.
6. `stridal-resolve.sh` registers directly, not `stridal-engine.sh --resolve` through `if-project.sh`.
7. A `none` record gaining an origin is cleared by `stridal trust reset`, from a terminal only.
8. The 10 ms ceiling returns to the owner with OPS-218's idle-machine number.

The amendment to ADR-0018 decision 5, for OPS-218's PR, true of what lands:

> A repository counts as marked if a model marker is in the worktree or in the tree of the ref treated
> as main: origin's default branch, read at SessionStart at origin's live tip through the recorded
> url; with no origin, the branch `stridal.mainBranch` names, else `main`. The verdict is a record
> under the plugin's data directory, and each later call obeys it: deleting a marker, adding
> `.claude/stridal-template` or moving a ref in a worktree changes nothing until a session resolves
> again. Before a session has a record, the read is of local refs and worktree files, which a lane can
> write, so it is a convenience, not a control. A tree that cannot be read locally counts as unknown,
> never unmarked. A session rooted below a repository's top stands aside. The opt-out is removing the
> marker on main, by a reviewed PR; the next session stands aside.

## Where the row was wrong

- `git remote set-head` in `--resolve` contradicts "never through the lane's own git directory":
  the resolver reports it instead.
- `stridal-engine.sh --resolve` through `if-project.sh` would fail
  `TestTheCommittedRegistrationsDoNotYetRunTheLauncher`, and `if-project.sh` stands aside in a
  copy-install repository such as this one.
- ADR-0018 decision 5's "Nothing sets it today" is false of `enabledPlugins`: the scaffold's settings set
  it. OPS-218's ADR change corrects it.
- `plugin/bin/` is on main, against the row's "a plugin with a top-level `bin/` is refused". OPS-237
  checks which is true; option (b) stands either way.
- "Not trusting `CLAUDE_PLUGIN_DATA` from the environment" can only be partial, as its fallback reads
  other environment. The bound is that `lock update` writes a working-tree file reaching main by PR.
- A real fetch cannot be shown on `v0.1.0-rc.1`, whose plugin carries no manifest (the release has an
  `engines.sha256` asset) and whose release has no bare assets. These rows
  prove it on fixtures, and the new tag is the first real proof.

## Open in this design

An independent review of this file found these on 2026-11-03, after the owner had read it, as it had
not been reviewed first. Each is reasoning about a design with no code yet. The row named settles it
before any code, as the row says, and a change to a decision above returns to the owner. The same
review corrected this file after the owner read it: decision 4's wording, with its meaning kept; the
list of what changes live behaviour; and OPS-201's place ahead of the release, with the release and the
first lock as rows of their own.

- **OPS-234: the no-record path.** The shim "runs no git", but "one local read" of main's tree needs it.
  So decision 2's refusal cannot see a marker only on main, and it must not catch an unmarked repository,
  which stands aside. The amendment's `unknown` has no outcome among `run`, `refuse` and `aside`.
- **OPS-234: a killed resolver.** A record from the last session survives a resolver killed by
  SessionStart's timeout, so a new session obeys an old verdict after main's lock moved.
- **OPS-234: words.** "Copy, then exec" and "verify-and-exec" conflict with the shim, which "runs no
  git, hash, awk or network" and whose "126 and 127 refuse", as `stridal-engine.sh` runs its engine
  without exec for that reason; decision 7 says "read, verify, exec", and the row names no amendment.
- **OPS-235: the mirror's lock.** A killed holder of the `mkdir` lock has no recovery, and contention
  reads as an outage. This is the sticky class of round 3's `shallow.lock`.
- **OPS-235: `stridal trust reset`.** "From a terminal only" names no mechanism: say what executes it.
- **OPS-235: the seed.** The recorded url is seeded on first sight from config normal work can write, so
  a lane rewriting it before the first resolve chooses the authority. State this trust-on-first-use limit
  in ADR-0018, or close it.
- **OPS-235: decision 3's key.** `gh auth setup-git` writes a scoped `credential.https://github.com.helper`,
  so keeping only `credential.helper` fails a private origin, which then reads as "origin said no". The
  decision does not say which scope supplies the helper, and `.git/config` is writable through Bash.
- **OPS-237: this repo's build.** Recognizing the module path at the mirror's tip gives any marked
  repository declaring that path an unpinned engine with a `run` record. Tie it to more than content.
- **OPS-237: `stridal trust`** needs a binary `plugin/bin/` does not hold: say how a plugin user gets one.
- **OPS-218: decision 6's cost.** With `if-project.sh`'s stand-aside gone, every repository a user-scope
  plugin sees gets a seeded url, a mirror and a remote call at SessionStart unless the marker is read
  first. Bound it, and state the cost.

## Still unverified, for the PR named

- OPS-235: `ls-tree` and the protocol stop on old git and partial clones (only git 2.54 is here).
- OPS-232: Mac-to-Linux byte equality of the engines; the CI equality check would catch a difference.
- OPS-218: whether `settings.json` `env` or `CLAUDE_ENV_FILE` reach a hook, SessionStart ordering and
  timeouts, and whether a project canary can detect a disabled plugin.
