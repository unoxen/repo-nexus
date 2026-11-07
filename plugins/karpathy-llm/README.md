# Karpathy LLM Plugin for Repo Nexus

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants (Cursor, Claude Code, GitHub Copilot, Antigravity, Windsurf).

No external vector databases, embedding pipelines, or MCP servers required — just a 2-level B-Tree sharded index, sorted TSV property graph, and interlinked markdown files traversed natively by AI agents.

Reference specification: [setup-karpathy-wiki.md](https://github.com/unoxen/ai-toolkit/blob/main/prompts/setup-karpathy-wiki.md) (also available locally in [`instructions/rnex-scaffolding-meta-prompt.md`](instructions/rnex-scaffolding-meta-prompt.md)).

---

## What It Provides

### 1. The 4 Cardinal Principles for Coding Agents (`rules/behavioral.md`)
* **Think Before Coding:** Explicit assumptions, problem formulation, and trade-off evaluation before writing code.
* **Simplicity First:** Minimal abstractions, readable implementations, and zero boilerplate bloat.
* **Surgical Changes:** Minimal blast radius, preserved comments/docstrings, and tightly focused diffs.
* **Goal-Driven Execution:** Upfront verification criteria, automated tests, and rigorous diff review.

### 2. Multi-Repo Context Engineering & Autonomy (`rules/behavioral.md`)
* Guidelines tailored for Repo Nexus workspaces respecting member repository autonomy and physical repository boundaries.
* Deterministic 3-step retrieval protocol: B-Tree Root Router (`_index.md`) $\to$ Targeted Leaf Shard (`_index/<shard>.md`) $\to$ Target Leaf Markdown Page.

### 3. Zero-Dependency B-Tree & TSV Graph Architecture (`instructions/rnex-wiki-architecture.md`)
* **Intake Sources (`sources`, default: `["docs", "repos/**/README.md"]`):** Multi-value array of directory paths and glob patterns for unmodified source material (articles, transcripts, docs, meeting notes, repo READMEs).
* **Zero-Duplication In-Place Architecture:** Source files are indexed directly where they reside in the workspace (`README.md`, `docs/`, `RFC/`, `repos/<member>/...`). Zero redundant copies and zero symbolic links (`wiki/concepts/` and `wiki/repos/` are completely eradicated).
* **B-Tree Root Router (`<wiki_dir>/_index.md`):** Compact, strictly bounded routing table ($\le 80$ lines, zero YAML frontmatter) mapping lexicographic key ranges to leaf shard files in `_index/`.
* **B-Tree Leaf Shards (`<wiki_dir>/_index/*.md`):** Lexicographically sorted catalogs (`repo-nexus.md`, `repo-nexus-<subscope>.md`, `repos-<member-repo>.md`). Automatically split into alphabetical sub-shards (`<shard>-a-m.md`, `<shard>-n-z.md`) when exceeding capacity thresholds.
* **Sorted TSV Property Graph (`<wiki_dir>/_graph/*.tsv`):** Plain-text adjacency lists (`nodes.tsv`, `edges_out.tsv`, `edges_in.tsv`) maintaining graph topology and supporting $O(\log N)$ binary search traversal via BSD `look` or early-exit POSIX `awk`.
* **Audit Trail (`<wiki_dir>/_log.md`):** Shared append-only log recording ingest and lint operations across tracked wiki pages. Inspected via `tail -n 20 _log.md`.

### 4. Standardized Agent Skills (`skills/`)
* **`wiki-ingest.md` (User Skill: `rnex-karpathy-llm-wiki-ingest`):** Guides deterministic CLI in-place scanning, graph registration in `_graph/*.tsv`, B-Tree shard rebalancing, and direct AI enrichment of source documents.
* **`wiki-lint.md` (User Skill: `rnex-karpathy-llm-wiki-lint`):** Integrity audit protocol to validate paths, auto-heal legacy structures, assert zero symlinks, recompute graph edges, detect broken `[[wikilinks]]`, verify root line budget ($\le 80$ lines), purge legacy caches (`hot.md`, `index.md`, `concepts/`, `repos/`), and verify `LC_ALL=C` sort order.

---

## Deterministic Lifecycle: Initialization vs. Evolutionary Growth

To ensure workspaces remain 100% predictable, understandable, and consistent across all tools, the Karpathy LLM Wiki follows a strict two-phase lifecycle:

### Phase 1: 100% Deterministic Initialization
Enabling the plugin (`rnex plugin enable karpathy-llm`) performs an exact, zero-interview scaffolding step:
* **Predictable Baseline**: Standard baseline files are created (`docs/.gitkeep`, `wiki/_index.md`, `wiki/_log.md`, `wiki/_index/*.md`, `wiki/_graph/*.tsv`).
* **Scoped Assets**: Behavioral rules, wiki architecture guides, skills, commands, and templates are cleanly isolated under `.rnex/plugins/karpathy-llm/`.
* **Zero Guesswork**: No interactive interviews, no AI-generated folder variances, and no "agent decides" ambiguities at init time.
* **Idempotent**: Safe to run repeatedly; existing curated wiki pages are never overwritten.

### Phase 2: Evolutionary Growth & Domain Specialization (Usage Phase)
Once initialized, the workspace structure organically evolves according to actual domain needs and source materials:
* **Source Ingestion (`rnex-karpathy-llm-wiki-ingest`)**: As raw source documents are deposited and ingested, authoritative documents are indexed directly in place, graph edges are registered in `_graph/*.tsv`, and B-Tree shards in `_index/*.md` and `_index.md` are automatically rebalanced.
* **Customizable Guidelines**: Teams can tailor `rules/behavioral.md` and `instructions/rnex-wiki-architecture.md` for their specific conventions.
* **Graph Maintenance (`rnex-karpathy-llm-wiki-lint`)**: The periodic lint workflow validates relation paths, verifies sort invariants, and flags broken wikilinks.

---

## Directory Layout Scaffolding

When enabled, the plugin scaffolds:

```text
my-workspace/
├── docs/                            # Workspace documentation
│   └── .gitkeep
├── repos/                           # Member repositories (inspected in-place)
│   └── <member-repo>/
│       └── README.md
├── wiki/
│   ├── _index.md                    # B-Tree Root Router (<= 80 lines)
│   ├── _log.md                      # Ingestion & lint audit history
│   ├── _index/                      # B-Tree Domain Shards (sorted LC_ALL=C)
│   │   ├── repo-nexus.md            # (or repo-nexus-<subscope>.md, e.g. -a-m.md)
│   │   └── repos-<member-repo>.md   # Member repository documentation shards
│   └── _graph/                      # Sorted TSV Property Graph
│       ├── nodes.tsv
│       ├── edges_out.tsv
│       └── edges_in.tsv
├── .rnex/
│   └── plugins/
│       └── karpathy-llm/
│           ├── instructions/
│           │   ├── rnex-wiki-architecture.md# LLM Wiki architecture & relation schema
│           │   └── rnex-scaffolding-meta-prompt.md# Scaffolding instructions
│           ├── rules/
│           │   └── behavioral.md         # Cardinal principles & context engineering
│           ├── skills/
│           │   ├── wiki-ingest.md        # Deterministic in-place ingestion workflow
│           │   └── wiki-lint.md          # Graph validation & B-tree rebalance workflow
│           ├── bin/
│           │   ├── ingest.sh             # User-facing ingest command
│           │   └── lint.sh               # User-facing lint & migration command
│           ├── lib/
│           │   ├── config.sh             # Plugin configuration loader
│           │   ├── utils.sh              # Pure slug and wikilink utilities
│           │   ├── source_helpers.sh     # In-place YAML source discovery & expansion
│           │   ├── graph_helpers.sh      # Two-pass TSV property graph compiler
│           │   ├── btree_helpers.sh      # B-Tree shard compiler & rebalancer
│           │   └── agent_query_helpers.sh# Internal O(log N) search and ego graph query
│           └── templates/
│               ├── _index.md             # Baseline root router template
│               └── _log.md               # Baseline audit log template
└── rnex.yaml                        # Plugin configuration
```

---

## Enabling in Repo Nexus

### Option 1: Via CLI (Recommended)

```bash
rnex plugin enable karpathy-llm
```

This command:
1. Adds `karpathy-llm` to `plugins:` in `rnex.yaml`.
2. Copies initial templates (`wiki/_index.md`, `wiki/_log.md`, `wiki/_index/*.md`, `wiki/_graph/*.tsv`).
3. Scopes `rules/`, `instructions/`, `skills/`, `bin/`, `lib/`, `hooks/`, `agents/`, and `templates/` into `.rnex/plugins/karpathy-llm/`.
4. Reconciles workspace state, member repositories, and plugin assets via `rnex sync`.

### Option 2: Declarative in `rnex.yaml`

Configure `karpathy-llm` under `plugins:` in `rnex.yaml`:

```yaml
plugins:
  karpathy-llm: {}
```

Then reconcile workspace:

```bash
rnex sync
```

---

## Configuration Reference

The plugin supports two levels of configuration:
1. **Repo Config (`rnex.yaml`)**: Shared across your team and version-controlled. Configures repository-level structure, file paths, and indexing rules.
2. **Local Config (`.local.rnex.yaml`)**: Machine-specific and gitignored.

### 1. Shared Repo Configuration (`rnex.yaml`)

```yaml
plugins:
  karpathy-llm:
    # Intake sources (directories and/or glob patterns)
    sources:
      - docs
      - "repos/**/README.md"

    # Directory paths relative to workspace root (defaults shown)
    wiki_dir: wiki              # Directory for curated atomic markdown pages
    index_dir: "_index"         # Subdirectory for sorted B-Tree leaf shards
    graph_dir: "_graph"         # Subdirectory for sorted TSV property graph tables
    btree_root_max_lines: 80    # Maximum allowed lines in root wiki/_index.md router
    btree_shard_max_entries: 100# Threshold before splitting a B-Tree shard
    graph_default_depth: 1      # Default ego-subgraph traversal depth in hops
```

### 2. Local Machine Configuration (`.local.rnex.yaml`)

Use this file to customize how your local workstation resolves wiki paths or sources:

```yaml
plugins:
  karpathy-llm:
    wiki_dir: wiki
    sources:
      - docs
      - "repos/**/README.md"
```

### CLI Subcommands

The `karpathy-llm` plugin exposes a streamlined 2-command CLI:

```sh
# Ingest all configured sources and enabled member repos
rnex plugin karpathy-llm ingest

# Ingest a specific markdown source or member repository README
rnex plugin karpathy-llm ingest docs/architecture.md
rnex plugin karpathy-llm ingest --file docs/architecture.md
rnex plugin karpathy-llm ingest --source docs/architecture.md
rnex plugin karpathy-llm ingest --repo backend-api --quiet

# Lint wiki schema, sort invariants, and wikilink integrity
rnex plugin karpathy-llm lint

# Strict linting (exits non-zero on warnings or errors)
rnex plugin karpathy-llm lint --strict
```

### Internal Agent Query Operations (`_search` & `_graph`)

AI coding agents navigate the wiki during task execution using high-performance internal library helpers (`lib/agent_query_helpers.sh`):

* **Prefix Search (`_search <prefix>`)**: $O(\log N)$ binary search prefix lookup against `wiki/_graph/nodes.tsv` using BSD `look` or POSIX `awk` early-exit (< 1 ms latency).
* **Ego-Subgraph Traversal (`_graph <node_id> [--depth 1|2]`)**: Traverses the sorted TSV adjacency tables to render 1-hop dependencies, backlinks, and optional 2-hop reachability.

### Summary Reference Table

| Field | Scope / File | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `sources` | Repo (`rnex.yaml`) | `list` | `[docs, "repos/**/README.md"]` | Directory paths and/or glob patterns for intake documents. |
| `wiki_dir` | Repo (`rnex.yaml`) | `string` | `wiki` | Directory containing atomic domain pages. |
| `index_dir` | Repo (`rnex.yaml`) | `string` | `_index` | Subdirectory for sorted B-Tree leaf shards. |
| `graph_dir` | Repo (`rnex.yaml`) | `string` | `_graph` | Subdirectory for sorted TSV property graph tables. |
| `btree_root_max_lines` | Repo (`rnex.yaml`) | `integer` | `80` | Ceiling on lines allowed in `wiki/_index.md`. |
| `btree_shard_max_entries` | Repo (`rnex.yaml`) | `integer` | `100` | Entry count threshold before automatically splitting a shard. |
| `graph_default_depth` | Repo (`rnex.yaml`) | `integer` | `1` | Default ego-subgraph traversal depth in hops. |

---

## Everyday Operation & Cadence

1. **Intake:** Drop raw research papers, meeting notes, PRDs, or architecture specs into `./docs/` unmodified.
2. **Ingest:** Instruct your AI assistant: *"Run wiki-ingest on docs/source-document.md"*, or run `rnex plugin karpathy-llm ingest` (automatically rebuilds graph TSVs and B-Tree shards).
3. **Maintenance:** Run `rnex plugin karpathy-llm lint` (or the `wiki-lint` workflow) to validate relations, purge legacy caches, and update graph edges.
4. **Agent Navigation:** AI assistants navigate the knowledge base via `wiki/_index.md` $\to$ domain shards $\to$ target pages, querying relationships via internal agent search & graph operations.

---

## Disabling

```bash
rnex plugin disable karpathy-llm
```

When disabled:
- Scoped assets under `.rnex/plugins/karpathy-llm/` are cleanly removed.
- **Your data in `./docs/` and `wiki/` is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
