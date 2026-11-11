#!/usr/bin/env bash
# Report how long the current gh token has left, from the `github-authentication-token-expiration` response header.
# Usage: token-expiry.sh --state <file>
# Runs `gh api -i user` once (as whatever identity the caller's environment gives gh) and prints exactly one line,
# exit 0:
#   none                     the call worked and sent no expiry header (a token with no expiry)
#   ok <days> <YYYY-MM-DD>   more than 14 days left
#   notify <days> <YYYY-MM-DD>
#                            0..14 days left and not yet notified on today's UTC date (records today in the state)
#   warned <days> <YYYY-MM-DD>
#                            0..14 days left, already notified on today's UTC date
#   expired <YYYY-MM-DD>     the header's time is <= now; or the call failed and the remembered expiry is <= now
# <days> = floor((expiry - now) / 86400); <YYYY-MM-DD> is the expiry's UTC date.
# The header is matched case-insensitively (a trailing CR is stripped). Its value is "YYYY-MM-DD HH:MM:SS UTC" or
# "YYYY-MM-DD HH:MM:SS +HHMM" / "-HHMM" (converted to UTC); anything else is unparseable.
# Once a token expires the call fails (401) with no header, so the last seen expiry is remembered in the state file:
#   line 1  expiry, ISO UTC (2026-12-09T17:00:00Z), empty after a "none" read
#   line 2  last notified UTC date (YYYY-MM-DD), may be empty; kept only while line 1 is unchanged (a rotation resets it)
# It is rewritten atomically (temp file + mv in its directory) on every successful read. Its directory must exist.
# Nothing from the environment (the token included) is ever printed. Date math uses jq, so it runs on macOS and Linux.
# Test hooks: TOKEN_EXPIRY_GH_OUT names a file used in place of the call's output; TOKEN_EXPIRY_GH_FAIL=1 makes the
# call fail; TOKEN_EXPIRY_NOW is an epoch used in place of `date -u +%s`.
# Exit 2 = refused (message on stderr): bad args; the state's directory is missing; the call failed and no expired
# date is remembered (the identity check reports why); the header is present but unparseable.
set -euo pipefail
export LC_ALL=C

refuse() { echo "token-expiry.sh: refused: $*" >&2; exit 2; }

state=""
while [ $# -gt 0 ]; do
  case $1 in
    --state) [ $# -ge 2 ] || refuse "--state needs a value"; state=$2; shift 2 ;;
    *) refuse "unknown argument '$1' (usage: token-expiry.sh --state <file>)" ;;
  esac
done
[ -n "$state" ] || refuse "--state <file> is required"
state_dir=$(dirname "$state")
[ -d "$state_dir" ] || refuse "the state file's directory $state_dir does not exist"
[ ! -e "$state" ] || [ -f "$state" ] || refuse "the state path $state is not a regular file"

if [ -n "${TOKEN_EXPIRY_NOW:-}" ]; then
  [[ $TOKEN_EXPIRY_NOW =~ ^[0-9]+$ ]] || refuse "TOKEN_EXPIRY_NOW must be an epoch in seconds"
  now=$TOKEN_EXPIRY_NOW
else
  now=$(date -u +%s)
fi
today=$(jq -nr --argjson n "$now" '$n | todate | .[0:10]')

# iso_epoch ISO -> epoch on stdout, or fail if ISO is not a real YYYY-MM-DDTHH:MM:SSZ time (round-trip check).
iso_epoch() {
  [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  jq -nr --arg s "$1" '($s | fromdateiso8601) as $e | if ($e | todate) == $s then $e else error("bad") end' 2>/dev/null
}

# write_state EXPIRY_ISO NOTIFIED_DATE
write_state() {
  local tmp
  tmp=$(mktemp "$state_dir/.token-expiry.XXXXXX") || refuse "could not write a temp file in $state_dir"
  printf '%s\n%s\n' "$1" "$2" > "$tmp"
  mv -f "$tmp" "$state" || { rm -f "$tmp"; refuse "could not replace $state"; }
}

old_exp="" old_notified=""
if [ -f "$state" ]; then
  { IFS= read -r old_exp || true; IFS= read -r old_notified || true; } < "$state"
fi

# The call. Its output: header lines, a blank line, the JSON body.
ok_call=1 out=""
if [ "${TOKEN_EXPIRY_GH_FAIL:-}" = 1 ]; then
  ok_call=0
elif [ -n "${TOKEN_EXPIRY_GH_OUT:-}" ]; then
  out=$(cat "$TOKEN_EXPIRY_GH_OUT") || ok_call=0
else
  out=$(gh api -i user 2>/dev/null) || ok_call=0
fi

if [ "$ok_call" = 0 ]; then
  if old_epoch=$(iso_epoch "$old_exp") && [ "$old_epoch" -le "$now" ]; then
    echo "expired ${old_exp:0:10}"
    exit 0
  fi
  refuse "gh api user failed and no expired token date is remembered (check the identity: gh auth status)"
fi

value="" found=0
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  [ -n "$line" ] || break
  lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
  if [[ $lower =~ ^github-authentication-token-expiration:[[:space:]]*(.*)$ ]]; then
    found=1
    value=${line#*:}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    break
  fi
done <<< "$out"

if [ "$found" = 0 ]; then
  write_state "" ""
  echo none
  exit 0
fi

[[ $value =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}:[0-9]{2}:[0-9]{2})\ (UTC|[+-][0-9]{4})$ ]] \
  || refuse "unparseable token expiry header value"
base_iso="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}Z"
zone=${BASH_REMATCH[3]}
base=$(iso_epoch "$base_iso") || refuse "unparseable token expiry header value"
offset=0
if [ "$zone" != UTC ]; then
  hh=$((10#${zone:1:2})); mm=$((10#${zone:3:2}))
  [ "$hh" -le 23 ] && [ "$mm" -le 59 ] || refuse "unparseable token expiry header value"
  offset=$((hh * 3600 + mm * 60))
  [ "${zone:0:1}" = + ] || offset=$((-offset))
fi
exp=$((base - offset))
exp_iso=$(jq -nr --argjson e "$exp" '$e | todate')
exp_date=${exp_iso:0:10}

notified=""
[ "$exp_iso" != "$old_exp" ] || notified=$old_notified

if [ "$exp" -le "$now" ]; then
  write_state "$exp_iso" "$notified"
  echo "expired $exp_date"
  exit 0
fi
days=$(( (exp - now) / 86400 ))
if [ "$days" -gt 14 ]; then
  write_state "$exp_iso" "$notified"
  echo "ok $days $exp_date"
elif [ "$notified" = "$today" ]; then
  write_state "$exp_iso" "$notified"
  echo "warned $days $exp_date"
else
  write_state "$exp_iso" "$today"
  echo "notify $days $exp_date"
fi
