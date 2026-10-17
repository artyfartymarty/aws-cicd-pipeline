---
tags: [review, security]
---
# Review findings

Back to [[00 Home]]. An adversarial review of the code and policies, and what changed. "Fixed" means the code changed and the local tests cover it where they can. Nothing has run against real AWS yet.

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | Critical | Any branch could reach prod. The prod gate was only YAML, and the runner or the OIDC role could assume the prod deploy role | **Fixed.** Prod needs `<project>-ci-prod`, which AWS only trusts for `refs/heads/main`. The runner and `<project>-ci` can't assume prod. A `tofu test` fails if prod's trust changes (mutation-checked) |
| 2 | Critical | In sandbox mode, dev and prod app roles shared `yield-boundary`, so a dev role could be written to reach prod | **Fixed.** Every env has its own self-propagating boundary on the deploy role and its app roles. IT applies the platform, so the team can't edit pipeline roles |
| 3 | High | Anyone with the build role could overwrite `builds/<sha>/app.zip` before a release | **Fixed.** Deploys pin the first S3 version ever uploaded. Release only accepts SHAs that were once the tip of `main` (first-parent) |
| 4 | High | The runner boot script logged the GitHub token, and jobs ran with passwordless sudo | **Fixed.** No tracing around secrets, log is `600`, jobs run as a no-sudo `runner` user, and the runner version is pinned. The runner also no longer gets prod credentials (see 1) |
| 5 | High | VPC subnet variable names didn't match, so the Lambda deployed outside the VPC | **Fixed.** Per-env settings moved to SSM (see 13) |
| 6 | High | `tofu init` likely failed because the S3 backend lists `env:/` | **Fixed.** Prefix allowed. Verify on the first real run |
| 7 | High | The SCP left ways out (third-party PrivateLink, RAM shares, Lattice, Cloud WAN, HTTP-calling services) | **Mostly fixed.** Denied, and the remaining limits are listed in [[Sandbox guardrails]] |
| 8 | Medium | Team policy allowed billing, purchases and CloudTrail tampering | **Fixed** in the SCP |
| 9 | Medium | Team could add any OIDC issuer or rewrite trust on pipeline roles | **Fixed.** Issuers limited to GitHub/Bitbucket, pipeline roles protected, plus an RCP limiting role assumption to the org |
| 10 | Medium | `lambda:*` let a pipeline make a function public | **Fixed.** Deploy roles deny `AddPermission` and function URLs |
| 11 | Medium | `yield-boundary` lacked CreatePolicy, instance profiles, service-linked roles | **Fixed** |
| 12 | Medium | The prod preview on merge failed for non-approvers | **Fixed.** Approver check only runs for a real apply. The preview still uses prod deploy credentials (read-only plan role not built) |
| 13 | Medium | GitHub Free private repos have no Environment variables, branch rules or reviewers | **Fixed** by moving config to SSM (see [[Config outside the repo]]). Branch protection still needs Pro, see below |
| 14 | Low | Teardown could use the wrong project name | **Fixed.** Teardown stops if `PROJECT` differs from `terraform.tfvars` |
| 15 | Low | `BuildSha` tag retagged every resource each deploy | **Fixed.** Only the Lambda is tagged |
| 16 | Low | A Spot interruption mid-apply leaves a stale lock | **Known.** Run `tofu force-unlock` |
| 17 | Low | A third queued deploy to the same env cancels the pending one | **Known.** GitHub keeps one pending run per concurrency group |
| 18 | Low | `lambda:VpcIds` on updates is unverified | **Known.** On the IT checklist |

## Still open, and why
- **On GitHub Free, anyone with write access can push to `main`, so they can reach prod.** Alone in the repo, that's only you. For a team, GitHub Pro/Team (branch protection, CODEOWNERS on `.github/`, required reviewers) closes it.
- **Bitbucket prod depends on Premium.** Working assumption (2026-10-17): work's workspace has Premium, so deployment permissions limit prod to `main` and admins. Not confirmed. If it turns out to be wrong, `check-prod.sh` in the prod step still blocks non-`main` runs and anyone not in `.bitbucket/PROD_APPROVERS`, but someone who edits `bitbucket-pipelines.yml` on a branch can remove that check.
- **People with team access can still change prod by hand** in the shared sandbox account. The separation stops pipelines, not people. A separate prod account is the real fix.

Related: [[IAM role chain]], [[Prod release sequence]], [[Sandbox guardrails]].
