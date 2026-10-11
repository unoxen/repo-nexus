---
title: Workspace Commands
description: CLI reference for rnex workspace lifecycle commands including init, status, fix, sync, update, completion, and install.
---

# Workspace Commands

Workspace commands manage the meta-repo configuration, AI routing files, health diagnostics, and environment integrations.

---

## `rnex init`

Initializes a new Repo Nexus Virtual Meta-Repo workspace.

### Syntax
```sh
rnex init [options] [directory]
```

### Parameters & Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `directory` | | string | `$PWD` | Target directory to initialize. |
| `--yes` | `-y` | boolean | `false` | Non-interactive mode; accepts all defaults automatically. |
| `--code-workspace` | | boolean \| string | `false` | Enable VS Code multi-root workspace file. Pass string for custom name. |
| `--hooks` | | boolean | `true` (if git) | Force-enable automated Git hooks setup during initialization. |
| `--no-hooks` | | boolean | `false` | Skip Git hooks configuration during initialization. |
| `--claude` | | boolean | `false` | Enable Claude Code plugin (`CLAUDE.md` and `.claude/`). |
| `--copilot` | | boolean | `false` | Enable GitHub Copilot plugin (`.github/`). |
| `--cursor` | | boolean | `false` | Enable Cursor plugin (`.cursorrules` and `.cursor/rules/`). |
| `--gemini` | | boolean | `false` | Enable Google Gemini plugin (`GEMINI.md` and `.gemini/`). |
| `--windsurf` | | boolean | `false` | Enable Windsurf plugin (`.windsurfrules` and `.windsurf/`). |

### Examples
```bash
# Interactive setup
rnex init

# Non-interactive initialization for CI or automated setup
rnex init -y --claude --hooks
```

---

## `rnex status`

Performs comprehensive diagnostic and health checks across the workspace.

### Syntax
```sh
rnex status
```

### What It Reports
* **Configuration State**: Location and schema version of `rnex.yaml` and `.local.rnex.yaml`.
* **Git Status**: Validation that `.gitignore` ignores `repos/` and local files, and whether `core.hooksPath` points to `.rnex/hooks`.
* **AI Routing**: Existence of delimited routing blocks in `AGENTS.md`, `CLAUDE.md`, etc.
* **Member Clones**: Health, branches, and `.rnex` state of every member repository.

```bash
rnex status
```

```text
[rnex] Workspace root: /workspace
[rnex] Config: rnex.yaml (.local.rnex.yaml loaded)
[rnex] Repositories: 2 active, 0 disabled
```

---

## `rnex fix` (alias: `sync`)

Reconciles workspace configuration, AI routing blocks, prompts catalog, active plugins, and member clones.

### Syntax
```sh
rnex fix [options]
rnex sync [options]
```

### Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `--yes` | `-y` | boolean | `false` | Automatically confirm schema upgrades if prompted. |
| `--quiet` | `-q` | boolean | `false` | Quiet mode; suppresses non-error informational messages (ideal for hooks). |
| `--upgrade` | | boolean | `false` | Explicitly trigger version upgrade reconciliation. |

### Reconciliation Actions
1. Upgrades configuration schema non-destructively if older version detected.
2. Re-verifies `.gitignore` rules for `repos/` and local configs.
3. Inserts or updates delimited routing blocks (`<!-- REPO-NEXUS:START -->` ... `<!-- REPO-NEXUS:END -->`).
4. Syncs standardized workflow prompts into `.rnex/prompts/`.
5. Re-syncs enabled plugin assets into `.rnex/plugins/` and member `repos/<name>/.rnex/`.

---

## `rnex update` (alias: `upgrade`)

Safely updates an existing workspace's configuration schema and routing instructions to match the currently installed CLI version.

### Syntax
```sh
rnex update [-y]
rnex upgrade [-y]
```

* Upgrades configuration schema without wiping comments or indentation.
* Reconciles AI instructions and active provider plugins in a single run.

---

## `rnex install`

Symlinks the `rnex` and `repo-nexus` executables into a user or system bin directory.

### Syntax
```sh
rnex install [bin-directory]
```

* Default target: `~/.local/bin`
* Creates symlinks for both `rnex` and `repo-nexus`.

---

## `rnex completion`

Generates shell auto-completion scripts.

### Syntax
```sh
rnex completion <bash|zsh|fish>
```

::: code-group

```sh [Zsh]
# Add to ~/.zshrc
source <(rnex completion zsh)
```

```sh [Bash]
# Add to ~/.bashrc
source <(rnex completion bash)
```

```sh [Fish]
# Add to ~/.config/fish/config.fish
rnex completion fish | source
```

:::

---

## `rnex version`

Prints the installed version of `rnex`.

```bash
rnex version
# or:
rnex -v
```
