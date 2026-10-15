---
title: "Member Repositories Management"
tags: [repositories, git, lifecycle, clones]
last_updated: 2026-10-15
sources: ["docs/cli/workspace.md", "docs/guide/architecture.md"]
related: ["virtual-meta-repo.md", "batch-operations.md", "git-hooks-lifecycle.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Member Repositories Management

## Summary
Member repositories are autonomous Git repositories placed under `repos/<name>/` managed by Repo Nexus. Each member repository preserves its independent git history, remote origins, and branch strategies.

## Key Facts & Insights
* **Clone Lifecycle:** Declared in `rnex.yaml` with remote URLs and optional default branches. Cloned on demand via `rnex clone` or initialized during `rnex init`.
* **Autonomous Operations:** All source code commits, branch checkouts, and pushes occur directly within the member repository root (`repos/<name>/`). The meta-repo root does not commit member repository code.
* **Local Gating:** Repositories can be selectively disabled via `enabled: false` in `.local.rnex.yaml` to exclude them from batch execution (`rnex exec`) and AI routing.
* **Workspace Isolation:** Member repositories contain an optional `.rnex/` directory for repo-specific AI instructions, isolated from the meta-repo's workspace configuration.

## Contextual Links
* See [Batch Operations](./batch-operations.md) for multi-repo command execution.
* See [Git Hooks Lifecycle](./git-hooks-lifecycle.md) for event dispatching across member repos.
