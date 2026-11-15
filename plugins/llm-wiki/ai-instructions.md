# LLM Wiki AI Instructions

## 1. B-Tree Wiki Retrieval Protocol

1. **Step 1 — B-Tree Root Index**: Read `{wikiDir}/{indexFile}` to identify the relevant shard.
2. **Step 2 — Leaf Shard & Source Access**: Read only the specific B-Tree leaf shard identified in Step 1 (`{wikiDir}/repo-nexus*.md` or `{wikiDir}/repos-*.md`) and open only authoritative source documents referenced in that shard.

## 2. Maintenance & Operations

- **Zero Ad-Hoc Edits**: Never edit `{wikiDir}/` shards manually or create ad-hoc files inside `{wikiDir}/`.
- **Ingestion**: Run `rnex plugin llm-wiki ingest` (or shorthand `rnex plugin ingest`) to index missing sources from {sources} into `{wikiDir}/`.
- **Linting & Auto-Healing**: Run `rnex plugin llm-wiki lint` (or shorthand `rnex plugin lint`) to validate shard bounds (root router limit: {btreeRootMaxLines} lines; shard entry limit: {btreeShardMaxEntries} entries), cross-references, and alphabetical sorting inside `{wikiDir}/`.
- **Audit Log**: Maintenance records are tracked in `{wikiDir}/{logFile}` (bounded to {logMaxRecords} records).
- **Agent Skills**: Load `.rnex/plugins/llm-wiki/skills/ingest.md` or `.rnex/plugins/llm-wiki/skills/lint.md` only when performing corresponding wiki tasks.
