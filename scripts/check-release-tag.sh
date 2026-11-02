#!/bin/sh
# check-release-tag.sh TAG: a release tag must be on origin/main and name this tree's version
# (Version in framework/internal/cmd/root.go, as v<Version>), so a tag on a side branch or a stale
# tree builds no draft. Run by .github/workflows/release.yml on a full clone.
set -eu
tag=${1:?usage: check-release-tag.sh <tag>}
root=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^var Version = "\(.*\)"$/\1/p' "$root/framework/internal/cmd/root.go")
[ -n "$version" ] || { echo "check-release-tag: no Version in framework/internal/cmd/root.go" >&2; exit 1; }
[ "$tag" = "v$version" ] || { echo "check-release-tag: tag $tag is not v$version" >&2; exit 1; }
git -C "$root" rev-parse -q --verify "refs/remotes/origin/main^{commit}" >/dev/null ||
  { echo "check-release-tag: no origin/main here (a full clone is needed)" >&2; exit 1; }
git -C "$root" merge-base --is-ancestor "refs/tags/$tag^{commit}" refs/remotes/origin/main ||
  { echo "check-release-tag: $tag is not on origin/main" >&2; exit 1; }
echo "check-release-tag: $tag is on origin/main and names this version"
