---
title: CLI Overview & Cheatsheet
description: Fast reference cheatsheet for rnex commands, global options, environment variables, and exit codes.
---

# CLI Overview & Cheatsheet

`rnex` is a zero-dependency command-line utility built entirely in pure POSIX shell (`/bin/sh`). It orchestrates **Virtual Meta-Repo** workspaces, coordinates member repositories, automates Git workflows, and mirrors AI context.

## Quick Command Cheatsheet

| Command | Category | Description |
|:---|:---|:---|
| [`rnex init`](workspace.md#rnex-init) | Workspace | Initialize a new Repo Nexus workspace. |
| [`rnex status`](workspace.md#rnex-status) | Workspace | Inspect workspace health, clones, and AI instructions. |
| [`rnex fix` / `sync`](workspace.md#rnex-fix-alias-sync) | Workspace | Reconcile config, routing, prompts, and plugins. |
| [`rnex update` / `upgrade`](workspace.md#rnex-update-alias-upgrade) | Workspace | Part of fix: verify version, upgrade schema, and reconcile workspace. |
| [`rnex install`](workspace.md#rnex-install) | Workspace | Symlink `rnex` to `~/.local/bin`. |
| [`rnex completion`](workspace.md#rnex-completion) | Workspace | Generate shell auto-completion for Zsh, Bash, or Fish. |
| [`rnex version`](workspace.md#rnex-version) | Workspace | Display current installed CLI version. |
| [`rnex add`](repos.md#rnex-add) | Repositories | Register a git repository and clone it into `./repos/`. |
| [`rnex clone`](repos.md#rnex-clone) | Repositories | Clone all declared repositories missing from disk. |
| [`rnex list`](repos.md#rnex-list) | Repositories | Print table of registered member repositories. |
| [`rnex enable`](repos.md#rnex-enable-rnex-disable) | Repositories | Enable a repository (include in sync and exec). |
| [`rnex disable`](repos.md#rnex-enable-rnex-disable) | Repositories | Disable a repository (exclude from sync and exec). |
| [`rnex remove`](repos.md#rnex-remove) | Repositories | Unregister repository and delete clone from disk. |
| [`rnex rnex-dir`](repos.md#rnex-rnex-dir) | Repositories | Toggle `.rnex/` context inside member repository. |
| [`rnex exec`](execution.md) | Execution | Run arbitrary shell commands across all active repos. |
| [`rnex hooks`](tooling.md#git-hooks-automation) | Tooling | Manage automated Git hooks (`post-merge`, etc.). |
| [`rnex plugin`](tooling.md#plugin-management) | Tooling | List, inspect, enable, and disable workspace plugins. |

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
