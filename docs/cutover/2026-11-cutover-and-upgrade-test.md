# Cutover and upgrade test (2026-11)

Run every command in your own terminal, outside any Claude session, unless it says Web. Do the phases in order.

## Where things stand
- Merged on `main`: #452 (installer lock, `--upgrade`, `--adopt`), #453 (a dispatcher pass runs without approval prompts), #454 Part 1 (the old project's names are gone from tracked files, with a check).
- Open and yours: #452 (the v0.1.0 tag), #454 Part 2 (the move to a clean repo).
- The tag waits until the new repo exists, because the history rewrite changes every sha and tag.

## Phase 0: get ready
**0.1 Pull `main`** (the upgrade commands don't exist in an older copy):
```sh
cd <KIT>
git switch main && git pull --ff-only
git log --oneline -1
```

**0.2 Create the new Keychain item** (before restarting this repo's dispatcher; the token never prints):
```sh
security find-generic-password -s <OLD-KEYCHAIN-SERVICE> -a rfhayn-bot -w | pbcopy
security add-generic-password -s stridal-github-bot -a rfhayn-bot -w     # paste at the prompt
pbcopy < /dev/null                                                       # clear the clipboard
security find-generic-password -s stridal-github-bot -a rfhayn-bot       # no -w: shows the item only
```

**0.3 Restart this repo's dispatcher.** Exit its session first, because the launcher refuses while one runs:
```sh
cd <KIT> && .claude/bin/dispatch.sh
```
**Keep `<OLD-KEYCHAIN-SERVICE>`.** The other repo launches its workers through it, so deleting it would break that repo's next worker. Both items hold the same token: when you rotate it, update both with `security add-generic-password -U ...`. Drop the old item only after the other repo's `Agent keychain:` line names its own service.

## Phase 1: test the upgrade on the other repo (on a throwaway worktree)
No dispatcher stop is needed, and a scheduled job there can keep running: this only writes a separate directory and one branch. **Never run plain `bootstrap.sh <dir>`** against that repo: plain mode calls `gh` and sets its ruleset, labels and merge settings.

1. Look without changing it:
   ```sh
   cd <OTHER>
   git fetch origin
   git status --short | head
   git branch --show-current
   ```
2. Make the worktree:
   ```sh
   git worktree add ../upgrade-test -b chore/upgrade-test origin/main
   ```
3. The lock-less refusal (writes nothing):
   ```sh
   KIT=<KIT>
   $KIT/bootstrap.sh --upgrade ../upgrade-test
   git -C ../upgrade-test status --short      # expect: nothing
   ```
4. Adopt it:
   ```sh
   $KIT/bootstrap.sh --adopt ../upgrade-test
   git -C ../upgrade-test status --short      # expect: only .claude/kit.lock is new
   ```
5. Dry run, and read the plan before applying:
   ```sh
   $KIT/bootstrap.sh --upgrade ../upgrade-test > ~/upgrade-plan.txt
   ```
6. Apply:
   ```sh
   $KIT/bootstrap.sh --upgrade ../upgrade-test --apply
   git -C ../upgrade-test status --short
   git -C ../upgrade-test diff --stat
   find ../upgrade-test -name '*.kit-new'
   ```
   Check: an unedited file is replaced; an edited file is left alone with a `.kit-new` beside it; `CLAUDE.md` is untouched. A repo that has diverged from the kit will show many `.kit-new` files; that is expected.
7. Clean up:
   ```sh
   cd <OTHER>
   git worktree remove --force ../upgrade-test
   git branch -D chore/upgrade-test
   rm -f ~/upgrade-plan.txt
   git worktree list
   ```
File what you find as follow-up issues.

If you later apply an upgrade to the real repo: the skill is read from disk on each pass, changed scripts are used by the next worker, running workers keep the contract they started with, and a changed `settings.json` may not reach a running session. Restart its dispatcher after the apply, while its worker is idle.

## Phase 2: move to a clean `stridal` repo (#454 Part 2)
Start only when no worker or PR is open.

**2.1 Back up the repo:**
```sh
cd <KIT> && git fetch origin --prune
git bundle create ~/stridal-backup-2026-11-12.bundle --all
git bundle verify ~/stridal-backup-2026-11-12.bundle
git clone ~/stridal-backup-2026-11-12.bundle ~/stridal-restore-test && git -C ~/stridal-restore-test log --oneline | wc -l
rm -rf ~/stridal-restore-test
```

**2.2 Rename the old repo and take it private:**
```sh
gh api repos/rfhayn/stridal --jq .private         # note: public or private; match it in 2.4
gh repo rename stridal-old -R rfhayn/stridal --yes
gh repo edit rfhayn/stridal-old --visibility private --accept-visibility-change-consequences
```

**2.3 Rewrite the history** (replace the banned names; list them in a `replace.txt` built from `.claude/banned-names.txt`, putting the longer Keychain name first so it becomes `stridal-github-bot`, then the general names, each to `source-repo`, using the `regex:(?i)<pattern>==>source-repo` form):
```sh
brew install git-filter-repo
mkdir -p ~/stridal-cutover && cd ~/stridal-cutover
git clone ~/stridal-backup-2026-11-12.bundle stridal-clean
cd stridal-clean
git filter-repo --replace-text ../replace.txt --replace-message ../replace.txt
```
Verify, with each count 0 (use the patterns in `.claude/banned-names.txt`):
```sh
git log --all -p | grep -ciE '<banned patterns joined with |>'
git for-each-ref --format='%(refname)' | grep -ciE '<banned patterns joined with |>'
```

**2.4 Create the new repo and push** (match the visibility from 2.2):
```sh
gh repo create rfhayn/stridal --private --description "Stridal: a copy-in kit for building with Claude Code"
cd ~/stridal-cutover/stridal-clean
git remote add origin https://github.com/rfhayn/stridal.git
git push --all origin
git push --tags origin
```

**2.5 Copy the settings across:**
```sh
gh api repos/rfhayn/stridal-old/rulesets --jq '.[].id'
gh api repos/rfhayn/stridal-old/rulesets/<id> | jq 'del(.id,.source,.source_type,._links,.created_at,.updated_at,.node_id,.current_user_can_bypass)' > ~/stridal-cutover/ruleset.json
gh api repos/rfhayn/stridal/rulesets --method POST --input ~/stridal-cutover/ruleset.json
gh api repos/rfhayn/stridal-old --jq '{allow_squash_merge,allow_merge_commit,allow_rebase_merge,allow_auto_merge,delete_branch_on_merge,squash_merge_commit_title,squash_merge_commit_message}'
gh label list -R rfhayn/stridal-old --limit 100 --json name,color,description --jq '.[] | [.name,.color,.description] | @tsv' > ~/stridal-cutover/labels.tsv
while IFS=$'\t' read -r n c d; do gh label create "$n" -R rfhayn/stridal --color "$c" --description "$d" --force; done < ~/stridal-cutover/labels.tsv
gh api -X PUT repos/rfhayn/stridal/collaborators/rfhayn-bot -f permission=push
```
Then apply the merge settings printed above to the new repo with `gh api repos/rfhayn/stridal --method PATCH` (booleans need `-F`). Web: accept the invitation as `rfhayn-bot` at https://github.com/rfhayn/stridal/invitations; match the Actions workflow permissions in Settings, Actions, General; link the Project board to the new repo.

**2.6 Point your local checkout at it:**
```sh
mv <KIT> <KIT>-old-checkout
git clone https://github.com/rfhayn/stridal.git <KIT>
```
Cloning to the same path keeps Claude's project memory. Then run a dispatch pass there, check CI and the labels, and file clean issues for what is still open (do not transfer issues: their text carries the old names).

## Phase 3: tag the release (on the new repo)
```sh
cd <KIT> && git switch main && git pull --ff-only
cat VERSION
git tag -a v0.1.0 -m "v0.1.0" && git push origin v0.1.0
gh release create v0.1.0 --title "v0.1.0" --notes-file CHANGELOG.md
```
Then try the README's pinned install command against a temp directory; it could not be tried before the tag existed.

## Phase 4: delete the old repo
Only when satisfied and the backup bundle restores. Web: the old repo, Settings, Danger Zone, Delete this repository. It cannot be undone. Optionally `gh repo archive rfhayn/stridal-old --yes` first.

## Not verified
- The ruleset export may need small edits before GitHub accepts it.
- `git filter-repo` replaces the names with `source-repo`, which reads oddly in a few old sentences but removes every banned name.
- PRs, Actions history and releases stay in the old repo and are gone once it is deleted.
- Delete this file once the cutover is finished.
