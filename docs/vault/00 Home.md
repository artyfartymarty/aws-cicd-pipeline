---
tags: [moc]
---
# CI/CD pattern vault

Open this folder (`docs/vault`) as an Obsidian vault. Diagrams are Mermaid, which Obsidian renders natively. The Graph view shows how the notes link.

## Start here
- [[Work pattern]]: what the company runs today, from the Rovo answers and the Autobahn diagrams
- [[My pattern]]: the pattern **here**: GitHub Actions + my AWS account
- [[Yield work pattern]]: the pattern **at work**: Bitbucket Pipelines + the Yield sandbox
- [[Local to work]]: how the pattern here translates to the pattern at work
- [[Mapping]]: work vs mine, component by component, and what's missing
- [[Branching and releases]]: feature → `dev` → release PR → `main`, versions and tags
- [[Runners]]: why there are two runner modes, and which one matches work

## How it runs
- [[Dev deploy sequence]]
- [[Prod release sequence]]
- [[IAM role chain]]
- [[Network]]
- [[Config outside the repo]]

## Guardrails, cost, review
- [[Sandbox guardrails]]
- [[Cost]]
- [[Review findings]]
- [[Gaps and next steps]]
- [[Glossary]]: the words this vault uses, and the ones it avoids

> [!note] Sources
> "Work" facts come from the Rovo screenshots Brian shared (Confluence pages summarized by Rovo, marked "Uses AI. Verify results"). Where I'm inferring, the note says so.

> [!tip] Without Obsidian
> Every diagram is also rendered as an SVG in `diagrams/`.
