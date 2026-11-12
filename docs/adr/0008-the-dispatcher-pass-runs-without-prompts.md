# 0008. A dispatcher pass runs without a prompt

Date: 2026-11-12 · Status: proposed

## Context
`/loop /dispatch` stopped the owner on routine commands (#453). Two causes:
- A command that needs the network or the process table fails inside the sandbox (`ps -axo command=`: "operation not
  permitted"; the GraphQL call in `dispatch-next.sh`: `x509: OSStatus -26276`). The retry outside the sandbox falls
  under the `Bash(dangerouslyDisableSandbox:true)` ask rule, so it prompts every pass.
- A command that runs outside the sandbox (`gh` is excluded) is no longer covered by `autoAllowBashIfSandboxed`, so it
  needs an allow rule of its own. `gh issue list/edit/comment`, `gh project field-list`, `gh api graphql` and `ps` had
  none, and `Bash(gh label*)` under `ask` beat any allow for the one-time `gh label create`.

## Decision
- **Excluded from the sandbox** (so they run outside it the first time, with no retry): `ps *`,
  `bash .claude/bin/dispatch-next.sh *`, `bash .claude/bin/token-expiry.sh *`. `session.sh` and `gh` already were.
- **Allowed**: `ps -axo command=` (exact), `gh api graphql *`, `gh api user*`, `gh api repos/*/compare/*`,
  `gh api repos/*/rules/branches/main*`, `gh project field-list*`, `gh project view*`, `gh issue list/comment/edit`,
  `gh pr update-branch`, and `gh label create agent:working --force` / `agent:blocked --force` (exact).
- **Ask narrowed, deny only grown**: `Bash(gh label*)` becomes `delete`, `edit` and `clone`, so the two exact `create`
  commands can be allowed (ask beats allow). A new deny rule, `Bash(gh api graphql *mutation*)`, keeps the allowed
  GraphQL read from being a write. No deny rule is removed or narrowed, and `Bash(*merge-ok*)` stays (ADR-0003).
- **The skill** tells the dispatcher that a sandbox refusal of `ps` means stale settings, not "no worker", and never to
  retry with `dangerouslyDisableSandbox`.
- **The agent token** keeps `read:project` only; the owner moves cards (`docs/runbooks/agent-token.md`).
- `.claude/bin/test-settings.sh` (run by `kit-check.sh`) asserts all of this from `settings.json`.

## Consequences
- Good: an idle-to-armed pass needs no approval; v0.1.0 ships that.
- Cost / risk: the rules match command text only (as ADR-0003 says). `gh api graphql *` is still a text match, so a
  mutation written to avoid the word, or `gh issue edit` on any issue, is allowed. The agent token's scopes
  (`repo`, `read:project`, `workflow`) and the `lane` check's actor test are what bound the damage.
