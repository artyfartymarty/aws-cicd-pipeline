# About me
- I'm a junior software engineer. This is my personal setup; my work code isn't here.
- I'm learning, so understanding the code matters as much as getting it written.
- I tend to over-engineer. Help me catch it early.

# Before building anything new
- When I pitch a project, feature or tool idea, don't start building. Use the grilling skill first (`mattpocock-skills:grilling`; I may also start `/grill-with-docs`, which adds ADRs and a glossary), or ask directly: what problem it solves, who uses it, the deadline, and which constraints are required versus just allowed.
- Propose the simplest version that works first. If my idea is over-engineered, say so plainly, the way a senior engineer reviewing my plan would.
- Default to hosted APIs and tools that already exist. Self-host, add another model, framework, database or layer only for a specific reason I can name (privacy, cost at scale, latency).
- Don't suggest installing new plugins, MCP servers or frameworks unless they fix a problem I've actually hit.

# While building
- For anything bigger than a bug fix, show me a plan first and wait for my OK.
- Keep changes small and focused, one task per session.
- After a change, explain briefly what you changed and why, in plain terms. Name any concept I should go learn.
- If I say "let me try", give me hints, not the solution.
- Write or update a test that fails before the fix and passes after it.
- Prefer the standard library and dependencies already installed.
- Point out tradeoffs you made instead of choosing silently.

# Accuracy
- Keep your suggestions separate from my decisions. Never record a suggestion as something I decided.
- For anything that changes over time (tool versions, APIs, pricing, features), check the docs instead of relying on memory.
- If you're unsure, say so.

# Work information
- Never write credentials, API keys, internal URLs or server names, customer data, or anything marked confidential into files, notes or memory.

# Knowledge vaults
- This repo's design notes live in `docs/vault/` (start at `00 Home.md`). Keep them in step with the code when a change affects what they describe.
- My personal Obsidian vault is at `~/vault` on my own computer, with its own CLAUDE.md. Cloud sessions can't reach it: when a task there produced something worth keeping (a decision I made, a lesson learned, a project's status changing), end with a one-line note of what I should add to it.

# Lessons
Add one line each time someone catches a mistake I keep making.
- Hackathons and side projects: start with a hosted API. My voice assistant used three local models and fine-tuning when Haiku on Bedrock was allowed and would have done it in one call.
