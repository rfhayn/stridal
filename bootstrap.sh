#!/usr/bin/env bash
# Lean kit installer. Three modes:
#   ./bootstrap.sh <dest-repo-dir> <hosted|self-hosted>                 copy files only (never overwrites)
#   ./bootstrap.sh <dest-repo-dir> <hosted|self-hosted> <owner/repo>    copy files, then protect main
#   ./bootstrap.sh --enable-auto-merge <owner/repo> <red-PR-number>     only after a red PR was refused
# GitHub steps need `gh auth login` as a repo admin. Private repos need GitHub Pro/Team for rulesets.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--enable-auto-merge" ]; then
  REPO="${2:?owner/repo}"; PR="${3:?number of a PR whose ci check is red}"
  gh api "repos/$REPO/rulesets" --jq '.[] | select(.name=="main" and .enforcement=="active") | .id' | grep -q . \
    || { echo "No active 'main' ruleset on $REPO. Refusing."; exit 1; }
  state=$(gh pr view "$PR" --repo "$REPO" --json state,mergeStateStatus --jq '.state+" "+.mergeStateStatus')
  red=$(gh pr view "$PR" --repo "$REPO" --json statusCheckRollup \
        --jq '[.statusCheckRollup[] | select(.name=="ci" and .conclusion=="FAILURE")] | length')
  [ "$state" = "OPEN BLOCKED" ] && [ "$red" -ge 1 ] \
    || { echo "PR #$PR is not proof (state='$state', red ci checks=$red). Need OPEN + BLOCKED with ci failing."; exit 1; }
  gh repo edit "$REPO" --enable-auto-merge
  echo "Proof recorded (PR #$PR blocked with red ci). Auto-merge enabled. Close PR #$PR without merging."
  exit 0
fi

DEST="${1:?usage: see header}"; RUNNER="${2:?runner choice required: hosted or self-hosted}"; REPO="${3:-}"
case "$RUNNER" in hosted|self-hosted) ;; *) echo "runner must be 'hosted' or 'self-hosted'"; exit 1;; esac

# 1. Files (never overwrite).
cd "$KIT"
for f in CLAUDE.md .claude/settings.json .claude/agents/reviewer.md .claude/agents/researcher.md \
         .claude/skills/brief/SKILL.md .claude/skills/ship/SKILL.md .claude/skills/merge/SKILL.md .claude/skills/land/SKILL.md .claude/hooks/one-way-guard.sh \
         .claude/bin/scope-check.sh .claude/bin/session.sh .claude/statusline.sh .claude/rules/EXAMPLE-migrations.md.example \
         .github/workflows/ci.yml .github/workflows/lane.yml .github/pull_request_template.md \
         docs/ROADMAP.md docs/adr/0000-template.md docs/ARCHITECTURE.md docs/RISKS.md \
         docs/templates/DATA-MODEL.md docs/templates/API.md docs/templates/INVENTORY.md \
         docs/templates/runbook.md docs/templates/spec.md; do
  if [ -e "$DEST/$f" ]; then echo "skip (exists): $f"; continue; fi
  # This repo keeps its own CLAUDE.md and ci.yml; new projects get the templates.
  case "$f" in
    CLAUDE.md) src=CLAUDE.template.md ;;
    .github/workflows/ci.yml) src=.github/ci.template.yml ;;
    *) src="$f" ;;
  esac
  mkdir -p "$DEST/$(dirname "$f")"; cp -p "$src" "$DEST/$f"; echo "added: $f"
  # 2. Runner choice is applied to the two required-check workflows we just copied.
  if [ "$RUNNER" = self-hosted ] && [[ "$f" == .github/workflows/* ]]; then
    sed -i.bak 's/runs-on: ubuntu-[^ ]*/runs-on: [self-hosted]/' "$DEST/$f" && rm -f "$DEST/$f.bak"
  fi
done
grep -qF '.claude/worktrees/' "$DEST/.gitignore" 2>/dev/null || cat gitignore.append >> "$DEST/.gitignore"
echo "Runner: $RUNNER for ci and lane."
[ "$RUNNER" = hosted ] && echo "  Each lane run bills 1 minute and each ci run its length. If this account has ever paused pull_request CI for minutes, rerun with self-hosted."

[ -n "$REPO" ] || { echo "Files copied. Pass owner/repo as the 3rd argument to protect main."; exit 0; }

# 3. GitHub: ruleset FIRST. Auto-merge stays OFF until a red PR has been refused (--enable-auto-merge).
prev=$(gh api "repos/$REPO" --jq '[.allow_merge_commit,.allow_rebase_merge,.allow_squash_merge,.delete_branch_on_merge,.allow_auto_merge,.squash_merge_commit_title,.squash_merge_commit_message]|map(tostring)|join(" ")')
read -r p_merge p_rebase p_squash p_delete p_auto p_title p_message <<<"$prev"
rollback() {
  echo "GitHub setup failed. Restoring previous merge settings." >&2
  gh api -X PATCH "repos/$REPO" -F allow_merge_commit="$p_merge" -F allow_rebase_merge="$p_rebase" \
    -F allow_squash_merge="$p_squash" -F delete_branch_on_merge="$p_delete" -F allow_auto_merge="$p_auto" \
    -f squash_merge_commit_title="$p_title" -f squash_merge_commit_message="$p_message" >/dev/null
  exit 1
}
gh repo edit "$REPO" --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --delete-branch-on-merge --enable-auto-merge=false || rollback
# Squash commits carry the PR title and body, so the history keeps each PR's why.
gh api -X PATCH "repos/$REPO" -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null || rollback
gh api -X POST "repos/$REPO/rulesets" --input "$KIT/.github/ruleset-main.json" >/dev/null || rollback

for l in "lane:1-contained|0e8a16|Reversible, contained: auto-merge on green CI" \
         "lane:2-wide|fbca04|Reversible, wide: CI + one review, then auto-merge" \
         "lane:3-hard|d93f0b|Hard to reverse: the owner adds merge-ok and merges" \
         "merge-ok|5319e7|Owner only: approves a lane-3 merge"; do
  IFS="|" read -r n c d <<<"$l"; gh label create "$n" --repo "$REPO" --color "$c" --description "$d" --force >/dev/null
done

cat <<MSG
Ruleset 'main' is active. Auto-merge is OFF.
Next:
$( [ "$RUNNER" = self-hosted ] && echo "  0. Register a runner: https://github.com/$REPO/settings/actions/runners/new (until one is online, ci and lane queue and nothing merges)." )
  1. Fill the {{placeholders}} in CLAUDE.md, ci.yml (check + format) and HARD_PATHS in lane.yml; set PERSONAL_DATA in settings.json and .gitignore.
  2. Merge the kit PR (lane:2-wide) by hand once ci and lane are green.
  3. Prove it: open a PR with a deliberately failing test, label it lane:1-contained, wait for ci to go red.
  4. ./bootstrap.sh --enable-auto-merge $REPO <that PR number>   (checks it is BLOCKED with ci red, then enables auto-merge)
MSG
