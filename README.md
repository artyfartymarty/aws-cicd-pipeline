# aws-cicd-pipeline

A personal, low-cost copy of the work pipeline (Bitbucket Pipelines + JFrog +
self-hosted runners in AWS, Dev on demand, PR into `main`, gated promotion of
the same build to Prod), rebuilt on GitHub Actions + one AWS account with
OpenTofu. It is laid out as a reusable pattern so the Yield team can run dev
and prod side by side in a single sandbox account.

## Two patterns: here and at work

| | Here (my account) | At work (Yield sandbox) |
|---|---|---|
| CI | GitHub Actions, `.github/workflows/` | Bitbucket Pipelines, `bitbucket-pipelines.yml` |
| `runner_mode` | `ec2` or `github-oidc` | `bitbucket-oidc` (`infra/platform/work.tfvars.example`) |
| Prod gate in IAM | OIDC `sub` must be `main` | OIDC `sub` must carry the prod deployment environment |

Both CI files call the same `scripts/ci/*.sh` and the same `infra/`, so only
sign-in and prod gating differ. The translation guide is
[`docs/vault/Local to work.md`](docs/vault/Local%20to%20work.md), and the work
pattern itself is [`docs/vault/Yield work pattern.md`](docs/vault/Yield%20work%20pattern.md).

## Two modes (GitHub)

| | `runner_mode = "ec2"` (default) | `runner_mode = "github-oidc"` |
|---|---|---|
| Where jobs run | One Spot EC2 runner in your account | GitHub-hosted runners |
| How CI gets AWS access | Runner instance role | GitHub OIDC role (no stored keys) |
| Internet gateway | Yes, for the runner only | None |
| Lambda | Outside a VPC, or in private subnets (`lambda_in_vpc`) | Private subnets, no internet route |
| Use it for | Mirroring the work setup in your personal account | The Yield sandbox (see `sandbox-guardrails/`), or the cheapest personal setup |
| Cost | ~$6.50/month 24/7, ~$1 if stopped when idle | ~$0.25/month |

A third mode, `bitbucket-oidc`, is the same as `github-oidc` with Bitbucket
as the OIDC issuer; it is the one to use at work.

All modes use the same role chain: base role -> `<project>-deploy-dev` /
`<project>-deploy-prod`. Settings for the sandbox are in
`infra/platform/sandbox.tfvars.example`.

## How it maps to work

| At work | Here |
|---|---|
| Bitbucket Pipelines, Dynamic Pipelines shared templates | GitHub Actions; `_build.yml` / `_deploy.yml` are reusable templates (`workflow_call`) |
| Autobahn golden patterns, 3 layers | Layer 1 `infra/modules/`, Layer 2 `.github/workflows/_*.yml`, Layer 3 `infra/app/` |
| EKS self-hosted runners in the Tools account | One `t4g.micro` Spot EC2 runner in its own VPC (EKS has a ~$73/month control-plane fee) |
| OIDC base role -> `provisioner-*` role chain | Runner instance role (base) -> `cicd-lab-deploy-dev` / `-qa` / `-prod` |
| JFrog / ECR artifact | S3 `builds/<git sha>/app.zip`, built once, never overwritten |
| Config Graph `infraConfig` / Compass per-env settings | SSM Parameter Store `/<project>/env/<env>/config` (outside the repo) |
| Harness IACM workspaces dev/test/prod | One state file per env: `app/dev.tfstate`, `app/qa.tfstate`, `app/prod.tfstate` |
| "Deploy to Dev" button, any branch | **Deploy to Dev** workflow, Run workflow on any branch |
| Jira Ops subtask + Production Authorization | Merging a **release PR** (`dev` into `main`) + `.github/PROD_APPROVERS` allow-list |
| `python-serverless` template | The sample app: a Python Lambda + DynamoDB table |

## Flow

```
feature branch --push--> CI (GitHub-hosted, free): pytest, tofu fmt/validate/test (mocked AWS)
      |                  PR rules: conventional PR title
      +--(optional, manual) Deploy to Dev
      |
      PR into dev, squash merge (1 approval, CI green)
      |
dev --merge--> Dev pipeline --> CI -> build sha -> plan+apply dev -> smoke test
      |
      release PR dev -> main, merge commit (only dev may go into main)
      |   opening/updating it --> QA --> same build -> plan+apply qa -> smoke test
      |
main --merge--> Release --> same build dev and QA ran -> authz check -> apply prod -> smoke test
                                                    -> tag vX.Y.Z + GitHub release listing every PR
```

The branching rules, versioning and what GitHub Free can't enforce are in
`docs/vault/Branching and releases.md`.

- **AWS** only hands out prod credentials to workflows running on `main`
  (OIDC subject `repo:<owner>/<repo>:ref:refs/heads/main`). A workflow edited on
  another branch is refused by IAM, not just by YAML. The self-hosted runner
  never holds prod credentials; prod jobs run on GitHub-hosted runners.
- On top of that, **Release** checks that `main`'s tip is a merge from `dev`,
  deploys the build `dev` already ran, and checks that the person who merged is
  in `.github/PROD_APPROVERS`.
- Deploys pin the **first** S3 version ever uploaded for a build, so a later
  upload to the same key can't change what reaches prod.
- Rollback = run **Roll back prod** on `main` with the `Build:` SHA from an
  older GitHub release.

> [!warning] GitHub Free limit
> On a free private repo there is no branch protection, so approvals, required
> CI and CODEOWNERS reviews are not enforced, and anyone with write access can
> push to `main`. Prod still refuses anything on `main` that isn't a merge from
> `dev`. Alone in your repo that's you. For a team, GitHub Pro/Team adds branch
> protection, which closes this. See `docs/vault/Branching and releases.md`.

## Separation of dev and prod in one account

```
runner role or cicd-lab-ci (any branch)   publish artifacts, read dev config
  -> cicd-lab-deploy-dev                  cicd-lab-dev-*  resources + app/dev.tfstate only
cicd-lab-ci-prod (main branch only)       read artifacts and prod config
  -> cicd-lab-deploy-prod                 cicd-lab-prod-* resources + app/prod.tfstate only
```

Each deploy role, and every role it creates, carries that env's permissions
boundary (`cicd-lab-<env>-app-boundary`). The boundary only covers that env's
resources and only lets roles create roles under the same boundary, so nothing
the dev pipeline makes can reach prod. Deploy roles also can't make a Lambda
public, edit trust policies, or weaken a boundary. The platform stack (runner,
VPC, IAM) is applied only by you (or IT), so no pipeline can change its own permissions.

## Repo layout

```
app/                         Python Lambda + unit tests
infra/modules/lambda-app/    Layer 1 module
infra/app/                   Layer 3 pattern, applied by the pipeline per env
infra/platform/              runner, VPC, IAM roles, artifact bucket (you apply this)
.github/workflows/           ci, _build, _deploy (templates), deploy-dev, pipeline, release
scripts/                     bootstrap-state, runner-power, teardown
sandbox-guardrails/          draft SCP, RCP, team policy and boundary for the Yield sandbox account
docs/vault/                  Obsidian vault: work vs mine, UML and charts
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
   (Skip this step in `github-oidc` mode: there is no runner.)
3. **Platform** (VPC, runner or OIDC role, IAM, artifact bucket)
   ```bash
   cp infra/platform/terraform.tfvars.example infra/platform/terraform.tfvars   # set github_repo
   make platform-plan              # read it
   make platform-apply
   ```
   In `ec2` mode the runner shows as *Idle* under repo Settings > Actions >
   Runners within a few minutes.
4. **GitHub variables + environments**
   ```bash
   make gh-vars                    # repo variables: region, buckets, the two OIDC role ARNs, RUNS_ON
   ```
5. **Branches:** create `dev` from `main` and make it the default branch
   (Settings > General), so new PRs target it. Leave "Automatically delete head
   branches" off, or merging a release PR could delete `dev`.
6. **First deploy:** merge a PR into `dev` (deploys dev). Then open a PR from
   `dev` into `main` and merge it with a merge commit (deploys prod and tags
   `v0.1.0`). Check it with `make invoke ENV=prod`.

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
- The default environments are `["dev", "qa", "prod"]`. Add one (say `test`) to
  `environments` in the platform stack and to the `env` validation in `infra/app/variables.tf`.
- IT applies `infra/platform` once (like the StackSet at work) with
  `sandbox.tfvars.example`, so the team can't edit the pipeline roles. Per-env
  settings land in SSM, which the workflows read.

## Next steps (not built yet, on purpose)

- Move `infra/modules/` and the `_*.yml` templates to their own repos, versioned
  by git tag (`rc` then stable), and pin them from the pattern (comments in
  `infra/app/main.tf` and `_deploy.yml` show the exact `source`/`uses` lines).
- Mark the pattern repo as a GitHub *template repository* to play the Autobahn
  scaffolder role ("Use this template" creates a new repo with the pipeline wired).
- GitHub Pro/Team: branch protection on `main`, CODEOWNERS on `.github/`, and a
  `prod` Environment with required reviewers (the OIDC trust then moves to
  `repo:<owner>/<repo>:environment:prod`).
- Interface VPC endpoints (SSM, Secrets Manager, etc.) for Lambdas that need
  them. They cost about $7/month each per AZ, so none are created by default.
