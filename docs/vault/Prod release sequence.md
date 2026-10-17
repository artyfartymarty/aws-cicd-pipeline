---
tags: [sequence]
---
# Prod release sequence

Back to [[00 Home]]. The merge to `main` deploys dev and **previews** prod. Prod only changes through **Release build**, the stand-in for the Jira Ops subtask + Production Authorization.

```mermaid
sequenceDiagram
  autonumber
  actor A as Approver
  participant GH as GitHub Actions
  participant V as verify job
  participant STS as AWS STS
  participant DEV as dev env
  participant PROD as prod env

  Note over GH: Earlier: merge to main → build sha, apply dev, plan-only prod
  A->>GH: Run "Release build" on main with build_sha
  GH->>V: sha is 40 hex chars and an ancestor of origin/main?
  V-->>GH: ok
  GH->>STS: CI role → AssumeRole deploy-dev
  GH->>DEV: tofu apply builds/sha + smoke test
  DEV-->>GH: healthy
  GH->>GH: Production authorization:<br/>ref is main and actor in PROD_APPROVERS
  alt not authorized
    GH-->>A: fail, prod untouched
  else authorized
    GH->>STS: CI-prod role (main only) → AssumeRole deploy-prod
    GH->>PROD: tofu plan + apply same builds/sha
    GH->>PROD: smoke test: build == sha
    PROD-->>A: prod running sha
  end
```

Rollback is the same run with an older SHA.

Related: [[Dev deploy sequence]], [[Review findings]].
