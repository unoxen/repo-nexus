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
| `--claude` | | boolean | `false` | Enable Claude Code plugin (maintains `CLAUDE.md`, generates skills in `.claude/skills/`). |
| `--cursor` | | boolean | `false` | Enable Cursor plugin (maintains `.cursorrules`, generates skills in `.cursor/rules/`). |
| `--gemini` | | boolean | `false` | Enable Google Gemini plugin (maintains `GEMINI.md`, generates skills in `.gemini/skills/`). |
| `--windsurf` | | boolean | `false` | Enable Windsurf plugin (maintains `.windsurfrules`, generates skills in `.windsurf/rules/`). |

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

## `rnex sync`

Reconciles workspace configuration, skills, plugins, `.rnex/` harness directories, and compiles `.rnex/ai-instructions.md`. `rnex sync` is the sole reconciliation command in Repo Nexus (`rnex fix` and `rnex status --fix` are removed).

### Syntax
```sh
rnex sync [options]
```

### Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `--yes` | `-y` | boolean | `false` | Automatically confirm schema upgrades if prompted. |
| `--quiet` | `-q` | boolean | `false` | Quiet mode; suppresses non-error informational messages (ideal for hooks). |

### Reconciliation Actions
1. Upgrades configuration schema non-destructively if an older version is detected.
2. Re-verifies `.gitignore` rules for `repos/` and local configs, and ensures `.ignore` contains `!repos/*`.
3. Compiles `.rnex/ai-instructions.md` by combining the base template with active configuration and all enabled plugin `instructions.md` fragments. Writes single strict directive to top-level provider files (`AGENTS.md`, `CLAUDE.md`, etc.).
4. Syncs core agentic skills from `toolkit/skills/` to `.rnex/skills/` and generates zero-logic User Skills (`rnex-*.md`) in active AI provider directories.
5. Re-syncs enabled plugin assets into `.rnex/plugins/` and member `repos/<name>/.rnex/`.
6. Dispatches plugin lifecycle hooks (`before_sync`, `after_sync`).
7. Reconciles automated Git hooks in `.rnex/hooks/` against `git_hooks` config.
8. Re-creates member `.rnex/` scaffolding in active repositories (`rnex_dir: true`).
9. Updates multi-root `.code-workspace` folder mappings if configured.
10. Generates `.rnex/bin/auto-sync.sh` and updates the checksum stamp in `.rnex/.sync_stamp`.

---

## `rnex status`

Inspects workspace health and diagnostic information. `rnex status` is **strictly read-only** with no `--fix` flag.

### Syntax
```sh
rnex status
```

### Execution
* **Strictly Read-Only**: Inspects workspace health, active repos, loaded config files (`rnex.yaml` and `.local.rnex.yaml`), git hooks, and plugins.
* **Sync Diagnostics**: Compares current config checksums against `.rnex/.sync_stamp` and suggests running `rnex sync` if configuration drift is detected.

---

## `rnex update` (alias: `upgrade`)

Runs version verification and invokes `rnex sync` to upgrade workspace configuration and routing instructions to match the installed CLI version.

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
`rnex update` delegates directly to `rnex sync`:
* **Upfront Version Diagnostics**: Compares `version:` in `rnex.yaml` against the installed CLI version. If already matching, it reports that the workspace is up to date.
* **Unified Reconciliation**: Delegates directly to `rnex sync`, ensuring configuration schema upgrades, instruction updates (`AGENTS.md`, `.rnex/ai-instructions.md`), prompts, and plugin reconciliation occur in a single, idempotent pass.
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
