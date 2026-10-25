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

## Complete Annotated Manifest (`rnex.yaml`)

```yaml
# Workspace Metadata
version: "1"
name: "acme-platform"
description: "Multi-repo platform workspace and shared AI context"
repos_dir: "./repos"
code_workspace: "acme.code-workspace"

# Git Integration (Ignore rules & Git hooks)
git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"
    - "*.log"
    - ".env.local"
  hooks:
    post-merge:
      - "rnex sync --quiet"
    post-checkout:
      - "rnex sync --quiet"
    pre-commit:
      - "rnex plugin karpathy-llm lint"
    pre-push:
      - "rnex plugin karpathy-llm lint --strict"

# RNEX Lifecycle Hooks (Map of RNEX events to command lists)
rnex_hooks:
  before_init: []
  after_init:
    - "echo 'Workspace initialized'"
  before_sync: []
  after_sync:
    - "rnex plugin karpathy-llm ingest --quiet"
  before_clone: []
  after_clone:
    - "rnex exec npm install"
  before_repo_add: []
  after_repo_add: []
  before_repo_remove: []
  after_repo_remove: []
  before_repo_set: []
  after_repo_set: []
  before_plugin_enable: []
  after_plugin_enable: []
  before_plugin_disable: []
  after_plugin_disable: []
  before_plugin_command: []
  after_plugin_command: []
  before_exec: []
  after_exec: []

# Member Repositories
repos:
  backend:
    url: "git@github.com:acme/backend-api.git"
    branch: "main"
    enabled: true
    readonly: false
    description: "Core Go/PostgreSQL API service"
  frontend:
    url: "https://github.com/acme/web-client.git"
    branch: "develop"
    enabled: true
    readonly: false
    description: "React/TypeScript web application"
  shared-contracts:
    url: "git@github.com:acme/contracts.git"
    branch: "v2"
    enabled: true
    readonly: true
    description: "Read-only OpenAPI & Protobuf schemas"

# Scoped Plugins & AI Providers
plugins:
  claude:
    enabled: true
    skills: true
  cursor:
    enabled: true
    skills: true
  codex:
    enabled: true
    skills: true
  gemini:
    enabled: false
    skills: true
  windsurf:
    enabled: false
    skills: true
  copilot:
    enabled: false
    skills: true
  karpathy-llm:
    enabled: true
    wiki_dir: "wiki"
    sources:
      - "docs"
      - "adr"
      - "repos/**/README.md"
```

---

## Field Specifications

### Root Options

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `version` | string | `"1"` | Schema version compatibility check. |
| `name` | string | basename | Workspace identifier. |
| `repos_dir` | string | `./repos` | Directory where member repositories are cloned. |
| `code_workspace`| string / bool | `false` | Path to generated `.code-workspace` file. |

### Git Integration (`git`)

* `git.ignore`: List of directories or file patterns appended to `.gitignore`. Directories starting with `.rnex` or `rnex` (`**/.rnex*/`, `**/rnex*/`) are recursively ignored by default.
* `git.hooks`: Map of Git hook names (`post-merge`, `post-checkout`, `pre-commit`, `pre-push`) to lists of shell commands executed when the hook fires.

### Lifecycle Hooks (`rnex_hooks`)

Map of workspace lifecycle event names (`before_sync`, `after_sync`, `after_clone`, etc.) to lists of shell commands executed by the RNEX dispatcher.

### Member Repositories (`repos`)

Each key represents a repository name with:
* `url`: Git remote repository clone URL.
* `branch`: Default Git branch to checkout.
* `enabled`: Whether the repository is active and eligible for batch operations (`true` by default).
* `readonly`: When `true`, instructs AI agents and developers that the repository is reference-only.
