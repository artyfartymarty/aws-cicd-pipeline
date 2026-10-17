---
tags: [network]
---
# Network

Back to [[00 Home]].

```mermaid
flowchart TB
  internet((Internet))
  subgraph VPC[VPC 10.20.0.0/16]
    subgraph PUB[Runner subnet 10.20.1.0/24 - ec2 mode only]
      runner[Spot runner<br/>SG: no inbound, 443 out]
    end
    subgraph PRIV[Private subnets 10.20.10-11.0/24 - no internet route]
      lam[VPC Lambdas<br/>SG: no inbound, 443 out]
    end
    s3e[S3 gateway endpoint - free]
    ddbe[DynamoDB gateway endpoint - free]
  end
  igw[Internet gateway<br/>ec2 mode only]
  runner --> igw --> internet
  runner --> s3e
  lam --> s3e
  lam --> ddbe
```

- No NAT gateway (about $33/month) and no interface endpoints (about $7/month each per AZ).
- In `github-oidc` mode, only the private side exists. That is what the [[Sandbox guardrails]] require.
- At work, egress goes through Transit Gateway and Palo Alto firewalls instead (see [[Runners]]).
