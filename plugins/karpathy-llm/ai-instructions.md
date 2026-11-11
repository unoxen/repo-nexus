# Karpathy LLM AI Instructions

## 1. B-Tree Wiki Retrieval Protocol

1. **Step 1 — B-Tree Root Index**: Read `.rnex/wiki/index.md` to identify the relevant shard.
2. **Step 2 — Leaf Shard & Source Access**: Read only the specific B-Tree leaf shard identified in Step 1 (e.g., `.rnex/wiki/repo-nexus.md` or `.rnex/wiki/repos-<member>.md`) and open only authoritative source documents referenced in that shard.

## 2. Maintenance & Operations

- **Zero Ad-Hoc Edits**: Never edit `.rnex/wiki/` shards manually or create ad-hoc files inside the wiki directory.
- **Ingestion**: Run `rnex plugin karpathy-llm ingest` (or shorthand `rnex plugin ingest`) to index missing sources or update documentation.
- **Linting & Auto-Healing**: Run `rnex plugin karpathy-llm lint` (or shorthand `rnex plugin lint`) to validate shard bounds, cross-references, and alphabetical sorting.
- **Agent Skills**: Load skills from `.rnex/plugins/karpathy-llm/skills/` (`wiki-ingest.md`, `wiki-lint.md`) only when performing corresponding wiki tasks.
