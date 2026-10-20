---
tags: [roadmap]
---
# Gaps and next steps

Back to [[00 Home]]. From [[Mapping]], most useful first.

1. **Decide the runner shape** for the sandbox ([[Runners]]): OIDC (built) or a tools-account runner (closest to work's EKS setup).
2. **Split the layers into repos**: `tofu-modules` (Layer 1, tagged `v1.x.x-rc` then `v1.x.x`) and `pipeline-templates` (Layer 2, tagged `v1`). Pin them from the pattern repo.
3. **Scaffolder**: mark the pattern repo as a GitHub template repository and add a `scripts/new-pattern.sh` that creates the repo, runs `make gh-vars`, and writes the env config. That's the Autobahn form.
4. **A `test` environment**: one entry in `environments` and the `env` validation.
5. **Quality gate**: SonarCloud is free only for public repos; for private, run `ruff` + `bandit` + `checkov`/`trivy config` in CI instead. All free.
6. **Enforce the branch rules**: GitHub Pro ($4/month) gives branch protection and code owners on private repos, so the rules in [[Branching and releases]] become real (approvals, required CI, no deleting `dev`), which also closes the gap in [[Review findings]].
7. **Containers**: an ECR + ECS Fargate variant to match the `ecs-*` templates. Fargate costs only while tasks run, but needs interface endpoints in a no-internet VPC (~$7 each per AZ).
8. **Runner monitoring**: CloudWatch agent on the runner, matching "monitored in CloudWatch".
