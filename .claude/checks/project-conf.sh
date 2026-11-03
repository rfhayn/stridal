#!/bin/sh
# project-conf.sh: project.conf is data, not a program (OPS-219, lib/conf.sh). A branch can edit it and
# every hook loads it, so what it holds runs nowhere: not in conf.sh, not in any hook or the status
# line, not in the gate's own readers. FORMAT_CMD, ROADMAP_PARSER, ROADMAP_NORMALIZER (and
# BATCH_REGENERATE: checks/batch.sh) run as an argv with no shell, and a value that needs a shell
# fails by name. The refusal of a guard.d rule that differs from origin/<main>, and the block on a
# merge while a line is refused, are in checks/merge-guard.sh, through the real guard; the gate's FAIL
# is in checks/gate.sh; the plugin's scaffold.sh is in framework/internal/plugin.
#
# Each proof that something did not run is a stamp in $CAN it would make. What makes that evidence is
# the positive beside it: the same fixture, the key read and applied.
# Also: every hook that loads the conf, and the status line, are its callers (the callers, rule 3).
. "$(dirname "$0")/lib.sh"
need git jq

S=$(scratch)
CAN="$S/can"; mkdir -p "$CAN" "$S/home"
F="$S/proj"; new_repo "$F"
mkdir -p "$F/.claude/lib" "$F/.claude/hooks/lib" "$F/src"
cp "$ROOT/.claude/lib/"* "$F/.claude/lib/" 2>/dev/null
cp "$ROOT/.claude/hooks/"*.sh "$F/.claude/hooks/"
cp "$ROOT/.claude/hooks/lib/"* "$F/.claude/hooks/lib/"
cp "$ROOT/.claude/statusline.sh" "$F/.claude/"
git -C "$F" add -A && git -C "$F" commit -qm base
C="$F/.claude/project.conf"
empty() { [ -z "$(ls "$CAN")" ]; }
clear_can() { rm -f "$CAN"/*; }
# get KEY: KEY as conf.sh leaves it, read in a subshell; what conf.sh said goes to $S/err.
get() { (ROOT=$F; . "$F/.claude/lib/conf.sh" 2>"$S/err"; eval "printf '%s' \"\${$1-}\""); }
errors() { (ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; printf '%s' "$CONF_ERRORS"); }

# ── The grammar: what a line may be ─────────────────────────────────────────────────────────────
# reads 'LINE' WANT LABEL: the line is read clean and PROJECT_NAME is WANT.
reads() {
  printf '%s\n' "$1" > "$C"
  v=$(get PROJECT_NAME); e=$(errors)
  [ "$v" = "$2" ] && [ -z "$e" ] && ok "grammar: $3" || fail "grammar: $3: read '$v', errors: $e"
}
reads 'PROJECT_NAME="a b"'                 'a b'      'KEY="value"'
reads "PROJECT_NAME='a b'"                 'a b'      "KEY='value'"
reads 'PROJECT_NAME=ab/c.d:e,f@g%h+i=j-k'  'ab/c.d:e,f@g%h+i=j-k' 'KEY=value, bare'
reads 'PROJECT_NAME=""'                    ''         'an empty value overrides the default'
reads 'PROJECT_NAME='                      ''         'KEY= is empty'
reads '   PROJECT_NAME="a"   '             'a'        'indented, blanks after'
reads 'PROJECT_NAME="a"   # a note'        'a'        'a comment after the value'
reads 'PROJECT_NAME=a # a note'            'a'        'a comment after a bare value'
reads 'PROJECT_NAME="a#b"'                 'a#b'      'a # inside quotes is the value'
reads "PROJECT_NAME='\$(x) \`y\` \\z'"     '$(x) `y` \z' 'single quotes are literal, in a shell and here'
reads 'PROJECT_NAME="[^ ]* — ♪"'           '[^ ]* — ♪' 'patterns and non-ASCII in double quotes'
reads '# PROJECT_NAME="no"'                'Project'  'a comment is nothing'
printf 'PROJECT_NAME="first"\nPROJECT_NAME="last"\n' > "$C"
[ "$(get PROJECT_NAME)" = last ] && ok "grammar: the last of two lines wins, as in a shell" || fail "grammar: two lines read $(get PROJECT_NAME)"
printf 'PROJECT_NAME="no newline at the end"' > "$C"
[ "$(get PROJECT_NAME)" = "no newline at the end" ] && ok "grammar: a last line with no newline is read" || fail "grammar: the last line was dropped: $(get PROJECT_NAME)"

# refuses 'LINE' KEY LABEL: refused by name, the default kept, nothing run; the line after it still reads.
refuses() {
  printf '%s\nOWNER_NAME="after"\n' "$1" > "$C"
  clear_can
  e=$(errors); bad=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_bad "$2" && echo yes)
  v=$(get OWNER_NAME)
  if [ -n "$e" ] && [ "$bad" = yes ] && [ "$v" = after ] && grep -q 'line 1' "$S/err" && empty
  then ok "refused: $3"
  else fail "refused: $3: errors '$e', conf_bad $2 '$bad', OWNER_NAME '$v', stderr $(cat "$S/err"), ran: $(ls "$CAN" | tr '\n' ' ')"; fi
}
refuses "PROJECT_NAME=\"\$(touch $CAN/a)\""        PROJECT_NAME 'a command substitution in double quotes'
refuses "PROJECT_NAME=\$(touch $CAN/a)"            PROJECT_NAME 'a bare command substitution'
refuses "PROJECT_NAME=\"\`touch $CAN/a\`\""        PROJECT_NAME 'a backtick substitution'
refuses 'PROJECT_NAME="$HOME/x"'                   PROJECT_NAME 'a variable: nothing expands'
refuses 'PROJECT_NAME="$ROOT/x"'                   PROJECT_NAME 'even $ROOT: nothing expands'
refuses 'PROJECT_NAME="a\"b"'                      PROJECT_NAME 'a backslash in double quotes'
refuses 'PROJECT_NAME=~/x'                         PROJECT_NAME 'a tilde'
refuses "PROJECT_NAME=\"a\"; touch $CAN/a"         PROJECT_NAME 'a command after the value'
refuses "PROJECT_NAME=\"a\" && touch $CAN/a"       PROJECT_NAME 'a list after the value'
refuses "PROJECT_NAME=a touch $CAN/a"              PROJECT_NAME 'a command with a bare assignment before it'
refuses 'PROJECT_NAME="a"b'                        PROJECT_NAME 'a word stuck to the closing quote'
refuses 'PROJECT_NAME="a"#b'                       PROJECT_NAME 'no blank before the #: a shell would read it as the value'
refuses 'PROJECT_NAME="never closed'               PROJECT_NAME 'an open quote: a value is one line'
refuses "touch $CAN/a"                             '?' 'a command'
refuses "if touch $CAN/a; then :; fi"              '?' 'a compound command'
refuses 'export PROJECT_NAME="a"'                  '?' 'export: nothing project.conf sets reaches a child'
refuses 'PROJECT_NAME = "a"'                       '?' 'blanks around ='
refuses 'project_name="a"'                         '?' 'a lower-case key: those are the scripts'"'"' own variables'
refuses '_PRIVATE="a"'                             '?' 'a key that does not start with a letter'
refuses '="a"'                                     '?' 'no key at all'
refuses 'A:B="a"'                                  '?' 'a key with other characters'
printf 'touch %s/sourced\n' "$CAN" > "$S/other.conf"
refuses ". $S/other.conf"                          '?' 'sourcing another file'
printf 'PROJECT_NAME="$(touch %s/a)"\n' "$CAN" > "$C"
[ "$(get PROJECT_NAME)" = Project ] && ok "a refused line leaves the key's default" || fail "a refused line set '$(get PROJECT_NAME)'"
for sh_ in sh bash; do
  command -v "$sh_" >/dev/null 2>&1 || continue
  # Inside a script that runs set -eu (the gate), a refused line must not end the script.
  v=$(cd "$F" && ROOT=$F "$sh_" -c 'set -eu; . "$ROOT/.claude/lib/conf.sh" 2>/dev/null; printf "%s" "$CONF_BAD_KEYS"') \
    && [ "$v" = " PROJECT_NAME" ] && ok "a refused line does not end a $sh_ script under set -eu" || fail "$sh_ -eu: exit or '$v'"
done

# ── A key is on the allowlist: a known key, or the project's own prefix ───────────────────────
# The first row is what a shell reads for itself, the second what tools and the model do; none of them
# is special-cased, so the same line holds a name nobody has thought of (the last).
for k in PATH IFS HOME ENV BASH_ENV CDPATH PS4 TMOUT OPTIND OPTERR POSIXLY_CORRECT LC_ALL LANG TZ RANDOM \
  ROOT TMPDIR GIT_DIR LD_PRELOAD DYLD_INSERT_LIBRARIES GUARD_RULE_TIMEOUT CLAUDE_PROJECT_DIR CONF_ERRORS NOBODY_THOUGHT_OF_THIS; do
  printf '%s="%s/there"\n' "$k" "$S" > "$C"
  v=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>"$S/err"; conf_bad "$k" || echo not-refused
      eval "printf '%s' \"\${$k-}\"")
  case $v in
    *"$S/there"* | not-refused*) fail "project.conf set $k: $v" ;;
    *) grep -q 'PROJECT_' "$S/err" && ok "$k is refused by project.conf, with a message naming the prefix" || fail "$k: no prefix named: $(cat "$S/err")" ;;
  esac
done
printf 'GATE_TAIL_LINES="9"\n' > "$C"
case $(errors) in *environment*) ok "...and for a variable the scripts read by its exact name, it says the environment still sets it" ;; *) fail "no word on the environment: $(errors)" ;; esac
printf 'PROJECT_OURS="from-conf"\n' > "$C"
v=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; printf '%s|%s|' "$PROJECT_OURS" "$CONF_ERRORS"; env | grep -c '^PROJECT_OURS=')
[ "$v" = "from-conf||0" ] && ok "a PROJECT_ key is the project's: set, and not exported" || fail "PROJECT_ key: $v"
# No name a shell reads carries the prefix: not bash's variables, not dash's (it has only POSIX's).
if command -v bash >/dev/null 2>&1; then
  v=$(env -i bash -c 'compgen -v PROJECT_ 2>/dev/null; set' | grep -c '^PROJECT_')
  [ "$v" = 0 ] && ok "bash reads no PROJECT_ variable" || fail "bash holds $v PROJECT_ variables"
fi
printf 'GATE="from-conf"\n' > "$C"
v=$(GATE=from-env; export GATE; ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; printf '%s|%s' "$GATE" "$CONF_BAD_KEYS")
[ "$v" = "from-conf|" ] && ok "a key the model knows is the project's, whatever the environment says" || fail "known key: $v"
# Every default conf.sh sets is on the list (framework/internal/template holds the shipped modules' too).
missing=""
for k in $(grep -oE '^[A-Z][A-Z0-9_]*=' "$F/.claude/lib/conf.sh" | tr -d = | grep -vE '^CONF_' | sort -u); do
  (ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; _conf_key_ok "$k") || missing="$missing $k"
done
[ -z "$missing" ] && ok "_conf_known holds every default conf.sh sets" || fail "defaults missing from _conf_known:$missing"
# A project's own module.conf is the same text, so it is held to the same list: "declared by a module"
# would let that text declare anything.
mkdir -p "$F/.claude/modules/own"
printf 'name="own"\nTMOUT="1"\nOWN_KEY="set"\nPROJECT_OWN_KEY="set"\n' > "$F/.claude/modules/own/module.conf"
printf 'MODULES="own"\n' > "$C"
v=$(unset TMOUT OWN_KEY; ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; printf '%s|%s|%s|%s' "${TMOUT-}" "${OWN_KEY-}" "${PROJECT_OWN_KEY-}" "$CONF_BAD_KEYS")
[ "$v" = "||set| TMOUT OWN_KEY" ] && ok "a module.conf key off the list is refused by name; one with the prefix is set" || fail "module.conf: $v"
rm -rf "$F/.claude/modules"

# ── A file that cannot be heard is an error, not "no conf" ────────────────────────────────────
rm -f "$C"; mkdir "$C"
v=$(errors); bad=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_bad GATE && echo yes)
[ -n "$v" ] && [ "$bad" = yes ] && ok "a directory at project.conf is an error, which any key may have meant" || fail "directory: errors '$v', bad '$bad'"
rmdir "$C"; ln -s "$S/no-such-file" "$C"
v=$(errors); [ -n "$v" ] && ok "a dangling link at project.conf is an error" || fail "dangling link read as no conf"
rm -f "$C"
v=$(errors); [ -z "$v" ] && ok "project.conf truly absent is no conf: the defaults, no error" || fail "absent: $v"

# ── CRLF and NUL read the same way in every shell: refused ────────────────────────────────────
printf 'PROJECT_NAME="a"\r\nOWNER_NAME="b"\r\n' > "$C"
e=$(errors)
case $e in *CRLF*) ok "CRLF line endings are refused, by that name" ;; *) fail "CRLF: errors '$e', PROJECT_NAME '$(get PROJECT_NAME)'" ;; esac
[ "$(printf '%s\n' "$e" | wc -l | tr -d ' ')" = 1 ] && ok "...with one error for the whole file" || fail "CRLF gave many errors: $e"
for line in 'PROJECT_NAME=a' '   ' 'PROJECT_NAME='; do
  printf '%s\r\n' "$line" > "$C"
  case $(errors) in *CRLF*) ok "...and a carriage return after '$line' is too" ;; *) fail "a carriage return after '$line' passed: $(errors)" ;; esac
done
printf '# a note\r\n' > "$C"
[ -z "$(errors)" ] && ok "a carriage return in a comment changes no value, so it passes" || fail "a CR comment: $(errors)"
# A value git would read as an option can run a program, whichever key it came in by (lib/conf.sh).
for k in MAIN_BRANCH BRANCH_CHANGE BRANCH_FIX BRANCH_OPS BRANCH_SESSION_CLOSE RECORDS_BASELINE COAUTHOR_HEALTH_SINCE ADR_DIR JOURNAL CHANGES_DIR ROADMAP; do
  printf '%s="--upload-pack=touch %s/opt"\n' "$k" "$CAN" > "$C"
  v=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>"$S/err"; conf_bad "$k" && echo refused; eval "printf '%s' \"\${$k-}\"")
  case $v in *upload-pack*) fail "$k took a value git reads as an option: $v" ;; refused*) ok "$k refuses a value starting with -" ;; *) fail "$k: not refused: $v" ;; esac
done
for k in GATE_QUICK_FLAGS GATE_FAIL_PATTERN GATE_TAIL_EXCLUDE PROJECT_FLAGS; do
  printf '%s="--a-value"\n' "$k" > "$C"
  [ "$(get "$k")" = --a-value ] && ok "$k may start with -: it is no argument to git" || fail "$k refused its value: $(errors)"
done
printf 'PROJECT_NAME="x\000y"\nOWNER_NAME="b"\n' > "$C"
v=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_nul_check 2>/dev/null; printf '%s' "$CONF_ERRORS")
case $v in *"NUL byte"*) ok "conf_nul_check refuses a NUL byte, by name, whatever this shell made of the line" ;; *) fail "NUL: $v" ;; esac
printf 'PROJECT_NAME="clean"\n' > "$C"
v=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_nul_check 2>/dev/null; printf '%s' "$CONF_ERRORS")
[ -z "$v" ] && ok "...and says nothing of a file with none" || fail "NUL check on a clean file: $v"

# ── A hook does not hang on a small file: the limits ──────────────────────────────────────────
longv=$(awk 'BEGIN { for (i = 0; i < 490; i++) printf "a" }')
# load_under SHELL FILE: load it under SHELL, bounded; prints the errors.
load_under() { (cd "$F" && ROOT=$F "$1" -c '. "$ROOT/.claude/lib/conf.sh" 2>/dev/null; printf "%s" "$CONF_ERRORS"'); }
# The most work the limits allow: 1000 of the longest lines, each a key that parses.
awk -v v="$longv" 'BEGIN { for (i = 0; i < 1000; i++) printf "PROJECT_K%d=\"%s\"\n", i, v }' > "$C"
for sh_ in sh dash; do
  command -v "$sh_" >/dev/null 2>&1 || { [ "$sh_" = dash ] && continue; fail "no sh"; continue; }
  t0=$(date +%s)  # wall-clock: the bound under test is real time, what a hook timeout counts
  e=$(load_under "$sh_")
  t1=$(date +%s)  # wall-clock: as above
  [ -z "$e" ] && [ $((t1 - t0)) -le "$(slow 30)" ] && ok "$sh_: 1000 of the longest lines read clean, in $((t1 - t0)) s" || fail "$sh_: near the limits: $((t1 - t0)) s, errors: $(printf '%s' "$e" | head -c 200)"
done
awk 'BEGIN { for (i = 0; i < 1001; i++) print "PROJECT_A=\"b\"" }' > "$C"
e=$(errors); case $e in *"more than 1000 lines"*) [ "$(printf '%s\n' "$e" | wc -l | tr -d ' ')" = 1 ] && ok "line 1001 refuses the file, with one error" || fail "line count: many errors" ;; *) fail "1001 lines read: $e" ;; esac
awk 'BEGIN { for (i = 0; i < 1000; i++) print "PROJECT_A=\"b\"" }' > "$C"
[ -z "$(errors)" ] && ok "...1000 lines do not" || fail "1000 lines refused: $(errors)"
awk 'BEGIN { printf "PROJECT_A=\""; for (i = 0; i < 501; i++) printf "a"; print "\"" }' > "$C"
e=$(errors); case $e in *"over 512"*) ok "a line of 513 characters refuses the file" ;; *) fail "513 characters read: $e" ;; esac
awk 'BEGIN { printf "PROJECT_A=\""; for (i = 0; i < 500; i++) printf "a"; print "\"" }' > "$C"
[ -z "$(errors)" ] && ok "...a line of 512 does not" || fail "512 characters refused: $(errors)"
awk -v v="$longv" 'BEGIN { for (i = 0; i < 60; i++) print "NOT_A_KEY" i "=\"" v "\"" }' > "$C"
e=$(errors); case $e in *"20 lines it cannot read"*) [ "$(printf '%s\n' "$e" | wc -l | tr -d ' ')" -le 21 ] && ok "20 refused lines stop the reading, with one more error" || fail "error flood" ;; *) fail "no stop at 20: $(printf '%s' "$e" | tail -n 1 | head -c 200)" ;; esac
# The same limit holds a project's own module.conf, which needs no line that parses.
mkdir -p "$F/.claude/modules/huge"
awk 'BEGIN { print "name=\"huge\""; for (i = 0; i < 5000; i++) print "NOT_A_KEY" i "=\"x\"" }' > "$F/.claude/modules/huge/module.conf"
printf 'MODULES="huge"\n' > "$C"
for sh_ in sh dash; do
  command -v "$sh_" >/dev/null 2>&1 || continue
  t0=$(date +%s)  # wall-clock: as above
  e=$(load_under "$sh_")
  t1=$(date +%s)  # wall-clock: as above
  case $e in *"20 keys it cannot read"*) [ "$(printf '%s\n' "$e" | wc -l | tr -d ' ')" -le 21 ] && [ $((t1 - t0)) -le "$(slow 10)" ] && ok "$sh_: 5000 keys off the list in a module.conf stop at 20, in $((t1 - t0)) s" || fail "$sh_: module.conf: $((t1 - t0)) s" ;; *) fail "$sh_: module.conf did not stop: $(printf '%s' "$e" | tail -n 1 | head -c 160)" ;; esac
done
rm -rf "$F/.claude/modules"
awk 'BEGIN { for (i = 0; i < 1000000; i++) printf "\"="; print "" }' > "$C"
for sh_ in sh dash; do
  command -v "$sh_" >/dev/null 2>&1 || continue
  t0=$(date +%s)  # wall-clock: as above
  e=$(load_under "$sh_")
  t1=$(date +%s)  # wall-clock: as above
  case $e in *"over 512"*) [ $((t1 - t0)) -le "$(slow 30)" ] && ok "$sh_: a 2 MB line is refused in $((t1 - t0)) s" || fail "$sh_: 2 MB line took $((t1 - t0)) s" ;; *) fail "$sh_: 2 MB line: $(printf '%s' "$e" | head -c 200)" ;; esac
done

# ── Every entry point: a project.conf holding substitutions runs nothing ──────────────────────
hostile() {
  { printf 'PROJECT_NAME="$(touch %s/double)"\n' "$CAN"
    printf 'OWNER_NAME=`touch %s/backtick`\n' "$CAN"
    printf 'OWNER_ROLE="x"; touch %s/after\n' "$CAN"
    printf 'touch %s/plain\n' "$CAN"
    printf 'STATUS_MARK=a touch %s/prefixed\n' "$CAN"
    printf 'if touch %s/compound; then :; fi\n' "$CAN"
    printf 'GATE="tools/own-gate.sh"\n'
    printf 'GATE_CLEAN_ROOM="archive"\n'; } > "$C"
}
hostile
clear_can; (ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; printf '%s\n' "$GATE" > "$S/gate-seen")
empty && [ "$(cat "$S/gate-seen")" = tools/own-gate.sh ] && ok "conf.sh: ran nothing, and read the valid key after the lines it refused" \
  || fail "conf.sh: ran $(ls "$CAN" | tr '\n' ' '); GATE read as $(cat "$S/gate-seen")"
# The authority: every hook in the directory that names the loader, not a list of them.
PAY='{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"check","tool_input":{"command":"git status"},"isolation":"worktree"}'
n=0
for h in "$F/.claude/hooks/"*.sh; do
  grep -q 'lib/conf.sh' "$h" || continue
  n=$((n + 1)); clear_can
  printf '%s' "$PAY" | (cd "$F" && HOME="$S/home" CLAUDE_PROJECT_DIR="$F" sh "$h") >/dev/null 2>&1
  empty && ok "$(basename "$h") runs nothing from project.conf" || fail "$(basename "$h") ran: $(ls "$CAN" | tr '\n' ' ')"
done
[ "$n" -ge 6 ] && ok "$n hooks load the conf (non-vacuity)" || fail "only $n hooks name lib/conf.sh: the loop above would pass vacuously"
clear_can
out=$(printf '{"cwd":"%s"}' "$F" | (cd "$F" && HOME="$S/home" sh "$F/.claude/statusline.sh" 2>/dev/null))
empty && [ -n "$out" ] && ok "the status line runs nothing from project.conf, and still renders" || fail "statusline ran: $(ls "$CAN" | tr '\n' ' '); out: $out"
# The gate's own readers, which read one key before the gate has loaded the conf.
wait_rel=$(gate_wait_path)
if [ -f "$ROOT/$wait_rel" ]; then
  ci="$F/$(dirname "$wait_rel")"; mkdir -p "$ci/lib"
  cp "$ROOT/$wait_rel" "$ci/"; cp "$ROOT/$(dirname "$wait_rel")/lib/gate-state.sh" "$ci/lib/"
  printf '.claude/\n%s/\n' "$(dirname "$wait_rel" | cut -d/ -f1)" >> "$F/.git/info/exclude"
  clear_can
  # A copy that predates this says so, once, rather than failing the two cases below on their faces.
  if ! stale_copy "$ROOT/$wait_rel" lib/conf.sh; then
    out=$(cd "$F" && GATE_WAIT_SECONDS=0 sh "$F/$wait_rel" 2>&1)
    case $out in
      *tools/own-gate.sh*) empty && ok "gate-wait.sh runs nothing from project.conf, and reads GATE from it" || fail "gate-wait.sh ran: $(ls "$CAN" | tr '\n' ' ')" ;;
      *) fail "gate-wait.sh did not read GATE from project.conf: $out" ;;
    esac
  fi
  clear_can
  if ! stale_copy "$ROOT/$(dirname "$wait_rel")/lib/gate-state.sh" lib/conf.sh; then
    # What run-local.sh runs first, under the same set -eu.
    (cd "$F" && unset ROOT STRIDAL_GATE_STATE GATE_CLEAN_ROOM; bash -c 'set -euo pipefail; . "$1"; gate_state_start run-local.sh --quick' _ "$ci/lib/gate-state.sh") >/dev/null 2>&1
    st=$(cat "$(git -C "$F" rev-parse --absolute-git-dir)/ci-gate.state" 2>/dev/null)
    case $st in
      *subject=commit*) empty && ok "gate-state.sh runs nothing from project.conf, and reads GATE_CLEAN_ROOM from it" || fail "gate-state.sh ran: $(ls "$CAN" | tr '\n' ' ')" ;;
      *) fail "gate-state.sh did not read GATE_CLEAN_ROOM from project.conf: $st" ;;
    esac
  fi
else
  fail "cannot run: $wait_rel is not in this project"
fi
# The gate in CI sources the repository's own copy of conf.sh, which the plugin never overwrites.
# Spelt with the quote before /lib: this is that copy, not the plugin's.
own_conf="$ROOT/.claude"/lib/conf.sh
[ ! -f "$own_conf" ] || stale_copy "$own_conf" _conf_parse || ok "this repository's copy of conf.sh reads project.conf as data"
# How the old-copy message reads.
printf 'old\n' > "$S/old-copy"
out=$(stale_copy "$S/old-copy" some-mark)
case $out in *"old copy"*"stridal update"*"/stridal:init"*) ok "an old copy is said to be one, with how to refresh it, on both installs" ;; *) fail "stale_copy said: $out" ;; esac

# No file the model ships gives project.conf to a shell. The tree is the authority, with no pattern for
# HOW a line might read it (through a variable, through eval, through cat): every executable line that
# names the file is counted, by file, against this table, so a new one stops here to be read. Only in
# the framework's own gate: it holds what ships, and a project's own files are the project's.
conf_lines="2 change-approval.sh
1 compound.sh
1 hooks/format.sh
3 hooks/no-background-gate.sh
1 hooks/no-silent-wait.sh
10 hooks/pr-merge-guard.sh
1 lib/change.sh
19 lib/conf.sh
4 lib/health.sh
1 modules/artifacts/guard.d/currency.sh
1 modules/ideas/enable.sh
1 modules/openspec/enable.sh
1 modules/people/people.sh
1 modules/risk-register/enable.sh
1 modules/write-surfaces/guard.d/write-surfaces.sh
1 skills/log-insight/context.sh
3 workflows/build-change.js
1 ci/batch.sh
2 ci/run-local.sh"
# framework_of DIR: the framework's checkout when DIR is it or its template/; nothing for a project.
framework_of() {
  if [ -d "$1/framework/internal/plugin/assets" ]; then printf '%s\n' "$1"
  elif [ -d "$1/../framework/internal/plugin/assets" ]; then (cd "$1/.." && pwd)
  fi
}
# lines_naming_conf FRAMEWORK: "<count> <path under template/>" per file with an executable line naming it.
lines_naming_conf() {
  for d in "$1/template/.claude" "$1/template/scripts/ci" "$1/framework/internal/plugin/assets"; do
    grep -rlE --exclude-dir=worktrees --exclude-dir=checks --exclude-dir=local --exclude-dir=cases --exclude='*.md' \
      --exclude='*.json' --exclude='*.txt' --exclude='*.yaml' --exclude=project.conf --exclude=module.conf 'project[.]conf' "$d"
  done | while IFS= read -r f; do
    n=$(grep -v '^[[:space:]]*#' "$f" | grep -c 'project[.]conf')
    rel=${f#"$1"/}; rel=${rel#template/}; rel=${rel#.claude/}; rel=${rel#scripts/}
    [ "$n" = 0 ] || printf '%s %s\n' "$n" "$rel"
  done
}
fw=$(framework_of "$ROOT")
if [ -n "$fw" ]; then
  seen=$(lines_naming_conf "$fw")
  drift=$(printf '%s\n%s\n' "$conf_lines" "$seen" | sort | uniq -u)
  [ -z "$drift" ] && ok "every executable line naming project.conf in what ships is one this table has read ($(printf '%s\n' "$seen" | wc -l | tr -d ' ') files)" \
    || fail "the lines naming project.conf changed; read each, and only if it gives the file to no shell, update this table: $(printf '%s' "$drift" | tr '\n' ';')"
fi
mkdir -p "$F/.claude/local"; printf 'cat "$ROOT/.claude/project.conf"\n' > "$F/.claude/local/own.sh"
[ -z "$(framework_of "$F")" ] && ok "a project's own file naming project.conf is not this table's to judge" || fail "a project read as the framework"
rm -f "$F/.claude/local/own.sh"

# ── The argv callers: no shell, and a value that needs one fails by name ───────────────────────
# Each has three cases. It runs its program with its arguments; `eval touch …`, which holds no shell
# character and which any shell would run, does not run (only exec, no shell, refuses it); a value with
# shell syntax is refused by name before anything starts.
PAY_FMT=$(jq -cn --arg f "$F/src/a.ts" '{tool_name:"Write",tool_input:{file_path:$f}}')
echo 'x' > "$F/src/a.ts"
printf 'echo "$#:$*" > "%s/fmt-args"\n' "$S" > "$F/fmt.sh"
git -C "$F" update-ref refs/remotes/origin/main HEAD
git -C "$F" remote add origin "$F/no-such-origin.git"
fmt_here() { printf '%s' "$PAY_FMT" | (cd "$F" && CLAUDE_PROJECT_DIR="$F" sh "$F/.claude/hooks/format.sh" 2>/dev/null); }
# fmt: as a merged setting: the hook runs the program origin's main names.
fmt() { conf_on_main "$F"; fmt_here; }
printf 'FORMAT_CMD="sh fmt.sh --flag=x two"\nFORMAT_EXT="ts"\n' > "$C"
out=$(fmt); rc=$?
[ "$rc" = 0 ] && [ "$(cat "$S/fmt-args" 2>/dev/null)" = "3:--flag=x two $F/src/a.ts" ] && [ -z "$out" ] \
  && ok "FORMAT_CMD: its words, and the file last, reach the program; nothing is said" || fail "FORMAT_CMD: exit $rc, args $(cat "$S/fmt-args" 2>/dev/null), said $out"
printf 'FORMAT_CMD="eval touch %s/fmt"\nFORMAT_EXT="ts"\n' "$CAN" > "$C"; clear_can
out=$(fmt); rc=$?
[ "$rc" = 0 ] && empty && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("could not start")' >/dev/null 2>&1 \
  && ok "FORMAT_CMD: no shell runs it, and Claude is told it did not start, without blocking the edit" || fail "FORMAT_CMD no shell: exit $rc, ran $(ls "$CAN" | tr '\n' ' '), said $out"
for v in "touch $CAN/a | touch $CAN/b" "touch $CAN/a; touch $CAN/b" "cd src && touch $CAN/a" "VAR=1 touch $CAN/a" "-c touch" "touch \"$CAN/a\"" "touch $CAN/*"; do
  printf "FORMAT_CMD='%s'\nFORMAT_EXT=\"ts\"\n" "$(printf '%s' "$v" | sed "s/'/'\\\\''/g")" > "$C"; clear_can
  # A value holding a double quote is a shell's to read: a single-quoted conf line keeps it literal.
  out=$(fmt); rc=$?
  [ "$rc" = 0 ] && empty && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("FORMAT_CMD")' >/dev/null 2>&1 \
    && ok "FORMAT_CMD refuses by name: $v" || fail "FORMAT_CMD '$v': exit $rc, ran $(ls "$CAN" | tr '\n' ' '), said $out"
done
printf 'FORMAT_CMD="$(touch %s/a)"\nFORMAT_EXT="ts"\n' "$CAN" > "$C"; clear_can
out=$(fmt)
empty && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("FORMAT_CMD")' >/dev/null 2>&1 \
  && ok "FORMAT_CMD with a substitution says so at each edit of a file it owns, rather than formatting nothing in silence" || fail "FORMAT_CMD substitution: ran $(ls "$CAN" | tr '\n' ' '), said $out"
# The note is about a file the formatter owns, names the key at fault, and a bad FORMAT_EXT gets its own.
echo 'x' > "$F/src/a.md"
PAY_MD=$(jq -cn --arg f "$F/src/a.md" '{tool_name:"Write",tool_input:{file_path:$f}}')
out=$(printf '%s' "$PAY_MD" | (cd "$F" && CLAUDE_PROJECT_DIR="$F" sh "$F/.claude/hooks/format.sh" 2>/dev/null))
[ -z "$out" ] && ok "...and says nothing of a file the formatter does not own" || fail "format.sh noted a file outside FORMAT_EXT: $out"
printf 'OWNER_NAME="$(x)"\nFORMAT_CMD="$(y)"\nFORMAT_EXT="ts"\n' > "$C"
out=$(fmt)
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("FORMAT_CMD") and (test("OWNER_NAME") | not)' >/dev/null 2>&1 \
  && ok "...naming FORMAT_CMD, not the first refused line of the file" || fail "format.sh quoted the wrong line: $out"
printf 'FORMAT_CMD="sh fmt.sh"\nFORMAT_EXT="$(y)"\n' > "$C"; conf_on_main "$F"
out=$(printf '%s' "$PAY_MD" | (cd "$F" && CLAUDE_PROJECT_DIR="$F" sh "$F/.claude/hooks/format.sh" 2>/dev/null))
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("FORMAT_EXT")' >/dev/null 2>&1 \
  && ok "a refused FORMAT_EXT gets a note on any file, as it cannot say whose file this is" || fail "FORMAT_EXT refused in silence: $out"
# The program is main's, not the branch's this hook runs in. A value on the branch alone does not run.
printf 'FORMAT_CMD="sh fmt.sh main-says"\nFORMAT_EXT="ts"\n' > "$C"; conf_on_main "$F"
printf 'FORMAT_CMD="touch %s/branch-says"\nFORMAT_EXT="ts"\n' "$CAN" > "$C"; clear_can; rm -f "$S/fmt-args"
out=$(fmt_here)
empty && grep -q main-says "$S/fmt-args" 2>/dev/null && ok "format.sh runs the program main names, not the one the branch names" || fail "format.sh ran the branch's: ran $(ls "$CAN" | tr '\n' ' '), args $(cat "$S/fmt-args" 2>/dev/null), said $out"
git -C "$F" symbolic-ref --delete refs/remotes/origin/HEAD; clear_can
out=$(fmt_here)
empty && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("set-head")' >/dev/null 2>&1 \
  && ok "origin's main unknown: format.sh runs nothing, and says how to fix that" || fail "format.sh with origin's HEAD unknown: ran $(ls "$CAN" | tr '\n' ' '), said $out"
git -C "$F" update-ref -d refs/remotes/origin/conf-on-main; rm -f "$F/.git/conf-on-main"
git -C "$F" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main; clear_can
out=$(fmt_here)
empty && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("names no FORMAT_CMD")' >/dev/null 2>&1 \
  && ok "main holding no project.conf: format.sh runs nothing, and says why" || fail "format.sh, main with no conf: ran $(ls "$CAN" | tr '\n' ' '), said $out"

rq() { (ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; roadmap_queue "$@"); }
printf 'echo "parsed $*"\n' > "$F/own.sh"
printf 'ROADMAP_PARSER="sh own.sh --extra"\n' > "$C"
out=$(rq --check) && [ "$out" = "parsed --extra --check" ] && ok "ROADMAP_PARSER: its words, then the mode, reach the program" || fail "ROADMAP_PARSER: $out"
printf 'ROADMAP_PARSER="eval touch %s/p"\n' "$CAN" > "$C"; clear_can
rq --check >/dev/null 2>&1 && fail "ROADMAP_PARSER: a parser that cannot start read as a queue" || { empty && ok "ROADMAP_PARSER: no shell runs it, and the queue is UNKNOWN" || fail "ROADMAP_PARSER no shell: ran $(ls "$CAN" | tr '\n' ' ')"; }
for line in "ROADMAP_PARSER='touch $CAN/a | cat'" "ROADMAP_PARSER=\"\$(touch $CAN/a)\"" "ROADMAP_NORMALIZER='cat; touch $CAN/a'" "ROADMAP=\"\$(touch $CAN/a)\""; do
  printf '%s\n' "$line" > "$C"; clear_can
  out=$(rq --check 2>&1); rc=$?
  [ "$rc" != 0 ] && empty && case $out in *UNKNOWN*ROADMAP*) true ;; *) false ;; esac \
    && ok "a queue with $line is UNKNOWN, by name, not the template's parser's reading" || fail "$line: exit $rc, ran $(ls "$CAN" | tr '\n' ' '), said $out"
done
ROW='1	1		1.1	add-a	change	planned		Ana	summary	20	'
printf 'printf "%%s\\n" "%s"\n' "$ROW" > "$F/rows.sh"
printf 'sed "s/planned/queued/"\n' > "$F/norm.sh"
printf 'ROADMAP_PARSER="sh rows.sh"\nROADMAP_NORMALIZER="sh norm.sh"\n' > "$C"
case "$(rq --tsv)" in *"	queued	"*) ok "ROADMAP_NORMALIZER: a filter, run with no shell, on the parser's rows" ;; *) fail "ROADMAP_NORMALIZER: $(rq --tsv 2>&1)" ;; esac
printf 'ROADMAP_PARSER="sh rows.sh"\nROADMAP_NORMALIZER="eval touch %s/n"\n' "$CAN" > "$C"; clear_can
out=$(rq --tsv 2>&1); rc=$?
[ "$rc" != 0 ] && empty && case $out in *ROADMAP_NORMALIZER*UNKNOWN*) true ;; *) false ;; esac \
  && ok "ROADMAP_NORMALIZER: no shell runs it, and the queue is UNKNOWN" || fail "ROADMAP_NORMALIZER no shell: exit $rc, ran $(ls "$CAN" | tr '\n' ' '), said $out"

# What a branch's value must not steer outside the guard: read from main, and strict without it.
# REVIEW_CAPS: this repo's fixture F, with the scripts copied in.
cp "$ROOT/.claude/review-cap.sh" "$ROOT/.claude/quota-gate.sh" "$ROOT/.claude/machine-quiet.sh" "$F/.claude/" 2>/dev/null
keys_here() { (cd "$F" && ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_keys_from_main "$F/.claude/lib/conf.sh" "$@" 2>/dev/null
  for k in "$@"; do eval "printf '%s=%s\n' \"\$k\" \"\${$k-}\""; done; printf 'note=%s\n' "$CONF_MAIN_NOTE"); }
printf 'REVIEW_CAPS="low:9 normal:9 high:9"\nMQ_DOCKER="0"\nMQ_ORPHAN_SHAPES="*main-shape*"\nQUOTA_LANE_STOP_PCT="55"\n' > "$C"; conf_on_main "$F"
printf 'REVIEW_CAPS="low:99 normal:99 high:99"\nMQ_DOCKER="1"\nMQ_ORPHAN_SHAPES="*branch-shape*"\nQUOTA_LANE_STOP_PCT="99"\n' > "$C"
v=$(keys_here REVIEW_CAPS MQ_DOCKER MQ_ORPHAN_SHAPES QUOTA_LANE_STOP_PCT | tr '\n' '|')
[ "$v" = "REVIEW_CAPS=low:9 normal:9 high:9|MQ_DOCKER=0|MQ_ORPHAN_SHAPES=*main-shape*|QUOTA_LANE_STOP_PCT=55|note=|" ] && ok "conf_keys_from_main: main's values, not the branch's" || fail "conf_keys_from_main: $v"
grep -q 'conf_keys_from_main .* MQ_ORPHAN_SHAPES MQ_DOCKER MQ_COLIMA' "$F/.claude/machine-quiet.sh" && grep -q 'conf_keys_from_main .* REVIEW_CAPS REVIEW_AT_CAP' "$F/.claude/review-cap.sh" && grep -q 'conf_keys_from_main .* QUOTA_LANE_STOP_PCT' "$F/.claude/quota-gate.sh" \
  && ok "machine-quiet, review-cap and quota-gate ask for them" || fail "a script no longer asks main for its keys"
# machine-quiet by behaviour: a fake claude, ps and docker first on PATH, so this asks nothing of the
# machine it runs on, and the PIDs ps lists exist nowhere. --dry-run prints what it would stop.
mkdir -p "$S/mq"
printf '#!/bin/sh\necho "[]"\n' > "$S/mq/claude"
printf '#!/bin/sh\ntouch "%s"\n' "$S/docker-ran" > "$S/mq/docker"
printf '#!/bin/sh\nprintf "%%s\\n" "999991 1 /bin/sh /x/main-shape/run" "999992 1 /bin/sh /x/branch-shape/run" "999993 1 /bin/sh %s/.claude/worktrees/lane/.claude/hooks/x.sh"\n' "$(git -C "$F" rev-parse --show-toplevel)" > "$S/mq/ps"
chmod +x "$S/mq/claude" "$S/mq/docker" "$S/mq/ps"
mq_here() { (cd "$F" && HOME="$S/home" PATH="$S/mq:$PATH" sh "$F/.claude/machine-quiet.sh" --dry-run 2>&1); }
out=$(mq_here)
case $out in *"would: kill 999991"*) case $out in *"kill 999992"* | *"kill 999993"*) fail "machine-quiet: more than main's shape: $out" ;; *) ok "machine-quiet: lists main's shape, not the branch's" ;; esac ;; *) fail "machine-quiet did not list main's shape: $out" ;; esac
[ ! -e "$S/docker-ran" ] && ok "machine-quiet: the branch's MQ_DOCKER does nothing" || fail "machine-quiet: the branch's MQ_DOCKER ran docker"
git -C "$F" symbolic-ref --delete refs/remotes/origin/HEAD
v=$(keys_here REVIEW_CAPS MQ_DOCKER MQ_ORPHAN_SHAPES QUOTA_LANE_STOP_PCT | tr '\n' '|')
case $v in "REVIEW_CAPS=low:2 normal:3 high:3|MQ_DOCKER=0|MQ_ORPHAN_SHAPES=*@WT@/*/.claude/hooks/*|QUOTA_LANE_STOP_PCT=90|note=origin's main cannot be read"*) ok "main unreadable: conf.sh's defaults, with a note naming the fix" ;; *) fail "main unreadable: $v" ;; esac
out=$(mq_here); case $out in *"on the defaults"*set-head*"would: kill 999993"*) case $out in *"kill 999991"* | *"kill 999992"*) fail "machine-quiet, main unreadable: not the default shape alone: $out" ;; *) ok "machine-quiet, main unreadable: the default shape, with a note naming the fix" ;; esac ;; *) fail "machine-quiet said: $out" ;; esac
[ ! -e "$S/docker-ran" ] && ok "machine-quiet, main unreadable: docker stays off" || fail "machine-quiet, main unreadable: the branch's MQ_DOCKER ran docker"
out=$(cd "$F" && HOME="$S/home" ROOT="$F" sh "$F/.claude/quota-gate.sh" 2>&1 | head -n 3); case $out in *"on the default threshold"*) ok "quota-gate says so" ;; *) fail "quota-gate said: $out" ;; esac
git -C "$F" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# A read of main takes a repository's module.conf from main too: branch text there is no key of main's.
mkdir -p "$F/.claude/modules/own"
printf 'name="own"\n' > "$F/.claude/modules/own/module.conf"
printf 'MODULES="own"\n' > "$C"; rm -f "$F/.git/conf-on-main"; conf_on_main "$F"
printf 'name="own"\nFORMAT_CMD="touch %s/from-branch-module"\nNOT_A_KEY="x"\n' "$CAN" > "$F/.claude/modules/own/module.conf"
v=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; CONF_MAIN_NOTE=x; conf_keys_from_main "$F/.claude/lib/conf.sh" FORMAT_CMD 2>/dev/null; printf 'cmd=%s|note=%s|bad=%s' "$FORMAT_CMD" "$CONF_MAIN_NOTE" "$CONF_MAIN_BAD_KEYS")
[ "$v" = "cmd=|note=|bad=" ] && ok "a repository's module.conf on a branch gives main's keys nothing, and no error" || fail "the branch's module.conf reached main's keys: $v"
rm -rf "$F/.claude/modules"
printf 'MODULES=""\n' > "$C"; rm -f "$F/.git/conf-on-main"; conf_on_main "$F"
# No remote: the disk is the authority. mktemp failing: the defaults, never the checkout's value.
git -C "$F" remote remove origin
printf 'REVIEW_CAPS="low:7 normal:7 high:7"\n' > "$C"
v=$(keys_here REVIEW_CAPS | tr '\n' '|')
[ "$v" = "REVIEW_CAPS=low:7 normal:7 high:7|note=|" ] && ok "conf_keys_from_main: no remote: the disk's value, with no note" || fail "no remote: $v"
git -C "$F" remote add origin "$F/no-such-origin.git"
git -C "$F" update-ref refs/remotes/origin/main HEAD; git -C "$F" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
v=$( (TMPDIR="$S/no-such-dir"; export TMPDIR; keys_here REVIEW_CAPS) | tr '\n' '|')
case $v in "REVIEW_CAPS=low:2 normal:3 high:3|note=no temp file"*) ok "conf_keys_from_main: no temp file: the defaults, with a note, not this checkout's value" ;; *) fail "no temp file: $v" ;; esac
# A git error reading main is not "main holds none".
real_git=$(command -v git); mkdir -p "$S/bin"
printf '#!/bin/sh\ncase " $* " in *" ls-tree "*) exit 129 ;; esac\nexec "%s" "$@"\n' "$real_git" > "$S/bin/git"; chmod +x "$S/bin/git"
printf 'REVIEW_CAPS="low:7 normal:7 high:7"\n' > "$C"; rm -f "$F/.git/conf-on-main"; conf_on_main "$F"
v=$( (PATH="$S/bin:$PATH"; export PATH; keys_here REVIEW_CAPS) | tr '\n' '|')
case $v in "REVIEW_CAPS=low:2 normal:3 high:3|note=git could not read"*) ok "conf_keys_from_main: a git error is said, not read as main holding no file" ;; *) fail "a git error: $v" ;; esac
rm -f "$S/bin/git"
git -C "$F" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main; rm -f "$F/.git/conf-on-main"

# conf_exec itself: a function or a builtin of the caller's shell is no program, and a caller's IFS or
# an option on the first word changes nothing.
: > "$C"
printf 'touch "%s/dotted"\n' "$CAN" > "$F/dot.sh"
out=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; myfn() { touch "$CAN/fn"; }; conf_exec myfn 2>/dev/null); rc=$?
[ "$rc" = 127 ] && empty && ok "conf_exec: the caller's function is not run" || fail "conf_exec function: exit $rc, ran $(ls "$CAN" | tr '\n' ' ')"
out=$(cd "$F" && ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_exec ". ./dot.sh" 2>/dev/null); rc=$?
case $rc in 126 | 127) empty && ok "conf_exec: the dot builtin is not run" || fail "conf_exec dot: ran $(ls "$CAN" | tr '\n' ' ')" ;; *) fail "conf_exec dot: exit $rc" ;; esac
out=$(cd "$F" && ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; IFS=:; conf_exec "printf %s:%s" "a b" c); rc=$?
[ "$rc" = 0 ] && [ "$out" = "a b:c" ] && ok "conf_exec: splits on blanks whatever the caller's IFS, and its arguments stay whole" || fail "conf_exec split: exit $rc, $out"
out=$(ROOT=$F; . "$F/.claude/lib/conf.sh" 2>/dev/null; conf_exec "-c touch" 2>&1); rc=$?
[ "$rc" = 126 ] && case $out in *"cannot run"*) true ;; *) false ;; esac && ok "conf_exec: a leading option is refused, by name" || fail "conf_exec option: exit $rc, $out"

# ── A malformed line never turns no-background-gate off ───────────────────────────────────────
ng() { printf '%s' "$1" | (cd "$F" && CLAUDE_PROJECT_DIR="$F" sh "$F/.claude/hooks/no-background-gate.sh" >/dev/null 2>"$S/err"); }
bgcmd() { jq -cn --arg c "$1" --arg a "${2:-}" --argjson b "${3:-false}" '{tool_name:"Bash",tool_input:{command:$c,run_in_background:$b}} + (if $a == "" then {} else {agent_id:$a} end)'; }
printf 'GATE="$(tools/where.sh)"\n' > "$C"
ng "$(bgcmd 'tools/own-gate.sh &')"; expect_rc 2 $? "no-background-gate: GATE unreadable: a command the shell backgrounds could be the gate"
grep -q 'GATE' "$S/err" && ok "...and it names the line" || fail "no name in: $(cat "$S/err")"
ng "$(bgcmd 'tools/own-gate.sh' a1 true)"; expect_rc 2 $? "no-background-gate: GATE unreadable: a subagent's run_in_background could be the gate"
ng "$(bgcmd 'git status')"; expect_rc 0 $? "...a foreground command is not stopped by it"
ng "$(bgcmd 'tools/own-gate.sh' '' true)"; expect_rc 0 $? "...nor the main session's run_in_background, which wakes it"
printf 'OWNER_NAME="$(x)"\n' > "$C"
ng "$(bgcmd 'sleep 1 &')"; expect_rc 0 $? "...a bad line for another key leaves the guard reading the gate's own keys"
printf 'touch nothing\n' > "$C"
ng "$(bgcmd 'sleep 1 &')"; expect_rc 2 $? "...a line naming no key could have meant GATE, so it counts"

# A branch cannot rename the gate away, and an unreadable ref blocks nothing.
bgnames() { printf '%s' "$(bgcmd "$1" a1 true)" | (cd "$F" && CLAUDE_PROJECT_DIR="$F" sh "$F/.claude/hooks/no-background-gate.sh" >/dev/null 2>&1); }
printf 'GATE="tools/main-gate.sh"\n' > "$C"; rm -f "$F/.git/conf-on-main"; conf_on_main "$F"
printf 'GATE="tools/branch-gate.sh"\n' > "$C"
bgnames tools/main-gate.sh; expect_rc 2 $? "no-background-gate: main's gate name counts, whatever the branch renamed it"
ng "$(bgcmd 'true && tools/main-gate.sh' a1 false)"; expect_rc 2 $? "...behind an && in a subagent's short-timeout call too"
ng "$(bgcmd 'tools/main-gate.sh &')"; expect_rc 2 $? "...and sent to the shell's background from the main session"
bgnames tools/branch-gate.sh; expect_rc 2 $? "...and the branch's own does too"
bgnames tools/neither.sh; expect_rc 0 $? "...and another script does not"
git -C "$F" symbolic-ref --delete refs/remotes/origin/HEAD
bgnames tools/branch-gate.sh; expect_rc 2 $? "...with main unreadable, the branch's still counts"
bgnames tools/main-gate.sh; expect_rc 0 $? "...and an unreadable ref blocks nothing else"
git -C "$F" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# The hot path: how many reads of main a call pays, counted through a logging git (no clock).
mkdir -p "$S/lg"
printf '#!/bin/sh\necho "$*" >> "%s/lg/log"\nexec "%s" "$@"\n' "$S" "$(command -v git)" > "$S/lg/git"; chmod +x "$S/lg/git"
main_reads() {  # main_reads HOOK PAYLOAD: the hook's reads of a file from a commit
  : > "$S/lg/log"
  printf '%s' "$2" | (cd "$F" && CLAUDE_PROJECT_DIR="$F" PATH="$S/lg:$PATH" sh "$F/.claude/hooks/$1" >/dev/null 2>&1)
  grep -c 'cat-file\|ls-tree' "$S/lg/log"
}
printf 'FORMAT_CMD="true"\nFORMAT_EXT="go"\n' > "$C"; conf_on_main "$F"
echo x > "$F/src/a.go"; echo x > "$F/src/a.md"
hot_path() {  # hot_path WANT LABEL HOOK PAYLOAD
  n=$(main_reads "$3" "$4")
  [ "$n" = "$1" ] && ok "hot path: $2: $n reads of main" || fail "hot path: $2: $n reads of main, want $1: $(cat "$S/lg/log")"
}
hot_path 0 "no-background-gate, a main session's plain call" no-background-gate.sh "$(bgcmd 'git status')"
hot_path 0 "no-background-gate, a main session's && call" no-background-gate.sh "$(bgcmd 'git status && git log')"
hot_path 0 "the merge guard, a plain call" pr-merge-guard.sh "$(bgcmd 'git status')"
hot_path 0 "format.sh, a file no formatter owns" format.sh "$(jq -cn --arg f "$F/src/a.md" '{tool_name:"Write",tool_input:{file_path:$f}}')"
hot_path 2 "format.sh, a file the formatter owns" format.sh "$(jq -cn --arg f "$F/src/a.go" '{tool_name:"Write",tool_input:{file_path:$f}}')"

# ── This project's own project.conf reads clean ───────────────────────────────────────────────
real=$(ROOT=$ROOT; . "$F/.claude/lib/conf.sh" 2>/dev/null; printf '%s' "$CONF_ERRORS")
[ -z "$real" ] && ok "$ROOT/.claude/project.conf reads clean as data" || fail "$ROOT/.claude/project.conf: $real"

finish
