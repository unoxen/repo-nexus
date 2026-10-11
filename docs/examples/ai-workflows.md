---
title: Cross-Repo AI Workflows
description: Practical walkthrough of executing cross-cutting features, workspace audits, and multi-agent refactoring with Repo Nexus.
---

# Cross-Repo AI Workflows

One of the greatest challenges with AI coding assistants in multi-repo setups is context isolation: agents operating inside one repository cannot easily coordinate changes across upstream or downstream services.

Repo Nexus equips AI assistants with standardized cross-repo skills and workflows located in `.rnex/skills/` and `.rnex/workflows/`, routed directly through universal `AGENTS.md`.

---

## Workspace Skills & Workflows

When a workspace is initialized, Repo Nexus seeds `.rnex/skills/` and `.rnex/workflows/` with specialized agent workflow templates:

| Workflow / Skill | Target Agent Goal |
|:---|:---|
| `rnex-cross-repo-feature` | Implement an end-to-end feature across backend, frontend, and shared contracts. |
| `rnex-workspace-audit` | Audit git status, unpushed branches, dirty files, and schema health. |
| `rnex-wiki-ingest` | Ingest raw intake documents into atomic Karpathy LLM Wiki pages. |
| `rnex-wiki-lint` | Validate markdown links, compute backlinks, and update the master index. |

When provider plugins (such as `copilot`, `claude`, `gemini`, `cursor`, or `windsurf`) are enabled with `prompts: true`, these workflows are automatically mirrored into the respective native prompt pickers (e.g. `.github/prompts/`, `.claude/commands/`, `.gemini/prompts/`, `.cursor/prompts/`, `.windsurf/prompts/`).

---

## Executing a Cross-Repo Feature

### 1. Invoke the Workflow in Your AI Assistant
In your AI assistant (Copilot Chat, Claude Code, Gemini/Antigravity, Cursor, Windsurf), run or type:

```text
Follow the workflow in .rnex/workflows/rnex-cross-repo-feature.md to add OAuth2 login support across backend and web-client.
```
*(Or select `rnex-cross-repo-feature` directly from your IDE's prompt picker or slash commands.)*

### 2. Autonomous Execution Sequence
The agent follows a 4-stage protocol:
1. **Context Orientation**: Inspects `rnex.yaml` to identify member repositories and locate contract definitions in `repos/contracts/`.
2. **Schema & Contract Definition**: Modifies the shared protocol or OpenAPI spec first.
3. **Service Implementation**: Applies backend API handlers in `repos/backend/` and updates frontend client components in `repos/web-client/`.
4. **Verification**: Executes workspace-wide verification via `rnex exec npm test`.

### 3. Preserving Commits per Repository
Because each repository in `./repos/` is an autonomous Git repository, the agent commits changes directly in each repository root without creating messy parent commit dependencies:

```bash
cd repos/contracts && git commit -m "feat(auth): define oauth2 schema"
cd ../backend && git commit -m "feat(auth): implement oauth2 endpoints"
cd ../web-client && git commit -m "feat(auth): add login buttons"
```
