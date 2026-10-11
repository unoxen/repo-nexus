# Karpathy LLM Plugin for Repo Nexus

The **`karpathy-llm`** plugin packages Andrej Karpathy's agent behavioral principles, multi-repo context engineering standards, and the autonomous **Karpathy LLM Wiki** knowledge architecture for AI coding assistants (Cursor, Claude Code, GitHub Copilot, Antigravity, Windsurf).

No external vector databases, embedding pipelines, or MCP servers required — just interlinked markdown files with structured YAML frontmatter traversed natively by AI agents.

Reference specification: [setup-karpathy-wiki.md](https://github.com/nu-nenoi/ai-toolkit/blob/main/prompts/setup-karpathy-wiki.md) (also available locally in [`instructions/scaffolding-meta-prompt.md`](instructions/scaffolding-meta-prompt.md)).

---

## What It Provides

### 1. The 4 Cardinal Principles for Coding Agents (`rules/behavioral.md`)
* **Think Before Coding:** Explicit assumptions, problem formulation, and trade-off evaluation before writing code.
* **Simplicity First:** Minimal abstractions, readable implementations, and zero boilerplate bloat.
* **Surgical Changes:** Minimal blast radius, preserved comments/docstrings, and tightly focused diffs.
* **Goal-Driven Execution:** Upfront verification criteria, automated tests, and rigorous diff review.

### 2. Multi-Repo Context Engineering & Autonomy (`rules/behavioral.md`)
* Guidelines tailored for Repo Nexus workspaces respecting member repository autonomy and physical repository boundaries.

### 3. Complete Karpathy LLM Wiki Architecture (`instructions/wiki-architecture.md`)
* **`/raw/` Intake Directory:** Append-only directory where unmodified source material (articles, transcripts, docs, meeting notes) is deposited. Includes `.gitkeep`.
* **`/wiki/` Curated Knowledge Base:** Interlinked atomic markdown pages, each with typed frontmatter relations (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`).
* **`/wiki/index.md` Navigation Index:** Master categorized catalog organizing atomic concepts, architecture decisions, and cross-project knowledge.
* **`/wiki/hot.md` Rolling Context Cache:** High-density ~500-word orientation summary for rapid agent onboarding without full wiki scans (especially for codebase knowledge and second-brain wikis).
* **`/wiki/_log.md` Audit Trail:** Append-only log recording every ingest and lint operation with timestamped details.

### 4. Standardized Agent Workflows (`workflows/`)
* **`wiki-ingest.md` (8 Steps):** Decomposes raw source documents into 5–25 atomic wiki pages with frontmatter relations.
* **`wiki-lint.md` (10 Steps):** Integrity audit protocol to validate paths, recompute `mentioned_in`, eliminate orphans, merge duplicates, audit inconsistencies, identify gaps, suggest source candidates, and rebuild indexes.

---

## Deterministic Lifecycle: Initialization vs. Evolutionary Growth

To ensure workspaces remain 100% predictable, understandable, and consistent across all tools, the Karpathy LLM Wiki follows a strict two-phase lifecycle:

### Phase 1: 100% Deterministic Initialization
Enabling the plugin (`rnex plugin enable karpathy-llm`) performs an exact, zero-interview scaffolding step:
* **Predictable Baseline**: Fixed standard files are created (`raw/.gitkeep`, `wiki/index.md`, `wiki/hot.md`, `wiki/_log.md`).
* **Scoped Assets**: Behavioral rules, wiki architecture guides, workflows, and templates are cleanly isolated under `.rnex/plugins/karpathy-llm/`.
* **Zero Guesswork**: No interactive interviews, no AI-generated folder variances, and no "agent decides" ambiguities at init time.
* **Idempotent**: Safe to run repeatedly; existing user files are never overwritten.

### Phase 2: Evolutionary Growth & Domain Specialization (Usage Phase)
Once initialized, the workspace structure organically evolves according to actual domain needs and source materials:
* **Source Ingestion (`wiki-ingest`)**: As raw source documents are deposited into `/raw/` and ingested, atomic pages are generated. Users or agents can organize pages into categorical subfolders (e.g. `architecture/`, `decisions/`, `concepts/`, `projects/`) or keep them flat.
* **Customizable Guidelines**: Teams can tailor `rules/behavioral.md` and `instructions/wiki-architecture.md` for their specific team conventions.
* **Graph Maintenance (`wiki-lint`)**: The periodic lint workflow validates relation paths, updates `mentioned_in`, and rebuilds `index.md` and `hot.md` to match the evolved knowledge graph.

---

## Directory Layout Scaffolding

When enabled, the plugin scaffolds:

```text
my-workspace/
├── raw/
│   └── .gitkeep                     # Intake for unmodified source documents
├── wiki/
│   ├── index.md                     # Master catalog
│   ├── hot.md                       # Rolling ~500-word quick-orient context
│   └── _log.md                      # Ingestion & lint audit history
├── .rnex/
│   └── plugins/
│       └── karpathy-llm/
│           ├── instructions/
│           │   └── wiki-architecture.md# LLM Wiki architecture & relation schema
│           ├── rules/
│           │   └── behavioral.md    # Cardinal principles & context engineering
│           ├── workflows/
│           │   ├── wiki-ingest.md   # 8-step decomposition & ingestion workflow
│           │   └── wiki-lint.md     # 10-step graph validation & maintenance workflow
│           └── templates/
│               ├── wiki-page.template.md# Atomic page template with typed relations
│               └── LLM_WIKI.sample.md# Sample wiki walkthrough
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
2. Copies initial templates (`wiki/index.md`, `wiki/_log.md`, `wiki/hot.md`, `raw/.gitkeep`, `.rnex/templates/wiki-page.template.md`, `.rnex/templates/LLM_WIKI.sample.md`).
3. Scopes `rules/`, `instructions/`, and `workflows/` into `.rnex/plugins/karpathy-llm/`.
4. Syncs scope links and AI context files across all registered member repositories via `rnex fix`.

### Option 2: Declarative in `rnex.yaml`

Configure `karpathy-llm` under `plugins:` in `rnex.yaml`:

```yaml
plugins:
  karpathy-llm: {}
```

Then reconcile and fix:

```bash
rnex fix
```

---

## Configuration Reference

The plugin supports two levels of configuration:
1. **Repo Config (`rnex.yaml`)**: Shared across your team and version-controlled. Configures repository-level structure, file paths, and indexing rules.
2. **Local Config (`.local.rnex.yaml`)**: Machine-specific and gitignored. Configures git hook triggers, deterministic checks, and your preferred local AI runner command.

### 1. Shared Repo Configuration (`rnex.yaml`)

```yaml
plugins:
  karpathy-llm:
    # Directory paths relative to workspace root (defaults shown)
    wiki_dir: wiki              # Directory for curated atomic markdown pages
    raw_dir: raw                # Append-only directory for unmodified intake documents

    # Master catalog auto-indexing (default: true)
    # Automatically rebuilds categorized links in wiki/index.md when pages change
    auto_index: true
```

### 2. Local Machine Configuration (`.local.rnex.yaml`)

Use this file to customize how your local workstation executes wiki maintenance (e.g., via git hooks, deterministic scripts, or provider-agnostic AI CLI runners):

```yaml
plugins:
  karpathy-llm:
    # Optional automated git hook trigger (default: unset / manual only):
    #   "git-post-commit"  - Runs immediately after a successful commit (Recommended: non-blocking)
    #   "git-pre-push"     - Runs before pushing changes to remote
    #   "git-post-merge"   - Runs after pulling upstream updates from teammates
    # Omit or leave unset for purely manual maintenance (default).
    lint_trigger: git-post-commit

    # Stage 1: Deterministic graph maintenance (default: true)
    # Executes zero-token AST/regex checks to validate broken links, recompute mentioned_in,
    # and find orphaned pages without calling an LLM (<50ms, free, offline).
    run_deterministic_checks: true

    # Stage 2: Provider-agnostic AI command runner (default: "")
    # Executed ONLY when semantic synthesis is required (e.g. decomposing /raw/ docs via wiki-ingest).
    # The trigger pipes the workflow markdown instructions to this command via standard input (stdin).
    ai_cmd: "llm -m openrouter/auto"

    # Examples for popular CLI tools:
    # ai_cmd: "gemini run"                         # Google Gemini / Antigravity CLI
    # ai_cmd: "claude -p"                          # Claude Code CLI
    # ai_cmd: "ollama run llama3"                  # Local offline model
    # ai_cmd: "aider --message"                    # Aider CLI
    # ai_cmd: ""                                   # Empty: Prompt-only mode (prints terminal notification)

    # Terminal notifications on commit (default: true)
    # Displays non-blocking alerts in your terminal right after git commit completes.
    notify_on_changes: true
```

### Detailed Option Descriptions

#### `auto_index` (Repo Config)
* **What it does:** Automatically keeps `/wiki/index.md` (the master catalog) synchronized with all atomic pages in `/wiki/`.
* **How it works:** During `wiki-ingest` and `wiki-lint`, the tool inspects each page's frontmatter (`title`, `tags`, directory category) and updates the categorized link sections in `index.md`.
* **Why you need it:** AI coding assistants read `wiki/index.md` first as a high-level "navigation map" to locate relevant concepts without scanning hundreds of individual markdown files (saving massive amounts of context tokens). If disabled (`false`), you must manually maintain links in `index.md`.

#### `lint_trigger` (Local Config)
* **What it does:** Optional git hook trigger to automate wiki graph audits and maintenance workflows (`wiki-lint` and `wiki-ingest`).
* **Default:** Unset / omitted. Automated triggers are **disabled by default**; wiki maintenance is purely manual unless you explicitly opt into a Git hook here.
* **Supported opt-in values:**
  * `git-post-commit` *(Recommended)*: Fires immediately after a `git commit` succeeds. It is completely non-blocking and checks `git diff-tree` to see if files in `/raw/` or `/wiki/` were added or modified.
  * `git-pre-push`: Fires before pushing changes upstream, catching dead links or unparsed notes before publishing to the team.
  * `git-post-merge`: Fires after `git pull` when teammates have added new wiki notes or intake documents.
* **Why you need it:** Lets you optionally bind wiki maintenance to a specific Git lifecycle event without nagging prompts or timer counters. If you prefer running workflows manually on demand, leave this field omitted.

#### `notify_on_changes` (Local Config)
* **What it does:** Controls whether helpful status messages and action reminders are printed to your terminal stdout.
* **When is it triggered?** Triggered **immediately after a git operation completes** (e.g., right after `git commit` finishes writing the commit object, or during `git push`).
  * If new documents were committed into `/raw/`: prints an alert (e.g. `[WIKI] 2 new intake documents in /raw/. Run wiki-ingest with your AI assistant.`).
  * If broken links or orphans were detected: prints a summary notice highlighting the pages that need attention.
* **Why you need it:** Provides immediate visibility into pending wiki operations without blocking or slowing down your Git workflow. Set to `false` for silent background execution.

#### `run_deterministic_checks` (Local Config)
* **What it does:** Enables fast, offline graph analysis before invoking any LLM.
* **How it works:** Runs a local script that parses Markdown link targets and frontmatter relations (`sources`, `related`, `extends`, `contradicts`). It validates that target files exist, recomputes reciprocal `mentioned_in: []` backlinks, and identifies orphan pages.
* **Why you need it:** Resolves 90% of routine wiki maintenance in <50ms without spending API tokens, hitting rate limits, or risking LLM path hallucinations.

#### `ai_cmd` (Local Config)
* **What it does:** A provider-agnostic shell command template used to execute semantic LLM tasks (such as decomposing an intake document via `wiki-ingest` or resolving factual contradictions).
* **How it works:** When semantic work is needed, the trigger pipes the task prompt and workflow file into this shell command via standard input (`stdin`).
* **Why you need it:** Decouples your wiki workflow from any single vendor. Works with Simon Willison's `llm`, Google Gemini / Antigravity CLI, Anthropic Claude Code, Ollama, Aider, or custom shell scripts. If left blank (`""`), the system operates in prompt-only mode, reminding you to run the workflow in your interactive chat assistant.

### Summary Reference Table

| Field | Scope / File | Type | Default | Values / Behavior |
|:---|:---|:---|:---|:---|
| `auto_index` | Repo (`rnex.yaml`) | `boolean` | `true` | Auto-rebuilds categorized links in `wiki/index.md`. Set to `false` for manual curation. |
| `wiki_dir` | Repo (`rnex.yaml`) | `string` | `wiki` | Directory containing atomic domain pages. |
| `raw_dir` | Repo (`rnex.yaml`) | `string` | `raw` | Append-only directory for unmodified source materials. |
| `lint_trigger` | Local (`.local.rnex.yaml`) | `string` | *(unset)* | Optional opt-in Git hook: `git-post-commit`, `git-pre-push`, `git-post-merge`. Unset = purely manual. |
| `run_deterministic_checks` | Local (`.local.rnex.yaml`) | `boolean` | `true` | Offline zero-token validation of broken links, `mentioned_in`, and orphans. |
| `ai_cmd` | Local (`.local.rnex.yaml`) | `string` | `""` | Command template for semantic tasks. If unset, operates in prompt-only mode. |
| `notify_on_changes` | Local (`.local.rnex.yaml`) | `boolean` | `true` | Terminal alerts printed right after git commit/push when `/raw/` or wiki needs attention. |

---

## Everyday Operation & Cadence

1. **Intake:** Drop raw research papers, meeting notes, PRDs, or architecture specs into `/raw/` unmodified.
2. **Ingest:** Instruct your AI assistant: *"Run wiki-ingest on raw/source-document.md"*.
3. **Maintenance:** Run the `wiki-lint` workflow to validate relations, prune orphans, and update `mentioned_in` links.

---

## Disabling

```bash
rnex plugin disable karpathy-llm
```

Safely unlinks plugin assets from member repositories and removes the entry from `rnex.yaml`. Your curated `/wiki/` and `/raw/` data remain completely untouched on disk.
