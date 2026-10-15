---
title: Wiki Index
last_updated: 2026-10-15
---

# Wiki Index

Master navigation index for the Karpathy LLM Wiki. Agents query this index on demand when searching for specific domain concepts not covered in `hot.md`.

> **Convention**: Every page entry must maintain a 1-line annotation (e.g. `- [Topic](path.md): Brief description`) so agents can target the exact page without exploratory reading.

## Overview & Status
* **Rolling Cache:** [`hot.md`](./hot.md) — Fast ~500-word orientation cache (read first on startup).
* **Operation Log:** [`_log.md`](./_log.md) — Timestamped ingest & maintenance history.

## Architecture & Concepts
* [`virtual-meta-repo.md`](./virtual-meta-repo.md): Central architectural model unifying independent git repositories without submodules or symlink fragility.
* [`context-engineering.md`](./context-engineering.md): AI routing protocol, single directive in `AGENTS.md`, and modular instruction routing.
* [`karpathy-llm-wiki.md`](./karpathy-llm-wiki.md): Compounding knowledge base architecture, hot cache, master index, and frontmatter relations.
* [`plugin-system.md`](./plugin-system.md): Scoped plugin architecture in `.rnex/plugins/<name>/` with declarative manifests and lifecycle hooks.

## Configuration & Lifecycle
* [`two-level-configuration.md`](./two-level-configuration.md): Two-level configuration hierarchy combining `rnex.yaml` with local `.local.rnex.yaml` overrides.
* [`workspace-lifecycle.md`](./workspace-lifecycle.md): Workspace lifecycle, declarative health checks (`rnex status`), and reconciliation (`rnex sync`).
* [`git-hooks-lifecycle.md`](./git-hooks-lifecycle.md): Native workspace git hooks in `.rnex/hooks/` with dynamic plugin trigger dispatch.

## Tooling & Operations
* [`member-repositories.md`](./member-repositories.md): Autonomous Git repository management under `repos/<name>/` and physical clone lifecycle.
* [`batch-operations.md`](./batch-operations.md): Cross-repository batch execution engine (`rnex exec`) across all enabled member repositories.
* [`ide-provider-mirroring.md`](./ide-provider-mirroring.md): Scoped prompt and instruction mirroring across Claude, Copilot, Cursor, Gemini, and Windsurf.
