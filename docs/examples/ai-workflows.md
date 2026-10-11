---
title: Cross-Repo AI Workflows
description: Practical walkthrough of executing cross-cutting features, workspace audits, and multi-agent refactoring with Repo Nexus.
---

# Cross-Repo AI Workflows

One of the greatest challenges with AI coding assistants in multi-repo setups is context isolation: agents operating inside one repository cannot easily coordinate changes across upstream or downstream services.

Repo Nexus equips AI assistants with standardized cross-repo workflows located in `.rnex/prompts/`.

---

## The Prompts Catalog

When a workspace is initialized, Repo Nexus seeds `.rnex/prompts/` with specialized agent workflow templates:

| Workflow Prompt | Target Agent Goal |
|:---|:---|
| `rnex-cross-repo-feature.md` | Implement an end-to-end feature across backend, frontend, and shared contracts. |
| `rnex-workspace-audit.md` | Audit git status, unpushed branches, dirty files, and schema health. |
| `rnex-wiki-ingest.md` | Ingest raw documentation from `/raw/` into Karpathy LLM Wiki pages. |
| `rnex-wiki-lint.md` | Validate markdown links, compute backlinks, and update the master index. |

---

## Executing a Cross-Repo Feature

### 1. Invoke the Prompt in Your AI Assistant
In Claude Code, Cursor, or Gemini, invoke the workflow:

```text
Follow the workflow in .rnex/prompts/rnex-cross-repo-feature.md to add OAuth2 login support across backend and web-client.
```

### 2. Autonomous Execution Sequence
The agent follows a 4-stage protocol:
1. **Context Orientation**: Inspects `rnex.yaml` to identify member repositories and locate contract definitions in `repos/contracts/`.
2. **Schema & Contract Definition**: Modifies the shared protocol or OpenAPI spec first.
3. **Service Implementation**: Applies backend API handlers in `repos/backend/` and updates frontend client components in `repos/web-client/`.
4. **Verification**: Executes workspace-wide verification via `rnex exec npm test`.

### 3. Preserving Commits per Repository
Because each repository in `./repos/` is a standard Git repository, the agent commits changes directly in each repository root without creating messy parent commit dependencies:

```bash
cd repos/contracts && git commit -m "feat(auth): define oauth2 schema"
cd ../backend && git commit -m "feat(auth): implement oauth2 endpoints"
cd ../web-client && git commit -m "feat(auth): add login buttons"
```
