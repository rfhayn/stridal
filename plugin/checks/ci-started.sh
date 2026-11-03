#!/bin/sh
STRIDAL_FW=$(cd "$(dirname "$0")/.." && pwd) # stridal plugin: the plugin root (framework/internal/plugin)
# merge-pr's step 2 confirms each check GATE_PR_CHECKS requires has started on the PR's head commit
# before it trusts a watch, and toggles draft and ready only for a name the head holds as skipped,
# cancelled or neutral, or a head with no checks at all (skills/merge-pr/ci-started.sh). A stub gh
# and a stub clock that only sleep and each gh call advance, so no case waits and the time a run would
# take is still measured. The stub's answers copy the COMPLETED shapes real gh returned for #389's head
# and for a draft's; a live rollup entry, a StatusContext and `in_progress` from the runs read are its
# own, from gh's documented fields: none of the three has been seen on the read the script uses.
#
#   - #389's state, alone and beside a second required check that passed: it toggles, with a wait
#     before EACH toggle. A name merely absent (a typo, a status that reports later) never toggles;
#   - never a toggle while anything is live on the head, or when the read of the runs fails;
#   - each way it ends has its own exit, words true of its cause, and its next step in the skill;
#   - a draft is marked ready on every path, its new run seen before it exits, and the skill's step 2
#     reaches a green draft, so step 4's ready fires nothing new. A signal between the toggle's two
#     calls readies it again; a kill -9 there is the limit;
#   - it stops, with its words, well inside the tool's five minutes.
. "$(dirname "$0")/lib.sh"
need jq

d=$(scratch)
mkdir -p "$d/bin" "$d/p/.claude/lib" "$d/p/.claude/skills/merge-pr" "$d/s"
cp "$STRIDAL_FW/lib/conf.sh" "$d/p/.claude/lib/"
cp "$STRIDAL_FW/skills/merge-pr/ci-started.sh" "$d/p/.claude/skills/merge-pr/" 2>/dev/null
S="$d/p/.claude/skills/merge-pr/ci-started.sh"
HEAD_SHA=b7f4d8bb1e7d9e5a894341d3c3648b48eb9d4c23

cat > "$d/bin/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >> "$GH_STATE/log"
echo $(($(cat "$GH_STATE/clock") + ${GH_COST:-1})) > "$GH_STATE/clock"
case "$1 $2" in
  "pr view")
    [ ! -f "$GH_STATE/view-fails" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    [ ! -f "$GH_STATE/view-garbage" ] || { echo "not json"; exit 0; }
    # A rollup this read brings: a check that reports later than the first reads.
    v=$(($(cat "$GH_STATE/views") + 1)); echo "$v" > "$GH_STATE/views"
    [ ! -f "$GH_STATE/rollup-at-$v" ] || cp "$GH_STATE/rollup-at-$v" "$GH_STATE/rollup"
    [ ! -f "$GH_STATE/runs-at-$v" ] || cp "$GH_STATE/runs-at-$v" "$GH_STATE/runs"
    printf '{"headRefOid":"%s","isDraft":%s,"statusCheckRollup":%s}\n' "$HEAD_SHA" "$(cat "$GH_STATE/draft")" "$(cat "$GH_STATE/rollup")" ;;
  "run list")
    [ ! -f "$GH_STATE/runs-fail-once" ] || { rm -f "$GH_STATE/runs-fail-once"; echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    [ ! -f "$GH_STATE/runs-fail" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    [ ! -f "$GH_STATE/runs-garbage" ] || { echo "not json"; exit 0; }
    cat "$GH_STATE/runs" ;;
  "pr ready")
    case "$*" in
      *--undo*)
        [ ! -f "$GH_STATE/undo-fails" ] || { echo "undo refused: not the author" >&2; exit 1; }
        echo true > "$GH_STATE/draft"
        [ ! -f "$GH_STATE/undo-kills" ] || { sig=$(cat "$GH_STATE/undo-kills"); rm -f "$GH_STATE/undo-kills"; kill -"$sig" "$PPID"; }
        exit 0 ;;
    esac
    [ ! -f "$GH_STATE/ready-fails" ] || { echo "ready refused" >&2; exit 1; }
    echo false > "$GH_STATE/draft"
    n=$(($(cat "$GH_STATE/readies") + 1)); echo "$n" > "$GH_STATE/readies"
    # A run starts on the ready this case names, and on no other: a ready can leave none.
    [ ! -f "$GH_STATE/starts-on-$n" ] || cp "$GH_STATE/starts-on-$n" "$GH_STATE/rollup"
    [ ! -f "$GH_STATE/runs-on-$n" ] || cp "$GH_STATE/runs-on-$n" "$GH_STATE/runs" ;;
esac
exit 0
EOF
# A clock past any budget stops the run, so a script that never ends fails here instead of hanging.
# CLOCK_SCALE: a case with no use for the real cadence takes fewer reads to reach the same deadline.
cat > "$d/bin/sleep" <<'EOF'
#!/bin/sh
echo "sleep $1" >> "$GH_STATE/log"
t=$(($(cat "$GH_STATE/clock") + $1 * CLOCK_SCALE)); echo "$t" > "$GH_STATE/clock"
[ "$t" -lt 2000 ] || { echo "stub clock: past 2000 s, still running" >&2; kill -TERM "$PPID"; }
EOF
cat > "$d/bin/date" <<'EOF'
#!/bin/sh
cat "$GH_STATE/clock"
EOF
chmod +x "$d/bin/gh" "$d/bin/sleep" "$d/bin/date"

check() {  # check NAME WORKFLOW STATUS CONCLUSION
  printf '{"__typename":"CheckRun","name":"%s","workflowName":"%s","status":"%s","conclusion":"%s"}' "$1" "$2" "$3" "$4"
}
status() {  # status CONTEXT STATE
  printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"
}
SKIPPED=$(check test test COMPLETED SKIPPED)
OTHER_OK=$(check build release-build COMPLETED SUCCESS)
RUNNING=$(check "test (ubuntu-latest)" test IN_PROGRESS "")
PASSED=$(check "test (ubuntu-latest)" test COMPLETED SUCCESS)
# A required check skipped on the head, and a run of another workflow that passed: what #389's head
# held when the watch read as a pass, and what any draft of this repository holds.
HELD="[$SKIPPED,$OTHER_OK]"
STARTED="[$SKIPPED,$OTHER_OK,$RUNNING]"
RUNS_DONE='[{"status":"completed","workflowName":"test"},{"status":"completed","workflowName":"release-build"}]'
RUNS_LIVE='[{"status":"completed","workflowName":"release-build"},{"status":"in_progress","workflowName":"test"}]'
RUNS_HELD='[{"status":"completed","workflowName":"release-build"},{"status":"pending","workflowName":"test"}]'
REASON_HELD="a person must read why"
REASON_ABSENT="Compare GATE_PR_CHECKS"
REASON_EMPTY="CI is not running"

# fresh CHECKS DRAFT ROLLUP [RUNS]: a new case, at the fast clock unless it says `real`.
fresh() {
  rm -rf "$d/s"; mkdir -p "$d/s"
  printf 'GATE_PR_CHECKS="%s"\n' "$1" > "$d/p/.claude/project.conf"
  echo "$2" > "$d/s/draft"
  printf '%s\n' "$3" > "$d/s/rollup"
  printf '%s\n' "${4:-$RUNS_DONE}" > "$d/s/runs"
  echo 0 > "$d/s/readies"; echo 0 > "$d/s/views"; echo 0 > "$d/s/clock"
  : > "$d/s/log"
  rm -f "$d/out"
  scale=4 cost=1
}
real() { scale=1; }
starts_on() { printf '%s\n' "$2" > "$d/s/starts-on-$1"; }
run() {  # run: the script, on PR 5; its output in $d/out, its exit in $rc
  rc=0
  PATH="$d/bin:$PATH" GH_STATE="$d/s" HEAD_SHA="$HEAD_SHA" CLOCK_SCALE=$scale GH_COST=$cost sh "$S" 5 > "$d/out" 2>&1 || rc=$?
}
count() { grep -c -- "$1" "$d/s/log"; }
readies() { grep '^gh pr ready' "$d/s/log" | tr '\n' ';' | sed 's/;$//'; }
said() {  # said TEXT LABEL
  grep -qF -- "$1" "$d/out" && ok "$2" || fail "$2: no '$1' in: $(cat "$d/out")"
}
not_said() {  # not_said TEXT LABEL
  grep -qF -- "$1" "$d/out" && fail "$2: '$1' in: $(cat "$d/out")" || ok "$2"
}
is() {  # is WANT GOT LABEL
  [ "$1" = "$2" ] && ok "$3" || fail "$3: got '$2', want '$1'; log: $(tr '\n' ';' < "$d/s/log"); output: $(cat "$d/out")"
}
toggled() {  # toggled LABEL: at least once
  [ "$(count '--undo')" -gt 0 ] && ok "$1" || fail "$1: no toggle; log: $(tr '\n' ';' < "$d/s/log")"
}
# The seconds slept before each undo, since the one before it.
gaps() { awk '/--undo/ { print t + 0; t = 0 } /^sleep / { t += $2 }' "$d/s/log"; }

# ── The state that read as a pass ───────────────────────────────────────────────────────────
fresh test false "$HELD"; starts_on 1 "$STARTED"; run
expect_rc 0 "$rc" "a skipped required check beside another workflow's success: a toggle starts it, exit 0"
is 1 "$(count '--undo')" "...one toggle, not none: another workflow's run on the head is not this check's"
is "gh pr ready 5 --undo;gh pr ready 5" "$(readies)" "...undo first, then ready"
said "test (ubuntu-latest)=IN_PROGRESS" "...and it names the check it saw start"
said "$(printf %.9s "$HEAD_SHA")" "...on the head it read"
is false "$(cat "$d/s/draft")" "...and the PR ends ready"
# The stub answers every read the same: only the command line says what was asked for.
grep -qFx "gh run list --commit $HEAD_SHA --limit 100 --json status,workflowName" "$d/s/log" && ok "...the runs read asks for this head's runs, past gh's default of 20" || fail "the runs read is not as pinned: $(grep '^gh run' "$d/s/log" | head -n 1)"
grep -qFx 'gh pr view 5 --json headRefOid,isDraft,statusCheckRollup' "$d/s/log" && ok "...and the PR read asks for the head, the draft and the rollup in one answer" || fail "the PR read is not as pinned: $(grep '^gh pr view' "$d/s/log" | head -n 1)"

fresh "test lint" false "[$SKIPPED,$(status lint SUCCESS)]"; starts_on 1 "[$SKIPPED,$RUNNING,$(status lint SUCCESS)]"; run
expect_rc 0 "$rc" "test=SKIPPED beside lint=SUCCESS, both required: a toggle starts it, exit 0"
is 1 "$(count '--undo')" "...one toggle: a second required check that passed does not hide a lost run"

# ── A draft, as the context reports it ──────────────────────────────────────────────────────
fresh test true "$HELD"; starts_on 1 "$STARTED"; run
expect_rc 0 "$rc" "a draft whose ready starts the run: exit 0"
is "gh pr ready 5" "$(readies)" "...one ready and no toggle"

fresh test true "$HELD"; starts_on 2 "$STARTED"; run
expect_rc 0 "$rc" "a ready right after a push, which leaves no run: the toggle starts it, exit 0"
is "gh pr ready 5;gh pr ready 5 --undo;gh pr ready 5" "$(readies)" "...ready, then undo, then ready"

# A green draft, which step 2 now reaches. Left a draft, step 4's ready would fire a new run after
# step 2 read green, and the guard would block once: so it is readied here, and its run seen here.
fresh test true "[$PASSED]"; starts_on 1 "[$RUNNING]"; run
expect_rc 0 "$rc" "a green draft: exit 0"
is "gh pr ready 5" "$(readies)" "...marked ready in step 2, not left for step 4's ready"
said "test (ubuntu-latest)=IN_PROGRESS" "...and it reports the run that ready started, not the pass before it"
fresh test true "[$PASSED]"; printf '%s\n' "$RUNS_LIVE" > "$d/s/runs-on-1"; run
expect_rc 0 "$rc" "...a run that ready started and only the runs show yet: exit 0"
is 0 "$(count '--undo')" "...and no toggle"
said "test=in_progress" "...and it names that run: gh pr checks can still read the pass before it"
said "gh run list --commit $HEAD_SHA" "...and how to see it"
fresh test true "[$PASSED]"; real; run
expect_rc 0 "$rc" "a green draft whose ready starts no new run: exit 0, once it has looked"
is "gh pr ready 5" "$(readies)" "...and no toggle"
not_said "live in the head's Actions runs" "...and names no run, as it saw none"
t=$(cat "$d/s/clock"); [ "$t" -gt 0 ] && [ "$t" -le 60 ] && ok "...and that look is short ($t s)" || fail "looked for $t s"

# ── A ready PR is left alone when its name has started ──────────────────────────────────────
for c in "QUEUED:" "COMPLETED:SUCCESS" "COMPLETED:FAILURE"; do
  fresh test false "[$SKIPPED,$(check "test (ubuntu-latest)" test "${c%:*}" "${c#*:}")]"; run
  expect_rc 0 "$rc" "started: test (ubuntu-latest) $c"
  is 0 "$(count '^gh pr ready')" "...no ready, no toggle: a red is a start, and the guard reads it"
  is 0 "$(count '^sleep')" "...and no wait"
done

# ── A name the head holds as not run: toggled, then a person reads why ──────────────────────
fresh test false "$HELD"; real; run
expect_rc 1 "$rc" "still skipped after the toggles: exit 1, never a pass"
is 2 "$(count '--undo')" "...it toggles twice, as the clock allows"
said "STOP" "...and says stop"
said "after 2 toggle(s)" "...and counts the toggles it made"
said "$REASON_HELD" "...and that a person must read why"
said "build=SUCCESS" "...with the names gh does show"
not_said "$REASON_ABSENT" "...and not to compare the names: this name is on the head"
not_said "$REASON_EMPTY" "...and not that CI is not running: a run skipped it"
is false "$(cat "$d/s/draft")" "...and leaves the PR ready, not a draft"
n=0; for g in $(gaps); do
  n=$((n + 1))
  [ "$g" -ge 60 ] && ok "...toggle $n comes after a wait of $g s: straight after a push is the race itself" || fail "toggle $n came after only $g s; log: $(tr '\n' ';' < "$d/s/log")"
done
is 2 "$n" "...two gaps measured, one before each toggle"
for c in CANCELLED NEUTRAL; do
  fresh test false "[$(check "test (ubuntu-latest)" test COMPLETED $c)]"; run
  expect_rc 1 "$rc" "$c on the head: not started"
  toggled "...so it is toggled"
  said "$REASON_HELD" "...and a person reads why"
done
fresh test false "[]"; run
expect_rc 1 "$rc" "no checks at all on the head: not started"
toggled "...so it is toggled"
said "$REASON_EMPTY" "...and it says CI may not be running"
said "$REASON_ABSENT" "...or the names are wrong"

# ── A name merely absent never toggles: absence is not evidence of a lost run ───────────────
absent() {  # absent CHECKS ROLLUP LABEL
  fresh "$1" false "$2"; run
  expect_rc 1 "$rc" "$3: exit 1"
  is 0 "$(count '--undo')" "...no toggle: nothing restarts a suite for it"
  said "$REASON_ABSENT" "...and it says to compare the names"
  not_said "$REASON_HELD" "...and no more than that"
  not_said "$REASON_EMPTY" "...and not that CI is not running: the head has checks"
}
absent tset "[$PASSED]" "a typo as the only name, its suite passed"
absent "test tset" "[$PASSED]" "a typo beside a name that started"
absent test "[$OTHER_OK]" "a workflow that runs only on ready_for_review, with other checks on the head"
absent test "[$(check testing ci COMPLETED SUCCESS)]" "a check whose name only starts with the required name"
absent test "[$(check "test-e2e (x)" ci COMPLETED SUCCESS)]" "a matrix job of another name"
absent ci/x "[$(status ci/x EXPECTED)]" "a status that is only expected"
absent test "[{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]" "an entry with neither name nor context"
fresh "test tset" false "[$SKIPPED]"; run
expect_rc 1 "$rc" "one name skipped and one absent: exit 1"
toggled "...toggled for the skipped one"
said "$REASON_HELD" "...it says a person reads why of the one"
said "$REASON_ABSENT" "...and to compare the other"
fresh "test lint" false "[$PASSED]"; real
printf '%s\n' "[$PASSED,$(status lint SUCCESS)]" > "$d/s/rollup-at-9"; run
expect_rc 0 "$rc" "a status that posts after the suite ended: started"
is 0 "$(count '--undo')" "...and no re-run of the suite"

# ── Never a toggle while anything is live on the head ───────────────────────────────────────
held() {  # held WANT-EXIT LABEL: no toggle, and the words for what it stopped on
  expect_rc "$1" "$rc" "$2"
  is 0 "$(count '--undo')" "...no toggle"
}
# `started` and `missing` are built before any decision, so one order of two names can stand for both.
for names in "test lint" "lint test"; do
  fresh "$names" false "[$SKIPPED,$RUNNING]" "$RUNS_LIVE"; run
  held 4 "'$names', a suite running and lint not reported: not yet"
  said "test (ubuntu-latest)=IN_PROGRESS" "...it says what is live"
  said "gh pr checks 5 --watch" "...and to watch it"
  said "GATE_PR_CHECKS" "...and to compare the names"
  said "lint" "...naming the one not started"
  not_said "$REASON_EMPTY" "...and never that CI is not running"
done
fresh "test lint" false "[$RUNNING]" "$RUNS_LIVE"; real
printf '%s\n' "[$RUNNING,$(status lint PENDING)]" > "$d/s/rollup-at-4"; run
held 0 "a second name reporting while the suite runs: started"
fresh test false "$HELD" "$RUNS_HELD"; run
held 4 "a run held pending, with no job in the rollup yet: not yet"
said "test=pending" "...named as the runs read says it"
said "gh run list --commit $HEAD_SHA" "...and how to see it, since no check reports it"
not_said "gh pr checks 5 --watch" "...not a watch, which would end at once"
fresh test false "[$SKIPPED,$(check build release-build IN_PROGRESS "")]"; run
held 4 "another workflow's job still running: not yet"
said "gh pr checks 5 --watch" "...a check, so a watch sees it"
fresh test false "[$SKIPPED,$(status ci/other PENDING)]"; run
held 4 "a commit status still pending: not yet"
fresh test false "$HELD"; real; printf '%s\n' "$RUNS_HELD" > "$d/s/runs-on-1"; run
expect_rc 4 "$rc" "a run the first toggle started, with no job yet: not yet"
is 1 "$(count '--undo')" "...and no second toggle over it"
fresh test false "$HELD" "$RUNS_LIVE"; printf '%s\n' "$RUNS_DONE" > "$d/s/runs-at-3"; starts_on 1 "$STARTED"; run
expect_rc 0 "$rc" "a run gone by the time the wait is up: the toggle goes ahead"
is 1 "$(count '--undo')" "...once"

# ── The read of the runs failing is unknown, never nothing live ─────────────────────────────
fresh test false "$HELD"; : > "$d/s/runs-fail"; run
held 3 "gh run list fails throughout: exit 3"
said "unknown" "...it says what is unknown"
fresh test false "$HELD"; : > "$d/s/runs-garbage"; run
held 3 "gh run list answers with something else: exit 3"
fresh "test lint" false "[$SKIPPED,$RUNNING]"; : > "$d/s/runs-fail"; run
held 4 "the runs unreadable, a job live in the rollup: that is known, not yet"
fresh test false "$HELD"; : > "$d/s/runs-fail-once"; starts_on 1 "$STARTED"; run
expect_rc 0 "$rc" "the read failing once, then answering: it toggles on the answer"
is 1 "$(count '--undo')" "...once"

# ── What counts as a start ──────────────────────────────────────────────────────────────────
fresh "test lint" false "[$RUNNING,$(check lint ci QUEUED "")]"; run
expect_rc 0 "$rc" "every required name started: exit 0"
fresh ci/x false "[$(status ci/x PENDING)]"; run
expect_rc 0 "$rc" "a commit status reported pending is a start"
said "ci/x=PENDING" "...named by its context"
fresh test false "[$(check test test IN_PROGRESS "")]"; run
expect_rc 0 "$rc" "the bare name running is a start: the guard matches a name exactly too"

# ── No name to confirm ──────────────────────────────────────────────────────────────────────
fresh "" false "$HELD"; run
expect_rc 0 "$rc" "GATE_PR_CHECKS empty, a ready PR: nothing to confirm"
is 0 "$(count '^gh pr ready')" "...nothing readied, nothing toggled"
is 0 "$(count '^sleep')" "...and no wait"
said "GATE_PR_CHECKS" "...and it says so, not a bare exit"
fresh "" true "$HELD"; printf '%s\n' "$RUNS_LIVE" > "$d/s/runs-on-1"; run
expect_rc 0 "$rc" "GATE_PR_CHECKS empty, a draft: exit 0"
is "gh pr ready 5" "$(readies)" "...marked ready, not left for step 4's ready"
said "GATE_PR_CHECKS" "...and says it had no name to confirm"
fresh "" true "$HELD"; real; run
expect_rc 0 "$rc" "GATE_PR_CHECKS empty, a draft with no CI: exit 0"
is "gh pr ready 5" "$(readies)" "...and only that one ready"
t=$(cat "$d/s/clock"); [ "$t" -le 60 ] && ok "...paying a short look ($t s)" || fail "a draft with no CI pays $t s"
# A refused line leaves the key at its empty default, which must not read as "none required".
fresh test false "$HELD"; printf 'GATE_PR_CHECKS=test; rm x\n' > "$d/p/.claude/project.conf"; run
expect_rc 3 "$rc" "a GATE_PR_CHECKS line conf.sh refuses: exit 3, not nothing to confirm"
is 0 "$(count .)" "...and not one gh call"

# ── Each failure's exit, and words that match its cause ─────────────────────────────────────
fresh test false "$HELD"; : > "$d/s/view-fails"; run
expect_rc 3 "$rc" "gh cannot read the PR: exit 3"
is 0 "$(count '^gh pr ready')" "...no toggle on a read that failed"
said "gh auth status" "...and it points at gh, not CI"
fresh test false "$HELD"; : > "$d/s/view-garbage"; run
expect_rc 3 "$rc" "gh answers with something that is not the PR: exit 3"
is 0 "$(count '^gh pr ready')" "...no toggle on that either"
fresh test true "$HELD"; : > "$d/s/ready-fails"; run
expect_rc 3 "$rc" "a draft's ready refused: exit 3"
said "ready refused" "...with gh's own reason"
not_said "gh auth status" "...and no guess that it is the login"
fresh test false "$HELD"; : > "$d/s/undo-fails"; run
expect_rc 3 "$rc" "the toggle's undo refused: exit 3"
is 1 "$(count '--undo')" "...and it stops there"
said "not the author" "...with gh's own reason"
not_said "gh auth status" "...and no guess that it is the login"
is false "$(cat "$d/s/draft")" "...the PR still ready"
fresh test false "$HELD"; : > "$d/s/ready-fails"; run
expect_rc 3 "$rc" "the toggle's ready refused: exit 3"
said "leaves it a draft" "...and it says the PR is left a draft"
not_said "gh auth status" "...and no guess that it is the login"
rm "$d/p/.claude/lib/conf.sh"
fresh test false "$HELD"; run
expect_rc 3 "$rc" "conf.sh missing: exit 3, not the 1 that means compare GATE_PR_CHECKS"
said "conf.sh" "...and it names the file"
cp "$STRIDAL_FW/lib/conf.sh" "$d/p/.claude/lib/"
# gh or jq not installed: a PATH of only what the script needs, less the one under test.
mkdir -p "$d/nogh" "$d/nojq"
for t in dirname sh cat grep sed awk tr head cut printf; do
  p=$(command -v "$t") || continue
  case $p in /*) ln -sf "$p" "$d/nogh/$t"; ln -sf "$p" "$d/nojq/$t" ;; esac
done
ln -sf "$(command -v jq)" "$d/nogh/jq"
ln -sf "$d/bin/gh" "$d/nojq/gh"
for t in nogh nojq; do
  fresh test false "$HELD"; rc=0
  PATH="$d/$t" GH_STATE="$d/s" HEAD_SHA="$HEAD_SHA" "$d/nogh/sh" "$S" 5 > "$d/out" 2>&1 || rc=$?
  expect_rc 3 "$rc" "$t: exit 3"
  said "not installed" "...and it says so"
done

# ── Inside the tool's five minutes, in its own words ────────────────────────────────────────
for c in 1 10; do
  fresh test false "$HELD"; real; cost=$c; run
  expect_rc 1 "$rc" "gh at $c s a call: it ends by itself, exit 1"
  said "STOP" "...with its words"
  t=$(cat "$d/s/clock")
  [ "$t" -le 280 ] && ok "...at $t s, a real margin under the 300 s the skill gives the tool" || fail "ends at $t s, with gh at $c s a call"
done
fresh test false "$HELD" "$RUNS_LIVE"; real; cost=10; run
expect_rc 4 "$rc" "a live head, gh at 10 s a call: it ends by itself, exit 4"
t=$(cat "$d/s/clock"); [ "$t" -le 280 ] && ok "...at $t s" || fail "ends at $t s"

# ── A signal between the toggle's two calls ─────────────────────────────────────────────────
# No shell can trap a signal it starts with ignored, and run.sh's parallel phase starts each check in
# the background, with INT ignored: there INT cannot reach the script, and that run says so by name.
for c in TERM:143 INT:130 HUP:129; do
  sig=${c%:*} want=${c#*:}
  if ! sh -c 'trap "exit 0" "$1"; kill -"$1" $$; exit 1' sh "$sig"; then
    ok "$sig between the undo and the ready: NOT exercised, this run started with $sig ignored; run this check alone"
    continue
  fi
  fresh test false "$HELD"; echo "$sig" > "$d/s/undo-kills"; run
  expect_rc "$want" "$rc" "$sig between the undo and the ready: it dies of it"
  is false "$(cat "$d/s/draft")" "...and readies the PR first: a kill never leaves it a draft with no word"
  fresh test false "$HELD"; echo "$sig" > "$d/s/undo-kills"; : > "$d/s/ready-fails"; run
  expect_rc "$want" "$rc" "...and when that ready is refused"
  said "leaves it a draft" "...it says the PR is left a draft"
done

# ── Its arguments ───────────────────────────────────────────────────────────────────────────
fresh test false "$HELD"
for a in "" "5 6" "--undo"; do
  rc=0
  # shellcheck disable=SC2086
  PATH="$d/bin:$PATH" GH_STATE="$d/s" HEAD_SHA="$HEAD_SHA" CLOCK_SCALE=1 sh "$S" $a > "$d/out" 2>&1 || rc=$?
  expect_rc 2 "$rc" "arguments '$a': usage"
done
is 0 "$(count .)" "...and no gh call: a flag never reaches gh pr ready"

# ── The step that runs it, and reads each exit ──────────────────────────────────────────────
SK="$STRIDAL_FW/skills/merge-pr/SKILL.md"
step2=$(awk '/^### 2\. /{on=1} /^### 2b\. /{on=0} on' "$SK")
# On one line: a sentence the skill wraps is still one sentence to hold.
flat=$(printf '%s\n' "$step2" | tr '\n' ' ' | sed 's/  */ /g')
first_watch='gh pr checks <n> --watch'
before_watch=${flat%%"$first_watch"*}
printf '%s\n' "$step2" | grep -qF 'skills/merge-pr/ci-started.sh <n>' && ok "merge-pr's step 2 runs ci-started.sh" || fail "merge-pr's step 2 does not run ci-started.sh"
# The first watch, so the later one, on exit 0's path, cannot stand in for exit 4's.
case $before_watch in
  *'skills/merge-pr/ci-started.sh <n>'*'A check is live: `') ok "...before the first watch, which is exit 4's for a live check" ;;
  *) fail "merge-pr's step 2 has no watch after ci-started.sh for a live check before any other watch" ;;
esac
printf '%s\n' "$step2" | grep 'skills/merge-pr/ci-started.sh <n>' | grep -q 'five minutes' && ok "...and gives it the five minutes it can take" || fail "merge-pr's step 2 does not say how long ci-started.sh can take"
for w in '- **A required check has not reported or is not green, or the PR is a draft**' 'skipped, neutral or cancelled' 'toggles draft and ready only for a name the head holds as one of those, or a head with no checks at all, with nothing live on it' 'Exit 0 names what started, and any run live on the head' 'Exit 1: STOP' 'a name absent means compare `GATE_PR_CHECKS` with the names it prints' 'a name still skipped after the toggles means a person must read why' 'Exit 3:' 'Exit 4:' 'A check is live: `gh pr checks <n> --watch`, then run it again, once' 'a second exit 4 is a STOP' 'gh run list --commit <head>' 'does not count as the second'; do
  case $flat in
    *"$w"*) ok "...and reads '$w'" ;;
    *) fail "merge-pr's step 2 does not read '$w'" ;;
  esac
done
finish
