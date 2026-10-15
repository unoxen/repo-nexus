---
title: "AI Context Engineering & Routing Protocol"
tags: [ai, context, agents, routing, tokens]
last_updated: 2026-10-15
sources: ["docs/guide/architecture.md", "docs/cli/workspace.md"]
related: ["virtual-meta-repo.md", "ide-provider-mirroring.md", "karpathy-llm-wiki.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# AI Context Engineering & Routing Protocol

## Summary
Repo Nexus replaces massive, bloated prompt context dumps with a lean routing protocol. It enforces strict session startup gates and decouples tasks into operational routers that dispatch to dedicated skills and workflows.

## Key Facts & Insights
* **Single Direct Routing Directive:** The top-level `AGENTS.md` is minimal (under 5 lines), pointing AI assistants unconditionally to `.rnex/ai-instructions.md`.
* **Mandatory Session Startup Gate:** AI assistants must read configuration (`rnex.yaml` / `.local.rnex.yaml`) and plugin routing instructions first before touching member repositories. Blind codebase scans are strictly prohibited.
* **Task Router Decoupling:** Operational prompts (e.g. `rnex-cross-repo-feature.md`, `rnex-workspace-audit.md`) contain zero inline rules or heuristic algorithms. They act strictly as routers pointing to `.rnex/skills/` and `.rnex/workflows/`.
* **Context Economy:** Keeps token consumption minimal by directing agents to targeted files in `repos/<name>/` rather than loading entire repositories into context.

## Contextual Links
* See [Karpathy LLM Wiki](./karpathy-llm-wiki.md) for structured knowledge graph retrieval.
* See [IDE Provider Mirroring](./ide-provider-mirroring.md) for prompt delivery across developer tools.
