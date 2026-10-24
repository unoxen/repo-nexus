---
title: Member Repository Commands
description: CLI reference for managing member repositories in Repo Nexus via rnex repo subcommands, rnex clone, and rnex list.
---

# Member Repository Commands

Member repository commands register, clone, configure, inspect, and execute commands across individual Git repositories managed under `./repos/`.

---

## Single-Repository Operations (`rnex repo`)

All operations targeting a single member repository are namespaced under `rnex repo`.

### `rnex repo add`

Registers a repository in configuration and clones it into `./repos/<name>`.

#### Syntax
```sh
rnex repo add <git-url> [options]
```

#### Parameters & Options
| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `<git-url>` | string | *(required)* | Remote Git clone URL (SSH or HTTPS) or local repository path. |
| `--name <name>` | string | *(optional)* | Short identifier for repository (folder name in `./repos/`). Defaults to the repository name from `<git-url>`. |
| `--branch <branch>` | string | *(optional)* | Branch to track and checkout during initial clone. |
| `--local` | boolean | `false` | Registers repository in `.local.rnex.yaml` instead of team `rnex.yaml`. |
| `--disabled` | boolean | `false` | Registers repository with `enabled: false` (skips immediate clone). |
| `--readonly` | boolean | `false` | Sets `readonly: true`; designates repository as reference-only. |

#### Examples
```bash
# Register and clone a service using explicit name and branch
rnex repo add git@github.com:myorg/backend-api.git --name backend --branch develop

# Register and clone without providing a name (name defaults to 'web-app')
rnex repo add https://github.com/myorg/web-app.git

# Register a private experiment on workstation only
rnex repo add --local git@github.com:myorg/exp.git --name experiment
```

---

### `rnex repo remove`

Unregisters a member repository from configuration and deletes its clone from `./repos/<name>`.

#### Syntax
```sh
rnex repo remove <name> [options]
```

#### Options
| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--force` | boolean | `false` | Remove repository even if uncommitted changes or untracked files exist. |

::: danger Destructive Operation
`rnex repo remove` deletes the target repository folder from disk. Always ensure you have pushed any working branches or uncommitted changes to remote before removing.
:::

---

### `rnex repo set`

Configures options for an individual member repository, such as enabling/disabling or setting read-only mode.

#### Syntax
```sh
rnex repo set <name> [options]
```

#### Options
| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--enable` | boolean | `false` | Enable the repository (include in `rnex clone`, `rnex exec`, and AI routing). |
| `--disable` | boolean | `false` | Disable the repository (exclude from batch clone, execution, and routing). |
| `--readonly` | boolean | `false` | Mark repository as read-only (information-only for AI assistants). |
| `--readwrite` | boolean | `false` | Mark repository as read-write. |
| `--local` | boolean | `false` | Apply setting as a workstation override in `.local.rnex.yaml`. |

#### Examples
```bash
# Disable a service across the workspace
rnex repo set analytics --disable

# Mark a reference repo as read-only locally
rnex repo set docs-ref --readonly --local

# Re-enable a disabled service
rnex repo set backend --enable
```

---

### `rnex repo clone`

Clones a single registered member repository into `./repos/<name>`.

#### Syntax
```sh
rnex repo clone <name>
```

#### Examples
```bash
rnex repo clone backend
```

---

### `rnex repo status`

Inspects current Git status, active branch, dirty working tree, and configuration flags for a specific member repository.

#### Syntax
```sh
rnex repo status <name>
```

#### Examples
```bash
rnex repo status backend
```

---

### `rnex repo exec`

Executes an arbitrary shell command specifically inside the member repository directory (`./repos/<name>`).

#### Syntax
```sh
rnex repo exec <name> <command...>
```

#### Examples
```bash
# Run tests inside the backend repository
rnex repo exec backend npm test

# Check Git log in the frontend repository
rnex repo exec frontend git log -3 --oneline
```

---

## Workspace-Level Repository Commands

These commands operate across all member repositories declared in the workspace configuration.

### `rnex clone`

Clones all registered, enabled repositories that are currently missing from disk.

#### Syntax
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
Teammates onboarding onto the meta-repo run `rnex clone` to fetch all member repositories in a single command.
:::

---

### `rnex list`

Outputs a formatted table of all registered member repositories, their active branches, clone state, and readonly status.

#### Syntax
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
