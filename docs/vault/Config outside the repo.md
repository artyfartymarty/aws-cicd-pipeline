---
tags: [config]
---
# Config outside the repo

Back to [[00 Home]]. Work keeps per-env settings in Config Graph `infraConfig`, Compass and SSM (see [[Work pattern]]). Here they live in **SSM Parameter Store**, one JSON parameter per env, written by the platform stack:

```
/cicd-lab/env/dev/config
{
  "deploy_role_arn": "arn:aws:iam::<acct>:role/cicd-lab-deploy-dev",
  "app_boundary_arn": "arn:aws:iam::<acct>:policy/cicd-lab-dev-app-boundary",
  "lambda_subnet_ids": [],
  "lambda_security_group_ids": []
}
```

The deploy template reads it with the base role before assuming the deploy role. Standard parameters are free.

Why not GitHub Environment variables: on GitHub Free, environment variables, environment secrets, required reviewers and branch rules only work in **public** repos ([GitHub docs](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)). This repo should be private because of the runner.

Repo-level GitHub variables hold only what's needed to sign in: region, project, bucket names, the base role ARNs and `RUNS_ON`.
