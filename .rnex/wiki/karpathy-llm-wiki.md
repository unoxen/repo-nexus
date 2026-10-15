---
title: "Karpathy LLM Wiki Knowledge Architecture"
tags: [wiki, karpathy, knowledge-base, relations, hot-cache]
last_updated: 2026-10-15
sources: ["docs/plugins/karpathy-llm.md", "toolkit/plugins/karpathy-llm/instructions/rnex-wiki-architecture.md"]
related: ["context-engineering.md", "plugin-system.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# Karpathy LLM Wiki Knowledge Architecture

## Summary
The Karpathy LLM Wiki is a persistent, compounding knowledge base optimized for AI agents. Raw source material is decomposed into atomic markdown files that agents navigate by reading indexes and following typed frontmatter relations.

## Key Facts & Insights
* **Bounded Hot Cache (`hot.md`):** Strict ~500-word ceiling providing instant agent orientation across three structured sections: Architecture & Repo Map, Current Focus, and Key Contracts.
* **Master Navigation Index (`index.md`):** Master catalog containing 1-line annotated links for every atomic page, enabling direct targeted reading without exploratory scanning.
* **Typed Frontmatter Relations:** Every page maintains relational graph fields (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`). The relation graph lives in frontmatter rather than body text.
* **Lifecycle Workflows:**
  - `rnex-wiki-ingest`: Decomposes raw intake documents from `<raw_dir>/` into 5–25 atomic pages.
  - `rnex-wiki-lint`: Audits relation paths, recomputes bidirectional `mentioned_in` backlinks, detects orphan pages, and rebuilds the index.
* **Audit Trail (`_log.md`):** Append-only log recording every ingest and maintenance operation.

## Contextual Links
* See [Context Engineering](./context-engineering.md) for agent routing standards.
* See [Plugin Architecture](./plugin-system.md) for plugin hooks and triggers.
