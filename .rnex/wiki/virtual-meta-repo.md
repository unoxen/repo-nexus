---
title: "Virtual Meta-Repo Architecture"
tags: [architecture, core, virtual-meta-repo]
last_updated: 2026-10-15
sources: ["docs/guide/architecture.md", "docs/guide/why-repo-nexus.md"]
related: ["member-repositories.md", "two-level-configuration.md", "context-engineering.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Virtual Meta-Repo Architecture

## Summary
The Virtual Meta-Repo is the central architectural model of Repo Nexus. It unifies independent Git repositories into a coordinated multi-repo workspace without employing Git submodules, monorepo consolidation, or fragile symlink hierarchies.

## Key Facts & Insights
* **Physical Independence:** Member repositories remain standard, autonomous Git repositories located under `repos/<name>/`. Each maintains its own `.git` directory, branches, commits, remotes, and workflows.
* **Zero Symlink Fragility:** Legacy multi-repo tooling relied on symlinks that broke across operating systems (especially Windows), caused circular directory traversals, and corrupted build caches. Repo Nexus operates on explicit directory paths and deterministic discovery.
* **Single AI Entrypoint:** The root workspace contains lean routing directives (`AGENTS.md`) and scoped instructions (`.rnex/ai-instructions.md`) that allow AI assistants to navigate cross-repo tasks safely without unbounded repository scans.
* **Separation of Concerns:** Workspace-level assets (prompts, hooks, plugins) are isolated in `.rnex/`, preserving member repository trees completely unmodified.

## Contextual Links
* See [Member Repositories](./member-repositories.md) for details on clone management and local operations.
* See [Context Engineering](./context-engineering.md) for how AI assistants navigate the meta-repo.
