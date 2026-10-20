#!/usr/bin/env bash
# The "Production Authorization" check, shared by both CI systems. IAM already
# refuses prod outside main (GitHub) or outside the prod deployment environment
# (Bitbucket); this adds: run from main, the build is one a release PR brought
# into main, and the person who started it is on the approver list.
# Usage: check-prod.sh <current-branch> <build-sha> <who> <approvers-file>
set -euo pipefail
BRANCH="$1" SHA="$2" WHO="$3" APPROVERS="$4"

if [ "$BRANCH" != "main" ]; then
  echo "Prod deploys must run from main (this run is on $BRANCH)." >&2; exit 1
fi
if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "The build must be a full 40-character commit SHA." >&2; exit 1
fi
# Released builds are dev's tip at each release merge: the second parent of a
# merge commit on main's first-parent history. Anything else in dev's history
# (a commit later squashed over by another PR) was never released as a whole.
# main's own first-parent commits are also accepted, for builds made before
# the dev branch existed.
git fetch --quiet origin main 2>/dev/null || true
MAIN="${MAIN_REF:-origin/main}"
if ! { git rev-list --first-parent "$MAIN"
       git log --first-parent --merges --format='%P' "$MAIN" | cut -d' ' -f2; } | grep -qxF "$SHA"; then
  echo "$SHA was never released to main. Only dev builds that a release PR merged can go to prod." >&2; exit 1
fi
if ! grep -v '^#' "$APPROVERS" | grep -qxF "$WHO"; then
  echo "$WHO is not in $APPROVERS, so cannot deploy to prod." >&2; exit 1
fi
echo "$WHO is authorized to deploy $SHA to prod."
