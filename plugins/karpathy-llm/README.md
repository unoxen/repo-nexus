# Karpathy LLM Plugin for Repo Nexus

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants (Cursor, Claude Code, GitHub Copilot, Antigravity, Windsurf).

No external vector databases, embedding pipelines, or MCP servers required — just a zero-dependency flat B-Tree sharded index directly in `.rnex/wiki/*.md`, organized by a bounded root router (`.rnex/wiki/index.md`), and recorded in a chronological audit log (`.rnex/wiki/log.md`).

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
* Deterministic 3-step retrieval protocol: B-Tree Root Router (`.rnex/wiki/index.md`) $\to$ Targeted Leaf Shard (`.rnex/wiki/<shard>.md`) $\to$ In-Place Source Document.

### 3. Zero-Dependency Flat B-Tree Architecture (`instructions/rnex-wiki-architecture.md`)
* **Intake Sources (`sources`, default: `["docs", "repos/**/README.md"]`):** Multi-value array of directory paths and glob patterns for unmodified source material (articles, transcripts, docs, meeting notes, repo READMEs).
* **Zero-Duplication In-Place Architecture:** Source files are indexed directly where they reside in the workspace (`README.md`, `docs/`, `RFC/`, `repos/<member>/...`). Zero redundant copies and zero symbolic links.
* **B-Tree Root Router (`<wiki_dir>/index.md`):** Compact, strictly bounded routing table ($\le 80$ lines, zero YAML frontmatter) mapping lexicographic key ranges to leaf shard files in `<wiki_dir>/`. Default: `.rnex/wiki/index.md`.
* **Flat Leaf Shards (`<wiki_dir>/repo-nexus*.md`, `<wiki_dir>/repos-*.md`):** Lexicographically sorted catalogs.
* **Chronological Audit Log (`<wiki_dir>/log.md`):** Shared append-only log recording granular document lifecycle events (`created`, `updated`, `deleted`) and operational summaries when sources are indexed or repaired. Bounded to a rolling 1000-record window pruning oldest records first. Inspected via `tail -n 20 .rnex/wiki/log.md`.

### 4. Standardized Agent Skills (`skills/`)
* **`wiki-ingest.md` (User Skill: `rnex-karpathy-llm-wiki-ingest`):** Guides deterministic CLI missing-source ingestion, flat B-Tree leaf shard updates, root router compilation, and audit log updates.
* **`wiki-lint.md` (User Skill: `rnex-karpathy-llm-wiki-lint`):** Standalone integrity audit protocol to validate existing wiki files, assert zero symlinks, verify shard links and workspace doc references, and check root router bounds ($\le 80$ lines).

---

## Directory Layout Scaffolding

When enabled, the plugin scaffolds:

```text
my-workspace/
├── docs/                            # Workspace documentation
│   └── architecture.md
├── repos/                           # Member repositories (inspected in-place)
│   └── <member-repo>/
│       └── README.md
├── .rnex/
│   ├── wiki/                        # Default curated flat markdown wiki
│   │   ├── index.md                 # B-Tree Root Router (<= 80 lines)
│   │   ├── log.md                   # Ingestion & lint audit history
│   │   ├── repo-nexus.md            # Nexus repo shard
│   │   └── repos-<member-repo>.md   # Member repo shard
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
│           └── lib/
│               ├── config.sh
│               ├── utils.sh
│               ├── source_helpers.sh
│               ├── btree_helpers.sh
│               └── lint_helpers.sh
└── rnex.yaml
```

---

## Enabling in Repo Nexus

### Via CLI

```bash
rnex plugin enable karpathy-llm
```

This command:
1. Adds `karpathy-llm` to `plugins:` in `rnex.yaml`.
2. Scopes `rules/`, `instructions/`, `skills/`, `bin/`, `lib/`, and `hooks/` into `.rnex/plugins/karpathy-llm/`.
3. Reconciles workspace state, member repositories, and plugin assets via `rnex sync`.

---

## Configuration Reference

Configure `karpathy-llm` under `plugins:` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  karpathy-llm:
    # Intake sources (directories and/or glob patterns)
    sources:
      - docs
      - "repos/**/README.md"

    # Directory paths and control files relative to workspace root (defaults shown)
    wiki_dir: ".rnex/wiki"      # Directory for curated flat markdown shards
    index_file: "index.md"      # B-Tree Root Router filename
    log_file: "log.md"          # Chronological audit log filename
    btree_root_max_lines: 80    # Maximum allowed lines in root index.md router
    btree_shard_max_entries: 100# Threshold before splitting a B-Tree shard
```

### CLI Subcommands

The `karpathy-llm` plugin exposes a streamlined 2-command CLI:

```sh
# Ingest missing sources from configured intake sources
rnex plugin karpathy-llm ingest

# Ingest a specific markdown source file directly in place
rnex plugin karpathy-llm ingest docs/architecture.md
rnex plugin karpathy-llm ingest --file docs/architecture.md

# Lint existing wiki structure, link integrity, and zero-symlink invariants
rnex plugin karpathy-llm lint
```

### Automated Synchronization Hooks (Strictly Opt-In)

Repo Nexus enforces a strict **zero-hidden-hooks** architecture: `rnex sync` reconciles workspace state and projects user skills into configured AI assistants, but **never** runs automatic or implicit document ingestion without explicit user declaration.

To execute wiki ingestion automatically at the end of each `rnex sync`, declare the lifecycle hook in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
# ==============================================================================
# RNEX Lifecycle Hooks (Strictly Opt-In — Zero Defaults)
# ==============================================================================
rnex-hooks:
  after_sync:
    - "rnex plugin karpathy-llm ingest"

# ==============================================================================
# Workspace Plugins
# ==============================================================================
plugins:
  karpathy-llm:
    sources:
      - docs
      - "repos/**/README.md"
```

### Retrieval Protocol: How AI Agents Query the Wiki

AI coding assistants navigate the wiki using a deterministic 3-step retrieval protocol:
1. **Root Read:** Read `.rnex/wiki/index.md` ($\le 80$ lines) to locate the relevant leaf shard.
2. **Shard Read:** Read the target shard in `.rnex/wiki/` (`repo-nexus*.md` or `repos-<member>*.md`) to find the exact source file path and summary.
3. **In-Place Read:** Open and read the authoritative source file directly where it resides in the workspace. Discover backlinks and cross-references using standard workspace search tools (`grep`, `ripgrep`).

---

## Disabling

```bash
rnex plugin disable karpathy-llm
```

When disabled:
- Scoped assets under `.rnex/plugins/karpathy-llm/` are cleanly removed.
- **Your data in `./docs/` and `.rnex/wiki/` is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
