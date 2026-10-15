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
  - Read `.rnex/wiki/hot.md` and `.rnex/wiki/index.md` once per session for orientation.
  - Perform Git commits directly inside individual member repositories.

### 3. Autonomous LLM Wiki Architecture
A self-healing, agent-maintained knowledge graph structured as:

- **`./docs/` Intake Directory**:
  - Append-only directory where unmodified source material (articles, transcripts, docs, API references, meeting notes) is deposited.
  - Raw sources are immutable source-of-truth references for citations.
- **`.rnex/wiki/` Curated Knowledge Base**:
  - Interlinked atomic markdown pages, each representing a single concept, architectural pattern, or domain decision.
  - Each page contains structured YAML frontmatter defining typed relations:
    ```yaml
    ---
    title: Workspace Configuration Protocol
    sources: [docs/rnex-design-spec.md]
    related: [.rnex/wiki/member-repos.md, .rnex/wiki/ai-routing.md]
    extends: [.rnex/wiki/multi-repo-architecture.md]
    contradicts: []
    mentioned_in: []
    ---
    ```
- **`.rnex/wiki/index.md` Navigation Index**:
  - Master categorized catalog organizing all atomic concepts, architecture decisions, and cross-project knowledge.
- **`.rnex/wiki/hot.md` Rolling Context Cache**:
  - High-density ~500-word orientation summary for rapid agent onboarding without full wiki scans. Agents read this once on startup.
- **`.rnex/wiki/_log.md` Audit Trail**:
  - Append-only log recording every ingest and lint operation with timestamped details and source attribution.

### 4. Standardized Agent Workflows
- **`wiki-ingest.md` (8-Step Ingestion Protocol)**:
  - Decomposes raw source documents from `./docs/` into 5–25 atomic wiki pages.
  - Formulates bi-directional frontmatter relations (`sources`, `related`, `extends`, `contradicts`).
  - Appends operations to `.rnex/wiki/_log.md` and rebuilds `.rnex/wiki/index.md`.
- **`wiki-lint.md` (10-Step Integrity Audit Protocol)**:
  - Validates inter-page link paths and file existence.
  - Recomputes reverse backlinks (`mentioned_in`).
  - Identifies and eliminates orphan pages.
  - Merges duplicate or overlapping pages.
  - Audits logical inconsistencies and flags outdated information.
  - Updates `.rnex/wiki/hot.md` and rebuilds `.rnex/wiki/index.md`.

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
    wiki_dir: .rnex/wiki        # Directory for curated atomic markdown pages
    raw_dir: ./docs             # Append-only directory for unmodified intake documents

    # Automated Git hook trigger for wiki verification
    # Options: git-post-merge, git-post-commit, git-pre-commit, git-pre-push, manual
    lint_trigger: manual

    # Notify developer when changes are committed to ./docs/ or .rnex/wiki/
    notify_on_changes: true

    # Enable or disable
    enabled: true
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `wiki_dir` | string | `.rnex/wiki` | Directory containing curated atomic markdown pages. |
| `raw_dir` | string | `./docs` | Append-only directory for unmodified source intake documents. |
| `lint_trigger` | string | `manual` | Git hook event that triggers wiki change detection (`git-post-merge`, `git-post-commit`, `git-pre-commit`, `git-pre-push`, `manual`). |
| `notify_on_changes` | boolean | `true` | Show notification banner when changes are committed to `./docs/` or `.rnex/wiki/`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Automated Git Hooks Integration

When workspace Git hooks are installed (`rnex hooks install`), the `karpathy-llm` plugin links directly into Git events:
- **`post-merge`**: Detects if incoming commits touched `./docs/` or `.rnex/wiki/`, warning the developer to review or re-lint.
- **`post-commit`**: Reminds the developer to run `wiki-lint` or `wiki-ingest` if wiki files were committed.
- **`pre-commit` & `pre-push`**: Emits trigger notices if unvalidated wiki files are staged or about to be pushed.

Inspect active trigger status anytime:
```sh
rnex hooks status
```

---

## Generated Directory Structure

When `karpathy-llm` is enabled, it scaffolds:

```text
my-workspace/
├── docs/
│   └── .gitkeep                     # Deposit unmodified source files here
├── .rnex/
│   ├── wiki/
│   │   ├── index.md                 # Master navigation catalog
│   │   ├── hot.md                   # High-density ~500-word orientation summary
│   │   └── _log.md                  # Append-only audit history
│   └── plugins/
│       └── karpathy-llm/
│           ├── rules/
│           │   └── behavioral.md         # 4 Cardinal principles & context engineering
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

During `rnex sync`, its `after_sync.sh` lifecycle hook automatically registers zero-logic User Skill pointers (`rnex-karpathy-llm-wiki-ingest` and `rnex-karpathy-llm-wiki-lint`) across all enabled AI provider directories (`.cursor/rules/`, `.claude/skills/`, `.gemini/skills/`, `.windsurf/rules/`).

When running `rnex plugin disable karpathy-llm`, its `before_plugin_disable.sh` lifecycle hook automatically unregisters the User Skills from all provider directories, while keeping core workspace skills intact.

---

## Disabling the Plugin

```sh
rnex plugin disable karpathy-llm
```

When disabled:
- Scoped assets under `.rnex/plugins/karpathy-llm/` and member repository mirrors are cleanly removed.
- **Your data in `./docs/` and `.rnex/wiki/` is preserved 100% intact.** Repo Nexus never deletes user-generated knowledge bases upon plugin disablement.
