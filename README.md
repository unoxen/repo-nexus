# Repo Nexus (`rnex`)

[![CI](https://github.com/unoxen/repo-nexus/actions/workflows/ci.yml/badge.svg)](https://github.com/unoxen/repo-nexus/actions/workflows/ci.yml)
[![npm version](https://img.shields.io/npm/v/repo-nexus.svg)](https://www.npmjs.com/package/repo-nexus)
[![License: MIT](https://img.shields.io/github/license/unoxen/repo-nexus)](LICENSE)
[![POSIX Compatible](https://img.shields.io/badge/POSIX-compatible-success)](#)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#)
[![CLI Reference](https://img.shields.io/badge/docs-site-blue.svg)](https://unoxen.github.io/repo-nexus/)

A **simple, lightweight Virtual Meta-Repo companion** for multi-repo workspaces and shared AI context. It organizes independent repositories into a unified workspace and shares lean routing instructions (`AGENTS.md`) **without Git submodules, monorepo migrations, or symlink fragility**.

- **No Git Submodules or Nested Git Collisions**: Member repositories are physically cloned into `./repos/` and strictly ignored by workspace Git. Each repository maintains its own standalone history, remotes, branches, and commits with zero submodule friction.
- **Unified Workspace for AI Coding Assistants**: Open one root folder to give Cursor, Claude Code, GitHub Copilot, Codex, or Antigravity complete cross-service visibility.
- **Two-Level Configuration as Source of Truth**: Shared team manifest in `rnex.yaml` with machine-specific overrides in `.local.rnex.yaml` (highest priority).
- **1-Command Team Onboarding**: Teammates clone the meta-repo and run `rnex clone` to clone and configure all member repos in seconds.
- **Cross-Repo Batch Operations**: Run arbitrary commands across all active repositories with `rnex exec <command>`.
- **Scoped Plugins & Context Packs**: Modular plugin packages scoped under `.rnex/plugins/<plugin-name>/` with support for domain directories (e.g. `raw/` and `wiki/` for `karpathy-llm`).
- **Zero Dependencies**: Pure POSIX shell CLI (`rnex`). Works out of the box across macOS, Linux, and Windows (WSL/Git Bash).

> 💡 **Documentation & Guides:**
> - Check out the **[Documentation Site](https://unoxen.github.io/repo-nexus/)** or local **[CLI Reference](docs/cli/)** for complete command syntax, flags, Git hooks, plugins, and prompts.
> - Check out the **[Plugins Guide](docs/plugins/)** for detailed documentation on all built-in AI provider and domain plugins.
> - Check out the **[Frequently Asked Questions (FAQ)](docs/faq/)** for architecture deep dives, Git workflows, and AI context strategies.

---

## Table of Contents

- [What Repo Nexus Is (and What It Isn't)](#what-repo-nexus-is-and-what-it-isnt)
- [How It Works: Virtual Meta-Repo Architecture](#how-it-works-virtual-meta-repo-architecture)
- [Key Principles](#key-principles)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Everyday Usage](#everyday-usage)
- [Plugins & Scoped Context Packs](#plugins--scoped-context-packs)
- [Two-Level Configuration (`rnex.yaml` & `.local.rnex.yaml`)](#two-level-configuration)
- [CLI Command Reference](#cli-command-reference)
- [Full CLI Reference Manual (docs/cli/)](docs/cli/)
- [Shell Auto-Completion](#shell-auto-completion)
- [Project Structure](#project-structure)
- [Running Tests](#running-tests)
- [Frequently Asked Questions (FAQ)](docs/faq/)
- [License](#license)

---

## What Repo Nexus Is (and What It Isn't)

| What It Is | What It Isn't |
| :--- | :--- |
| **A lightweight companion utility** (~25 KB POSIX script). | **NOT a replacement for your workspace or tools.** It doesn't replace VS Code, Cursor, JetBrains, or your terminal. |
| **A Virtual Meta-Repo orchestrator** managing member clones in `./repos/`. | **NOT a build tool or monorepo orchestrator.** It doesn't replace tools like Nx, Turborepo, Cargo, or Gradle. |
| **Zero Git friction.** Repositories remain normal, autonomous Git repos. | **NOT Git submodules or subtrees.** No `.gitmodules` files, no detached HEADs, no commit coordination lock-in. |
| **Strictly encapsulated.** Internal rnex assets live exclusively in `.rnex/`. | **NOT invasive.** Member repositories remain clean; workspace-related context is isolated to `repos/<name>/.rnex/`. |

---

## How It Works: Virtual Meta-Repo Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Repo Nexus Workspace Root (Virtual Meta-Repo)              │
│                                                             │
│  my-workspace/                                              │
│    .local.rnex.yaml  (Highest Priority: local overrides)    │
│    rnex.yaml         (Team Manifest: repos & plugins)       │
│    AGENTS.md         (Routing-only AI agent instructions)   │
│    .gitignore        (Strictly ignores repos/ & local yaml) │
│    .rnex/            (Strictly encapsulated internal state) │
│      plugins/        (Scoped plugin directories)            │
│        karpathy-llm/ (Isolated rules, workflows, templates) │
│    repos/            (Autonomous Physical Git Clones)       │
│      backend/        (Own .git, branches, PRs)              │
│        .rnex/        (Quarantined member-specific context)  │
│      frontend/       (Own .git, branches, PRs)              │
│        .rnex/        (Quarantined member-specific context)  │
│                                                             │
│  • Agent opens workspace → reads config first → sees stack. │
│  • Repos are 100% normal Git clones (zero submodules).      │
│  • Work across repos seamlessly using rnex exec.            │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Principles

1. **Configuration as Single Source of Truth**:
   Every agent workflow and command starts by reading the configuration files. `.local.rnex.yaml` takes **highest priority** over `rnex.yaml`.

2. **No Git Submodules (Complete Repository Autonomy)**:
   Member repositories are cloned directly into `./repos/<name>`. The root workspace `.gitignore` ignores `repos/`, ensuring the workspace repository never tracks or interferes with member Git histories, remotes, branches, or commits.

3. **Enabled by Default with Two-Level Merging**:
   Member repositories are enabled by default. Developers can selectively disable specific repositories locally in `.local.rnex.yaml` (`enabled: false`) without mutating the shared `rnex.yaml`. Disabled repositories are skipped by `clone` and `exec`.

4. **Routing-Only Top-Level AI Instructions**:
   `AGENTS.md` (and related top-level instruction files) contains no inlined plugin rules or tool boilerplate. It acts solely as a lean navigation router directing AI agents to configuration files, scoped plugins, and member `.rnex/` contexts.

5. **Strict File Encapsulation**:
   All `rnex`-managed internal files live exclusively in `.rnex/`. Member repositories isolate Repo Nexus assets in `repos/<name>/.rnex/`.

---

## Installation

Install `rnex` via npm, standalone one-liner (`curl` / `wget`), or from source:

### Option 1: Via npm (Global)

```bash
npm install -g repo-nexus
```
*(Installs both `repo-nexus` and `rnex` commands globally, or run without installing via `npx repo-nexus init`)*

### Option 2: Standalone One-Liner (curl / wget — Zero Dependencies, No Node.js)

```bash
curl -fsSL https://raw.githubusercontent.com/unoxen/repo-nexus/main/scripts/install.sh | sh
# or
wget -qO- https://raw.githubusercontent.com/unoxen/repo-nexus/main/scripts/install.sh | sh
```
*(Downloads and links `rnex` and `repo-nexus` into `~/.local/bin` without requiring Node.js or npm)*

### Option 3: Native Installer (Clone & Install)

```bash
git clone https://github.com/unoxen/repo-nexus.git
cd repo-nexus
./rnex install
```
*(Installs `rnex` and `repo-nexus` into `~/.local/bin`, or pass a custom directory like `./rnex install /usr/local/bin`)*

---

## Quick Start

```bash
# 1. Initialize a new workspace
mkdir my-workspace && cd my-workspace
rnex init

# 2. Register and clone repositories
rnex add backend git@github.com:myorg/backend-api.git
rnex add frontend https://github.com/myorg/web-app.git

# 3. Check workspace health
rnex status

# 4. Run a batch command across all member repos
rnex exec git status -s
```

When a teammate clones your workspace, they simply run:
```bash
rnex clone
```
All declared member repositories are cloned and wired up automatically!

---

## Everyday Usage

```bash
# Register and clone a repository
rnex add backend git@github.com:myorg/backend.git

# Register a repository in local config only (.local.rnex.yaml)
rnex add --local analytics git@github.com:myorg/analytics.git

# Clone all missing member repositories
rnex clone

# Run a command across all active repositories
rnex exec git status -s
rnex exec npm test

# Disable a repository (skipped by clone, exec, and agents)
rnex disable analytics
rnex disable --local analytics    # disable locally without modifying team rnex.yaml

# Re-enable a repository
rnex enable analytics

# List all registered repositories with clone status and active branch
rnex list

# Inspect workspace health, active repos, and plugin status
rnex status

# Reconcile workspace, sync plugins, and upgrade config in a single pass (aliases: sync, update, upgrade)
rnex fix

# Unregister and delete a repository
rnex remove analytics
```

---

## Plugins & Scoped Context Packs

Repo Nexus features a scoped plugin architecture. Plugins package curated AI instructions, agent behavioral rules, and architecture templates that are synchronized into dedicated directories under `.rnex/plugins/<plugin-name>/`.

```bash
# List available and active plugins
rnex plugin list

# Inspect plugin details and provided files
rnex plugin info karpathy-llm

# Enable a plugin in your workspace
rnex plugin enable karpathy-llm

# Disable a plugin and clean up scoped assets
rnex plugin disable karpathy-llm
```

### Built-in Plugins

> For dedicated guides, configuration options, and directory layouts for each plugin, see the [**Repo Nexus Plugins Guide**](docs/plugins/).

#### 1. `copilot`
The `copilot` plugin provides GitHub Copilot integration, automatically mirroring workspace and active plugin assets:
* **Prompts (`.github/prompts/*.prompt.md`)**: Formatted with YAML frontmatter (`name`, `description`) for the VS Code Copilot Chat prompt picker and slash commands.
* **Agent Skills (`.github/skills/<name>/SKILL.md`)**: Configured for GitHub Copilot Agent mode and `gh skill`.
* **Custom Agents (`.github/agents/*.agent.md`)**: Active plugins' agent definitions mirrored for Copilot workspace custom agents.
* **Instructions (`.github/copilot-instructions.md`)**: Synthesized workspace routing and active plugin guidelines, preserving manual user instructions.
* **Configurable Options**:
  ```yaml
  plugins:
    copilot:
      prompts: true        # mirror prompts to .github/prompts/*.prompt.md (default: true)
      skills: true         # mirror skills to .github/skills/<name>/SKILL.md (default: true)
      instructions: true   # mirror guidelines to .github/copilot-instructions.md (default: true)
      agents: true         # mirror custom agents to .github/agents/*.agent.md (default: true)
  ```

#### 2. `claude`
The `claude` plugin integrates Anthropic's Claude Code and Claude CLI:
* **Instructions (`CLAUDE.md`)**: Manages the root `CLAUDE.md` routing context, replacing `AGENTS.md`.
* **Slash Commands (`.claude/commands/*.md`)**: Standardized commands (`/rnex-cross-repo-feature`, etc.) for Claude Code.
* **Agent Skills (`.claude/skills/<name>/SKILL.md`)**: Mirrored tool skills and workflows.
* **Configurable Options**:
  ```yaml
  plugins:
    claude:
      instructions: true   # maintain CLAUDE.md (default: true)
      prompts: true        # mirror slash commands to .claude/commands/ (default: true)
      skills: true         # mirror skills to .claude/skills/ (default: true)
  ```

#### 3. `gemini`
The `gemini` plugin integrates Google Gemini CLI and Gemini Code Assist:
* **Instructions (`GEMINI.md`)**: Manages root `GEMINI.md` context, replacing `AGENTS.md`.
* **Prompts (`.gemini/prompts/*.prompt.md`)**: Standardized prompts formatted with YAML frontmatter.
* **Skills (`.gemini/skills/<name>/SKILL.md`)**: Mirrored tool skills for Gemini agents.
* **Configurable Options**:
  ```yaml
  plugins:
    gemini:
      instructions: true   # maintain GEMINI.md (default: true)
      prompts: true        # mirror prompts to .gemini/prompts/ (default: true)
      skills: true         # mirror skills to .gemini/skills/ (default: true)
  ```

#### 4. `cursor`
The `cursor` plugin integrates the Cursor IDE:
* **Instructions (`.cursorrules` & `.cursor/rules/repo-nexus.mdc`)**: Synchronizes project routing rules.
* **Prompts (`.cursor/prompts/*.md`)**: Mirrored prompt files.
* **Skills (`.cursor/skills/<name>/SKILL.md`)**: Mirrored agent skills.
* **Configurable Options**:
  ```yaml
  plugins:
    cursor:
      instructions: true   # maintain .cursorrules and MDC rule (default: true)
      prompts: true        # mirror prompts to .cursor/prompts/ (default: true)
      skills: true         # mirror skills to .cursor/skills/ (default: true)
  ```

#### 5. `windsurf`
The `windsurf` plugin integrates the Codeium Windsurf IDE:
* **Instructions (`.windsurfrules`)**: Synchronizes project routing rules.
* **Prompts (`.windsurf/prompts/*.md`)**: Mirrored prompt files.
* **Skills (`.windsurf/skills/<name>/SKILL.md`)**: Mirrored agent skills.
* **Configurable Options**:
  ```yaml
  plugins:
    windsurf:
      instructions: true   # maintain .windsurfrules (default: true)
      prompts: true        # mirror prompts to .windsurf/prompts/ (default: true)
      skills: true         # mirror skills to .windsurf/skills/ (default: true)
  ```

#### 6. `karpathy-llm`
The `karpathy-llm` plugin packages Andrej Karpathy's verified LLM agent design patterns, context engineering principles, and the autonomous **Karpathy LLM Wiki** architecture:
* **The 4 Cardinal Agent Rules** (`.rnex/plugins/karpathy-llm/rules/behavioral.md`):
  1. *Think Before Coding:* Formulate explicit assumptions, boundary checks, and trade-offs before writing code.
  2. *Simplicity First:* Minimal abstractions, readable implementations, zero speculative boilerplate.
  3. *Surgical Changes:* Minimal blast radius, preserved comments/docstrings, and tight diffs.
  4. *Goal-Driven Execution:* Upfront verification criteria, automated tests, and diff inspection.
* **Autonomous Karpathy LLM Wiki Architecture:**
  * **Intake (`/raw/`):** Append-only intake for unmodified source documents.
  * **Curated Knowledge Base (`/wiki/`):** Interlinked atomic markdown pages with typed YAML frontmatter relations.
  * **Navigation Index (`/wiki/index.md`):** Master categorized navigation index.
  * **Rolling Context (`/wiki/hot.md`):** ~500-word quick-orient context cache for AI agents.
  * **Operation Log (`/wiki/_log.md`):** Append-only audit trail of ingest and lint operations.
* **Standardized Workflows (`.rnex/plugins/karpathy-llm/workflows/`):**
  * `wiki-ingest.md`: 8-step protocol decomposing raw source documents into atomic wiki pages.
  * `wiki-lint.md`: 10-step protocol validating paths, relations, contradictions, and indexing.

---

## Two-Level Configuration

1. **Repo Config (`rnex.yaml`):** Shared manifest committed to Git. Declares member repos, Git URLs, default enabled states, and active plugins.
2. **Local Config (`.local.rnex.yaml`):** Machine-specific file ignored in `.gitignore`. Takes **highest priority** and overrides repo settings.

### Repo Configuration (`rnex.yaml`)

```yaml
# Directory for member repository clones
repos_dir: ./repos

# Automated workspace Git hooks (default: true)
git_hooks: true

# Workspace plugins and tool integrations
plugins:
  copilot:
    prompts: true
    skills: true
    instructions: true
    agents: true
  karpathy-llm: {}

# Member repositories (enabled by default)
repos:
  backend:
    url: git@github.com:myorg/backend-api.git
    rnex_dir: true      # default: true (creates repos/backend/.rnex/)
  frontend:
    url: https://github.com/myorg/web-app.git
    rnex_dir: true
  analytics:
    url: git@github.com:myorg/analytics.git
    enabled: false       # disabled: skipped by clone and exec
    rnex_dir: false
```

### Local Configuration (`.local.rnex.yaml`)

```yaml
# Highest priority local overrides
repos:
  analytics:
    enabled: true        # locally enable analytics on this workstation
```

---

## CLI Command Reference

> 📖 **Full Manual Available:** See the comprehensive **[CLI Reference Manual](docs/cli/)** for exhaustive details, deep dives into every command and flag, lifecycle behaviors, automated Git hooks, scoped plugins, standardized prompts catalog, and shell completion recipes.

### Global Options
| Option | Description |
|:---|:---|
| `-c, --config <file>` | Explicit path to `rnex.yaml` (executes in that workspace directory) |
| `-h, --help` | Display command help and usage instructions |
| `-v, --version` | Display version |

### Commands
| Command | Description |
|:---|:---|
| `rnex init [-y] [--ai <file>] [--code-workspace [file]] [--hooks\|--no-hooks] [dir]` | Initialize a new Virtual Meta-Repo workspace in current (or target) directory |
| `rnex install [dir]` | Install `rnex` & `repo-nexus` globally into `~/.local/bin` (or custom dir) |
| `rnex add [--local] [--disabled] <name> <git-url>` | Register and clone repo into `./repos/<name>` |
| `rnex clone` | Clone all missing enabled repositories declared in `rnex.yaml` |
| `rnex exec <command...>` | Execute a shell command across all active member repositories |
| `rnex remove <name>` | Unregister repo and delete `./repos/<name>` |
| `rnex enable [--local] <name>` | Enable a repository in active workspace |
| `rnex disable [--local] <name>` | Disable a repository from active workspace |
| `rnex list` | List all member repositories with clone state, active branch, and `.rnex` status |
| `rnex status` | Inspect workspace health, active repos, config loaded, git hooks, and plugins |
| `rnex rnex-dir <enable\|disable> <name>` | Toggle `.rnex/` directory integration for a member repository |
| `rnex fix [-y] [--quiet]` (or `sync`) | Reconcile workspace repositories, plugins, prompts, and member `.rnex/` directories |
| `rnex update [-y]` (or `upgrade`) | Safely upgrade workspace configuration schema and routing instructions |
| `rnex hooks <install\|uninstall\|status> [--local]` | Manage automated Git hooks (`.rnex/hooks` and `git_hooks: true\|false`) |
| `rnex plugin <list\|info\|enable\|disable>` | Manage workspace plugins |
| `rnex completion <bash\|zsh\|fish>` | Generate shell auto-completion script |

---

## Shell Auto-Completion

Generate auto-completions for your shell:

### Zsh
```bash
# Add to ~/.zshrc
source <(rnex completion zsh)
```

### Bash
```bash
# Add to ~/.bashrc
source <(rnex completion bash)
```

### Fish
```bash
# Add to ~/.config/fish/config.fish
rnex completion fish | source
```

---

## Project Structure

```
repo-nexus/
├── package.json                    # npm package manifest (single version source of truth)
├── rnex                            # CLI executable (POSIX shell)
├── AGENTS.md                       # Routing-only universal AI instructions
├── CHANGELOG.md                    # Release history and migration notes
├── docs/
│   ├── AGENTS.sample.md            # Template for routing-only AGENTS.md
│   ├── rnex.example.yaml           # Full config reference with examples
│   ├── guide/                      # Architecture, workflows, and getting started
│   ├── cli/                        # Comprehensive CLI reference manual
│   ├── plugins/                    # Scoped plugin guides and specifications
│   ├── examples/                   # Multi-repo patterns and case studies
│   └── faq/                        # Frequently Asked Questions
├── .github/
│   └── workflows/ci.yml            # GitHub Actions CI workflow
├── tests/
│   └── test_cli.sh                 # Automated CLI test suite
├── toolkit/                        # Shared plugins, prompts, and templates
│   ├── plugins/
│   │   └── karpathy-llm/           # Scoped Karpathy LLM plugin
│   └── prompts/                    # Standardized AI operational prompts
└── README.md
```

---

## Running Tests

```bash
./tests/test_cli.sh
```

---

## License

[MIT](LICENSE)
