---
title: RNEX Lifecycle Hooks
description: Complete reference for RNEX lifecycle hooks, event triggers, configuration syntax, and environment variables.
---

# RNEX Lifecycle Hooks

Repo Nexus includes a built-in event-driven lifecycle hook system configured under the top-level `rnex_hooks:` block in `rnex.yaml` or `.local.rnex.yaml`.

---

## Configuration Syntax

Hooks are defined as a mapping from lifecycle event names to lists of shell commands:

```yaml
rnex_hooks:
  before_sync: []
  after_sync:
    - "rnex plugin karpathy-llm ingest --quiet"
    - "echo 'Workspace synchronized successfully'"

  before_clone: []
  after_clone:
    - "rnex exec npm install"

  before_repo_add: []
  after_repo_add:
    - "echo 'Added repository:' $RNEX_REPO_NAME"

  before_plugin_command: []
  after_plugin_command:
    - "echo 'Finished command:' $RNEX_PLUGIN_COMMAND"
```

Workstation-specific overrides can be added to `.local.rnex.yaml`. If an event list is specified in `.local.rnex.yaml`, its command list takes precedence and overrides that event's commands in `rnex.yaml` (both underscore `after_sync` and hyphenated `after-sync` keys are supported).

---

## Supported Lifecycle Events

| Event Name | Trigger Moment | Command Arguments Received |
|:---|:---|:---|
| `before_init` | Fired before workspace initialization begins. | `[directory]` |
| `after_init` | Fired immediately after workspace initialization finishes. | `[directory]` |
| `before_sync` | Fired before workspace reconciliation begins. | `[flags...]` |
| `after_sync` | Fired after all reconciliation steps (skills, gitignore, hooks) finish. | `[flags...]` |
| `before_clone` | Fired before member repository cloning begins. | |
| `after_clone` | Fired after all missing repositories have cloned. | |
| `before_repo_add` | Fired before adding and cloning a new repository. | `<url> [--name <name>] ...` |
| `after_repo_add` | Fired after a new repository is cloned and registered. | `<url> [--name <name>] ...` |
| `before_repo_remove`| Fired before removing a repository from configuration. | `<name> [--purge]` |
| `after_repo_remove` | Fired after a repository is unregistered and purged. | `<name> [--purge]` |
| `before_repo_set` | Fired before toggling repository status flags. | `<name> [flags...]` |
| `after_repo_set` | Fired after repository flags are updated. | `<name> [flags...]` |
| `before_plugin_enable` | Fired before copying plugin assets into `.rnex/plugins/`. | `<plugin-name>` |
| `after_plugin_enable` | Fired after plugin assets and skills are placed. | `<plugin-name>` |
| `before_plugin_disable`| Fired before running cleanup and pruning plugin assets. | `<plugin-name>` |
| `after_plugin_disable` | Fired after plugin assets are deleted. | `<plugin-name>` |
| `before_plugin_command`| Fired before executing a plugin subcommand. | `<plugin> <cmd> [args...]` |
| `after_plugin_command` | Fired after executing a plugin subcommand. | `<plugin> <cmd> [args...]` |
| `before_exec` | Fired before batch command execution across repositories. | `<cmd...>` |
| `after_exec` | Fired after batch command execution completes. | `<cmd...>` |

---

## Execution Environment & Variables

Hooks execute within a standard subshell (`/bin/sh -e`) inside the workspace root (`RNEX_ROOT`). Any non-zero exit code halts execution immediately, preventing downstream corruption.

### Exported Variables

* `RNEX_ROOT`: Absolute path to the workspace root directory.
* `RNEX_HOOK_EVENT`: Name of the lifecycle event currently executing (e.g. `after_sync`).
* `RNEX_HOOK_ARGS`: Full space-separated string of arguments passed to the event.
* `RNEX_REPO_NAME`: Name of the affected repository (for `repo` events).
* `RNEX_PLUGIN_NAME`: Name of the affected plugin (for `plugin` events).
* `RNEX_PLUGIN_COMMAND`: Name of the executed subcommand (for `plugin_command` events).

### Re-Entrancy Guard
To prevent recursive loops (e.g. `after_sync` executing `rnex sync`), the dispatcher exports `RNEX_HOOK_ACTIVE="<event_name>"` and skips subsequent invocations of the same event until the initial call unwinds.
