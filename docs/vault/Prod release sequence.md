---
tags: [sequence]
---
# Prod release sequence

Back to [[00 Home]]. Merging the **release PR** (`dev` into `main`) deploys prod with the build `dev` already ran, then tags the release. This stands in for the Jira Ops subtask + Production Authorization. The branching rules are in [[Branching and releases]].

```mermaid
sequenceDiagram
  autonumber
  actor A as Approver
  participant GH as GitHub Actions
  participant V as verify job
  participant STS as AWS STS
  participant PROD as prod env

  Note over GH: Earlier: PRs squash into dev → build dev-tip sha, apply dev
  A->>GH: Merge release PR dev → main (merge commit)
  GH->>V: release-sha.sh: main's tip is a merge from dev?
  V-->>GH: build = dev's tip (second parent)
  GH->>GH: Production authorization:<br/>ref is main, sha was released, merger in PROD_APPROVERS
  alt not authorized
    GH-->>A: fail, prod untouched
  else authorized
    GH->>STS: CI-prod role (main only) → AssumeRole deploy-prod
    GH->>PROD: tofu plan + apply same builds/sha
    GH->>PROD: smoke test: build == sha
    GH->>GH: next-version.sh → tag vX.Y.Z + GitHub release (build + PR list)
    PROD-->>A: prod running sha
  end
```

Rollback: **Roll back prod** on `main` with the `Build:` SHA from an older release. It deploys dev, then prod, and runs the same checks.

Related: [[Dev deploy sequence]], [[Review findings]].
