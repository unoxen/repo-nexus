---
title: Workspace Lifecycle
description: Detailed guide for initializing, reconciling, inspecting, and managing the Repo Nexus workspace lifecycle.
---

# Workspace Lifecycle

Repo Nexus provides a declarative, deterministic lifecycle for multi-repository workspaces. All workspace state flows from `rnex.yaml` and `.local.rnex.yaml`, reconciled through `rnex sync`.

---

## 1. Initialization (`rnex init`)

Initializes a new Repo Nexus Virtual Meta-Repo workspace.

### Syntax
```sh
rnex init [options] [directory]
```

### Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `directory` | | string | `$PWD` | Target directory to initialize. |
| `--yes` | `-y` | boolean | `false` | Non-interactive mode; accepts all defaults automatically. |
| `--code-workspace` | | boolean \| string | `false` | Enable VS Code multi-root workspace file. Pass string for custom name. |
| `--hooks` | | boolean | `true` (if git) | Force-enable automated Git hooks setup during initialization. |
| `--no-hooks` | | boolean | `false` | Skip Git hooks configuration during initialization. |
| `--copilot` | | boolean | `false` | Enable GitHub Copilot plugin (`.github/copilot-instructions.md`, `.github/skills/`). |
| `--claude` | | boolean | `false` | Enable Claude Code plugin (`CLAUDE.md`, `.claude/skills/`). |
| `--cursor` | | boolean | `false` | Enable Cursor plugin (`.cursorrules`, `.cursor/rules/`). |
| `--codex` | | boolean | `false` | Enable OpenAI Codex plugin (`CODEX.md`, `.codex/skills/`). |
| `--gemini` | | boolean | `false` | Enable Google Gemini plugin (`GEMINI.md`, `.agents/skills/`). |
| `--windsurf` | | boolean | `false` | Enable Windsurf plugin (`.windsurfrules`, `.windsurf/rules/`). |
| `--karpathy` | | boolean | `false` | Enable Karpathy LLM Wiki plugin (`wiki/`, `docs/`). |
| `--plugin <name>` | | string | | Enable any specified plugin during initialization (repeatable). |

---

## 2. Synchronization & Reconciliation (`rnex sync`)

`rnex sync` is the single reconciliation command in Repo Nexus. It reconciles workspace configuration, skills, plugins, Git ignore rules, Git hook wrappers, and compiles `.rnex/ai-instructions.md`.

### Syntax
```sh
rnex sync [options]
```

### Options
| Option | Shorthand | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `--yes` | `-y` | boolean | `false` | Automatically confirm non-destructive schema upgrades if prompted. |
| `--upgrade` | | boolean | `false` | Explicitly trigger non-destructive configuration and schema upgrade checks. |
| `--quiet` | `-q` | boolean | `false` | Quiet mode; suppresses non-error informational messages (ideal for hooks). |

### Reconciliation Pipeline
1. Upgrades configuration schema non-destructively if an older version is detected.
2. Re-verifies `.gitignore` rules from `git.ignore` (enforcing directory-only patterns `**/.rnex*/`, `**/rnex*/`, `repos/`), and ensures `.ignore` contains `!repos/*`.
3. Compiles `.rnex/ai-instructions.md` by combining the base template with active configuration and all enabled plugin instruction fragments. Writes single strict directive to top-level provider files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, etc.).
4. Syncs core agentic skills from `toolkit/skills/` to `.rnex/skills/` and generates zero-logic User Skills (`rnex-*`) in active AI provider directories.
5. Re-syncs enabled plugin assets into `.rnex/plugins/` and reconciles on-demand member `repos/<name>/.rnex/` directories.
6. Dispatches lifecycle hooks (`before_sync`, `after_sync`).
7. Reconciles Git hook dispatchers in `.git/hooks/` against declarative `git.hooks` commands.
8. Updates multi-root `.code-workspace` folder mappings if configured.
9. Updates the checksum stamp in `.rnex/sync_stamp`.

---

## 3. Diagnostics & Health (`rnex status`)

Inspects workspace health and diagnostic information. `rnex status` is **strictly read-only**.

### Syntax
```sh
rnex status
```

### Diagnostics Reported
* Status of meta-repo control files (`.gitignore`, `rnex.yaml`, `AGENTS.md`, `.rnex/ai-instructions.md`).
* Active AI provider instruction files and user skills.
* Enabled plugins, version, and scoped directories.
* Registered member repositories, active branch, read-only status, and clone health.
* Configuration drift warnings if `rnex.yaml` has un-synchronized changes.

---

## 4. Multi-Repo Batch Execution (`rnex exec`)

Runs arbitrary shell commands sequentially across every active member repository in `./repos/`.

```bash
rnex exec [command...]
```

* Executes in each repository root (`./repos/<name>`).
* Preserves and bubbles the exact exit code of any failing command.
* Sets environment variables: `RNEX_REPO_NAME`, `RNEX_REPO_PATH`, `RNEX_REPO_BRANCH`.
