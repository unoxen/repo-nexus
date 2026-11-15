# LLM Wiki AI Instructions

## 1. B-Tree Wiki Retrieval Protocol

1. **Step 1 — B-Tree Root Index**: Read `{wiki_dir}/{index_file}` to identify the relevant shard.
2. **Step 2 — Leaf Shard & Source Access**: Read only the specific B-Tree leaf shard identified in Step 1 (`{wiki_dir}/repo-nexus*.md` or `{wiki_dir}/repos-*.md`) and open only authoritative source documents referenced in that shard.

## 2. Maintenance & Operations

- **Zero Ad-Hoc Edits**: Never edit `{wiki_dir}/` shards manually or create ad-hoc files inside `{wiki_dir}/`.
- **Ingestion**: Run `rnex plugin llm-wiki ingest` (or shorthand `rnex plugin ingest`) to index missing sources from {sources} into `{wiki_dir}/`.
- **Linting & Auto-Healing**: Run `rnex plugin llm-wiki lint` (or shorthand `rnex plugin lint`) to validate shard bounds (root router limit: {btree_root_max_lines} lines; shard entry limit: {btree_shard_max_entries} entries), cross-references, and alphabetical sorting inside `{wiki_dir}/`.
- **Audit Log**: Maintenance records are tracked in `{wiki_dir}/{log_file}` (bounded to {log_max_records} records).
- **Agent Skills**: Load `.rnex/plugins/llm-wiki/skills/ingest.md` or `.rnex/plugins/llm-wiki/skills/lint.md` only when performing corresponding wiki tasks.
