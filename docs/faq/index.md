---
title: Frequently Asked Questions
description: Common questions about Repo Nexus, virtual meta-repos, Git autonomy, AI context routing, and system requirements.
---

# Frequently Asked Questions (FAQ)

This guide addresses common architectural questions, Git internals, and operational details about **Repo Nexus (`rnex`)**.

---

## General Setup & Philosophy

### What is Repo Nexus?
Repo Nexus is a zero-dependency **Virtual Meta-Repo companion** that organizes multiple independent Git repositories into a unified development workspace with shared AI routing context.

### How does it differ from traditional monorepo orchestrators?
Unlike heavy monorepo tools (such as Nx, Turborepo, or Bazel) that take over build pipelines, require unified lockfiles, and impose cross-package dependency graphs, Repo Nexus acts strictly as an architectural coordinator. It never replaces your compiler, test runner, package manager, or build tooling.

### Does it require Git Submodules?
**No.** Member repositories are physically cloned into `./repos/<name>`. The workspace root `.gitignore` strictly ignores `repos/`. Each repository remains a completely standard, autonomous Git repository with its own `.git` directory, remotes, branches, and commit history. There are no `.gitmodules`, no detached HEADs, and no submodule pointer commits.

### Why do I need rnex?
Modern AI coding assistants (Claude Code, Cursor, GitHub Copilot, Google Antigravity) are designed around a single project root. In real-world software development, systems are split across frontends, backend APIs, shared packages, and infrastructure.

This creates two major frictions:
1. **Siloed Context**: Opening one repository leaves the AI blind to API contracts, types, or services in other repositories, leading to hallucinations.
2. **Onboarding Friction**: New team members must manually locate, clone, and configure multiple repositories.

Repo Nexus solves both:
* Unites repositories under one Virtual Meta-Repo root so AI assistants see the full architecture.
* Enables 1-command onboarding: teammates run `rnex clone` and every repository is fetched in seconds.

---

## Architecture & Git Mechanics

### Why use physical clones in `./repos/` instead of symlinks?
1. **Universal Portability**: Zero symlink fragility. Works 100% natively on macOS, Linux, and Windows without elevated permissions.
2. **File Watcher & Tool Compatibility**: Native folders avoid known symlink bugs in IDE file watchers, bundlers, and linters.
3. **Intuitive Simplicity**: Every project is right where you expect it in `./repos/<name>`.

### Can I use Git commands on member repositories?
**Yes.** Git operates completely normally. When you navigate into `repos/<name>/` and run `git commit`, `git pull`, or `git push`, Git operates directly against that repository's own branches and remotes.

### Can AI agents create and modify files inside member repos?
**Yes.** Any file created or modified under `repos/<name>/...` (e.g. `repos/backend/src/api.ts`) is a real file inside that repository, immediately tracked by that repo's Git.

### Will rnex interfere with Git branches or commit histories?
**No.** The workspace root `.gitignore` ignores `repos/`. The parent meta-repo never commits or interferes with member repository contents.

---

## Configuration & Context Routing

### What is the two-level configuration model?
1. **Team Config (`rnex.yaml`)**: Shared team manifest committed to Git. Declares repo URLs, default enabled states, and plugins.
2. **Local Config (`.local.rnex.yaml`)**: Machine-specific file ignored by Git. Takes **highest priority** and overrides repo settings.

### What is the routing-only instructions pattern?
Top-level AI instructions (`AGENTS.md`, `CLAUDE.md`, etc.) do not include sprawling inlined rules. Instead, they act as **lean navigation routers**:
1. Mandate reading `.local.rnex.yaml` and `rnex.yaml` on session start.
2. Route agents to `.rnex/plugins/<plugin-name>/` for scoped plugin rules.
3. Route agents to `repos/<name>/.rnex/` for member-specific instructions.

---

## Platforms & Requirements

### What are the system requirements? Does it work on Windows?
`rnex` is written in POSIX shell script (`/bin/sh`). It runs natively on:
* **macOS**
* **Linux**
* **Windows** (via WSL2, Git Bash, or MSYS2)

### Does rnex have external runtime dependencies?
**No.** The `rnex` executable has zero external dependencies—no Node.js runtime, Python, or external package managers are required to run the CLI.

### What files should be committed to Git?
* **Commit**: `rnex.yaml`, `AGENTS.md`, `docs/`, `toolkit/`, and `.gitignore`.
* **Do NOT Commit**: `repos/` and `.local.rnex.yaml` (both are strictly ignored by `.gitignore`).
