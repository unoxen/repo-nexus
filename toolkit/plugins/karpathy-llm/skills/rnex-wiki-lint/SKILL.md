---
name: rnex-wiki-lint
description: Autonomous link validation, backlink recalculation, and graph repair for Karpathy LLM Wiki.
---

# Karpathy LLM Wiki Lint Skill

Use this skill when auditing and maintaining knowledge graph integrity across the curated wiki directory (configured via `plugins.karpathy-llm.wiki_dir` in `rnex.yaml`, default: `wiki/`).

## Key Steps
- Resolve `wiki_dir` (default: `wiki`) and `raw_dir` (default: `raw`) from `rnex.yaml` / `.local.rnex.yaml`.
- Validate all relation filepaths exist under `<wiki_dir>/` and `<raw_dir>/`.
- Recalculate and update `mentioned_in` backlinks.
- Check for orphan pages and update `<wiki_dir>/index.md`.
- Flag contradictions and record maintenance in `<wiki_dir>/_log.md`.
