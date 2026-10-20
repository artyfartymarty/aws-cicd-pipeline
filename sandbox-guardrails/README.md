# Yield sandbox guardrails

Proposed access for the Yield team's sandbox AWS account. The team gets broad ("lax")
access to build things, including their own VPCs and IAM roles. The account gets
**no network path to the internet**, and nobody in it can weaken these rules.

These are drafts for IT to review. Replace `ACCOUNT_ID` and `ORG_ID` before use.
Diagrams are in `docs/vault/Sandbox guardrails.md`.

| File | Applied by | Purpose |
|---|---|---|
| `scp-no-internet.json` | IT, as an Organizations **SCP** on the account | Hard limits nobody in the account can remove |
| `rcp-no-outside-principals.json` | IT, as an Organizations **RCP** | Only principals in the org (and AWS services) can assume roles here |
| `yield-team-policy.json` | IT, on the team's SSO permission set | Day-to-day access |
| `yield-boundary.json` | IT creates it once as policy `yield-boundary` | Ceiling on every role the team creates; self-propagating |
| `infra/platform` (repo root) | IT applies it once, like the StackSet at work | Pipeline roles, OIDC provider, per-env deploy roles and boundaries |

## What the team can do
- Everything in compute, data, storage, serverless and monitoring (like `PowerUserAccess`).
- Create VPCs, subnets, route tables, security groups, and **AWS-owned** VPC endpoints,
  so private workloads can still reach S3, DynamoDB, SSM and other AWS services.
- Create IAM roles, policies and instance profiles named `yield-*`, as long as each role
  carries `yield-boundary`. Roles under the boundary can do the same, and nothing more.
- Create the GitHub or Bitbucket OIDC provider (only those two issuers).

## What nobody in the account can do (SCP)
- Internet gateways, egress-only gateways, NAT, carrier gateways, the default VPC.
- Elastic IPs or instances launched with a public IP.
- VPN, Direct Connect, peering, Transit Gateway, Cloud WAN, VPC Lattice, accepting RAM
  shares (a shared subnet from another account could have internet). One exception: IT's
  network role may attach the VPC to work's Transit Gateway or Cloud WAN (step 6 below).
- VPC endpoints to non-AWS PrivateLink services, or offering endpoint services.
- Lambdas outside a VPC, and public Lambda URLs.
- Managed services that call out to the internet: EventBridge API destinations,
  Step Functions HTTP tasks, SNS HTTP/email/SMS subscriptions, App Runner, CloudShell,
  SageMaker notebooks with direct internet.
- IAM users and access keys, Organizations and account settings, billing changes,
  reserved/savings purchases, domain registration, Marketplace.
- Stopping or deleting CloudTrail, Config, GuardDuty or Security Hub.
- Turning off account-level S3 Block Public Access.

## What the team can't touch
- The pipeline roles (`yield-deploy-*`, `yield-ci*`, `yield-runner`) and every `yield-*boundary`
  policy. IT creates them through `infra/platform`, so the dev pipeline can never be
  edited into a prod pipeline.

## IT checklist before handover
1. **Delete the default VPC in every region.** New accounts come with one that already has an internet gateway.
2. Turn on S3 Block Public Access at the account level.
3. Create `yield-boundary`, then attach the SCP, the RCP and the team policy.
4. Apply `infra/platform` with `infra/platform/sandbox.tfvars.example`.
5. If IT's own admin role must be exempt from the SCP, add
   `"ArnNotLike": {"aws:PrincipalArn": "arn:aws:iam::*:role/<it-admin-role>"}` to each Deny's condition.
6. **Only if the sandbox joins work's network:** replace `<it-network-role>` in the SCP's
   `OnlyItConnectsToWorkNetwork` statement with the role IT applies `infra/platform` with.
   That role alone may accept the Transit Gateway or Cloud WAN resource share and create
   the attachment. Then set `private_network` in `terraform.tfvars`.
7. Test one Lambda env-var update after applying: the `lambda:VpcIds` condition on
   `UpdateFunctionConfiguration` is AWS's documented pattern, but confirm it.

## Honest limits
- **Dev and prod share one account, so people with team access can change prod by hand.**
  The separation stops *pipelines*: the dev pipeline cannot read, write or create
  anything in prod. If people must be kept out of prod too, prod needs its own account.
- **Inbound** public endpoints (API Gateway, CloudFront, public AppSync) still work without
  a VPC. Block them in the SCP if they shouldn't exist.
- Some services still reach the internet from AWS's side, for example CodeBuild without
  a VPC, Glue, SES, or SageMaker training jobs without network isolation. Before the team
  uses one, add a deny or a VPC condition for it.
- S3 and DynamoDB gateway endpoints without an endpoint policy can reach any account's
  buckets in the region. Add endpoint policies with `aws:ResourceAccount` if exfiltration matters.
- **If the sandbox joins work's network**, the team can still edit its own route tables and
  could point `0.0.0.0/0` at the attachment. The SCP has no condition key for a route's
  destination, so the real guard is the network side: the sandbox's route domain (Cloud WAN
  segment) must have no path to internet egress. Confirm that with Enterprise Networks.
- DNS queries still leave through the VPC resolver. Route 53 Resolver DNS Firewall closes that.
- `ec2:VpceServiceOwner` and `sns:Protocol` are the condition keys I expect to work. Run
  them through IAM Access Analyzer's policy validation before applying.
