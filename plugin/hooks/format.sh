#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# PostToolUse hook (matcher: Write|Edit). Formats the file Claude just wrote with the project's
# formatter, so formatting never reaches review as a finding and never needs a sweeping
# reformat commit.
#
# Configured in .claude/project.conf: FORMAT_CMD (the formatter, given the file as its last
# argument, e.g. `gofmt -w`, `npx --no-install prettier --write`, `ruff format`) and FORMAT_EXT
# (space-separated extensions it owns). With FORMAT_CMD empty this does nothing. It runs as one
# command and its arguments, with no shell (conf_exec, lib/conf.sh), and the value is origin/<main>'s,
# as this hook runs on whatever branch an edit lands on.
#
# Never blocks: a formatter failure must not stop an edit, and the gate's lint step is what catches
# a file the formatter could not handle. It tells Claude (hook_note, the one exit-0 channel that
# reaches it) only when the formatter could not start, or project.conf cannot say which it is: a
# formatter that never runs would otherwise read exactly like one with nothing to change.

ROOT=$(case $STRIDAL_FW in (*/.claude) dirname "$STRIDAL_FW" ;; (*) [ -n "${ROOT:-}" ] && echo "$ROOT" || git rev-parse --show-toplevel 2>/dev/null || pwd ;; esac)
# A `.` of a missing file is fatal with a shell-dependent status (dash exits 2): test first; without
# the config there is no formatter configured.
[ -f "$STRIDAL_FW/lib/conf.sh" ] || exit 0
# shellcheck disable=SC1091
. "$STRIDAL_FW/lib/conf.sh"
# This checkout's copy says only whether to look further: a branch that turns the formatter off runs
# no program, and the many projects with none pay nothing for git. Which program runs is main's.
[ -n "${FORMAT_CMD:-}" ] || conf_bad FORMAT_CMD || conf_bad FORMAT_EXT || exit 0
command -v jq >/dev/null 2>&1 || exit 0

f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$f" ] && [ -f "$f" ] || exit 0

# The checkout's FORMAT_EXT filters first, so a file no formatter owns pays no git; a branch can already
# turn the formatter off for itself, so this hands it nothing.
ext=${f##*.}
if ! conf_bad FORMAT_EXT; then
  case " ${FORMAT_EXT:-} " in *" $ext "*) ;; *) exit 0 ;; esac
fi
branch_cmd=$FORMAT_CMD
conf_keys_from_main "$STRIDAL_FW/lib/conf.sh" FORMAT_CMD FORMAT_EXT
if [ -n "$CONF_MAIN_NOTE" ] && [ -z "$CONF_MAIN_BAD_KEYS" ]; then
  hook_note PostToolUse "format.sh did not format this file: $CONF_MAIN_NOTE"
  exit 0
fi
# From here on this hook's keys are main's, so what it says of a refused one is too. With no remote
# they stayed the disk's, and so do its errors.
if [ -n "$CONF_MAIN_READ" ]; then CONF_BAD_KEYS=$CONF_MAIN_BAD_KEYS CONF_ERRORS=$CONF_MAIN_ERRORS; fi
if [ -z "${FORMAT_CMD:-}" ] && ! conf_bad FORMAT_CMD; then
  hook_note PostToolUse "format.sh did not format this file: origin's main names no FORMAT_CMD, and a hook does not run the program a branch names. A branch's formatter takes effect once it lands."
  exit 0
fi

# A FORMAT_EXT it could not read cannot say whose file this is, so that note comes before the filter;
# one for FORMAT_CMD comes after it, since a file the formatter does not own lost nothing.
if conf_bad FORMAT_EXT; then
  hook_note PostToolUse "format.sh did not format this file: $(conf_why FORMAT_EXT)"
  exit 0
fi
case " ${FORMAT_EXT:-} " in *" $ext "*) ;; *) exit 0 ;; esac
if conf_bad FORMAT_CMD; then
  hook_note PostToolUse "format.sh did not format this file: $(conf_why FORMAT_CMD)"
  exit 0
fi
[ -n "${FORMAT_CMD:-}" ] || exit 0

# Run from the file's own checkout, so a formatter resolved relative to the repo (a local
# node_modules/.bin, a venv) is the one that checkout carries.
dir=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null) || dir=$ROOT
rc=0
(cd "$dir" && conf_exec "$FORMAT_CMD" "$f") >/dev/null 2>&1 || rc=$?
case $rc in
  126 | 127) hook_note PostToolUse "format.sh did not format this file: FORMAT_CMD ($FORMAT_CMD, .claude/project.conf) could not start (exit $rc); it runs as one command and its arguments, with no shell." ;;
  *) [ "$branch_cmd" = "$FORMAT_CMD" ] || hook_note PostToolUse "format.sh ran the FORMAT_CMD origin's main names ($FORMAT_CMD). This branch's ($branch_cmd) takes effect once it lands." ;;
esac
exit 0
