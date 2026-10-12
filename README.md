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
- **One Command Team Onboarding**: Teammates clone the meta-repo and run `rnex clone` to clone and configure all member repos in seconds.
- **Cross-Repo Batch Operations**: Run arbitrary commands across all active repositories with `rnex exec <command>`.
- **Scoped Plugins & Context Packs**: Modular plugin packages scoped under `.rnex/plugins/<plugin-name>/` with support for domain directories (e.g. `raw/` and `wiki/` for `karpathy-llm`).
- **Zero Dependencies**: Pure POSIX shell CLI (`rnex`). Works out of the box across macOS, Linux, and Windows (WSL/Git Bash).

> 💡 **Documentation:** Full documentation lives on the **[Documentation Site](https://unoxen.github.io/repo-nexus/)** (sources in [`docs/`](docs/)):
> - **[Architecture](docs/guide/architecture.md)** and **[Why Repo Nexus?](docs/guide/why-repo-nexus.md)** — workspace layout and rationale
> - **[CLI Reference](docs/cli/)** — all commands, flags, everyday usage, Git hooks, and shell completion
> - **[Plugins Guide](docs/plugins/)** — built-in AI provider and domain plugins
> - **[Configuration](docs/guide/configuration.md)** — `rnex.yaml` and `.local.rnex.yaml` schema
> - **[FAQ](docs/faq/)** — architecture deep dives, Git workflows, and AI context strategies

---

## Table of Contents

- [What Repo Nexus Is (and What It Isn't)](#what-repo-nexus-is-and-what-it-isnt)
- [Key Principles](#key-principles)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Running Tests](#running-tests)
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
