---
tags: [iam, security]
---
# IAM role chain

Back to [[00 Home]]. Same shape as work's "OIDC base role → provisioner role", see [[Work pattern]].

```mermaid
flowchart LR
  gh[GitHub OIDC token<br/>any branch] --> ci[project-ci<br/>base role]
  ghm[GitHub OIDC token<br/>main branch only] --> cip[project-ci-prod<br/>base role]
  ec2[Runner instance profile<br/>ec2 mode] --> rr[project-runner<br/>base role]
  ci -->|AssumeRole| dd[project-deploy-dev]
  rr -->|AssumeRole| dd
  cip -->|AssumeRole| dp[project-deploy-prod]
  rr -. never .-> dp
  dd -->|creates, with boundary| ad[project-dev-app role]
  dp -->|creates, with boundary| ap[project-prod-app role]
  ad --> ld[dev Lambda]
  ap --> lp[prod Lambda]
```

```mermaid
classDiagram
  class NonProdBase {
    +s3 Get/Put builds/*
    +ssm GetParameter /project/env/dev/config
    +sts AssumeRole deploy-dev
  }
  class ProdBase_mainOnly {
    +s3 Get builds/* and versions
    +ssm GetParameter /project/env/prod/config
    +sts AssumeRole deploy-prod
  }
  class DeployRole_env {
    +s3 RW app/env.tfstate + .tflock
    +s3 Get builds/*
    +lambda * on project-env-*
    +dynamodb * on project-env-*
    +logs * on /aws/lambda/project-env-*
    +iam CreateRole only with boundary
    +iam PassRole project-env-* to Lambda
    -deny public Lambda, trust edits, boundary edits
  }
  class AppBoundary_env {
    +logs to own log groups
    +dynamodb on project-env-* tables
    +ec2 ENI actions for VPC Lambda
  }
  class AppRole_env {
    +logs own group
    +dynamodb own table
  }
  NonProdBase --> DeployRole_env : assumes dev
  ProdBase_mainOnly --> DeployRole_env : assumes prod
  DeployRole_env --> AppRole_env : creates
  AppBoundary_env --> AppRole_env : caps
  AppBoundary_env --> DeployRole_env : caps
```

## What each role can't do
- The runner, and any workflow on a non-main branch, can't get prod credentials at all. AWS checks the OIDC subject claim.
- A dev deploy role can't read or write prod state, resources or roles: every ARN is scoped to `project-dev-*`.
- No pipeline-created role can exceed its boundary, and no deploy role can remove or edit a boundary.
- In the sandbox, every role also carries `yield-boundary` (see [[Sandbox guardrails]]).

Known limit: on GitHub Free anyone with write access can push to `main`. See [[Review findings]].
