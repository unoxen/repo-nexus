# Karpathy LLM Wiki Knowledge Architecture

> "A persistent, compounding knowledge base optimized for AI agents." — Andrej Karpathy

This instruction document defines the operational rules, intake lifecycle, and typed relation schema for the Karpathy LLM Wiki.

The curated wiki directory (`wiki_dir`, default: `wiki/`) and raw intake directory (`raw_dir`, default: `raw/`) are configured in `rnex.yaml` (or overridden locally in `.local.rnex.yaml`) under `plugins.karpathy-llm`. AI assistants must resolve these directories from configuration before reading or writing wiki files.

---

## 1. Operating Rules

When working in a workspace with an active Karpathy LLM Wiki:

- **Configuration Resolution**: Read `rnex.yaml` / `.local.rnex.yaml` to identify the active `raw_dir` (default: `raw`) and `wiki_dir` (default: `wiki`).
- **Intake**: All source material (articles, transcripts, docs, notes) goes to `<raw_dir>/` unmodified. Never write directly to `<wiki_dir>/` without ingesting.
- **Orientation**: Before answering domain questions, read `<wiki_dir>/index.md` to find relevant pages, then read only those pages. If `<wiki_dir>/hot.md` exists, read it first as a quick-orient step.
- **Ingestion**: When files appear in `<raw_dir>/`, run the `rnex-wiki-ingest` workflow (`.rnex/plugins/karpathy-llm/workflows/rnex-wiki-ingest.md`). One source document typically produces many atomic pages (commonly 5–25 pages) — do not collapse a source into a single file.
- **Maintenance**: Run the `rnex-wiki-lint` workflow (`.rnex/plugins/karpathy-llm/workflows/rnex-wiki-lint.md`) to validate paths, update `mentioned_in`, and preserve graph integrity.

---

## 2. Typed Frontmatter Relation Schema

Every page in `<wiki_dir>/` must maintain typed frontmatter relations:

```yaml
---
title: ""
tags: []
last_updated: YYYY-MM-DD
# Typed relation fields — paths relative to <wiki_dir>/ (or workspace root for raw sources)
sources: []          # <raw_dir>/ files this page was derived from
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
