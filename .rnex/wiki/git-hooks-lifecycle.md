---
title: "Automated Git Hooks & Lifecycle Dispatch"
tags: [git, hooks, lifecycle, triggers]
last_updated: 2026-10-15
sources: ["docs/cli/tooling.md", "docs/guide/configuration.md"]
related: ["workspace-lifecycle.md", "plugin-system.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Automated Git Hooks & Lifecycle Dispatch

## Summary
Repo Nexus features native workspace Git hooks managed via `rnex hooks install|uninstall|status`. Hooks automatically dispatch maintenance events, reconcile configuration changes on checkout/merge, and invoke plugin triggers.

## Key Facts & Insights
* **Config-Driven Activation:** Controlled globally via `git_hooks: true|false` in `rnex.yaml` and overridden locally via `--local`.
* **Hook Chaining:** `.rnex/hooks/` scripts automatically chain to custom team wrappers in `scripts/githooks/` or `.githooks/`, preventing collisions with existing repository workflows.
* **Self-Rewrite Prevention:** Guards against inode churn and infinite execution loops during git operations using runtime environment flags.
* **Plugin Triggers:** Dispatches hook events (`post-merge`, `post-commit`, `pre-commit`, `pre-push`) to active plugins matching configured triggers (e.g. `lint_trigger: manual`).

## Contextual Links
* See [Workspace Lifecycle](./workspace-lifecycle.md) for `rnex sync` post-merge execution.
* See [Plugin Architecture](./plugin-system.md) for plugin hook contracts.
