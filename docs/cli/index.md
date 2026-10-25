---
title: CLI Overview & Cheatsheet
description: Fast reference cheatsheet for rnex commands, global options, environment variables, and exit codes.
---

# CLI Overview & Cheatsheet

`rnex` is a zero-dependency command-line utility built entirely in pure POSIX shell (`/bin/sh`). It orchestrates **Virtual Meta-Repo** workspaces, coordinates member repositories, automates Git workflows, and mirrors AI context.

## Quick Command Cheatsheet

### Workspace Lifecycle & System

Manage workspace initialization, configuration reconciliation, health diagnostics, and CLI environment setup.

| Command | Syntax | Description |
|:---|:---|:---|
| [`rnex init`](workspace.md#rnex-init) | `rnex init [options] [dir]` | Initialize a new Repo Nexus workspace (`rnex.yaml`, Git rules, and AI routing). |
| [`rnex sync`](workspace.md#rnex-sync) | `rnex sync [-y] [-q\|--quiet]` | Single reconciliation command: sync skills, plugins, Git hooks & ignore rules, and compile `.rnex/ai-instructions.md`. |
| [`rnex status`](workspace.md#rnex-status) | `rnex status` | Strictly read-only: inspect workspace health, active repos, loaded config, hooks, and plugins. |
| [`rnex install`](workspace.md#rnex-install) | `rnex install [bin-dir]` | Install and symlink `rnex` and `repo-nexus` to `~/.local/bin` (or custom directory). |
| [`rnex completion`](workspace.md#rnex-completion) | `rnex completion <bash\|zsh\|fish>` | Generate shell auto-completion script with event-driven auto-sync hooks. |
| [`rnex version`](workspace.md#rnex-version) | `rnex version` / `rnex -v` | Display the current installed CLI version. |

### Single-Repository Management (`rnex repo`)

Register, configure, inspect, or run commands targeting an individual member repository under `./repos/<name>`.

| Command | Syntax | Description |
|:---|:---|:---|
| [`rnex repo add`](repos.md#rnex-repo-add) | `rnex repo add <url> [--name <n>] [--branch <b>] [--local] [--disabled] [--readonly]` | Register a Git repository in configuration and clone it into `./repos/<name>`. |
| [`rnex repo remove`](repos.md#rnex-repo-remove) | `rnex repo remove <name> [--purge] [-y\|--yes]` | Unregister a repository from configuration (pass `--purge` to also delete its directory from disk). |
| [`rnex repo set`](repos.md#rnex-repo-set) | `rnex repo set <name> [--enable\|--disable] [--readonly\|--readwrite] [--global\|--local]` | Update repository state and access flags (defaults to `--local` in `.local.rnex.yaml`). |
| [`rnex repo clone`](repos.md#rnex-repo-clone) | `rnex repo clone <name>` | Clone a specific registered member repository into `./repos/<name>`. |
| [`rnex repo status`](repos.md#rnex-repo-status) | `rnex repo status <name>` | Inspect configuration, active branch, and Git working tree status for a specific repository. |
| [`rnex repo exec`](repos.md#rnex-repo-exec) | `rnex repo exec <name> <command...>` | Execute an arbitrary shell command inside `./repos/<name>`. |
| [`rnex repo list`](repos.md#rnex-list) | `rnex repo list` | Alias for `rnex list` — display a table of registered member repositories. |

### Workspace-Wide Repository & Batch Operations

Operate across all registered member repositories in the workspace at once.

| Command | Syntax | Description |
|:---|:---|:---|
| [`rnex clone`](repos.md#rnex-clone) | `rnex clone` | Clone all enabled member repositories declared in configuration that are missing from disk. |
| [`rnex list`](repos.md#rnex-list) | `rnex list` | Print a formatted table of all registered repositories with state, clone status, branch, and readonly flag. |
| [`rnex exec`](execution.md) | `rnex exec <command...>` | Run an arbitrary shell command sequentially across all enabled member repositories. |

### Plugins & Extensible Tooling (`rnex plugin`)

Manage modular AI provider plugins, knowledge base extensions, and plugin-provided CLI subcommands.

| Command | Syntax | Description |
|:---|:---|:---|
| [`rnex plugin list`](tooling.md#rnex-plugin-list) | `rnex plugin [list]` | List all available, enabled, and disabled plugins. |
| [`rnex plugin info`](tooling.md#rnex-plugin-info) | `rnex plugin info <name>` | Display metadata, configurable YAML options, commands, and templates for a plugin. |
| [`rnex plugin enable`](tooling.md#rnex-plugin-enable) | `rnex plugin enable [--local] <name>` | Enable a plugin in workspace configuration and sync its assets into `.rnex/plugins/<name>/`. |
| [`rnex plugin disable`](tooling.md#rnex-plugin-disable) | `rnex plugin disable [--local] <name>` | Disable a plugin, run its cleanup hook, and prune its scoped assets. |
| [`rnex plugin update`](tooling.md#rnex-plugin-update) | `rnex plugin update [<name>]` | Re-sync and update an enabled plugin (or all enabled plugins) from toolkit sources. |
| [`rnex plugin <name> <cmd>`](tooling.md#extensible-plugin-commands-rnex-plugin-name-command) | `rnex plugin <name> <cmd> [options...]` | Execute a subcommand provided by an enabled plugin (e.g. `rnex plugin karpathy-llm ingest`). |

---

## Global Syntax & Flags

```sh
rnex [global-options] <command> [command-options] [arguments]
```

### Global Options Table

| Flag | Shorthand | Type | Description |
|:---|:---|:---|:---|
| `--config <file>` | `-c <file>` | string | Path to custom workspace configuration file (e.g. `/path/to/rnex.yaml`). Executes as if running from that file's directory. |
| `--help` | `-h` | boolean | Display command usage and help summary. |
| `--version` | `-v` | boolean | Output CLI version. |

---

## Agentic Skills Catalog

Repo Nexus provides a standardized suite of agentic skills in `toolkit/skills/` (core) and `toolkit/plugins/<plugin>/skills/` (plugins).

AI assistants navigate skills via `AGENTS.md` and direct skill protocol paths:

| Skill | Category | Purpose | Protocol Path |
|:---|:---|:---|:---|
| `clone-sync` | Core | Automated clone, setup, and synchronization of member repositories. | `.rnex/skills/clone-sync.md` |
| `batch-exec` | Core | Cross-repository batch commands, parallel execution, and verification. | `.rnex/skills/batch-exec.md` |
| `workspace-status` | Core | Workspace health check, git dirty status, branch tracking, and configuration audit. | `.rnex/skills/workspace-status.md` |
| `wiki-ingest` | Plugin (`karpathy-llm`) | Autonomous ingestion of source docs into atomic Karpathy LLM Wiki pages. | `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` |
| `wiki-lint` | Plugin (`karpathy-llm`) | Link validation, backlink recalculation, and index rebuilding. | `.rnex/plugins/karpathy-llm/skills/wiki-lint.md` |

---

## Environment Variables

| Variable | Description |
|:---|:---|
| `RNEX_CONFIG` | Overrides the default configuration file path (`rnex.yaml`). |
| `NO_COLOR` | Disables ANSI color sequences in terminal output when set. |

---

## Exit Codes

| Code | Meaning |
|:---|:---|
| `0` | Success. |
| `1` | General error (missing config, invalid arguments, or failing `rnex exec` command). |

