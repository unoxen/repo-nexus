# Karpathy LLM Wiki Knowledge Architecture

> "A persistent, compounding knowledge base optimized for AI agents." — Andrej Karpathy

This instruction document defines the operational rules, intake lifecycle, and typed relation schema for the Karpathy LLM Wiki.

The curated wiki directory (`wiki_dir`, default: `.rnex/wiki`) and raw intake directory (`raw_dir`, default: `./docs`) are configured in `rnex.yaml` (or overridden locally in `.local.rnex.yaml`) under `plugins.karpathy-llm`. AI assistants must resolve these directories from configuration before reading or writing wiki files.

---

## 1. Operating Rules & Token Economy

When working in a workspace with an active Karpathy LLM Wiki:

- **Configuration Resolution**: Read `rnex.yaml` / `.local.rnex.yaml` to identify the active `raw_dir` (default: `./docs`) and `wiki_dir` (default: `.rnex/wiki`).
- **Read-Only Input Directives**: `raw_dir` (`./docs`) and `./repos/` are strictly read-only inputs during wiki operations. Never create, copy, or modify files inside `./docs`; write generated output exclusively inside `wiki_dir` (`.rnex/wiki/`).
- **Intake**: All source material (articles, transcripts, docs, notes) goes to `<raw_dir>/` (default: `./docs`) unmodified, and member repository READMEs exist under `./repos/<name>/README.md`. Sources are read directly in-place without staging copies. Never write directly to `<wiki_dir>/` without ingesting.
- **Orientation (Hot-Cache First)**: Read `<wiki_dir>/hot.md` (default: `.rnex/wiki/hot.md`) for quick ~500-word orientation. Consult `<wiki_dir>/index.md` (default: `.rnex/wiki/index.md`) on demand only if the specific topic or contract is not covered in `hot.md`.
- **Bounded Hot Cache**: `<wiki_dir>/hot.md` enforces a strict ~500-word ceiling with 3 structured sections: 1. Architecture & Repo Map, 2. Current Focus & Recent Ingests, 3. Key Contracts. Ingest and lint workflows must condense older context to prevent bloat.
- **Behavioral Principles**: Strictly adhere to the coding agent principles defined at `.rnex/plugins/karpathy-llm/rules/behavioral.md`.
- **Ingestion**: When files appear in `<raw_dir>/` or when member repos are added, execute the `wiki-ingest` agentic skill protocol (`.rnex/plugins/karpathy-llm/skills/wiki-ingest.md`). One source document produces 5–25 atomic pages — never collapse a source into a single file.
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
