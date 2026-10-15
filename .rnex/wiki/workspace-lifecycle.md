---
title: "Workspace Reconciliation & Lifecycle"
tags: [cli, sync, status, update, lifecycle]
last_updated: 2026-10-15
sources: ["docs/cli/workspace.md", "docs/guide/getting-started.md"]
related: ["two-level-configuration.md", "plugin-system.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Workspace Reconciliation & Lifecycle

## Summary
The Repo Nexus workspace lifecycle centers around declarative configuration, continuous health checks with `rnex status`, automated reconciliation via `rnex sync`, and non-destructive schema migrations.

## Key Facts & Insights
* **`rnex init`:** Initializes a fresh Virtual Meta-Repo or configures an existing multi-repo folder with interactive prompts for git hooks and provider plugins.
* **`rnex sync`:** Reconciles workspace state, member repository `.rnex/` structures, active plugin assets, and IDE prompt mirrors. Accepts `-y` for non-interactive automation and `--quiet` for hook execution.
* **`rnex status`:** Diagnostics engine verifying configuration files, AI instruction integrity, VS Code multi-root workspace sync, Git hooks health, and member repository clean/dirty status.
* **Non-Destructive Upgrades:** Schema upgrades across CLI versions are detected upfront, prompting developers to upgrade configuration cleanly without data loss.

## Contextual Links
* See [Two-Level Configuration](./two-level-configuration.md) for configuration parameters.
* See [Plugin Architecture](./plugin-system.md) for plugin synchronization hooks.
