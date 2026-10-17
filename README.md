# aws-cicd-pipeline

A personal, low-cost copy of the work pipeline (Bitbucket Pipelines + JFrog +
self-hosted runners in AWS, Dev on demand, PR into `main`, gated promotion of
the same build to Prod), rebuilt on GitHub Actions + one AWS account with
OpenTofu. It is laid out as a reusable pattern so the Yield team can run dev
and prod side by side in a single sandbox account.

## How it maps to work

| At work | Here |
|---|---|
| Bitbucket Pipelines, Dynamic Pipelines shared templates | GitHub Actions; `_build.yml` / `_deploy.yml` are reusable templates (`workflow_call`) |
| Autobahn golden patterns, 3 layers | Layer 1 `infra/modules/`, Layer 2 `.github/workflows/_*.yml`, Layer 3 `infra/app/` |
| EKS self-hosted runners in the Tools account | One `t4g.micro` Spot EC2 runner in its own VPC (EKS has a ~$73/month control-plane fee) |
| OIDC base role -> `provisioner-*` role chain | Runner instance role (base) -> `cicd-lab-deploy-dev` / `cicd-lab-deploy-prod` |
| JFrog / ECR artifact | S3 `builds/<git sha>/app.zip`, built once, never overwritten |
| Config Graph `infraConfig` / Compass per-env settings | GitHub Environment variables on `dev` and `prod` (outside the repo) |
| Harness IACM workspaces dev/test/prod | One state file per env: `app/dev.tfstate`, `app/prod.tfstate` |
| "Deploy to Dev" button, any branch | **Deploy to Dev** workflow, Run workflow on any branch |
| Jira Ops subtask + Production Authorization | **Release build** workflow from `main` + `.github/PROD_APPROVERS` allow-list |
| `python-serverless` template | The sample app: a Python Lambda + DynamoDB table |

## Flow

```
feature branch --push--> CI (GitHub-hosted, free): pytest, tofu fmt/validate/test (mocked AWS)
      |
      +--(manual) Deploy to Dev --> CI -> build sha -> plan+apply dev -> smoke test
      |
      PR into main (CI must pass)
      |
main --merge--> Main pipeline --> CI -> build sha -> apply dev -> PLAN-ONLY preview of prod
                                                                    |
            (manual APPROVE) Release build(sha) --> apply dev -> authz check -> apply prod -> smoke test
```

- Prod only runs from `main`, only for SHAs that are on `main`, only after dev
  succeeded in the same run, and only for people in `.github/PROD_APPROVERS`.
  A repo admin who isn't listed is blocked, same as at work.
- The prod artifact is byte-for-byte the one dev tested (same S3 object).
- Rollback = run **Release build** with an older SHA.

## Separation of dev and prod in one account

```
runner instance role         register runner, publish artifacts, sts:AssumeRole only
  -> cicd-lab-deploy-dev      cicd-lab-dev-*  resources + app/dev.tfstate only
  -> cicd-lab-deploy-prod     cicd-lab-prod-* resources + app/prod.tfstate only
```

Every role the pipeline creates must carry that env's permissions boundary
(`cicd-lab-<env>-app-boundary`), so a dev run cannot create anything that
reaches prod. The platform stack (runner, VPC, IAM) is applied only by you,
from your laptop; the runner cannot change its own permissions.

## Repo layout

```
app/                         Python Lambda + unit tests
infra/modules/lambda-app/    Layer 1 module
infra/app/                   Layer 3 pattern, applied by the pipeline per env
infra/platform/              runner, VPC, IAM roles, artifact bucket (you apply this)
.github/workflows/           ci, _build, _deploy (templates), deploy-dev, pipeline, release
scripts/                     bootstrap-state, runner-power, teardown
```

## Test locally first (free)

Needs Python 3.12+, OpenTofu 1.10+ (`brew install opentofu`), `make`.

```bash
pip install -r app/requirements-dev.txt
make test        # pytest + tofu fmt/validate + `tofu test` with a mocked AWS provider
make lock        # once: write provider lock files for mac + Linux + arm64, then commit them
```

`tofu test` never calls AWS. It checks things like: the Lambda deploys the
exact build artifact, the app role carries the boundary, prod's table has
deletion protection, the runner has no inbound rules and uses IMDSv2.

## One-time setup (about 15 minutes)

You need: the AWS CLI logged in as an admin of your account, `gh` CLI logged in,
and an empty **private** GitHub repo with this code pushed to it.

1. **State bucket**
   ```bash
   make bootstrap-state            # creates cicd-lab-tfstate-<account id>
   ```
2. **GitHub token for the runner.** GitHub > Settings > Developer settings >
   Fine-grained tokens > New: only this repo, permission
   *Administration: Read and write*. Then:
   ```bash
   make pat                        # stores it in SSM as a SecureString
   ```
3. **Platform** (VPC, runner, IAM, artifact bucket)
   ```bash
   cp infra/platform/terraform.tfvars.example infra/platform/terraform.tfvars   # set github_repo
   make platform-plan              # read it
   make platform-apply
   ```
   Within a few minutes the runner shows as *Idle* under repo Settings >
   Actions > Runners.
4. **GitHub variables + environments**
   ```bash
   make gh-vars                    # repo vars + dev/prod Environments with their DEPLOY_ROLE_ARN
   ```
5. **First deploy:** push to `main` (or Actions > Deploy to Dev). Then
   Actions > Release build > Run workflow on `main` with that commit's SHA.
   Check it with `make invoke ENV=prod`.

## Day to day

```bash
make runner-start     # before you push
make runner-stop      # when you're done for the day
make runner-shell     # shell on the runner via SSM (no SSH, no open ports)
```

If the runner is stopped, jobs that need it wait in the queue until you start it.

## Cost (us-east-1, rough)

| Item | Runner on 24/7 | Runner on ~20 h/month |
|---|---|---|
| EC2 t4g.micro Spot | ~$2 | ~$0.05 |
| Public IPv4 (only while running) | $3.65 | ~$0.10 |
| 8 GB gp3 disk | $0.64 | $0.64 |
| S3, Lambda, DynamoDB on-demand, logs (7-day retention) | < $0.25 | < $0.25 |
| **Total** | **~$6.50/month** | **~$1/month** |

On-demand instead of Spot (`use_spot = false`) adds about $4/month at 24/7.
There is no NAT gateway (~$33/month), no EKS (~$73/month), no load balancer.
GitHub-hosted CI uses the free private-repo minutes (a CI run takes 1 to 2
minutes). Spot prices move; these are estimates, not quotes. Set an AWS Budget
alert at $10 to be safe:

```bash
aws budgets create-budget --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget '{"BudgetName":"cicd-lab","BudgetLimit":{"Amount":"10","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"you@example.com"}]}]'
```

## Teardown

```bash
make teardown     # destroys prod, dev, platform, the SSM token and the state bucket (asks first)
```

Then remove the offline runner under repo Settings > Actions > Runners and
revoke the fine-grained token.

## Porting to the Yield team sandbox account

Nothing hard-codes an account ID. To stand it up in the sandbox:

- Point the AWS CLI at the sandbox (`export AWS_PROFILE=yield-sandbox`).
- Pick a prefix and region: `make ... PROJECT=yield AWS_REGION=us-east-1`
  (and `project = "yield"` in `terraform.tfvars`). All names, roles and scopes follow it.
- Add environments by setting `environments = ["dev", "test", "prod"]` in the
  platform stack and adding `test` to the `env` validation in `infra/app/variables.tf`.
- If IT pre-creates the roles (like the StackSet at work), drop `iam.tf` from
  the platform stack and set `DEPLOY_ROLE_ARN` per environment to their ARNs.

## Next steps (not built yet, on purpose)

- Move `infra/modules/` and the `_*.yml` templates to their own repos, versioned
  by git tag (`rc` then stable), and pin them from the pattern (comments in
  `infra/app/main.tf` and `_deploy.yml` show the exact `source`/`uses` lines).
- Mark the pattern repo as a GitHub *template repository* to play the Autobahn
  scaffolder role ("Use this template" creates a new repo with the pipeline wired).
- Required reviewers on the `prod` Environment, if the repo is on a paid plan.
- Swap the runner to GitHub-hosted + GitHub OIDC for the base role, if you'd
  rather not run any EC2 at all.
