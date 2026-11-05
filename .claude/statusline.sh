#!/bin/sh
# Status line: <project> · <branch> <●|✓> <↑a↓b> · <N>% ctx · <model> [· workers: N]
# Claude Code pipes a JSON blob on stdin. Only jq and git are used; no network. It never prints an error and exits 0.
# Fields (https://code.claude.com/docs/en/statusline): workspace.current_dir, cwd,
# context_window.used_percentage, model.display_name.

input=$(cat 2>/dev/null)
cwd="" used="" model=""
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
  used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
fi
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then cwd=$(pwd); fi

git_seg=""
if command -v git >/dev/null 2>&1; then
  dirs=$(git -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)
  gitdir=$(printf '%s\n' "$dirs" | sed -n 1p)
  common=$(printf '%s\n' "$dirs" | sed -n 2p)
  if [ -n "$gitdir" ] && [ -n "$common" ]; then
    project=$(basename "$(dirname "$common")")
    branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    mark="✓"
    [ -z "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -n 1)" ] || mark="●"
    sync=""
    counts=$(git -C "$cwd" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
    if [ -n "$counts" ]; then
      behind=${counts%%[!0-9]*}
      ahead=${counts##*[!0-9]}
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && sync=" ↑$ahead"
      if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
        if [ -n "$sync" ]; then sync="$sync↓$behind"; else sync=" ↓$behind"; fi
      fi
    fi
    git_seg="$project · $branch $mark$sync"
  fi
fi

out="$git_seg"
add() { if [ -n "$out" ]; then out="$out · $1"; else out="$1"; fi; }
case "$used" in
  '' | *[!0-9.]*) ;;
  *) add "${used%%.*}% ctx" ;;
esac
[ -z "$model" ] || add "$model"

# Open worker sessions, counted in the main checkout only (git dir equals common dir).
if [ -n "$git_seg" ] && [ "$gitdir" = "$common" ]; then
  n=0
  for f in "$common"/spawn/*.term; do [ -f "$f" ] && n=$((n + 1)); done
  [ "$n" -gt 0 ] && add "workers: $n"
fi

[ -n "$out" ] || out=$(basename "$cwd")
printf '%s\n' "$out"
exit 0
