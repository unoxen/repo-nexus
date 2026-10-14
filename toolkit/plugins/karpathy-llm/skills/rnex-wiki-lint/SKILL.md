---
name: rnex-wiki-lint
description: Autonomous link validation, backlink recalculation, and graph repair for Karpathy LLM Wiki.
---

# Karpathy LLM Wiki Lint Skill

Use this skill when auditing and maintaining knowledge graph integrity across the curated wiki directory (configured via `plugins.karpathy-llm.wiki_dir` in `rnex.yaml`, default: `.rnex/wiki`).

## Key Steps
- Resolve `wiki_dir` (default: `.rnex/wiki`) and `raw_dir` (default: `./docs`) from `rnex.yaml` / `.local.rnex.yaml`.
- Validate all relation filepaths exist under `<wiki_dir>/` and `<raw_dir>/`.
- Recalculate and update `mentioned_in` backlinks.
- Check for orphan pages and update `<wiki_dir>/index.md` (default: `.rnex/wiki/index.md`).
- Flag contradictions and record maintenance in `<wiki_dir>/_log.md` (default: `.rnex/wiki/_log.md`).
