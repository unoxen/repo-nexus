---
title: Quick Start with Repo Nexus
description: Learn prerequisites, installation options, and how to initialize your first Repo Nexus virtual meta-repo workspace in minutes.
---

# Quick Start

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
curl -fsSL https://raw.githubusercontent.com/unoxen/repo-nexus/main/rnex -o /usr/local/bin/rnex
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
[rnex] Created rnex.yaml (version 0.8.1)
[rnex] Created ./repos/ directory
[rnex] Created .rnex/ and standardized skills
[rnex] Reconciled .gitignore
[rnex] Workspace initialized successfully.
```

### 2. Add Member Repositories

Add your git repositories to the workspace manifest:

```bash
rnex repo add git@github.com:my-org/backend-service.git --name backend
rnex repo add git@github.com:my-org/web-app.git --name frontend
```

### 3. Clone All Repositories

Fetch and clone all declared repositories in batch:

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
Workspace Health:
  ✓ .gitignore (reconciled)
  ✓ rnex.yaml (manifest)
  ✓ AGENTS.md (standard instructions directive)
  ✓ .rnex/ai-instructions.md (compiled AI instructions)

Member Repositories:
  ● backend            [main] git@github.com:my-org/backend-service.git
  ● frontend           [main] git@github.com:my-org/web-app.git
```

### 5. Execute Batch Commands

Run commands across all active repositories simultaneously:

```bash
rnex exec git status -s
```

```text
==> [backend] (./repos/backend)
 M src/api/router.go

==> [frontend] (./repos/frontend)
?? package-lock.json
```

## Next Steps

* Learn about the [Virtual Meta-Repo Architecture](../documentation/architecture).
* Explore the [Two-Level Configuration](../documentation/configuration) model.
* Review all available commands in the [CLI Reference](../reference/cli).
