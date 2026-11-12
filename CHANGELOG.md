# Changelog

Built from the titles of merged PRs. The kit in its present form starts at #409; the earlier Stridal engine is at tag `stridal-final`.

## 0.1.0

First release a project can pin to. `bootstrap.sh` now records `.claude/kit.lock` and can `--upgrade` and `--adopt` (ADR-0007).

- Installer: version stamp, `--upgrade`, `--adopt` and this changelog (#452)
- feat: retire the hand-run loop: /brief, /ship, /merge, /land (#438 C2) (#451)
- feat: workers run /ship's checks themselves (#438 part C1, #443) (#446)
- feat: one-command dispatcher launcher and the machine-user runbook (#437) (#444)
- feat: port the Now-column dispatcher into the kit (#436 part A) (#440)
- feat: one worker per slug, tab identity check on send, fetched text is data (#433)
- feat: keep claude.ai connectors out of worker sessions (#431)
- feat: preflight and reviewer evidence checks for /ship (#430)
- fix: drop the inert Write(...) ask rules (#429)
- docs: split the roadmap like CLAUDE.md, fill in this repo's own (#428)
- docs: CLAUDE.md says the owner, not Rich (#427)
- feat: a lean status line that ships with the kit (#425)
- chore: shipped files say the owner, not Rich; allow gh pr list (#424)
- feat: session.sh sync for /land, /ship reports back (#423)
- docs: README says what Stridal is; /land pulls before it closes (#422)
- feat: worker login-shell PATH, /ship <slug> from main, close cleanup (#421)
- feat: /brief and /land use session.sh, shipped to new projects (#419)
- feat: session.sh opens and closes worker sessions in Ghostty tabs (#418)
- docs: PR template Why/Roadmap lines, lane.yml Why check, /brief recent work (#417)
- fix: say gh runs plain instead of needing a sandbox-off run (#416)
- docs: ARCHITECTURE and RISKS docs, five templates, marker check, /brief template rules (#415)
- docs: README and lane.yml describe /merge and the merge-ok prompt (#414)
- feat: /merge adds the lane 3 green light, with a prompt instead of a deny (#413)
- fix: git push runs sandboxed, so allow it without -u and stop excluding it (#412)
- fix: align /ship and Guards with what the sandbox does (#411)
- docs: structured roadmap, ADR links, and /brief roadmap and ADR rules (#410)
- Replace Stridal with the lean Claude Code kit (#409)
