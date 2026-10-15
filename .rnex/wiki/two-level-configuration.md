---
title: "Two-Level Configuration Hierarchy"
tags: [configuration, rnex-yaml, local-overrides]
last_updated: 2026-10-15
sources: ["docs/guide/configuration.md", "docs/examples/local-overrides.md"]
related: ["virtual-meta-repo.md", "workspace-lifecycle.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Two-Level Configuration Hierarchy

## Summary
Repo Nexus implements a two-level configuration hierarchy combining team-wide repository declarations in `rnex.yaml` with developer-specific uncommitted overrides in `.local.rnex.yaml`.

## Key Facts & Insights
* **Base Configuration (`rnex.yaml`):** Version-controlled file at the workspace root defining the team baseline: member repository URLs, enabled plugins, workspace schema version, and default settings.
* **Local Override (`.local.rnex.yaml`):** Git-ignored configuration file for developer-specific deviations. It supports selective repository enablement (`enabled: false`), custom paths, and plugin settings.
* **Precedence Rules:** Values in `.local.rnex.yaml` always take highest precedence over `rnex.yaml`. Any missing keys cleanly fall back to `rnex.yaml` defaults.
* **Zero Repo Contamination:** Developers can disable heavy repositories or tweak local paths without dirtying version control or risking accidental commits of local preferences.

## Contextual Links
* See [Workspace Lifecycle](./workspace-lifecycle.md) for how configuration is validated and reconciled.
* See [Virtual Meta-Repo Architecture](./virtual-meta-repo.md) for workspace layout defaults.
