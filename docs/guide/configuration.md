---
title: Configuration & Schema
description: Comprehensive specification of rnex.yaml and .local.rnex.yaml, precedence rules, schema options, and configuration reconciliation.
---

# Configuration & Schema

Repo Nexus uses a declarative YAML configuration system split across two layers: **Team Configuration** (`rnex.yaml`) and **Workstation Overrides** (`.local.rnex.yaml`).

## Two-Level Configuration Model

### 1. Team Configuration (`rnex.yaml`)
* **Checked into Git**: Shared with all team members and CI pipelines.
* **Establishes Defaults**: Defines member repositories, baseline plugins, and default branch settings.

### 2. Workstation Overrides (`.local.rnex.yaml`)
* **Gitignored**: Never committed to version control.
* **Developer Flexibility**: Enables individual engineers to disable repositories they don't work on, test experimental branches, or activate preferred editor plugins locally without polluting team configuration.

### Merging Precedence
Settings in `.local.rnex.yaml` take precedence over `rnex.yaml`:
1. If a key is present in `.local.rnex.yaml`, its value overrides the value in `rnex.yaml`.
2. Repositories and plugins are merged by name: disabling a repository in `.local.rnex.yaml` (`enabled: false`) overrides `enabled: true` in `rnex.yaml`.

---

## Configuration Schema

Below is a complete annotated example of `rnex.yaml`:

```yaml
# Workspace Schema Version
version: 0.5.13

# Directory where member repositories are cloned (default: ./repos)
repos_dir: ./repos

# Multi-root VS Code / Cursor workspace file generation
# Options: false, true (generates <dir>.code-workspace), or custom filename
code_workspace: workspace.code-workspace

# Automated workspace Git hooks (default: true)
git_hooks: true

# Member Repositories
repos:
  backend:
    url: git@github.com:my-org/api-service.git
    branch: main
    enabled: true
    shallow: false

  frontend:
    url: git@github.com:my-org/web-frontend.git
    branch: develop
    enabled: true

  legacy-monolith:
    url: git@github.com:my-org/old-monolith.git
    branch: master
    enabled: false # Disabled by default; skip cloning

# Workspace Plugins
plugins:
  # AI Provider Plugins
  claude:
    instructions: true
    prompts: true
    workflows: true

  cursor:
    instructions: true
    prompts: true
    workflows: true

  # Knowledge & Agent Protocol Plugins
  karpathy-llm:
    lint_trigger: git-post-merge
    notify_on_changes: true
```

---

## Field Specifications

### Root Options

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `version` | string | Current CLI version | Schema version compatibility check. |
| `repos_dir` | string | `./repos` | Relative or absolute path where member repos are cloned. |
| `code_workspace` | boolean \| string | `false` | Enables `.code-workspace` generation. Pass a string for custom filename. |
| `git_hooks` | boolean | `true` | Configures `.rnex/hooks` as `core.hooksPath` during `rnex fix`. |
| `repos` | map | `{}` | Map of member repository specifications keyed by name. |
| `plugins` | map | `{}` | Map of enabled plugins and their configuration options. |

### Repository Object (`repos.<name>`)

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `url` | string | *(required)* | Remote Git clone URL (SSH or HTTPS). |
| `branch` | string | Remote default | Target branch to checkout during clone or sync. |
| `enabled` | boolean | `true` | If `false`, repository is skipped during clone, exec, and sync. |
| `shallow` | boolean | `false` | If `true`, clone with `--depth 1` for fast CI setup. |

---

## Workstation Override Example

To disable heavy services and switch to a personal feature branch locally, create `.local.rnex.yaml`:

```yaml
repos:
  backend:
    branch: feat/user-auth-rewrite
  legacy-monolith:
    enabled: false

plugins:
  gemini:
    instructions: true
```

After modifying configuration files directly, reconcile the workspace state:

```bash
rnex fix
```

::: tip Alias Available
`rnex sync` is an identical alias for `rnex fix`. Both commands reconcile config, update directory structures, and regenerate instruction files.
:::
