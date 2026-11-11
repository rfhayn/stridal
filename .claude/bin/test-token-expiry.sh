#!/usr/bin/env bash
# Self-test for token-expiry.sh. Run: bash .claude/bin/test-token-expiry.sh (from any cwd).
# Fixtures (gh outputs, state files) are generated into a throwaway mktemp -d; gh is never called.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/test-token-expiry.XXXXXX")   # macOS's bare mktemp -d ignores $TMPDIR
trap 'rm -rf "$T"' EXIT
total=0; fail=0
EXPIRY=${TOKEN_EXPIRY_UNDER_TEST:-$here/token-expiry.sh}
mkdir -p "$T/bin" "$T/s"
# A gh that always fails, first on PATH: a missing fixture hook can never reach the network.
cat > "$T/bin/gh" <<'EOF'
#!/bin/sh
echo "fake gh: no network in tests" >&2; exit 99
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
unset TOKEN_EXPIRY_GH_OUT TOKEN_EXPIRY_GH_FAIL TOKEN_EXPIRY_NOW
S="$T/s/agent-token"
OUT="$T/gh.out"

epoch() { jq -nr --arg s "$1" '$s | fromdateiso8601'; }
EXP=$(epoch 2026-12-09T17:00:00Z)
DAY=86400

# ghout HEADER_LINE...  -> $OUT as `gh api -i user` prints it (status line, headers, blank line, body)
ghout() {
  { printf 'HTTP/2.0 200 OK\n'; printf 'Content-Type: application/json\n'
    [ $# -eq 0 ] || printf '%s\n' "$@"
    printf '\n{"login":"someone"}\n'; } > "$OUT"
}
HDR='Github-Authentication-Token-Expiration: 2026-12-09 17:00:00 UTC'

# case_ NAME WANT_EXIT WANT_REGEX NOW [ENV=VAL...] -- ARGS...   (whole stdout must match the bash regex)
case_() {
  local name=$1 want=$2 re=$3 now=$4; shift 4
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  total=$((total+1))
  local o got
  o=$(env TOKEN_EXPIRY_NOW="$now" TOKEN_EXPIRY_GH_OUT="$OUT" ${envs[@]+"${envs[@]}"} bash "$EXPIRY" "$@" 2>"$T/err")
  got=$?
  if [ "$got" != "$want" ]; then fail=$((fail+1)); echo "FAIL $name: want exit $want, got $got ($o $(cat "$T/err"))"
  elif ! [[ "$o" =~ $re ]]; then fail=$((fail+1)); echo "FAIL $name: stdout '$o' does not match $re"; fi
}
# state_is NAME WANT  -> the state file's content (trailing newlines dropped) must equal WANT
state_is() {
  total=$((total+1))
  local got
  got=$(cat "$S" 2>/dev/null)
  if [ "$got" != "$2" ]; then fail=$((fail+1)); echo "FAIL $1: state is '$got', want '$2'"; fi
}
A=(--state "$S")

# No header: a token with no expiry.
ghout
case_ "no header -> none" 0 '^none$' "$((EXP - 30*DAY))" -- "${A[@]}"
state_is "none clears the remembered expiry" ""

# Plenty of time left.
ghout "$HDR"
case_ ">14 days -> ok" 0 '^ok 15 2026-12-09$' "$((EXP - 15*DAY))" -- "${A[@]}"
state_is "ok records the expiry" 2026-12-09T17:00:00Z
case_ "14 days and 1s -> notify 14 (floor)" 0 '^notify 14 2026-12-09$' "$((EXP - 14*DAY - 1))" -- "${A[@]}"
rm -f "$S"

# The 14-day edge and once-a-day notification.
N14=$((EXP - 14*DAY))
D14=$(jq -nr --argjson n "$N14" '$n | todate | .[0:10]')
case_ "exactly 14 days -> notify" 0 '^notify 14 2026-12-09$' "$N14" -- "${A[@]}"
state_is "notify records today" "2026-12-09T17:00:00Z"$'\n'"$D14"
case_ "same UTC day again -> warned" 0 '^warned 13 2026-12-09$' "$((N14 + 3600))" -- "${A[@]}"
state_is "warned keeps today" "2026-12-09T17:00:00Z"$'\n'"$D14"
NEXT=$(( (N14 / DAY + 1) * DAY ))
D15=$(jq -nr --argjson n "$NEXT" '$n | todate | .[0:10]')
case_ "next UTC day -> notify again" 0 '^notify 13 2026-12-09$' "$NEXT" -- "${A[@]}"
state_is "notify records the new day" "2026-12-09T17:00:00Z"$'\n'"$D15"
case_ "last second -> notify 0" 0 '^notify 0 2026-12-09$' "$((EXP - 1))" -- "${A[@]}"

# Header spelling: lowercase name (HTTP/2) with a CR, and an offset.
rm -f "$S"
printf 'HTTP/2.0 200 OK\r\ngithub-authentication-token-expiration: 2026-12-09 17:00:00 UTC\r\n\r\n{}\r\n' > "$OUT"
case_ "lowercase header with CR" 0 '^ok 20 2026-12-09$' "$((EXP - 20*DAY))" -- "${A[@]}"
ghout 'Github-Authentication-Token-Expiration: 2026-12-09 12:00:00 -0500'
case_ "offset -0500 converts to UTC" 0 '^notify 2 2026-12-09$' "$((EXP - 2*DAY))" -- "${A[@]}"
state_is "offset stored as UTC" "2026-12-09T17:00:00Z"$'\n'"$(jq -nr --argjson n "$((EXP - 2*DAY))" '$n | todate | .[0:10]')"
ghout 'Github-Authentication-Token-Expiration: 2026-12-10 01:30:00 +0830'
case_ "offset +0830 converts to UTC" 0 '^ok 30 2026-12-09$' "$((EXP - 30*DAY))" -- "${A[@]}"
ghout 'X-Other: 1' 'Github-Authentication-Token-Expiration: 2026-12-09 17:00:00 +0000'
case_ "offset +0000 among other headers" 0 '^ok 30 2026-12-09$' "$((EXP - 30*DAY))" -- "${A[@]}"
# A header-like line in the body does not count.
{ printf 'HTTP/2.0 200 OK\n\n'; printf '%s\n' "$HDR"; } > "$OUT"
case_ "header only in the body -> none" 0 '^none$' "$((EXP - 30*DAY))" -- "${A[@]}"

# Expired.
ghout "$HDR"
case_ "past time -> expired" 0 '^expired 2026-12-09$' "$((EXP + 5))" -- "${A[@]}"
case_ "exactly now -> expired" 0 '^expired 2026-12-09$' "$EXP" -- "${A[@]}"
state_is "expired records the expiry" 2026-12-09T17:00:00Z

# The call fails (401 after expiry): the remembered expiry decides.
printf '2026-12-09T17:00:00Z\n\n' > "$S"
case_ "call fails + remembered past -> expired" 0 '^expired 2026-12-09$' "$((EXP + DAY))" TOKEN_EXPIRY_GH_FAIL=1 -- "${A[@]}"
case_ "call fails + remembered future -> refused" 2 '^$' "$((EXP - DAY))" TOKEN_EXPIRY_GH_FAIL=1 -- "${A[@]}"
rm -f "$S"
case_ "call fails + no state -> refused" 2 '^$' "$((EXP + DAY))" TOKEN_EXPIRY_GH_FAIL=1 -- "${A[@]}"
printf '\n\n' > "$S"
case_ "call fails + state after none -> refused" 2 '^$' "$((EXP + DAY))" TOKEN_EXPIRY_GH_FAIL=1 -- "${A[@]}"
printf 'garbage\n' > "$S"
case_ "call fails + garbage state -> refused" 2 '^$' "$((EXP + DAY))" TOKEN_EXPIRY_GH_FAIL=1 -- "${A[@]}"
# Without either hook the (fake, failing) gh is the call.
rm -f "$S"
case_ "real call path fails -> refused" 2 '^$' "$EXP" TOKEN_EXPIRY_GH_OUT= -- "${A[@]}"
printf '2026-12-09T17:00:00Z\n\n' > "$S"
case_ "real call path fails + remembered past -> expired" 0 '^expired 2026-12-09$' "$((EXP + 1))" TOKEN_EXPIRY_GH_OUT= -- "${A[@]}"

# Unparseable header values.
for v in '2026-12-09T17:00:00Z' '2026-12-09 17:00:00 PST' '2026-12-09 17:00:00' 'soon' '' '2026-13-40 17:00:00 UTC' '2026-12-09 17:00:00 +2460'; do
  ghout "Github-Authentication-Token-Expiration: $v"
  case_ "unparseable '$v' -> refused" 2 '^$' "$((EXP - 30*DAY))" -- "${A[@]}"
done

# Bad args.
ghout "$HDR"
case_ "no args refused" 2 '^$' "$EXP"
case_ "--state needs value" 2 '^$' "$EXP" -- --state
case_ "unknown arg refused" 2 '^$' "$EXP" -- --state "$S" --nope
case_ "missing state dir refused" 2 '^$' "$EXP" -- --state "$T/nodir/agent-token"
case_ "state is a directory refused" 2 '^$' "$EXP" -- --state "$T/s"
case_ "bad TOKEN_EXPIRY_NOW refused" 2 '^$' "abc" -- "${A[@]}"

# Rotation: a new, later expiry replaces the remembered one, and today's notification is forgotten.
printf '2026-12-09T17:00:00Z\n%s\n' "$D14" > "$S"
ghout 'Github-Authentication-Token-Expiration: 2027-12-09 17:00:00 UTC'
case_ "rotation -> ok" 0 '^ok 379 2027-12-09$' "$N14" -- "${A[@]}"
state_is "rotation replaces the expiry and clears the notified date" 2027-12-09T17:00:00Z
ghout 'Github-Authentication-Token-Expiration: 2026-12-20 17:00:00 UTC'
printf '2026-12-09T17:00:00Z\n%s\n' "$D14" > "$S"
case_ "rotation inside the window notifies again" 0 '^notify 13 2026-12-20$' "$((EXP + 1 - 3*DAY))" -- "${A[@]}"

# Nothing from the environment is printed.
total=$((total+1))
o=$(env GH_TOKEN=sekrit-token-value TOKEN_EXPIRY_NOW="$EXP" TOKEN_EXPIRY_GH_FAIL=1 bash "$EXPIRY" --state "$T/nodir/x" 2>&1; \
    env GH_TOKEN=sekrit-token-value TOKEN_EXPIRY_NOW="$EXP" TOKEN_EXPIRY_GH_OUT="$OUT" bash "$EXPIRY" --state "$S" 2>&1)
case $o in *sekrit*) fail=$((fail+1)); echo "FAIL the token leaked into output" ;; esac
# No temp files are left beside the state.
total=$((total+1))
if compgen -G "$T/s/.token-expiry.*" >/dev/null; then fail=$((fail+1)); echo "FAIL a temp file was left in the state dir"; fi

echo "$((total-fail))/$total passed"
[ "$fail" = 0 ]
