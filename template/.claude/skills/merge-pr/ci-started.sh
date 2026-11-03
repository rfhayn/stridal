#!/bin/sh
# Has every check GATE_PR_CHECKS requires started on the PR's head commit? (merge-pr, step 2)
#
#   sh .claude/skills/merge-pr/ci-started.sh <pr>
#
# A watch is evidence only of a check that exists. `gh pr ready` seconds after a push can leave the
# head with no run of the required check: the ready event's run belongs to the commit before and the
# push's run saw a draft and skipped. `gh pr checks --watch --required` then has nothing to wait for.
#
# Did the required check start? The required NAMES in the head's rollup, read with the head in one
# answer, matched as the merge guard matches them. Started is any result but skipped, neutral or
# cancelled (a red is a start, and the guard reads it); a check only `expected` has not started.
# `gh run list --commit <head>` cannot answer this: it shows a run of any workflow, and a skipped
# required check beside another workflow's success is the very state in question.
#
# Is anything live on the head? The rollup, and the head's Actions runs, which alone show a run with
# no job yet. A read of the runs that fails is unknown, never nothing live.
#
# A toggle (`gh pr ready --undo`, then `gh pr ready`) fires the ready event on the head as it now is.
# Absence alone is not evidence that a run was lost, so it toggles only for a name the rollup holds as
# skipped, neutral or cancelled, or an empty rollup; only with nothing live; and only after a wait, as
# a toggle straight after a push is the same race again. The clock allows two. A name absent beside
# other checks never toggles, so a typo restarts nothing; the cost is that a workflow triggered only by
# ready_for_review, with other checks present, stops at exit 1. Known race: a run that registers
# after the runs read and before the undo can be cancelled by the toggle.
#
# A draft is marked ready on every path, and that ready can start a run the rollup does not show yet,
# so it looks for one, for up to 30 s, before it answers: the reader then watches it here, rather than
# merge-pr's own later ready firing it and the guard blocking once.
#
# It stops itself at about 224 s with real gh latency, and under 280 s with gh at 10 s a call, inside
# the five minutes the skill gives the tool. Known limits: no gh call has its own timeout, so a gh
# that hangs is stopped only by the tool, with none of these words. A TERM, INT or HUP between the toggle's calls readies the PR
# before it dies (or says it could not); a kill -9 there leaves a draft, which merge-pr's context names.
#
# Exit 0: every required name started on the head, each named on stdout; or none is required. A
# readied draft's new run, if the look found one, is named there too.
# Exit 1: nothing live and a name not started: STOP, and its message says why that is.
# Exit 2: usage.
# Exit 3: a read or a refusal stopped it (gh, jq, or GATE_PR_CHECKS): that says nothing about CI.
# Exit 4: a name not started and something live on the head: its message says what to wait on.
# Killed by a signal: 143, 130 or 129.
# Checked by .claude/checks/ci-started.sh.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
# A `.` of a missing file ends the shell with a status of the shell's choosing: on macOS, 1.
if [ ! -f "$ROOT/.claude/lib/conf.sh" ]; then
  echo "ci-started: cannot read $ROOT/.claude/lib/conf.sh" >&2
  exit 3
fi
# shellcheck disable=SC1091
. "$ROOT/.claude/lib/conf.sh"

if [ $# -ne 1 ] || [ -z "$1" ] || [ "${1#-}" != "$1" ]; then
  echo "usage: ci-started.sh <pr>" >&2
  exit 2
fi
pr=$1

die() {
  echo "ci-started: $1" >&2
  exit 3
}

if conf_bad GATE_PR_CHECKS; then
  die "cannot read GATE_PR_CHECKS: $(conf_why GATE_PR_CHECKS)"
fi
for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

# wall-clock: these bounds are the time the tool that runs this will wait, so real time is the point.
now() { date +%s; }
WINDOW=70 # seconds with no toggle before the next
DEADLINE=210
LOOK=30 # seconds a readied draft is looked at for a new run
INTERVAL=15

ROLLUP='def entries: (.statusCheckRollup // [])[] | objects;
  def shown: "\(.name // .context // "?")=\(if (.conclusion // "") != "" then .conclusion else (.status // .state // "?") end)";
  def lost: .conclusion == "SKIPPED" or .conclusion == "NEUTRAL" or .conclusion == "CANCELLED";'
NOT_THE_PR="gh pr view $pr did not return the PR. That is gh, not CI."

# read_pr: sets view, head, draft, reported, started (name=result, ...), and the names not started as
# held (the rollup has them, skipped, neutral or cancelled) or absent (it does not).
read_pr() {
  view=$(gh pr view "$pr" --json headRefOid,isDraft,statusCheckRollup) \
    || die "gh pr view $pr failed. That is gh (auth or network: gh auth status), not CI."
  head=$(printf '%s' "$view" | jq -er '.headRefOid | strings' 2>/dev/null) || die "$NOT_THE_PR"
  draft=$(printf '%s' "$view" | jq -r '.isDraft' 2>/dev/null) || die "$NOT_THE_PR"
  reported=$(printf '%s' "$view" | jq -r "$ROLLUP"'[ entries | shown ] | join(", ")' 2>/dev/null) || die "$NOT_THE_PR"
  started="" held="" absent=""
  for want in $GATE_PR_CHECKS; do
    got=$(printf '%s' "$view" | jq -r --arg w "$want" "$ROLLUP"'
      [ entries | select((.name // .context // "") as $n | $n == $w or ($n | startswith($w + " ("))) ] as $m
      | [ $m[] | select((lost | not) and .state != "EXPECTED") | shown ] as $s
      | if ($s | length) > 0 then "S" + ($s | join(", ")) elif ($m | any(lost)) then "H" else "A" end' 2>/dev/null) || die "$NOT_THE_PR"
    case $got in
      S*) started="${started:+$started, }${got#S}" ;;
      H) held="${held:+$held }$want" ;;
      *) absent="${absent:+$absent }$want" ;;
    esac
  done
}

# read_live: sets live (what is not finished in the rollup), runs_live (in the Actions runs), and
# runs_read ("" when the runs could not be read).
read_live() {
  live=$(printf '%s' "$view" | jq -r "$ROLLUP"'
    [ entries | select((.status != null and .status != "COMPLETED") or .state == "PENDING") | shown ] | join(", ")' 2>/dev/null) || die "$NOT_THE_PR"
  runs_live="" runs_read=""
  runs=$(gh run list --commit "$head" --limit 100 --json status,workflowName) || return 0
  runs_live=$(printf '%s' "$runs" | jq -er 'arrays | [ .[] | select(.status != "completed") | "\(.workflowName)=\(.status)" ] | join(", ")' 2>/dev/null) || return 0
  runs_read=1
}

# answer [RUNS]: RUNS is what this very read found live, as a read before a toggle would be stale here.
answer() {
  echo "ci-started: PR #$pr head $(printf %.9s "$head"): ${started:-GATE_PR_CHECKS names no check, so there is none to confirm}"
  [ -z "${1:-}" ] || echo "ci-started: also live in the head's Actions runs: $1. gh pr checks may not show it yet, and can still read the pass before it: see it with gh run list --commit $head, and read gh pr checks once it has jobs."
  exit 0
}

killed_in_toggle() {
  gh pr ready "$pr" || echo "ci-started: killed between the toggle's calls, and gh pr ready $pr was refused: this leaves it a draft" >&2
  exit "$1"
}

start=$(now)
since=$start
toggles=0
readied=""
while :; do
  read_pr
  t=$(now)
  if [ "$draft" = true ]; then
    gh pr ready "$pr" || die "gh pr ready $pr was refused (gh's reason above), so it is still a draft. That says nothing about CI."
    readied=1
  fi
  if [ -z "$held$absent" ]; then
    { [ -z "$readied" ] || [ $((t - start)) -ge "$LOOK" ]; } && answer
    read_live
    [ -z "$live$runs_live" ] || answer "$runs_live"
  elif [ $((t - start)) -ge "$DEADLINE" ]; then
    break
  elif { [ -n "$held" ] || [ -z "$reported" ]; } && [ $((t - since)) -ge "$WINDOW" ]; then
    read_live
    if [ -z "$live$runs_live" ] && [ -n "$runs_read" ]; then
      toggles=$((toggles + 1))
      echo "ci-started: PR #$pr head $(printf %.9s "$head"): ${held:-$absent} not started and nothing live; toggling draft and ready"
      # Only across these two calls: a signal here would leave the PR a draft with no word.
      trap 'killed_in_toggle 143' TERM
      trap 'killed_in_toggle 130' INT
      trap 'killed_in_toggle 129' HUP
      gh pr ready "$pr" --undo || die "gh pr ready $pr --undo was refused (gh's reason above), so the PR is as it was. That says nothing about CI."
      gh pr ready "$pr" || die "gh pr ready $pr was refused after the undo (gh's reason above), which leaves it a draft: run gh pr ready $pr. That says nothing about CI."
      trap - TERM INT HUP
      since=$(now)
    fi
  fi
  sleep "$INTERVAL"
done

read_live
where="PR #$pr head $(printf %.9s "$head")"
if [ -n "$live" ]; then
  echo "ci-started: NOT YET. $where: $held $absent not started, and live on the head: $live${runs_live:+, $runs_live}. Nothing was toggled over it. Watch it (gh pr checks $pr --watch) and run this again. If a name has still not reported once nothing is live, compare GATE_PR_CHECKS with the names the head reports: ${reported:-nothing}." >&2
  exit 4
fi
if [ -n "$runs_live" ]; then
  echo "ci-started: NOT YET. $where: $held $absent not started, and live in the head's Actions runs, with no check reporting it yet: $runs_live. Nothing was toggled over it, and gh pr checks cannot watch it. See it with gh run list --commit $head and run this again once it has jobs: this is not a second exit 4. If a name has still not reported once nothing is live, compare GATE_PR_CHECKS with the names the head reports: ${reported:-nothing}." >&2
  exit 4
fi
if [ -z "$runs_read" ]; then
  die "$where: $held $absent not started, and gh run list could not be read, so whether a run is live on the head is unknown, and nothing was toggled on it. Fix that (auth or network: gh auth status) and run this again."
fi
echo "ci-started: STOP. $where, after $toggles toggle(s), nothing live. The head reports: ${reported:-nothing}." >&2
[ -z "$held" ] || echo "ci-started: $held is still skipped, neutral or cancelled on the head: a person must read why (the job's if:, its workflow's triggers)." >&2
if [ -z "$reported" ]; then
  echo "ci-started: Compare GATE_PR_CHECKS with the workflows' job names, or CI is not running (billing, disabled workflows)." >&2
elif [ -n "$absent" ]; then
  echo "ci-started: Compare GATE_PR_CHECKS with those names: $absent reported nothing. If a name is right, no run of it reached this head, or it reports later: run this again once it should have." >&2
fi
exit 1
