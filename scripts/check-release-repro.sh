#!/bin/sh
# check-release-repro.sh ENGINES.SHA256 [TARGET...]: rebuild this checkout's release with an empty
# build cache and compare its engines against a release's engines.sha256 (ADR-0018's release check).
# Check out the release's tag first. release.yml runs it on a second runner. Exit 0 only when every
# engine rebuilt matches; with TARGETs, only those are rebuilt, and each must be in the file.
set -eu
want=${1:?usage: check-release-repro.sh <engines.sha256> [os/arch ...]}
shift
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/release-repro.XXXXXX")
trap 'rm -rf "$out"' EXIT INT TERM
GOCACHE="$out/gocache" sh "$root/scripts/build-release.sh" --out "$out/dist" "$@" >/dev/null
[ -s "$out/dist/engines.sha256" ] || { echo "release-repro: the rebuild produced no engines" >&2; exit 1; }
sort "$out/dist/engines.sha256" > "$out/got"
sort "$want" > "$out/want"
if [ $# -gt 0 ]; then
  # A partial rebuild answers only for its own targets.
  comm -23 "$out/got" "$out/want" > "$out/miss"
  [ ! -s "$out/miss" ] || { echo "release-repro: does not reproduce:" >&2; cat "$out/miss" >&2; exit 1; }
else
  cmp -s "$out/got" "$out/want" || { echo "release-repro: does not reproduce" >&2; diff "$out/want" "$out/got" >&2 || true; exit 1; }
fi
echo "release-repro: $(wc -l < "$out/got" | tr -d ' ') engine(s) reproduce $want"
