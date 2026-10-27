---
title: Quick Start with Repo Nexus | Meta Repository & Nexus Repo Setup
description: Learn prerequisites, installation options, and how to initialize your first Repo Nexus virtual meta repository (meta repo) and nexus repository (nexus repo) workspace in minutes.
head:
  - - meta
    - name: keywords
      content: nexus repository, meta repository, nexus repo, meta repo, quick start, virtual meta repository, multi-repo setup, rnex
---

# Quick Start

Repo Nexus (`rnex`) orchestrates multi-repository projects into a unified **nexus repository** (**nexus repo**) and **meta repository** (**meta repo**) workspace without requiring monorepo migrations or Git submodules. This walkthrough guides you through installing `rnex`, initializing your first workspace, and connecting member repositories.

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

```sh [Standalone Shell Installer]
# Zero-dependency POSIX installer into ~/.local/bin (no Node.js required)
curl -fsSL https://raw.githubusercontent.com/unoxen/repo-nexus/main/scripts/install.sh | sh

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
[✓] Created rnex.yaml
[✓] Created .gitignore (ignoring repos/, recursive .rnex directories, and .local.rnex.yaml)
[✓] Created .ignore (un-ignoring member repos for search tools)
[✓] Created AGENTS.md (routing to .rnex/ai-instructions.md)
[✓] Workspace initialized in /Users/dev/my-workspace
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
[i] Cloning backend into /Users/dev/my-workspace/repos/backend...
Cloning into '/Users/dev/my-workspace/repos/backend'...
[✓] Cloned backend
[i] Cloning frontend into /Users/dev/my-workspace/repos/frontend...
Cloning into '/Users/dev/my-workspace/repos/frontend'...
[✓] Cloned frontend
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
[backend] (git status -s)
 M src/api/router.go

[frontend] (git status -s)
?? package-lock.json
```

## Next Steps

* Learn about the [Virtual Meta-Repo Architecture](../documentation/architecture).
* Explore the [Two-Level Configuration](../documentation/configuration) model.
* Review all available commands in the [CLI Reference](../reference/cli).
