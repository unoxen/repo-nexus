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
rnex add [options] [<name>] <git-url>
```

### Parameters & Options
| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `<name>` | string | *(optional)* | Short identifier for repository (folder name in `./repos/`). If omitted, defaults to the last path component of `<git-url>` (without `.git` suffix). |
| `<git-url>` | string | *(required)* | Remote Git clone URL (SSH or HTTPS) or local repository path. |
| `--local` | boolean | `false` | Registers repository in `.local.rnex.yaml` instead of team `rnex.yaml`. |
| `--disabled` | boolean | `false` | Registers repository with `enabled: false` (skips immediate clone). |
| `--readonly` | boolean | `false` | Sets `readonly: true`; designates repository as reference-only / information-only. |

### Examples
```bash
# Register and clone a service using explicit name
rnex add backend git@github.com:myorg/backend-api.git

# Register and clone without providing a name (name defaults to 'web-app')
rnex add https://github.com/myorg/web-app.git

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

Outputs a formatted table of all registered member repositories, their active branches, clone state, and readonly status.

### Syntax
```sh
rnex list
```

```text
NAME               STATE      CLONED   BRANCH         READONLY   URL
----               -----      ------   ------         --------   ---
backend            enabled    cloned   main           false      git@github.com:myorg/backend-api.git
frontend           enabled    cloned   develop        false      git@github.com:myorg/frontend-web.git
docs-reference     enabled    cloned   main           true       git@github.com:myorg/docs-ref.git
analytics          disabled   missing  -              false      git@github.com:myorg/analytics.git
```

---

## `rnex readonly`

Toggles whether a member repository is read-only (`readonly: true`).

### Syntax
```sh
rnex readonly <enable|disable> <name> [--local]
```

* When marked read-only, AI assistants use this repository strictly for information, code exploration, and schema references without editing files or committing code.
* Pass `--local` to persist the toggle in `.local.rnex.yaml` without modifying team-wide `rnex.yaml`.

```bash
# Mark docs-reference as read-only across workspace
rnex readonly enable docs-reference

# Mark an internal dependency as read-only locally
rnex readonly enable --local shared-libs
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

## `rnex rnex-dir` *(Legacy / Deprecated)*

Under the lazy/on-demand model, member repositories remain completely clean by default and `.rnex/` is only created when an active plugin requires member-level state. `rnex rnex-dir` is maintained for backward compatibility.

### Syntax
```sh
rnex rnex-dir <enable|disable> <name>
```

* `rnex rnex-dir disable <name>` cleanly prunes orphaned `.rnex/` folders from member repositories.
