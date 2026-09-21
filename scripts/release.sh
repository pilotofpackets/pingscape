#!/bin/sh
# Tags a release: scripts/release.sh 0.2.0
#
# Sets MARKETING_VERSION in project.yml (and commits that, if it changed), then
# creates the annotated tag v<version>. Nothing is pushed.
set -eu

cd "$(dirname "$0")/.."

version="${1:-}"
if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "usage: scripts/release.sh MAJOR.MINOR.PATCH   (for example 0.2.0)" >&2
    exit 1
fi
tag="v$version"

if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
    echo "error: releases are tagged on main" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "error: the working tree has uncommitted changes, commit or stash them first" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "error: tag $tag already exists" >&2
    exit 1
fi
latest=$(git tag --list 'v[0-9]*' | sort -V | tail -n 1)
if [ -n "$latest" ] && [ "$(printf '%s\n%s\n' "${latest#v}" "$version" | sort -V | tail -n 1)" != "$version" ]; then
    echo "error: $version is lower than the latest release ${latest#v}" >&2
    exit 1
fi

current=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
if [ "$current" != "$version" ]; then
    sed -E "s/^( *MARKETING_VERSION: ).*/\1\"$version\"/" project.yml > project.yml.tmp
    mv project.yml.tmp project.yml
    git commit -q -m "Release $version" project.yml
fi

build=$(git rev-list --count HEAD)
git tag -a "$tag" -m "Pingscape $version (build $build)"

echo "Tagged $tag at build $build. To publish it:"
echo "  git push origin main $tag"
