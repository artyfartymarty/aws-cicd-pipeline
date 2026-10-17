---
tags: [security, sandbox]
---
# Sandbox guardrails

Back to [[00 Home]]. Full drafts and the IT checklist are in `sandbox-guardrails/` at the repo root.

```mermaid
flowchart TB
  scp[SCP on the sandbox account<br/>IT owns, team cannot remove] --> acct((Sandbox account))
  team[Team permission set<br/>everything except IAM/org/billing admin<br/>+ IAM roles yield-* with boundary] --> acct
  bnd[yield-boundary<br/>self-propagating ceiling] --> roles[Every role the team or a pipeline creates]
  scp -. denies .-> x1[IGW, NAT, egress-only IGW]
  scp -. denies .-> x2[Elastic IPs, public IP on launch]
  scp -. denies .-> x3[VPN, peering, Transit Gateway]
  scp -. denies .-> x4[Lambda outside a VPC, public Lambda URLs]
  scp -. denies .-> x5[IAM users and access keys]
  scp -. denies .-> x6[3rd-party PrivateLink, RAM shares, Lattice, Cloud WAN]
  scp -. denies .-> x7[Billing, purchases, CloudTrail/Config tampering]
  rcp[RCP: only org principals<br/>can assume roles] --> acct
  it[IT applies infra/platform] --> pipe[Pipeline roles + per-env boundaries<br/>team cannot edit]
  pipe --> acct
```

Honest limits are in `sandbox-guardrails/README.md`. The main one: dev and prod share the account, so people (not pipelines) with team access can still change prod by hand. Brian accepted that on 2026-10-17 because sandbox prod is a rehearsal ([[Glossary]]).

**Who applies what (Brian, 2026-10-17):** IT applies `infra/platform`, not the team. That is what keeps the pipeline roles out of the team's reach.

The team can still build VPCs, subnets, security groups and VPC endpoints, and create IAM roles named `yield-*`.

Related: [[Network]], [[IAM role chain]], [[Review findings]].
