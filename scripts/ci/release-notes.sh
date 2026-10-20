#!/usr/bin/env bash
# Print the notes for a release: the build it deployed, then one line per PR
# merged into dev since the last v* tag (each squash commit is one PR, and its
# subject is the PR title with its number). GitHub uses this as the release
# body, Bitbucket as the tag message, so both list the same changes.
# Usage: release-notes.sh [ref]   (default HEAD, a release merge on main)
set -euo pipefail
REF="${1:-HEAD}"

echo "Build: $(git rev-parse "$REF^2")"
echo
if LAST="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$REF" 2>/dev/null)"; then
  echo "## Changes since $LAST"
  git log --no-merges --format='- %s' "$LAST..$REF"
else
  echo "## Changes"
  git log --no-merges --format='- %s' "$REF"
fi
