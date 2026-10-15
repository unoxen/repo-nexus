---
title: "Scoped Plugin Architecture"
tags: [plugins, architecture, lifecycle, extensibility]
last_updated: 2026-10-15
sources: ["docs/plugins/index.md", "docs/plugins/authoring.md"]
related: ["context-engineering.md", "ide-provider-mirroring.md", "karpathy-llm-wiki.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Scoped Plugin Architecture

## Summary
Repo Nexus plugins extend the workspace with AI provider integrations, domain tools, and workflows. Plugins are self-contained packages scoped under `.rnex/plugins/<plugin-name>/` with declarative manifests and lifecycle hooks.

## Key Facts & Insights
* **Declarative Manifest (`plugin.yaml`):** Declares plugin metadata, configuration defaults, lifecycle hooks, and provided skills, workflows, and prompts.
* **Lifecycle Hooks:** Shell scripts executed during workspace lifecycle events:
  - `after_init.sh`: Runs once when the plugin is enabled or during workspace initialization.
  - `after_sync.sh`: Runs during `rnex sync` to prepare assets and reconcile intake.
  - `git_*.sh`: Event hooks (`git_post-commit.sh`, `git_post-merge.sh`, etc.) triggered by workspace git operations.
* **Clean Deactivation:** Disabling a plugin with `rnex plugin disable <name>` cleanly cleans mirrored provider prompts, instructions, and workspace state without leaving orphaned files.

## Contextual Links
* See [Karpathy LLM Wiki](./karpathy-llm-wiki.md) for the premier domain knowledge plugin.
* See [IDE Provider Mirroring](./ide-provider-mirroring.md) for how plugins deliver prompts.
