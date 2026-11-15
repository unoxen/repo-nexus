---
title: LLM Wiki & Agent Knowledge Plugin
description: Implement the 4 cardinal principles for coding agents and autonomous zero-dependency flat B-Tree LLM Wiki architecture in Repo Nexus.
---

# LLM Wiki & Agent Knowledge Plugin

The **`llm-wiki`** plugin packages agent behavioral principles, multi-repo context engineering standards, and the autonomous **LLM Wiki** knowledge architecture (based on the Karpathy LLM Wiki pattern) for AI coding assistants.

It requires **zero external vector databases, embedding pipelines, or heavy MCP infrastructure** — knowledge is indexed directly in place into a flat B-Tree sharded index (`<wiki_dir>/*.md`, configured via `plugins.llm-wiki.wiki_dir`), organized by a bounded root router (`<wiki_dir>/<index_file>`, configured via `plugins.llm-wiki.index_file`), and recorded in a chronological audit log (`<wiki_dir>/<log_file>`, configured via `plugins.llm-wiki.log_file`) that AI agents navigate natively.

![LLM Wiki](/llm-wiki.jpeg)

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
  - Respect member repository autonomy (`<repos_dir>/<name>/`, configured via `repos_dir`).
  - Follow the deterministic 3-step retrieval protocol: B-Tree Root Router (`<wiki_dir>/<index_file>`) $\to$ Domain Shard (`<wiki_dir>/<shard>.md`) $\to$ In-Place Source Document.
  - Perform Git commits directly inside individual member repositories.

### 3. Flat Zero-Prefix B-Tree Wiki Architecture
A self-healing, agent-maintained knowledge base structured directly under `<wiki_dir>/` (configured via `plugins.llm-wiki.wiki_dir`):

- **Authoritative Source Materials**:
  - Unmodified source documents configured via `plugins.llm-wiki.sources` are inspected and indexed directly in place.
  - Zero duplicate file copies and zero symbolic links.
  - Intake sources are fully configurable via `plugins.llm-wiki.sources`.
- **`<wiki_dir>/<index_file>` B-Tree Root Router**:
  - Compact, strictly bounded routing table (maximum allowed lines configured via `plugins.llm-wiki.btree_root_max_lines`, zero YAML frontmatter) organizing domain shards with key ranges and entry counts.
- **`<wiki_dir>/repo-nexus*.md` & `<wiki_dir>/repos-*.md` Flat Leaf Shards**:
  - Lexicographically sorted domain leaf pages (`repo-nexus.md`, `repos-<member-repo>.md`, `repos-<member-repo>-<subscope>.md`). Automatically split into alphabetical sub-shards (e.g. `repo-nexus-a-m.md`, `repo-nexus-n-z.md`) when exceeding `plugins.llm-wiki.btree_shard_max_entries`.
- **`<wiki_dir>/<log_file>` Operational Audit Trail**:
  - Shared append-only log recording granular document lifecycle events (`created`, `updated`, `deleted`) and operational summaries when sources are ingested or repaired. Automatically trimmed to `plugins.llm-wiki.log_max_records` (default: 1000) by cutting oldest entries first. Inspected with `tail -n 20 <wiki_dir>/<log_file>`.

### 4. Standardized Agent Workflows
- **`ingest.md` (Ingestion Protocol)**:
  - Scans workspace documentation configured under `plugins.llm-wiki.sources` and indexes missing sources in place without touching already-indexed entries.
  - Rebalances flat B-Tree leaf shards directly in `<wiki_dir>/`, compiles `<wiki_dir>/<index_file>`, and updates `<wiki_dir>/<log_file>` when new sources are added.
- **`lint.md` (Integrity Audit Protocol)**:
  - Standalone structural and reference audit without running ingestion or mutating source files.
  - Auto-heals directory structures, links orphan shards, prunes dead references, and re-sorts catalog entries in `LC_ALL=C` order.
  - Enforces zero symbolic links across the `<wiki_dir>/` directory.
  - Enforces the maximum allowed lines in `<wiki_dir>/<index_file>`.
  - Conditional audit logging: mutates `<log_file>` only when repairs are made; zero changes on clean runs.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable llm-wiki

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local llm-wiki
```

---

## Configuration Options

Configure options under `plugins.llm-wiki` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  llm-wiki:
    # Directory paths and control files relative to workspace root (defaults shown)
    wiki_dir: ".rnex/wiki"      # Directory for curated flat markdown shards (default: .rnex/wiki)
    index_file: "index.md"      # B-Tree Root Router filename (default: index.md)
    log_file: "log.md"          # Chronological audit log filename (default: log.md)
    log_max_records: 1000       # Maximum records in log.md before oldest are pruned (default: 1000)
    btree_root_max_lines: 80    # Maximum allowed lines in root index.md router (default: 80)
    btree_shard_max_entries: 100# Threshold before splitting a B-Tree shard (default: 100)
    relative_links: "rewrite"   # Link strategy: "rewrite" (default) or "strip"/"delete"
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
| `log_max_records` | integer | `1000` | Maximum records in `log.md` before oldest entries are pruned (FIFO rolling window). |
| `btree_root_max_lines` | integer | `80` | Ceiling on lines allowed in `index.md`. |
| `btree_shard_max_entries` | integer | `100` | Maximum records allowed per leaf shard (default: 100). All wiki files (excluding `index.md` and `log.md`) strictly enforce this limit; shards exceeding this threshold are automatically and recursively subdivided to arbitrary depths (by letters `a-m`/`n-z`, by first 2 letters `pa-pm`/`pn-pz`, by first 3 letters `paa-pam`/`pan-paz`, etc.). |
| `relative_links` | string | `"rewrite"` | Handling strategy for relative links in ingested markdown summaries: `"rewrite"` (resolves relative links against source directory to valid paths from wiki, stripping broken links) or `"strip"` / `"delete"` (removes relative link markup, preserving anchor text). External links are always preserved. |
| `sources` | list | `[docs, "repos/**/README.md"]` | Intake directories and/or glob patterns relative to workspace root. Overridable in `.local.rnex.yaml`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

### Intake Sources (`sources`)

The `sources` setting defines where the LLM Wiki discovers documentation for in-place indexing:

- **Directory Paths (e.g. `docs`, `notes`)**: Repo Nexus recursively scans the directory for all Markdown files. Hidden directories (starting with `.`) and `node_modules` are automatically pruned.
- **Recursive Globs (e.g. `"repos/**/README.md"`)**: Pure POSIX `/bin/sh` pattern resolution matches files at arbitrary directory depths. Always quote globs containing `*` in YAML. Directories named `.git`, `.rnex`, and `node_modules` are pruned during traversal.
- **Active Repository Filtering**: Any resolved path located within `<repos_dir>/<name>/` (default `repos/<name>/`) is checked against member repository status. If a repository is disabled (`enabled: false`) in `rnex.yaml` or `.local.rnex.yaml`, its files are automatically excluded.
- **Two-Level Configuration Precedence**: If `sources` is declared in `.local.rnex.yaml`, it completely overrides the `sources` list defined in `rnex.yaml`.

---

## Plugin CLI Commands

The `llm-wiki` plugin exposes a streamlined, focused 2-command CLI surface:

### `rnex plugin llm-wiki ingest`

Ingests and indexes authoritative workspace documents and member repository documentation directly in place into flat B-Tree shards in `.rnex/wiki/*.md` (or custom `wiki_dir`) and rebalances `index.md`.

Ingestion operates on a **missing-sources-only** basis: it inspects already-indexed workspace paths within the wiki shards and skips them, only compiling newly added or unindexed sources. Existing manual summaries and edits are preserved untouched.

```sh
# Ingest missing workspace sources and enabled member repos
rnex plugin llm-wiki ingest

# Ingest a specific markdown source file directly in place
rnex plugin llm-wiki ingest docs/architecture.md
# Or using the --file flag
rnex plugin llm-wiki ingest --file docs/architecture.md

# Run quietly
rnex plugin llm-wiki ingest --quiet
```

| Argument / Option | Type | Default | Description |
|:---|:---|:---|:---|
| `<file_path>` | string | *(all missing sources)* | Ingest a single specified markdown file directly. |
| `--file, -f <path>` | string | *(all missing sources)* | Ingest a specific markdown file. |
| `--rewrite-links` | boolean | `true` | Rewrite relative links in source summaries to valid paths from wiki. |
| `--strip-links, --delete-links` | boolean | `false` | Strip relative link formatting in source summaries to plain text. |
| `--quiet, -q` | boolean | `false` | Suppress non-essential informational output. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

### Automated Ingestion via Workspace Lifecycle Hooks (Strictly Opt-In)

Repo Nexus enforces a strict **zero-hidden-hooks** architecture: `rnex sync` reconciles workspace state and projects user skills into configured AI assistants, but **never** runs automatic or implicit document ingestion without explicit user declaration.

To execute wiki ingestion automatically at the end of each `rnex sync`, declare the lifecycle hook under `rnex-hooks.after_sync` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
# ==============================================================================
# RNEX Lifecycle Hooks (Strictly Opt-In — Zero Defaults)
# ==============================================================================
rnex-hooks:
  after_sync:
    - "rnex plugin llm-wiki ingest"

# ==============================================================================
# Workspace Plugins
# ==============================================================================
plugins:
  llm-wiki:
    sources:
      - docs
      - "repos/**/README.md"
```

### `rnex plugin llm-wiki lint`

Standalone structural, reference, and sorting audit for the wiki. Inspects directory structures, auto-heals and recursively subdivides oversized shards exceeding `btree_shard_max_entries` (max 100 records per leaf shard; splits infinitely by letters, first 2 letters, first 3 letters, etc. without error), verifies link targets, checks sorting order (`LC_ALL=C`), asserts zero symbolic links, and verifies the $\le 80$ line ceiling on `index.md`:

```sh
# Audit wiki integrity (standalone, zero ingestion)
rnex plugin llm-wiki lint

# Strict mode: fail on any warning
rnex plugin llm-wiki lint --strict

# Run quietly
rnex plugin llm-wiki lint --quiet
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--strict, -s` | boolean | `false` | Fail with exit code 1 if any warnings or structural issues are detected. |
| `--quiet, -q` | boolean | `false` | Suppress non-essential informational output. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

---

## Retrieval Protocol: How AI Agents Query the Wiki

Autonomous AI coding agents navigate the wiki using a deterministic 3-step retrieval protocol without needing vector embeddings or external MCP services:

1. **Step 1 — Root Read**: Read `<wiki_dir>/<index_file>` ($\le$ `btree_root_max_lines` lines) to locate the target shard file (`repo-nexus*.md` or `repos-<member>*.md`).
2. **Step 2 — Leaf Shard Read**: Read the target shard directly in `<wiki_dir>/` to find the exact source file path and summary.
3. **Step 3 — In-Place Access**: Read the authoritative source file directly where it resides in the workspace. Cross-references and backlinks are discovered natively using standard workspace search tools (`grep`, `ripgrep`).

---

## Automated Git Hooks Integration

Integrate wiki integrity checks into your Git workflow using declarative `git.hooks` configuration in `rnex.yaml`:

```yaml
git:
  hooks:
    pre-commit:
      - "rnex plugin llm-wiki lint"
    post-merge:
      - "rnex sync --quiet"
```

---

## Generated Directory Structure

When `llm-wiki` is enabled, it maintains:

```text
my-workspace/
├── <source_dir>/                    # Configured intake source directory (via plugins.llm-wiki.sources)
│   └── architecture.md
├── <repos_dir>/                     # Member repositories (configured via repos_dir, inspected in-place)
│   └── <member-repo>/
│       └── README.md
├── <wiki_dir>/                      # Configured wiki directory (via plugins.llm-wiki.wiki_dir, default: .rnex/wiki)
│   ├── <index_file>                 # B-Tree Root Router (default: index.md)
│   ├── <log_file>                   # Chronological audit history (default: log.md)
│   ├── repo-nexus.md                # Nexus repo shard (or repo-nexus-a-m.md, etc.)
│   └── repos-<member-repo>.md       # Member repo shard (e.g. repos-backend-apps.md)
├── .rnex/
│   └── plugins/
│       └── llm-wiki/
│           ├── ai-instructions.md
│           ├── instructions/
│           │   └── rnex-wiki-architecture.md
│           ├── rules/
│           │   └── behavioral.md
│           ├── skills/
│           │   ├── ingest.md
│           │   └── lint.md
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

The `llm-wiki` plugin encapsulates its agentic skills in `.rnex/plugins/llm-wiki/skills/`:
- `ingest.md`
- `lint.md`

During `rnex sync`, its `after_sync.sh` lifecycle hook automatically registers zero-logic User Skill pointers (`rnex-llm-wiki-ingest` and `rnex-llm-wiki-lint`) across the configured `<skill_dir>` of all enabled AI provider plugins.

When running `rnex plugin disable llm-wiki`, its lifecycle hook automatically unregisters the User Skills from all active provider skill directories, while keeping user data in `plugins.llm-wiki.wiki_dir` and `plugins.llm-wiki.sources` intact.

---

## Disabling the Plugin

```sh
rnex plugin disable llm-wiki
```

When disabled:
- Scoped assets under `.rnex/plugins/llm-wiki/` are cleanly removed.
- **Your data in the configured `plugins.llm-wiki.wiki_dir` and `plugins.llm-wiki.sources` paths is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
