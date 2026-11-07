---
title: Karpathy LLM & Agent Knowledge Wiki Plugin
description: Implement Andrej Karpathy's 4 cardinal principles for coding agents and autonomous zero-dependency LLM Wiki architecture in Repo Nexus.
---

# Karpathy LLM & Agent Knowledge Wiki Plugin

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants.

It requires **zero external vector databases, embedding pipelines, or heavy MCP infrastructure** — knowledge is indexed as a 2-level B-Tree sharded catalog, maintained as a sorted TSV property graph, and represented as interlinked markdown pages with typed YAML frontmatter that AI agents navigate natively.

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
  - Follow the deterministic 3-step retrieval protocol: B-Tree Root Router (`_index.md`) $\to$ Domain Shard (`_index/<shard>.md`) $\to$ Target Leaf Page.
  - Perform Git commits directly inside individual member repositories.

### 3. Autonomous LLM Wiki Architecture
A self-healing, agent-maintained knowledge graph structured as:

- **`./docs/` Intake Directory**:
  - Append-only directory where unmodified source material (articles, transcripts, docs, API references, meeting notes) is deposited.
  - Raw sources are immutable source-of-truth references for citations.
- **`wiki/` Curated Knowledge Base**:
  - Interlinked atomic markdown pages categorized into domain concepts and repository-scoped docs (default directory: `wiki/` at workspace root):
    - `wiki/concepts/<slug>.md`: Universal architectural patterns, cross-cutting models, invariants, and design decisions.
    - `wiki/repos/<repo_scope>/<slug>.md`: Repository-scoped documentation (`repos/nexus/` for nexus-level workspace docs; `repos/<member-repo>/` for member repositories).
  - Each page contains structured YAML frontmatter defining typed relations:
    ```yaml
    ---
    title: Workspace Configuration Protocol
    sources: [docs/rnex-design-spec.md]
    related: [wiki/repos/nexus/member-repos.md, wiki/concepts/ai-routing.md]
    extends: [wiki/concepts/multi-repo-architecture.md]
    contradicts: []
    mentioned_in: []
    ---
    ```
- **`wiki/_index.md` B-Tree Root Router**:
  - Compact, strictly bounded routing table ($\le 80$ lines, zero YAML frontmatter) organizing domain shards in `wiki/_index/` with key ranges and graph metrics.
- **`wiki/_index/` Sorted B-Tree Leaf Shards**:
  - Lexicographically sorted domain leaf pages (`concepts.md`, `repos-nexus.md`, `repos-<member-repo>.md`). Automatically split into alphabetical sub-shards (e.g. `concepts-a-m.md`, `concepts-n-z.md`, `repos-backend-api-a-m.md`) when exceeding capacity thresholds.
- **`wiki/_graph/` Sorted TSV Property Graph**:
  - Tab-separated tables (`nodes.tsv`, `edges_out.tsv`, `edges_in.tsv`) maintaining adjacency relationships queried via \(O(\log N)\) binary search.
- **`wiki/_log.md` Audit Trail**:
  - Shared append-only log recording ingest, graph update, and lint operations across tracked wiki pages with timestamped details and source attribution. Inspected with `tail -n 20 _log.md`.

### 4. Standardized Agent Workflows
- **`wiki-ingest.md` (8-Step Ingestion Protocol)**:
  - Scaffolds deterministic 1-to-1 wiki pages (`wiki/repos/<scope>/<slug>.md` for repository documents and READMEs; `wiki/concepts/<slug>.md` for design concepts and specifications) and enriches them in-place.
  - Formulates bi-directional frontmatter relations (`sources`, `related`, `extends`, `contradicts`).
  - Idempotently updates `wiki/_log.md`, registers edges in `wiki/_graph/*.tsv`, and rebalances B-Tree shards in `wiki/_index/` and `wiki/_index.md`.
- **`wiki-lint.md` (10-Step Integrity Audit Protocol)**:
  - Non-destructively migrates legacy categories (`overview/`, `entities/`, `sources/`) to `concepts/` and `repos/`.
  - Purges legacy caches (`hot.md`, `index.md`).
  - Validates inter-page link paths and file existence.
  - Detects broken `[[wikilinks]]` across the property graph.
  - Verifies strict `LC_ALL=C` sorting across TSV tables.
  - Enforces the $\le 80$ line budget on root `wiki/_index.md`.
  - Automatically records audit entries in `_log.md`.

### 5. Specialized Agent (`agents/rnex-wiki-curator.agent.md`)
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
    index_dir: "_index"         # Subdirectory for sorted B-Tree leaf shards (default: _index)
    graph_dir: "_graph"         # Subdirectory for sorted TSV property graph tables (default: _graph)
    btree_root_max_lines: 80    # Maximum allowed lines in root wiki/_index.md router (default: 80)
    btree_shard_max_entries: 100# Threshold before splitting a B-Tree shard (default: 100)
    graph_default_depth: 1      # Default ego-subgraph traversal depth in hops (default: 1)
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
| `index_dir` | string | `_index` | Subdirectory containing sorted B-Tree leaf shards. |
| `graph_dir` | string | `_graph` | Subdirectory containing sorted TSV property graph tables. |
| `btree_root_max_lines` | integer | `80` | Ceiling on lines allowed in `wiki/_index.md`. |
| `btree_shard_max_entries` | integer | `100` | Entry count threshold before automatically splitting a shard. |
| `graph_default_depth` | integer | `1` | Default ego-subgraph traversal depth in hops. |
| `sources` | list | `[docs, "repos/**/README.md"]` | Intake directories and/or glob patterns relative to workspace root. Overridable in `.local.rnex.yaml`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

### Intake Sources (`sources`)

The `sources` setting defines where the Karpathy LLM Wiki discovers raw intake documents for `wiki-ingest` and change verification:

- **Directory Paths (e.g. `docs`, `notes`)**: Repo Nexus recursively scans the directory for all files. Hidden directories (starting with `.`) and `node_modules` are automatically pruned.
- **Recursive Globs (e.g. `"repos/**/README.md"`)**: Pure POSIX `/bin/sh` pattern resolution matches files at arbitrary directory depths. Always quote globs containing `*` in YAML. Directories named `.git`, `.rnex`, and `node_modules` are pruned during traversal.
- **Single-Level Globs (e.g. `repos/*/README.md` or `docs/*.md`)**: Matches files at a fixed directory level.
- **Active Repository Filtering**: Any resolved path located within `<repos_dir>/<name>/` (default `repos/<name>/`) is checked against member repository status. If a repository is disabled (`enabled: false`) in `rnex.yaml` or `.local.rnex.yaml`, its files are automatically excluded.
- **Two-Level Configuration Precedence**: If `sources` is declared in `.local.rnex.yaml`, it completely overrides the `sources` list defined in `rnex.yaml`.
- **Legacy Migration**: Existing configurations with `raw_dir: <dir>` are automatically rewritten to a `sources` list during `rnex sync`.
- **Directory Provisioning**: When running `rnex sync`, explicit directory entries (such as `docs`) are created automatically if missing. Glob patterns (containing `*`, `?`, or `[`) and file targets are never converted into directories.

---

## Plugin CLI Commands

The `karpathy-llm` plugin exposes a streamlined, focused 2-command CLI interface. Separate `init` and `index` commands are not needed because directory scaffolding, graph edge updates, and B-Tree rebalancing occur automatically inside `ingest` and `lint`:

### `rnex plugin karpathy-llm ingest`

Ingests raw intake documents and member repository READMEs into atomic, interlinked markdown pages in `wiki/concepts/` and `wiki/repos/<repo_scope>/`, updates graph edges in `wiki/_graph/*.tsv`, and rebalances B-Tree shards in `wiki/_index/` and `wiki/_index.md`.

```sh
rnex plugin karpathy-llm ingest [options] [<file_path>]
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `<file_path>` | string | *(all sources)* | Ingest a single specified markdown file directly. |
| `--file, -f <path>` | string | *(all sources)* | Ingest a specific markdown file. |
| `--source, -s <path>` | string | *(all sources)* | Ingest a specific markdown file or intake directory instead of all configured `sources`. |
| `--repo <name>` | string | *(all enabled repos)* | Ingest a specific member repository README (`wiki/repos/<name>/<name>-readme.md`). |
| `-q, --quiet` | boolean | `false` | Suppress non-error informational progress messages. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

### `rnex plugin karpathy-llm lint`

Audits wiki graph integrity, validates required YAML frontmatter keys, verifies `LC_ALL=C` sorting across TSV tables, detects broken `[[wikilinks]]`, enforces the $\le 80$ line ceiling on `wiki/_index.md`, auto-migrates legacy pages to the `concepts/` and `repos/` taxonomy, and purges deprecated `hot.md` or `index.md` files with audit logging.

```sh
rnex plugin karpathy-llm lint [options]
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `--strict` | boolean | `false` | Treat warnings (broken sources, broken wikilinks, line budget overflow) as errors and exit with a non-zero code. |
| `-q, --quiet` | boolean | `false` | Suppress non-error informational messages. |
| `-h, --help` | boolean | `false` | Display command usage and options. |

---

## Internal Agent Query Operations (`_search` & `_graph`)

While human developers interact exclusively via `ingest` and `lint`, autonomous AI coding agents navigate the wiki during task execution using high-performance internal library helpers (`lib/agent_query_helpers.sh`):

* **Prefix Search (`_search <prefix>`)**:
  Performs $O(\log N)$ binary search prefix lookup against `wiki/_graph/nodes.tsv` using BSD `look` or early-exit POSIX `awk`, returning matching node slugs, shard locations, and summaries in under 1 ms.
* **Ego-Subgraph Traversal (`_graph <node_id> [--depth 1|2]`)**:
  Traverses the sorted TSV adjacency tables to render the ego-subgraph for a queried node, displaying its metadata, 1-hop outbound dependencies, 1-hop inbound backlinks, and optional 2-hop reachability.

These routines are invoked directly by the plugin's agent skills (`wiki-ingest` and `wiki-lint`) without exposing unnecessary CLI commands to user terminals.

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
│   ├── _index.md                    # B-Tree Root Router (<= 80 lines)
│   ├── _log.md                      # Append-only audit history
│   ├── _index/                      # B-Tree Domain Shards (sorted LC_ALL=C)
│   │   ├── concepts.md              # (or concepts-a-m.md, concepts-n-z.md)
│   │   ├── repos-nexus.md           # Workspace-level nexus documentation shard
│   │   └── repos-<member-repo>.md   # Member repository documentation shards
│   ├── _graph/                      # Sorted TSV Property Graph
│   │   ├── nodes.tsv
│   │   ├── edges_out.tsv
│   │   └── edges_in.tsv
│   ├── concepts/                    # Curated architecture & concept pages
│   │   └── <concept-slug>.md
│   └── repos/                       # Repository-scoped documentation pages
│       ├── nexus/                   # Nexus-level documentation
│       │   └── <doc-slug>.md
│       └── <member-repo>/           # Member repository pages (e.g. README, guides)
│           └── <doc-slug>.md
├── .rnex/
│   └── plugins/
│       └── karpathy-llm/
│           ├── instructions/
│           │   ├── rnex-wiki-architecture.md
│           │   └── rnex-scaffolding-meta-prompt.md
│           ├── rules/
│           │   └── behavioral.md
│           ├── skills/
│           │   ├── wiki-ingest.md
│           │   └── wiki-lint.md
│           ├── bin/
│           │   ├── ingest.sh
│           │   └── lint.sh
│           ├── lib/
│           │   ├── config.sh
│           │   ├── utils.sh
│           │   ├── graph_helpers.sh
│           │   ├── btree_helpers.sh
│           │   └── agent_query_helpers.sh
│           └── templates/
│               ├── _index.md
│               ├── _log.md
│               └── rnex-wiki-page.template.md
└── rnex.yaml
```

---

## User Skills & Provider Integration

The `karpathy-llm` plugin encapsulates its agentic skills in `.rnex/plugins/karpathy-llm/skills/`:
- `wiki-ingest.md`
- `wiki-lint.md`

During `rnex sync`, its `after_sync.sh` lifecycle hook automatically registers zero-logic User Skill pointers (`rnex-karpathy-llm-wiki-ingest` and `rnex-karpathy-llm-wiki-lint`) across all enabled AI provider directories (`.cursor/rules/`, `.claude/skills/`, `.agents/skills/`, `.codex/skills/`, `.github/skills/`, `.windsurf/rules/`).

When running `rnex plugin disable karpathy-llm`, its `before_plugin_disable.sh` lifecycle hook automatically unregisters the User Skills from all provider directories, while keeping core workspace skills intact.

---

## Disabling the Plugin

```sh
rnex plugin disable karpathy-llm
```

When disabled:
- Scoped assets under `.rnex/plugins/karpathy-llm/` are cleanly removed.
- **Your data in `./docs/` and `wiki/` is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
