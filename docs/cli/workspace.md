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
| `--claude` | | boolean | `false` | Enable Claude Code plugin (mirrors prompts to `.claude/commands/`). |
| `--copilot` | | boolean | `false` | Enable GitHub Copilot plugin (mirrors prompts to `.github/prompts/`). |
| `--cursor` | | boolean | `false` | Enable Cursor plugin (mirrors prompts to `.cursor/prompts/`). |
| `--gemini` | | boolean | `false` | Enable Google Gemini plugin (mirrors prompts to `.gemini/prompts/`). |
| `--windsurf` | | boolean | `false` | Enable Windsurf plugin (mirrors prompts to `.windsurf/prompts/`). |

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
* **AI Routing**: Status of universal `AGENTS.md`, `.rnex/skills/`, `.rnex/workflows/`, and provider prompts directories.
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

## `rnex sync`

Synchronizes workspace assets, validates configuration, and audits or reconciles AI routing instructions, skills, workflows, active plugins, and member clones.

- **Audit Mode (Default)**: When run without `--fix`, inspects workspace configuration, Git ignores, routing blocks, plugin assets, and member repositories, logging any issues or inconsistencies without mutating files.
- **Reconcile Mode (`--fix`)**: Reconciles configuration schema, updates instruction files, synchronizes skills/workflows, mirrors operational prompts, and fixes inconsistencies.

### Syntax
```sh
rnex sync [options]
```

### Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `--fix` | `-f` | boolean | `false` | Apply reconciliation fixes across workspace, routing, plugins, and repos. |
| `--yes` | `-y` | boolean | `false` | Automatically confirm schema upgrades if prompted (used with `--fix`). |
| `--quiet` | `-q` | boolean | `false` | Quiet mode; suppresses non-error informational messages (ideal for hooks). |
| `--upgrade` | | boolean | `false` | Explicitly trigger version upgrade reconciliation (implies `--fix`). |

### Reconciliation Actions (with `--fix`)
1. Upgrades configuration schema non-destructively if an older version is detected.
2. Re-verifies `.gitignore` rules for `repos/` and local configs, and ensures `.ignore` contains `!repos/*`.
3. Inserts or updates delimited routing blocks in universal `AGENTS.md` and active provider instruction files (`CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`).
4. Syncs base workflows to `.rnex/workflows/` and base skills to `.rnex/skills/`, purging any legacy `.rnex/prompts/`.
5. Mirrors operational prompts to enabled AI providers (`.github/prompts/`, `.claude/commands/`, etc.).
6. Re-syncs enabled plugin assets into `.rnex/plugins/` and member `repos/<name>/.rnex/`.
7. Reconciles automated Git hooks in `.rnex/hooks/` against `git_hooks` config.
8. Re-creates member `.rnex/` scaffolding in active repositories.
9. Updates multi-root `.code-workspace` folder mappings if configured.

---

## `rnex update` (alias: `upgrade`)

Runs version verification and invokes the unified `rnex sync --fix` reconciliation engine to upgrade workspace configuration and routing instructions to match the installed CLI version.

### Syntax
```sh
rnex update [options]
rnex upgrade [options]
```

### Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `--yes` | `-y` | boolean | `false` | Automatically confirm schema upgrades if prompted. |
| `--quiet` | `-q` | boolean | `false` | Suppress non-error informational messages. |

### Relationship with `rnex sync`
`rnex update` is part of the `rnex sync` command family:
* **Upfront Version Diagnostics**: Compares `version:` in `rnex.yaml` against the installed CLI version. If already matching, it reports that the workspace is up to date.
* **Unified Reconciliation**: Delegates directly to `rnex sync --fix`, ensuring configuration schema upgrades, instruction updates (`AGENTS.md`, provider files), skills/workflows sync, and plugin reconciliation occur in a single, idempotent pass.
* **Non-Destructive Migration**: Upgrades schema keys while preserving comments, indentation, and custom configurations.

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
