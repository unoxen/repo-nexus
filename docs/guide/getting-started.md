---
title: Getting Started with Repo Nexus
description: Learn prerequisites, installation options, and how to initialize your first Repo Nexus virtual meta-repo workspace in minutes.
---

# Getting Started

Repo Nexus (`rnex`) orchestrates multi-repository projects into a unified workspace without requiring monorepo migrations or Git submodules. This walkthrough guides you through installing `rnex`, initializing your first workspace, and connecting member repositories.

## Prerequisites

* **Operating System**: macOS, Linux, or Windows (via WSL2).
* **Shell**: Standard POSIX `/bin/sh` (compatible with `bash`, `zsh`, and `dash`).
* **Git**: `git` version 2.20 or newer installed and available in `$PATH`.
* **Node.js** *(optional)*: Node.js >= 24 when running via `npx` or `npm`. Pure shell installation requires zero Node.js runtime.

## Installation

Choose your preferred installation method:

::: code-group

```sh [npx (No Install)]
# Run commands directly without global installation
npx repo-nexus init
```

```sh [npm (Global)]
# Install globally via npm registry
npm install -g repo-nexus

# Verify installation
rnex --version
```

```sh [Standalone Shell Binary]
# Direct POSIX download to /usr/local/bin (no Node.js required)
curl -fsSL https://raw.githubusercontent.com/nu-nenoi/repo-nexus/main/rnex -o /usr/local/bin/rnex
chmod +x /usr/local/bin/rnex

# Verify installation
rnex --version
```

:::

## Creating Your First Workspace

### 1. Initialize the Workspace

Navigate to an empty directory or an existing umbrella folder and initialize Repo Nexus:

```bash
rnex init
```

For non-interactive setup (e.g. in CI pipelines or automated scripts), pass `-y`:

```bash
rnex init -y
```

```text
[rnex] Initializing Repo Nexus workspace in /Users/dev/my-workspace...
[rnex] Created rnex.yaml (version 0.5.13)
[rnex] Created ./repos/ directory
[rnex] Created .rnex/ and standardized prompts
[rnex] Reconciled .gitignore
[rnex] Workspace initialized successfully.
```

### 2. Add Member Repositories

Add your git repositories to the workspace manifest:

```bash
rnex add backend git@github.com:my-org/backend-service.git
rnex add frontend git@github.com:my-org/web-app.git
```

### 3. Clone All Repositories

Fetch and clone all declared repositories in parallel or batch:

```bash
rnex clone
```

```text
[rnex] Cloning backend into ./repos/backend...
Cloning into './repos/backend'...
[rnex] Cloning frontend into ./repos/frontend...
Cloning into './repos/frontend'...
[rnex] All 2 member repositories cloned successfully.
```

### 4. Check Workspace Status

Inspect the health, branches, and configuration state of all member repositories:

```bash
rnex status
```

```text
[rnex] Workspace root: /Users/dev/my-workspace
[rnex] Config: rnex.yaml
[rnex] Repositories (2):
  ✓ backend  (main) -> ./repos/backend
  ✓ frontend (main) -> ./repos/frontend
```

## Next Steps

* Understand the [Virtual Meta-Repo Architecture](./architecture.md).
* Learn about [Two-Level Configuration](./configuration.md) (`rnex.yaml` vs `.local.rnex.yaml`).
* Explore [Plugins and AI Context Mirroring](../plugins/index.md).
