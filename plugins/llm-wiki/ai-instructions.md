# LLM Wiki AI Instructions

## 1. B-Tree Wiki Retrieval Protocol

1. **Step 1 — B-Tree Root Index**: Read `<wiki_dir>/<index_file>` (configured via `plugins.llm-wiki.wiki_dir` and `plugins.llm-wiki.index_file`, default: `.rnex/wiki/index.md`) to identify the relevant shard.
2. **Step 2 — Leaf Shard & Source Access**: Read only the specific B-Tree leaf shard identified in Step 1 (e.g., `<wiki_dir>/repo-nexus*.md` or `<wiki_dir>/repos-<member>*.md`) and open only authoritative source documents referenced in that shard.

## 2. Maintenance & Operations

- **Zero Ad-Hoc Edits**: Never edit `<wiki_dir>/` shards manually or create ad-hoc files inside the wiki directory.
- **Ingestion**: Run `rnex plugin llm-wiki ingest` (or shorthand `rnex plugin ingest`) to index missing sources from `plugins.llm-wiki.sources`.
- **Linting & Auto-Healing**: Run `rnex plugin llm-wiki lint` (or shorthand `rnex plugin lint`) to validate shard bounds, cross-references, and alphabetical sorting.
- **Agent Skills**: Load skills from `.rnex/plugins/llm-wiki/skills/` (`ingest.md`, `lint.md`) only when performing corresponding wiki tasks.
