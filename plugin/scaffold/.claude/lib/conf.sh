# conf.sh: sourced (never run) by the operating model's scripts. Sets ROOT and the defaults,
# then reads the project's .claude/project.conf over them, as data (_conf_parse).
#
# ROOT comes from this file's own location when the caller passes it (CONF_FROM), else from
# git: a hook runs from wherever the session happens to be, and a context script may be run
# from a subdirectory. A caller that already knows ROOT sets it first; conf.sh keeps it.
#
# Usage from .claude/<dir>/x.sh:   ROOT=$(cd "$(dirname "$0")/../.." && pwd); . "$ROOT/.claude/lib/conf.sh"

if [ -z "${ROOT:-}" ]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
fi

PROJECT_NAME="Project"
PROJECT_SLUG="project"
STATUS_MARK="◆"
OWNER_ROLE="owner"
OWNER_NAME=""
APPROVAL_DELEGATED="0"
MAIN_BRANCH="main"
BRANCH_CHANGE="change/"
BRANCH_FIX="fix/"
BRANCH_OPS="ops/"
JOURNAL="docs/development-journal.md"
INSIGHTS="docs/insights-log.md"
JOURNAL_FRAGMENTS="docs/journal.d"
ROADMAP="docs/roadmap.md"
ROADMAP_PARSER=""
ROADMAP_NORMALIZER=""
OWNER_QUEUE="docs/owner-queue.md"
ADR_DIR="docs/adr"
PRACTICES_DIR="docs/practices"
ADR_EVIDENCE_FROM=""
ADR_EVIDENCE_SPIKES=""
ADR_EVIDENCE_KNOWN=""
INSIGHT_AREAS=""
INSIGHTS_TABLE_HEADING="## Log"
JOURNAL_HEADING='^## Session [0-9]+(\.[0-9]+)* — [0-9]{4}-[0-9]{2}-[0-9]{2}[^ ]* — [^ ].* — .+'
RECORDS_BASELINE=""
CHANGES_LEGACY=""
COMPOUND_MAX_SESSIONS="3"
REVIEW_CAPS="low:2 normal:3 high:3"
REVIEW_AT_CAP="stop"
TIME_ZONE="America/New_York"
TIME_ZONE_LABEL="ET"
QUOTA_LANE_STOP_PCT="90"
PROPOSALS="markdown"
CHANGES_DIR="changes"
SPECS_DIR="specs"
REVIEW_PAGE="none"
SCENARIO_IDS="required"
TEST_GLOBS="*_test.go *.test.* *.spec.* test_*.py *_test.py tests/ test/ __tests__/ spec/"
GATE_RUN="scripts/ci/run-local.sh"
GATE="scripts/ci/gate.sh"
GATE_STEPS="scripts/ci/steps.sh"
GATE_CLEAN_ROOM="none"
GATE_REMOTE_WORKFLOW=""
GATE_DISPLAY_CONTEXTS=""
GATE_PR_CHECKS=""
GATE_FAIL_PATTERN=""
GATE_TAIL_EXCLUDE=""
GATE_DOCS=""
MQ_ORPHAN_SHAPES="*@WT@/*/.claude/hooks/*"
MQ_DOCKER="0"
MQ_COLIMA="0"
FORMAT_CMD=""
FORMAT_EXT=""
MODULES=""
PLAYBOOK="docs/playbook.md"
AGENTS_MD_MAX_BYTES="16000"
AGENTS_MD_MAX_ROW="320"
MKTEMP_CHECK_PATHS=""
COAUTHOR_HEALTH_SINCE=""
CHANGE_RECORD_EXTRA=""
GATE_QUICK_FLAGS="--quick"
BATCH_REGENERATE=""
# Derived from BRANCH_OPS after project.conf is read, unless the project names its own (or "").
BRANCH_SESSION_CLOSE="@default"

# project.conf IS DATA (OPS-219). A branch can edit it, and every hook loads it, so it is read line by
# line here and never given to a shell: no line of it runs and nothing in it expands.
#
# A CONTROL DOES NOT TAKE ITS DECISIONS FROM THE BRANCH IT JUDGES. The merge guard reads the whole of
# origin/<main>'s copy (GUARD_CONF, exported, so every script it starts does too). format.sh's program
# (FORMAT_CMD, FORMAT_EXT), machine-quiet's MQ_ keys, REVIEW_CAPS, REVIEW_AT_CAP and QUOTA_LANE_STOP_PCT
# come from it (conf_keys_from_main). no-background-gate recognises main's gate names beside the
# branch's. What runs in an agent's own call stays the branch's, as it runs the branch's code by design
# and CI's required check is the control: the gate (GATE, GATE_RUN, GATE_STEPS), batch.sh
# (BATCH_REGENERATE), enable.sh (OPENSPEC_BIN), living.sh (LIVING_SCRIPT_CHECK). The roadmap parser runs
# in the guard's children from main's copy, and on the panel's refresh in the root that panel serves:
# the main checkout as normally run, a lane's if `stridal panel` was started inside that lane. On a copy install this file and the hooks are themselves the branch's own files
# until OPS-145, so all of this holds fully only from the plugin.
#
# What a line may be: blank, a comment, or KEY="value", KEY='value' or KEY=value, with an optional
# blank and `# comment` after it. A value is one line. A double-quoted value holds no $, backtick or
# backslash, since a shell would read those and this does not: single quotes mean the literal text,
# in a shell and here. A bare value holds only letters, digits and _ . / : @ % + , = -. No value starts
# with `-`, which git would read as an option (a `--upload-pack=` is a program), except where a key is
# not an argument: GATE_QUICK_FLAGS, the two patterns, a number, and a project's own PROJECT_ keys.
#
# Anything else is an ERROR, never a silent skip. The key keeps its default, and a default can be a
# guard turned off (an empty GATE_PR_CHECKS requires no check), so the line goes on CONF_ERRORS and
# its key on CONF_BAD_KEYS ("?" when the line names no key it could mean), and is said on stderr. Who
# acts on it: pr-merge-guard blocks every merge of this repo, run-local.sh fails the gate,
# no-background-gate treats any backgrounded command as the gate when GATE or GATE_RUN is the bad key,
# and roadmap_queue, format.sh and batch.sh refuse a bad key of theirs (conf_bad).
#
# THE KEY IS AN ALLOWLIST: a default above or a shipped module's default (_conf_known), or the prefix
# PROJECT_, which is the project's own (no shell, git, gh or jq reads a PROJECT_ name). A list of what
# to refuse could not finish, since a plain assignment to the right name stops a shell's `read`, or
# chooses every program a guard runs. A project's own module takes the prefix too: its module.conf is
# a branch's text, so "declared by a module" would let that text name anything (modules_defaults).
_conf_known="ARTIFACT_PUBLISH ARTIFACT_REGISTRY ARTIFACT_RULE_SECONDS CI_STATUS_LOCAL_CONTEXT CI_STATUS_LOCAL_FAIL \
CI_STATUS_LOCAL_PASS CI_STATUS_REMOTE_CONTEXT CI_STATUS_REMOTE_PASS IDEAS_FILE IDEAS_PAGE LIVING_COMMAND_SECONDS \
LIVING_SCRIPT_CHECK LIVING_TYPED_DURATION OPENSPEC_BIN PEOPLE PEOPLE_OWNERS PREMISE_DOC_DIRS PREMISE_REQUIRED_ON RISK_REGISTER \
WRITE_SURFACE_GLOBS WRITE_SURFACE_MAX \
PROJECT_NAME PROJECT_SLUG STATUS_MARK OWNER_ROLE OWNER_NAME APPROVAL_DELEGATED MAIN_BRANCH \
BRANCH_CHANGE BRANCH_FIX BRANCH_OPS JOURNAL INSIGHTS JOURNAL_FRAGMENTS ROADMAP ROADMAP_PARSER ROADMAP_NORMALIZER \
OWNER_QUEUE ADR_DIR PRACTICES_DIR ADR_EVIDENCE_FROM ADR_EVIDENCE_SPIKES ADR_EVIDENCE_KNOWN INSIGHT_AREAS \
INSIGHTS_TABLE_HEADING JOURNAL_HEADING RECORDS_BASELINE CHANGES_LEGACY COMPOUND_MAX_SESSIONS REVIEW_CAPS \
REVIEW_AT_CAP TIME_ZONE TIME_ZONE_LABEL QUOTA_LANE_STOP_PCT PROPOSALS CHANGES_DIR SPECS_DIR REVIEW_PAGE \
SCENARIO_IDS TEST_GLOBS GATE_RUN GATE GATE_STEPS GATE_CLEAN_ROOM GATE_REMOTE_WORKFLOW GATE_DISPLAY_CONTEXTS \
GATE_PR_CHECKS GATE_FAIL_PATTERN GATE_TAIL_EXCLUDE GATE_DOCS MQ_ORPHAN_SHAPES MQ_DOCKER MQ_COLIMA FORMAT_CMD \
FORMAT_EXT MODULES PLAYBOOK AGENTS_MD_MAX_BYTES AGENTS_MD_MAX_ROW MKTEMP_CHECK_PATHS COAUTHOR_HEALTH_SINCE \
CHANGE_RECORD_EXTRA GATE_QUICK_FLAGS BATCH_REGENERATE BRANCH_SESSION_CLOSE"
CONF_ERRORS=""
CONF_BAD_KEYS=""
_conf_nerr=0

# _conf_key_ok KEY: the allowlist above.
_conf_key_ok() {
  case " $_conf_known " in *" $1 "*) return 0 ;; esac
  case $1 in PROJECT_*) return 0 ;; esac
  return 1
}

# _conf_value_ok KEY VALUE: not a value git would take for an option, unless the key is never an argument.
_conf_value_ok() {
  case $2 in
    -*) case $1 in GATE_QUICK_FLAGS | GATE_FAIL_PATTERN | GATE_TAIL_EXCLUDE | QUOTA_LANE_STOP_PCT | PROJECT_*) ;; *) return 1 ;; esac ;;
  esac
  return 0
}

# _conf_line_bad KEY TEXT: this line (_cf_l, _cf_n) is refused. One ending in a carriage return says
# CRLF, once, for the whole file; it is looked for only here, as a process on every load is not free.
_conf_line_bad() {
  case $_cf_l in
    *"$(printf '\r')")
      _conf_bad '?' ".claude/project.conf line $_cf_n ends in a carriage return (CRLF line endings), so it is refused from there on: save it with LF"
      _cf_stop=1 ;;
    *) _conf_bad "$1" ".claude/project.conf line $_cf_n$2" ;;
  esac
}

# _conf_bad KEY MESSAGE: record one error. KEY is "?" when the line names no key it could mean.
_conf_bad() {
  CONF_BAD_KEYS="$CONF_BAD_KEYS $1"
  CONF_ERRORS="${CONF_ERRORS:+$CONF_ERRORS
}$2"
  _conf_nerr=$((_conf_nerr + 1))
  printf 'conf.sh: %s\n' "$2" >&2
}

# conf_bad KEY: 0 when project.conf did not give KEY's value, so the reader holds a default it was
# not asked for: KEY's own line was refused, or a line was refused that could have meant any key.
conf_bad() {
  case " $CONF_BAD_KEYS " in *" $1 "* | *" ? "*) return 0 ;; esac
  return 1
}

# conf_why KEY: the error that made conf_bad KEY true, for a reader's message.
conf_why() {
  _cw=$(printf '%s\n' "$CONF_ERRORS" | grep -F "($1)" | head -n 1)
  [ -n "$_cw" ] || _cw=$(printf '%s\n' "$CONF_ERRORS" | head -n 1)
  printf '%s\n' "$_cw"
}

# conf_nul_check [FILE]: a NUL byte reads differently in each shell (dash drops it; bash cuts the line
# there), and nothing inside a shell can see it, so this takes two processes. Run by what decides on
# the file (a read of main's copy, run-local.sh, the check), not on every load, which every hook pays for.
conf_nul_check() {
  set -- "${1:-$ROOT/.claude/project.conf}"
  [ -f "$1" ] || return 0
  if ! LC_ALL=C tr -d '\000' < "$1" | cmp -s - "$1"; then
    _conf_bad '?' ".claude/project.conf holds a NUL byte, which each shell reads differently: remove it"
  fi
}

# _conf_shellish TEXT: 0 when TEXT holds a character only a shell would read.
_conf_shellish() {
  case $1 in
    *\$* | *\`* | *\\* | *\"* | *\'* | *\;* | *\&* | *\|* | *\<* | *\>* | *\(* | *\)* | *\{* | *\}* | *\[* | *\]* \
      | *\** | *\?* | *\~* | *\!* | *\#*) return 0 ;;
  esac
  return 1
}

# _conf_parse FILE: no fork per line or per key (every hook pays for this); `eval` only ever assigns,
# to a key on the allowlist, and the value stays in a variable it names, unexpanded.
#
# The limits keep a hook from hanging on a small committed file: a shell's pattern operators and its
# appends to the error list grow with the square of their input. Past one, the file is refused with
# one error, and what comes after it stays a default. A line past the limit is read to its end once.
_conf_parse() {
  _cf_n=0
  _cf_stop=''
  while IFS= read -r _cf_l || [ -n "$_cf_l" ]; do
    [ -z "$_cf_stop" ] || return 0
    _cf_n=$((_cf_n + 1))
    if [ "$_cf_n" -gt 1000 ]; then
      _conf_bad '?' ".claude/project.conf has more than 1000 lines, so it is refused from there on"
      return 0
    fi
    if [ "${#_cf_l}" -gt 512 ]; then
      _conf_bad '?' ".claude/project.conf line $_cf_n is over 512 characters, so it is refused from there on"
      return 0
    fi
    if [ "$_conf_nerr" -ge 20 ]; then
      _conf_bad '?' ".claude/project.conf has 20 lines it cannot read, so it is refused from there on"
      return 0
    fi
    case $_cf_l in
      '' | \#*) continue ;;
      [\ \	]*)
        _cf_l=${_cf_l#"${_cf_l%%[! 	]*}"}
        case $_cf_l in '' | \#*) continue ;; esac ;;
    esac
    _cf_k=${_cf_l%%=*}
    # Spelt out, not [A-Z]: in a shell honouring a locale's collation, that range holds lower case.
    case $_cf_l in *=*) ;; *) _cf_k='' ;; esac
    case $_cf_k in
      [!ABCDEFGHIJKLMNOPQRSTUVWXYZ]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) _cf_k='' ;;
    esac
    if [ -z "$_cf_k" ]; then
      _conf_line_bad '?' " is not KEY=\"value\" or a comment; no line of project.conf runs, so it does nothing"
      continue
    fi
    if ! _conf_key_ok "$_cf_k"; then
      _conf_line_bad "$_cf_k" " ($_cf_k) sets a key the model does not know, which could be one a shell or a tool reads: a key of the project's own takes the prefix PROJECT_ (a variable the scripts read by its exact name, GATE_TAIL_LINES say, is set in the environment)"
      continue
    fi
    _cf_r=${_cf_l#*=}
    case $_cf_r in
      \"*) _cf_q=\" ;;
      \'*) _cf_q=\' ;;
      *) _cf_q='' ;;
    esac
    if [ -n "$_cf_q" ]; then
      _cf_b=${_cf_r#?}
      case $_cf_b in
        *"$_cf_q"*) ;;
        *) _conf_line_bad "$_cf_k" " ($_cf_k) opens a quote it does not close; a value is one line"; continue ;;
      esac
      _cf_v=${_cf_b%%"$_cf_q"*}
      _cf_t=${_cf_b#*"$_cf_q"}
      if [ "$_cf_q" = \" ]; then
        case $_cf_v in
          *\$* | *\`* | *\\*)
            _conf_line_bad "$_cf_k" " ($_cf_k) holds a \$, backtick or backslash in double quotes, which only a shell reads; nothing here expands, so write the value itself, in single quotes if it is literal"
            continue ;;
        esac
      fi
    else
      _cf_v=${_cf_r%%[ 	]*}
      _cf_t=${_cf_r#"$_cf_v"}
      case $_cf_v in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:@%+,=-]*)
          _conf_line_bad "$_cf_k" " ($_cf_k) has a bare value holding a character only a quoted one may; nothing here expands, so quote the literal value"
          continue ;;
      esac
    fi
    # After the value: nothing, or a blank and a comment. Another word would have run as a command.
    case $_cf_t in
      '') ;;
      [\ \	]*)
        _cf_t=${_cf_t#"${_cf_t%%[! 	]*}"}
        case $_cf_t in
          '' | \#*) ;;
          *) _conf_line_bad "$_cf_k" " ($_cf_k) has more after its value; no line of project.conf runs"; continue ;;
        esac ;;
      *) _conf_line_bad "$_cf_k" " ($_cf_k) has more after its value; no line of project.conf runs"; continue ;;
    esac
    if ! _conf_value_ok "$_cf_k" "$_cf_v"; then
      _conf_line_bad "$_cf_k" " ($_cf_k) starts with -, which git would read as an option"
      continue
    fi
    eval "$_cf_k=\$_cf_v"
    [ "$_cf_k" != MAIN_BRANCH ] || _conf_main_named=1
  done < "$1"
  return 0
}

# conf_main_ref: the full ref of this repository's main, by git's own record: origin's HEAD, never a
# key a branch can edit. Fails when that is unset or names a branch this clone does not have.
conf_main_ref() {
  _cm_r=$(git -C "$ROOT" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || return 1
  git -C "$ROOT" rev-parse -q --verify "$_cm_r^{commit}" >/dev/null 2>&1 || return 1
  printf '%s\n' "$_cm_r"
}
# The fix for conf_main_ref failing, for any reader's message.
conf_main_fix() {
  printf '%s' "origin's main cannot be read here, as git does not know which branch of origin is main. Run: git -C \"$ROOT\" fetch origin && git -C \"$ROOT\" remote set-head origin <this project's main branch>. A first push does not set it, so run that after one too; an origin with no main yet first needs: git -C \"$ROOT\" push origin <this project's main branch>. A single-branch or shallow clone also needs, before the fetch: git -C \"$ROOT\" remote set-branches --add origin <this project's main branch>."
}

# conf_main_blob REF PATH OUT: PATH as REF has it, into OUT. 0 written; 2 REF truly holds no PATH; 1
# git could not say, which is never read as "absent": that would run a control on defaults in silence.
conf_main_blob() {
  _cb=$(git -C "$ROOT" ls-tree "$1" -- "$2" 2>/dev/null) || return 1
  [ -n "$_cb" ] || return 2
  git -C "$ROOT" cat-file blob "$1:$2" > "$3" 2>/dev/null || return 1
}

# conf_keys_from_main LIB KEY...: these keys as origin/<main>'s copy has them, for a hook or a script
# that a branch's value must not steer (LIB is this file). A repository with no remote has no main but
# the disk: the keys stay as they are. Main holding no project.conf is the defaults, with no complaint.
# Main unreadable is the defaults too, with why in CONF_MAIN_NOTE. A line main's copy refuses keeps its
# default: CONF_MAIN_NOTE says so, and CONF_MAIN_BAD_KEYS and CONF_MAIN_ERRORS hold the requested keys
# it touches, apart from this checkout's CONF_BAD_KEYS and CONF_ERRORS, which keep judging the rest.
# The merge guard takes the whole file instead (GUARD_CONF).
conf_keys_from_main() {
  _ck_lib=$1; shift
  CONF_MAIN_NOTE="" CONF_MAIN_BAD_KEYS="" CONF_MAIN_ERRORS="" CONF_MAIN_READ=""
  # Any remote means a main is expected here. worktree-hook-drift.sh exempts all but one called
  # origin: on a repository whose only remote has another name, this notes it cannot read main.
  [ -n "$(git -C "$ROOT" remote 2>/dev/null)" ] || return 0
  CONF_MAIN_READ=1
  _ck_f=$(mktemp "${TMPDIR:-/tmp}/conf-main.XXXXXX") || { CONF_MAIN_NOTE="no temp file to read origin's main into"; _ck_f=/dev/null; }
  if ! _ck_ref=$(conf_main_ref); then
    CONF_MAIN_NOTE=$(conf_main_fix); [ "$_ck_f" = /dev/null ] || : > "$_ck_f"
  elif [ "$_ck_f" != /dev/null ]; then
    conf_main_blob "$_ck_ref" .claude/project.conf "$_ck_f"
    case $? in
      0) ;;
      2) : > "$_ck_f" ;;
      *) : > "$_ck_f"; CONF_MAIN_NOTE="git could not read .claude/project.conf from ${_ck_ref#refs/remotes/}" ;;
    esac
  fi
  _ck_out=$(
    GUARD_CONF=$_ck_f
    . "$_ck_lib" 2>/dev/null
    for _ck_k in "$@"; do
      eval "printf '%s=%s\n' \"\$_ck_k\" \"\${$_ck_k-}\""
      if conf_bad "$_ck_k"; then
        printf '_ck_bad=%s\n' "$_ck_k"
        printf '_ck_err=%s\n' "$(conf_why "$_ck_k")"
      fi
    done
  )
  [ "$_ck_f" = /dev/null ] || rm -f "$_ck_f"
  while IFS= read -r _ck_l; do
    _ck_k=${_ck_l%%=*}
    case $_ck_k in
      _ck_bad) CONF_MAIN_BAD_KEYS="$CONF_MAIN_BAD_KEYS ${_ck_l#*=}" ;;
      _ck_err)
        [ -n "$CONF_MAIN_NOTE" ] || CONF_MAIN_NOTE="origin's main's project.conf holds a line that is not data, so a key read here may be a default: ${_ck_l#*=}"
        CONF_MAIN_ERRORS="${CONF_MAIN_ERRORS:+$CONF_MAIN_ERRORS
}${_ck_l#*=}" ;;
      *) eval "$_ck_k=\${_ck_l#*=}" ;;
    esac
  done <<CONF_MAIN_KEYS
$_ck_out
CONF_MAIN_KEYS
}

# Truly absent is no conf: the defaults. Anything else that cannot be read as a file (a directory, a
# dangling link, a pipe) is an error: the project has said something, and it cannot be heard.
# GUARD_CONF names another copy to read, as main's in the merge guard (off the allowlist, so a conf
# cannot set it); /dev/null is that copy when none could be made, the defaults and nothing else.
_conf_main_named=""
if [ "${GUARD_CONF:-}" = /dev/null ]; then
  :
elif [ -f "${GUARD_CONF:-$ROOT/.claude/project.conf}" ] && [ -r "${GUARD_CONF:-$ROOT/.claude/project.conf}" ]; then
  _conf_parse "${GUARD_CONF:-$ROOT/.claude/project.conf}"
elif [ -e "${GUARD_CONF:-$ROOT/.claude/project.conf}" ] || [ -L "${GUARD_CONF:-$ROOT/.claude/project.conf}" ]; then
  _conf_bad '?' ".claude/project.conf is there but is not a readable file"
fi
# Reading main's copy, a MAIN_BRANCH it does not name is the branch git knows as main, not the default.
if [ -n "${GUARD_CONF:-}" ] && [ -z "$_conf_main_named" ] && _cm_named=$(conf_main_ref); then
  MAIN_BRANCH=${_cm_named#refs/remotes/origin/}
fi

# _conf_argv_bad VALUE: 0 when VALUE cannot run as an argv: it holds shell syntax, has no command, or
# its first word is an option or an assignment, which are a shell's or exec's to read, not a program.
_conf_argv_bad() {
  _conf_shellish "$1" && return 0
  _ca=${1#"${1%%[! 	]*}"}
  _ca=${_ca%%[ 	]*}
  case $_ca in '' | -* | *=*) return 0 ;; esac
  return 1
}

# The keys that name a program run as an argv with no shell (conf_exec). An existing value that needs
# a shell (a pipe, a quote, a `cd x &&`) fails here, by name, rather than doing nothing: put it in a
# script and name the script. The key is then empty, so nothing can run the refused text.
for _cf_k in FORMAT_CMD ROADMAP_PARSER ROADMAP_NORMALIZER BATCH_REGENERATE; do
  eval "_cf_v=\$$_cf_k"
  if [ -n "$_cf_v" ] && _conf_argv_bad "$_cf_v"; then
    _conf_bad "$_cf_k" ".claude/project.conf ($_cf_k) cannot run: it runs as one command and its arguments, with no shell, so shell syntax, a leading option or a leading VAR= is refused; put it in a script and name the script"
    eval "$_cf_k="
  fi
done

# conf_exec VALUE [ARGS]: replace this shell with the program VALUE names, VALUE split on blanks, ARGS
# after it, and no shell in between: no expansion, no glob, and exec (not "$@" alone, which a shell
# would look up as a builtin or a function first). Call it ONLY in a subshell. Exit 126 or 127 when
# the program cannot start, as exec itself gives; 126, naming VALUE, when it cannot run as an argv.
conf_exec() {
  if _conf_argv_bad "$1"; then
    printf 'conf.sh: "%s" cannot run: one command and its arguments, with no shell\n' "$1" >&2
    exit 126
  fi
  _cx=$1; shift
  set -f
  unset IFS   # the default: blanks and newlines, whatever the caller set
  # shellcheck disable=SC2086
  set -- $_cx "$@"
  exec "$@"
}

[ "$BRANCH_SESSION_CLOSE" = "@default" ] && BRANCH_SESSION_CLOSE="${BRANCH_OPS}session-[0-9]*-close*"

# roadmap_queue MODE [ARGS] [FILE]: THE way a script reads the change queue. Every consumer calls
# this, never a parser by path (checks/roadmap.sh fails one that does), so a project that keeps its
# own parser sets ROADMAP_PARSER once and every reader follows (docs/roadmap.md, *Plugging in your
# own parser*, states the contract). Modes: --text, --check, --tsv, --queued [kind]; an explicit
# roadmap path may follow. Exit 0 = read; anything else = the queue is UNKNOWN (not empty).
#
# --queued is derived here from --tsv, so a plugged parser need not implement it. --tsv goes through
# ROADMAP_NORMALIZER when one is set (a filter from the parser's columns to the contract's), then is
# held to the contract: a row the consumers would misread is an error, never a silently wrong queue.
roadmap_queue() {
  # A roadmap rule reads its rows on stdin. One that reads the queue itself would run every rule
  # again, itself included, without end (hundreds of levels deep before process creation fails).
  if [ -n "${ROADMAP_IN_RULE:-}" ]; then
    echo "ERROR: a roadmap rule (roadmap.d) read the change queue; a rule reads its rows on stdin, never the queue, so the queue is UNKNOWN"
    return 1
  fi
  case "${1:-}" in
    --queued)
      shift; _rq_k=""
      case "${1:-}" in change|fix|ops) _rq_k=$1; shift ;; esac
      _rq_t=$(roadmap_queue --tsv "$@") || { printf '%s\n' "$_rq_t"; return 1; }
      [ -z "$_rq_t" ] || printf '%s\n' "$_rq_t" | awk -F'\t' -v k="$_rq_k" '$7 == "queued" && (k == "" || $6 == k) { print $5 }'
      return 0 ;;
  esac
  # A parser project.conf did not give leaves the template's in its place: a confident reading of a
  # roadmap it may not be the parser for. The queue is UNKNOWN instead.
  if conf_bad ROADMAP_PARSER || conf_bad ROADMAP_NORMALIZER || conf_bad ROADMAP; then
    printf 'ERROR: .claude/project.conf cannot say how to read the roadmap, so the change queue is UNKNOWN:\n%s\n' "$CONF_ERRORS"
    return 1
  fi
  # ROADMAP_BUILTIN=1 tells the template's parser it was called by this helper, not as the front
  # door, so a ROADMAP_PARSER naming it (or a wrapper around it) cannot loop back here.
  if [ -z "$ROADMAP_PARSER" ]; then
    _rq_o=$(ROADMAP_BUILTIN=1 sh "$ROOT/.claude/roadmap-queue.sh" "$@"); _rq_rc=$?
  else
    _rq_o=$(cd "$ROOT" && ROADMAP_BUILTIN=1 && export ROOT ROADMAP ROADMAP_BUILTIN && conf_exec "$ROADMAP_PARSER" "$@"); _rq_rc=$?
  fi
  if [ "$_rq_rc" -eq 0 ] && [ "${1:-}" = --tsv ]; then
    if [ -n "$ROADMAP_NORMALIZER" ] && [ -n "$_rq_o" ]; then
      _rq_o=$(printf '%s\n' "$_rq_o" | (cd "$ROOT" && export ROOT ROADMAP && conf_exec "$ROADMAP_NORMALIZER")) \
        || { echo "ERROR: ROADMAP_NORMALIZER ($ROADMAP_NORMALIZER) failed, so the change queue is UNKNOWN"; return 1; }
    fi
    if ! _rq_e=$(printf '%s\n' "$_rq_o" | roadmap_tsv_errors); then
      printf 'ERROR: the roadmap parser (%s) broke the --tsv contract, so the change queue is UNKNOWN:\n%s\n' "${ROADMAP_PARSER:-.claude/roadmap-queue.sh}" "$_rq_e"
      return 1
    fi
  fi
  # The roadmap rules of the enabled modules and the local layer (roadmap.d/*.sh) hold every read,
  # whatever the mode: a queue a rule refuses is UNKNOWN to every reader, as a parse error is. A
  # mode other than --tsv is checked through a --tsv read of the same file (a subshell, so this
  # call's own variables survive it).
  # The list is read with its exit status: a listing that FAILED is not "no rules".
  if [ "$_rq_rc" -eq 0 ] && ! _rq_rl=$(roadmap_rules); then
    echo "ERROR: the roadmap rules (roadmap.d) could not be listed, so the change queue is UNKNOWN"
    return 1
  fi
  if [ "$_rq_rc" -eq 0 ] && [ -n "$_rq_rl" ]; then
    if [ "${1:-}" = --tsv ]; then
      if ! _rq_e=$(printf '%s\n' "$_rq_o" | roadmap_rules_errors); then
        printf 'ERROR: the change queue is UNKNOWN; a roadmap rule refused it:\n%s\n' "$_rq_e"
        return 1
      fi
    else
      case "${1:-}" in --text|--check) shift ;; esac
      _rq_e=$(roadmap_queue --tsv "$@") || { printf '%s\n' "$_rq_e"; return 1; }
    fi
  fi
  [ -z "$_rq_o" ] || printf '%s\n' "$_rq_o"
  return "$_rq_rc"
}

# roadmap_rules: "<layer>\t<file>" per roadmap.d/*.sh rule of the enabled modules and the local
# layer (lib/modules.sh), loaded here when no module was on to load it. Empty when there is none;
# exit 1 when there could be some (a module on, or a local roadmap.d/) but the loader cannot load.
roadmap_rules() {
  if ! roadmap_rules_load; then
    [ -z "${MODULES:-}" ] && [ ! -d "$ROOT/.claude/local/roadmap.d" ] && return 0
    return 1
  fi
  ext_files roadmap.d .sh
}
roadmap_rules_load() {
  command -v ext_files >/dev/null 2>&1 && return 0
  [ -f "$ROOT/.claude/lib/modules.sh" ] && . "$ROOT/.claude/lib/modules.sh"
}

# roadmap_rules_errors: stdin = the --tsv rows. Runs each rule per its own #! line on them, in the
# project root; prints each refusal, indented and naming its rule, and exits 1 if any rule refused.
roadmap_rules_errors() {
  _rr_in=$(cat)
  _rr_list=$(roadmap_rules) || { echo "  the roadmap rules (roadmap.d) could not be listed"; return 1; }
  [ -n "$_rr_list" ] || return 0
  roadmap_rules_load || { echo "  lib/modules.sh could not be loaded to run the roadmap rules"; return 1; }
  _rr_bad=0
  _rr_tab=$(printf '\t')
  while IFS="$_rr_tab" read -r _rr_l _rr_f; do
    # ROADMAP_IN_RULE: a rule that reads the queue is refused (roadmap_queue), not recursed into.
    _rr_out=$(printf '%s\n' "$_rr_in" | (cd "$ROOT" && ROADMAP_IN_RULE=1 && export ROOT ROADMAP ROADMAP_IN_RULE && run_shebang "$_rr_f") 2>&1); _rr_rc=$?
    [ "$_rr_rc" -eq 0 ] && continue
    _rr_bad=1
    [ -n "$_rr_out" ] || _rr_out="exited $_rr_rc and said nothing"
    printf '%s\n' "$_rr_out" | sed "s|^|  ${_rr_l} roadmap.d/$(basename "$_rr_f"): |"
  done <<EOF
$_rr_list
EOF
  return "$_rr_bad"
}

# roadmap_tsv_errors: stdin is --tsv output; prints one line per row that breaks the contract and
# exits 1 if any did. 12 tab-separated columns: line phase section id change kind state pr owner
# summary budget due; an optional 13th, started (the row's section's start date); an optional 14th,
# the row's raw status, read by the people module; an optional 15th, deps (roadmap_deps_errors);
# an optional 16th, the budget's kind (soft or hard; none, or empty, reads as hard: OPS-91)
# (docs/roadmap.md); more are ignored. Blank input is an empty queue, not an error.
roadmap_tsv_errors() {
  _rt_in=$(cat)
  _rt_e=$(printf '%s\n' "$_rt_in" | roadmap_tsv_shape_errors); _rt_rc=$?
  _rt_d=$(printf '%s\n' "$_rt_in" | roadmap_deps_errors) || _rt_rc=1
  # Printed as is, never through sed: a row cut at 60 bytes may end mid-character.
  [ -z "$_rt_e" ] || printf '%s\n' "$_rt_e"
  [ -z "$_rt_d" ] || printf '%s\n' "$_rt_d"
  return "$_rt_rc"
}

# roadmap_deps_errors: stdin is --tsv output; prints one line per Deps (column 15) the queue cannot
# follow and exits 1 if any. Column 15 is empty or comma-separated tokens, no spaces: a row id of
# the roadmap, or #N (an issue or PR outside it, never looked up: a parser touches no network). An
# id that names no row, a cycle, or an open row (queued, in flight, open) waiting on a cancelled one
# is an error: each would leave a row waiting on something that never comes, silently.
roadmap_deps_errors() {
  awk -F'\t' '
    function bad(r, m) { printf "  line %s (%s): %s\n", L[r], I[r], m; nb++ }
    # dfs: colour 1 while on the path, 2 when done; a dependency met on the path closes a cycle.
    function dfs(u,   k, v, p, j) {
      col[u] = 1; path[++depth] = u
      for (k = 1; k <= nd[u]; k++) {
        v = D[u, k]
        if (!(v in row)) continue
        if (col[v] == 1) {
          p = ""; for (j = depth; j >= 1; j--) if (path[j] == v) break
          for (; j <= depth; j++) p = p path[j] " → "
          bad(row[v], "Deps cycle: " p v)
        } else if (col[v] == 0) dfs(v)
      }
      depth--; col[u] = 2
    }
    $0 == "" || NF < 4 { next }
    { n++; L[n] = $1; I[n] = $4; S[n] = $7; row[$4] = n; col[$4] = 0
      if (NF < 15 || $15 == "") next
      m = split($15, t, ",")
      for (k = 1; k <= m; k++) {
        if (t[k] ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) D[$4, ++nd[$4]] = t[k]
        else if (t[k] !~ /^#[0-9]+$/) { bad(n, "Deps \"" $15 "\" is not a row id or #N, comma-separated (a note goes in the Change cell)"); break }
      }
    }
    END {
      for (r = 1; r <= n; r++) for (k = 1; k <= nd[I[r]]; k++) {
        v = D[I[r], k]
        if (!(v in row)) bad(r, "Deps name " v ", which is no row in the roadmap")
        else if (S[row[v]] == "cancelled" && (S[r] == "queued" || S[r] == "inflight" || S[r] == "open")) bad(r, "Deps name " v ", which is cancelled, so the row would wait forever")
      }
      for (r = 1; r <= n; r++) if (col[I[r]] == 0) dfs(I[r])
      exit nb > 0
    }'
}

roadmap_tsv_shape_errors() {
  awk -F'\t' '
    function bad(m) { printf "  tsv row %d (%s): %s\n", NR, substr($0, 1, 60), m; nb++ }
    $0 == "" { next }
    NF < 12 { bad("has " NF " column(s), the contract needs 12"); next }
    $1 !~ /^[0-9]+$/ { bad("column 1 (line) is not a line number") }
    $2 == "" { bad("column 2 (phase) is empty; a row outside every phase has \"-\"") }
    $4 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { bad("column 4 (row id) \"" $4 "\" is empty or not [A-Za-z0-9._-]") }
    $5 == "" { bad("column 5 (change id) is empty") }
    $6 != "change" && $6 != "fix" && $6 != "ops" { bad("column 6 (kind) \"" $6 "\" is not change, fix or ops") }
    $7 != "queued" && $7 != "inflight" && $7 != "open" && $7 != "merged" && $7 != "cancelled" { bad("column 7 (state) \"" $7 "\" is not queued, inflight, open, merged or cancelled (a ROADMAP_NORMALIZER maps a parser'"'"'s own words)") }
    $8 != "" && $8 !~ /^[0-9]+$/ { bad("column 8 (PR) \"" $8 "\" is not a number") }
    $11 != "" && $11 !~ /^[0-9]+(\.[0-9][0-9]?)?$/ { bad("column 11 (budget) \"" $11 "\" is not dollars") }
    $12 != "" && $12 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { bad("column 12 (due) \"" $12 "\" is not YYYY-MM-DD") }
    NF >= 13 && $13 != "" && $13 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { bad("column 13 (started) \"" $13 "\" is not YYYY-MM-DD") }
    NF >= 16 && $16 != "" && $16 != "soft" && $16 != "hard" { bad("column 16 (budget kind) \"" $16 "\" is not soft, hard or empty") }
    NF >= 16 && $16 != "" && $11 == "" { bad("column 16 (budget kind) is \"" $16 "\" for a row with no budget (column 11)") }
    END { exit nb > 0 }'
}

# The enabled modules (MODULES) may carry default keys of their own (module.conf), applied only
# where project.conf set nothing. Only when a module is on, or a legacy switch names one: every
# hook sources this file, and most projects enable none.
if [ -n "$MODULES" ] || [ "$PROPOSALS" = openspec ] || [ "$REVIEW_PAGE" = artifact ]; then
  # shellcheck disable=SC1091
  [ -f "$ROOT/.claude/lib/modules.sh" ] && . "$ROOT/.claude/lib/modules.sh" && modules_defaults
fi

# _brand_env: the product's name for the shell, as framework/internal/brand holds it for Go
# (OPS-101; TestShellBrandMatches holds the two to the same value).
_brand_env() {
  BRAND_NAME="stridal"
}
_brand_env

# focus_file BRANCH [DIR]: the per-branch focus file the status line reads and status-write.sh
# writes, in the git directory of DIR's repository (default: the current one). Every worktree of a
# repository shares it, and it is keyed by branch, so two repos, or two lanes of one, never show
# each other's focus. Not under $HOME: the sandbox lets a command write the repository but not
# ~/.claude (OPS-75). It is under BRAND_NAME's folder. Fails outside a git repository.
focus_file() {
  _ff=$(git -C "${2:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  _ff_key=$(printf '%s' "$1" | tr '/' '-')
  printf '%s' "$_ff/$BRAND_NAME/focus-$_ff_key.txt"
}

# clean_rel PATH: PATH cleaned as Go's path.Clean cleans it, the form install (cleanRel,
# framework/internal/template/conf.go) places files at and writes into settings.json for GATE and
# GATE_RUN: no empty or "." element, "x/.." resolved, no trailing "/", "." when nothing is left.
# An empty PATH stays empty: an unset key, so the caller's default applies, never ".".
# Compare a project.conf path with what install wrote only through this (OPS-72).
clean_rel() {
  [ -n "$1" ] || { printf '\n'; return; }
  _cr_out=; _cr_root=; _cr_ifs=$IFS
  case "$1" in /*) _cr_root=/ ;; esac
  case $- in *f*) _cr_f=1 ;; *) _cr_f= ;; esac
  set -f; IFS=/
  for _cr_e in $1; do
    case "$_cr_e" in
      '' | .) ;;
      ..) case "$_cr_out" in
            '' | .. | */..) [ -n "$_cr_root" ] || _cr_out=${_cr_out:+$_cr_out/}.. ;;
            */*) _cr_out=${_cr_out%/*} ;;
            *) _cr_out= ;;
          esac ;;
      *) _cr_out=${_cr_out:+$_cr_out/}$_cr_e ;;
    esac
  done
  IFS=$_cr_ifs; [ -n "$_cr_f" ] || set +f
  if [ -n "$_cr_root" ]; then printf '/%s\n' "$_cr_out"; else printf '%s\n' "${_cr_out:-.}"; fi
}

# gate_cmd PATH: the gate as a command, as install writes it into the sandbox exclusion and the
# allow list (RenderSettings): cleaned (clean_rel), with ./ before a gate at the repository root,
# which a bare name would look up on PATH. Empty stays empty.
gate_cmd() {
  _gc=$(clean_rel "$1")
  case "$_gc" in
    '' | */*) printf '%s\n' "$_gc" ;;
    *) printf './%s\n' "$_gc" ;;
  esac
}

# gate_wait_path: where install puts gate-wait.sh, by the rule Mapping applies
# (framework/internal/template/conf.go): beside GATE_RUN while the runner keeps the template's
# name, run-local.sh; a project's own runner (any other name) leaves it at scripts/ci/ (OPS-72).
# A runner at the repository root puts it at ./gate-wait.sh, as Go's path.Dir (".") does: a bare
# gate-wait.sh would not match the settings install wrote, nor run off PATH.
gate_wait_path() { gate_file_path gate-wait.sh; }
# gate_file_path NAME: the same rule for any template file that moves with the runner (batch.sh).
gate_file_path() {
  _gr=$(clean_rel "$GATE_RUN")
  case "$_gr" in
    run-local.sh) printf './%s\n' "$1" ;;
    */run-local.sh) printf '%s\n' "${_gr%/run-local.sh}/$1" ;;
    *) printf 'scripts/ci/%s\n' "$1" ;;
  esac
}

# fetch_main: bring origin/<main> up to date for a context script; 0 when origin/<main> is then
# readable. With CONTEXT_OFFLINE=1 (the checks set it) it fetches nothing and reports only
# whether a ref is already there, so a check never touches the network or the remote refs.
fetch_main() {
  [ "${CONTEXT_OFFLINE:-}" = 1 ] || git fetch -q origin "$MAIN_BRANCH" 2>/dev/null || return 1
  git rev-parse -q --verify "origin/$MAIN_BRANCH" >/dev/null 2>&1
}

# close_session_number: the session Up next offers the daily close as (`panel-suggest.sh close`,
# the one place it is computed: `session-4-5-close` is 4.5). fold.sh's N and the entry dev-journal
# writes, so the close writes the Session the suggestion waits for, even with no fragment to fold
# (OPS-129). Empty when no close is offered (or the project has no panel-suggest.sh); a suggestion
# that fails prints `CANNOT CHECK — <its first line>` and returns 1, never an empty answer.
close_session_number() {
  [ -f "$ROOT/.claude/panel-suggest.sh" ] || return 0
  _cs_o=$(sh "$ROOT/.claude/panel-suggest.sh" close 2>&1) \
    || { echo "CANNOT CHECK — panel-suggest.sh close failed: $(printf '%s\n' "$_cs_o" | head -1)"; return 1; }
  printf '%s\n' "$_cs_o" | sed -n 's/.*"name":"session-\([0-9][0-9-]*\)-close".*/\1/p' | head -1 | tr - .
}

# count_rows ERE FILE: how many lines match, or CANNOT CHECK when the file is missing. (`grep -c`
# prints 0 AND exits 1 on no match, so `$(grep -c … || echo 0)` prints "0" twice.)
count_rows() {
  if [ -f "$2" ]; then grep -cE "$1" "$2"; else echo "CANNOT CHECK ($2 is missing)"; fi
}

# hook_note EVENT TEXT: allow, and tell Claude. On exit 0 a hook's plain stdout and stderr
# reach only the debug log; `hookSpecificOutput.additionalContext` is the channel that reaches
# the model. One line, JSON-escaped. The same text goes to stderr for the debug log.
hook_note() {
  echo "$2" >&2
  _esc=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\t' '  ')
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$_esc"
}
