#!/usr/bin/env bash
# Lean kit installer. Modes:
#   ./bootstrap.sh <dest-repo-dir> <hosted|self-hosted>                 copy files only (never overwrites), write .claude/kit.lock
#   ./bootstrap.sh <dest-repo-dir> <hosted|self-hosted> <owner/repo>    copy files, then protect main
#   ./bootstrap.sh --upgrade <dest-repo-dir> [--apply]                  compare a project with this kit and its lock; dry run unless --apply
#   ./bootstrap.sh --adopt <dest-repo-dir>                              write a lock for a project installed before locks existed
#   ./bootstrap.sh --enable-auto-merge <owner/repo> <red-PR-number>     only after a red PR was refused
#   ./bootstrap.sh --install-alias                                      append a `dispatch` alias to ~/.zshrc or ~/.bashrc (opt-in; also accepted with an install)
# GitHub steps need `gh auth login` as a repo admin. Private repos need GitHub Pro/Team for rulesets.
# --upgrade and --adopt never call gh and never delete a file (Stridal's ADR-0007).
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"

# --install-alias: the one thing this script writes outside the project (Stridal's ADR-0007, amended). Opt-in.
ALIAS_MARK="# stridal-dispatch-alias"
ALIAS_LINE="alias dispatch='\"\$(git rev-parse --show-toplevel)\"/.claude/bin/dispatch.sh'"
install_alias() {
  local rc
  case "$(basename "${SHELL:-}")" in
    zsh) rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *) echo "install-alias: SHELL is '${SHELL:-}', not zsh or bash. Nothing written. Add this to your shell rc yourself:"
       echo "  $ALIAS_LINE"; return 1 ;;
  esac
  if grep -qF "$ALIAS_MARK" "$rc" 2>/dev/null; then echo "Already in $rc: nothing changed."; return 0; fi
  # An rc that does not end in a newline would swallow the alias into its last line.
  if [ -s "$rc" ] && [ -n "$(tail -c 1 "$rc")" ]; then echo >> "$rc"; fi
  echo "$ALIAS_LINE $ALIAS_MARK" >> "$rc"
  echo "Wrote to $rc:"
  echo "  $ALIAS_LINE $ALIAS_MARK"
}
DO_ALIAS=0; ARGS=()
for a in "$@"; do if [ "$a" = --install-alias ]; then DO_ALIAS=1; else ARGS+=("$a"); fi; done
set -- ${ARGS[@]+"${ARGS[@]}"}
if [ "$DO_ALIAS" = 1 ]; then
  install_alias || exit 1
  [ $# -gt 0 ] || exit 0
fi

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

# The kit's file list: what a project receives, and what --upgrade compares.
FILES=(CLAUDE.md .claude/settings.json .claude/agents/reviewer.md .claude/agents/researcher.md
       .claude/hooks/one-way-guard.sh
       .claude/bin/scope-check.sh .claude/bin/check-evidence.sh .claude/bin/session.sh .claude/statusline.sh .claude/rules/EXAMPLE-migrations.md.example
       .claude/bin/dispatch-next.sh .claude/bin/as-agent.sh .claude/bin/token-expiry.sh
       .claude/bin/test-session.sh .claude/bin/test-dispatch.sh .claude/bin/test-token-expiry.sh
       .claude/bin/dispatch.sh .claude/bin/test-launcher.sh .claude/bin/test-scope-check.sh docs/runbooks/agent-token.md
       .claude/hooks/notify-waiting.sh .claude/skills/dispatch/SKILL.md .claude/skills/dispatch/worker-contract.md
       .github/lane/lane.sh .github/lane/test.sh
       .github/workflows/ci.yml .github/workflows/lane.yml .github/pull_request_template.md
       docs/adr/0000-template.md docs/ARCHITECTURE.md docs/RISKS.md
       docs/templates/DATA-MODEL.md docs/templates/API.md docs/templates/INVENTORY.md
       docs/templates/runbook.md docs/templates/spec.md)
LOCK=.claude/kit.lock
VERSION=$(tr -d '[:space:]' < "$KIT/VERSION")

# This repo keeps its own CLAUDE.md and ci.yml; new projects get the templates.
src_for() {
  case "$1" in
    CLAUDE.md) echo CLAUDE.template.md ;;
    .github/workflows/ci.yml) echo .github/ci.template.yml ;;
    *) echo "$1" ;;
  esac
}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/kit-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
# stage <file> <runner>: the kit's copy of a file as a project on that runner receives it; prints its path.
stage() {
  local out="$STAGE/$1"
  mkdir -p "$(dirname "$out")"; cp -p "$KIT/$(src_for "$1")" "$out"
  # The runner choice is applied to the two required-check workflows.
  if [ "$2" = self-hosted ] && [[ "$1" == .github/workflows/* ]]; then
    sed -i.bak 's/runs-on: ubuntu-[^ ]*/runs-on: [self-hosted]/' "$out" && rm -f "$out.bak"
  fi
  echo "$out"
}
# Lock lines are "<sha256 or -> <path>" (two spaces); "-" means edited, never equal to a file's hash. See Stridal's ADR-0007.
lock_hash() { awk -v p="$2" '$2 == p && $1 != "version" && $1 != "runner" { print $1; exit }' "$1/$LOCK"; }
lock_runner() { awk '$1 == "runner" { print $2; exit }' "$1/$LOCK"; }
lock_version() { awk '$1 == "version" { print $2; exit }' "$1/$LOCK"; }
# write_lock <dest> <runner> <entries file>: header plus entries, sorted by path, replacing the lock whole.
write_lock() {
  mkdir -p "$1/.claude"
  { echo "# stridal kit.lock 1: sha256 of each file as the kit installed it; - means edited. Written by bootstrap.sh."
    echo "version $VERSION"; echo "runner $2"
    LC_ALL=C sort -k2 "$3"; } > "$STAGE/lock.new"
  cp "$STAGE/lock.new" "$1/$LOCK"
}
detect_runner() { if grep -q 'runs-on: \[self-hosted\]' "$1/.github/workflows/ci.yml" 2>/dev/null; then echo self-hosted; else echo hosted; fi; }

if [ "${1:-}" = "--adopt" ]; then
  [ $# -eq 2 ] || { echo "usage: ./bootstrap.sh --adopt <dest-repo-dir>"; exit 1; }
  DEST="$2"
  [ -d "$DEST" ] || { echo "adopt: $DEST is not a directory"; exit 1; }
  [ ! -e "$DEST/$LOCK" ] || { echo "adopt: $DEST/$LOCK already exists; nothing written"; exit 1; }
  runner=$(detect_runner "$DEST"); : > "$STAGE/entries"; same=0; edited=0
  for f in "${FILES[@]}"; do
    [ -e "$DEST/$f" ] || continue
    s=$(stage "$f" "$runner")
    if [ "$(sha "$DEST/$f")" = "$(sha "$s")" ]; then echo "$(sha "$s")  $f" >> "$STAGE/entries"; same=$((same + 1))
    else echo "-  $f" >> "$STAGE/entries"; edited=$((edited + 1)); echo "differs from the kit, recorded as edited: $f"; fi
  done
  write_lock "$DEST" "$runner" "$STAGE/entries"
  echo "adopt: wrote $DEST/$LOCK (version $VERSION, runner $runner): $same files match the kit, $edited recorded as edited."
  echo "Next: ./bootstrap.sh --upgrade $DEST"
  exit 0
fi

if [ "${1:-}" = "--upgrade" ]; then
  usage="usage: ./bootstrap.sh --upgrade <dest-repo-dir> [--apply]"
  [ $# -ge 2 ] && [ $# -le 3 ] || { echo "$usage"; exit 1; }
  DEST="$2"; APPLY=0
  case "${3:-}" in "") ;; --apply) APPLY=1 ;; *) echo "$usage"; exit 1 ;; esac
  [ -d "$DEST" ] || { echo "upgrade: $DEST is not a directory"; exit 1; }
  [ -f "$DEST/$LOCK" ] || { echo "upgrade: $DEST has no $LOCK, so there is nothing to compare against. Nothing written."
    echo "  If it was installed before locks existed, run: ./bootstrap.sh --adopt $DEST"; exit 1; }
  runner=$(lock_runner "$DEST"); case "$runner" in hosted|self-hosted) ;; *) echo "upgrade: $DEST/$LOCK has no valid runner line. Nothing written."; exit 1 ;; esac
  P="would "; [ "$APPLY" = 1 ] && P=""
  [ "$APPLY" = 1 ] || echo "Dry run: nothing is written. Add --apply to carry out this plan."
  echo "Project at kit $(lock_version "$DEST"), this kit is $VERSION (runner $runner)."
  : > "$STAGE/changes"; : > "$STAGE/touched"; : > "$STAGE/kept"; n_add=0; n_rep=0; n_keep=0; n_cur=0
  for f in "${FILES[@]}"; do
    [ "$f" != CLAUDE.md ] || continue   # never touched; its diff is printed below
    s=$(stage "$f" "$runner"); ks=$(sha "$s")
    if [ ! -e "$DEST/$f" ]; then
      echo "${P}add: $f"; n_add=$((n_add + 1)); echo "$f" >> "$STAGE/touched"
      if [ "$APPLY" = 1 ]; then mkdir -p "$DEST/$(dirname "$f")"; cp -p "$s" "$DEST/$f"; echo "$ks  $f" >> "$STAGE/changes"; fi
      continue
    fi
    ps=$(sha "$DEST/$f"); ls=$(lock_hash "$DEST" "$f")
    if [ "$ps" = "$ks" ]; then n_cur=$((n_cur + 1))
    elif [ "$ps" = "$ls" ]; then
      echo "${P}replace (never edited): $f"; n_rep=$((n_rep + 1)); echo "$f" >> "$STAGE/touched"
      if [ "$APPLY" = 1 ]; then cp -p "$s" "$DEST/$f"; echo "$ks  $f" >> "$STAGE/changes"; fi
    elif [ "$ks" = "$ls" ]; then
      echo "keep (edited here, kit unchanged): $f"; n_keep=$((n_keep + 1)); echo "$f unchanged" >> "$STAGE/kept"
    else
      echo "keep (edited here, kit changed): $f -> ${P}write $f.kit-new"; n_keep=$((n_keep + 1)); echo "$f kit-new" >> "$STAGE/kept"
      if [ "$APPLY" = 1 ]; then cp -p "$s" "$DEST/$f.kit-new"; fi
    fi
  done
  # In the lock, no longer in the kit's list: reported, never deleted.
  while read -r h p; do
    case "$h" in "#"*|version|runner|"") continue ;; esac
    found=0; for f in "${FILES[@]}"; do [ "$f" = "$p" ] && found=1; done
    [ "$found" = 1 ] || echo "dropped from the kit (left in place, delete it yourself if you want): $p"
  done < "$DEST/$LOCK"
  if [ -f "$DEST/CLAUDE.md" ]; then
    if diff -u "$DEST/CLAUDE.md" "$KIT/CLAUDE.template.md" > "$STAGE/claude.diff"; then echo "CLAUDE.md: same as the template."
    else echo "CLAUDE.md is never touched. The template differs from yours (- yours, + template):"; cat "$STAGE/claude.diff"; fi
  fi
  # Kit files depend on each other (.claude/kit.deps). A file added or replaced above may need a file kept as edited:
  # warn, naming the .kit-new to merge first. Only a warning: nothing is written or removed because of it (Stridal's ADR-0007).
  if [ -f "$KIT/.claude/kit.deps" ]; then
    while IFS=: read -r df needs; do
      case "$df" in "#"*|"") continue ;; esac
      grep -qxF -e "$df" "$STAGE/touched" || continue
      for nf in $needs; do
        k=$(awk -v p="$nf" '$1 == p { print $2; exit }' "$STAGE/kept")
        [ -n "$k" ] || continue
        if [ "$k" = kit-new ]; then
          echo "WARNING: $df needs $nf, which you edited and upgrade kept. Merge $nf.kit-new into $nf first, or $df may not work."
        else
          echo "WARNING: $df needs $nf, which you edited and upgrade kept. Check that your $nf still supports what $df calls."
        fi
      done
    done < "$KIT/.claude/kit.deps"
  fi
  echo "Summary: $n_add to add, $n_rep to replace, $n_keep kept as edited, $n_cur already current."
  if [ "$APPLY" = 1 ] && [ -s "$STAGE/changes" ]; then
    # Only files upgrade changed are rewritten in the lock; every other line stays as it was.
    awk 'NR == FNR { new[$2] = $0; next } /^#/ || $1 == "version" || $1 == "runner" { next } !($2 in new) { print }
         END { for (p in new) print new[p] }' "$STAGE/changes" "$DEST/$LOCK" > "$STAGE/entries"
    write_lock "$DEST" "$runner" "$STAGE/entries"
    echo "Wrote $DEST/$LOCK (version $VERSION)."
  fi
  exit 0
fi

[ $# -ge 1 ] || { echo "usage: see the header of bootstrap.sh"; exit 1; }
[ $# -ge 2 ] || { echo "runner choice required: hosted or self-hosted"; exit 1; }
DEST="$1"; RUNNER="$2"; REPO="${3:-}"
case "$RUNNER" in hosted|self-hosted) ;; *) echo "runner must be 'hosted' or 'self-hosted'"; exit 1;; esac

# 1. Files (never overwrite). The lock is written only on the first run; later runs leave it alone.
: > "$STAGE/entries"
for f in "${FILES[@]}"; do
  s=$(stage "$f" "$RUNNER")
  if [ -e "$DEST/$f" ]; then
    echo "skip (exists): $f"
    # A file that was already there is recorded as it stands if it equals the kit's copy, else as edited.
    if [ "$(sha "$DEST/$f")" = "$(sha "$s")" ]; then echo "$(sha "$s")  $f" >> "$STAGE/entries"; else echo "-  $f" >> "$STAGE/entries"; fi
    continue
  fi
  mkdir -p "$DEST/$(dirname "$f")"; cp -p "$s" "$DEST/$f"; echo "added: $f"
  echo "$(sha "$s")  $f" >> "$STAGE/entries"
done
if [ -e "$DEST/$LOCK" ]; then echo "skip (exists): $LOCK"; else write_lock "$DEST" "$RUNNER" "$STAGE/entries"; echo "added: $LOCK (kit version $VERSION)"; fi
grep -qF '.claude/worktrees/' "$DEST/.gitignore" 2>/dev/null || cat "$KIT/gitignore.append" >> "$DEST/.gitignore"
echo "Runner: $RUNNER for ci and lane."
[ "$RUNNER" = hosted ] && echo "  Each lane run bills 1 minute (it runs on two events per PR update) and each ci run its length. If this account has ever paused pull_request CI for minutes, rerun with self-hosted."

echo "Public repo? lane.yml runs on pull_request_target, which GitHub blocks by default for public repos from 2026-12-02, so without an Actions policy that allows it there is no lane check and nothing merges. Setting it is a GitHub settings change (Settings > Actions > General) and needs the owner's yes; this script does not do it."

# Offered, written only with --install-alias: it resolves the repo when you use it, so one alias serves every kit project.
if [ "$DO_ALIAS" = 0 ]; then
  echo "To start a project's dispatcher with one command (from any directory inside it), add this to your shell rc yourself,"
  echo "or rerun with --install-alias to have it appended to ~/.zshrc or ~/.bashrc:"
  echo "  $ALIAS_LINE"
fi
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
