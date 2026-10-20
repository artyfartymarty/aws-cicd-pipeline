#!/usr/bin/env bash
# Print the next semantic version (vMAJOR.MINOR.PATCH) for a release, from the
# conventional-commit subjects merged since the last v* tag. Shared by GitHub
# (release.yml) and Bitbucket (bitbucket-pipelines.yml).
#   type!: ... or a "BREAKING CHANGE:" line -> major
#   feat: ...                               -> minor
#   anything else (fix:, chore:, ...)       -> patch
# Feature PRs are squash-merged into dev, so each commit is one PR and its
# subject is the PR title. Release merge commits into main are skipped.
# Usage: next-version.sh [ref]   (default HEAD)
set -euo pipefail
REF="${1:-HEAD}"

if LAST="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$REF" 2>/dev/null)"; then
  RANGE="$LAST..$REF"
else
  LAST="" RANGE="$REF" # no release yet
fi

BUMP=""
while IFS= read -r -d '' msg; do
  msg="${msg#$'\n'}" # git puts a newline between records
  subject="${msg%%$'\n'*}"
  if [[ "$subject" =~ ^[a-z]+(\([^\)]*\))?!: ]] || grep -q '^BREAKING[ -]CHANGE:' <<<"$msg"; then
    BUMP="major"
  elif [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
    [ "$BUMP" = major ] || BUMP="minor"
  else
    [ -n "$BUMP" ] || BUMP="patch"
  fi
done < <(git log --no-merges --format='%B%x00' "$RANGE")

if [ -z "$BUMP" ]; then
  echo "Nothing to release: no commits since ${LAST:-the start}." >&2; exit 1
fi
if [ -z "$LAST" ]; then
  echo v0.1.0; exit 0
fi

IFS=. read -r MAJOR MINOR PATCH <<<"${LAST#v}"
case "$BUMP" in
  major) echo "v$((MAJOR + 1)).0.0" ;;
  minor) echo "v$MAJOR.$((MINOR + 1)).0" ;;
  patch) echo "v$MAJOR.$MINOR.$((PATCH + 1))" ;;
esac
