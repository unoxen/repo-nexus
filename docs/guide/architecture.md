---
title: Virtual Meta-Repo Architecture
description: Deep dive into the Repo Nexus workspace layout, member repository isolation, runtime directories, and delimited context merging.
---

# Virtual Meta-Repo Architecture

Repo Nexus coordinates multiple repositories through a declarative directory hierarchy that balances workspace-wide orchestration with complete member repository autonomy.

## Filesystem Layout

A fully initialized Repo Nexus workspace is structured as follows:

```text
my-workspace/
├── .git/                            # Meta-repo Git tracking (workspace config & docs only)
├── .gitignore                       # Ensures repos/ and local overrides remain untracked by Git
├── .ignore                          # Un-ignores repos/* for ripgrep, Claude Code, and search tools
├── rnex.yaml                        # Team-wide workspace declaration
├── .local.rnex.yaml                 # (Optional) Developer workstation overrides (gitignored)
│
├── .rnex/                           # Workspace orchestration directory (tracked)
│   ├── hooks/                       # Core workspace Git hooks (e.g. post-merge auto-sync)
│   ├── plugins/                     # Enabled plugin instructions, skills, and agents
│   └── prompts/                     # Standardized prompt library (audit, refactor, etc.)
│
├── repos/                           # Autonomous member repository clones (gitignored)
│   ├── backend/                     # Standard Git repository (remote: api.git)
│   │   ├── .git/
│   │   ├── .rnex/                   # Mirrored workspace context for localized AI agents
│   │   └── src/
│   └── frontend/                    # Standard Git repository (remote: web.git)
│       ├── .git/
│       ├── .rnex/
│       └── src/
│
├── AGENTS.md                        # Primary AI agent instructions (or CLAUDE.md / GEMINI.md)
└── workspace.code-workspace         # (Optional) VS Code / Cursor multi-root configuration
```

## Core Architectural Pillars

### 1. Member Repository Isolation & AI Search Discovery (`./repos/`)
Member repositories reside in `./repos/<name>/`. Each repository retains its own independent `.git` directory, remote tracking branches, tags, and commit history.

::: warning Never Commit `repos/` to Meta-Repo
Repo Nexus automatically configures `.gitignore` in the meta-repo root with:
```text
repos/*
!repos/.gitkeep
```
Member repository files are never tracked or committed to the parent meta-repo.
:::

To ensure code search tools (ripgrep, Claude Code, VS Code search) and AI indexers (Cursor codebase indexing, Gemini CLI) can discover and index member code across repos, Repo Nexus automatically maintains un-ignore files (`.ignore`, `.cursorignore`, `.geminiignore`) with `!repos/*`. This allows AI assistants and search engines to index code while meta-repo Git remains completely clean.

### 2. The `.rnex/` Orchestration Directory
The `.rnex/` directory holds active plugins, automation hooks, and the standardized prompt library:
* **`.rnex/prompts/`**: Reusable markdown prompts for common cross-repo workflows (workspace audit, cross-repo refactors, architecture summaries).
* **`.rnex/plugins/`**: Isolated directory per enabled plugin (`.rnex/plugins/<plugin-name>/`), preventing naming collisions between plugins.

### 3. Member Repository Context Mirroring
When an AI assistant (such as Claude Code, Cursor, or Gemini) operates inside a specific member repository (`repos/backend/`), it cannot inspect files outside that repository's root.

Repo Nexus solves this through **automated context projection**:
* Active plugins and shared prompts are mirrored into `repos/<name>/.rnex/`.
* Local instruction files (`repos/<name>/.rnex/instructions.md`) provide member-level awareness of the parent meta-repo.
* Member autonomy is preserved without duplicating maintenance.

### 4. Non-Destructive Delimited Merging
When Repo Nexus injects workspace routing rules into developer instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`), it isolates managed blocks inside explicit HTML comments:

```markdown
<!-- REPO-NEXUS:START -->
# Multi-Repo AI Workspace Context
This workspace operates as a Repo Nexus Virtual Meta-Repo uniting independent repositories.
...
<!-- REPO-NEXUS:END -->
```

::: tip Preserving Custom Instructions
Any custom guidelines, rules, or documentation authored outside the `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->` markers are strictly preserved during `rnex sync --fix` or plugin synchronization.
:::

### 5. Multi-Root IDE Workspaces
When enabled via `--code-workspace`, Repo Nexus generates a VS Code / Cursor `.code-workspace` file that automatically registers the workspace root and every active member repository in `./repos/`. Opening the workspace file opens all repositories in a single unified editor window.
