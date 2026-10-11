---
name: rnex-wiki-ingest
description: Autonomous ingestion and atomic decomposition of raw sources into Karpathy LLM Wiki pages.
---

# Karpathy LLM Wiki Ingestion Skill

Use this skill when decomposing raw documents, research notes, meeting logs, or external articles from the raw intake directory (configured via `plugins.karpathy-llm.raw_dir` in `rnex.yaml`, default: `raw/`) into atomic wiki pages under the curated wiki directory (`plugins.karpathy-llm.wiki_dir`, default: `wiki/`).

## Key Rules
- Resolve `raw_dir` (default: `raw`) and `wiki_dir` (default: `wiki`) from `rnex.yaml` / `.local.rnex.yaml`.
- Source documents stay untouched in `<raw_dir>/`.
- Produce 5–25 atomic pages per document (never lump into one large file).
- Include YAML frontmatter with typed relations (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`).
- Record completed ingestion in `<wiki_dir>/_log.md` and update `<wiki_dir>/index.md`.
