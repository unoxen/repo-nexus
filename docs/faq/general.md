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

---

## Implementation & Portability

### Why is rnex written in pure POSIX `/bin/sh`?
`repo-nexus` is implemented entirely in pure POSIX-compliant `/bin/sh` with zero external runtime dependencies (no Node.js, Python, or Rust required):
- **Universal Portability**: Runs out-of-the-box on macOS, Linux, WSL2, Git Bash on Windows, and minimal Docker or CI/CD container environments.
- **Zero Bootstrap Overhead**: Does not require installing package managers, compiling binaries, or downloading multi-megabyte dependencies before executing commands.
- **Deterministic Reliability**: Relies exclusively on standard POSIX utilities (`awk`, `sed`, `grep`, `cat`, `mkdir`, `cp`, `rm`, `git`), avoiding version incompatibilities across operating systems.

---

## Configuration & Local Overrides

### How does the 3-tier configuration hierarchy work?
Repo Nexus resolves settings through a deterministic, 3-tier priority hierarchy:
1. **Tier 1 (Highest Priority) — `.local.rnex.yaml`**: Uncommitted, developer-specific overrides on your local machine (e.g. customized paths, disabled repositories, machine-specific hooks). List values in `.local.rnex.yaml` replace the corresponding team list.
2. **Tier 2 — `rnex.yaml`**: The committed team manifest defining active member repositories, default branches, shared plugins, and workspace lifecycle hooks.
3. **Tier 3 (Lowest Priority) — `plugin.yaml`**: Built-in default configuration options defined within individual plugin manifests.

Whenever you update configuration files, running `rnex sync` reconciles the workspace harness (`.rnex/`) and generated AI context.

### How can I skip cloning or running commands on repositories I don't work on locally?
You can disable individual repositories locally without modifying the shared `rnex.yaml`:
```bash
rnex repo set <repo-name> --disable --local
```
This writes `enabled: false` for that repository into `.local.rnex.yaml`. Subsequent executions of `rnex clone` and `rnex exec` will automatically skip that repository on your machine while leaving the team configuration untouched.

---

## AI Context Routing & Provider Plugins

### Why is `AGENTS.md` a lean routing file instead of containing all prompts inline?
`repo-nexus` follows the **Routing-Only Principle** for top-level agent instruction files:
- **Token Economy**: Storing exhaustive instructions, schema definitions, and rules in `AGENTS.md` wastes large amounts of context window tokens on every agent interaction.
- **Single Source of Truth**: Detailed workspace rules, environment paths, and conventions reside in `.rnex/ai-instructions.md`, compiled dynamically during `rnex sync`.
- **Targeted Navigation**: `AGENTS.md` acts as a lean router that directs AI coding assistants (Claude Code, Cursor, Codex, Gemini, Copilot, Windsurf) to specific workspace contracts, repository maps, and plugin documentation on demand.

### Are AI instruction files generated automatically by default?
Yes, core routing files like `AGENTS.md` are established during `rnex init`. Specific provider tool configurations (e.g. `.cursor/rules/`, `.github/copilot-instructions.md`, `CLAUDE.md`) follow an **opt-in AI projection model**: they are generated and kept synchronized only when their corresponding provider plugins (`cursor`, `copilot`, `claude`, `gemini`, `codex`, `windsurf`) are enabled.

---

## Karpathy LLM Wiki (`karpathy-llm`)

### How does the Karpathy LLM Wiki differ from traditional RAG?
Traditional Retrieval-Augmented Generation (RAG) splits raw documents into arbitrary text chunks and dynamically retrieves top-k matches to synthesize answers from scratch on every query.

In contrast, the **Karpathy LLM Wiki** architecture:
- **Synthesizes Once on Ingest**: Source documents and member repository documentation are compiled into atomic, structured Markdown pages under your configured wiki directory (default `.rnex/wiki/`).
- **Knowledge Compounding**: Curated pages link to related concepts using standard Markdown links (`[Title](./page.md)`) and typed frontmatter graphs (`sources`, `related`, `extends`), allowing knowledge quality to compound over time as the codebase evolves.
- **Deterministic Navigation**: Agents navigate compiled domain knowledge systematically via the B-Tree root table (`index.md`) and flat domain shards (`repo-nexus*.md`, `repos-<member>*.md`) without exploratory trial-and-error searches.

### What is the structure of the flat B-Tree Karpathy LLM Wiki?
Each core wiki asset has a distinct architectural responsibility directly under `.rnex/wiki/` (or custom configured `wiki_dir`):
- **`index.md` (B-Tree Root Router)**: Strictly bounded under 80 lines with zero YAML frontmatter. Contains a compact routing table mapping domain key ranges to flat leaf shards in `.rnex/wiki/`.
- **`repo-nexus*.md` & `repos-<member>*.md` (Sorted Flat Leaf Shards)**: Domain-partitioned catalogs sorted in strict `LC_ALL=C` order. Automatically splits into alphabetical sub-shards (e.g. `repo-nexus-a-m.md`, `repo-nexus-n-z.md`) when entry thresholds are exceeded.
- **`log.md` (Operational Audit Trail)**: An append-only, timestamped log recording every source ingestion, shard rebalance, and lint validation run. Recent activity is checked with `tail -n 20 .rnex/wiki/log.md`.

### Why were TSV property graphs (`_graph/`) and legacy wrappers removed?
Plain TSV graphs (`nodes.tsv`, `edges_out.tsv`, `edges_in.tsv`) and nested directory wrappers (`_index/`, `_graph/`) added unnecessary multi-table bookkeeping and synchronization complexity. Modern AI coding assistants and native workspace search tools (`grep`, `ripgrep`) resolve backlinks and references instantaneously directly from the codebase. Eliminating property graphs and subdirectory prefixes provides:
1. **Flat Zero-Prefix Simplicity**: All shard files and root control files reside directly under `.rnex/wiki/` (`index.md`, `log.md`, `repo-nexus*.md`, `repos-*.md`).
2. **Strictly Bounded Context**: `index.md` is guaranteed to remain $\le 80$ lines regardless of repository size.
3. **Predictable Token Consumption**: Agents navigate via a 3-step retrieval protocol (Root Router $\to$ Leaf Shard $\to$ In-Place Source Document) loading only the exact knowledge required.
4. **Zero Dependencies & Zero Symlinks**: Operates purely on standard POSIX shell tools (`awk`, `sed`, `grep`, `sort`) with zero symlinks, ensuring cross-platform safety on Windows, Linux, and macOS.

### Can I ingest a single document or specific repository?
Yes. The `ingest` command supports granular targeting and processes only missing sources by default:
```bash
# Ingest a single source document
rnex plugin karpathy-llm ingest docs/spec.md
# Or using the --file flag
rnex plugin karpathy-llm ingest --file docs/spec.md

# Batch-ingest all configured sources
rnex plugin karpathy-llm ingest
```

---

## Automation, Lifecycle Hooks & Git Hooks

### What is the difference between Lifecycle Hooks and Git Hooks?
- **Lifecycle Hooks**: Orchestration events triggered by `rnex` CLI commands (configured under `hooks:` in `rnex.yaml` or `.local.rnex.yaml`). Supported events include `before_sync`, `after_sync`, `before_clone`, `after_clone`, `before_repo_add`, `after_repo_add`, `before_exec`, and `after_exec`.
- **Git Hooks**: Native Git client hooks installed directly into the workspace root `.git/hooks/` directory (e.g. `pre-commit`, `commit-msg`, `pre-push`). When Repo Nexus configures Git hooks, any pre-existing local hook is safely preserved as `<hook>.user` and chained non-destructively.
