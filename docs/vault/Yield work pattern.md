---
tags: [pattern, work, bitbucket]
---
# Yield work pattern (Bitbucket)

The pattern to use **at work**, in the Yield sandbox account: Bitbucket Pipelines, no GitHub anywhere. It is the same pipeline as [[My pattern]] with a Bitbucket front end. How the two line up, piece by piece, is in [[Local to work]]. Back to [[00 Home]].

## What runs

| Trigger | Steps | File |
|---|---|---|
| Push to any branch except `main` | test | `bitbucket-pipelines.yml` → `default` |
| **Run pipeline → deploy-to-dev** (any branch) | test → build → dev | `custom: deploy-to-dev` |
| Merge to `main` | test → build → dev → **manual** prod | `branches: main` |
| **Run pipeline → release-build** on `main`, with `BUILD_SHA` | dev → **manual** prod | `custom: release-build` (stands in for the Jira Ops subtask) |

Every AWS step has `oidc: true` and runs the shared scripts in `scripts/ci/`, the same ones GitHub runs. `infra/` is unchanged.

```mermaid
flowchart LR
  dev[Developer] -->|push branch| t[test]
  dev -->|Run pipeline: deploy-to-dev| t2[test] --> b[build<br/>builds/sha/app.zip] --> d[Deploy dev<br/>deployment: dev]
  dev -->|merge PR| m[main pipeline] --> t3[test] --> b2[build] --> d2[Deploy dev] --> p{{Deploy prod<br/>deployment: prod<br/>trigger: manual}}
  rel[Run pipeline: release-build<br/>BUILD_SHA] --> d3[Deploy dev] --> p2{{Deploy prod}}
  p --> chk[check-prod.sh<br/>main, first-parent, approver UUID]
  p2 --> chk
```

## How prod is protected

```mermaid
sequenceDiagram
  autonumber
  participant BB as Bitbucket step<br/>(deployment: prod)
  participant STS as AWS STS
  participant CP as yield-ci-prod
  participant DP as yield-deploy-prod
  BB->>BB: check-prod.sh: branch is main, SHA was main's tip, triggerer UUID in .bitbucket/PROD_APPROVERS
  BB->>STS: AssumeRoleWithWebIdentity(OIDC token)
  Note over STS,CP: trust: aud = workspace audience<br/>sub LIKE {repo-uuid}:{prod-env-uuid}:*
  STS-->>BB: yield-ci-prod credentials
  BB->>DP: sts:AssumeRole (deploy.sh)
  DP-->>BB: prod deploy credentials, capped by yield-prod boundary
  BB->>BB: SSM config, pin first upload, tofu init/plan/apply, smoke test
```

- **AWS side.** `yield-ci-prod` trusts only OIDC tokens whose `sub` carries the **prod deployment environment UUID** of this repo. Steps without `deployment: prod` can't get it. Nothing else (the non-prod role, a dev step) can assume `yield-deploy-prod`.
- **Bitbucket side.** AWS can only match `aud` and `sub` for this issuer, and Bitbucket's `sub` has no branch in it. So *which branch may use the prod environment* must be set in Bitbucket: Repository settings → Deployments → prod → **only `main`, only admins**. Those deployment permissions are a **Bitbucket Premium** feature.
- **Script side.** `check-prod.sh` refuses non-`main` runs, SHAs that were never `main`'s tip, and anyone not in `.bitbucket/PROD_APPROVERS`. A branch can edit that script, so it is a speed bump; the two gates above are the real ones.

> [!warning] Check with DevOps
> If the work workspace is not on Premium, or prod deployment permissions aren't set, then anyone who can push a branch can add `deployment: prod` to the YAML and get prod credentials. Ask whether the workspace has deployment permissions, or whether prod must go through Autobahn's Production Authorization instead.

## Setting it up in the sandbox

1. **IT (or you, if allowed) applies `infra/platform`** with `work.tfvars.example` copied to `terraform.tfvars`. The values come from Bitbucket → Repository settings → Pipelines → **OpenID Connect**: identity provider URL, audience, repository UUID, and the dev / prod deployment environment UUIDs.
2. **Bitbucket → Deployments:** environments `dev` (Test) and `prod` (Production). On `prod`, restrict to `main` and admins.
3. **Bitbucket → Repository variables:** paste what `make bb-vars` prints (`AWS_REGION`, `PROJECT`, `TF_STATE_BUCKET`, `ARTIFACT_BUCKET`, `AWS_CI_ROLE_ARN`, `AWS_CI_PROD_ROLE_ARN`). None are secrets.
4. **`.bitbucket/PROD_APPROVERS`:** the Bitbucket user UUIDs allowed to release.
5. Run **deploy-to-dev** on a branch. Then merge, and press **Deploy prod** on the main pipeline.

The sandbox [[Sandbox guardrails]] already allow the Bitbucket OIDC issuer (`api.bitbucket.org/*`) and block internet gateways, so this mode creates none. Bitbucket's own runners are outside the account and reach AWS APIs over the internet, like GitHub's do in [[Runners|GitHub OIDC mode]].

## Differences from the GitHub version

- No prod *preview* plan in the main pipeline: a Bitbucket deployment environment can be used once per pipeline, so the manual prod step plans and applies in one go. The plan is printed in its log before apply.
- No step summary page; plans and smoke-test results are in the step logs.
- Prod identity is a user **UUID**, not a login name.
- Bitbucket serialises deploys to one environment by itself; GitHub needs a `concurrency:` group.
