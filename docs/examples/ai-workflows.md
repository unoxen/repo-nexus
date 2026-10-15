---
title: Cross-Repo AI Workflows
description: Practical walkthrough of executing cross-cutting features, workspace audits, and multi-agent refactoring with Repo Nexus.
---

# Cross-Repo AI Workflows

One of the greatest challenges with AI coding assistants in multi-repo setups is context isolation: agents operating inside one repository cannot easily coordinate changes across upstream or downstream services.

Repo Nexus equips AI assistants with standardized cross-repo agentic skills located in `.rnex/skills/` and active plugin directories (`.rnex/plugins/<plugin>/skills/`), routed directly through universal `AGENTS.md`.

---

## Two-Tier Skills Architecture

When a workspace is initialized, Repo Nexus maintains core agentic skills in `.rnex/skills/` alongside plugin-owned skills in `.rnex/plugins/<plugin>/skills/`:

| Skill | Category | Target Agent Goal | Protocol Path |
|:---|:---|:---|:---|
| `clone-sync` | Core | Automated clone, setup, and synchronization of member repositories. | `.rnex/skills/clone-sync.md` |
| `batch-exec` | Core | Cross-repository batch commands, parallel execution, and verification. | `.rnex/skills/batch-exec.md` |
| `workspace-status` | Core | Workspace health check, git dirty status, branch tracking, and configuration audit. | `.rnex/skills/workspace-status.md` |
| `wiki-ingest` | Plugin (`karpathy-llm`) | Ingest raw intake documents into atomic Karpathy LLM Wiki pages. | `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` |
| `wiki-lint` | Plugin (`karpathy-llm`) | Validate markdown links, compute backlinks, and update the master index. | `.rnex/plugins/karpathy-llm/skills/wiki-lint.md` |

When provider plugins (such as `claude`, `gemini`, `cursor`, or `windsurf`) are enabled with `skills: true`, zero-logic User Skill pointers (`rnex-<skill-name>.md`) are generated directly into the respective native provider directories (`.cursor/rules/`, `.claude/skills/`, `.gemini/skills/`, `.windsurf/rules/`).

---

## Executing a Cross-Repo Batch Feature

### 1. Invoke the Skill in Your AI Assistant
In your AI assistant (Claude Code, Gemini/Antigravity, Cursor, Windsurf), run or type:

```text
Follow the skill protocol in .rnex/skills/batch-exec.md to run tests across backend and web-client.
```
*(Or invoke `rnex-batch-exec` directly from your IDE's skill/rules list.)*

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
