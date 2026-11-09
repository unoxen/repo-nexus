---
title: Karpathy LLM & Agent Knowledge Wiki Plugin
description: Implement Andrej Karpathy's 4 cardinal principles for coding agents and autonomous zero-dependency flat B-Tree LLM Wiki architecture in Repo Nexus.
---

# Karpathy LLM & Agent Knowledge Wiki Plugin

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants.

It requires **zero external vector databases, embedding pipelines, or heavy MCP infrastructure** — knowledge is indexed directly in place into a flat B-Tree sharded index (`.rnex/wiki/*.md`, or a custom configured `wiki_dir`), organized by a bounded root router (`.rnex/wiki/index.md`), and recorded in a chronological audit log (`.rnex/wiki/log.md`) that AI agents navigate natively.

![Karpathy LLM Wiki](/karpathy-llm.jpeg)

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
  - Respect member repository autonomy (`<repos_dir>/<name>/`, default `repos/<name>/`).
  - Follow the deterministic 3-step retrieval protocol: B-Tree Root Router (`.rnex/wiki/index.md`) $\to$ Domain Shard (`.rnex/wiki/<shard>.md`) $\to$ In-Place Source Document.
  - Perform Git commits directly inside individual member repositories.

### 3. Flat Zero-Prefix B-Tree Wiki Architecture
A self-healing, agent-maintained knowledge base structured directly under `.rnex/wiki/` (or custom configured `wiki_dir`):

- **Authoritative Source Materials**:
  - Unmodified source documents (`README.md`, `docs/*.md`, `RFC/*.md`, and member repositories `<repos_dir>/<name>/**/*.md`) are inspected and indexed directly in place.
  - Zero duplicate file copies and zero symbolic links (`concepts/` and `repos/` subdirectories inside wiki are completely eradicated).
  - Intake sources are fully configurable via `sources` under `plugins.karpathy-llm`.
- **`.rnex/wiki/index.md` B-Tree Root Router**:
  - Compact, strictly bounded routing table ($\le 80$ lines, zero YAML frontmatter) organizing domain shards with key ranges and entry counts.
- **`.rnex/wiki/repo-nexus*.md` & `.rnex/wiki/repos-*.md` Flat Leaf Shards**:
  - Lexicographically sorted domain leaf pages (`repo-nexus.md`, `repos-<member-repo>.md`, `repos-<member-repo>-<subscope>.md`). Automatically split into alphabetical sub-shards (e.g. `repo-nexus-a-m.md`, `repo-nexus-n-z.md`) when exceeding capacity thresholds.
- **`.rnex/wiki/log.md` Operational Audit Trail**:
  - Shared append-only log recording source ingestion events when new sources are indexed into the wiki. Inspected with `tail -n 20 .rnex/wiki/log.md`.

### 4. Standardized Agent Workflows
- **`wiki-ingest.md` (Ingestion Protocol)**:
  - Scans workspace documentation and indexes missing sources in place without touching already-indexed entries.
  - Rebalances flat B-Tree leaf shards directly in `.rnex/wiki/`, compiles `.rnex/wiki/index.md`, and updates `.rnex/wiki/log.md` when new sources are added.
- **`wiki-lint.md` (Integrity Audit Protocol)**:
  - Standalone structural and reference audit without running ingestion or mutating source files.
  - Auto-heals directory structures, links orphan shards, prunes dead references, and re-sorts catalog entries in `LC_ALL=C` order.
  - Purges deprecated legacy files (`hot.md`, `_index.md`, `_log.md`) and subdirectories (`_graph/`, `_index/`).
  - Enforces zero symbolic links across the `.rnex/wiki/` directory.
  - Enforces the $\le 80$ line budget on root `.rnex/wiki/index.md`.
  - Conditional audit logging: mutates `log.md` only when repairs are made; zero changes on clean runs.
- **`wiki-query.md` (3-Step Retrieval Protocol)**:
  - Guides AI agents through deterministic knowledge lookup: Root Router (`index.md`) $\to$ Domain Shard (`<shard>.md`) $\to$ In-Place Source Document.

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
    # Directory paths and control files relative to workspace root (defaults shown)
    wiki_dir: ".rnex/wiki"      # Directory for curated flat markdown shards (default: .rnex/wiki)
    index_file: "index.md"      # B-Tree Root Router filename (default: index.md)
    log_file: "log.md"          # Chronological audit log filename (default: log.md)
    btree_root_max_lines: 80    # Maximum allowed lines in root index.md router (default: 80)
    btree_shard_max_entries: 100# Threshold before splitting a B-Tree shard (default: 100)
    sources:                    # Intake documents: directories and/or glob patterns
      - docs                    #   directory: all files (hidden dirs and node_modules pruned)
      - "repos/**/README.md"    #   recursive glob (quote it); disabled repos are excluded
                                # A sources list in .local.rnex.yaml replaces this list entirely.

    # Enable or disable
    enabled: true
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `wiki_dir` | string | `".rnex/wiki"` | Directory containing flat markdown shards and router files. |
| `index_file` | string | `index.md` | B-Tree Root Router filename within `wiki_dir`. |
| `log_file` | string | `log.md` | Chronological audit log filename within `wiki_dir`. |
| `btree_root_max_lines` | integer | `80` | Ceiling on lines allowed in `index.md`. |
| `btree_shard_max_entries` | integer | `100` | Entry count threshold before automatically splitting a shard. |
| `sources` | list | `[docs, "repos/**/README.md"]` | Intake directories and/or glob patterns relative to workspace root. Overridable in `.local.rnex.yaml`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

### Intake Sources (`sources`)

The `sources` setting defines where the Karpathy LLM Wiki discovers documentation for in-place indexing:

- **Directory Paths (e.g. `docs`, `notes`)**: Repo Nexus recursively scans the directory for all Markdown files. Hidden directories (starting with `.`) and `node_modules` are automatically pruned.
- **Recursive Globs (e.g. `"repos/**/README.md"`)**: Pure POSIX `/bin/sh` pattern resolution matches files at arbitrary directory depths. Always quote globs containing `*` in YAML. Directories named `.git`, `.rnex`, and `node_modules` are pruned during traversal.
- **Active Repository Filtering**: Any resolved path located within `<repos_dir>/<name>/` (default `repos/<name>/`) is checked against member repository status. If a repository is disabled (`enabled: false`) in `rnex.yaml` or `.local.rnex.yaml`, its files are automatically excluded.
- **Two-Level Configuration Precedence**: If `sources` is declared in `.local.rnex.yaml`, it completely overrides the `sources` list defined in `rnex.yaml`.

---

## Plugin CLI Commands

The `karpathy-llm` plugin exposes a streamlined, focused 2-command CLI surface:

### `rnex plugin karpathy-llm ingest`

Ingests and indexes authoritative workspace documents and member repository documentation directly in place into flat B-Tree shards in `.rnex/wiki/*.md` (or custom `wiki_dir`) and rebalances `index.md`.

Ingestion operates on a **missing-sources-only** basis: it inspects already-indexed workspace paths within the wiki shards and skips them, only compiling newly added or unindexed sources. Existing manual summaries and edits are preserved untouched.

```sh
# Ingest missing workspace sources and enabled member repos
rnex plugin karpathy-llm ingest

# Ingest a specific markdown source file directly in place
rnex plugin karpathy-llm ingest docs/architecture.md
# Or using the --file flag
rnex plugin karpathy-llm ingest --file docs/architecture.md

# Run quietly
rnex plugin karpathy-llm ingest --quiet
```

| Argument / Option | Type | Default | Description |
|:---|:---|:---|:---|
| `<file_path>` | string | *(all missing sources)* | Ingest a single specified markdown file directly. |
| `--file, -f <path>` | string | *(all missing sources)* | Ingest a specific markdown file. |
| `--quiet, -q` | boolean | `false` | Suppress non-essential informational output. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

### `rnex plugin karpathy-llm lint`

Standalone structural, reference, and sorting audit for the wiki. Inspects directory structures, verifies link targets, checks sorting order (`LC_ALL=C`), asserts zero symbolic links, and verifies the $\le 80$ line ceiling on `index.md` without modifying files or writing to `log.md`:

```sh
# Audit wiki integrity (standalone, zero ingestion)
rnex plugin karpathy-llm lint

# Strict mode: fail on any warning
rnex plugin karpathy-llm lint --strict

# Run quietly
rnex plugin karpathy-llm lint --quiet
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--strict, -s` | boolean | `false` | Fail with exit code 1 if any warnings or structural issues are detected. |
| `--quiet, -q` | boolean | `false` | Suppress non-essential informational output. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

---

### Automated Ingestion via Workspace Lifecycle Hooks

Core `rnex sync` is completely decoupled from plugin ingestion. To automatically run ingestion whenever `rnex sync` is executed, configure declarative `rnex_hooks.after_sync` in `rnex.yaml`:

```yaml
rnex_hooks:
  after_sync:
    - "rnex plugin karpathy-llm ingest"
```

---

## Retrieval Protocol: How AI Agents Query the Wiki

Autonomous AI coding agents navigate the wiki using a deterministic 3-step retrieval protocol without needing vector embeddings or external MCP services:

1. **Step 1 — Root Read**: Read `.rnex/wiki/index.md` ($\le 80$ lines) to locate the target shard file (`repo-nexus*.md` or `repos-<member>*.md`).
2. **Step 2 — Leaf Shard Read**: Read the target shard directly in `.rnex/wiki/` to find the exact source file path and summary.
3. **Step 3 — In-Place Access**: Read the authoritative source file directly where it resides in the workspace. Cross-references and backlinks are discovered natively using standard workspace search tools (`grep`, `ripgrep`).

---

## Automated Git Hooks Integration

Integrate wiki integrity checks into your Git workflow using declarative `git.hooks` configuration in `rnex.yaml`:

```yaml
git:
  hooks:
    pre-commit:
      - "rnex plugin karpathy-llm lint"
    post-merge:
      - "rnex sync --quiet"
```

---

## Generated Directory Structure

When `karpathy-llm` is enabled, it maintains:

```text
my-workspace/
├── docs/                            # Workspace documentation
│   └── architecture.md
├── repos/                           # Member repositories (inspected in-place)
│   └── <member-repo>/
│       └── README.md
├── .rnex/
│   ├── wiki/                        # Default wiki directory (configurable via wiki_dir)
│   │   ├── index.md                 # B-Tree Root Router (<= 80 lines)
│   │   ├── log.md                   # Chronological audit history
│   │   ├── repo-nexus.md            # Nexus repo shard (or repo-nexus-a-m.md, etc.)
│   │   └── repos-<member-repo>.md   # Member repo shard (e.g. repos-backend-apps.md)
│   └── plugins/
│       └── karpathy-llm/
│           ├── instructions/
│           │   ├── rnex-wiki-architecture.md
│           │   └── rnex-scaffolding-meta-prompt.md
│           ├── rules/
│           │   └── behavioral.md
│           ├── skills/
│           │   ├── wiki-ingest.md
│           │   ├── wiki-lint.md
│           │   └── wiki-query.md
│           ├── bin/
│           │   ├── ingest.sh
│           │   └── lint.sh
│           └── lib/
│               ├── config.sh
│               ├── utils.sh
│               ├── source_helpers.sh
│               ├── btree_helpers.sh
│               └── lint_helpers.sh
└── rnex.yaml
```

---

## User Skills & Provider Integration

The `karpathy-llm` plugin encapsulates its agentic skills in `.rnex/plugins/karpathy-llm/skills/`:
- `wiki-ingest.md`
- `wiki-lint.md`
- `wiki-query.md`

During `rnex sync`, its `after_sync.sh` lifecycle hook automatically registers zero-logic User Skill pointers (`rnex-karpathy-llm-wiki-ingest`, `rnex-karpathy-llm-wiki-lint`, and `rnex-karpathy-llm-wiki-query`) across all enabled AI provider directories (`.cursor/rules/`, `.claude/skills/`, `.agents/skills/`, `.codex/skills/`, `.github/skills/`, `.windsurf/rules/`).

When running `rnex plugin disable karpathy-llm`, its lifecycle hook automatically unregisters the User Skills from all provider directories, while keeping user data in `.rnex/wiki/` (or custom `wiki_dir`) intact.

---

## Disabling the Plugin

```sh
rnex plugin disable karpathy-llm
```

When disabled:
- Scoped assets under `.rnex/plugins/karpathy-llm/` are cleanly removed.
- **Your data in `.rnex/wiki/` (or custom `wiki_dir`) and `./docs/` is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
