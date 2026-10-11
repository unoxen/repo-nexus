---
title: Member Repository Commands
description: CLI reference for managing member repositories in Repo Nexus, including add, clone, list, enable, disable, remove, and rnex-dir.
---

# Member Repository Commands

Member repository commands register, clone, toggle, and manage individual git repositories managed under `./repos/`.

---

## `rnex add`

Registers a repository in configuration and immediately clones it into `./repos/<name>`.

### Syntax
```sh
rnex add [options] <name> <git-url>
```

### Parameters & Options
| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `<name>` | string | *(required)* | Short identifier for repository (used as folder name in `./repos/`). |
| `<git-url>` | string | *(required)* | Remote Git clone URL (SSH or HTTPS). |
| `--local` | boolean | `false` | Registers repository in `.local.rnex.yaml` instead of team `rnex.yaml`. |
| `--disabled` | boolean | `false` | Registers repository with `enabled: false` (skips immediate clone). |
| `--no-rnex-dir` | boolean | `false` | Sets `rnex_dir: false`, leaving member repository completely untouched. |

### Examples
```bash
# Register and clone a shared team service
rnex add backend git@github.com:myorg/backend-api.git

# Register a private experiment on local machine only
rnex add --local experiment git@github.com:myorg/exp.git
```

---

## `rnex clone`

Clones all registered, enabled repositories missing on disk.

### Syntax
```sh
rnex clone
```

```bash
rnex clone
```

```text
[rnex] Cloning backend into ./repos/backend...
Cloning into './repos/backend'...
[rnex] All member repositories cloned successfully.
```

::: tip Ideal for Onboarding
Teammates cloning the meta-repo run `rnex clone` to fetch all member repositories in a single command.
:::

---

## `rnex list`

Outputs a formatted table of all registered member repositories, their active branches, clone state, and `.rnex` directory status.

### Syntax
```sh
rnex list
```

```text
Name       Enabled  Cloned  Branch  rnex-dir  URL
backend    yes      yes     main    yes       git@github.com:myorg/backend-api.git
frontend   yes      yes     develop yes       git@github.com:myorg/frontend-web.git
analytics  no       no      -       no        git@github.com:myorg/analytics.git
```

---

## `rnex enable` & `rnex disable`

Toggles whether a member repository is active in workspace operations.

### Syntax
```sh
rnex enable [--local] <name>
rnex disable [--local] <name>
```

* When disabled, a repository is excluded from `rnex clone`, `rnex exec`, and AI agent routing.
* Pass `--local` to persist the toggle in `.local.rnex.yaml` without modifying team-wide `rnex.yaml`.

```bash
# Disable a memory-heavy service locally
rnex disable --local monolith
```

---

## `rnex remove`

Unregisters a member repository from configuration and deletes its clone from `./repos/<name>`.

### Syntax
```sh
rnex remove <name>
```

::: danger Destructive Operation
`rnex remove` deletes the target repository folder from disk. Always ensure you have pushed any working branches or uncommitted changes to remote before confirming deletion.
:::

---

## `rnex rnex-dir`

Toggles member-level context projection inside `repos/<name>/.rnex/`.

### Syntax
```sh
rnex rnex-dir <enable|disable> <name>
```

* When enabled, workspace prompts and plugin context are projected into `repos/<name>/.rnex/` for localized AI assistants.
* When disabled, the repository root remains completely pristine.
