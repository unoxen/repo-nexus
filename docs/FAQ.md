---
title: Frequently Asked Questions
description: Comprehensive FAQ for Repo Nexus, covering architecture, Git internals, submodule pitfalls, two-level config, AI context routing, and system requirements.
---

# Frequently Asked Questions (FAQ)

This document answers common architectural, operational, and technical questions about **Repo Nexus (`rnex`)**, why it exists, how it works as a **Virtual Meta-Repo for AI Agents**, how it handles Git autonomy, and how to use it effectively.

---

## General Setup & Philosophy

### What is repo-nexus?

It is a zero-dependency **Virtual Meta-Repo companion** that organizes multiple independent Git repositories into a unified development workspace with shared AI routing context.

---

### How does it differ from traditional monorepo orchestrators?

Unlike heavy monorepo tools (such as Nx, Turborepo, or Bazel) that take over build pipelines, require unified lockfiles, and impose cross-package dependency graphs, `repo-nexus` acts strictly as an architectural companion. It does not replace your compiler, test runner, package manager, or build tooling.

---

### Does it require Git Submodules?

**No.** Member repositories are physically cloned into `./repos/<name>`. The workspace root `.gitignore` strictly ignores `repos/`. Each repository remains a 100% normal, autonomous Git repository with its own `.git` directory, remotes, branches, and commit history. There are no `.gitmodules`, no detached HEADs, and no submodule pointer commits.

---

### Why do I need rnex?

Modern AI coding assistants (Claude Code, Cursor, GitHub Copilot, Codex, Antigravity) are designed around a single project root. In real-world software development, applications are rarely confined to a single repository—they are split across frontends, backend APIs, shared packages, and infrastructure.

This creates two major frictions:
1. **Siloed Context**: Opening one repository in an AI tool leaves the AI blind to API contracts, types, or services in other repositories, leading to hallucinations.
2. **Onboarding Friction**: New team members must manually find and clone 5–10 repos, set up local folder structures, and configure tools.

**`rnex` solves both**:
- It unites repositories under one Virtual Meta-Repo root so AI assistants see the whole stack.
- It enables 1-command onboarding: teammates run `rnex clone` and every repository is cloned and wired up in seconds.

---

### Why not just use a monorepo or Git submodules?

| Solution | Drawbacks | How `rnex` compares |
| :--- | :--- | :--- |
| **Git Monorepo** | Heavy migration effort, combined CI/CD pipelines, complex permissions, slow checkouts. | **Zero migration**: Repositories remain completely independent with their own remotes and CI/CD pipelines. |
| **Git Submodules** | Detached HEAD states, tricky merge conflicts, complex multi-step commits, rigid coupling. | **Zero submodule friction**: Root Git ignores `repos/`. Repos are completely normal autonomous clones. |
| **Manual Multi-Window** | Juggling 5 IDE windows, copy-pasting API types, fragmented AI reasoning. | **Unified Workspace**: AI agents see the entire system from the meta-repo root. |

---

## Architecture & Mechanics

### How does the Virtual Meta-Repo work?

When you initialize a workspace (`rnex init`), `rnex` creates:
1. `rnex.yaml` (declaring member repository URLs and active plugins).
2. Root `.gitignore` (ignoring `repos/` and `.local.rnex.yaml`).
3. Routing-only `AGENTS.md` (directing AI assistants to configuration and plugins).
4. `.rnex/` (strictly encapsulating all internal rnex assets and scoped plugins).

When you run `rnex add <name> <git-url>` or `rnex clone`, member repositories are cloned directly into `./repos/<name>`.

---

### Why use physical clones in `./repos/` instead of symlinks?

1. **Universal Portability**: Zero symlink fragility. Works 100% natively on macOS, Linux, and Windows without elevated permissions or Developer Mode.
2. **File Watcher & Tool Compatibility**: Native folders avoid known symlink bugs in IDE file watchers, bundlers, and linters.
3. **Intuitive Simplicity**: Every project is right where you expect it in `./repos/<name>`.

---

### Can I use Git commands (pull, push, commit) on member repos?

**Yes.** Git operates completely normally.
When you or your IDE navigate into `repos/<name>/` and run `git status`, `git commit`, `git pull`, or `git push`, Git operates directly against that repository's own branches and remotes.

---

### Can AI agents create and modify files inside member repos?

**Yes.** Any file created or modified under `repos/<name>/...` (e.g. `repos/backend/src/api.ts`) is a real file inside that repository, immediately tracked by that repo's Git.

---

### Will rnex interfere with Git branches, remotes, or commit histories?

**No.** The workspace root `.gitignore` ignores `repos/`. The workspace Git repository never commits or interferes with member repository contents.

---

### How does batch execution (rnex exec) work?

Running `rnex exec <command>` iterates through every active, enabled repository in `./repos/` and executes the command within that directory. For example:

```bash
rnex exec git status -s
rnex exec npm test
```

---

## Configuration & AI Context Routing

### What is the two-level configuration model?

1. **Repo Config (`rnex.yaml`)**: Shared team manifest committed to Git. Declares repo URLs, default enabled states, and plugins.
2. **Local Config (`.local.rnex.yaml`)**: Machine-specific file ignored by Git. Takes **highest priority** and overrides repo settings.

---

### How does the enabled/disabled setting work?

Repositories support an `enabled: true|false` setting:
- **Default State**: Enabled (`true`). If omitted, the repository is automatically considered enabled.
- **Local Overrides**: If a team has 10 repos, but a developer only works on two, they can set `enabled: false` for the other eight in `.local.rnex.yaml`.
- **Disabled Repositories**: Skipped by `rnex clone`, `rnex exec`, and excluded from AI agent tasks.

CLI commands:
```bash
rnex disable analytics --local    # disable locally
rnex enable analytics             # re-enable
```

---

### What is the routing-only instructions pattern in AGENTS.md?

Top-level AI instructions (`AGENTS.md`, `CLAUDE.md`, etc.) do not include sprawling inlined rules or tool text. Instead, they act as **lean navigation routers**:
1. Mandate reading `.local.rnex.yaml` (highest priority) and `rnex.yaml` first.
2. Route agents to `.rnex/plugins/<plugin-name>/` for scoped plugin rules.
3. Route agents to `repos/<name>/.rnex/` for member-specific instructions.

---

### What is the member repository `.rnex/` directory?

Repo Nexus initializes an isolated `.rnex/` folder inside each member repository (`repos/<name>/.rnex/`):
- Encapsulates Repo Nexus metadata and scoped plugin rules for that repository.
- Keeps member repository roots clean and untouched.
- Can be disabled at any time with `rnex rnex-dir disable <name>`.

---

### How are plugins structured and scoped?

Plugins are strictly scoped under `.rnex/plugins/<plugin-name>/`.
For example, the built-in `karpathy-llm` plugin places its rules, workflows, and instructions in `.rnex/plugins/karpathy-llm/`, while instantiating domain directories (`./docs` for intake documents and `.rnex/wiki` for curated knowledge) as specified by its architecture.

---

## Platforms & Setup

### What are the system requirements? Does it work on Windows?

`rnex` is written in POSIX shell script (`/bin/sh`). It runs natively on:
- **macOS**
- **Linux**
- **Windows** (via WSL2, Git Bash, or MSYS2)

Because `rnex` uses standard physical folders and `git clone` instead of symlinks, it has zero symlink permission limitations on Windows.

---

### Does rnex have external runtime dependencies?

**No.** The `rnex` executable has zero external dependencies—no Node.js runtime, Python, or external package managers are required to execute the CLI.

---

### What files should be committed to Git?

In your Repo Nexus workspace Git repository:
- **Commit**: `rnex.yaml`, `AGENTS.md`, `docs/`, `toolkit/`, and `.gitignore`.
- **Do NOT Commit**: `repos/` and `.local.rnex.yaml` (both are strictly ignored by `.gitignore`).
