---
title: General & Architectural FAQ
description: Common architectural questions, comparisons with monorepos and Git submodules, and Virtual Meta-Repo mechanics.
---

# General & Architectural FAQ

This document answers common architectural and technical questions about **Repo Nexus (`rnex`)**, why it exists, how it works as a **Virtual Meta-Repo for AI Agents**, and how it compares to alternative approaches.

---

## General Concepts & Philosophy

### What is Repo Nexus (`rnex`)?
Repo Nexus is a zero-dependency **Virtual Meta-Repo companion** that organizes multiple independent Git repositories into a unified development workspace with shared AI routing context.

### How does it differ from traditional monorepo orchestrators?
Unlike heavy monorepo tools (such as Nx, Turborepo, or Bazel) that take over build pipelines, require unified lockfiles, and impose cross-package dependency graphs, `repo-nexus` acts strictly as an architectural companion. It does not replace your compiler, test runner, package manager, or build tooling.

### Does it require Git Submodules?
**No.** Member repositories are physically cloned into `./repos/<name>`. The workspace root `.gitignore` strictly ignores `repos/`. Each repository remains a 100% normal, autonomous Git repository with its own `.git` directory, remotes, branches, and commit history. There are no `.gitmodules`, no detached HEADs, and no submodule pointer commits.

### Why do I need rnex?
Modern AI coding assistants (Claude Code, Cursor, GitHub Copilot, Codex, Antigravity) are designed around a single project root. In real-world software development, applications are rarely confined to a single repository—they are split across frontends, backend APIs, shared packages, and infrastructure.

This creates two major frictions:
1. **Siloed Context**: Opening one repository in an AI tool leaves the AI blind to API contracts, types, or services in other repositories, leading to hallucinations.
2. **Onboarding Friction**: New team members must manually find and clone 5–10 repos, set up local folder structures, and configure tools.

**`rnex` solves both**:
- It unites repositories under one Virtual Meta-Repo root so AI assistants see the whole stack.
- It enables 1-command onboarding: teammates run `rnex clone` and every repository is cloned and wired up in seconds.

---

## Architectural Comparison Table

| Dimension | Git Submodules | Monorepo (Nx / Turborepo) | Repo Nexus (`rnex`) |
| :--- | :--- | :--- | :--- |
| **Repository Model** | Nested Git trees | Single giant repository | Virtual Meta-Repo umbrella |
| **Git Complexity** | High (detached HEAD, pointer sync) | Low (single git log) | Zero (standard independent repos) |
| **Migration Cost** | High | Massive (rewrite git history) | Instant (`rnex init` & `rnex repo add`) |
| **Runtime Dependencies** | Git | Node.js, Rust, or Go runtimes | Pure POSIX `/bin/sh` (zero deps) |
| **AI Context Scoping** | Manual per repo | Root-level bleed | Delimited, multi-provider mirroring |
| **Local Developer Overrides** | Hard / dirty git status | Difficult | Native via `.local.rnex.yaml` |

---

## Autonomy & Git Operations

### Can I use standard Git commands (pull, push, commit) on member repos?
**Yes.** When you or your IDE navigate into `repos/<name>/` and run `git status`, `git commit`, `git pull`, or `git push`, Git operates directly against that repository's own branches and remotes.

### Can AI agents create and modify files inside member repos?
**Yes.** Any file created or modified under `repos/<name>/...` (e.g. `repos/backend/src/api.ts`) is a real file inside that repository, immediately tracked by that repo's Git.

### Will rnex interfere with Git branches, remotes, or commit histories?
**No.** The workspace root `.gitignore` ignores `repos/`. The workspace Git repository never commits or interferes with member repository contents.
