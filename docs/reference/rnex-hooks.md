---
title: Lifecycle Hooks
description: Complete reference for lifecycle hooks, event triggers, configuration syntax, and environment variables.
---

# Lifecycle Hooks

Repo Nexus includes a built-in event-driven lifecycle hook system configured under the top-level `rnexHooks:` block in `rnex.yaml` or `.local.rnex.yaml`.

::: tip Zero Default & Zero Hidden Hooks (Strict Opt-In)
Repo Nexus enforces a strict **opt-in** contract: **zero default or hidden lifecycle hooks exist**. No commands run during any lifecycle stage unless explicitly declared in `rnex.yaml` or `.local.rnex.yaml`.
:::

---

## Configuration Syntax

Hooks are defined as a mapping from lifecycle event names to lists of shell commands:

```yaml
rnexHooks:
  beforeSync: []
  afterSync:
    - "rnex plugin llm-wiki ingest"
    - "echo 'Workspace synchronized successfully'"

  beforeClone: []
  afterClone:
    - "rnex exec npm install"

  beforeRepoAdd: []
  afterRepoAdd:
    - "echo 'Added repository:' $RNEX_REPO_NAME"

  beforePluginCommand: []
  afterPluginCommand:
    - "echo 'Finished command:' $RNEX_PLUGIN_COMMAND"
```

Workstation-specific overrides can be added to `.local.rnex.yaml`. If an event list is specified in `.local.rnex.yaml`, its command list takes precedence and overrides that event's commands in `rnex.yaml`.

---

## Supported Lifecycle Events

| Event Name | Trigger Moment | Command Arguments Received |
|:---|:---|:---|
| `beforeInit` | Fired before workspace initialization begins. | `[directory]` |
| `afterInit` | Fired immediately after workspace initialization finishes. | `[directory]` |
| `beforeSync` | Fired before workspace reconciliation begins. | `[flags...]` |
| `afterSync` | Fired after all reconciliation steps (skills, gitignore, hooks) finish. | `[flags...]` |
| `beforeClone` | Fired before member repository cloning begins. | |
| `afterClone` | Fired after all missing repositories have cloned. | |
| `beforeRepoAdd` | Fired before adding and cloning a new repository. | `<url> [--name <name>] ...` |
| `afterRepoAdd` | Fired after a new repository is cloned and registered. | `<url> [--name <name>] ...` |
| `beforeRepoRemove` | Fired before removing a repository from configuration. | `<name> [--purge]` |
| `afterRepoRemove` | Fired after a repository is unregistered and purged. | `<name> [--purge]` |
| `beforeRepoSet` | Fired before toggling repository status flags. | `<name> [flags...]` |
| `afterRepoSet` | Fired after repository flags are updated. | `<name> [flags...]` |
| `beforePluginEnable` | Fired before copying plugin assets into `.rnex/plugins/`. | `<plugin-name>` |
| `afterPluginEnable` | Fired after plugin assets and skills are placed. | `<plugin-name>` |
| `beforePluginDisable` | Fired before running cleanup and pruning plugin assets. | `<plugin-name>` |
| `afterPluginDisable` | Fired after plugin assets are deleted. | `<plugin-name>` |
| `beforePluginCommand` | Fired before executing a plugin subcommand. | `<plugin> <cmd> [args...]` |
| `afterPluginCommand` | Fired after executing a plugin subcommand. | `<plugin> <cmd> [args...]` |
| `beforeExec` | Fired before batch command execution across repositories. | `<cmd...>` |
| `afterExec` | Fired after batch command execution completes. | `<cmd...>` |

---

## Execution Environment & Variables

Hooks execute within a standard subshell (`/bin/sh -e`) inside the workspace root (`RNEX_ROOT`). Any non-zero exit code halts execution immediately, preventing downstream corruption.

### Exported Variables

* `RNEX_ROOT`: Absolute path to the workspace root directory.
* `RNEX_HOOK_EVENT`: Name of the lifecycle event currently executing (e.g. `afterSync`).
* `RNEX_HOOK_ARGS`: Full space-separated string of arguments passed to the event.
* `RNEX_REPO_NAME`: Name of the affected repository (for `repo` events).
* `RNEX_PLUGIN_NAME`: Name of the affected plugin (for `plugin` events).
* `RNEX_PLUGIN_COMMAND`: Name of the executed subcommand (for `plugin_command` events).

### Recursion Prevention (`--ignore-hooks` / `-H`)
To prevent recursive hook execution across nested or consequential commands:
* Pass `--ignore-hooks` or `-H` to any `rnex` command (or set `RNEX_IGNORE_HOOKS=1`) to skip all user-configured `rnexHooks` and `git.hooks`.
* Whenever `rnex` executes a command from a lifecycle hook or Git hook, it automatically injects `--ignore-hooks` into `rnex` invocations and exports `RNEX_IGNORE_HOOKS=1` in the hook subshell so triggered commands and any consequential subcommands never recurse into user hooks.
