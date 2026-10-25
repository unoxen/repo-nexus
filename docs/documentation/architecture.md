---
title: Virtual Meta-Repo Architecture
description: Deep dive into the Repo Nexus workspace layout, member repository isolation, runtime directories, delimited context merging, and architecture diagram.
---

# Virtual Meta-Repo Architecture

Repo Nexus coordinates multiple repositories through a declarative directory hierarchy that balances workspace-wide orchestration with complete member repository autonomy.

## Architecture Diagram

The following diagram illustrates how configuration flows through the core engine to manage tracked meta-repo assets, git-ignored runtime files, and autonomous member clones:

```mermaid
flowchart TB
    classDef config fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#f8fafc
    classDef engine fill:#0f172a,stroke:#818cf8,stroke-width:2px,color:#f8fafc
    classDef tracked fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#f8fafc
    classDef ignored fill:#3f1d2e,stroke:#f472b6,stroke-width:2px,stroke-dasharray: 5 5,color:#f8fafc
    classDef repo fill:#1e1b4b,stroke:#a78bfa,stroke-width:2px,color:#f8fafc

    subgraph ConfigLayer["1. Two-Level Configuration (Single Source of Truth)"]
        direction LR
        LocalYaml[".local.rnex.yaml<br/>(Machine Overrides — Priority 1)"]:::config
        SharedYaml["rnex.yaml<br/>(Shared Team Manifest — Priority 2)"]:::config
        
        subgraph SchemaSections["Configuration Schema"]
            GitSchema["git:<br/>• ignore: [repos/, **/.rnex*/, **/rnex*/]<br/>• hooks: {post-merge: [...], pre-commit: [...]}"]:::config
            RnexHooksSchema["rnex_hooks:<br/>• after_sync: [...]<br/>• after_clone: [...]<br/>• before_exec: [...]"]:::config
            ReposSchema["repos:<br/>• url, branch, enabled, readonly"]:::config
            PluginsSchema["plugins:<br/>• claude, cursor, codex, gemini,<br/>  windsurf, copilot, karpathy-llm"]:::config
        end

        LocalYaml -->|Overrides| SharedYaml
        SharedYaml --> SchemaSections
    end

    subgraph CoreEngine["2. Repo Nexus Core Engine (Pure POSIX /bin/sh)"]
        direction TB
        CLI["rnex CLI Router &amp; Lifecycle Hook Dispatcher<br/>(Fires rnex_hooks.&lt;event&gt; before/after every command)"]:::engine

        subgraph WorkspaceCmds["Workspace Commands"]
            WSInitSync["rnex init | rnex sync<br/>(Reconciles Workspace, Hooks &amp; AI Context)"]:::engine
            WSBatch["rnex clone | rnex status | rnex exec<br/>(Batch Operations Across Enabled Repos)"]:::engine
        end

        subgraph RepoCmds["Single-Repo Commands (rnex repo ...)"]
            RepoAddRemove["rnex repo add &lt;url&gt; [--name] [--branch]<br/>rnex repo remove &lt;name&gt;"]:::engine
            RepoSet["rnex repo set &lt;name&gt;<br/>[--enable|--disable] [--readonly|--readwrite]"]:::engine
            RepoScoped["rnex repo clone | status | exec &lt;name&gt;"]:::engine
        end

        subgraph PluginCmds["Plugin Engine (rnex plugin ...)"]
            PluginLifecycle["rnex plugin list | info | enable | disable"]:::engine
            PluginExec["rnex plugin &lt;name&gt; &lt;command&gt; [options]<br/>(e.g., karpathy-llm ingest | lint)"]:::engine
        end

        CLI --> WorkspaceCmds
        CLI --> RepoCmds
        CLI --> PluginCmds
    end

    subgraph GitTracked["3. Git-Tracked Meta-Repo Assets (Permanent Knowledge)"]
        direction TB
        MainContext["Permanent AI Routing Context Files<br/>• AGENTS.md (Universal Router)<br/>• CLAUDE.md | GEMINI.md | CODEX.md<br/>• .cursorrules | .windsurfrules<br/>• .github/copilot-instructions.md"]:::tracked
        CuratedWiki["Karpathy LLM Wiki Graph (./wiki/)<br/>• wiki/index.md (Entrypoint)<br/>• wiki/hot.md (~500w Cache)<br/>• wiki/_log.md &amp; wiki/repo-*.md"]:::tracked
        GitIgnoreFile[".gitignore<br/>(Managed deterministically via git.ignore)"]:::tracked
    end

    subgraph GitIgnored["4. Git-Ignored Runtime &amp; Generated Assets (**/.rnex*/, **/rnex*/, repos/)"]
        direction TB
        RnexDir[".rnex/ Internal Harness<br/>• .rnex/ai-instructions.md<br/>• .rnex/skills/ &amp; .rnex/plugins/&lt;name&gt;/commands/<br/>• .rnex/sync_stamp"]:::ignored
        AIProxies["Generated AI Skill &amp; Rule Proxies (rnex-*)<br/>• .claude/skills/rnex-* | .codex/skills/rnex-*<br/>• .agents/skills/rnex-* | .cursor/rules/rnex-*<br/>• .windsurf/rules/rnex-* | .github/skills/rnex-*"]:::ignored
        GitHooksDir[".git/hooks/* Wrappers<br/>(Executes git.hooks command lists)"]:::ignored

        subgraph MemberRepos["./repos/ (Autonomous Member Clones — No Git Submodules)"]
            RepoA["repos/backend/<br/>(Standalone .git, branch, remotes)"]:::repo
            RepoB["repos/frontend/<br/>(Standalone .git, branch, remotes)"]:::repo
            RepoC["repos/shared-contracts/<br/>(Read-Only / Selective Clone)"]:::repo
        end
    end

    SchemaSections -->|Parsed by lib/yaml.sh| CLI
    RepoAddRemove -->|Updates repos:| SharedYaml
    RepoSet -->|Updates state| LocalYaml

    WSInitSync -->|Maintains permanent routing| MainContext
    WSInitSync -->|Reconciles ignore rules| GitIgnoreFile
    WSInitSync -->|Bundles skills &amp; plugins| RnexDir
    WSInitSync -->|Projects rnex-* proxies| AIProxies
    WSInitSync -->|Installs hook wrappers| GitHooksDir

    WSBatch -->|Clones &amp; executes across| MemberRepos
    RepoScoped -->|Operates on single repo| MemberRepos

    GitHooksDir -.->|Triggers git.hooks commands| CLI
    PluginExec -->|Ingests READMEs &amp; docs / Lints graph| CuratedWiki
    MemberRepos -.->|Read by karpathy-llm ingest| PluginExec
    MainContext -.->|Routes AI Assistants to| RnexDir
    MainContext -.->|Routes AI Assistants to| CuratedWiki
```

---

## Filesystem Layout

A fully initialized Repo Nexus workspace is structured as follows:

```text
my-workspace/
├── .git/                            # Meta-repo Git tracking (workspace config & docs only)
├── .gitignore                       # Managed deterministically via git.ignore
├── .ignore                          # Un-ignores repos/* for ripgrep, Claude Code, and search tools
├── rnex.yaml                        # Team-wide workspace declaration
├── .local.rnex.yaml                 # (Optional) Developer workstation overrides (gitignored)
│
├── .rnex/                           # Workspace orchestration directory (gitignored)
│   ├── ai-instructions.md           # Compiled AI routing & plugin context
│   ├── sync_stamp                   # Checksum-based drift detection stamp
│   ├── plugins/                     # Enabled plugin instructions, skills, and agents
│   └── skills/                      # Core workspace agentic skills (clone-sync, batch-exec, etc.)
│
├── repos/                           # Autonomous member repository clones (gitignored)
│   ├── backend/                     # Standard Git repository (remote: api.git)
│   │   ├── .git/
│   │   └── src/
│   └── frontend/                    # Standard Git repository (remote: web.git)
│       ├── .git/
│       └── src/
│
├── AGENTS.md                        # Permanent universal AI agent router
├── CLAUDE.md                        # Permanent Claude Code router
├── CODEX.md                         # Permanent OpenAI Codex router
└── workspace.code-workspace         # (Optional) VS Code / Cursor multi-root configuration
```

## Core Architectural Pillars

### 1. Member Repository Isolation & Autonomous Git Roots (`./repos/`)
Member repositories reside in `./repos/<name>/`. Each repository retains its own independent `.git` directory, remote tracking branches, tags, and commit history.

::: warning Never Commit `repos/` to Meta-Repo
Repo Nexus automatically configures `.gitignore` in the meta-repo root with:
```text
repos/
**/.rnex*/
**/rnex*/
```
Member repository files are never tracked or committed to the parent meta-repo.
:::

To ensure code search tools (ripgrep, Claude Code, VS Code search) and AI indexers (Cursor codebase indexing, Gemini CLI) can discover and index member code across repos, Repo Nexus automatically maintains un-ignore files (`.ignore`, `.cursorignore`, `.geminiignore`) with `!repos/*`. This allows AI assistants and search engines to index code while meta-repo Git remains completely clean.

### 2. The `.rnex/` Orchestration Directory
The `.rnex/` directory encapsulates active plugins, automation hooks, and agentic skills:
* **`.rnex/skills/`**: Core workspace-wide agentic skills owned by `rnex` (`clone-sync.md`, `batch-exec.md`, `workspace-status.md`).
* **`.rnex/plugins/`**: Isolated directory per enabled plugin (`.rnex/plugins/<plugin-name>/`), encapsulating plugin-owned skills, rules, and commands without naming collisions.

### 3. Non-Destructive Delimited Merging & Permanent Routing
Repo Nexus injects workspace routing rules into developer instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CODEX.md`, `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`) by isolating managed blocks inside explicit HTML comments:

```markdown
<!-- REPO-NEXUS:START -->
CRITICAL: You MUST read and strictly follow all instructions in `.rnex/ai-instructions.md` before executing any task or answering any query in this workspace.
<!-- REPO-NEXUS:END -->
```

::: tip Preserving Custom Instructions
Any custom guidelines, rules, or documentation authored outside the `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->` markers are strictly preserved during `rnex sync` or plugin reconfiguration.
:::

### 4. Multi-Root IDE Workspaces
When enabled via `--code-workspace`, Repo Nexus generates a VS Code / Cursor `.code-workspace` file that automatically registers the workspace root and every active member repository in `./repos/`. Opening the workspace file opens all repositories in a single unified editor window.
