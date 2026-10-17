---
tags: [sequence]
---
# Dev deploy sequence

Back to [[00 Home]]. "Deploy to Dev" from any branch, shown in `github-oidc` mode. In `ec2` mode the runner's instance role replaces the OIDC step.

```mermaid
sequenceDiagram
  autonumber
  actor Dev as Developer
  participant GH as GitHub Actions
  participant CI as CI job<br/>(GitHub-hosted)
  participant STS as AWS STS
  participant S3A as S3 artifacts
  participant SSM as SSM config
  participant S3S as S3 state
  participant AWS as Lambda + DynamoDB (dev)

  Dev->>GH: Run "Deploy to Dev" on branch
  GH->>CI: ci.yml: pytest, tofu fmt/validate/test (mocked)
  CI-->>GH: pass
  GH->>STS: _build: OIDC token (repo:owner/repo:ref:...)
  STS-->>GH: CI role credentials
  GH->>S3A: head builds/sha/app.zip
  alt not built yet
    GH->>S3A: put builds/sha/app.zip
  end
  GH->>STS: _deploy: OIDC token
  STS-->>GH: CI role credentials
  GH->>SSM: get /project/env/dev/config
  GH->>STS: AssumeRole deploy-dev
  STS-->>GH: deploy-dev credentials
  GH->>S3S: tofu init (app/dev.tfstate + lock)
  GH->>AWS: tofu plan + apply (s3_key = builds/sha)
  GH->>AWS: invoke {"action":"health"}
  AWS-->>GH: env=dev, build=sha
```

Related: [[Prod release sequence]], [[IAM role chain]].
