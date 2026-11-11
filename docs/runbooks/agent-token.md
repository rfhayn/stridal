# Runbook: the agents' machine user and its GitHub token

## Purpose
The dispatcher and its workers act on GitHub as a separate **machine user**, not as you (ADR-0004). That keeps
the approver and the agent apart: a lane-3 PR needs the `merge-ok` label from the `Approver:` in `CLAUDE.md`'s
`## Dispatcher` block, and `lane.sh` counts it only when the Approver, never the Agent, applied it. The machine
user's classic personal access token lives in the macOS Keychain; `.claude/bin/as-agent.sh` reads it at launch
and nothing else does.

## When to use
- Setting a repo up for `/dispatch` for the first time (do it before the first dispatch).
- The expiry warning has appeared, or the token has expired (see Rotate).
- You need to add a scope to the token.

## Prereqs
- You own the GitHub account that is the Approver, and can add collaborators to the repo and the Project.
- macOS with the `security` tool (the Keychain), `gh`, and this kit's `.claude/bin/as-agent.sh`.
- Do every step yourself, in your own terminal. Claude never types the token or runs `security` for it.

## Steps
1. **Create the account.** Sign up a second GitHub account for the agents (a private window keeps it apart from
   your own session). Turn on **2FA** for it and keep its recovery codes. This is the `Agent:` login.
2. **Give it the least access.** Add it to the repo as a **write** collaborator, never admin, and accept the
   invitation as that account. Give it **Read** on the Project board (the Now column is the backlog, ADR-0001);
   write access to the board is not needed. Never make it a repo admin and never let it be the Approver.
3. **Create a classic token** as the machine user: Settings, Developer settings, Personal access tokens,
   **Tokens (classic)**, Generate new token (classic). Pick an expiry (90 days is a reasonable choice). Tick exactly:
   - `repo`: read and write the repo's code, issues and pull requests.
   - `read:project`: read the Project board. Without it the Now column cannot be read.
   - `workflow`: GitHub refuses any push that adds or changes a file under `.github/workflows/` without it, and
     the kit's own changes touch those files.

   Copy the value once; GitHub shows it only on this page.
4. **Store it in the Keychain**, from your own terminal (not a Claude session):
   ```sh
   security add-generic-password -s <service> -a <login> -w
   ```
   `<service>` is a name you choose for the Keychain item and `<login>` is the machine user's login. With `-w`
   last and no value, `security` prompts for the password, so it never lands in shell history.
5. **Name them in `CLAUDE.md`'s `## Dispatcher` block**, with an `Approver:` that is a different login:
   ```
   - Name: <key> · Project: <owner> #<n> · Approver: <your login> · max_workers: 1
   - Agent: <login> · Agent keychain: <service>
   - Start: `.claude/bin/dispatch.sh`
   ```
   `Agent keychain:` is the `<service>` from step 4. The launcher refuses when `Agent:` is set but `Agent keychain:`
   is missing or still a `{{placeholder}}`, and when Agent and Approver are the same login.
6. **Start the dispatcher** with `.claude/bin/dispatch.sh` (or the `dispatch` alias `bootstrap.sh` prints) from
   the repo, with the main checkout on `main`. It opens `claude --name dispatch-<key>` through `as-agent.sh` and
   runs `/loop /dispatch`.

## Verify
- `security find-generic-password -s <service> -a <login>` (no `-w`) shows the item without printing the token.
- From the started session, `gh api user --jq .login` prints the machine user's login, not yours.
- `.claude/bin/dispatch.sh` run with a dispatcher already open refuses with `already runs`.

## Rotate and expiry
On each pass the dispatcher runs `.claude/bin/token-expiry.sh`, which reads the
`github-authentication-token-expiration` header from `gh api -i user` (the token it already holds; no Keychain
read). From 14 days out it pushes `agent token expires <date> (<n> days); rotate it` once a day. Once the token has
expired it stops with that message and moves nothing until you rotate it. The date is read live, so this runbook
holds none.

To rotate (a new value):
1. Sign in to GitHub as the machine user. Open the token (step 3) and **Regenerate token**. Pick the new expiry,
   check the scopes are still exactly `repo`, `read:project` and `workflow`, and copy the new value.
2. Store it, replacing the old one, from your own terminal:
   ```sh
   security add-generic-password -U -s <service> -a <login> -w
   ```
3. Restart the dispatcher, since a running session keeps the old token in its environment: close its tab, then run
   `.claude/bin/dispatch.sh`. Workers still open keep the old token until they end, so rotate before it lapses.

To add or drop a scope, **edit** the token (change the scope boxes, then **Update token**) and do not regenerate
it. Editing keeps the value and expiry, so the Keychain and running sessions need nothing. Regenerating issues a
new value while the Keychain still holds the old one, and the old one stops working at once.

## Rollback
Remove the access: delete the token in GitHub and the Keychain item
(`security delete-generic-password -s <service> -a <login>`), then remove the machine user from the repo. Delete
the `Agent:` lines to run the dispatcher as yourself, which `dispatch.sh` allows with a warning (not advised: the
approver and agent are then the same account).

## Last checked
Fill in when you set this up: date, by whom, and the result of the Verify steps.
