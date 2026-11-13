# 0004. The dispatcher and its workers act on GitHub as a machine user

Date: 2026-11-11 · Status: proposed

## Context
Every Claude session ran `gh` and `git push` with the owner's credentials, so GitHub recorded the owner as the actor
for anything an agent did. A text-matching deny rule (0003) cannot stop a GraphQL call from adding the approval label
as the owner. Only a separate identity lets `lane` prove "the owner approved this", and lets "moved to Now by the
owner" on the board be trusted (0001).

## Decision
- **The account.** A machine user (this repo: `rfhayn-bot`) with 2FA, a **write** collaborator on the repo (never
  admin), with Read on the Project. One bot can serve several repos. The owner makes these GitHub settings.
- **Its token.** A classic token with scopes `repo`, `read:project` and `workflow` only (fine-grained tokens can't
  reach a repo owned by another personal account). It is stored in the macOS Keychain under a repo-named service,
  from the owner's own terminal; never in `.env`, a tracked file, a command line or a log. It expires, and the
  dispatcher warns daily from 14 days out (`token-expiry.sh`).
- **Who uses it.** Only the dispatcher and its workers. `.claude/bin/as-agent.sh <service> <command>` reads the token
  and execs the command with `GH_TOKEN`, an empty agent `GH_CONFIG_DIR` and env-only git config routing https pushes
  through `gh auth git-credential`; `session.sh open --agent-keychain <service>` starts each worker through it. The
  dispatch skill stops if `gh api user` is not the `Agent:` login in CLAUDE.md. `Approver` must differ from `Agent`.
- **`lane`.** The approver is the `Approver:` login (0002); a label the bot adds is rejected
  (`.github/lane/test.sh`).
- **Light guards.** `.claude/settings.json` denies Bash commands containing `gh auth `, `security find-` and
  `security dump-keychain`.

## Consequences
- Good: `lane` can tell the agent's label from the owner's.
- Cost / risk: isolation is light, not full: the owner's `gh` keyring entry and browser session remain on the Mac, and
  the deny rules match text. A second account and token to keep, and when the token lapses the dispatcher stops
  (the safe direction). The bot can push workflow files (the `workflow` scope); that still lands only through a PR,
  and a `.github/` change is lane 3. HTTPS remotes only: an ssh remote would push with the owner's key. User-owned
  boards only. Commits keep the owner's git author.
- Revisit if: an agent is ever seen acting as the owner (then a separate macOS user), or the board moves to an
  organisation.

## Links
Ported from the repo this kit came from. This repo: Agent `rfhayn-bot`, keychain service
`stridal-github-bot`. Related: 0001, 0002, 0003.
