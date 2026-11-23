# LLM Wiki Plugin for Repo Nexus

The **`llm-wiki`** plugin packages the agent behavioral principles, multi-repo context engineering standards, and the autonomous **LLM Wiki** knowledge architecture for AI coding assistants.

No external vector databases, embedding pipelines, or MCP servers required — just a zero-dependency flat B-Tree sharded index directly inside the configured `plugins.llm-wiki.wikiDir` (default: `.rnex/wiki`), organized by a bounded root router (`plugins.llm-wiki.indexFile`, default: `index.md`), and recorded in a chronological audit log (`plugins.llm-wiki.logFile`, default: `log.md`).

---

## What It Provides

### 1. The 4 Cardinal Principles for Coding Agents (`rules/behavioral.md`)
* **Think Before Coding:** Explicit assumptions, problem formulation, and trade-off evaluation before writing code.
* **Simplicity First:** Minimal abstractions, readable implementations, and zero boilerplate bloat.
* **Surgical Changes:** Minimal blast radius, preserved comments/docstrings, and tightly focused diffs.
* **Goal-Driven Execution:** Upfront verification criteria, automated tests, and rigorous diff review.

### 2. Multi-Repo Context Engineering & Autonomy (`rules/behavioral.md`)
* Guidelines tailored for Repo Nexus workspaces respecting member repository autonomy and physical repository boundaries (`reposDir`).
* Deterministic 3-step retrieval protocol: B-Tree Root Router (`<wikiDir>/<indexFile>`) $\to$ Targeted Leaf Shard (`<wikiDir>/<shard>.md`) $\to$ In-Place Source Document.

### 3. Zero-Dependency Flat B-Tree Architecture (`instructions/rnex-wiki-architecture.md`)
* **Intake Sources (`plugins.llm-wiki.sources`, default: `["README.md", "docs", "{reposDir}/**/README.md"]`):** Multi-value array of directory paths, file paths, and glob patterns for unmodified source material (articles, transcripts, docs, meeting notes, repo READMEs).
* **Zero-Duplication In-Place Architecture:** Source files configured in `plugins.llm-wiki.sources` are indexed directly where they reside in the workspace. Zero redundant copies and zero symbolic links.
* **B-Tree Root Router (`<wikiDir>/<indexFile>`):** Compact, strictly bounded routing table (bounded by `plugins.llm-wiki.btreeRootMaxLines`, default: $\le 80$ lines) mapping lexicographic key ranges to leaf shard files in `<wikiDir>/`.
* **Flat Leaf Shards (`<wikiDir>/repo-nexus*.md`, `<wikiDir>/repos-*.md`):** Lexicographically sorted catalogs bounded by `plugins.llm-wiki.btreeShardMaxEntries` (default: 100 entries).
* **Chronological Audit Log (`<wikiDir>/<logFile>`):** Shared append-only log recording granular document lifecycle events (`created`, `updated`, `deleted`) and operational summaries when sources are indexed or repaired. Bounded to a rolling `plugins.llm-wiki.logMaxRecords` window (default: 1000) pruning oldest records first.

### 4. Standardized Agent Skills (`skills/`)
* **`ingest.md` (User Skill: `rnex-llm-wiki-ingest`):** Guides deterministic CLI missing-source ingestion from `plugins.llm-wiki.sources`, flat B-Tree leaf shard updates, root router compilation, and audit log updates.
* **`lint.md` (User Skill: `rnex-llm-wiki-lint`):** Standalone integrity audit protocol to validate existing wiki files in `plugins.llm-wiki.wikiDir`, assert zero symlinks, verify shard links and workspace doc references, and check root router bounds.

---

## Directory Layout Scaffolding

When enabled, the plugin scaffolds:

```text
my-workspace/
├── <sources>/                       # Configured via plugins.llm-wiki.sources
│   └── <source-doc>.md
├── <reposDir>/                      # Configured via reposDir (default: repos/)
│   └── <member-repo>/
│       └── README.md
├── .rnex/
│   ├── wiki/                        # Default plugins.llm-wiki.wikiDir
│   │   ├── index.md                 # B-Tree Root Router (plugins.llm-wiki.indexFile)
│   │   ├── log.md                   # Ingestion & lint audit log (plugins.llm-wiki.logFile)
│   │   ├── repo-nexus.md            # Nexus repo shard
│   │   └── repos-<member-repo>.md   # Member repo shard
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

## Enabling in Repo Nexus

### Via CLI

```bash
rnex plugin enable llm-wiki
```

This command:
1. Adds `llm-wiki` to `plugins:` in `rnex.yaml`.
2. Scopes `rules/`, `instructions/`, `skills/`, `bin/`, `lib/`, and `hooks/` into `.rnex/plugins/llm-wiki/`.
3. Reconciles workspace state, member repositories, and plugin assets via `rnex sync`.

---

## Configuration Reference

Configure `llm-wiki` under `plugins:` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  llm-wiki:
    # Intake sources (files, directories, and/or glob patterns)
    sources:
      - README.md
      - docs
      - "{reposDir}/**/README.md"
    # Optional excluded files, directories, and/or glob patterns (default: [])
    exclude: []

    # Directory paths and control files relative to workspace root (defaults shown)
    wikiDir: ".rnex/wiki"           # Directory for curated flat markdown shards
    indexFile: "index.md"           # B-Tree Root Router filename
    logFile: "log.md"               # Chronological audit log filename
    btreeRootMaxLines: 80           # Maximum allowed lines in root indexFile
    btreeShardMaxEntries: 100       # Threshold before splitting a B-Tree shard
    recordSummaryMaxLength: 100     # Maximum character length of each wiki record summary
    logMaxRecords: 1000             # Maximum rolling records in logFile
    relativeLinks: "rewrite"        # Relative link strategy: "rewrite" or "strip"
```

### CLI Subcommands

The `llm-wiki` plugin exposes a streamlined 2-command CLI:

```sh
# Ingest missing sources from configured plugins.llm-wiki.sources
rnex plugin llm-wiki ingest

# Ingest a specific markdown source file or directory directly in place
rnex plugin llm-wiki ingest <source_path>

# Force re-index existing entries for a modified file, directory, or all configured sources
rnex plugin llm-wiki ingest --force [<source_path>]
rnex plugin llm-wiki ingest -f [<source_path>]

# Validate and auto-heal existing wiki docs, headers, link integrity, and B-Tree shards
rnex plugin llm-wiki lint

# Fast link-and-structure-only validation without reading source document content
rnex plugin llm-wiki lint --shallow
```

### Automated Synchronization Hooks (Strictly Opt-In)

Repo Nexus enforces a strict **zero-hidden-hooks** architecture: `rnex sync` reconciles workspace state and projects user skills into configured AI assistants, but **never** runs automatic or implicit document ingestion without explicit user declaration.

To execute wiki ingestion automatically at the end of each `rnex sync`, declare the lifecycle hook under `rnexHooks:` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
rnexHooks:
  afterSync:
    - "rnex plugin llm-wiki ingest"

plugins:
  llm-wiki:
    sources:
      - docs
      - "repos/**/README.md"
```

### Retrieval Protocol: How AI Agents Query the Wiki

AI coding assistants navigate the wiki using a deterministic 3-step retrieval protocol:
1. **Root Read:** Read `<wikiDir>/<indexFile>` (configured via `plugins.llm-wiki.wikiDir` and `plugins.llm-wiki.indexFile`) to locate the relevant leaf shard.
2. **Shard Read:** Read the target shard in `<wikiDir>/` (`repo-nexus*.md` or `repos-<member>*.md`) to find the exact source file path and summary.
3. **In-Place Read:** Open and read the authoritative source file directly where it resides in the workspace. Discover backlinks and cross-references using standard workspace search tools (`grep`, `ripgrep`).

---

## Disabling

```bash
rnex plugin disable llm-wiki
```

When disabled:
- Scoped assets under `.rnex/plugins/llm-wiki/` and projected user skills are cleanly removed.
- **Your source files configured in `plugins.llm-wiki.sources` and compiled wiki index in `plugins.llm-wiki.wikiDir` are preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
