---
title: General & Architectural FAQ | Nexus Repository & Meta Repo Guide
description: Common architectural questions, comparisons with monorepos and Git submodules, and virtual meta repository (meta repo) and nexus repository (nexus repo) mechanics.
head:
  - - meta
    - name: keywords
      content: nexus repository, meta repository, nexus repo, meta repo, virtual meta repository, git submodules vs meta repo, multi-repo workspace, rnex
---

# General & Architectural FAQ

This document answers common architectural and technical questions about **Repo Nexus (`rnex`)**, why it exists, how it works as a **Virtual Meta Repository (meta repo)** and **Nexus Repository (nexus repo)** for engineering teams and AI coding assistants, and how it compares to alternative approaches.

---

## General Concepts & Philosophy

### What is Repo Nexus (`rnex`)?
Repo Nexus is a zero-dependency **Virtual Meta Repository (meta repo)** and **Nexus Repository (nexus repo)** manager that organizes multiple independent Git repositories into a unified development workspace with shared AI routing context.

### What is a Nexus Repository and Meta Repository?
A **meta repository** (or **meta repo**) is an umbrella repository that coordinates multiple autonomous child repositories without nesting their Git histories or using brittle Git submodules. A **nexus repository** (or **nexus repo**) serves as the centralized hub and connection point that mirrors shared configurations, team conventions, and scoped AI instructions across all member repositories. `repo-nexus` combines both concepts into a zero-dependency virtual workspace.

### How does it differ from traditional monorepo orchestrators?
Unlike heavy monorepo tools (such as Nx, Turborepo, or Bazel) that take over build pipelines, require unified lockfiles, and impose cross-package dependency graphs, `repo-nexus` acts strictly as an architectural coordinator and workspace orchestrator. It does not replace your compiler, test runner, package manager, or build tooling.

### Nexus Repo vs Git Submodules: How do they differ?
Git Submodules nest repositories within version control pointers, causing detached HEAD states, desynchronization, and commit coordination bottlenecks. In contrast, a **nexus repo** / **meta repo** managed by `repo-nexus` keeps member repositories physically independent in `<repos_dir>/<name>` (default `./repos/<name>`, configurable via `repos_dir`), strictly ignored by the parent Git repository. You retain standard, autonomous Git operations with zero submodule lock-in.

### What is the recommended Meta Repo workflow?
1. **Initialize Workspace**: Run `rnex init` in the root meta repo.
2. **Declare Member Repositories**: Add services using `rnex repo add <git-url>`.
3. **One-Command Clone**: Team members clone the meta repository and execute `rnex clone`.
4. **Autonomous Development**: Engineers work directly within `<repos_dir>/<service>` (default `repos/<service>`) using familiar Git branches, commits, and pull requests.
5. **Batch Operations**: Run workspace-wide tasks (linting, tests, status) across all services using `rnex exec <command>`.

### Does it require Git Submodules?
**No.** Member repositories are physically cloned into your configured member repository directory (`<repos_dir>/<name>`, default `./repos/<name>`). The workspace root `.gitignore` strictly ignores `<repos_dir>/` (and `.rnex/`). Each repository remains a 100% normal, autonomous Git repository with its own `.git` directory, remotes, branches, and commit history. There are zero `.rnex/` folders inside member repos, no `.gitmodules`, no detached HEADs, and no submodule pointer commits.

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
**Yes.** When you or your IDE navigate into `<repos_dir>/<name>/` (default `repos/<name>/`) and run `git status`, `git commit`, `git pull`, or `git push`, Git operates directly against that repository's own branches and remotes.

### Can AI agents create and modify files inside member repos?
**Yes.** Any file created or modified under `<repos_dir>/<name>/...` (e.g. `repos/backend/src/api.ts`) is a real file inside that repository, immediately tracked by that repo's Git.

### Will rnex interfere with Git branches, remotes, or commit histories?
**No.** The workspace root `.gitignore` ignores `<repos_dir>/` (default `repos/`). The workspace Git repository never commits or interferes with member repository contents.
