#!/usr/bin/env bash
# Print the build to release for a commit on main, and check main only took
# what the branching rules allow. A release PR (dev -> main, merge commit)
# makes main's tip a merge whose second parent is dev's tip. That dev commit
# was already built and deployed to dev, so prod gets the same build.
# Refuses a direct push to main and a merge from any branch other than dev.
# Shared by GitHub (release.yml) and Bitbucket (bitbucket-pipelines.yml).
# Usage: release-sha.sh [ref]   (default HEAD)
set -euo pipefail
REF="${1:-HEAD}"
DEV="${DEV_REF:-origin/dev}"

if ! SHA="$(git rev-parse --verify --quiet "$REF^2")"; then
  echo "$(git rev-parse --short "$REF") is not a merge commit. main only takes release PRs from dev, merged with a merge commit." >&2
  exit 1
fi
git fetch --quiet origin dev 2>/dev/null || true
if ! git merge-base --is-ancestor "$SHA" "$DEV"; then
  echo "$(git rev-parse --short "$SHA") is not from dev. Only dev may be merged into main." >&2
  exit 1
fi
echo "$SHA"
