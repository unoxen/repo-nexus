# Repo Nexus (`rnex`) CLI Reference Manual

`rnex` is a lightweight, zero-dependency command-line utility built entirely in pure POSIX shell (`/bin/sh`). It orchestrates **Virtual Meta-Repo** workspaces, manages autonomous member repository clones, automates multi-repo Git workflows, and coordinates AI routing instructions without Git submodules.

---

## Table of Contents

- [Overview & Global Options](#overview--global-options)
- [Workspace Lifecycle Commands](#workspace-lifecycle-commands)
  - [`rnex init`](#rnex-init)
  - [`rnex status`](#rnex-status)
  - [`rnex fix` (alias: `sync`)](#rnex-fix-alias-sync)
  - [`rnex update` (alias: `upgrade`)](#rnex-update-alias-upgrade)
  - [`rnex install`](#rnex-install)
  - [`rnex completion`](#rnex-completion)
  - [`rnex version`](#rnex-version)
- [Member Repository Commands](#member-repository-commands)
  - [`rnex add`](#rnex-add)
  - [`rnex clone`](#rnex-clone)
  - [`rnex exec`](#rnex-exec)
  - [`rnex list`](#rnex-list)
  - [`rnex enable`](#rnex-enable)
  - [`rnex disable`](#rnex-disable)
  - [`rnex remove`](#rnex-remove)
  - [`rnex rnex-dir`](#rnex-rnex-dir)
- [Git Hooks Automation Commands](#git-hooks-automation-commands)
  - [`rnex hooks install`](#rnex-hooks-install)
  - [`rnex hooks status`](#rnex-hooks-status)
  - [`rnex hooks uninstall`](#rnex-hooks-uninstall)
- [Plugin Management Commands](#plugin-management-commands)
  - [`rnex plugin list`](#rnex-plugin-list)
  - [`rnex plugin info`](#rnex-plugin-info)
  - [`rnex plugin enable`](#rnex-plugin-enable)
  - [`rnex plugin disable`](#rnex-plugin-disable)
- [Standardized Prompts Catalog](#standardized-prompts-catalog)
- [Environment Variables & Exit Codes](#environment-variables--exit-codes)

---

## Overview & Global Options

### Syntax
```sh
rnex [global-options] <command> [command-options] [arguments]
```

### Global Options

| Option | Shorthand | Description |
|:---|:---|:---|
| `--config <file>` | `-c <file>` | Path to a custom workspace configuration file (e.g. `/path/to/rnex.yaml`). Executes as if running from the directory containing that configuration file. |
| `--help` | `-h` | Display summary help and command usage. |
| `--version` | `-v` | Display the current version of the CLI. |

---

## Workspace Lifecycle Commands

### `rnex init`

Initializes a new Repo Nexus Virtual Meta-Repo workspace.

```sh
rnex init [options] [directory]
```

#### Arguments & Options
- `directory` *(optional)*: Target directory to initialize. Defaults to current working directory (`$PWD`).
- `-y`, `--yes`: Non-interactive mode. Accepts all defaults automatically without prompting.
- `--code-workspace [filename]`: Enable VS Code / Cursor multi-root workspace file generation. Defaults to `<directory-name>.code-workspace` if omitted.
- `--hooks`: Force-enable automated Git hooks setup during initialization.
- `--no-hooks`: Skip Git hooks configuration during initialization.
- `--copilot`: Enable GitHub Copilot integration plugin (mirrors prompts, skills, agents, and instructions to `.github/`).
- `--claude`: Enable Anthropic Claude Code plugin (maintains `CLAUDE.md`, mirrors prompts/skills/agents to `.claude/`).
- `--gemini`: Enable Google Gemini & Antigravity plugin (maintains `GEMINI.md`, mirrors prompts/skills/agents to `.gemini/`).
- `--cursor`: Enable Cursor IDE plugin (maintains `.cursorrules` / `.cursor/rules/`, mirrors prompts/skills/agents to `.cursor/`).
- `--windsurf`: Enable Windsurf IDE plugin (maintains `.windsurfrules`, mirrors prompts/skills/agents to `.windsurf/`).

#### What it does:
1. Creates `rnex.yaml` with schema versioning (`version: <version>`), `repos_dir: ./repos`, and configured defaults.
2. Merges Repo Nexus routing instructions (`<!-- REPO-NEXUS:START -->` ... `<!-- REPO-NEXUS:END -->`) into `AGENTS.md` (or the respective provider file if a provider plugin flag was specified).
3. Creates `./repos/` directory with a tracked `.gitkeep`.
4. Creates `.rnex/`, `.rnex/plugins/`, and copies standardized prompts to `.rnex/prompts/`.
5. Reconciles `.gitignore` to ensure `repos/` and `.local.rnex.yaml` are never tracked by the meta-repo (while keeping `.rnex/` tracked).
6. Generates a multi-root `.code-workspace` file if configured.
7. Prompts to configure automated workspace Git hooks (`core.hooksPath = .rnex/hooks`) if inside a Git repository.
8. Configures and syncs enabled plugins.

#### Examples:
```sh
# Initialize in current directory with interactive prompts (creates AGENTS.md)
rnex init

# Non-interactive initialization for CI or automated setup
rnex init -y

# Initialize for Anthropic Claude Code with automated Git hooks (creates CLAUDE.md)
rnex init -y --claude --hooks

# Initialize with VS Code multi-root workspace support
rnex init --code-workspace my-team.code-workspace
```

---

### `rnex status`

Performs a comprehensive diagnostic and health check on the active workspace.

```sh
rnex status
```

#### What it reports:
- **Configuration & Versions**: Path, version tag, and load status of `rnex.yaml` and `.local.rnex.yaml`.
- **Paths**: Clones directory (`repos_dir`) and primary AI instructions file.
- **Git Integration**: Validation that `.gitignore` ignores `repos/` and local files (while keeping `.rnex/` tracked), and whether `core.hooksPath` points to `.rnex/hooks`.
- **AI Routing Context**: Existence and routing block markers in `AGENTS.md`, `CLAUDE.md`, `.code-workspace`, and prompts catalog (`.rnex/prompts/index.md`).
- **Active Plugins**: List of enabled plugins, scoped versions, and asset directories.
- **Member Repositories**: Every registered repository, enabled/disabled state, clone health, and active Git branch.

---

### `rnex fix` (alias: `sync`)

Reconciles the workspace configuration, instructions, prompts, plugins, and member clones.

```sh
rnex fix [options]
```

#### Options:
- `-y`, `--yes`: Automatically confirm configuration schema upgrades if an older workspace version is detected.
- `-q`, `--quiet`: Quiet mode; suppresses non-error informational messages (used in background Git hooks).
- `--upgrade`: Explicitly triggers version upgrade reconciliation.

#### What it reconciles:
1. **Version Upgrade Check**: If workspace configuration version is older than running CLI, prompts to upgrade non-destructively.
2. **Git Ignore**: Ensures `repos/`, `.rnex/`, and local config files are ignored, stripping legacy counters.
3. **Routing Instructions**: Replaces or inserts the delimited Repo Nexus routing block in `AGENTS.md`, `CLAUDE.md`, etc.
4. **Prompts Synchronization**: Copies standard workflow prompts into `.rnex/prompts/`.
5. **Git Hooks**: Re-syncs hook scripts in `.rnex/hooks/` if active.
6. **Plugins**: Scopes plugin templates, instructions, and rules to `.rnex/plugins/<plugin>/`.
7. **Member Repositories**: Ensures member `.rnex/` directories exist where enabled.
8. **VS Code / Cursor Workspace**: Regenerates folder mappings in the `.code-workspace` file.

---

### `rnex update` (alias: `upgrade`)

Safely updates an existing workspace's configuration schema and routing instructions to match the currently installed CLI version as part of the unified `rnex fix` reconciliation process.

```sh
rnex update [-y]
```

- Compares `version:` in `rnex.yaml` with the running `rnex` CLI version.
- Non-destructively upgrades the configuration schema and inserts newly introduced keys while strictly preserving existing comments, indentation, and repository declarations.
- Reconciles AI instructions, active provider plugins, and workspace routing in a single execution.
- `rnex update` and `rnex upgrade` are aliases that invoke the unified `rnex fix` workflow.

---

### `rnex install`

Installs the `rnex` and `repo-nexus` executables into a system bin directory.

```sh
rnex install [bin-directory]
```

- Default directory: `~/.local/bin`
- Creates symlinks for both `rnex` and `repo-nexus`.

---

### `rnex completion`

Generates shell completion scripts for Tab auto-completion.

```sh
rnex completion <bash|zsh|fish>
```

#### Setup:
- **Zsh** (in `~/.zshrc`):
  ```sh
  source <(rnex completion zsh)
  ```
- **Bash** (in `~/.bashrc`):
  ```sh
  source <(rnex completion bash)
  ```
- **Fish** (in `~/.config/fish/config.fish`):
  ```sh
  rnex completion fish | source
  ```

---

### `rnex version`

Outputs the version number of the `rnex` CLI.

```sh
rnex version
# or:
rnex -v
```

---

## Member Repository Commands

### `rnex add`

Registers a repository in the workspace configuration and immediately clones it into `./repos/<name>`.

```sh
rnex add [options] <name> <git-url>
```

#### Options:
- `--local`: Registers the repository in `.local.rnex.yaml` instead of `rnex.yaml` (machine-specific, not committed to Git).
- `--disabled`: Registers the repository but flags it `enabled: false` (not cloned until enabled).
- `--no-rnex-dir`: Sets `rnex_dir: false`, leaving the member repository completely untouched without a member `.rnex/` directory.

#### Examples:
```sh
# Register and clone a team repository
rnex add backend git@github.com:myorg/backend-api.git

# Register a private experiment on local machine only
rnex add --local experiment git@github.com:myorg/exp.git
```

---

### `rnex clone`

Clones any registered, enabled repository that is currently missing on disk.

```sh
rnex clone
```

Teammates who clone the meta-repo run `rnex clone` to fetch all member repositories in a single step.

---

### `rnex exec`

Executes an arbitrary shell command across all active (enabled) member repositories in parallel or sequential order.

```sh
rnex exec <command...>
```

#### Examples:
```sh
# Check Git status across all member repositories
rnex exec git status -s

# Pull latest commits on active branch across all repos
rnex exec git pull --ff-only

# Run tests in all member repos
rnex exec npm test
```

---

### `rnex list`

Lists all registered member repositories with their clone status, active Git branch, and member `.rnex` state.

```sh
rnex list
```

---

### `rnex enable` & `rnex disable`

Toggles whether a member repository is active in the workspace.

```sh
# Enable a repository
rnex enable [--local] <name>

# Disable a repository
rnex disable [--local] <name>
```

- When disabled, a repository is excluded from `rnex clone`, `rnex exec`, and AI agent routing.
- `--local`: Writes the override into `.local.rnex.yaml`, allowing individual developers to disable repositories on their workstation without affecting teammates.

---

### `rnex remove`

Unregisters a member repository from configuration and deletes its clone from disk.

```sh
rnex remove <name>
```

Prompts for interactive confirmation before deleting files.

---

### `rnex rnex-dir`

Toggles `.rnex/` directory integration inside a specific member repository (`repos/<name>/.rnex/`).

```sh
rnex rnex-dir <enable|disable> <name>
```

---

## Git Hooks Automation Commands

Repo Nexus manages workspace-level Git hooks via `git config core.hooksPath .rnex/hooks` and configuration in `rnex.yaml` (`git_hooks: true|false`). The hooks are native shell scripts that dynamically evaluate configuration triggers in `rnex.yaml` and `.local.rnex.yaml`.

```sh
rnex hooks <install|uninstall|status> [--local]
```

### Configuration (`rnex.yaml` / `.local.rnex.yaml`)
```yaml
# Enable or disable automated Git hooks
git_hooks: true   # default: true (when in a Git repository)
```
- When `git_hooks: true`, `rnex fix` ensures hooks are installed and up to date.
- When `git_hooks: false`, `rnex fix` disables and uninstalls hooks from Git.
- Overrides can be placed in `.local.rnex.yaml` to disable hooks locally without modifying team config.

### Subcommands

#### `rnex hooks install [--local]`
Installs native hook dispatchers into `.rnex/hooks/`, sets `core.hooksPath = .rnex/hooks`, and records `git_hooks: true` in `rnex.yaml` (or `.local.rnex.yaml` if `--local` is passed):
- **`post-merge`**: Automatically runs `rnex fix -y --quiet` whenever you run `git pull` or merge upstream changes, ensuring new repositories or plugin additions sync instantly.
- **`post-commit`**: Evaluates `lint_trigger: git-post-commit`. If `/raw/` or `/wiki/` files were committed, alerts the user to run maintenance workflows.
- **`pre-commit`**: Evaluates `lint_trigger: git-pre-commit`. Validates staged files before committing.
- **`pre-push`**: Evaluates `lint_trigger: git-pre-push`. Validates changes before pushing to remote.

#### `rnex hooks status`
Displays the configuration setting (`git_hooks: true/false`), active `core.hooksPath`, installed hook scripts, and plugin triggers detected in `rnex.yaml`.

#### `rnex hooks uninstall [--local]`
Unsets `core.hooksPath` in Git configuration, removes `.rnex/hooks/`, and records `git_hooks: false` in `rnex.yaml` (or `.local.rnex.yaml` if `--local` is passed).

---

## Plugin Management Commands

Repo Nexus features a modular plugin architecture where plugin rules, instructions, and templates are scoped strictly under `.rnex/plugins/<plugin-name>/`.

For complete documentation on built-in plugins (Copilot, Claude, Gemini, Cursor, Windsurf, Karpathy LLM), see the [**Repo Nexus Plugins Guide**](plugins/README.md).

```sh
rnex plugin <list|info|enable|disable> [options] [name]
```

### Subcommands
- **`rnex plugin list`**: Displays all available plugins distributed with `rnex` and highlights enabled plugins.
- **`rnex plugin info <name>`**: Shows description, version, configurable options, scoped directory, and external template paths for a plugin.
- **`rnex plugin enable [--local] <name>`**: Enables a plugin in `rnex.yaml` (or `.local.rnex.yaml` with `--local`), copies assets to `.rnex/plugins/<name>/`, and reconciles workspace files.
- **`rnex plugin disable [--local] <name>`**: Removes plugin assets from `.rnex/plugins/<name>/` and disables the plugin in `rnex.yaml` (or overrides with `enabled: false` in `.local.rnex.yaml` with `--local`).

---

## Standardized Prompts Catalog

Repo Nexus provides a standardized suite of operational prompt templates in `toolkit/prompts/` that sync to `.rnex/prompts/` during `rnex fix` or `rnex init`.

AI assistants navigate workflows via the catalog index at `.rnex/prompts/index.md`:

| Prompt File | Purpose |
|:---|:---|
| [`index.md`](../toolkit/prompts/index.md) | Master catalog indexing all available workflows and prompts. |
| [`rnex-cross-repo-feature.md`](../toolkit/prompts/rnex-cross-repo-feature.md) | Structured workflow for implementing cross-cutting features across multiple repos. |
| [`rnex-workspace-audit.md`](../toolkit/prompts/rnex-workspace-audit.md) | Health, git dirty status, branch tracking, and configuration audit workflow. |
| [`rnex-wiki-ingest.md`](../toolkit/prompts/rnex-wiki-ingest.md) | Autonomous ingestion of source docs from `/raw/` into Karpathy LLM Wiki pages. |
| [`rnex-wiki-lint.md`](../toolkit/prompts/rnex-wiki-lint.md) | Link validation, backlink (`mentioned_in`) recalculation, and index rebuilding. |

---

## Environment Variables & Exit Codes

### Environment Variables
- `RNEX_CONFIG`: Overrides the default `rnex.yaml` configuration file path.
- `NO_COLOR`: Disables ANSI color output when set.

### Exit Codes
- `0`: Success.
- `1`: General error (e.g. invalid arguments, missing workspace configuration, command failure).
