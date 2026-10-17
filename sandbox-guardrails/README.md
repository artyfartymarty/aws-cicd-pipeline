# Yield sandbox guardrails

Proposed access for the Yield team's sandbox AWS account: broad ("lax") access
so the team can build freely, including their own VPCs and IAM roles, but
**no path to or from the internet** and no way to escalate past the guardrails.

These are drafts for IT to review. Replace `ACCOUNT_ID` with the sandbox
account ID before use.

| File | Who applies it | What it does |
|---|---|---|
| `scp-no-internet.json` | IT, as an Organizations **SCP** on the sandbox account | Hard limits the team cannot remove, even as admins |
| `yield-team-policy.json` | IT, on the team's SSO permission set or role | What the team can do day to day |
| `yield-boundary.json` | IT creates it once as the IAM policy `yield-boundary` | Ceiling on every role the team creates. It is self-propagating: a role with it can create more roles only if they carry it too, so pipelines can create app roles without ever escaping it |

## What the team CAN do

- Everything in compute, data, storage, serverless, monitoring, etc. (like AWS `PowerUserAccess`).
- Create their own VPCs, subnets, route tables, security groups and **VPC endpoints**
  (so private workloads can still reach S3, DynamoDB, SSM and other AWS services).
- Create IAM roles, policies and instance profiles named `yield-*`, as long as
  each role carries the `yield-boundary` permissions boundary.
- Create an OIDC provider so CI (GitHub Actions or Bitbucket) can deploy without stored keys.

## What the team CANNOT do

- Create or attach internet gateways, egress-only gateways, NAT gateways, or carrier gateways.
- Give anything a public IP (Elastic IPs, public IPs on launch, public-by-default subnets).
- Connect the VPCs to anything outside the account: VPN, peering, Transit Gateway, Client VPN.
- Run a Lambda outside a VPC (a non-VPC Lambda has internet access by default),
  or expose a Lambda URL without authentication.
- Create IAM users or access keys, touch Organizations, SSO or billing.
- Remove the boundary from a role, or edit the boundary itself, so a role they
  create can never be more powerful than the boundary.
- Turn off the account-level S3 Block Public Access.

## Before handing the account over (IT checklist)

1. **Delete the default VPC in every region.** New accounts come with one that
   already has an internet gateway, and the SCP only stops new ones being made.
2. Turn on S3 Block Public Access at the account level.
3. Create the `yield-boundary` policy, then attach the SCP and the team policy.
4. If IT's own admin role needs to be exempt from the SCP, add
   `"Condition": {"ArnNotLike": {"aws:PrincipalArn": "arn:aws:iam::*:role/<it-admin-role>"}}`
   to each Deny statement.

## Known gaps (worth a conversation with IT)

- **Inbound public endpoints** such as API Gateway, CloudFront and public
  AppSync APIs are reachable from the internet without a VPC. If those should be
  blocked too, add them to the SCP. Internet-facing load balancers already fail
  because there is no internet gateway.
- A few managed services can reach the internet from AWS's side (for example
  CodeBuild without a VPC, or Glue jobs). If the rule is strictly "no outbound
  internet from anything", list the services the team plans to use and IT can
  add a deny or VPC condition for each.
- `ec2:ModifySubnetAttribute` is fully denied, because it is how a subnet gets
  public IPs by default. Subnets created by OpenTofu with default settings work fine.

## Effect on the pipeline in this repo

With no internet gateway, a self-hosted runner inside the sandbox cannot reach
GitHub. In the sandbox, the pipeline therefore runs on GitHub-hosted (or
Bitbucket) runners and signs in to AWS with OIDC: a base role that can only
assume the `yield-deploy-<env>` roles, the same role chain as the work diagrams.
Lambdas are attached to the team's private VPC with free S3 and DynamoDB gateway endpoints.
