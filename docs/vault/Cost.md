---
tags: [cost]
---
# Cost

Back to [[00 Home]]. Rough us-east-1 numbers. Spot prices move, so treat these as estimates.

```mermaid
pie showData
  title ec2 mode, runner on 24/7 (~$6.50/month)
  "Public IPv4" : 3.65
  "EC2 t4g.micro Spot" : 2.00
  "8 GB gp3 disk" : 0.64
  "S3, Lambda, DynamoDB, logs" : 0.25
```

```mermaid
pie showData
  title ec2 mode, runner stopped when idle (~$1/month)
  "8 GB gp3 disk" : 0.64
  "S3, Lambda, DynamoDB, logs" : 0.25
  "Runner ~20 h" : 0.15
```

| Mode | Monthly |
|---|---|
| `ec2`, runner always on | ~$6.50 |
| `ec2`, runner stopped when idle | ~$1 |
| `github-oidc` or `bitbucket-oidc` | ~$0.25 |

Things deliberately not used: EKS control plane (~$73), NAT gateway (~$33), Transit Gateway attachment (~$36), JFrog cloud (~$150+ per Vendr's estimate), interface endpoints (~$7 each per AZ).

Related: [[Runners]], [[Network]].
