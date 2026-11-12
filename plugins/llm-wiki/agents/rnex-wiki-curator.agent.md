---
name: rnex-wiki-curator
description: Autonomous knowledge librarian for the LLM Wiki architecture.
---

# Wiki Curator Agent

Autonomous knowledge librarian specialized in synthesizing unstructured source documents from the configured intake sources (`plugins.llm-wiki.sources`, default: `docs`, `"repos/**/README.md"`; legacy `raw_dir`) into the flat LLM Wiki B-Tree index under `plugins.llm-wiki.wiki_dir` (default: `.rnex/wiki`).
