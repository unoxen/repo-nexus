# Karpathy LLM Plugin for Repo Nexus

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants (Cursor, Claude Code, GitHub Copilot, Antigravity, Windsurf).

No external vector databases, embedding pipelines, or MCP servers required — just interlinked markdown files with structured YAML frontmatter traversed natively by AI agents.

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

### 3. Complete Karpathy LLM Wiki Architecture (`instructions/rnex-wiki-architecture.md`)
* **Intake Sources (`sources`, default: `["docs", "repos/**/README.md"]`):** Multi-value array of directory paths and glob patterns for unmodified source material (articles, transcripts, docs, meeting notes, repo READMEs). Legacy `raw_dir` (default: `./docs`) remains supported as a backward-compatible fallback.
* **Curated Knowledge Base (`wiki_dir`, default: `wiki`):** Interlinked atomic markdown pages, each with typed frontmatter relations (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`).
* **Navigation Index (`<wiki_dir>/index.md`, default: `wiki/index.md`):** Master categorized catalog organizing atomic concepts, architecture decisions, and cross-project knowledge.
* **Rolling Context Cache (`<wiki_dir>/hot.md`, default: `wiki/hot.md`):** High-density ~500-word orientation summary for rapid agent onboarding without full wiki scans (especially for codebase knowledge and second-brain wikis).
* **Audit Trail (`<wiki_dir>/_log.md`, default: `wiki/_log.md`):** Append-only log recording every ingest and lint operation with timestamped details.

### 4. Standardized Agent Skills (`skills/`)
* **`wiki-ingest.md` (User Skill: `rnex-karpathy-llm-wiki-ingest`):** Decomposes raw source documents into 5–25 atomic wiki pages with frontmatter relations.
* **`wiki-lint.md` (User Skill: `rnex-karpathy-llm-wiki-lint`):** Integrity audit protocol to validate paths, recompute `mentioned_in`, eliminate orphans, merge duplicates, audit inconsistencies, identify gaps, suggest source candidates, and rebuild indexes.

---

## Deterministic Lifecycle: Initialization vs. Evolutionary Growth

To ensure workspaces remain 100% predictable, understandable, and consistent across all tools, the Karpathy LLM Wiki follows a strict two-phase lifecycle:

### Phase 1: 100% Deterministic Initialization
Enabling the plugin (`rnex plugin enable karpathy-llm`) performs an exact, zero-interview scaffolding step:
* **Predictable Baseline**: Fixed standard files are created (`docs/.gitkeep`, `wiki/index.md`, `wiki/hot.md`, `wiki/_log.md`).
* **Scoped Assets**: Behavioral rules, wiki architecture guides, skills, commands, and templates are cleanly isolated under `.rnex/plugins/karpathy-llm/`.
* **Zero Guesswork**: No interactive interviews, no AI-generated folder variances, and no "agent decides" ambiguities at init time.
* **Idempotent**: Safe to run repeatedly; existing user files are never overwritten.

### Phase 2: Evolutionary Growth & Domain Specialization (Usage Phase)
Once initialized, the workspace structure organically evolves according to actual domain needs and source materials:
* **Source Ingestion (`rnex-karpathy-llm-wiki-ingest`)**: As raw source documents are deposited into `./docs` and ingested, atomic pages are generated. Users or agents can organize pages into categorical subfolders (e.g. `architecture/`, `decisions/`, `concepts/`, `projects/`) or keep them flat.
* **Customizable Guidelines**: Teams can tailor `rules/behavioral.md` and `instructions/rnex-wiki-architecture.md` for their specific team conventions.
* **Graph Maintenance (`rnex-karpathy-llm-wiki-lint`)**: The periodic lint workflow validates relation paths, updates `mentioned_in`, and rebuilds `index.md` and `hot.md` to match the evolved knowledge graph.

---

## Directory Layout Scaffolding

When enabled, the plugin scaffolds:

```text
my-workspace/
├── docs/
│   └── .gitkeep                     # Intake for unmodified source documents
├── wiki/
│   ├── index.md                     # Master catalog
│   ├── hot.md                       # Rolling ~500-word quick-orient context
│   └── _log.md                      # Ingestion & lint audit history
├── .rnex/
│   └── plugins/
│       └── karpathy-llm/
│           ├── instructions/
│           │   └── rnex-wiki-architecture.md# LLM Wiki architecture & relation schema
│           ├── rules/
│           │   └── behavioral.md         # Cardinal principles & context engineering
│           ├── skills/
│           │   ├── wiki-ingest.md        # 8-step decomposition & ingestion workflow
│           │   └── wiki-lint.md          # 10-step graph validation & maintenance workflow
│           └── templates/
│               ├── rnex-wiki-page.template.md# Atomic page template with typed relations
│               └── rnex-llm-wiki.sample.md# Sample wiki walkthrough
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
2. Copies initial templates (`wiki/index.md`, `wiki/_log.md`, `wiki/hot.md`).
3. Scopes `rules/`, `instructions/`, `skills/`, `commands/`, `hooks/`, `agents/`, and `templates/` into `.rnex/plugins/karpathy-llm/`.
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
```

### 2. Local Machine Configuration (`.local.rnex.yaml`)

Use this file to customize how your local workstation resolves wiki paths or sources:

```yaml
plugins:
  karpathy-llm:
    # Directory for curated atomic markdown pages (default: wiki)
    wiki_dir: wiki
    # Intake directories and/or glob patterns
    sources:
      - docs
      - "repos/**/README.md"
```

### CLI Subcommands

The `karpathy-llm` plugin provides parameterized commands via the `rnex plugin` engine:

```sh
# Ingest all configured sources and enabled member repos
rnex plugin karpathy-llm ingest

# Ingest a specific markdown source or member repository README
rnex plugin karpathy-llm ingest --source docs/architecture.md
rnex plugin karpathy-llm ingest --repo backend-api --quiet

# Lint wiki integrity, relations, and ~500-word hot cache boundary
rnex plugin karpathy-llm lint

# Strict linting (exits non-zero on warnings or errors)
rnex plugin karpathy-llm lint --strict
```

### Summary Reference Table

| Field | Scope / File | Type | Default | Values / Behavior |
|:---|:---|:---|:---|:---|
| `sources` | Repo (`rnex.yaml`) | `list` | `[docs, "repos/**/README.md"]` | Directory paths and/or glob patterns for intake documents. |
| `wiki_dir` | Repo (`rnex.yaml`) | `string` | `wiki` | Directory containing atomic domain pages. |

---

## Everyday Operation & Cadence

1. **Intake:** Drop raw research papers, meeting notes, PRDs, or architecture specs into `./docs/` unmodified.
2. **Ingest:** Instruct your AI assistant: *"Run wiki-ingest on docs/source-document.md"*, or run `rnex plugin karpathy-llm ingest`.
3. **Maintenance:** Run `rnex plugin karpathy-llm lint` (or the `wiki-lint` workflow) to validate relations, prune orphans, and update `mentioned_in` links.

---

## Disabling

```bash
rnex plugin disable karpathy-llm
```

Safely unlinks plugin assets from member repositories and removes the entry from `rnex.yaml`. Your curated `wiki/` and `./docs/` data remain completely untouched on disk.
