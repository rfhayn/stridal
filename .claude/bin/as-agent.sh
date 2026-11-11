#!/usr/bin/env bash
# Run a command as the agent's GitHub identity, whose token lives in the macOS Keychain.
# Usage: .claude/bin/as-agent.sh <keychain-service> <cmd> [args...]
# Reads the token with `security find-generic-password -s <service> -w` and execs <cmd> with:
#   GH_TOKEN             the token (the environment only: never argv, never a file, never printed)
#   GH_CONFIG_DIR        ${XDG_CONFIG_HOME:-$HOME/.config}/gh-agent-<service> (mode 700), so the user's own gh
#                        login and hosts.yml are never read
#   GIT_CONFIG_COUNT=2 and GIT_CONFIG_KEY/VALUE_0..1: the github.com credential helpers are reset (an empty value
#                        clears the list, osxkeychain included) and replaced by `!gh auth git-credential`, so git
#                        pushes as the agent too
#   GIT_TERMINAL_PROMPT=0  git never falls back to asking for a password
# Any Keychain failure (no such item, locked, denied) or an empty token refuses with exit 2 and runs nothing, so
# the command can never fall through to the user's own credentials.
# Test hook: AS_AGENT_SECURITY names the binary used in place of `security`.
set -euo pipefail

refuse() { echo "as-agent.sh: refused: $*" >&2; exit 2; }

[ $# -ge 2 ] || refuse "usage: as-agent.sh <keychain-service> <cmd> [args...]"
service=$1
shift
[[ $service =~ ^[A-Za-z0-9._-]+$ ]] || refuse "the keychain service must match ^[A-Za-z0-9._-]+\$"

security_bin=${AS_AGENT_SECURITY:-security}
token=$("$security_bin" find-generic-password -s "$service" -w) \
  || refuse "could not read the token for keychain service $service (missing, locked or denied); nothing was run"
[ -n "$token" ] || refuse "the keychain item $service holds an empty token; nothing was run"

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/gh-agent-$service"
mkdir -p "$cfg" || refuse "could not create $cfg"
chmod 700 "$cfg" || refuse "could not set mode 700 on $cfg"

export GH_TOKEN="$token"
export GH_CONFIG_DIR="$cfg"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.https://github.com.helper
export GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1=credential.https://github.com.helper
export GIT_CONFIG_VALUE_1='!gh auth git-credential'
export GIT_TERMINAL_PROMPT=0
unset token
exec "$@"
