# 0003. The approval label is withheld from Claude, not asked

Date: 2026-11-11 · Status: proposed

## Context
`lane` counts `merge-ok` only when the owner added it (0002), but a Claude session running `gh` as the owner
produces an event whose actor is the owner. This repo's guard is `Bash(*merge-ok*)` under `ask` in
`.claude/settings.json`. An `ask` rule needs a person at the prompt; in auto mode a classifier decides, and in
the source repo's evidence it allowed the command. The dispatcher makes unattended auto-mode workers the normal
case, so a worker could label its own lane-3 PR.

## Decision
`Bash(*merge-ok*)` belongs under `deny`, which holds in every mode, and the owner adds the label only in GitHub's web
UI. **Here the deny rule lands in part C of #436** (#438), in the same change that retires `/merge`, because `/merge`
adds the label through that one prompt and would stop working. Until then `ask` stays, and 0004's identity check is
what holds: the label an agent adds as the machine user is rejected by `lane`.

## Consequences
- Good: once denied, no Claude session can add the label from Bash in any mode.
- Cost / risk: the rule matches command text only. A GraphQL label-id call or a split word passes it, and it binds
  only Claude's Bash tool. Do not name a branch, folder or file with the label's name, since every command naming it
  is stopped; commit messages and PR bodies go through a file (`git commit -F`, `--body-file`).
- Revisit if: `/merge` is retired (part C), after which move the rule to `deny` and check it is in no `ask` entry.

## Links
Ported from the repo this kit came from. Related: 0002, 0004. Issue #436 part C = #438.
