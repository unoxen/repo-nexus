---
title: Karpathy LLM & Agent Knowledge Wiki Plugin
description: Implement Andrej Karpathy's 4 cardinal principles for coding agents and autonomous zero-dependency LLM Wiki architecture in Repo Nexus.
---

# Karpathy LLM & Agent Knowledge Wiki Plugin

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants.

It requires **zero external vector databases, embedding pipelines, or heavy MCP infrastructure** — knowledge is represented as interlinked, version-controlled markdown pages with typed YAML frontmatter that AI agents navigate natively.

---

## What It Provides

### 1. The 4 Cardinal Principles for Coding Agents (`rules/behavioral.md`)
- **Think Before Coding**: State explicit assumptions, formulate the problem clearly, and evaluate trade-offs before touching code.
- **Simplicity First**: Minimal abstractions, readable implementations, and zero boilerplate bloat. Avoid premature optimization or speculative generalization.
- **Surgical Changes**: Minimize blast radius. Modify only what is strictly necessary, preserve existing comments/docstrings, and produce clean, reviewable diffs.
- **Goal-Driven Execution**: Define upfront verification criteria, write/run automated tests, and review diffs rigorously before completing tasks.

### 2. Multi-Repo Context Engineering & Autonomy (`rules/behavioral.md`)
- Guidelines tailored specifically for multi-repo virtual workspaces:
  - Always read workspace configuration (`.local.rnex.yaml` and `rnex.yaml`) first.
  - Respect member repository autonomy (`repos/<name>/`).
  - Read `wiki/hot.md` and `wiki/index.md` once per session for orientation.
  - Perform Git commits directly inside individual member repositories.

### 3. Autonomous LLM Wiki Architecture
A self-healing, agent-maintained knowledge graph structured as:

- **`./docs/` Intake Directory**:
  - Append-only directory where unmodified source material (articles, transcripts, docs, API references, meeting notes) is deposited.
  - Raw sources are immutable source-of-truth references for citations.
- **`wiki/` Curated Knowledge Base**:
  - Interlinked atomic markdown pages, each representing a single concept, architectural pattern, or domain decision (default directory: `wiki/` at workspace root).
  - Each page contains structured YAML frontmatter defining typed relations:
    ```yaml
    ---
    title: Workspace Configuration Protocol
    sources: [docs/rnex-design-spec.md]
    related: [wiki/member-repos.md, wiki/ai-routing.md]
    extends: [wiki/multi-repo-architecture.md]
    contradicts: []
    mentioned_in: []
    ---
    ```
- **`wiki/index.md` Navigation Index**:
  - Master categorized catalog organizing all atomic concepts, architecture decisions, and cross-project knowledge.
- **`wiki/hot.md` Rolling Context Cache**:
  - High-density ~500-word orientation summary for rapid agent onboarding without full wiki scans. Agents read this once on startup.
- **`wiki/_log.md` Audit Trail**:
  - Append-only log recording every ingest and lint operation with timestamped details and source attribution.

### 4. Standardized Agent Workflows
- **`wiki-ingest.md` (8-Step Ingestion Protocol)**:
  - Decomposes raw source documents from `./docs/` into 5–25 atomic wiki pages.
  - Formulates bi-directional frontmatter relations (`sources`, `related`, `extends`, `contradicts`).
  - Appends operations to `wiki/_log.md` and rebuilds `wiki/index.md`.
- **`wiki-lint.md` (10-Step Integrity Audit Protocol)**:
  - Validates inter-page link paths and file existence.
  - Recomputes reverse backlinks (`mentioned_in`).
  - Identifies and eliminates orphan pages.
  - Merges duplicate or overlapping pages.
  - Audits logical inconsistencies and flags outdated information.
  - Updates `wiki/hot.md` and rebuilds `wiki/index.md`.

### 5. Specialized Agent (`agents/wiki-curator.agent.md`)
- A dedicated autonomous curator agent configured to maintain the LLM Wiki graph, execute ingestion protocols, and perform periodic graph integrity audits.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable karpathy-llm

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local karpathy-llm
```

---

## Configuration Options

Configure options under `plugins.karpathy-llm` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  karpathy-llm:
    # Directory paths relative to workspace root (defaults shown)
    wiki_dir: wiki              # Directory for curated atomic markdown pages (default: wiki)
    sources:                    # Intake documents: directories and/or glob patterns
      - docs                    #   directory: all files (hidden dirs and node_modules pruned)
      - "repos/**/README.md"    #   recursive glob (quote it); disabled repos are excluded
                                # A sources list in .local.rnex.yaml replaces this list entirely.

    # Enable or disable
    enabled: true
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `wiki_dir` | string | `wiki` | Directory containing curated atomic markdown pages. |
| `sources` | list | `[docs, "repos/**/README.md"]` | Intake directories and/or glob patterns relative to workspace root. Overridable in `.local.rnex.yaml`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

### Intake Sources (`sources`)

The `sources` setting defines where the Karpathy LLM Wiki discovers raw intake documents for `wiki-ingest` and change verification:

- **Directory Paths (e.g. `docs`, `notes`)**: Repo Nexus recursively scans the directory for all files. Hidden directories (starting with `.`) and `node_modules` are automatically pruned.
- **Recursive Globs (e.g. `"repos/**/README.md"`)**: Pure POSIX `/bin/sh` pattern resolution matches files at arbitrary directory depths. Always quote globs containing `*` in YAML. Directories named `.git`, `.rnex`, and `node_modules` are pruned during traversal.
- **Single-Level Globs (e.g. `repos/*/README.md` or `docs/*.md`)**: Matches files at a fixed directory level.
- **Active Repository Filtering**: Any resolved path located within `repos/<name>/` is checked against member repository status. If a repository is disabled (`enabled: false`) in `rnex.yaml` or `.local.rnex.yaml`, its files are automatically excluded.
- **Two-Level Configuration Precedence**: If `sources` is declared in `.local.rnex.yaml`, it completely overrides the `sources` list defined in `rnex.yaml`.
- **Legacy Migration**: Existing configurations with `raw_dir: <dir>` are automatically rewritten to a `sources` list during `rnex sync`.
- **Directory Provisioning**: When running `rnex sync`, explicit directory entries (such as `docs`) are created automatically if missing. Glob patterns (containing `*`, `?`, or `[`) and file targets are never converted into directories.

---

## Plugin CLI Commands

The `karpathy-llm` plugin provides native command-line subcommands via the extensible `rnex plugin` engine:

### `rnex plugin karpathy-llm ingest`

Ingests raw intake documents and member repository READMEs into atomic, interlinked markdown pages in `wiki/`.

```sh
rnex plugin karpathy-llm ingest [options]
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--source <path>` | string | *(all sources)* | Ingest a specific markdown file or intake directory instead of all configured `sources`. |
| `--repo <name>` | string | *(all enabled repos)* | Ingest a specific member repository README (`repo-<name>.md`). |
| `-q, --quiet` | boolean | `false` | Suppress non-error informational progress messages. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

### `rnex plugin karpathy-llm lint`

Audits wiki graph integrity, validates required YAML frontmatter keys, checks source file existence, flags orphan pages unreferenced in `index.md`, and enforces the ~500-word ceiling on `hot.md`.

```sh
rnex plugin karpathy-llm lint [options]
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--strict` | boolean | `false` | Treat warnings (broken sources, orphaned pages, `hot.md` word overflow) as errors and exit with a non-zero code. |
| `-q, --quiet` | boolean | `false` | Suppress non-error informational messages. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

---

## Automated Git Hooks Integration

Integrate wiki integrity checks into your Git workflow using the declarative `git.hooks` configuration in `rnex.yaml`:

```yaml
git:
  hooks:
    pre-commit:
      - "rnex plugin karpathy-llm lint"
    post-merge:
      - "rnex sync --quiet"
```

During `rnex init` or `rnex sync`, Repo Nexus installs Git hook dispatchers in `.git/hooks/` that automatically execute the configured commands.

---

## Generated Directory Structure

When `karpathy-llm` is enabled, it scaffolds:

```text
my-workspace/
├── docs/
│   └── .gitkeep                     # Deposit unmodified source files here
├── wiki/
│   ├── index.md                     # Master navigation catalog
│   ├── hot.md                       # High-density ~500-word orientation summary
│   └── _log.md                      # Append-only audit history
├── .rnex/
│   └── plugins/
│       └── karpathy-llm/
│           ├── rules/
│           │   └── behavioral.md         # 4 Cardinal principles & context engineering
│           ├── commands/
│           │   ├── ingest.sh             # CLI subcommand handler
│           │   └── lint.sh               # CLI subcommand handler
│           ├── skills/
│           │   ├── wiki-ingest.md        # Agentic skill for wiki ingestion
│           │   └── wiki-lint.md          # Agentic skill for wiki linting
│           ├── hooks/
│           │   ├── after_sync.sh         # Reconciles wiki intake & registers user skills
│           │   └── before_plugin_disable.sh # Unregisters user skills
│           ├── agents/
│           │   └── rnex-wiki-curator.agent.md
│           └── templates/
│               ├── rnex-wiki-page.template.md
│               └── rnex-llm-wiki.sample.md
└── rnex.yaml
```

---

## User Skills & Provider Integration

The `karpathy-llm` plugin encapsulates its agentic skills in `.rnex/plugins/karpathy-llm/skills/`:
- `wiki-ingest.md`
- `wiki-lint.md`

During `rnex sync`, its `after_sync.sh` lifecycle hook automatically registers zero-logic User Skill pointers (`rnex-karpathy-llm-wiki-ingest` and `rnex-karpathy-llm-wiki-lint`) across all enabled AI provider directories (`.cursor/rules/`, `.claude/skills/`, `.agents/skills/`, `.windsurf/rules/`).

When running `rnex plugin disable karpathy-llm`, its `before_plugin_disable.sh` lifecycle hook automatically unregisters the User Skills from all provider directories, while keeping core workspace skills intact.

---

## Disabling the Plugin

```sh
rnex plugin disable karpathy-llm
```

When disabled:
- Scoped assets under `.rnex/plugins/karpathy-llm/` and member repository mirrors are cleanly removed.
- **Your data in `./docs/` and `wiki/` is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
