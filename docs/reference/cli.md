---
title: CLI Reference
description: Complete reference for all Repo Nexus commands, rnex repo subcommands, rnex plugin operations, and global flags.
---

# CLI Reference

`rnex` is a zero-dependency CLI written entirely in pure POSIX `/bin/sh`. It orchestrates Virtual Meta-Repo workspaces, single-repository management under `rnex repo`, batch operations across `./repos/`, and extensible plugin commands.

---

## Global Options

```sh
rnex [global-options] <command> [command-options] [arguments]
```

| Flag | Shorthand | Type | Description |
|:---|:---|:---|:---|
| `--config <file>` | `-c <file>` | string | Path to custom workspace configuration file (e.g. `/path/to/rnex.yaml`). Executes as if running from that file's directory. |
| `--help` | `-h` | boolean | Display command usage and help summary. |
| `--version` | `-v` | boolean | Output CLI version. |

---

## Workspace Commands

### `rnex init`
Initializes a new Repo Nexus Virtual Meta-Repo workspace.

```sh
rnex init [options] [directory]
```

* `-y`, `--yes`: Non-interactive mode; accepts all defaults automatically.
* `--code-workspace`: Enable VS Code multi-root workspace file (pass string for custom file name).
* `--hooks`: Force-enable automated Git hooks setup during initialization.
* `--no-hooks`: Skip Git hooks configuration during initialization.
* `--claude`: Enable Claude Code plugin (`CLAUDE.md`, `.claude/skills/`).
* `--cursor`: Enable Cursor plugin (`.cursorrules`, `.cursor/rules/`).
* `--codex`: Enable OpenAI Codex plugin (`CODEX.md`, `.codex/skills/`).
* `--gemini`: Enable Google Gemini plugin (`GEMINI.md`, `.agents/skills/`).
* `--windsurf`: Enable Windsurf plugin (`.windsurfrules`, `.windsurf/rules/`).

### `rnex sync`
Single reconciliation command: syncs skills, plugins, Git hooks & ignore rules, and compiles `.rnex/ai-instructions.md`.

```sh
rnex sync [options]
```

* `-y`, `--yes`: Automatically confirm non-destructive schema upgrades if prompted.
* `-q`, `--quiet`: Quiet mode; suppresses non-error informational messages (ideal for hooks).

### `rnex status`
Strictly read-only diagnostic report: inspects workspace health, active repos, loaded config, hooks, and plugins.

```sh
rnex status
```

### `rnex clone`
Clones all enabled member repositories declared in configuration that are missing from `./repos/`.

```sh
rnex clone
```

### `rnex list`
Prints a formatted table of all registered repositories with state, clone status, branch, and readonly flag.

```sh
rnex list
```

### `rnex exec`
Runs an arbitrary shell command sequentially across all enabled member repositories.

```sh
rnex exec <command...>
```

* Preserves and returns exact non-zero exit codes upon command failure.
* Exports `RNEX_REPO_NAME`, `RNEX_REPO_PATH`, `RNEX_REPO_BRANCH`.

### `rnex install`
Installs and symlinks `rnex` and `repo-nexus` to `~/.local/bin` (or custom directory).

```sh
rnex install [bin-dir]
```

### `rnex completion`
Generates shell auto-completion scripts.

```sh
rnex completion <bash|zsh|fish>
```

---

## Single-Repository Commands (`rnex repo`)

Manage individual member repositories without affecting the entire workspace.

### `rnex repo add`
Registers a repository in configuration and clones it into `./repos/<name>`.

```sh
rnex repo add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]
```

* `<url>`: Git repository URL or local repository path.
* `--name <name>`: Custom repository name (inferred from URL basename if omitted).
* `--branch <branch>`: Initial Git branch to checkout.
* `--local`: Register in `.local.rnex.yaml` instead of `rnex.yaml`.
* `--disabled`: Register with `enabled: false`.
* `--readonly`: Register with `readonly: true`.

### `rnex repo remove`
Unregisters a repository from configuration.

```sh
rnex repo remove <name> [--purge] [-y|--yes]
```

* `--purge`: Also deletes the repository directory from disk (`./repos/<name>`).
* `-y`, `--yes`: Skip confirmation prompt when purging.

### `rnex repo set`
Updates repository state and flags.

```sh
rnex repo set <name> [--enable|--disable] [--readonly|--readwrite] [--global|--local]
```

* `--enable` / `--disable`: Toggle active state.
* `--readonly` / `--readwrite`: Toggle read-only flag.
* `--local` / `--global`: Write to `.local.rnex.yaml` (default) or `rnex.yaml`.

### `rnex repo clone`
Clones a single registered member repository into `./repos/<name>`.

```sh
rnex repo clone <name>
```

### `rnex repo status`
Inspects configuration, branch, and Git working tree status for a specific repository.

```sh
rnex repo status <name>
```

### `rnex repo exec`
Executes an arbitrary shell command targeting an individual repository.

```sh
rnex repo exec <name> <command...>
```

### `rnex repo list`
Alias for `rnex list`.

---

## Plugin Commands (`rnex plugin`)

Manage plugins and execute plugin-provided CLI commands.

### `rnex plugin list`
Lists all available, enabled, and disabled plugins along with their declared CLI commands.

```sh
rnex plugin list
```

### `rnex plugin info`
Displays detailed metadata, options, and commands for a plugin.

```sh
rnex plugin info <name>
```

### `rnex plugin enable`
Enables a plugin in configuration and copies assets to `.rnex/plugins/<name>/`.

```sh
rnex plugin enable [--local] <name>
```

### `rnex plugin disable`
Disables a plugin, executes its cleanup hook, and prunes scoped assets.

```sh
rnex plugin disable [--local] <name>
```

### `rnex plugin update`
Re-synchronizes and updates enabled plugins from toolkit sources.

```sh
rnex plugin update [<name>]
```

### `rnex plugin <name> <command>`
Executes a subcommand exposed by an enabled plugin:

```sh
rnex plugin <name> <command> [options...]
```

* Example: `rnex plugin karpathy-llm ingest --source docs/notes.md`
* Example: `rnex plugin karpathy-llm lint --strict`
* Shorthand execution: `rnex plugin <command> [options...]` when `<command>` is unique across enabled plugins.
