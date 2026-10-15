---
title: "Cross-Repository Batch Execution"
tags: [cli, exec, batch, tooling, commands]
last_updated: 2026-10-15
sources: ["docs/cli/tooling.md", "docs/guide/workflows.md"]
related: ["member-repositories.md", "workspace-lifecycle.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Cross-Repository Batch Execution

## Summary
The `rnex exec` command executes arbitrary shell commands across all enabled member repositories, enabling synchronized building, linting, testing, and Git operations without monorepo build tools.

## Key Facts & Insights
* **Sequential & Parallel Execution:** Runs commands inside each `repos/<name>/` directory with clear status output and exit code aggregation.
* **Error Handling:** Exits fast upon failure by default, with `--continue-on-error` (`-c`) support to complete execution across all repositories regardless of individual failures.
* **Filtering & Scoping:** Honors `enabled: false` declarations in `.local.rnex.yaml` and supports targeting specific member repositories.
* **Zero Wrapper Dependencies:** Operates natively with standard shell tools (`npm test`, `git status`, `cargo build`, `pytest`), requiring no language-specific plugin.

## Contextual Links
* See [Member Repositories](./member-repositories.md) for physical repository layout.
* See [Workspace Lifecycle](./workspace-lifecycle.md) for repository cloning and initialization.
