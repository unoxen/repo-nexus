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
| `--gemini` | | boolean | `false` | Enable Google Gemini plugin (maintains `GEMINI.md`, generates skills in `.agents/skills/`). |
| `--codex` | | boolean | `false` | Enable OpenAI Codex plugin (maintains `CODEX.md`, generates skills in `.codex/skills/`). |
| `--windsurf` | | boolean | `false` | Enable Windsurf plugin (maintains `.windsurfrules`, generates skills in `.windsurf/rules/`). |

### Examples
```bash
# Interactive setup
rnex init

# Non-interactive initialization for CI or automated setup
rnex init -y --claude --hooks
```

---

## `rnex sync`

Reconciles workspace configuration, skills, plugins, Git ignore rules, Git hook wrappers, and compiles `.rnex/ai-instructions.md`. `rnex sync` is the single synchronization and reconciliation entrypoint in Repo Nexus.

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
2. Re-verifies `.gitignore` rules from `git.ignore` (defaulting to safe directory-only patterns `**/.rnex*/`, `**/rnex*/`, `repos/`), and ensures `.ignore` contains `!repos/*`.
3. Compiles `.rnex/ai-instructions.md` by combining the base template with active configuration and all enabled plugin `instructions.md` fragments. Writes single strict directive to top-level provider files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, etc.).
4. Syncs core agentic skills from `toolkit/skills/` to `.rnex/skills/` and generates zero-logic User Skills (`rnex-*.md`) in active AI provider directories.
5. Re-syncs enabled plugin assets into `.rnex/plugins/` and member `repos/<name>/.rnex/`.
6. Dispatches plugin lifecycle hooks (`before_sync`, `after_sync`).
7. Reconciles Git hook dispatchers in `.git/hooks/` against declarative `git.hooks` commands.
8. Updates multi-root `.code-workspace` folder mappings if configured.
9. Generates `.rnex/bin/auto-sync.sh` and updates the checksum stamp in `.rnex/sync_stamp`.

---

## `rnex status`

Inspects workspace health and diagnostic information. `rnex status` is **strictly read-only**.

### Syntax
```sh
rnex status
```

### Execution
* **Strictly Read-Only**: Inspects workspace health, active repos, loaded config files (`rnex.yaml` and `.local.rnex.yaml`), git hooks, and plugins.
* **Sync Diagnostics**: Compares current config checksums against `.rnex/sync_stamp` and suggests running `rnex sync` if configuration drift is detected.

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
