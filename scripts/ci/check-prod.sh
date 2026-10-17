#!/usr/bin/env bash
# The "Production Authorization" check, shared by both CI systems. IAM already
# refuses prod outside main (GitHub) or outside the prod deployment environment
# (Bitbucket); this adds: run from main, the build was main's tip at some point,
# and the person who started it is on the approver list.
# Usage: check-prod.sh <current-branch> <build-sha> <who> <approvers-file>
set -euo pipefail
BRANCH="$1" SHA="$2" WHO="$3" APPROVERS="$4"

if [ "$BRANCH" != "main" ]; then
  echo "Prod deploys must run from main (this run is on $BRANCH)." >&2; exit 1
fi
if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "The build must be a full 40-character commit SHA." >&2; exit 1
fi
# First-parent only: the commit must have been main's HEAD at some point (a
# merge result), not a feature-branch commit merged into it.
git fetch --quiet origin main 2>/dev/null || true
if ! git rev-list --first-parent "${MAIN_REF:-origin/main}" | grep -qxF "$SHA"; then
  echo "$SHA was never the tip of main. Only builds of main can go to prod." >&2; exit 1
fi
if ! grep -v '^#' "$APPROVERS" | grep -qxF "$WHO"; then
  echo "$WHO is not in $APPROVERS, so cannot deploy to prod." >&2; exit 1
fi
echo "$WHO is authorized to deploy $SHA to prod."
