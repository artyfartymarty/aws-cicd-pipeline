---
tags: [glossary]
---
# Glossary

The words the vault uses for the pipeline, at home and at work. Back to [[00 Home]].

## Places

**Sandbox account**:
The single AWS account the Yield team gets, holding both dev and prod.
_Avoid_: work account, Yield account

**Sandbox prod**:
The prod environment inside the sandbox account. It is a rehearsal of the real promotion path, with no real users or data.
_Avoid_: production (on its own), live

**Platform**:
The shared, once-per-account layer: pipeline roles, OIDC provider, boundaries, buckets. IT applies it, never the team.
_Avoid_: bootstrap, base stack

## Promotion

**Build**:
One immutable `app.zip` for one commit SHA, stored once and never overwritten.
_Avoid_: artifact (on its own), package

**Release build**:
Promoting an existing build of `main` to prod by its SHA, without rebuilding.
_Avoid_: redeploy, hotfix

**Approver**:
A person listed in `PROD_APPROVERS` who may trigger a prod deploy.
_Avoid_: reviewer, admin

## Identity

**Pipeline role**:
An IAM role only a pipeline can assume, through OIDC. People never use it.
_Avoid_: service account, CI user

**Boundary**:
The permissions ceiling on a deploy role and every role it creates, one per environment.
_Avoid_: guardrail (that word is for the SCP and team policy)
