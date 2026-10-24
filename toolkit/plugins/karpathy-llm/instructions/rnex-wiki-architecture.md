# Karpathy LLM Wiki Knowledge Architecture

> "A persistent, compounding knowledge base optimized for AI agents." — Andrej Karpathy

This instruction document defines the operational rules, intake lifecycle, and typed relation schema for the Karpathy LLM Wiki.

The curated wiki directory (`wiki_dir`, default: `wiki`) and intake sources (`sources` list, default: `["docs", "repos/**/README.md"]`) are configured in `rnex.yaml` (or overridden locally in `.local.rnex.yaml`) under `plugins.karpathy-llm` (with legacy `raw_dir` supported as a fallback). AI assistants must resolve these paths from configuration before reading or writing wiki files.

---

## Mandatory Wiki-First Access Gate (Pre-Task Execution)

Before inspecting, searching, or modifying code inside member repositories (`repos/`), AI assistants MUST execute this sequence:

1. **Orientation Gate (`<wiki_dir>/hot.md`)**:
   - Always read `<wiki_dir>/hot.md` (default: `wiki/hot.md`) first to absorb architectural topology, member repo boundaries, and current focus.
   - Do NOT access `repos/` until this high-level orientation is completed.
2. **Catalog & Topic Lookup (`<wiki_dir>/index.md`)**:
   - If the specific domain concept, API contract, or component required for the task is not resolved in `hot.md`, read `<wiki_dir>/index.md` (default: `wiki/index.md`).
   - Identify and read the specific atomic wiki page(s) (e.g. `<wiki_dir>/auth.md`) corresponding to the task.
3. **Targeted Member Repository Access Only**:
   - Only after acquiring domain context and contract specifications from the wiki should you inspect targeted files within `repos/<name>/`. Never execute blind repository-wide grep or unbounded directory scans across `repos/`.

---

## 1. Operating Rules & Token Economy

When working in a workspace with an active Karpathy LLM Wiki:

- **Configuration Resolution**: Read `rnex.yaml` / `.local.rnex.yaml` to identify the active `sources` list (default: `["docs", "repos/**/README.md"]`; legacy `raw_dir` fallback) and `wiki_dir` (default: `wiki`).
- **Read-Only Input Directives**: Intake sources and `./repos/` are strictly read-only inputs during wiki operations. Never create, copy, or modify files inside configured sources; write generated output exclusively inside `wiki_dir` (`wiki/`).
- **Intake**: All source material (articles, transcripts, docs, notes) is resolved from the configured `sources` list (directories and recursive globs) unmodified, and member repository READMEs exist under `./repos/<name>/README.md`. Sources are read directly in-place without staging copies. Never write directly to `<wiki_dir>/` without ingesting.
- **Orientation (Hot-Cache First)**: Read `<wiki_dir>/hot.md` (default: `wiki/hot.md`) for quick ~500-word orientation. Consult `<wiki_dir>/index.md` (default: `wiki/index.md`) on demand only if the specific topic or contract is not covered in `hot.md`.
- **Bounded Hot Cache**: `<wiki_dir>/hot.md` enforces a strict ~500-word ceiling with 3 structured sections: 1. Architecture & Repo Map, 2. Current Focus & Recent Ingests, 3. Key Contracts. Ingest and lint workflows must condense older context to prevent bloat.
- **Behavioral Principles**: Strictly adhere to the coding agent principles defined at `.rnex/plugins/karpathy-llm/rules/behavioral.md`.
- **Annotated Indexing**: `<wiki_dir>/index.md` entries must maintain a single 1-line summary next to each atomic page link (e.g. `- [Auth Flow](auth.md): JWT validation and token rotation`) so agents pinpoint target pages in a single read without trial-and-error scanning.
- **Ingestion**: When files appear in configured `sources` or member repositories are added, execute the `wiki-ingest` agentic skill protocol (`.rnex/plugins/karpathy-llm/skills/wiki-ingest.md`). One source document produces 5–25 atomic pages — never collapse a source into a single file.
- **Maintenance**: Execute the `wiki-lint` agentic skill protocol (`.rnex/plugins/karpathy-llm/skills/wiki-lint.md`) to validate paths, update `mentioned_in`, and preserve graph integrity.

---

## 2. Typed Frontmatter Relation Schema

Every page in `<wiki_dir>/` must maintain typed frontmatter relations:

```yaml
---
title: ""
tags: []
last_updated: YYYY-MM-DD
# Typed relation fields — paths relative to <wiki_dir>/ (or workspace root for raw sources)
sources: []          # intake files (<source_path> or repos/<name>/README.md) this page was derived from
related: []          # thematically related wiki pages
extends: []          # pages this one builds upon or specialises
contradicts: []      # pages with conflicting information
mentioned_in: []     # pages that link to this one (maintained by lint)
---
```

**Body Structure:**
- Concise summary of the concept.
- Key facts, definitions, or insights.
- Inline standard Markdown links (`[Label](./path.md)`) where contextually useful in prose.

The relation graph lives in frontmatter, not in prose links. Agents traverse the graph by reading frontmatter fields, not by scanning body text.
